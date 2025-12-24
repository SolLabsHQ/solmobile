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
        let firstMessageId = packet.messageIds.first

        tx.status = .sending
        tx.lastError = nil

        do {
            let packet = tx.packet
            let userText = (firstMessageId.flatMap { try? fetchMessage(id: $0)?.text }) ?? ""

            let envelope = PacketEnvelope(
                packetId: packet.id,
                packetType: packet.packetType,
                threadId: packet.threadId,
                messageIds: packet.messageIds,
                messageText: userText,
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

    private func fetchMessage(id: UUID) throws -> Message? {
        let d = FetchDescriptor<Message>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(d).first
    }
}

struct PacketEnvelope: Sendable {
    let packetId: UUID
    let packetType: String
    let threadId: UUID
    let messageIds: [UUID]
    let messageText: String
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

private struct SolServerChatRequestDTO: Codable {
    let threadId: String
    let clientRequestId: String
    let message: String
}

private struct SolServerChatResponseDTO: Codable {
    let ok: Bool
    let transmissionId: String?
    let assistant: String?
    let idempotentReplay: Bool?
    let pending: Bool?
    let status: String?
}

struct StubChatTransport: ChatTransport {
    /// For Simulator: http://127.0.0.1:3333 works.
    /// For a physical iPhone: use your Mac's LAN IP (e.g., http://192.168.x.x:3333) and ensure ATS allows HTTP in dev.
    var baseURL: URL = URL(string: "http://127.0.0.1:3333")!

    func send(envelope: PacketEnvelope) async throws -> ChatResponse {
        // v0: keep simulated failure path for pipeline testing
        let simulate500 = (envelope.packetType == "chat_fail")

        let url = baseURL.appendingPathComponent("/v1/chat")

        // build request
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // set for request failures
        if simulate500 {
            req.setValue("500", forHTTPHeaderField: "x-sol-simulate-status")
        }

        // Use packetId as idempotency key so retries dedupe server-side.
        let dto = SolServerChatRequestDTO(
            threadId: envelope.threadId.uuidString,
            clientRequestId: envelope.packetId.uuidString,
            message: envelope.messageText
        )
        req.httpBody = try JSONEncoder().encode(dto)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // if 500 returns and we are simulation flow, send correct simulation failure error
        if simulate500, http.statusCode == 500 {
            throw ChatTransportError.simulatedFailure
        }

        // If server replies "pending" for an idempotent replay, surface a readable message for now.
        if http.statusCode == 202 {
            return ChatResponse(text: "⏳ Pending…")
        }

        // if a 2XX response then good and let pass else throw an error
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SolServer", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }

        let decoded = try JSONDecoder().decode(SolServerChatResponseDTO.self, from: data)
        return ChatResponse(text: decoded.assistant ?? "(no assistant text)")
    }
}
