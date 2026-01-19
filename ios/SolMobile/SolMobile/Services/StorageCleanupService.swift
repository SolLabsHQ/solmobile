//
//  StorageCleanupService.swift
//  SolMobile
//
//  ADR-008 offline-first TTL cleanup
//

import Foundation
import SwiftData
import os

@MainActor
struct StorageCleanupResult {
    let deletedMessages: Int
    let deletedThreads: Int
    let ran: Bool
}

@MainActor
struct StorageCleanupStats {
    let lastRunAt: Date?
    let deletedMessages: Int
    let deletedThreads: Int
}

@MainActor
final class StorageCleanupService {
    static let ttlSeconds: TimeInterval = 60 * 60 * 24 * 7
    // Run at most twice per day; foreground still triggers when due.
    static let cleanupIntervalSeconds: TimeInterval = 60 * 60 * 12

    private static let lastCleanupRunAtKey = "sol.storage.lastCleanupRunAt"
    private static let lastDeletedMessagesKey = "sol.storage.lastCleanupDeletedMessages"
    private static let lastDeletedThreadsKey = "sol.storage.lastCleanupDeletedThreads"

    private let modelContext: ModelContext
    private let log = Logger(subsystem: "com.sollabshq.solmobile", category: "StorageCleanup")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    static func loadStats() -> StorageCleanupStats {
        let defaults = UserDefaults.standard
        let ts = defaults.double(forKey: lastCleanupRunAtKey)
        let lastRunAt = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        let deletedMessages = defaults.integer(forKey: lastDeletedMessagesKey)
        let deletedThreads = defaults.integer(forKey: lastDeletedThreadsKey)
        return StorageCleanupStats(
            lastRunAt: lastRunAt,
            deletedMessages: deletedMessages,
            deletedThreads: deletedThreads
        )
    }

    func isCleanupDue(now: Date = .init()) -> Bool {
        guard let lastRunAt = Self.loadStats().lastRunAt else { return true }
        return now.timeIntervalSince(lastRunAt) >= Self.cleanupIntervalSeconds
    }

    func runCleanup(now: Date = .init(), force: Bool = false) throws -> StorageCleanupResult {
        if !force, !isCleanupDue(now: now) {
            return StorageCleanupResult(deletedMessages: 0, deletedThreads: 0, ran: false)
        }

        let cutoff = now.addingTimeInterval(-Self.ttlSeconds)

        let messageDescriptor = FetchDescriptor<Message>(
            predicate: #Predicate { msg in
                msg.pinned == false && msg.createdAt < cutoff
            }
        )

        let expiredMessages = try modelContext.fetch(messageDescriptor)
        let deletedMessages = expiredMessages.count
        if deletedMessages > 0 {
            expiredMessages.forEach { modelContext.delete($0) }
            try modelContext.save()
        }

        let threadDescriptor = FetchDescriptor<ConversationThread>(
            predicate: #Predicate { thread in
                thread.pinned == false
            }
        )

        let candidateThreads = try modelContext.fetch(threadDescriptor)
        let emptyThreads = candidateThreads.filter { $0.messages.isEmpty }
        let deletedThreads = emptyThreads.count
        if deletedThreads > 0 {
            emptyThreads.forEach { modelContext.delete($0) }
            try modelContext.save()
        }

        persistStats(runAt: now, deletedMessages: deletedMessages, deletedThreads: deletedThreads)

        log.info("cleanup completed messages=\(deletedMessages, privacy: .public) threads=\(deletedThreads, privacy: .public)")

        return StorageCleanupResult(
            deletedMessages: deletedMessages,
            deletedThreads: deletedThreads,
            ran: true
        )
    }

    private func persistStats(runAt: Date, deletedMessages: Int, deletedThreads: Int) {
        let defaults = UserDefaults.standard
        defaults.set(runAt.timeIntervalSince1970, forKey: Self.lastCleanupRunAtKey)
        defaults.set(deletedMessages, forKey: Self.lastDeletedMessagesKey)
        defaults.set(deletedThreads, forKey: Self.lastDeletedThreadsKey)
    }
}
