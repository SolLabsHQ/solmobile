//
//  BudgetStore.swift
//  SolMobile
//

import Foundation
import Combine
import os

struct BudgetState: Equatable {
    var isBlocked: Bool
    var blockedUntil: Date?
    var lastUpdatedAt: Date?
}

struct BudgetExceededInfo {
    let blockedUntil: Date?
}

final class BudgetStore: ObservableObject {
    static let shared = BudgetStore()

    private enum Keys {
        static let isBlocked = "solserver.budget.isBlocked"
        static let blockedUntil = "solserver.budget.blockedUntil"
        static let lastUpdatedAt = "solserver.budget.lastUpdatedAt"
    }

    @Published private(set) var state: BudgetState

    private let defaults: UserDefaults
    private let log = Logger(subsystem: "com.sollabshq.solmobile", category: "BudgetStore")
    private let dateParser = ISO8601DateFormatter()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.state = BudgetStore.load(from: defaults)
        refreshIfExpired()
    }

    func refreshIfExpired(now: Date = Date()) {
        guard state.isBlocked, let until = state.blockedUntil, until <= now else { return }
        log.info("budget block expired")
        state = BudgetState(isBlocked: false, blockedUntil: nil, lastUpdatedAt: Date())
        save()
    }

    func isBlockedNow(now: Date = Date()) -> Bool {
        refreshIfExpired(now: now)
        return state.isBlocked
    }

    func applyBudgetExceeded(blockedUntil: Date?) {
        state = BudgetState(isBlocked: true, blockedUntil: blockedUntil, lastUpdatedAt: Date())
        save()
    }

    func reload() {
        state = BudgetStore.load(from: defaults)
        refreshIfExpired()
    }

    func resetForTests() {
        defaults.removeObject(forKey: Keys.isBlocked)
        defaults.removeObject(forKey: Keys.blockedUntil)
        defaults.removeObject(forKey: Keys.lastUpdatedAt)
        reload()
    }

    func parseBudgetExceeded(from errorBody: String) -> BudgetExceededInfo? {
        guard let data = errorBody.data(using: .utf8) else { return nil }
        guard
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = raw["error"] as? String,
            error == "budget_exceeded"
        else {
            return nil
        }

        let blockedUntil = (raw["blocked_until"] as? String) ?? (raw["billing_period_end"] as? String)
        let date = blockedUntil.flatMap { dateParser.date(from: $0) }
        return BudgetExceededInfo(blockedUntil: date)
    }

    private func save() {
        defaults.set(state.isBlocked, forKey: Keys.isBlocked)
        if let until = state.blockedUntil {
            defaults.set(until.timeIntervalSince1970, forKey: Keys.blockedUntil)
        } else {
            defaults.removeObject(forKey: Keys.blockedUntil)
        }
        if let updatedAt = state.lastUpdatedAt {
            defaults.set(updatedAt.timeIntervalSince1970, forKey: Keys.lastUpdatedAt)
        } else {
            defaults.removeObject(forKey: Keys.lastUpdatedAt)
        }
    }

    private static func load(from defaults: UserDefaults) -> BudgetState {
        let isBlocked = defaults.bool(forKey: Keys.isBlocked)
        let blockedUntilSeconds = defaults.object(forKey: Keys.blockedUntil) as? TimeInterval
        let lastUpdatedSeconds = defaults.object(forKey: Keys.lastUpdatedAt) as? TimeInterval

        let blockedUntil = blockedUntilSeconds.map { Date(timeIntervalSince1970: $0) }
        let lastUpdatedAt = lastUpdatedSeconds.map { Date(timeIntervalSince1970: $0) }

        return BudgetState(isBlocked: isBlocked, blockedUntil: blockedUntil, lastUpdatedAt: lastUpdatedAt)
    }
}
