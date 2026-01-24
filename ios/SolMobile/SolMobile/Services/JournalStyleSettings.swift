//
//  JournalStyleSettings.swift
//  SolMobile
//

import Foundation

enum JournalStyleSettings {
    static let offersEnabledKey = "sol.journal.offers_enabled"
    static let cooldownMinutesKey = "sol.journal.cooldown_minutes"
    static let avoidPeakOverwhelmKey = "sol.journal.avoid_peak_overwhelm"
    static let defaultModeKey = "sol.journal.default_mode"
    static let maxLinesDefaultKey = "sol.journal.max_lines_default"
    static let toneNotesKey = "sol.journal.tone_notes"
    static let cpbIdKey = "sol.journal.cpb_id"
    private static let lastOfferShownAtKey = "sol.journal.last_offer_shown_at"

    static var offersEnabled: Bool {
        if UserDefaults.standard.object(forKey: offersEnabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: offersEnabledKey)
    }

    static func setOffersEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: offersEnabledKey)
    }

    static var cooldownMinutes: Int {
        if UserDefaults.standard.object(forKey: cooldownMinutesKey) == nil {
            return 60
        }
        return UserDefaults.standard.integer(forKey: cooldownMinutesKey)
    }

    static func setCooldownMinutes(_ minutes: Int) {
        UserDefaults.standard.set(max(0, minutes), forKey: cooldownMinutesKey)
    }

    static var avoidPeakOverwhelm: Bool {
        if UserDefaults.standard.object(forKey: avoidPeakOverwhelmKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: avoidPeakOverwhelmKey)
    }

    static func setAvoidPeakOverwhelm(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: avoidPeakOverwhelmKey)
    }

    static var defaultMode: JournalDraftMode {
        let raw = UserDefaults.standard.string(forKey: defaultModeKey)
        return JournalDraftMode(rawValue: raw ?? "assist") ?? .assist
    }

    static func setDefaultMode(_ mode: JournalDraftMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: defaultModeKey)
    }

    static var maxLinesDefault: Int {
        if UserDefaults.standard.object(forKey: maxLinesDefaultKey) == nil {
            return 12
        }
        return UserDefaults.standard.integer(forKey: maxLinesDefaultKey)
    }

    static func setMaxLinesDefault(_ value: Int) {
        UserDefaults.standard.set(max(1, value), forKey: maxLinesDefaultKey)
    }

    static var toneNotes: String {
        UserDefaults.standard.string(forKey: toneNotesKey) ?? "Warm, grounded, concise."
    }

    static func setToneNotes(_ notes: String) {
        UserDefaults.standard.set(notes, forKey: toneNotesKey)
    }

    static var cpbId: String? {
        guard let raw = UserDefaults.standard.string(forKey: cpbIdKey) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func setCpbId(_ cpbId: String?) {
        let trimmed = cpbId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: cpbIdKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: cpbIdKey)
        }
    }

    static var lastOfferShownAt: Date? {
        let ts = UserDefaults.standard.double(forKey: lastOfferShownAtKey)
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    static func markOfferShown(now: Date = Date()) {
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastOfferShownAtKey)
    }

    static func isCooldownActive(now: Date = Date()) -> Bool {
        guard offersEnabled else { return true }
        guard cooldownMinutes > 0 else { return false }
        guard let lastShownAt = lastOfferShownAt else { return false }
        return now.timeIntervalSince(lastShownAt) < TimeInterval(cooldownMinutes * 60)
    }
}
