//
//  StorageCleanupTests.swift
//  SolMobileTests
//

import XCTest
import SwiftData
@testable import SolMobile

@MainActor
final class StorageCleanupTests: SwiftDataTestBase {
    private nonisolated func skipIfIOS26() throws {
        if #available(iOS 26, *) {
            throw XCTSkip("SwiftData crash on iOS 26.x sim for cleanup deletes")
        }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try skipIfIOS26()
    }

    func test_cleanupDeletesOnlyUnpinnedOldMessages() throws {
        let now = Date()
        let thread = ConversationThread(title: "Thread", lastActiveAt: now)
        context.insert(thread)

        let oldUnpinned = Message(
            thread: thread,
            creatorType: .user,
            text: "old",
            createdAt: now.addingTimeInterval(-StorageCleanupService.ttlSeconds - 10),
            pinned: false
        )
        let oldPinned = Message(
            thread: thread,
            creatorType: .user,
            text: "pinned",
            createdAt: now.addingTimeInterval(-StorageCleanupService.ttlSeconds - 10),
            pinned: true
        )
        let fresh = Message(
            thread: thread,
            creatorType: .user,
            text: "fresh",
            createdAt: now.addingTimeInterval(-60),
            pinned: false
        )

        thread.messages.append(contentsOf: [oldUnpinned, oldPinned, fresh])
        context.insert(oldUnpinned)
        context.insert(oldPinned)
        context.insert(fresh)
        try context.save()

        let service = StorageCleanupService(modelContext: context)
        _ = try service.runCleanup(now: now, force: true)

        let remaining = try context.fetch(FetchDescriptor<Message>())
        XCTAssertFalse(remaining.contains { $0.id == oldUnpinned.id })
        XCTAssertTrue(remaining.contains { $0.id == oldPinned.id })
        XCTAssertTrue(remaining.contains { $0.id == fresh.id })
    }

    func test_cleanupRespectsSevenDayBoundary() throws {
        let now = Date()
        let cutoff = now.addingTimeInterval(-StorageCleanupService.ttlSeconds)
        let thread = ConversationThread(title: "Boundary", lastActiveAt: now)
        context.insert(thread)

        let atCutoff = Message(
            thread: thread,
            creatorType: .user,
            text: "at cutoff",
            createdAt: cutoff,
            pinned: false
        )
        let pastCutoff = Message(
            thread: thread,
            creatorType: .user,
            text: "past cutoff",
            createdAt: cutoff.addingTimeInterval(-1),
            pinned: false
        )

        thread.messages.append(contentsOf: [atCutoff, pastCutoff])
        context.insert(atCutoff)
        context.insert(pastCutoff)
        try context.save()

        let service = StorageCleanupService(modelContext: context)
        _ = try service.runCleanup(now: now, force: true)

        let remaining = try context.fetch(FetchDescriptor<Message>())
        XCTAssertTrue(remaining.contains { $0.id == atCutoff.id })
        XCTAssertFalse(remaining.contains { $0.id == pastCutoff.id })
    }

    func test_saveToMemoryPinsThreadAndMessages() {
        let thread = ConversationThread(title: "Pin", lastActiveAt: Date())
        context.insert(thread)

        let msg1 = Message(thread: thread, creatorType: .user, text: "one", pinned: false)
        let msg2 = Message(thread: thread, creatorType: .assistant, text: "two", pinned: false)
        thread.messages.append(contentsOf: [msg1, msg2])
        context.insert(msg1)
        context.insert(msg2)

        StoragePinningService(modelContext: context)
            .pinThreadAndMessages(thread: thread, messages: [msg1, msg2])

        XCTAssertTrue(thread.pinned)
        XCTAssertTrue(msg1.pinned)
        XCTAssertTrue(msg2.pinned)
    }

    func test_newMessagesInPinnedThreadDefaultToPinned() {
        let thread = ConversationThread(title: "Pinned", lastActiveAt: Date(), pinned: true)
        context.insert(thread)

        let msg = Message(thread: thread, creatorType: .user, text: "hello")
        context.insert(msg)

        XCTAssertTrue(msg.pinned)
    }

    func test_cleanupDeletesEmptyUnpinnedThreads() throws {
        let now = Date()
        let thread = ConversationThread(title: "Old", lastActiveAt: now)
        context.insert(thread)

        let oldMessage = Message(
            thread: thread,
            creatorType: .user,
            text: "expired",
            createdAt: now.addingTimeInterval(-StorageCleanupService.ttlSeconds - 10),
            pinned: false
        )
        thread.messages.append(oldMessage)
        context.insert(oldMessage)
        try context.save()

        let service = StorageCleanupService(modelContext: context)
        _ = try service.runCleanup(now: now, force: true)

        let remainingThreads = try context.fetch(FetchDescriptor<ConversationThread>())
        XCTAssertFalse(remainingThreads.contains { $0.id == thread.id })
    }
}
