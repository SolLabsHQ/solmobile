//
//  TraceEventsEncodingTests.swift
//  SolMobileTests
//

import XCTest
@testable import SolMobile

final class TraceEventsEncodingTests: XCTestCase {
    func test_deviceMuseObservation_isMechanismOnly() throws {
        let observation = DeviceMuseObservation(
            observationId: "obs-1",
            ts: "2026-02-01T00:00:00.000Z",
            localUserUuid: "local-1",
            threadId: "thread-1",
            messageId: "msg-1",
            version: "device-muse-observation-v0.1",
            source: .appleIntelligence,
            detectedType: "unknown",
            intensity: 0.2,
            confidence: 0.1,
            phaseHint: nil
        )

        let data = try JSONEncoder().encode(observation)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("detectedType"))
        XCTAssertFalse(json.contains("text"))
        XCTAssertFalse(json.contains("context"))
        XCTAssertFalse(json.contains("evidenceSpan"))
    }

    func test_traceEventsRequest_encodesUnion() throws {
        let offerEvent = JournalOfferEvent(
            eventId: "event-1",
            eventType: .journalOfferShown,
            ts: "2026-02-01T00:00:00.000Z",
            threadId: "thread-1",
            momentId: "m1",
            evidenceSpan: JournalEvidenceSpan(startMessageId: "msg-1", endMessageId: "msg-2"),
            phaseAtOffer: "settled",
            modeSelected: nil,
            userAction: nil,
            cooldownActive: nil,
            latencyMs: nil,
            refs: nil,
            tuning: nil
        )

        let request = TraceEventsRequest(
            requestId: "req-1",
            localUserUuid: "local-1",
            events: [.journalOffer(offerEvent)]
        )

        let data = try JSONEncoder().encode(request)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("journal_offer_shown"))
        XCTAssertTrue(json.contains("localUserUuid"))
    }
}
