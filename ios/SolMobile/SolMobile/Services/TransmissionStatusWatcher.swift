//
//  TransmissionStatusWatcher.swift
//  SolMobile
//
//  Created by SolMobile Outbox.
//

import Foundation

protocol TransmissionStatusWatcher {
    func poll(transmissionId: String, diagnostics: DiagnosticsContext?) async throws -> ChatPollResponse
}

struct PollingTransmissionStatusWatcher: TransmissionStatusWatcher {
    let transport: any ChatTransportPolling

    func poll(transmissionId: String, diagnostics: DiagnosticsContext?) async throws -> ChatPollResponse {
        try await transport.poll(transmissionId: transmissionId, diagnostics: diagnostics)
    }
}
