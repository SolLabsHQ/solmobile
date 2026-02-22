//
//  TransmissionActionsTests.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import Foundation
import XCTest
import SwiftData
@testable import SolMobile

@MainActor
final class TransmissionActionsTests: SwiftDataTestBase {
    private actor SendFlag {
        private var value = false

        func set() {
            value = true
        }

        func get() -> Bool {
            value
        }
    }

    private actor CapturedEnvelopeStore {
        private var envelope: PacketEnvelope?

        func set(_ envelope: PacketEnvelope) {
            self.envelope = envelope
        }

        func get() -> PacketEnvelope? {
            envelope
        }
    }
    @MainActor
    private final class TestTransport: ChatTransport {
        private let handler: @Sendable (PacketEnvelope) async throws -> ChatResponse

        init(_ handler: @escaping @Sendable (PacketEnvelope) async throws -> ChatResponse) {
            self.handler = handler
        }

        func send(envelope: PacketEnvelope, diagnostics: DiagnosticsContext? = nil) async throws -> ChatResponse {
            try await handler(envelope)
        }
    }

    override func setUp() {
        super.setUp()
        BudgetStore.shared.resetForTests()
    }

    func test_memoryDistill_bypassesMissingText_andSends() async throws {
        let transport = FakeTransport()
        transport.nextSend = {
            ChatResponse(
                text: "",
                statusCode: 202,
                transmissionId: "tx-distill",
                pending: true,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let user = Message(thread: thread, creatorType: .user, text: "hello")
        thread.messages.append(user)
        context.insert(user)

        let item = MemoryContextItem(
            messageId: user.id.uuidString,
            role: "user",
            content: user.text,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        let request = MemoryDistillRequest(
            threadId: thread.id.uuidString,
            triggerMessageId: user.id.uuidString,
            contextWindow: [item],
            requestId: "mem:thread:\(thread.id.uuidString)",
            reaffirmCount: 0,
            consent: MemoryConsent(explicitUserConsent: true)
        )

        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueMemoryDistill(
            threadId: thread.id,
            messageIds: [user.id],
            payload: request
        )

        await actions.processQueue()

        XCTAssertEqual(transport.sendCalls.count, 1)
        XCTAssertEqual(transport.sendCalls.first?.envelope.packetType, "memory_distill")

        let allTx = try context.fetch(FetchDescriptor<Transmission>())
        XCTAssertEqual(allTx.count, 1)
        XCTAssertTrue([.pending, .succeeded].contains(allTx[0].status))
        XCTAssertNil(allTx[0].lastError)
    }

    func test_processQueue_success_marksSucceeded_andAppendsAssistant() async throws {
        // Arrange
        let transport = FakeTransport()
        transport.nextSend = {
            ChatResponse(
                text: "hello from server",
                statusCode: 200,
                transmissionId: "tx123",
                pending: false,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let user = Message(thread: thread, creatorType: .user, text: "hi")
        thread.messages.append(user)
        context.insert(user)

        let draft = DraftRecord(threadId: thread.id.uuidString, content: "draft")
        context.insert(draft)

        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user)

        // Act
        await actions.processQueue()

        // Assert
        let allTx = try context.fetch(FetchDescriptor<Transmission>())
        XCTAssertEqual(allTx.count, 1)
        XCTAssertEqual(allTx[0].status, .succeeded)

        XCTAssertTrue(thread.messages.contains(where: { $0.creatorType == .assistant }))

        let drafts = try context.fetch(FetchDescriptor<DraftRecord>())
        XCTAssertTrue(drafts.isEmpty)
    }

    func test_processQueue_http500_requeues_recordsAttempt_andDoesNotAppendAssistant() async throws {
        // Arrange
        let transport = TestTransport { _ in
            throw TransportError.httpStatus(HTTPErrorInfo(code: 500, body: "boom"))
        }

        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let user = Message(thread: thread, creatorType: .user, text: "hi")
        thread.messages.append(user)
        context.insert(user)

        let draft = DraftRecord(threadId: thread.id.uuidString, content: "draft")
        context.insert(draft)

        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user)

        // Act
        await actions.processQueue()

        // Assert
        let allTx = try context.fetch(FetchDescriptor<Transmission>())
        XCTAssertEqual(allTx.count, 1)

        let tx = allTx[0]
        XCTAssertEqual(tx.status, .queued)
        XCTAssertTrue((tx.lastError ?? "").contains("boom"))

        // Attempt ledger should record the failure.
        let attempts = tx.deliveryAttempts.sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts[0].statusCode, 500)
        XCTAssertEqual(attempts[0].outcome, .failed)

        // No assistant message should be appended on failure.
        XCTAssertFalse(thread.messages.contains(where: { $0.creatorType == .assistant }))

        let drafts = try context.fetch(FetchDescriptor<DraftRecord>())
        XCTAssertEqual(drafts.count, 1)
    }

    func test_enqueueChat_skipsWhenMessageMissing() async throws {
        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let actions = TransmissionActions(modelContext: context, transport: FakeTransport())
        actions.enqueueChat(threadId: thread.id, messageId: UUID())

        let allTx = try context.fetch(FetchDescriptor<Transmission>())
        XCTAssertTrue(allTx.isEmpty)
    }

    func test_processQueue_dedupesAssistantByServerMessageId() async throws {
        let transport = FakeTransport()
        transport.nextSend = {
            ChatResponse(
                text: "updated response",
                statusCode: 200,
                transmissionId: "tx-dup",
                pending: false,
                responseInfo: nil,
                assistantMessageId: "assistant-1",
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let user = Message(thread: thread, creatorType: .user, text: "hi")
        thread.messages.append(user)
        context.insert(user)

        let assistant = Message(thread: thread, creatorType: .assistant, text: "old response")
        assistant.serverMessageId = "assistant-1"
        thread.messages.append(assistant)
        context.insert(assistant)

        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user)

        await actions.processQueue()

        let assistants = thread.messages.filter { $0.creatorType == .assistant }
        XCTAssertEqual(assistants.count, 1)
        XCTAssertEqual(assistants.first?.text, "updated response")

        let uniqueIds = Set(thread.messages.map { $0.id })
        XCTAssertEqual(uniqueIds.count, thread.messages.count)
    }

    func test_terminalFailure_doesNotBlockLaterQueued_transmission() async throws {
        let transport = TestTransport { _ in
            return ChatResponse(
                text: "ok",
                statusCode: 200,
                transmissionId: "tx-ok",
                pending: false,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let user1 = Message(thread: thread, creatorType: .user, text: "first")
        let user2 = Message(thread: thread, creatorType: .user, text: "second")
        thread.messages.append(user1)
        thread.messages.append(user2)
        context.insert(user1)
        context.insert(user2)

        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user1)
        actions.enqueueChat(thread: thread, userMessage: user2)

        let allTx = try context.fetch(FetchDescriptor<Transmission>())
        XCTAssertEqual(allTx.count, 2)

        let sorted = allTx.sorted { $0.createdAt < $1.createdAt }
        let first = sorted[0]
        let second = sorted[1]

        first.status = .failed
        first.lastError = "terminal_error"
        second.status = .queued

        try context.save()

        await actions.processQueue()

        let updated = try context.fetch(FetchDescriptor<Transmission>()).sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(updated[0].status, .failed)
        XCTAssertEqual(updated[1].status, .succeeded)
    }

    func test_staleSending_requeues_and_sends() async throws {
        let didSend = SendFlag()
        let transport = TestTransport { _ in
            await didSend.set()
            return ChatResponse(
                text: "ok",
                statusCode: 200,
                transmissionId: "tx-ok",
                pending: false,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let user = Message(thread: thread, creatorType: .user, text: "hello")
        thread.messages.append(user)
        context.insert(user)

        let packet = Packet(threadId: thread.id, messageIds: [user.id], messageText: user.text)
        context.insert(packet)

        let tx = Transmission(packet: packet)
        tx.status = .sending
        tx.createdAt = Date().addingTimeInterval(-120)
        context.insert(tx)
        try context.save()

        let actions = TransmissionActions(modelContext: context, transport: transport)
        await actions.processQueue()

        let didSendValue = await didSend.get()
        XCTAssertTrue(didSendValue)

        let fresh = try context.fetch(FetchDescriptor<Transmission>()).first
        XCTAssertEqual(fresh?.status, .succeeded)
    }

    func test_retryFailed_flipsChatFailToChat_requeues_andThenSucceeds() async throws {
        // Arrange
        let transport = TestTransport { envelope in
            // First pass should be chat_fail and throw.
            if envelope.packetType == "chat_fail" {
                throw TransportError.httpStatus(
                    HTTPErrorInfo(code: 422, body: "{\"error\":\"driver_block_enforcement_failed\"}")
                )
            }

            // After retryFailed(), packetType should be flipped to chat and succeed.
            return ChatResponse(
                text: "ok after retry",
                statusCode: 200,
                transmissionId: "tx-retry",
                pending: false,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let user = Message(thread: thread, creatorType: .user, text: "/fail please")
        thread.messages.append(user)
        context.insert(user)

        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user)

        // Act 1: fail
        await actions.processQueue()

        // Assert 1
        var allTx = try context.fetch(FetchDescriptor<Transmission>())
        XCTAssertEqual(allTx.count, 1)
        XCTAssertEqual(allTx[0].status, .failed)
        XCTAssertEqual(allTx[0].packet.packetType, "chat_fail")

        // Act 2: retry flips packetType and requeues
        actions.retryFailed()

        allTx = try context.fetch(FetchDescriptor<Transmission>())
        XCTAssertEqual(allTx[0].status, .queued)
        XCTAssertEqual(allTx[0].packet.packetType, "chat")

        // Option A: bypass exponential backoff in unit tests by aging the last attempt.
        // processQueue() respects backoff based on the timestamp of the last DeliveryAttempt.
        if let lastAttempt = allTx[0].deliveryAttempts.sorted(by: { $0.createdAt < $1.createdAt }).last {
            lastAttempt.createdAt = Date().addingTimeInterval(-60)
            try context.save()
        }

        // Act 3: succeeds
        await actions.processQueue()

        // Assert 3
        allTx = try context.fetch(FetchDescriptor<Transmission>())
        XCTAssertEqual(allTx[0].status, .succeeded)
        XCTAssertTrue(thread.messages.contains(where: { $0.creatorType == .assistant && $0.text.contains("ok after retry") }))
    }

    func test_budgetExceeded_blocksAndPersists() async throws {
        // Arrange
        let transport = TestTransport { _ in
            throw TransportError.httpStatus(HTTPErrorInfo(code: 422, body: "{\"error\":\"budget_exceeded\"}"))
        }

        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let user = Message(thread: thread, creatorType: .user, text: "hi")
        thread.messages.append(user)
        context.insert(user)

        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user)

        // Act
        await actions.processQueue()

        // Assert
        XCTAssertTrue(BudgetStore.shared.state.isBlocked)
        XCTAssertNotNil(BudgetStore.shared.state.lastUpdatedAt)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "solserver.budget.isBlocked"))

        let allTx = try context.fetch(FetchDescriptor<Transmission>())
        XCTAssertEqual(allTx.count, 1)
        XCTAssertEqual(allTx[0].status, .failed)
        XCTAssertTrue((allTx[0].lastError ?? "").contains("budget_exceeded"))
    }

    func test_blockedState_preventsSend() async throws {
        // Arrange
        BudgetStore.shared.applyBudgetExceeded(blockedUntil: nil)
        let didSend = SendFlag()
        let transport = TestTransport { _ in
            await didSend.set()
            return ChatResponse(
                text: "should not send",
                statusCode: 200,
                transmissionId: "tx",
                pending: false,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let user = Message(thread: thread, creatorType: .user, text: "hi")
        thread.messages.append(user)
        context.insert(user)

        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user)

        // Act
        await actions.processQueue()

        // Assert
        let didSendValue = await didSend.get()
        XCTAssertFalse(didSendValue)
        let allTx = try context.fetch(FetchDescriptor<Transmission>())
        XCTAssertEqual(allTx.count, 1)
        XCTAssertEqual(allTx[0].status, .failed)
    }

    func test_blockedUntil_past_unblocks() {
        // Arrange
        BudgetStore.shared.applyBudgetExceeded(blockedUntil: Date().addingTimeInterval(-60))

        // Act
        let isBlocked = BudgetStore.shared.isBlockedNow()

        // Assert
        XCTAssertFalse(isBlocked)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "solserver.budget.isBlocked"))
    }

    func test_budgetState_persistsAcrossReload() {
        // Arrange
        BudgetStore.shared.applyBudgetExceeded(blockedUntil: nil)

        // Act
        BudgetStore.shared.reload()

        // Assert
        XCTAssertTrue(BudgetStore.shared.state.isBlocked)
    }

    func test_sendOnce_prefersStructuredThreadMemento_overSummaryFallback() async throws {
        let sentEnvelope = CapturedEnvelopeStore()
        let transport = TestTransport { envelope in
            await sentEnvelope.set(envelope)
            return ChatResponse(
                text: "ok",
                statusCode: 200,
                transmissionId: "tx-prefer-structured",
                pending: false,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let priorPacket = Packet(threadId: thread.id, messageIds: [], messageText: "")
        context.insert(priorPacket)

        let priorTx = Transmission(packet: priorPacket)
        priorTx.status = .succeeded
        priorTx.serverThreadMementoId = "m-structured"
        priorTx.serverThreadMementoCreatedAtISO = "2026-02-20T00:00:00Z"
        priorTx.serverThreadMementoSummary = """
        Arc: Summary Arc
        Active: summary-active
        Parked: (none)
        Decisions: (none)
        Next: (none)
        """
        priorTx.serverThreadMementoPayloadJSON = """
        {"id":"m-structured","threadId":"\(thread.id.uuidString)","createdAt":"2026-02-20T00:00:00Z","version":"memento-v0.2","arc":"Structured Arc","active":["structured-active"],"parked":[],"decisions":[],"next":[]}
        """
        context.insert(priorTx)

        let user = Message(thread: thread, creatorType: .user, text: "hello")
        thread.messages.append(user)
        context.insert(user)
        try context.save()

        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user)
        await actions.processQueue()

        let capturedEnvelope = await sentEnvelope.get()
        let envelope = try XCTUnwrap(capturedEnvelope)
        let memento = try XCTUnwrap(envelope.threadMemento)
        XCTAssertEqual(memento.arc, "Structured Arc")
        XCTAssertEqual(memento.active, ["structured-active"])
    }

    func test_sendOnce_fallsBackToSummary_whenStructuredPayloadMalformed() async throws {
        let sentEnvelope = CapturedEnvelopeStore()
        let transport = TestTransport { envelope in
            await sentEnvelope.set(envelope)
            return ChatResponse(
                text: "ok",
                statusCode: 200,
                transmissionId: "tx-fallback-summary",
                pending: false,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let priorPacket = Packet(threadId: thread.id, messageIds: [], messageText: "")
        context.insert(priorPacket)

        let priorTx = Transmission(packet: priorPacket)
        priorTx.status = .succeeded
        priorTx.serverThreadMementoId = "m-summary"
        priorTx.serverThreadMementoCreatedAtISO = "2026-02-20T00:00:00Z"
        priorTx.serverThreadMementoPayloadJSON = "{bad-json"
        priorTx.serverThreadMementoSummary = """
        Arc: Summary Arc
        Active: one | two
        Parked: parked-one
        Decisions: keep-summary
        Next: next-item
        """
        context.insert(priorTx)

        let user = Message(thread: thread, creatorType: .user, text: "hello")
        thread.messages.append(user)
        context.insert(user)
        try context.save()

        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user)
        await actions.processQueue()

        let capturedEnvelope = await sentEnvelope.get()
        let envelope = try XCTUnwrap(capturedEnvelope)
        let memento = try XCTUnwrap(envelope.threadMemento)
        XCTAssertEqual(memento.arc, "Summary Arc")
        XCTAssertEqual(memento.active, ["one", "two"])
        XCTAssertEqual(memento.parked, ["parked-one"])
    }

    func test_sendOnce_omitsThreadMemento_whenNoStructuredOrParsableSummary() async throws {
        let sentEnvelope = CapturedEnvelopeStore()
        let transport = TestTransport { envelope in
            await sentEnvelope.set(envelope)
            return ChatResponse(
                text: "ok",
                statusCode: 200,
                transmissionId: "tx-omit-context",
                pending: false,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let priorPacket = Packet(threadId: thread.id, messageIds: [], messageText: "")
        context.insert(priorPacket)

        let priorTx = Transmission(packet: priorPacket)
        priorTx.status = .succeeded
        priorTx.serverThreadMementoId = "m-garbage"
        priorTx.serverThreadMementoCreatedAtISO = "2026-02-20T00:00:00Z"
        priorTx.serverThreadMementoPayloadJSON = "{bad-json"
        priorTx.serverThreadMementoSummary = "not parseable as formatter output"
        context.insert(priorTx)

        let user = Message(thread: thread, creatorType: .user, text: "hello")
        thread.messages.append(user)
        context.insert(user)
        try context.save()

        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user)
        await actions.processQueue()

        let capturedEnvelope = await sentEnvelope.get()
        let envelope = try XCTUnwrap(capturedEnvelope)
        XCTAssertNil(envelope.threadMemento)
    }
}
