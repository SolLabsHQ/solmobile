//
//  RetryPolicyTests.swift
//  SolMobileTests
//
//  Created by SolMobile Retry Policy Tests.
//

import XCTest
@testable import SolMobile

final class RetryPolicyTests: XCTestCase {
    func test_driverBlock422_isTerminal() {
        let body = #"{"error":"driver_block_enforcement_failed"}"#
        let decision = RetryPolicy.classify(
            statusCode: 422,
            body: body,
            headers: [:],
            error: nil
        )

        XCTAssertFalse(decision.retryable)
        XCTAssertEqual(decision.source, .httpStatus)
        XCTAssertEqual(decision.errorCode, "driver_block_enforcement_failed")
    }

    func test_422_parseFailure_defaultsTerminal() {
        let decision = RetryPolicy.classify(
            statusCode: 422,
            body: "not-json",
            headers: [:],
            error: nil
        )

        XCTAssertFalse(decision.retryable)
        XCTAssertEqual(decision.source, .httpStatus)
    }

    func test_429_isRetryable_andRespectsRetryAfter() {
        let decision = RetryPolicy.classify(
            statusCode: 429,
            body: #"{"error":"rate_limited"}"#,
            headers: ["retry-after": "5"],
            error: nil
        )

        XCTAssertTrue(decision.retryable)
        XCTAssertEqual(decision.source, .httpStatus)
        XCTAssertEqual(decision.retryAfterSeconds, 5)
    }

    func test_400_invalidRequest_isTerminalWithoutRetryableField() {
        let decision = RetryPolicy.classify(
            statusCode: 400,
            body: #"{"error":"invalid_request","details":{"foo":"bar"}}"#,
            headers: [:],
            error: nil
        )

        XCTAssertFalse(decision.retryable)
        XCTAssertEqual(decision.source, .parseFailedDefault)
        XCTAssertEqual(decision.errorCode, "invalid_request")
    }
}
