//
//  PhysicalityManager.swift
//  SolMobile
//

import CoreHaptics
import Foundation
import UIKit

enum PhysicalityManager {
    static var isPhysicalityEnabled: Bool {
        true
    }

    static var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    static func canFireHaptics() -> Bool {
        supportsHaptics
    }

    static func heartbeatIntensity(for moodAnchor: MoodAnchor?) -> Double {
        moodAnchor?.intensity ?? 0.6
    }
}
