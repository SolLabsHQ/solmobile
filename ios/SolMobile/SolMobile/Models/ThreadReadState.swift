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
    var lastSeenMessageId: UUID?
    var lastSeenAt: Date

    init(
        id: UUID = UUID(),
        threadId: UUID,
        lastSeenMessageId: UUID? = nil,
        lastSeenAt: Date = Date()
    ) {
        self.id = id
        self.threadId = threadId
        self.lastSeenMessageId = lastSeenMessageId
        self.lastSeenAt = lastSeenAt
    }
}
