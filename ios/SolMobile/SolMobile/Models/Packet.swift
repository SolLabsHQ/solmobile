//
//  Packet.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/22/25.
//

import Foundation
import SwiftData

@Model
final class Packet {
    @Attribute(.unique) var id: UUID
    var packetType: String
    var threadId: UUID
    var messageIds: [UUID]          // v0: usually [userMessageId]
    var contextRefsJson: String?    // keep loose for now (pinnedContextRef etc.)
    var payloadJson: String?        // later: full request payload

    init(
        id: UUID = UUID(),
        packetType: String = "chat",
        threadId: UUID,
        messageIds: [UUID],
        contextRefsJson: String? = nil,
        payloadJson: String? = nil
    ) {
        self.id = id
        self.packetType = packetType
        self.threadId = threadId
        self.messageIds = messageIds
        self.contextRefsJson = contextRefsJson
        self.payloadJson = payloadJson
    }
}
