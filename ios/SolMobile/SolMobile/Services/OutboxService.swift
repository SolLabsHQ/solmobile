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

    private var isProcessing: Bool = false
    private var needsRerun: Bool = false
    private var isStarted: Bool = false
    private var timerTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var notificationTokens: [NSObjectProtocol] = []

    private let pollLimit: Int = 3
    private let tickSeconds: TimeInterval = 5

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
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        startReachability()
        startTimer()
        registerAppLifecycle()

        kick(reason: "start", useBackgroundTask: false)
    }

    func enqueueChat(thread: ConversationThread, userMessage: Message) {
        let engine = TransmissionActions(
            modelContext: ModelContext(container),
            transport: transport,
            statusWatcher: statusWatcher
        )
        engine.enqueueChat(thread: thread, userMessage: userMessage)
        kick(reason: "enqueue", useBackgroundTask: true)
    }

    func retryFailed() {
        let engine = TransmissionActions(
            modelContext: ModelContext(container),
            transport: transport,
            statusWatcher: statusWatcher
        )
        engine.retryFailed()
        kick(reason: "retry", useBackgroundTask: true)
    }

    func runBackgroundRefresh() async {
        await runOnce(reason: "bg_refresh", useBackgroundTask: false)
    }

    private func registerAppLifecycle() {
        let center = NotificationCenter.default

        let resignToken = center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.kick(reason: "will_resign_active", useBackgroundTask: true)
            }
        }

        let activeToken = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.kick(reason: "did_become_active", useBackgroundTask: false)
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
                self?.kick(reason: "reachability", useBackgroundTask: false)
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
                self.kick(reason: "timer", useBackgroundTask: false)
            }
        }
    }

    private func kick(reason: String, useBackgroundTask: Bool) {
        outboxLog.info("kick reason=\(reason, privacy: .public) processing=\(self.isProcessing, privacy: .public)")

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
                self.kick(reason: "rerun", useBackgroundTask: false)
            }
        }
    }

    private func runOnce(reason: String, useBackgroundTask: Bool) async {
        outboxLog.info("run_once reason=\(reason, privacy: .public)")

        let work: () async -> Void = {
            let engine = TransmissionActions(
                modelContext: ModelContext(self.container),
                transport: self.transport,
                statusWatcher: self.statusWatcher
            )
            await engine.processQueue(pollLimit: self.pollLimit)
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
