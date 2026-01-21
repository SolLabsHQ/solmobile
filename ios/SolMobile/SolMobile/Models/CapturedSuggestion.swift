//
//  CapturedSuggestion.swift
//  SolMobile
//
//  Tracks capture suggestions that were exported or dismissed.
//

import Foundation
import SwiftData

@Model
final class CapturedSuggestion {
    @Attribute(.unique) var suggestionId: String
    var capturedAt: Date
    var destination: String
    var messageId: UUID?
    var locationLatitude: Double?
    var locationLongitude: Double?
    var sentimentLabel: String?

    init(
        suggestionId: String,
        capturedAt: Date = Date(),
        destination: String,
        messageId: UUID? = nil,
        locationLatitude: Double? = nil,
        locationLongitude: Double? = nil,
        sentimentLabel: String? = nil
    ) {
        self.suggestionId = suggestionId
        self.capturedAt = capturedAt
        self.destination = destination
        self.messageId = messageId
        self.locationLatitude = locationLatitude
        self.locationLongitude = locationLongitude
        self.sentimentLabel = sentimentLabel
    }
}
