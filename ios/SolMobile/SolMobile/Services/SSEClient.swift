//
//  SSEClient.swift
//  SolMobile
//
//  Created by SolMobile SSE.
//

import Foundation
import os
import LDSwiftEventSource

protocol SSEClientProtocol: Sendable {
    func connect()
    func disconnect()
    func reconnect()
}

final class LaunchDarklyEventSourceClient: EventHandler, SSEClientProtocol, @unchecked Sendable {
    private let log = Logger(subsystem: "com.sollabshq.solmobile", category: "SSEClient")

    private let dispatcher: SSEDispatcher
    private let statusStore: SSEStatusStore

    private var eventSource: EventSource?
    private var isActive: Bool = false

    init(dispatcher: SSEDispatcher, statusStore: SSEStatusStore = .shared) {
        self.dispatcher = dispatcher
        self.statusStore = statusStore
    }

    func connect() {
        guard !isActive else { return }
        guard Self.hasAuthToken() || AppEnvironment.current == .dev else {
            Task { @MainActor in
                self.statusStore.markDisconnected()
            }
            return
        }
        guard let url = buildEventsURL() else {
            Task { @MainActor in
                self.statusStore.markDisconnected()
            }
            return
        }

        Task { @MainActor in
            self.statusStore.markConnecting()
        }

        var config = EventSource.Config(handler: self, url: url)
        let baseReconnect = Self.jitteredDelay(1.0, variance: 0.2)
        let maxReconnect = max(baseReconnect, Self.jitteredDelay(30.0, variance: 0.2))
        config.reconnectTime = baseReconnect
        config.maxReconnectTime = maxReconnect
        config.backoffResetThreshold = 60.0
        config.headers = [:]
        config.headerTransform = { _ in
            Self.makeHeaders()
        }

        let source = EventSource(config: config)
        eventSource = source
        isActive = true
        source.start()
    }

    func disconnect() {
        guard isActive else { return }
        isActive = false
        eventSource?.stop()
        eventSource = nil
        Task { @MainActor in
            self.statusStore.markDisconnected()
        }
    }

    func reconnect() {
        disconnect()
        connect()
    }

    // MARK: - EventHandler

    func onOpened() {
        Task { @MainActor in
            self.statusStore.markConnected()
        }
    }

    func onClosed() {
        Task { @MainActor in
            self.statusStore.markDisconnected()
        }
    }

    func onMessage(eventType: String, messageEvent: MessageEvent) {
        Task { @MainActor in
            self.statusStore.markEventReceived()
            self.dispatcher.handle(eventType: eventType, messageEvent: messageEvent)
        }
    }

    func onComment(comment: String) {
        return
    }

    func onError(error: Error) {
        log.debug("sse error: \(String(describing: error), privacy: .public)")
        Task { @MainActor in
            self.statusStore.markDisconnected()
        }
    }

    // MARK: - Helpers

    private func buildEventsURL() -> URL? {
        let baseURL = SolServerBaseURL.effectiveURL()
        return baseURL.appendingPathComponent("/v1/events")
    }

    private static func makeHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        if let token = KeychainStore.read(key: KeychainKeys.stagingApiKey), !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
            headers["x-sol-api-key"] = token
        }
        headers["x-sol-user-id"] = UserIdentity.resolvedId()
        headers["x-sol-local-user-uuid"] = LocalIdentity.localUserUuid()
        return headers
    }

    private static func hasAuthToken() -> Bool {
        guard let token = KeychainStore.read(key: KeychainKeys.stagingApiKey) else { return false }
        return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func jitteredDelay(_ value: TimeInterval, variance: Double) -> TimeInterval {
        let delta = max(0.0, value * variance)
        let lower = max(0.1, value - delta)
        let upper = value + delta
        return Double.random(in: lower...upper)
    }
}
