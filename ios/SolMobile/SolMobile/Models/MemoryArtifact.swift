//
//  MemoryArtifact.swift
//  SolMobile
//

import Foundation
import SwiftData

@Model
final class MemoryArtifact {
    @Attribute(.unique) var memoryId: String
    var threadId: String?
    var triggerMessageId: String?
    var typeRaw: String
    var snippet: String?
    var moodAnchor: String?
    var rigorLevelRaw: String?
    var tagsCsv: String?
    var fidelityRaw: String?
    var transitionToHazyAt: Date?
    var createdAt: Date?
    var updatedAt: Date?

    var arrivalHapticFired: Bool
    var ascendedAt: Date?
    var locationLatitude: Double?
    var locationLongitude: Double?

    init(
        memoryId: String,
        threadId: String? = nil,
        triggerMessageId: String? = nil,
        typeRaw: String = "memory",
        snippet: String? = nil,
        moodAnchor: String? = nil,
        rigorLevelRaw: String? = nil,
        tagsCsv: String? = nil,
        fidelityRaw: String? = nil,
        transitionToHazyAt: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        arrivalHapticFired: Bool = false,
        ascendedAt: Date? = nil,
        locationLatitude: Double? = nil,
        locationLongitude: Double? = nil
    ) {
        self.memoryId = memoryId
        self.threadId = threadId
        self.triggerMessageId = triggerMessageId
        self.typeRaw = typeRaw
        self.snippet = snippet
        self.moodAnchor = moodAnchor
        self.rigorLevelRaw = rigorLevelRaw
        self.tagsCsv = tagsCsv
        self.fidelityRaw = fidelityRaw
        self.transitionToHazyAt = transitionToHazyAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.arrivalHapticFired = arrivalHapticFired
        self.ascendedAt = ascendedAt
        self.locationLatitude = locationLatitude
        self.locationLongitude = locationLongitude
    }
}

extension MemoryArtifact {
    var tags: [String] {
        guard let tagsCsv, !tagsCsv.isEmpty else { return [] }
        return tagsCsv.split(separator: ",").map { String($0) }
    }
}
