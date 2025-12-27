//
//  TransmissionActionsPollingTests.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import XCTest
import SwiftData
@testable import SolMobile

final class TransmissionActionsPollingTests: SwiftDataTestBase {

    // Transport that returns 202 first, then completes via poll.
    private struct MockPendingThenPollTransport: ChatTransportPolling {
        let txId: String = "tx-pending-1"

        func send(envelope: PacketEnvelope) async throws -> ChatResponse {
            return ChatResponse(
                text: "",
                statusCode: 202,
                transmissionId: txId,
                pending: true,
                threadMemento: nil
            )
        }

        func poll(transmissionId: String) async throws -> ChatPollResponse {
            XCTAssertEqual(transmissionId, txId)

            return ChatPollResponse(
                pending: false,
                assistant: "done",
                serverStatus: "completed",
                statusCode: 200,
                threadMemento: nil
            )
        }
    }

    @MainActor
    func test_pending202_then_poll_completes_and_appends_assistant() async {
        let transport = MockPendingThenPollTransport()
        let actions = TransmissionActions(modelContext: context, transport: transport)

        let thread = SeedFactory.makeThread(context, title: "poll-thread")
        let user = SeedFactory.makeUserMessage(context, thread: thread, text: "/pending hello")

        SeedFactory.enqueueChat(actions, thread: thread, userMessage: user)

        // First pass: send -> 202 => queued + pending attempt with server tx id.
        await actions.processQueue()

        guard let tx1 = SeedFactory.fetchFirstQueuedTransmission(context) ?? TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected a Transmission to exist")
            return
        }

        TestAssert.transmissionStatus(.queued, tx1)
        XCTAssertTrue(tx1.deliveryAttempts.count >= 1)
        XCTAssertEqual(tx1.deliveryAttempts.last?.outcome, .pending)
        XCTAssertEqual(tx1.deliveryAttempts.last?.transmissionId, transport.txId)

        // Second pass: sees pending+serverTxId => polls => succeeds + appends assistant message.
        await actions.processQueue()

        guard let tx2 = TestFetch.fetchOne(Transmission.self, context),
              let t2 = TestFetch.fetchOne(ConversationThread.self, context) else {
            XCTFail("Expected Transmission + Thread after polling")
            return
        }

        TestAssert.transmissionStatus(.succeeded, tx2)
        XCTAssertEqual(tx2.deliveryAttempts.last?.outcome, .succeeded)
        XCTAssertTrue(t2.messages.contains(where: { $0.creatorType == .assistant && $0.text == "done" }))
        XCTAssertEqual(t2.messages.count, 2) // user + assistant
    }
}
