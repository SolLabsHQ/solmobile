//
//  DebugModelValidators.swift
//  SolMobile
//

import Foundation
import os
import SwiftData

nonisolated enum DebugModelValidators {
    static let log = Logger(subsystem: "com.sollabshq.solmobile", category: "swiftdata-validate")

    static func assertMessageHasThread(
        _ message: Message,
        context: String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        #if DEBUG
        guard extractThread(from: message) != nil else {
            log.error(
                "BUG: Message.thread is nil at save time. context=\(context, privacy: .public) messageId=\(message.id.uuidString, privacy: .public) serverMessageId=\(String(describing: message.serverMessageId), privacy: .public) transmissionId=\(String(describing: message.transmissionId), privacy: .public) creator=\(message.creatorTypeRaw, privacy: .public)"
            )
            assertionFailure("BUG: Message.thread is nil at save time. context=\(context)", file: file, line: line)
            fatalError("BUG: Message.thread is nil at save time. context=\(context)")
        }
        #endif
    }

    static func assertMessagesHaveThread(
        _ messages: [Message],
        context: String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        #if DEBUG
        for message in messages {
            assertMessageHasThread(message, context: context, file: file, line: line)
        }
        #endif
    }

    #if DEBUG
    static func threadOrNil(_ message: Message) -> ConversationThread? {
        extractThread(from: message)
    }

    static func pruneOrphanMessages(
        modelContext: ModelContext,
        reason: String
    ) {
        let descriptor = FetchDescriptor<Message>()
        guard let messages = try? modelContext.fetch(descriptor) else { return }
        let orphans = messages.filter { extractThread(from: $0) == nil }
        guard !orphans.isEmpty else { return }

        orphans.forEach { modelContext.delete($0) }
        do {
            try modelContext.save()
            log.error("pruned_orphan_messages count=\(orphans.count, privacy: .public) reason=\(reason, privacy: .public)")
        } catch {
            log.error("prune_orphan_messages_failed count=\(orphans.count, privacy: .public) reason=\(reason, privacy: .public) err=\(String(describing: error), privacy: .public)")
        }
    }

    private static func extractThread(from message: Message) -> ConversationThread? {
        let mirror = Mirror(reflecting: message)
        guard let child = mirror.children.first(where: { $0.label == "thread" }) else {
            return message.thread
        }
        let threadMirror = Mirror(reflecting: child.value)
        if threadMirror.displayStyle == .optional {
            guard let first = threadMirror.children.first else { return nil }
            return first.value as? ConversationThread
        }
        if let thread = child.value as? ConversationThread {
            return thread
        }
        return message.thread
    }
    #endif
}
