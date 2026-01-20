//
//  SeedFactory.swift
//  SolMobileTests

//  Created by Jassen A. McNulty on 12/26/25.
//

import Foundation
import SwiftData
@testable import SolMobile

@MainActor
enum SeedFactory {

    static func makeThread(_ context: ModelContext, title: String = "t") -> ConversationThread {
        let t = ConversationThread(title: title)
        context.insert(t)
        return t
    }

    static func makeUserMessage(_ context: ModelContext, thread: ConversationThread, text: String = "hi") -> Message {
        let m = Message(thread: thread, creatorType: .user, text: text)
        thread.messages.append(m)
        context.insert(m)
        return m
    }

    static func enqueueChat(
        _ actions: TransmissionActions,
        thread: ConversationThread,
        userMessage: Message
    ) {
        actions.enqueueChat(thread: thread, userMessage: userMessage)
    }

    static func fetchFirstQueuedTransmission(_ context: ModelContext) -> Transmission? {
        let queuedRaw = TransmissionStatus.queued.rawValue
        let d = FetchDescriptor<Transmission>(predicate: #Predicate { $0.statusRaw == queuedRaw })
        return (try? context.fetch(d))?.first
    }

    static func fetchFirstPendingTransmission(_ context: ModelContext) -> Transmission? {
        let pendingRaw = TransmissionStatus.pending.rawValue
        let d = FetchDescriptor<Transmission>(predicate: #Predicate { $0.statusRaw == pendingRaw })
        return (try? context.fetch(d))?.first
    }
}
