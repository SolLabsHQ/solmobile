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
    private final class TestTransport: ChatTransport {
        private let handler: (PacketEnvelope) async throws -> ChatResponse

        init(_ handler: @escaping (PacketEnvelope) async throws -> ChatResponse) {
            self.handler = handler
        }

        func send(envelope: PacketEnvelope) async throws -> ChatResponse {
            try await handler(envelope)
        }
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
        let allTx = try context.fetch(FetchDescriptor<Transmission>())
        XCTAssertEqual(allTx.count, 1)
        XCTAssertEqual(allTx[0].status, .succeeded)

        XCTAssertTrue(thread.messages.contains(where: { $0.creatorType == .assistant }))
    }

    func test_processQueue_http500_marksFailed_recordsAttempt_andDoesNotAppendAssistant() async throws {
        // Arrange
        let transport = TestTransport { _ in
            throw TransportError.httpStatus(code: 500, body: "boom")
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
        let allTx = try context.fetch(FetchDescriptor<Transmission>())
        XCTAssertEqual(allTx.count, 1)

        let tx = allTx[0]
        XCTAssertEqual(tx.status, .failed)
        XCTAssertTrue((tx.lastError ?? "").contains("boom"))

        // Attempt ledger should record the failure.
        let attempts = tx.deliveryAttempts.sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts[0].statusCode, 500)
        XCTAssertEqual(attempts[0].outcome, .failed)

        // No assistant message should be appended on failure.
        XCTAssertFalse(thread.messages.contains(where: { $0.creatorType == .assistant }))
    }

    func test_retryFailed_flipsChatFailToChat_requeues_andThenSucceeds() async throws {
        // Arrange
        let transport = TestTransport { envelope in
            // First pass should be chat_fail and throw.
            if envelope.packetType == "chat_fail" {
                throw TransportError.simulatedFailure
            }

            // After retryFailed(), packetType should be flipped to chat and succeed.
            return ChatResponse(
                text: "ok after retry",
                statusCode: 200,
                transmissionId: "tx-retry",
                pending: false,
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
}
