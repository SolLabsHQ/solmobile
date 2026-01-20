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

enum DeliveryAttemptSource: String, Codable {
    case send
    case poll
    case terminal
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

    /// Whether this was a send attempt, poll attempt, or local terminal record.
    var source: DeliveryAttemptSource

    /// Optional short error string (network error, decode error, etc.).
    var errorMessage: String?

    /// Optional correlation id if the server returned one.
    var transmissionId: String?

    /// Whether the client inferred this failure as retryable.
    var retryableInferred: Bool?

    /// Optional retry-after seconds for rate limits (server-provided).
    var retryAfterSeconds: Double?

    /// Final response URL after redirects (redacted in diagnostics export).
    var finalURL: String?

    /// Parent Transmission (inverse relationship lives on Transmission.deliveryAttempts).
    @Relationship var transmission: Transmission?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        statusCode: Int,
        outcome: DeliveryOutcome,
        source: DeliveryAttemptSource = .send,
        errorMessage: String? = nil,
        transmissionId: String? = nil,
        retryableInferred: Bool? = nil,
        retryAfterSeconds: Double? = nil,
        finalURL: String? = nil,
        transmission: Transmission? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.statusCode = statusCode
        self.outcome = outcome
        self.source = source
        self.errorMessage = errorMessage
        self.transmissionId = transmissionId
        self.retryableInferred = retryableInferred
        self.retryAfterSeconds = retryAfterSeconds
        self.finalURL = finalURL
        self.transmission = transmission
    }
}
