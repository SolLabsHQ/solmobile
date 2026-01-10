//
//  Thread.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/22/25.
//

import Foundation
import SwiftData

@Model
final class ConversationThread {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var lastActiveAt: Date
    var pinned: Bool
    var expiresAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Message.thread)
    var messages: [Message]

    init(
        id: UUID = UUID(),
        title: String = "New Thread",
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        pinned: Bool = false,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.pinned = pinned
        self.expiresAt = expiresAt
        self.messages = []
    }
}
