//
//  TransmissionAction.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/22/25.
//

import Foundation
import SwiftData

@MainActor
final class TransmissionActions {
    private let modelContext: ModelContext
    private let transport: any ChatTransport

    init(modelContext: ModelContext, transport: (any ChatTransport)? = nil) {
        self.modelContext = modelContext
        self.transport = transport ?? StubChatTransport()
    }

    func enqueueChat(thread: Thread, userMessage: Message) {
        let shouldFail = userMessage.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("/fail")


        let packet = Packet(threadId: thread.id, messageIds: [userMessage.id])

        packet.packetType = shouldFail ? "chat_fail" : "chat"

        modelContext.insert(packet)

        let tx = Transmission(packet: packet)
        modelContext.insert(tx)

        try? modelContext.save()
    }

    func processQueue() async {
        let queuedRaw = TransmissionStatus.queued.rawValue
        let descriptor = FetchDescriptor<Transmission>(
            predicate: #Predicate { $0.statusRaw == queuedRaw },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        guard let queued = try? modelContext.fetch(descriptor) else { return }
        guard let tx = queued.first else { return } // v0: one in-flight at a time

        // Snapshot identifiers before we suspend.
        let txId = tx.id
        let packet = tx.packet
        let threadId = packet.threadId

        tx.status = .sending
        tx.lastError = nil

        do {
            let packet = tx.packet
            let envelope = PacketEnvelope(
                packetId: packet.id,
                packetType: packet.packetType,
                threadId: packet.threadId,
                messageIds: packet.messageIds,
                contextRefsJson: packet.contextRefsJson,
                payloadJson: packet.payloadJson
            )
            

            // IMPORTANT: Don't mutate SwiftData models after the await unless refetched.
            let response = try await transport.send(envelope: envelope)

            guard let freshTx = try? fetchTransmission(id: txId) else { return }

            if let thread = try? fetchThread(id: threadId) {
                let assistantMessage = Message(thread: thread, creatorType: .assistant, text: response.text)
                thread.messages.append(assistantMessage)
                thread.lastActiveAt = Date()
                modelContext.insert(assistantMessage)
            }

            freshTx.status = .succeeded
        } catch {
            guard let freshTx = try? fetchTransmission(id: txId) else { return }
            freshTx.status = .failed
            freshTx.lastError = String(describing: error)
        }
    }

    func retryFailed() {
        let failedRaw = TransmissionStatus.failed.rawValue
        let descriptor = FetchDescriptor<Transmission>(
            predicate: #Predicate { $0.statusRaw == failedRaw }
        )
        guard let failed = try? modelContext.fetch(descriptor) else { return }
        for tx in failed {
            tx.status = .queued
            tx.lastError = nil
        }
    }

    private func fetchThread(id: UUID) throws -> Thread? {
        let d = FetchDescriptor<Thread>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(d).first
    }

    private func fetchTransmission(id: UUID) throws -> Transmission? {
        let d = FetchDescriptor<Transmission>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(d).first
    }
}

struct PacketEnvelope: Sendable {
    let packetId: UUID
    let packetType: String
    let threadId: UUID
    let messageIds: [UUID]
    let contextRefsJson: String?
    let payloadJson: String?
}

protocol ChatTransport {
    func send(envelope: PacketEnvelope) async throws -> ChatResponse
}

enum ChatTransportError: Error {
    case simulatedFailure
}

struct ChatResponse {
    let text: String
}

struct StubChatTransport: ChatTransport {
    func send(envelope: PacketEnvelope) async throws -> ChatResponse {
        // v0 stub: deterministic echo so you can watch the pipeline work
        if envelope.packetType == "chat_fail" {
            throw ChatTransportError.simulatedFailure
        }
        return ChatResponse(text: "✅ Stub reply (packet \(envelope.packetId.uuidString.prefix(8)))")
    }
}
