//
//  HealthCheckPolicyTests.swift
//  SolMobileTests
//

import XCTest
@testable import SolMobile

final class HealthCheckPolicyTests: XCTestCase {
    func testHealthCheckSuccessIncludesAny2xx() {
        XCTAssertTrue(HealthCheckPolicy.isSuccess(status: 200))
        XCTAssertTrue(HealthCheckPolicy.isSuccess(status: 204))
        XCTAssertFalse(HealthCheckPolicy.isSuccess(status: 404))
    }
}
