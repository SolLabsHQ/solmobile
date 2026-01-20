//
//  ThreadReadState.swift
//  SolMobile
//
//  Created by SolMobile Unread Tracking.
//

import Foundation
import SwiftData

@Model
final class ThreadReadState {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var threadId: UUID
    var lastViewedMessageId: UUID?
    var readUpToMessageId: UUID?
    var lastViewedAt: Date
    var readUpToAt: Date?

    init(
        id: UUID = UUID(),
        threadId: UUID,
        lastViewedMessageId: UUID? = nil,
        readUpToMessageId: UUID? = nil,
        lastViewedAt: Date = Date(),
        readUpToAt: Date? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.lastViewedMessageId = lastViewedMessageId
        self.readUpToMessageId = readUpToMessageId
        self.lastViewedAt = lastViewedAt
        self.readUpToAt = readUpToAt
    }
}
