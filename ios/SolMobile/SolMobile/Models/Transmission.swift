//
//  Transmission.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/22/25.
//

import Foundation
import SwiftData

enum TransmissionStatus: String, Codable {
    case queued
    case sending
    case pending
    case succeeded
    case failed
}

@Model
final class Transmission {
    @Attribute(.unique) var id: UUID
    var type: String                 // "chat" for v0
    var requestId: String            // idempotency key (UUID string)
    var statusRaw: String
    var createdAt: Date
    var lastError: String?

    // Server-proposed ThreadMemento draft (navigation artifact).
    // Used to offer Accept/Decline in the UI without storing raw JSON.
    var serverThreadMementoId: String?
    var serverThreadMementoCreatedAtISO: String?
    var serverThreadMementoSummary: String?

    // Local ledger of delivery attempts (used to derive retry/backoff/timeout without redundant fields).
    @Relationship(deleteRule: .cascade, inverse: \DeliveryAttempt.transmission)
    var deliveryAttempts: [DeliveryAttempt] = []

    var packet: Packet

    init(
        id: UUID = UUID(),
        type: String = "chat",
        requestId: String = UUID().uuidString,
        status: TransmissionStatus = .queued,
        createdAt: Date = Date(),
        lastError: String? = nil,
        packet: Packet
    ) {
        self.id = id
        self.type = type
        self.requestId = requestId
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.lastError = lastError
        self.packet = packet
    }

    var status: TransmissionStatus {
        get { TransmissionStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }
}
