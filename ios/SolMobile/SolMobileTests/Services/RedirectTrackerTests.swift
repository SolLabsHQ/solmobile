//
//  RedirectTrackerTests.swift
//  SolMobileTests
//
//  Created by SolMobile Redirect Tracker Tests.
//

import Foundation
import XCTest
@testable import SolMobile

@MainActor
final class RedirectTrackerTests: XCTestCase {
    @MainActor
    func test_redirectTracker_recordsAndCapsChain() {
        let tracker = RedirectTracker()
        let taskKey = "test-task"

        let url1 = URL(string: "http://example.com")!
        let url2 = URL(string: "https://example.com")!
        let url3 = URL(string: "https://example.com/next")!
        let url4 = URL(string: "https://example.com/final")!

        tracker.recordRedirect(taskKey: taskKey, from: url1, to: url2, statusCode: 301, method: "GET")
        tracker.recordRedirect(taskKey: taskKey, from: url2, to: url3, statusCode: 302, method: "GET")
        tracker.recordRedirect(taskKey: taskKey, from: url3, to: url4, statusCode: 307, method: "GET")
        tracker.recordRedirect(taskKey: taskKey, from: url4, to: url1, statusCode: 308, method: "GET")

        let chain = tracker.consumeChain(taskKey: taskKey)
        let firstFrom = chain[0].from
        let lastTo = chain[2].to
        XCTAssertEqual(chain.count, 3)
        XCTAssertEqual(firstFrom, url1)
        XCTAssertEqual(lastTo, url4)
    }
}
