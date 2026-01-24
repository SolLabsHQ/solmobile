//
//  AppleIntelligenceObserver.swift
//  SolMobile
//

import Foundation

enum AppleIntelligenceSettings {
    static let enabledKey = "sol.apple_intelligence.enabled"
    static let minIntervalSeconds: TimeInterval = 30

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }
}

final class AppleIntelligenceObserver {
    static let shared = AppleIntelligenceObserver()

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var lastObservationAt: Date?

    private init() {}

    func observeMessage(_ message: Message) {
        guard AppleIntelligenceSettings.isEnabled else { return }
        guard Self.isAvailable else { return }
        guard !message.isGhostCard else { return }
        guard let messageId = message.resolvedServerMessageId else { return }

        let now = Date()
        if let last = lastObservationAt,
           now.timeIntervalSince(last) < AppleIntelligenceSettings.minIntervalSeconds {
            return
        }

        guard let signal = resolveSignal(for: message) else { return }
        guard signal.confidence > 0, signal.intensity > 0 else { return }
        lastObservationAt = now

        let observation = DeviceMuseObservation(
            observationId: UUID().uuidString,
            ts: Self.timestampFormatter.string(from: Date()),
            localUserUuid: LocalIdentity.localUserUuid(),
            threadId: message.thread.id.uuidString,
            messageId: messageId,
            version: "device-muse-observation-v0.1",
            source: .appleIntelligence,
            detectedType: signal.detectedType,
            intensity: signal.intensity,
            confidence: signal.confidence,
            phaseHint: signal.phaseHint
        )

        let request = TraceEventsRequest(
            requestId: UUID().uuidString,
            localUserUuid: observation.localUserUuid,
            events: [.deviceMuseObservation(observation)]
        )

        Task {
            try? await SolServerClient().postTraceEvents(request: request)
        }
    }

    private static var isAvailable: Bool {
        if #available(iOS 18.0, *) {
            return true
        }
        return false
    }

    private struct ObservationSignal {
        let detectedType: String
        let intensity: Double
        let confidence: Double
        let phaseHint: DeviceMusePhaseHint?
    }

    private func resolveSignal(for message: Message) -> ObservationSignal? {
        _ = message
        return nil
    }
}
