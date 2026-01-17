//
//  FakeTransport.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import Foundation
@testable import SolMobile

final class FakeTransport: ChatTransport, ChatTransportPolling, ChatTransportMementoDecision {
    struct SendCall { let envelope: PacketEnvelope }
    var sendCalls: [SendCall] = []

    // Configure behavior per test
    var nextSend: () throws -> ChatResponse = {
        ChatResponse(
            text: "ok",
            statusCode: 200,
            transmissionId: "tx1",
            pending: false,
            threadMemento: nil,
            evidenceSummary: nil,
            evidence: nil,
            evidenceWarnings: nil,
            outputEnvelope: nil
        )
    }

    var nextPoll: (String) throws -> ChatPollResponse = { _ in
        ChatPollResponse(
            pending: false,
            assistant: "polled",
            serverStatus: "completed",
            statusCode: 200,
            threadMemento: nil,
            evidenceSummary: nil,
            evidence: nil,
            evidenceWarnings: nil,
            outputEnvelope: nil
        )
    }

    var nextDecision: (String, String, ThreadMementoDecision) throws -> ThreadMementoDecisionResult = { _, _, _ in
        ThreadMementoDecisionResult(statusCode: 200, applied: true, reason: "applied", memento: nil)
    }

    func send(envelope: PacketEnvelope) async throws -> ChatResponse {
        sendCalls.append(.init(envelope: envelope))
        return try nextSend()
    }

    func poll(transmissionId: String) async throws -> ChatPollResponse {
        return try nextPoll(transmissionId)
    }

    func decideMemento(threadId: String, mementoId: String, decision: ThreadMementoDecision) async throws -> ThreadMementoDecisionResult {
        return try nextDecision(threadId, mementoId, decision)
    }
}
