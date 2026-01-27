//
//  AppleIntelligenceObserver.swift
//  SolMobile
//

import Foundation
import SwiftData
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

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

    private static let log = Logger(subsystem: "com.sollabshq.solmobile", category: "AppleIntelligenceObserver")

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let maxRetryAttempts = 20
    private let maxRetryWindowSeconds: TimeInterval = 10
    private let retryDelaySeconds: TimeInterval = 0.5
    private let maxObservedIds = 500

    private var lastObservationAtByThread: [String: Date] = [:]
    private var retryAttemptsByMessageId: [UUID: Int] = [:]
    private var retryStartByMessageId: [UUID: Date] = [:]
    private var pendingMessageIds = Set<UUID>()
    private var observedMessageIds = Set<String>()
    private var observedMessageIdOrder: [String] = []

    private init() {}

    @MainActor
    func observeMessage(_ message: Message) {
        let snapshot = MessageSnapshot(
            id: message.id,
            threadId: message.thread.id.uuidString,
            text: message.text,
            isGhostCard: message.isGhostCard,
            serverMessageId: message.resolvedServerMessageId
        )
        observeSnapshot(snapshot)
    }

    @MainActor
    private func observeSnapshot(_ snapshot: MessageSnapshot) {
        guard AppleIntelligenceSettings.isEnabled else {
            Self.log.debug("apple_intel_skip reason=disabled")
            clearRetryStateIfNeeded(for: snapshot.id)
            return
        }
        guard Self.isAvailable else {
            Self.log.debug("apple_intel_skip availability=unavailable reason=os_version_gate osVersion=\(Self.osVersionString(), privacy: .public)")
            return
        }
        guard !snapshot.isGhostCard else {
            Self.log.debug("apple_intel_skip reason=ghost_card threadId=\(snapshot.threadId, privacy: .public)")
            return
        }
        guard let serverMessageId = snapshot.serverMessageId, !serverMessageId.isEmpty else {
            Self.log.debug("apple_intel_retry reason=missing_server_message_id messageId=\(snapshot.id.uuidString, privacy: .public)")
            scheduleRetry(for: snapshot.id)
            return
        }
        if observedMessageIds.contains(serverMessageId) {
            Self.log.debug("apple_intel_skip reason=already_observed messageId=\(serverMessageId, privacy: .public)")
            return
        }

        let now = Date()
        if let last = lastObservationAtByThread[snapshot.threadId],
           now.timeIntervalSince(last) < AppleIntelligenceSettings.minIntervalSeconds {
            Self.log.debug("apple_intel_skip reason=throttled threadId=\(snapshot.threadId, privacy: .public)")
            return
        }

        Task.detached { [snapshot] in
            let signal = await Self.resolveSignal(for: snapshot)
            await MainActor.run {
                guard AppleIntelligenceSettings.isEnabled else {
                    Self.log.debug("apple_intel_skip reason=disabled_post_resolve")
                    AppleIntelligenceObserver.shared.clearRetryStateIfNeeded(for: snapshot.id)
                    return
                }
                guard let serverMessageId = snapshot.serverMessageId, !serverMessageId.isEmpty else {
                    Self.log.debug("apple_intel_skip reason=missing_server_message_id_post_resolve messageId=\(snapshot.id.uuidString, privacy: .public)")
                    return
                }
                if AppleIntelligenceObserver.shared.observedMessageIds.contains(serverMessageId) {
                    Self.log.debug("apple_intel_skip reason=already_observed_post_resolve messageId=\(serverMessageId, privacy: .public)")
                    return
                }
                guard let signal else {
                    Self.log.debug("apple_intel_skip reason=signal_nil threadId=\(snapshot.threadId, privacy: .public) messageId=\(serverMessageId, privacy: .public)")
                    return
                }
                guard signal.confidence > 0, signal.intensity > 0 else {
                    Self.log.debug("apple_intel_skip reason=signal_invalid threadId=\(snapshot.threadId, privacy: .public) messageId=\(serverMessageId, privacy: .public)")
                    return
                }

                AppleIntelligenceObserver.shared.lastObservationAtByThread[snapshot.threadId] = now
                AppleIntelligenceObserver.shared.rememberObserved(messageId: serverMessageId)

                let intensityStr = String(format: "%.2f", signal.intensity)
                let confidenceStr = String(format: "%.2f", signal.confidence)
                let phaseHint = signal.phaseHint?.rawValue ?? "none"
                Self.log.info("apple_intel_signal detectedType=\(signal.detectedType, privacy: .public) intensity=\(intensityStr, privacy: .public) confidence=\(confidenceStr, privacy: .public) phaseHint=\(phaseHint, privacy: .public) threadId=\(snapshot.threadId, privacy: .public) messageId=\(serverMessageId, privacy: .public)")

                let observation = DeviceMuseObservation(
                    observationId: UUID().uuidString,
                    ts: Self.timestampFormatter.string(from: Date()),
                    localUserUuid: LocalIdentity.localUserUuid(),
                    threadId: snapshot.threadId,
                    messageId: serverMessageId,
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
                    do {
                        try await SolServerClient().postTraceEvents(request: request)
                        Self.log.info("apple_intel_trace_posted eventId=\(observation.observationId, privacy: .public) requestId=\(request.requestId, privacy: .public)")
                    } catch {
                        Self.log.debug("apple_intel_trace_failed eventId=\(observation.observationId, privacy: .public) error=\(String(describing: error), privacy: .public)")
                    }
                }
            }
        }
    }

    @MainActor
    private func scheduleRetry(for messageId: UUID) {
        guard AppleIntelligenceSettings.isEnabled else {
            Self.log.debug("apple_intel_retry_stop reason=disabled messageId=\(messageId.uuidString, privacy: .public)")
            clearRetryStateIfNeeded(for: messageId)
            return
        }
        guard !pendingMessageIds.contains(messageId) else { return }
        pendingMessageIds.insert(messageId)
        let attempts = (retryAttemptsByMessageId[messageId] ?? 0) + 1
        retryAttemptsByMessageId[messageId] = attempts
        if retryStartByMessageId[messageId] == nil {
            retryStartByMessageId[messageId] = Date()
        }

        if attempts > maxRetryAttempts {
            Self.log.debug("apple_intel_retry_stop reason=max_attempts messageId=\(messageId.uuidString, privacy: .public)")
            clearRetryStateIfNeeded(for: messageId)
            return
        }

        if let started = retryStartByMessageId[messageId],
           Date().timeIntervalSince(started) > maxRetryWindowSeconds {
            Self.log.debug("apple_intel_retry_stop reason=timeout messageId=\(messageId.uuidString, privacy: .public)")
            clearRetryStateIfNeeded(for: messageId)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelaySeconds) { [weak self] in
            guard let self else { return }
            self.pendingMessageIds.remove(messageId)
            guard AppleIntelligenceSettings.isEnabled else {
                Self.log.debug("apple_intel_retry_stop reason=disabled_after_delay messageId=\(messageId.uuidString, privacy: .public)")
                self.clearRetryStateIfNeeded(for: messageId)
                return
            }
            guard let message = self.fetchMessage(id: messageId) else {
                Self.log.debug("apple_intel_retry_stop reason=message_missing messageId=\(messageId.uuidString, privacy: .public)")
                self.clearRetryStateIfNeeded(for: messageId)
                return
            }
            self.observeMessage(message)
        }
    }

    @MainActor
    private func clearRetryStateIfNeeded(for messageId: UUID) {
        retryAttemptsByMessageId.removeValue(forKey: messageId)
        retryStartByMessageId.removeValue(forKey: messageId)
        pendingMessageIds.remove(messageId)
    }

    @MainActor
    private func rememberObserved(messageId: String) {
        guard !observedMessageIds.contains(messageId) else { return }
        observedMessageIds.insert(messageId)
        observedMessageIdOrder.append(messageId)
        if observedMessageIdOrder.count > maxObservedIds {
            let evicted = observedMessageIdOrder.removeFirst()
            observedMessageIds.remove(evicted)
            Self.log.debug("apple_intel_evicted_observed messageId=\(evicted, privacy: .public)")
        }
    }

    private static var isAvailable: Bool {
        if #available(iOS 26.0, *) {
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

    private struct MessageSnapshot: Sendable {
        let id: UUID
        let threadId: String
        let text: String
        let isGhostCard: Bool
        let serverMessageId: String?
    }

    private static func resolveSignal(for snapshot: MessageSnapshot) async -> ObservationSignal? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            let availability = model.availability
            logAvailability(availability: availability)
            guard case .available = availability else { return nil }

            let session = LanguageModelSession(model: model, instructions: """
            You label the user's current message with a mechanism-only signal.
            Return ONLY the structured fields; no prose, no message text.
            detectedType must be one of: insight, gratitude, overwhelm, resolve, none.
            intensity must be a number between 0 and 1.
            confidence must be a number between 0 and 1.
            phaseHint must be one of: downshift, settled (or omit).
            """)

            do {
                let response = try await session.respond(
                    to: "Message: \(snapshot.text)",
                    generating: AppleIntelligenceSignal.self,
                    includeSchemaInPrompt: true
                )
                return normalize(signal: response.content)
            } catch {
                log.debug("apple_intel_signal_failed error=\(String(describing: error), privacy: .public)")
                return nil
            }
        }
        #endif

        log.debug("apple_intel_signal_unavailable reason=framework_missing osVersion=\(Self.osVersionString(), privacy: .public)")
        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func normalize(signal: AppleIntelligenceSignal) -> ObservationSignal? {
        let rawType = signal.detectedType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let detectedType = ["insight", "gratitude", "overwhelm", "resolve", "none"].contains(rawType) ? rawType : "none"
        let intensity = max(0, min(1, signal.intensity))
        let confidence = max(0, min(1, signal.confidence))
        let phaseHint = DeviceMusePhaseHint(rawValue: signal.phaseHint ?? "")

        if detectedType == "none" {
            return nil
        }

        return ObservationSignal(
            detectedType: detectedType,
            intensity: intensity,
            confidence: confidence,
            phaseHint: phaseHint
        )
    }

    @available(iOS 26.0, *)
    private static func logAvailability(availability: SystemLanguageModel.Availability) {
        let osVersion = Self.osVersionString()
        switch availability {
        case .available:
            log.info("apple_intel_availability availability=available osVersion=\(osVersion, privacy: .public)")
        case .unavailable(let reason):
            log.info("apple_intel_availability availability=unavailable reason=\(String(describing: reason), privacy: .public) osVersion=\(osVersion, privacy: .public)")
        }
    }
    #endif

    private static func osVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }

    @MainActor
    private func fetchMessage(id: UUID) -> Message? {
        let container = ModelContainerFactory.shared
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct AppleIntelligenceSignal {
    var detectedType: String
    var intensity: Double
    var confidence: Double
    var phaseHint: String?
}
#endif
