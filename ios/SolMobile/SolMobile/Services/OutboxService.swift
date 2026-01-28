//
//  OutboxService.swift
//  SolMobile
//
//  Created by SolMobile Outbox.
//

import Foundation
import Network
import os
import SwiftData
import UIKit

@MainActor
final class OutboxService {
    private let outboxLog = Logger(subsystem: "com.sollabshq.solmobile", category: "OutboxService")

    private let container: ModelContainer
    private let transport: any ChatTransport
    private let statusWatcher: TransmissionStatusWatcher?
    private let worker: OutboxWorkerActor

    private var isProcessing: Bool = false
    private var needsRerun: Bool = false
    private var isStarted: Bool = false
    private var timerTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var notificationTokens: [NSObjectProtocol] = []

    private let pollLimit: Int = 3
    private let tickSeconds: TimeInterval = 5
    private enum RunReason: String {
        case start
        case enqueue
        case retry
        case timer
        case reachability
        case bgRefresh = "bg_refresh"
        case willResignActive = "will_resign_active"
        case didBecomeActive = "did_become_active"
        case rerun

        var pollFirst: Bool {
            switch self {
            case .enqueue, .retry, .bgRefresh, .willResignActive:
                return false
            case .start, .timer, .reachability, .didBecomeActive, .rerun:
                return true
            }
        }
    }

    init(
        container: ModelContainer,
        transport: (any ChatTransport)? = nil,
        statusWatcher: TransmissionStatusWatcher? = nil
    ) {
        self.container = container
        let resolvedTransport = transport ?? SolServerClient()
        self.transport = resolvedTransport
        if let statusWatcher {
            self.statusWatcher = statusWatcher
        } else if let polling = resolvedTransport as? any ChatTransportPolling {
            self.statusWatcher = PollingTransmissionStatusWatcher(transport: polling)
        } else {
            self.statusWatcher = nil
        }
        self.worker = OutboxWorkerActor(
            container: container,
            transport: resolvedTransport,
            statusWatcher: self.statusWatcher
        )
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        startReachability()
        startTimer()
        registerAppLifecycle()

        kick(reason: .start, useBackgroundTask: false)
    }

    func enqueueChat(thread: ConversationThread, userMessage: Message) {
        let shouldFail = userMessage.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("/fail")

        let threadId = thread.id
        let messageId = userMessage.id
        let messageText = userMessage.text

        Task { [weak self] in
            guard let self else { return }
            await self.worker.enqueueChat(
                threadId: threadId,
                messageId: messageId,
                messageText: messageText,
                shouldFail: shouldFail
            )
            await MainActor.run {
                self.kick(reason: .enqueue, useBackgroundTask: true)
            }
        }
    }

    func enqueueMemoryDistill(threadId: UUID, messageIds: [UUID], payload: MemoryDistillRequest) {
        Task { [weak self] in
            guard let self else { return }
            await self.worker.enqueueMemoryDistill(
                threadId: threadId,
                messageIds: messageIds,
                payload: payload
            )
            await MainActor.run {
                self.kick(reason: .enqueue, useBackgroundTask: true)
            }
        }
    }
    func retryFailed() {
        Task { [weak self] in
            guard let self else { return }
            await self.worker.retryFailed()
            await MainActor.run {
                self.kick(reason: .retry, useBackgroundTask: true)
            }
        }
    }

    func handleSSETransmissionUpdate(transmissionId: String, reason: String) {
        outboxLog.info("sse event=transmission_update tx=\(transmissionId, privacy: .public) reason=\(reason, privacy: .public)")
        Task { [weak self] in
            guard let self else { return }
            await self.worker.pollTransmission(serverTransmissionId: transmissionId, reason: reason)
        }
    }

    func runBackgroundRefresh() async {
        await runOnce(reason: .bgRefresh, useBackgroundTask: false)
    }

    private func registerAppLifecycle() {
        let center = NotificationCenter.default

        let resignToken = center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.kick(reason: .willResignActive, useBackgroundTask: true)
            }
        }

        let activeToken = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.kick(reason: .didBecomeActive, useBackgroundTask: false)
            }
        }

        notificationTokens.append(resignToken)
        notificationTokens.append(activeToken)
    }

    private func startReachability() {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.sollabshq.solmobile.outbox.reachability")
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                self?.kick(reason: .reachability, useBackgroundTask: false)
            }
        }
        monitor.start(queue: queue)
        pathMonitor = monitor
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.tickSeconds * 1_000_000_000))
                self.kick(reason: .timer, useBackgroundTask: false)
            }
        }
    }

    private func kick(reason: RunReason, useBackgroundTask: Bool) {
        outboxLog.info("kick reason=\(reason.rawValue, privacy: .public) processing=\(self.isProcessing, privacy: .public)")

        guard !isProcessing else {
            needsRerun = true
            return
        }

        isProcessing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runOnce(reason: reason, useBackgroundTask: useBackgroundTask)

            self.isProcessing = false
            if self.needsRerun {
                self.needsRerun = false
                self.kick(reason: .rerun, useBackgroundTask: false)
            }
        }
    }

    private func runOnce(reason: RunReason, useBackgroundTask: Bool) async {
        outboxLog.info("run_once reason=\(reason.rawValue, privacy: .public)")

        let work: () async -> Void = {
            await self.worker.processQueue(pollLimit: self.pollLimit, pollFirst: reason.pollFirst)
        }

        if useBackgroundTask {
            await withBackgroundTask(name: "OutboxSend", operation: work)
        } else {
            await work()
        }
    }

    private func withBackgroundTask(
        name: String,
        operation: @escaping () async -> Void
    ) async {
        var taskId: UIBackgroundTaskIdentifier = .invalid
        taskId = UIApplication.shared.beginBackgroundTask(withName: name) {
            if taskId != .invalid {
                UIApplication.shared.endBackgroundTask(taskId)
                taskId = .invalid
            }
        }

        await operation()

        if taskId != .invalid {
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }
}
