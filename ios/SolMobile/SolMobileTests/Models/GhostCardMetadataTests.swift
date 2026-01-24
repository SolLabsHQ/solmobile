//
//  GhostCardMetadataTests.swift
//  SolMobileTests
//

import XCTest
@testable import SolMobile

final class GhostCardMetadataTests: XCTestCase {
    func test_isAscendEligible_requiresGhostKindRaw() {
        let thread = ConversationThread()
        let message = Message(thread: thread, creatorType: .assistant, text: "")

        message.ghostTypeRaw = "journal"
        XCTAssertFalse(message.isAscendEligible)

        message.ghostKindRaw = GhostKind.journalMoment.rawValue
        XCTAssertTrue(message.isAscendEligible)
    }
}
