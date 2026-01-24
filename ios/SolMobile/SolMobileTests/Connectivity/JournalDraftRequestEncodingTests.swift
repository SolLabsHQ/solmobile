//
//  JournalDraftRequestEncodingTests.swift
//  SolMobileTests
//

import XCTest
@testable import SolMobile

@MainActor
final class JournalDraftRequestEncodingTests: XCTestCase {
    func test_journalDraftRequest_encodesCpbRefs() throws {
        let request = JournalDraftRequest(
            requestId: "req-1",
            threadId: "thread-1",
            mode: .assist,
            evidenceSpan: JournalEvidenceSpan(startMessageId: "msg-1", endMessageId: "msg-2"),
            cpbRefs: [JournalDraftCpbRef(cpbId: "cpb-1", type: .journalStyle)],
            preferences: nil
        )

        let data = try JSONEncoder().encode(request)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("cpbRefs"))
        XCTAssertTrue(json.contains("cpb-1"))
    }
}
