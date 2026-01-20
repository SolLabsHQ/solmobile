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
    private var pendingViewedUpdates: [UUID: UUID] = [:]
    private var flushTask: Task<Void, Never>?
    private let debounceNanos: UInt64 = 300_000_000

    init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    func markViewed(threadId: UUID, messageId: UUID) {
        if pendingViewedUpdates[threadId] == messageId {
            return
        }

        pendingViewedUpdates[threadId] = messageId
        scheduleFlush()
    }

    func flush(threadId: UUID? = nil) async {
        let updates: [UUID: UUID]
        if let threadId, let messageId = pendingViewedUpdates[threadId] {
            updates = [threadId: messageId]
            pendingViewedUpdates[threadId] = nil
        } else {
            updates = pendingViewedUpdates
            pendingViewedUpdates.removeAll()
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
            existing.lastViewedMessageId = messageId
            existing.lastViewedAt = Date()
            if shouldAdvanceReadUpTo(currentId: existing.readUpToMessageId, candidateId: messageId) {
                existing.readUpToMessageId = messageId
                existing.readUpToAt = Date()
            }
            return
        }

        let state = ThreadReadState(
            threadId: threadId,
            lastViewedMessageId: messageId,
            readUpToMessageId: messageId,
            lastViewedAt: Date(),
            readUpToAt: Date()
        )
        context.insert(state)
    }

    private func shouldAdvanceReadUpTo(currentId: UUID?, candidateId: UUID) -> Bool {
        guard let candidate = fetchMessage(id: candidateId) else { return false }
        guard let currentId else { return true }
        guard let current = fetchMessage(id: currentId) else { return true }

        if candidate.createdAt == current.createdAt {
            return candidate.id.uuidString > current.id.uuidString
        }
        return candidate.createdAt > current.createdAt
    }

    private func fetchMessage(id: UUID) -> Message? {
        let msgId = id
        let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.id == msgId })
        return try? context.fetch(descriptor).first
    }
}
