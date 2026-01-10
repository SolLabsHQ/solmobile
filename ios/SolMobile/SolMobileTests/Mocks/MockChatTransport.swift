//
//  MockChatTransport.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import Foundation
@testable import SolMobile

final class MockChatTransport: ChatTransportPolling, ChatTransportMementoDecision {
    func decideMemento(
        threadId: String,
        mementoId: String,
        decision: SolMobile.ThreadMementoDecision
    ) async throws -> SolMobile.ThreadMementoDecisionResult {
        decideCalls.append((threadId: threadId, mementoId: mementoId, decision: decision))

        // Default behavior: pretend the server accepted the decision successfully.
        guard !decideModes.isEmpty else {
            return ThreadMementoDecisionResult(statusCode: 200, applied: true, reason: "applied", memento: nil)
        }

        let m = decideModes.removeFirst()
        switch m {
        case let .ok(status, applied, reason, memento):
            return ThreadMementoDecisionResult(statusCode: status, applied: applied, reason: reason, memento: memento)
        case let .fail(err):
            throw err
        }
    }
    
    enum Mode {
        case succeed(text: String, status: Int = 200, txId: String? = "tx-1", pending: Bool = false)
        case pending(status: Int = 202, txId: String = "tx-pending")
        case fail(Error)
    }

    var sendModes: [Mode] = []
    var pollModes: [Mode] = []

    private(set) var sendCalls: [PacketEnvelope] = []
    private(set) var pollCalls: [String] = []

    enum DecideMode {
        case ok(status: Int = 200, applied: Bool = true, reason: String? = "applied", memento: ThreadMementoDTO? = nil)
        case fail(Error)
    }

    var decideModes: [DecideMode] = []

    private(set) var decideCalls: [(threadId: String, mementoId: String, decision: SolMobile.ThreadMementoDecision)] = []

    func send(envelope: PacketEnvelope) async throws -> ChatResponse {
        sendCalls.append(envelope)
        guard !sendModes.isEmpty else {
            return ChatResponse(text: "(default)", statusCode: 200, transmissionId: "tx-default", pending: false, threadMemento: nil)
        }

        let m = sendModes.removeFirst()
        switch m {
        case let .succeed(text, status, txId, pending):
            return ChatResponse(text: text, statusCode: status, transmissionId: txId, pending: pending, threadMemento: nil)
        case let .pending(status, txId):
            return ChatResponse(text: "", statusCode: status, transmissionId: txId, pending: true, threadMemento: nil)
        case let .fail(err):
            throw err
        }
    }

    func poll(transmissionId: String) async throws -> ChatPollResponse {
        pollCalls.append(transmissionId)
        guard !pollModes.isEmpty else {
            return ChatPollResponse(pending: false, assistant: "(default poll)", serverStatus: "completed", statusCode: 200, threadMemento: nil)
        }

        let m = pollModes.removeFirst()
        switch m {
        case let .succeed(text, status, _, _):
            return ChatPollResponse(pending: false, assistant: text, serverStatus: "completed", statusCode: status, threadMemento: nil)
        case .pending:
            return ChatPollResponse(pending: true, assistant: nil, serverStatus: "created", statusCode: 200, threadMemento: nil)
        case let .fail(err):
            throw err
        }
    }
}
