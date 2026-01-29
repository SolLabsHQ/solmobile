//
//  SSEService.swift
//  SolMobile
//
//  Created by SolMobile SSE.
//

import Foundation
import UIKit

@MainActor
final class SSEService {
    static let shared = SSEService()

    private let dispatcher: SSEDispatcher
    private let client: SSEClientProtocol
    private weak var outboxService: OutboxService?
    private var started: Bool = false
    private var notificationTokens: [NSObjectProtocol] = []

    private init() {
        dispatcher = SSEDispatcher()
        client = LaunchDarklyEventSourceClient(dispatcher: dispatcher)
    }

    func bind(outboxService: OutboxService) {
        self.outboxService = outboxService
        dispatcher.onTransmissionAccepted = { _ in
            // UI state derives from SSEStatusStore; no additional action needed.
        }
        dispatcher.onTransmissionStarted = { _ in
            // UI state derives from SSEStatusStore; no additional action needed.
        }
        dispatcher.onTransmissionReady = { [weak outboxService] txId in
            outboxService?.handleSSETransmissionUpdate(transmissionId: txId, reason: "assistant_final_ready")
        }
        dispatcher.onTransmissionFailed = { [weak outboxService] txId in
            outboxService?.handleSSETransmissionUpdate(transmissionId: txId, reason: "assistant_failed")
        }
    }

    func start() {
        guard !started else { return }
        started = true
        registerAppLifecycle()
        client.connect()
    }

    func stop() {
        guard started else { return }
        started = false
        unregisterAppLifecycle()
        client.disconnect()
    }

    func refreshConnection() {
        if !started {
            started = true
            registerAppLifecycle()
        }
        client.reconnect()
    }

    private func registerAppLifecycle() {
        guard notificationTokens.isEmpty else { return }
        let center = NotificationCenter.default

        let resignToken = center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.client.disconnect()
        }

        let activeToken = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.started else { return }
            self.client.connect()
        }

        notificationTokens.append(resignToken)
        notificationTokens.append(activeToken)
    }

    private func unregisterAppLifecycle() {
        let center = NotificationCenter.default
        for token in notificationTokens {
            center.removeObserver(token)
        }
        notificationTokens.removeAll()
    }
}
