//
//  DeliveryAttempts.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/24/25.
//

import Foundation
import SwiftData

/// The outcome of a single attempt to deliver a queued Transmission.
/// Stored locally so we can derive retry/backoff/timeout without adding redundant fields.
enum DeliveryOutcome: String, Codable {
    case succeeded
    case failed
    case pending
}

@Model
final class DeliveryAttempt {
    @Attribute(.unique) var id: UUID

    /// When the attempt happened (device local time).
    var createdAt: Date

    /// HTTP status code when we got an HTTP response.
    /// Use -1 when the request failed before we got an HTTP response.
    var statusCode: Int

    /// Outcome derived from statusCode and client logic.
    var outcome: DeliveryOutcome

    /// Optional short error string (network error, decode error, etc.).
    var errorMessage: String?

    /// Optional correlation id if the server returned one.
    var transmissionId: String?

    /// Parent Transmission (inverse relationship lives on Transmission.deliveryAttempts).
    @Relationship var transmission: Transmission?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        statusCode: Int,
        outcome: DeliveryOutcome,
        errorMessage: String? = nil,
        transmissionId: String? = nil,
        transmission: Transmission? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.statusCode = statusCode
        self.outcome = outcome
        self.errorMessage = errorMessage
        self.transmissionId = transmissionId
        self.transmission = transmission
    }
}

