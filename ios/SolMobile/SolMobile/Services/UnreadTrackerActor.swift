//
//  UnreadTrackerActor.swift
//  SolMobile
//
//  Created by SolMobile Unread Tracking.
//

import Foundation
import SwiftData

actor UnreadTrackerActor {
    private let context: ModelContext
    private var pendingUpdates: [UUID: UUID] = [:]
    private var flushTask: Task<Void, Never>?
    private let debounceNanos: UInt64 = 300_000_000

    init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    func markSeen(threadId: UUID, messageId: UUID) {
        if pendingUpdates[threadId] == messageId {
            return
        }

        pendingUpdates[threadId] = messageId
        scheduleFlush()
    }

    func flush(threadId: UUID? = nil) async {
        let updates: [UUID: UUID]
        if let threadId, let messageId = pendingUpdates[threadId] {
            updates = [threadId: messageId]
            pendingUpdates[threadId] = nil
        } else {
            updates = pendingUpdates
            pendingUpdates.removeAll()
        }

        guard !updates.isEmpty else { return }

        for (threadId, messageId) in updates {
            upsertReadState(threadId: threadId, messageId: messageId)
        }

        try? context.save()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [debounceNanos] in
            try? await Task.sleep(nanoseconds: debounceNanos)
            await flush()
        }
    }

    private func upsertReadState(threadId: UUID, messageId: UUID) {
        let descriptor = FetchDescriptor<ThreadReadState>(
            predicate: #Predicate { $0.threadId == threadId }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.lastSeenMessageId = messageId
            existing.lastSeenAt = Date()
            return
        }

        let state = ThreadReadState(threadId: threadId, lastSeenMessageId: messageId, lastSeenAt: Date())
        context.insert(state)
    }
}
