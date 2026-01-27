//
//  ChatResponseMessageIdTests.swift
//  SolMobileTests
//

import XCTest
@testable import SolMobile

@MainActor
final class ChatResponseMessageIdTests: XCTestCase {
    func test_response_decodesUserMessageIdFromMessageId() throws {
        let json = """
        {
          "ok": true,
          "assistant": "Hello",
          "message_id": "msg-123",
          "evidenceSummary": {
            "captures": 0,
            "supports": 0,
            "claims": 0,
            "warnings": 0
          }
        }
        """

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        XCTAssertEqual(decoded.userMessageId, "msg-123")
    }
}
