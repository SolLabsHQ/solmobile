//
//  JournalOfferDecodingTests.swift
//  SolMobileTests
//

import XCTest
@testable import SolMobile

final class JournalOfferDecodingTests: XCTestCase {
    func test_outputEnvelope_decodesJournalOfferCamelCase() throws {
        let json = """
        {
          "assistantText": "Hello",
          "meta": {
            "journalOffer": {
              "momentId": "m1",
              "momentType": "insight",
              "phase": "settled",
              "confidence": "high",
              "evidenceSpan": {
                "startMessageId": "msg-1",
                "endMessageId": "msg-2"
              },
              "offerEligible": true
            }
          }
        }
        """

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(OutputEnvelopeDTO.self, from: data)
        XCTAssertEqual(decoded.meta?.journalOffer?.momentId, "m1")
        XCTAssertEqual(decoded.meta?.journalOffer?.evidenceSpan.startMessageId, "msg-1")
        XCTAssertEqual(decoded.meta?.journalOffer?.offerEligible, true)
    }
}
