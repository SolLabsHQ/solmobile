//
//  MemoryOfferSettings.swift
//  SolMobile
//

import Foundation

enum MemoryOfferSettings {
    static let autoAcceptKey = "sol.memory.auto_accept_offers"

    enum AutoAcceptMode: String, CaseIterable {
        case off = "off"
        case safeOnly = "safe_only"
        case always = "always"
    }

    static var autoAcceptMode: AutoAcceptMode {
        let raw = UserDefaults.standard.string(forKey: autoAcceptKey)
        return AutoAcceptMode(rawValue: raw ?? AutoAcceptMode.safeOnly.rawValue) ?? .safeOnly
    }

    static func setAutoAcceptMode(_ mode: AutoAcceptMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: autoAcceptKey)
    }
}
