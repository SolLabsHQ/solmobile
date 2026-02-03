//
//  HapticRouter.swift
//  SolMobile
//

import Foundation
import UIKit
import CoreHaptics

@MainActor
final class HapticRouter {
    static let shared = HapticRouter()

    enum EventKind: String {
        case acceptedTick
        case arrivalPulse
        case terminalFailure
        case ghostArrival
    }

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private let suppressionWindow: TimeInterval = 0.35
    private let storageKey = "sol.haptics.fired.v1"
    private let maxStoredKeys = 500
    private let keyTtlSeconds: TimeInterval = 60 * 60 * 24 * 14

    private var lastArrivalLikeAt: Date?
    private var firedKeys: [String: TimeInterval] = [:]

    private init() {
        loadFiredKeys()
    }

    func tapLight() {
        guard canFireHaptics() else { return }
        impactLight.prepare()
        impactLight.impactOccurred(intensity: 0.7)
    }

    func acceptedTick(idempotencyKey: String?) {
        guard let key = normalizeKey(idempotencyKey, kind: .acceptedTick) else { return }
        fireEvent(key: key, kind: .acceptedTick, arrivalLike: true) { [selection] in
            selection.prepare()
            selection.selectionChanged()
        }
    }

    func arrivalPulseSoft(idempotencyKey: String?) {
        guard let key = normalizeKey(idempotencyKey, kind: .arrivalPulse) else { return }
        fireEvent(key: key, kind: .arrivalPulse, arrivalLike: true) { [impactSoft] in
            impactSoft.prepare()
            impactSoft.impactOccurred()
        }
    }

    func arrivalPulseHeartbeat(idempotencyKey: String?, intensity: Double) {
        guard let key = normalizeKey(idempotencyKey, kind: .arrivalPulse) else { return }
        fireEvent(key: key, kind: .arrivalPulse, arrivalLike: true) { [impactMedium] in
            impactMedium.prepare()
            impactMedium.impactOccurred(intensity: clampIntensity(0.6 * intensity))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                impactMedium.impactOccurred(intensity: clampIntensity(0.9 * intensity))
            }
        }
    }

    func ghostArrival(idempotencyKey: String?, intensity: Double) {
        guard let key = normalizeKey(idempotencyKey, kind: .ghostArrival) else { return }
        fireEvent(key: key, kind: .ghostArrival, arrivalLike: true) { [impactMedium] in
            impactMedium.prepare()
            impactMedium.impactOccurred(intensity: clampIntensity(0.6 * intensity))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                impactMedium.impactOccurred(intensity: clampIntensity(0.9 * intensity))
            }
        }
    }

    func releaseTick() {
        guard canFireHaptics() else { return }
        selection.prepare()
        selection.selectionChanged()
    }

    func selectionTick() {
        guard canFireHaptics() else { return }
        selection.prepare()
        selection.selectionChanged()
    }

    func forgetHeavy() {
        guard canFireHaptics() else { return }
        impactHeavy.prepare()
        impactHeavy.impactOccurred()
    }

    func terminalFailure(idempotencyKey: String?) {
        guard let key = normalizeKey(idempotencyKey, kind: .terminalFailure) else { return }
        fireEvent(key: key, kind: .terminalFailure, arrivalLike: false) { [notification] in
            notification.prepare()
            notification.notificationOccurred(.error)
        }
    }

    private func normalizeKey(_ raw: String?, kind: EventKind) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return "\(kind.rawValue):\(raw)"
    }

    private func canFireHaptics() -> Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private func fireEvent(
        key: String,
        kind: EventKind,
        arrivalLike: Bool,
        action: @escaping () -> Void
    ) {
        guard canFireHaptics() else { return }

        let now = Date()
        pruneKeys(now: now)

        if firedKeys[key] != nil {
            return
        }

        if arrivalLike, let last = lastArrivalLikeAt, now.timeIntervalSince(last) < suppressionWindow {
            return
        }

        firedKeys[key] = now.timeIntervalSince1970
        if arrivalLike {
            lastArrivalLikeAt = now
        }
        persistFiredKeys()
        action()
    }

    private func loadFiredKeys() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else {
            return
        }
        firedKeys = decoded
    }

    private func persistFiredKeys() {
        guard let data = try? JSONEncoder().encode(firedKeys) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func pruneKeys(now: Date) {
        let cutoff = now.timeIntervalSince1970 - keyTtlSeconds
        firedKeys = firedKeys.filter { $0.value >= cutoff }
        if firedKeys.count <= maxStoredKeys {
            return
        }
        let sorted = firedKeys.sorted(by: { $0.value < $1.value })
        let overflow = sorted.count - maxStoredKeys
        guard overflow > 0 else { return }
        for (key, _) in sorted.prefix(overflow) {
            firedKeys.removeValue(forKey: key)
        }
    }
}

private func clampIntensity(_ value: Double) -> Double {
    min(max(value, 0.1), 1.2)
}
