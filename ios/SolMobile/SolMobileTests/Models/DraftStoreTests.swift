//
//  DraftStoreTests.swift
//  SolMobile
//

import XCTest
import SwiftData
@testable import SolMobile

@MainActor
final class DraftStoreTests: XCTestCase {
    private final class FakeDraftStoreBacking: DraftStoreBacking {
        private var storage: [String: DraftSnapshot] = [:]

        func fetch(threadId: String) -> DraftSnapshot? {
            storage[threadId]
        }

        func upsert(threadId: String, content: String, updatedAt: Date) {
            storage[threadId] = DraftSnapshot(content: content, updatedAt: updatedAt)
        }

        func delete(threadId: String) {
            storage.removeValue(forKey: threadId)
        }

        func cleanupExpired(cutoff: Date) throws {
            storage = storage.filter { $0.value.updatedAt >= cutoff }
        }
    }

    private func skipIfIOS26() throws {
        if #available(iOS 26, *) {
            throw XCTSkip("SwiftData crash on iOS 26.x sim for DraftRecord")
        }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try skipIfIOS26()
    }

    func test_upsertDraft_updatesExistingRecord() {
        let store = DraftStore(backing: FakeDraftStoreBacking())
        let threadId = UUID()

        store.upsertDraft(threadId: threadId, content: "hello")
        store.upsertDraft(threadId: threadId, content: "updated")

        let fetched = store.fetchDraft(threadId: threadId)
        XCTAssertEqual(fetched?.content, "updated")
    }

    func test_forceSaveNow_deletesOnEmpty() {
        let store = DraftStore(backing: FakeDraftStoreBacking())
        let threadId = UUID()

        store.upsertDraft(threadId: threadId, content: "keep me")
        store.forceSaveNow(threadId: threadId, content: "   ")

        XCTAssertNil(store.fetchDraft(threadId: threadId))
    }

    func test_cleanupExpiredDrafts_removesStaleRecords() throws {
        let store = DraftStore(backing: FakeDraftStoreBacking())
        let oldId = UUID()
        let newId = UUID()

        store.upsertDraft(
            threadId: oldId,
            content: "old",
            updatedAt: Date().addingTimeInterval(-DraftStore.ttlSeconds - 10)
        )
        store.upsertDraft(threadId: newId, content: "new")

        try store.cleanupExpiredDrafts()

        XCTAssertNil(store.fetchDraft(threadId: oldId))
        XCTAssertEqual(store.fetchDraft(threadId: newId)?.content, "new")
    }

    func test_swiftDataSmoke_upsertFetch() throws {
        try skipIfIOS26()

        let schema = Schema([DraftRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let store = DraftStore(modelContext: context)
        let threadId = UUID()

        store.upsertDraft(threadId: threadId, content: "hello")

        XCTAssertEqual(store.fetchDraft(threadId: threadId)?.content, "hello")
    }
}
