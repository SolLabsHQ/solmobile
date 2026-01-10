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

    // Transport that returns 202 but does NOT support polling.
    private struct MockPendingNoPollingTransport: ChatTransport {
        let txId: String = "tx-pending-nopoll"

        func send(envelope: PacketEnvelope) async throws -> ChatResponse {
            ChatResponse(
                text: "",
                statusCode: 202,
                transmissionId: txId,
                pending: true,
                threadMemento: nil
            )
        }
    }

    // Transport that returns 202, then poll keeps returning pending.
    private struct MockPendingThenPollStillPendingTransport: ChatTransportPolling {
        let txId: String = "tx-pending-still"

        func send(envelope: PacketEnvelope) async throws -> ChatResponse {
            ChatResponse(
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
                pending: true,
                assistant: nil,
                serverStatus: "created",
                statusCode: 200,
                threadMemento: nil
            )
        }
    }

    // Transport that returns 202, then poll throws.
    private struct MockPendingThenPollThrowsTransport: ChatTransportPolling {
        let txId: String = "tx-pending-throw"

        func send(envelope: PacketEnvelope) async throws -> ChatResponse {
            ChatResponse(
                text: "",
                statusCode: 202,
                transmissionId: txId,
                pending: true,
                threadMemento: nil
            )
        }

        func poll(transmissionId: String) async throws -> ChatPollResponse {
            XCTAssertEqual(transmissionId, txId)
            throw TransportError.httpStatus(code: 503, body: "unavailable")
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

    @MainActor
    func test_pending202_withoutPollingCapability_marks_failed_on_second_pass() async {
        let transport = MockPendingNoPollingTransport()
        let actions = TransmissionActions(modelContext: context, transport: transport)

        let thread = SeedFactory.makeThread(context, title: "nopoll-thread")
        let user = SeedFactory.makeUserMessage(context, thread: thread, text: "/pending hello")

        SeedFactory.enqueueChat(actions, thread: thread, userMessage: user)

        // First pass: send -> 202 => queued + pending attempt with server tx id.
        await actions.processQueue()

        guard let tx1 = TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected a Transmission to exist")
            return
        }

        TestAssert.transmissionStatus(.queued, tx1)
        XCTAssertEqual(tx1.deliveryAttempts.last?.outcome, .pending)
        XCTAssertEqual(tx1.deliveryAttempts.last?.transmissionId, transport.txId)

        // Second pass: queue sees pending+serverTxId but transport cannot poll => failed.
        await actions.processQueue()

        guard let tx2 = TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected a Transmission after second pass")
            return
        }

        TestAssert.transmissionStatus(.failed, tx2)
        XCTAssertTrue((tx2.lastError ?? "").contains("poll"))
    }

    @MainActor
    func test_pending202_poll_pending_requeues_and_does_not_append_assistant() async {
        let transport = MockPendingThenPollStillPendingTransport()
        let actions = TransmissionActions(modelContext: context, transport: transport)

        let thread = SeedFactory.makeThread(context, title: "still-pending-thread")
        let user = SeedFactory.makeUserMessage(context, thread: thread, text: "/pending hello")

        SeedFactory.enqueueChat(actions, thread: thread, userMessage: user)

        // Pass 1: 202 pending.
        await actions.processQueue()

        guard let tx1 = TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected a Transmission to exist")
            return
        }

        TestAssert.transmissionStatus(.queued, tx1)
        XCTAssertEqual(tx1.deliveryAttempts.last?.outcome, .pending)
        XCTAssertEqual(tx1.deliveryAttempts.last?.transmissionId, transport.txId)

        // Pass 2: poll returns pending again => stays queued and no assistant appended.
        await actions.processQueue()

        guard let tx2 = TestFetch.fetchOne(Transmission.self, context),
              let t2 = TestFetch.fetchOne(ConversationThread.self, context) else {
            XCTFail("Expected Transmission + Thread after poll")
            return
        }

        TestAssert.transmissionStatus(.queued, tx2)
        XCTAssertEqual(tx2.deliveryAttempts.last?.outcome, .pending)
        XCTAssertEqual(t2.messages.count, 1) // user only
    }

    @MainActor
    func test_pending202_poll_throw_marks_failed_and_records_failed_attempt() async {
        let transport = MockPendingThenPollThrowsTransport()
        let actions = TransmissionActions(modelContext: context, transport: transport)

        let thread = SeedFactory.makeThread(context, title: "poll-throws-thread")
        let user = SeedFactory.makeUserMessage(context, thread: thread, text: "/pending hello")

        SeedFactory.enqueueChat(actions, thread: thread, userMessage: user)

        // Pass 1: 202 pending.
        await actions.processQueue()

        // Pass 2: poll throws => tx failed.
        await actions.processQueue()

        guard let tx = TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected a Transmission after polling")
            return
        }

        TestAssert.transmissionStatus(.failed, tx)
        XCTAssertEqual(tx.deliveryAttempts.last?.outcome, .failed)
        XCTAssertTrue((tx.lastError ?? "").count > 0)
    }

    @MainActor
    func test_pendingTTL_exceeded_marks_failed_without_calling_transport() async {
        // Arrange a queued Transmission with an old pending attempt that has no server transmissionId.
        let transport = MockPendingNoPollingTransport()
        let actions = TransmissionActions(modelContext: context, transport: transport)

        let thread = SeedFactory.makeThread(context, title: "ttl-thread")
        let user = SeedFactory.makeUserMessage(context, thread: thread, text: "hello")

        SeedFactory.enqueueChat(actions, thread: thread, userMessage: user)

        guard let tx = TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected a Transmission")
            return
        }

        // Force an old pending streak with no server transmission id so we hit the TTL path.
        let old = Date().addingTimeInterval(-60)
        let pending = DeliveryAttempt(
            createdAt: old,
            statusCode: 202,
            outcome: .pending,
            errorMessage: nil,
            transmissionId: nil,
            transmission: tx
        )

        tx.deliveryAttempts.append(pending)
        context.insert(pending)
        tx.status = .queued

        // Act: processQueue should terminal-fail on TTL without attempting send.
        await actions.processQueue()

        guard let tx2 = TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected a Transmission after TTL check")
            return
        }

        TestAssert.transmissionStatus(.failed, tx2)
        XCTAssertEqual(tx2.deliveryAttempts.last?.outcome, .failed)
        XCTAssertEqual(tx2.deliveryAttempts.last?.statusCode, 408)
    }
}
