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

    init(
        suggestionId: String,
        capturedAt: Date = Date(),
        destination: String,
        messageId: UUID? = nil
    ) {
        self.suggestionId = suggestionId
        self.capturedAt = capturedAt
        self.destination = destination
        self.messageId = messageId
    }
}
