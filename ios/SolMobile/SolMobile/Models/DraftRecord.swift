//
//  DraftRecord.swift
//  SolMobile
//

import Foundation
import SwiftData

@Model
final class DraftRecord {
    @Attribute(.unique)
    var threadId: String
    var content: String
    var updatedAt: Date

    init(threadId: String, content: String, updatedAt: Date = Date()) {
        self.threadId = threadId
        self.content = content
        self.updatedAt = updatedAt
    }
}

struct DraftSnapshot: Sendable {
    let content: String
    let updatedAt: Date
}

nonisolated protocol DraftStoreBacking {
    func fetch(threadId: String) -> DraftSnapshot?
    func upsert(threadId: String, content: String, updatedAt: Date)
    func delete(threadId: String)
    func cleanupExpired(cutoff: Date) throws
}

nonisolated final class SwiftDataDraftStoreBacking: DraftStoreBacking {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetch(threadId: String) -> DraftSnapshot? {
        let descriptor = FetchDescriptor<DraftRecord>(
            predicate: #Predicate { draft in
                draft.threadId == threadId
            }
        )
        guard let record = (try? modelContext.fetch(descriptor))?.first else { return nil }
        return DraftSnapshot(content: record.content, updatedAt: record.updatedAt)
    }

    func upsert(threadId: String, content: String, updatedAt: Date) {
        let descriptor = FetchDescriptor<DraftRecord>(
            predicate: #Predicate { draft in
                draft.threadId == threadId
            }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.content = content
            existing.updatedAt = updatedAt
        } else {
            let draft = DraftRecord(threadId: threadId, content: content, updatedAt: updatedAt)
            modelContext.insert(draft)
        }

        try? modelContext.save()
    }

    func delete(threadId: String) {
        let descriptor = FetchDescriptor<DraftRecord>(
            predicate: #Predicate { draft in
                draft.threadId == threadId
            }
        )
        guard let existing = (try? modelContext.fetch(descriptor))?.first else { return }
        modelContext.delete(existing)
        try? modelContext.save()
    }

    func cleanupExpired(cutoff: Date) throws {
        let descriptor = FetchDescriptor<DraftRecord>(
            predicate: #Predicate { draft in
                draft.updatedAt < cutoff
            }
        )

        let stale = try modelContext.fetch(descriptor)
        guard !stale.isEmpty else { return }
        stale.forEach { modelContext.delete($0) }
        try modelContext.save()
    }
}

nonisolated final class DraftStore {
    static let ttlSeconds: TimeInterval = 60 * 60 * 24 * 30

    private let backing: DraftStoreBacking

    init(modelContext: ModelContext) {
        self.backing = SwiftDataDraftStoreBacking(modelContext: modelContext)
    }

    init(backing: DraftStoreBacking) {
        self.backing = backing
    }

    func fetchDraft(threadId: UUID) -> DraftSnapshot? {
        backing.fetch(threadId: threadId.uuidString)
    }

    func upsertDraft(threadId: UUID, content: String, updatedAt: Date = Date()) {
        backing.upsert(threadId: threadId.uuidString, content: content, updatedAt: updatedAt)
    }

    func deleteDraft(threadId: UUID) {
        backing.delete(threadId: threadId.uuidString)
    }

    func forceSaveNow(threadId: UUID, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteDraft(threadId: threadId)
            return
        }

        upsertDraft(threadId: threadId, content: trimmed, updatedAt: Date())
    }

    @MainActor
    func cleanupExpiredDrafts(now: Date = .init()) throws {
        let cutoff = now.addingTimeInterval(-DraftStore.ttlSeconds)
        try backing.cleanupExpired(cutoff: cutoff)
    }
}
