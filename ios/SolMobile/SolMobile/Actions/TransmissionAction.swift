//
//  TransmissionAction.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/22/25.
//

import Foundation
import SwiftData
import os

private let transportLog = Logger(subsystem: "com.sollabshq.solmobile", category: "Transport")

private func msSince(_ startNs: UInt64) -> Double {
    let endNs = DispatchTime.now().uptimeNanoseconds
    return Double(endNs &- startNs) / 1_000_000.0
}


@MainActor
final class TransmissionActions {
    private let outboxLog = Logger(subsystem: "com.sollabshq.solmobile", category: "Outbox")

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

        outboxLog.info("[enqueueChat] thread=\(thread.id.uuidString.prefix(8), privacy: .public) msg=\(userMessage.id.uuidString.prefix(8), privacy: .public) shouldFail=\(shouldFail, privacy: .public)")


        let packet = Packet(threadId: thread.id, messageIds: [userMessage.id])


        packet.packetType = shouldFail ? "chat_fail" : "chat"


        outboxLog.info("[enqueueChat] packet=\(packet.id.uuidString.prefix(8), privacy: .public) type=\(packet.packetType, privacy: .public)")


        modelContext.insert(packet)


        let tx = Transmission(packet: packet)

        modelContext.insert(tx)


        outboxLog.info("[enqueueChat] tx=\(tx.id.uuidString.prefix(8), privacy: .public) created")


        try? modelContext.save()
    }

    func processQueue() async {
        let runId = String(UUID().uuidString.prefix(8))
        outboxLog.info("[processQueue \(runId, privacy: .public)] start")

        let queuedRaw = TransmissionStatus.queued.rawValue

        let descriptor = FetchDescriptor<Transmission>(
            predicate: #Predicate { $0.statusRaw == queuedRaw },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        guard let queued = try? modelContext.fetch(descriptor) else {
            outboxLog.error("[processQueue \(runId, privacy: .public)] fetch queued failed")
            return
        }

        outboxLog.info("[processQueue \(runId, privacy: .public)] queued count=\(queued.count, privacy: .public)")

        guard let tx = queued.first else {
            outboxLog.info("[processQueue \(runId, privacy: .public)] nothing queued")
            return
        } // v0: one in-flight at a time

        // Snapshot identifiers before we suspend.
        let txId = tx.id
        let packet = tx.packet
        let threadId = packet.threadId
        let firstMessageId = packet.messageIds.first

        outboxLog.info("[processQueue \(runId, privacy: .public)] tx=\(txId.uuidString.prefix(8), privacy: .public) packet=\(packet.id.uuidString.prefix(8), privacy: .public) type=\(packet.packetType, privacy: .public) thread=\(threadId.uuidString.prefix(8), privacy: .public)")

        let startNs = DispatchTime.now().uptimeNanoseconds

        tx.status = .sending
        tx.lastError = nil


        outboxLog.info("[processQueue \(runId, privacy: .public)] tx=\(txId.uuidString.prefix(8), privacy: .public) status->sending")

        do {

            let packet = tx.packet

            let userText = (firstMessageId.flatMap { try? fetchMessage(id: $0)?.text }) ?? ""


            outboxLog.debug("[processQueue \(runId, privacy: .public)] tx=\(txId.uuidString.prefix(8), privacy: .public) userTextLen=\(userText.count, privacy: .public)")


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
            outboxLog.info("[processQueue \(runId, privacy: .public)] tx=\(txId.uuidString.prefix(8), privacy: .public) send -> transport")
            let response = try await transport.send(envelope: envelope)
            outboxLog.info("[processQueue \(runId, privacy: .public)] tx=\(txId.uuidString.prefix(8), privacy: .public) transport ok in \(msSince(startNs), format: .fixed(precision: 1))ms")

            guard let freshTx = try? fetchTransmission(id: txId) else { return }

            if let thread = try? fetchThread(id: threadId) {
                let assistantMessage = Message(thread: thread, creatorType: .assistant, text: response.text)
                thread.messages.append(assistantMessage)
                thread.lastActiveAt = Date()
                modelContext.insert(assistantMessage)
                outboxLog.info("[processQueue \(runId, privacy: .public)] tx=\(txId.uuidString.prefix(8), privacy: .public) assistant appended")
            }

            freshTx.status = .succeeded
            outboxLog.info("[processQueue \(runId, privacy: .public)] tx=\(txId.uuidString.prefix(8), privacy: .public) status->succeeded")
        }

        catch {
            outboxLog.error("[processQueue \(runId, privacy: .public)] tx=\(txId.uuidString.prefix(8), privacy: .public) transport failed in \(msSince(startNs), format: .fixed(precision: 1))ms err=\(String(describing: error), privacy: .public)")
            guard let freshTx = try? fetchTransmission(id: txId) else { return }
            freshTx.status = .failed
            freshTx.lastError = String(describing: error)
            outboxLog.info("[processQueue \(runId, privacy: .public)] tx=\(txId.uuidString.prefix(8), privacy: .public) status->failed")
        }

        outboxLog.info("[processQueue \(runId, privacy: .public)] end")
    }

    func retryFailed() {
        outboxLog.info("[retryFailed] invoked")

        let failedRaw = TransmissionStatus.failed.rawValue
        let descriptor = FetchDescriptor<Transmission>(
            predicate: #Predicate { $0.statusRaw == failedRaw }
        )
        guard let failed = try? modelContext.fetch(descriptor) else { return }

        outboxLog.info("[retryFailed] failed count=\(failed.count, privacy: .public)")

        for tx in failed {

            outboxLog.info("[retryFailed] tx=\(tx.id.uuidString.prefix(8), privacy: .public) packetType=\(tx.packet.packetType, privacy: .public)")

            // DEBUG:: one-shot fail test: only fail the first attempt
            if tx.packet.packetType == "chat_fail" {
                tx.packet.packetType = "chat"
                outboxLog.info("[retryFailed] tx=\(tx.id.uuidString.prefix(8), privacy: .public) one-shot flip chat_fail->chat")
            }

            tx.status = .queued
            tx.lastError = nil

            outboxLog.info("[retryFailed] tx=\(tx.id.uuidString.prefix(8), privacy: .public) status failed->queued")
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
        let startNs = DispatchTime.now().uptimeNanoseconds
        let isFailTest = (envelope.packetType == "chat_fail")
        transportLog.info("[send] packet=\(envelope.packetId.uuidString.prefix(8), privacy: .public) thread=\(envelope.threadId.uuidString.prefix(8), privacy: .public) failTest=\(isFailTest, privacy: .public)")

        
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
            transportLog.info("[send] simulate header set: 500")
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

        
        transportLog.info("[send] resp status=\(http.statusCode, privacy: .public) in \(msSince(startNs), format: .fixed(precision: 1))ms")

        
        // if 500 returns and we are simulation flow, send correct simulation failure error
        if simulate500, http.statusCode == 500 {
            transportLog.error("[send] simulated 500 -> throwing simulatedFailure")
            throw ChatTransportError.simulatedFailure
        }

        
        // If server replies "pending" for an idempotent replay, surface a readable message for now.
        if http.statusCode == 202 {
            transportLog.info("[send] pending (202)")
            return ChatResponse(text: "⏳ Pending…")
        }

        
        // if a 2XX response then good and let pass else throw an error
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            transportLog.error("[send] non-2xx status=\(http.statusCode, privacy: .public) bodyLen=\(body.count, privacy: .public)")
            throw NSError(domain: "SolServer", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }

        
        let decoded = try JSONDecoder().decode(SolServerChatResponseDTO.self, from: data)
        transportLog.info("[send] decoded ok assistantLen=\((decoded.assistant ?? "").count, privacy: .public)")
        return ChatResponse(text: decoded.assistant ?? "(no assistant text)")
    }
}
