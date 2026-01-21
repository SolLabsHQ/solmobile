//
//  GhostCardCTATests.swift
//  SolMobileTests
//
//  Created by SolMobile on 02/12/26.
//

import SwiftData
import XCTest
@testable import SolMobile

@MainActor
final class GhostCardCTATests: SwiftDataTestBase {
    func test_manualEntry_isEditOnly() throws {
        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let message = Message(thread: thread, creatorType: .assistant, text: "")
        message.ghostFactNull = true
        message.ghostMemoryId = nil
        message.ghostRigorLevelRaw = "normal"

        let state = message.ghostCTAState
        XCTAssertTrue(state.canEdit)
        XCTAssertFalse(state.canForget)
        XCTAssertFalse(state.requiresConfirm)
    }

    func test_highRigor_requiresConfirm_andAllowsForget() throws {
        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let message = Message(thread: thread, creatorType: .assistant, text: "")
        message.ghostFactNull = false
        message.ghostMemoryId = "mem-123"
        message.ghostRigorLevelRaw = "high"

        let state = message.ghostCTAState
        XCTAssertTrue(state.canEdit)
        XCTAssertTrue(state.canForget)
        XCTAssertTrue(state.requiresConfirm)
    }
}
