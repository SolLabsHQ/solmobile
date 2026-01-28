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

    func processQueue(pollLimit: Int, pollFirst: Bool) async {
        let engine = await MainActor.run {
            TransmissionActions(
                modelContext: ModelContext(container),
                transport: transport,
                statusWatcher: statusWatcher
            )
        }
        await engine.processQueue(pollLimit: pollLimit, pollFirst: pollFirst)
    }

    func enqueueChat(threadId: UUID, messageId: UUID, messageText: String?, shouldFail: Bool) async {
        let engine = await MainActor.run {
            TransmissionActions(
                modelContext: ModelContext(container),
                transport: transport,
                statusWatcher: statusWatcher
            )
        }
        await engine.enqueueChat(threadId: threadId, messageId: messageId, messageText: messageText, shouldFail: shouldFail)
    }

    func enqueueMemoryDistill(threadId: UUID, messageIds: [UUID], payload: MemoryDistillRequest) async {
        let engine = await MainActor.run {
            TransmissionActions(
                modelContext: ModelContext(container),
                transport: transport,
                statusWatcher: statusWatcher
            )
        }
        await engine.enqueueMemoryDistill(threadId: threadId, messageIds: messageIds, payload: payload)
    }
    func retryFailed() async {
        let engine = await MainActor.run {
            TransmissionActions(
                modelContext: ModelContext(container),
                transport: transport,
                statusWatcher: statusWatcher
            )
        }
        await engine.retryFailed()
    }

    func pollTransmission(serverTransmissionId: String, reason: String) async {
        let engine = await MainActor.run {
            TransmissionActions(
                modelContext: ModelContext(container),
                transport: transport,
                statusWatcher: statusWatcher
            )
        }
        await engine.pollTransmission(serverTransmissionId: serverTransmissionId, reason: reason)
    }
}
