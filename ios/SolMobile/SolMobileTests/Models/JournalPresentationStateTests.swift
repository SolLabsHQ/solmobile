//
//  JournalPresentationStateTests.swift
//  SolMobileTests
//

import XCTest
@testable import SolMobile

final class JournalPresentationStateTests: XCTestCase {
    func test_alertDismissTransitionsToShareSheetWhenFlagged() {
        let state = JournalPresentationState.alert(message: "Test", showShareSheet: true)
        let next = JournalPresentationState.nextStateOnAlertDismiss(state)
        XCTAssertEqual(next, .shareSheet)
    }

    func test_alertDismissTransitionsToIdleWhenNotFlagged() {
        let state = JournalPresentationState.alert(message: "Test", showShareSheet: false)
        let next = JournalPresentationState.nextStateOnAlertDismiss(state)
        XCTAssertEqual(next, .idle)
    }
}
