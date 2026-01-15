//
//  ThreadMementoDecisionTests.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import XCTest
import SwiftData
@testable import SolMobile

final class ThreadMementoDecisionTests: SwiftDataTestBase {

    // Async XCTAssertThrows helper for Swift concurrency tests.
    private func XCTAssertThrowsErrorAsync<T>(
        _ expression: @escaping () async throws -> T,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error to be thrown. \(message)", file: file, line: line)
        } catch {
            // Expected.
        }
    }

    private struct MockMementoDecisionTransport: ChatTransportMementoDecision, ChatTransport {
        var statusCode: Int = 200
        var applied: Bool = true
        var reason: String? = "applied"
        var returnedId: String = "memento-accepted-1"


        func send(envelope: PacketEnvelope) async throws -> ChatResponse {
            XCTFail("send(envelope:) should not be called in ThreadMementoDecisionTests")
            throw MockError.unexpectedSend
        }

        func decideMemento(threadId: String, mementoId: String, decision: ThreadMementoDecision) async throws -> ThreadMementoDecisionResult {
            // Server may return a different id on accept; your UI already handles that.
            let memento = ThreadMementoDTO(
                id: returnedId,
                threadId: threadId,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                version: "memento-v0",
                arc: "Arc",
                active: [],
                parked: [],
                decisions: [],
                next: []
            )

            return ThreadMementoDecisionResult(
                statusCode: statusCode,
                applied: applied,
                reason: reason,
                memento: memento
            )
        }
    }

    private struct MockChatTransportOnly: ChatTransport {
        func send(envelope: PacketEnvelope) async throws -> ChatResponse {
            // Not used for these tests.
            return ChatResponse(
                text: "ok",
                statusCode: 200,
                transmissionId: "tx-1",
                pending: false,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil
            )
        }
    }

    @MainActor
    func test_accept_clears_local_draft_fields_for_matching_transmissions() async throws {
        let transport = MockMementoDecisionTransport()
        let actions = TransmissionActions(modelContext: context, transport: transport)

        // Seed a thread + a tx with a serverThreadMementoId.
        let thread = SeedFactory.makeThread(context, title: "memento-thread")
        let user = SeedFactory.makeUserMessage(context, thread: thread, text: "hello")
        actions.enqueueChat(thread: thread, userMessage: user)

        guard let tx = TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected Transmission")
            return
        }

        tx.serverThreadMementoId = "draft-123"
        tx.serverThreadMementoCreatedAtISO = "2025-01-01T00:00:00.000Z"
        tx.serverThreadMementoSummary = "Arc: test"

        try context.save()

        // Act
        let result = try await actions.decideThreadMemento(
            threadId: thread.id,
            mementoId: "draft-123",
            decision: .accept
        )

        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.reason ?? "", "applied")

        // Assert local draft cleared so banner can disappear immediately.
        let fresh = try XCTUnwrap(TestFetch.fetchOne(Transmission.self, context))
        XCTAssertNil(fresh.serverThreadMementoId)
        XCTAssertNil(fresh.serverThreadMementoCreatedAtISO)
        XCTAssertNil(fresh.serverThreadMementoSummary)
    }

    @MainActor
    func test_revoke_clears_local_draft_fields_for_matching_transmissions() async throws {
        var transport = MockMementoDecisionTransport()
        transport.applied = true
        transport.reason = "applied"

        let actions = TransmissionActions(modelContext: context, transport: transport)

        // Seed a thread + a tx with a serverThreadMementoId.
        let thread = SeedFactory.makeThread(context, title: "memento-thread")
        let user = SeedFactory.makeUserMessage(context, thread: thread, text: "hello")
        actions.enqueueChat(thread: thread, userMessage: user)

        guard let tx = TestFetch.fetchOne(Transmission.self, context) else {
            XCTFail("Expected Transmission")
            return
        }

        tx.serverThreadMementoId = "draft-456"
        tx.serverThreadMementoCreatedAtISO = "2025-01-01T00:00:00.000Z"
        tx.serverThreadMementoSummary = "Arc: test"

        try context.save()

        // Act
        let result = try await actions.decideThreadMemento(
            threadId: thread.id,
            mementoId: "draft-456",
            decision: .revoke
        )

        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.reason ?? "", "applied")

        // Assert local draft cleared so banner can disappear immediately.
        let fresh = try XCTUnwrap(TestFetch.fetchOne(Transmission.self, context))
        XCTAssertNil(fresh.serverThreadMementoId)
        XCTAssertNil(fresh.serverThreadMementoCreatedAtISO)
        XCTAssertNil(fresh.serverThreadMementoSummary)
    }

    @MainActor
    func test_decideThreadMemento_unsupportedTransport_throws() async {
        let transport = MockChatTransportOnly()
        let actions = TransmissionActions(modelContext: context, transport: transport)

        let thread = SeedFactory.makeThread(context, title: "memento-thread")

        await XCTAssertThrowsErrorAsync({
            _ = try await actions.decideThreadMemento(
                threadId: thread.id,
                mementoId: "draft-789",
                decision: .accept
            )
        }, "Transport does not support memento decisions")
    }
}
