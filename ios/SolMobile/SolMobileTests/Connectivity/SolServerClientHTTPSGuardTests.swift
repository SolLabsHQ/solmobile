//
//  SolServerClientHTTPSGuardTests.swift
//  SolMobileTests
//
//  Created by SolMobile HTTPS Guard Tests.
//

import Foundation
import XCTest
@testable import SolMobile

@MainActor
final class SolServerClientHTTPSGuardTests: XCTestCase {
    func test_insecureBaseURL_isBlockedInStaging() async {
        AppEnvironment.override = .staging
        defer { AppEnvironment.override = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]

        let client = SolServerClient(
            baseURL: URL(string: "http://example.com")!,
            configuration: config
        )

        do {
            _ = try await client.chat(threadId: "t1", clientRequestId: "c1", message: "hi")
            XCTFail("Expected insecure base URL guard to throw")
        } catch TransportError.insecureBaseURL {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
