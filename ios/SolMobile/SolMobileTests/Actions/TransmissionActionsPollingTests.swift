//
//  TransmissionActionsPollingTests.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import XCTest
import SwiftData
@testable import SolMobile

@MainActor
final class TransmissionActionsPollingTests: SwiftDataTestBase {

    // Transport that returns 202 first, then completes via poll.
    private struct MockPendingThenPollTransport: ChatTransportPolling {
        let txId: String = "tx-pending-1"

        func send(envelope: PacketEnvelope, diagnostics: DiagnosticsContext? = nil) async throws -> ChatResponse {
            return ChatResponse(
                text: "",
                statusCode: 202,
                transmissionId: txId,
                pending: true,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        func poll(transmissionId: String, diagnostics: DiagnosticsContext? = nil) async throws -> ChatPollResponse {
            XCTAssertEqual(transmissionId, txId)

            return ChatPollResponse(
                pending: false,
                assistant: "done",
                serverStatus: "completed",
                statusCode: 200,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }
    }

    private struct MockPollCompletesTransport: ChatTransportPolling {
        func send(envelope: PacketEnvelope, diagnostics: DiagnosticsContext? = nil) async throws -> ChatResponse {
            return ChatResponse(
                text: "",
                statusCode: 202,
                transmissionId: "tx-any",
                pending: true,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        func poll(transmissionId: String, diagnostics: DiagnosticsContext? = nil) async throws -> ChatPollResponse {
            return ChatPollResponse(
                pending: false,
                assistant: "done",
                serverStatus: "completed",
                statusCode: 200,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }
    }

    // Transport that returns 202 but does NOT support polling.
    private struct MockPendingNoPollingTransport: ChatTransport {
        let txId: String = "tx-pending-nopoll"

        func send(envelope: PacketEnvelope, diagnostics: DiagnosticsContext? = nil) async throws -> ChatResponse {
            ChatResponse(
                text: "",
                statusCode: 202,
                transmissionId: txId,
                pending: true,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }
    }

    // Transport that returns 202, then poll keeps returning pending.
    private struct MockPendingThenPollStillPendingTransport: ChatTransportPolling {
        let txId: String = "tx-pending-still"

        func send(envelope: PacketEnvelope, diagnostics: DiagnosticsContext? = nil) async throws -> ChatResponse {
            ChatResponse(
                text: "",
                statusCode: 202,
                transmissionId: txId,
                pending: true,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        func poll(transmissionId: String, diagnostics: DiagnosticsContext? = nil) async throws -> ChatPollResponse {
            XCTAssertEqual(transmissionId, txId)

            return ChatPollResponse(
                pending: true,
                assistant: nil,
                serverStatus: "created",
                statusCode: 200,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }
    }

    // Transport that returns 202, then poll throws.
    private struct MockPendingThenPollThrowsTransport: ChatTransportPolling {
        let txId: String = "tx-pending-throw"

        func send(envelope: PacketEnvelope, diagnostics: DiagnosticsContext? = nil) async throws -> ChatResponse {
            ChatResponse(
                text: "",
                statusCode: 202,
                transmissionId: txId,
                pending: true,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        func poll(transmissionId: String, diagnostics: DiagnosticsContext? = nil) async throws -> ChatPollResponse {
            XCTAssertEqual(transmissionId, txId)
            throw TransportError.httpStatus(HTTPErrorInfo(code: 503, body: "unavailable"))
        }
    }

    private final class MockPendingThenPollTransientTransport: ChatTransportPolling {
        let txId: String = "tx-pending-transient"
        private var pollCalls: Int = 0

        func send(envelope: PacketEnvelope, diagnostics: DiagnosticsContext? = nil) async throws -> ChatResponse {
            ChatResponse(
                text: "",
                statusCode: 202,
                transmissionId: txId,
                pending: true,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        func poll(transmissionId: String, diagnostics: DiagnosticsContext? = nil) async throws -> ChatPollResponse {
            XCTAssertEqual(transmissionId, txId)
            pollCalls += 1

            if pollCalls == 1 {
                throw TransportError.httpStatus(HTTPErrorInfo(code: 503, body: "unavailable"))
            }

            return ChatPollResponse(
                pending: false,
                assistant: "done",
                serverStatus: "completed",
                statusCode: 200,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }
    }

    private actor CallRecorder {
        private(set) var sendCalls: Int = 0
        private(set) var sendAt: Date?
        private(set) var pollStartAt: Date?

        func recordSend() {
            sendCalls += 1
            if sendAt == nil {
                sendAt = Date()
            }
        }

        func recordPollStart() {
            if pollStartAt == nil {
                pollStartAt = Date()
            }
        }
    }

    private struct MockSlowPollTransport: ChatTransportPolling {
        let recorder: CallRecorder

        func send(envelope: PacketEnvelope, diagnostics: DiagnosticsContext? = nil) async throws -> ChatResponse {
            await recorder.recordSend()
            return ChatResponse(
                text: "ok",
                statusCode: 200,
                transmissionId: "tx-send",
                pending: false,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        func poll(transmissionId: String, diagnostics: DiagnosticsContext? = nil) async throws -> ChatPollResponse {
            await recorder.recordPollStart()
            try? await Task.sleep(nanoseconds: 200_000_000)

            return ChatPollResponse(
                pending: true,
                assistant: nil,
                serverStatus: "created",
                statusCode: 200,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }
    }

    private struct MockPollRecordingTransport: ChatTransportPolling {
        let recorder: CallRecorder

        func send(envelope: PacketEnvelope, diagnostics: DiagnosticsContext? = nil) async throws -> ChatResponse {
            XCTFail("send should not be called in poll-only test")
            return ChatResponse(
                text: "",
                statusCode: 200,
                transmissionId: "tx-unused",
                pending: false,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        func poll(transmissionId: String, diagnostics: DiagnosticsContext? = nil) async throws -> ChatPollResponse {
            await recorder.recordPollStart()
            return ChatPollResponse(
                pending: true,
                assistant: nil,
                serverStatus: "created",
                statusCode: 200,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
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

        // Send -> 202 => immediate poll => succeeds + appends assistant message.
        await actions.processQueue()

        guard let tx = TestFetch.fetchOne(Transmission.self, context),
              let t2 = TestFetch.fetchOne(ConversationThread.self, context) else {
            XCTFail("Expected Transmission + Thread after polling")
            return
        }

        TestAssert.transmissionStatus(.succeeded, tx)
        XCTAssertEqual(tx.deliveryAttempts.last?.outcome, .succeeded)
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

        // Send -> 202 => immediate poll attempt, but transport cannot poll => failed.
        await actions.processQueue()

        guard let tx1 = TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected a Transmission to exist")
            return
        }

        TestAssert.transmissionStatus(.failed, tx1)
        XCTAssertTrue((tx1.lastError ?? "").contains("poll"))
    }

    @MainActor
    func test_pending202_poll_pending_requeues_and_does_not_append_assistant() async {
        let transport = MockPendingThenPollStillPendingTransport()
        let actions = TransmissionActions(modelContext: context, transport: transport)

        let thread = SeedFactory.makeThread(context, title: "still-pending-thread")
        let user = SeedFactory.makeUserMessage(context, thread: thread, text: "/pending hello")

        SeedFactory.enqueueChat(actions, thread: thread, userMessage: user)

        // Pass 1: send -> 202 => poll returns pending again.
        await actions.processQueue()

        guard let tx1 = TestFetch.fetchOne(Transmission.self, context),
              let t2 = TestFetch.fetchOne(ConversationThread.self, context) else {
            XCTFail("Expected Transmission + Thread after poll")
            return
        }

        TestAssert.transmissionStatus(.pending, tx1)
        XCTAssertEqual(tx1.deliveryAttempts.last?.outcome, .pending)
        XCTAssertEqual(t2.messages.count, 1) // user only
    }

    @MainActor
    func test_pending202_poll_throw_requeues_and_records_failed_attempt() async {
        let transport = MockPendingThenPollThrowsTransport()
        let actions = TransmissionActions(modelContext: context, transport: transport)

        let thread = SeedFactory.makeThread(context, title: "poll-throws-thread")
        let user = SeedFactory.makeUserMessage(context, thread: thread, text: "/pending hello")

        SeedFactory.enqueueChat(actions, thread: thread, userMessage: user)

        // Pass 1: send -> 202 => poll throws => tx stays pending (retryable).
        await actions.processQueue()

        guard let tx = TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected a Transmission after polling")
            return
        }

        TestAssert.transmissionStatus(.pending, tx)
        XCTAssertEqual(tx.deliveryAttempts.last?.outcome, .failed)
        XCTAssertTrue((tx.lastError ?? "").count > 0)
    }

    @MainActor
    func test_pending202_poll_transient_error_recovers_and_completes() async {
        let transport = MockPendingThenPollTransientTransport()
        let actions = TransmissionActions(modelContext: context, transport: transport)

        let thread = SeedFactory.makeThread(context, title: "poll-transient-thread")
        let user = SeedFactory.makeUserMessage(context, thread: thread, text: "/pending hello")

        SeedFactory.enqueueChat(actions, thread: thread, userMessage: user)

        // Pass 1: send -> 202 => poll throws => stays pending (retryable).
        await actions.processQueue()

        guard let tx1 = TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected a Transmission after polling")
            return
        }

        TestAssert.transmissionStatus(.pending, tx1)

        if let lastPoll = tx1.deliveryAttempts.last {
            lastPoll.createdAt = Date().addingTimeInterval(-5)
            try? context.save()
        }

        // Pass 2: poll succeeds => should complete and append assistant.
        await actions.processQueue()

        guard let tx2 = TestFetch.fetchOne(Transmission.self, context),
              let t2 = TestFetch.fetchOne(ConversationThread.self, context) else {
            XCTFail("Expected Transmission + Thread after recovery poll")
            return
        }

        TestAssert.transmissionStatus(.succeeded, tx2)
        XCTAssertTrue(t2.messages.contains(where: { $0.creatorType == .assistant && $0.text == "done" }))
    }

    @MainActor
    func test_pending_survives_restart_and_resolves() async {
        let transport1 = MockPendingThenPollStillPendingTransport()
        let actions1 = TransmissionActions(modelContext: context, transport: transport1)

        let thread = SeedFactory.makeThread(context, title: "pending-restart-thread")
        let user = SeedFactory.makeUserMessage(context, thread: thread, text: "/pending hello")

        SeedFactory.enqueueChat(actions1, thread: thread, userMessage: user)

        await actions1.processQueue()

        guard let tx1 = TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected a Transmission after first pass")
            return
        }

        TestAssert.transmissionStatus(.pending, tx1)

        if let lastPoll = tx1.deliveryAttempts.last {
            lastPoll.createdAt = Date().addingTimeInterval(-5)
            try? context.save()
        }

        let restartContext = ModelContext(container)
        let transport2 = MockPollCompletesTransport()
        let actions2 = TransmissionActions(modelContext: restartContext, transport: transport2)

        await actions2.processQueue()

        guard let tx2 = TestFetch.fetchOne(Transmission.self, restartContext),
              let t2 = TestFetch.fetchOne(ConversationThread.self, restartContext) else {
            XCTFail("Expected Transmission + Thread after restart poll")
            return
        }

        TestAssert.transmissionStatus(.succeeded, tx2)
        XCTAssertTrue(t2.messages.contains(where: { $0.creatorType == .assistant && $0.text == "done" }))
    }

    @MainActor
    func test_send_first_avoids_slow_poll_blocking_send() async {
        let recorder = CallRecorder()
        let transport = MockSlowPollTransport(recorder: recorder)
        let actions = TransmissionActions(modelContext: context, transport: transport)

        let pendingThread = SeedFactory.makeThread(context, title: "slow-poll-thread")
        let pendingUser = SeedFactory.makeUserMessage(context, thread: pendingThread, text: "pending")
        let pendingPacket = Packet(threadId: pendingThread.id, messageIds: [pendingUser.id])
        context.insert(pendingPacket)
        let pendingTx = Transmission(packet: pendingPacket)
        pendingTx.status = .pending
        let pendingAttempt = DeliveryAttempt(
            createdAt: Date(),
            statusCode: 202,
            outcome: .pending,
            source: .send,
            errorMessage: nil,
            transmissionId: "tx-slow",
            transmission: pendingTx
        )
        pendingTx.deliveryAttempts.append(pendingAttempt)
        context.insert(pendingTx)
        context.insert(pendingAttempt)

        let queuedThread = SeedFactory.makeThread(context, title: "queued-thread")
        let queuedUser = SeedFactory.makeUserMessage(context, thread: queuedThread, text: "hello")
        SeedFactory.enqueueChat(actions, thread: queuedThread, userMessage: queuedUser)

        let task = Task {
            await actions.processQueue(pollLimit: 1, pollFirst: false)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        let sendCalls = await recorder.sendCalls
        XCTAssertEqual(sendCalls, 1, "Expected send to start before slow poll completes")

        await task.value
    }

    @MainActor
    func test_pendingLong_does_not_fail_terminally() async {
        // Arrange a pending Transmission with an old pending attempt that still has a server id.
        let transport = MockPendingThenPollStillPendingTransport()
        let actions = TransmissionActions(modelContext: context, transport: transport)

        let thread = SeedFactory.makeThread(context, title: "pending-long-thread")
        let user = SeedFactory.makeUserMessage(context, thread: thread, text: "hello")

        SeedFactory.enqueueChat(actions, thread: thread, userMessage: user)

        guard let tx = TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected a Transmission")
            return
        }

        let old = Date().addingTimeInterval(-120)
        let pending = DeliveryAttempt(
            createdAt: old,
            statusCode: 202,
            outcome: .pending,
            source: .send,
            errorMessage: nil,
            transmissionId: "tx-pending-still",
            transmission: tx
        )

        tx.deliveryAttempts.append(pending)
        context.insert(pending)
        tx.status = .pending

        // Act: processQueue should keep pending (no TTL failure).
        await actions.processQueue()

        guard let tx2 = TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected a Transmission after poll")
            return
        }

        TestAssert.transmissionStatus(.pending, tx2)
        XCTAssertEqual(tx2.deliveryAttempts.last?.outcome, .pending)
    }

    @MainActor
    func test_poll_backoff_skips_when_too_soon() async {
        let recorder = CallRecorder()
        let transport = MockPollRecordingTransport(recorder: recorder)
        let actions = TransmissionActions(modelContext: context, transport: transport)

        let thread = SeedFactory.makeThread(context, title: "poll-backoff-too-soon")
        let user = SeedFactory.makeUserMessage(context, thread: thread, text: "hello")

        let packet = Packet(threadId: thread.id, messageIds: [user.id], messageText: user.text)
        context.insert(packet)

        let tx = Transmission(packet: packet)
        tx.status = .pending

        let sendAttempt = DeliveryAttempt(
            createdAt: Date().addingTimeInterval(-6),
            statusCode: 202,
            outcome: .pending,
            source: .send,
            errorMessage: nil,
            transmissionId: "tx-backoff",
            transmission: tx
        )

        let pollAttempt = DeliveryAttempt(
            createdAt: Date(),
            statusCode: 200,
            outcome: .pending,
            source: .poll,
            errorMessage: nil,
            transmissionId: "tx-backoff",
            transmission: tx
        )

        tx.deliveryAttempts.append(sendAttempt)
        tx.deliveryAttempts.append(pollAttempt)
        context.insert(tx)
        context.insert(sendAttempt)
        context.insert(pollAttempt)
        try? context.save()

        await actions.processQueue()

        let pollStartAt = await recorder.pollStartAt
        XCTAssertNil(pollStartAt, "Expected poll to be skipped due to backoff")
    }

    @MainActor
    func test_poll_backoff_allows_after_wait() async {
        let recorder = CallRecorder()
        let transport = MockPollRecordingTransport(recorder: recorder)
        let actions = TransmissionActions(modelContext: context, transport: transport)

        let thread = SeedFactory.makeThread(context, title: "poll-backoff-ready")
        let user = SeedFactory.makeUserMessage(context, thread: thread, text: "hello")

        let packet = Packet(threadId: thread.id, messageIds: [user.id], messageText: user.text)
        context.insert(packet)

        let tx = Transmission(packet: packet)
        tx.status = .pending

        let sendAttempt = DeliveryAttempt(
            createdAt: Date().addingTimeInterval(-6),
            statusCode: 202,
            outcome: .pending,
            source: .send,
            errorMessage: nil,
            transmissionId: "tx-backoff-ready",
            transmission: tx
        )

        let pollAttempt = DeliveryAttempt(
            createdAt: Date().addingTimeInterval(-5),
            statusCode: 200,
            outcome: .pending,
            source: .poll,
            errorMessage: nil,
            transmissionId: "tx-backoff-ready",
            transmission: tx
        )

        tx.deliveryAttempts.append(sendAttempt)
        tx.deliveryAttempts.append(pollAttempt)
        context.insert(tx)
        context.insert(sendAttempt)
        context.insert(pollAttempt)
        try? context.save()

        await actions.processQueue()

        let pollStartAt = await recorder.pollStartAt
        XCTAssertNotNil(pollStartAt, "Expected poll to proceed after backoff window")
    }
}
