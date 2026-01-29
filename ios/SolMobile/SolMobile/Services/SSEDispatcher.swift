//
//  SSEDispatcher.swift
//  SolMobile
//
//  Created by SolMobile SSE.
//

import Foundation
import os
import LDSwiftEventSource

@MainActor
final class SSEDispatcher {
    private let log = Logger(subsystem: "com.sollabshq.solmobile", category: "SSEDispatcher")
    private let statusStore: SSEStatusStore

    var onTransmissionReady: ((String) -> Void)?
    var onTransmissionFailed: ((String) -> Void)?
    var onTransmissionAccepted: ((String) -> Void)?
    var onTransmissionStarted: ((String) -> Void)?

    init(statusStore: SSEStatusStore = .shared) {
        self.statusStore = statusStore
    }

    func handle(eventType: String, messageEvent: MessageEvent) {
        guard let data = messageEvent.data.data(using: .utf8) else {
            log.debug("sse decode failed: empty data")
            return
        }

        let envelope: SSEEventEnvelope
        do {
            envelope = try JSONDecoder().decode(SSEEventEnvelope.self, from: data)
        } catch {
            log.debug("sse decode failed: \(String(describing: error), privacy: .public)")
            return
        }

        if eventType != envelope.kind.rawValue && eventType != "message" {
            log.debug("sse kind mismatch eventType=\(eventType, privacy: .public) kind=\(envelope.kind.rawValue, privacy: .public)")
        }

        statusStore.recordEnvelope(envelope)

        switch envelope.kind {
        case .ping:
            return
        case .txAccepted:
            if let txId = envelope.subject.transmissionId {
                onTransmissionAccepted?(txId)
            }
            log.debug("sse tx_accepted tx=\(envelope.subject.transmissionId ?? "-", privacy: .public)")
        case .runStarted:
            if let txId = envelope.subject.transmissionId {
                onTransmissionStarted?(txId)
            }
            log.debug("sse run_started tx=\(envelope.subject.transmissionId ?? "-", privacy: .public)")
        case .assistantFinalReady:
            if let txId = envelope.subject.transmissionId {
                onTransmissionReady?(txId)
            }
        case .assistantFailed:
            if let txId = envelope.subject.transmissionId {
                onTransmissionFailed?(txId)
            }
        }
    }
}
