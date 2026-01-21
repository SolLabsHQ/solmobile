//
//  GhostCardLedger.swift
//  SolMobile
//

import Foundation
import SwiftData

@Model
final class GhostCardLedger {
    @Attribute(.unique) var key: String
    var arrivalHapticFired: Bool
    var createdAt: Date

    init(key: String, arrivalHapticFired: Bool = false, createdAt: Date = Date()) {
        self.key = key
        self.arrivalHapticFired = arrivalHapticFired
        self.createdAt = createdAt
    }
}
