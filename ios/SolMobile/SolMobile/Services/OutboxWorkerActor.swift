//
//  OutboxWorkerActor.swift
//  SolMobile
//
//  Created by SolMobile Outbox.
//

import Foundation
import SwiftData

actor OutboxWorkerActor {
    private let container: ModelContainer
    private let transport: any ChatTransport
    private let statusWatcher: TransmissionStatusWatcher?

    init(
        container: ModelContainer,
        transport: any ChatTransport,
        statusWatcher: TransmissionStatusWatcher?
    ) {
        self.container = container
        self.transport = transport
        self.statusWatcher = statusWatcher
    }

    func processQueue(pollLimit: Int) async {
        let engine = TransmissionActions(
            modelContext: ModelContext(container),
            transport: transport,
            statusWatcher: statusWatcher
        )
        await engine.processQueue(pollLimit: pollLimit)
    }

    func retryFailed() {
        let engine = TransmissionActions(
            modelContext: ModelContext(container),
            transport: transport,
            statusWatcher: statusWatcher
        )
        engine.retryFailed()
    }
}
