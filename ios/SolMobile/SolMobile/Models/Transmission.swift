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
