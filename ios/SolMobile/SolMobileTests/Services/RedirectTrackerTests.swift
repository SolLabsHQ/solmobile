//
//  RedirectTrackerTests.swift
//  SolMobileTests
//
//  Created by SolMobile Redirect Tracker Tests.
//

import Foundation
import XCTest
@testable import SolMobile

final class RedirectTrackerTests: XCTestCase {
    func test_redirectTracker_recordsAndCapsChain() {
        let tracker = RedirectTracker()
        let taskId = 42

        let url1 = URL(string: "http://example.com")!
        let url2 = URL(string: "https://example.com")!
        let url3 = URL(string: "https://example.com/next")!
        let url4 = URL(string: "https://example.com/final")!

        tracker.recordRedirect(taskId: taskId, from: url1, to: url2, statusCode: 301, method: "GET")
        tracker.recordRedirect(taskId: taskId, from: url2, to: url3, statusCode: 302, method: "GET")
        tracker.recordRedirect(taskId: taskId, from: url3, to: url4, statusCode: 307, method: "GET")
        tracker.recordRedirect(taskId: taskId, from: url4, to: url1, statusCode: 308, method: "GET")

        let chain = tracker.consumeChain(taskId: taskId)
        XCTAssertEqual(chain.count, 3)
        XCTAssertEqual(chain[0].from, url1)
        XCTAssertEqual(chain[2].to, url4)
    }
}
