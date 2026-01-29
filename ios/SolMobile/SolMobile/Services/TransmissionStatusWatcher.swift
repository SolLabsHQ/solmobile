//
//  TransmissionStatusWatcher.swift
//  SolMobile
//
//  Created by SolMobile Outbox.
//

import Foundation

protocol TransmissionStatusWatcher: Sendable {
    func poll(transmissionId: String, diagnostics: DiagnosticsContext?) async throws -> ChatPollResponse
}

struct PollingTransmissionStatusWatcher: TransmissionStatusWatcher, Sendable {
    let transport: any ChatTransportPolling

    func poll(transmissionId: String, diagnostics: DiagnosticsContext?) async throws -> ChatPollResponse {
        try await transport.poll(transmissionId: transmissionId, diagnostics: diagnostics)
    }
}
