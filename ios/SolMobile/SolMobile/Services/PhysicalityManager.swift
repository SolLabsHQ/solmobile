//
//  PhysicalityManager.swift
//  SolMobile
//

import CoreHaptics
import Foundation
import UIKit

enum PhysicalityManager {
    static let storageKey = "sol.ghost.physicality.enabled"

    static var isPhysicalityEnabled: Bool {
        if UserDefaults.standard.object(forKey: storageKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: storageKey)
    }

    static func setPhysicalityEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: storageKey)
    }

    static var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    static func canFireHaptics() -> Bool {
        isPhysicalityEnabled && supportsHaptics
    }

    static func heartbeatIntensity(for moodAnchor: MoodAnchor?) -> Double {
        moodAnchor?.intensity ?? 0.6
    }
}
