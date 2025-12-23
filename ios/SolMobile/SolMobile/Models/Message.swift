//
//  Message.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/22/25.
//

import Foundation
import SwiftData

@Model
final class Message {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var creatorTypeRaw: String
    var text: String

    var thread: Thread

    init(
        id: UUID = UUID(),
        thread: Thread,
        creatorType: CreatorType,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.thread = thread
        self.creatorTypeRaw = creatorType.rawValue
        self.text = text
        self.createdAt = createdAt
    }

    var creatorType: CreatorType {
        get { CreatorType(rawValue: creatorTypeRaw) ?? .user }
        set { creatorTypeRaw = newValue.rawValue }
    }
}
