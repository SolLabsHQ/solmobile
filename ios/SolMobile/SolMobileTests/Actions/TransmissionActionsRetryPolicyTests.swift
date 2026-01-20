//
//  TransmissionActionsRetryPolicyTests.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//


//
//  TransmissionActionsRetryPolicyTests.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import XCTest
import SwiftData
@testable import SolMobile

/// Retry policy tests for `TransmissionActions.processQueue()`.
///
/// Covered:
/// - backoff (don’t resend too soon)
/// - max attempts terminal (too many attempts -> fail)
@MainActor
final class TransmissionActionsRetryPolicyTests: XCTestCase {

    // MARK: - Test harness

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // In-memory SwiftData container for fast, isolated tests.
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(
            for: ConversationThread.self,
                 Message.self,
                 Packet.self,
                 Transmission.self,
                 DeliveryAttempt.self,
            configurations: config
        )
        self.context = container.mainContext
    }

    override func tearDownWithError() throws {
        self.context = nil
        self.container = nil
        try super.tearDownWithError()
    }

    // MARK: - Local transport helpers

    private final class CountingTransport: ChatTransport {
        private(set) var sendCallCount: Int = 0
        private let handler: (PacketEnvelope) async throws -> ChatResponse

        init(handler: @escaping (PacketEnvelope) async throws -> ChatResponse) {
            self.handler = handler
        }

        func send(envelope: PacketEnvelope, diagnostics: DiagnosticsContext? = nil) async throws -> ChatResponse {
            sendCallCount += 1
            return try await handler(envelope)
        }
    }

    private func makeThreadAndUserMessage(text: String) -> (ConversationThread, Message) {
        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let user = Message(thread: thread, creatorType: .user, text: text)
        thread.messages.append(user)
        context.insert(user)

        return (thread, user)
    }

    private func fetchSingleTransmission() throws -> Transmission {
        let tx = try context.fetch(FetchDescriptor<Transmission>())
        XCTAssertEqual(tx.count, 1)
        return tx[0]
    }

    // MARK: - Tests

    func test_processQueue_respectsBackoff_doesNotSendTooSoon() async throws {
        // Arrange
        let transport = CountingTransport { _ in
            // If this gets called, we violated backoff.
            return ChatResponse(
                text: "ok",
                statusCode: 200,
                transmissionId: "tx-1",
                pending: false,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        let (thread, user) = makeThreadAndUserMessage(text: "hello")
        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user)

        // Seed a prior attempt “just now” so the next run is still inside the backoff window.
        let tx = try fetchSingleTransmission()

        let recentAttempt = DeliveryAttempt(
            createdAt: Date(),
            statusCode: 500,
            outcome: .failed,
            errorMessage: "boom",
            transmissionId: nil,
            transmission: tx
        )
        tx.deliveryAttempts.append(recentAttempt)
        context.insert(recentAttempt)

        // Ensure it stays eligible for processQueue() (queued).
        tx.status = .queued
        tx.lastError = nil
        try context.save()

        // Act
        await actions.processQueue()

        // Assert
        XCTAssertEqual(transport.sendCallCount, 0)

        let fresh = try fetchSingleTransmission()
        XCTAssertEqual(fresh.status, .queued)
        XCTAssertEqual(fresh.deliveryAttempts.count, 1)
    }

    func test_processQueue_respectsRetryAfterHeader() async throws {
        let transport = CountingTransport { _ in
            // If this gets called, we violated retry-after.
            return ChatResponse(
                text: "ok",
                statusCode: 200,
                transmissionId: "tx-1",
                pending: false,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        let (thread, user) = makeThreadAndUserMessage(text: "hello")
        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user)

        let tx = try fetchSingleTransmission()

        let retryAttempt = DeliveryAttempt(
            createdAt: Date(),
            statusCode: 429,
            outcome: .failed,
            errorMessage: "rate_limited",
            transmissionId: nil,
            retryableInferred: true,
            retryAfterSeconds: 60,
            finalURL: nil,
            transmission: tx
        )
        tx.deliveryAttempts.append(retryAttempt)
        context.insert(retryAttempt)

        tx.status = .queued
        tx.lastError = nil
        try context.save()

        await actions.processQueue()

        XCTAssertEqual(transport.sendCallCount, 0)

        let fresh = try fetchSingleTransmission()
        XCTAssertEqual(fresh.status, .queued)
    }

    func test_processQueue_ignores_poll_attempts_for_send_limits() async throws {
        // Arrange
        let transport = CountingTransport { _ in
            return ChatResponse(
                text: "ok",
                statusCode: 200,
                transmissionId: "tx-1",
                pending: false,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        let (thread, user) = makeThreadAndUserMessage(text: "hello")
        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user)

        let tx = try fetchSingleTransmission()

        // Seed 5 send attempts (below max), plus newer poll attempts that should not block sending.
        for i in 0..<5 {
            let a = DeliveryAttempt(
                createdAt: Date().addingTimeInterval(TimeInterval(-120 - i)),
                statusCode: 500,
                outcome: .failed,
                source: .send,
                errorMessage: "fail \(i)",
                transmissionId: nil,
                transmission: tx
            )
            tx.deliveryAttempts.append(a)
            context.insert(a)
        }

        for i in 0..<3 {
            let a = DeliveryAttempt(
                createdAt: Date().addingTimeInterval(TimeInterval(-i)),
                statusCode: 200,
                outcome: .pending,
                source: .poll,
                errorMessage: nil,
                transmissionId: "tx-poll",
                transmission: tx
            )
            tx.deliveryAttempts.append(a)
            context.insert(a)
        }

        tx.status = .queued
        try context.save()

        // Act
        await actions.processQueue()

        // Assert
        XCTAssertEqual(transport.sendCallCount, 1)

        let fresh = try fetchSingleTransmission()
        XCTAssertEqual(fresh.status, .succeeded)
    }

    func test_processQueue_maxAttempts_marksFailed_terminal() async throws {
        // Arrange
        let transport = CountingTransport { _ in
            // Max-attempts terminal should short-circuit before send.
            return ChatResponse(
                text: "ok",
                statusCode: 200,
                transmissionId: "tx-1",
                pending: false,
                responseInfo: nil,
                threadMemento: nil,
                evidenceSummary: nil,
                evidence: nil,
                evidenceWarnings: nil,
                outputEnvelope: nil
            )
        }

        let (thread, user) = makeThreadAndUserMessage(text: "hello")
        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user)

        let tx = try fetchSingleTransmission()

        // Seed attempts >= maxSendAttempts (= 6 in `TransmissionActions`).
        // Use older createdAt values so we don’t hit backoff logic first.
        for i in 0..<6 {
            let a = DeliveryAttempt(
                createdAt: Date().addingTimeInterval(TimeInterval(-120 - i)),
                statusCode: 500,
                outcome: .failed,
                errorMessage: "fail \(i)",
                transmissionId: nil,
                transmission: tx
            )
            tx.deliveryAttempts.append(a)
            context.insert(a)
        }

        tx.status = .queued
        try context.save()

        // Act
        await actions.processQueue()

        // Assert
        XCTAssertEqual(transport.sendCallCount, 0)

        let fresh = try fetchSingleTransmission()
        XCTAssertEqual(fresh.status, .failed)
        XCTAssertNotNil(fresh.lastError)
        XCTAssertTrue(fresh.lastError?.contains("Max retry attempts") == true)

        // Existing 6 + terminal attempt appended by processQueue().
        XCTAssertEqual(fresh.deliveryAttempts.count, 7)

        let last = fresh.deliveryAttempts.sorted(by: { $0.createdAt < $1.createdAt }).last
        XCTAssertEqual(last?.statusCode, -1)
        XCTAssertEqual(last?.outcome, .failed)
    }
}
