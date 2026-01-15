//
//  SolServerClient.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/23/25.
//

import Foundation

struct Request: Codable {
    let threadId: String
    let clientRequestId: String
    let message: String
}

struct ModeDecision: Codable {
    let modeLabel: String
    let domainFlags: [String]
    let confidence: Double
    let checkpointNeeded: Bool
    let reasons: [String]
    let version: String
}

// ThreadMemento is a navigation artifact returned by SolServer.
// It is not durable knowledge; the client may choose to Accept/Decline.
struct ThreadMementoDTO: Codable {
    let id: String
    let threadId: String
    let createdAt: String
    let version: String

    let arc: String
    let active: [String]
    let parked: [String]
    let decisions: [String]
    let next: [String]
}

struct Response: Codable {
    let ok: Bool
    let transmissionId: String?
    let modeDecision: ModeDecision?
    let assistant: String?
    let idempotentReplay: Bool?
    let pending: Bool?
    let status: String?

    // Present when SolServer auto-saves a ThreadMemento (Option 1).
    let threadMemento: ThreadMementoDTO?
    
    // Evidence fields (PR #7.1 / PR #8)
    let evidenceSummary: EvidenceSummaryDTO?  // Always present in successful responses
    let evidence: EvidenceDTO?  // Omitted when none
    let evidenceWarnings: [EvidenceWarningDTO]?  // Omitted when none
}

struct TransmissionDTO: Codable {
    let id: String
    let status: String
}

struct TransmissionResponse: Codable {
    let ok: Bool
    let transmission: TransmissionDTO
    let pending: Bool?
    let assistant: String?

    // Present once the transmission is completed and the server has a memento snapshot.
    let threadMemento: ThreadMementoDTO?
}

private struct MementoDecisionRequest: Codable {
    let threadId: String
    let mementoId: String
    let decision: String
}

private struct MementoDecisionResponse: Codable {
    let ok: Bool
    let decision: String?
    let applied: Bool?
    let reason: String?
    let memento: ThreadMementoDTO?
}

final class SolServerClient: ChatTransportPolling, ChatTransportMementoDecision {
    let baseURL: URL
    private let session: URLSession

    // Dev telemetry keys used by Settings/dev UI
    private enum DevTelemetry {
        static let lastChatStatusCodeKey = "sol.dev.lastChatStatusCode"
        static let lastChatStatusAtKey = "sol.dev.lastChatStatusAt"

        static func persistLastChat(statusCode: Int) {
            UserDefaults.standard.set(statusCode, forKey: lastChatStatusCodeKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastChatStatusAtKey)
        }
    }

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Convenience init for app runtime where Settings controls the base URL.
    convenience init(session: URLSession = .shared) {
        let raw = (UserDefaults.standard.string(forKey: "solserver.baseURL") ?? "http://127.0.0.1:3333")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: raw) ?? URL(string: "http://127.0.0.1:3333")!
        self.init(baseURL: url, session: session)
    }

    // MARK: - Low-level HTTP helper

    private func requestJSON(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    private func require2xx(_ http: HTTPURLResponse, data: Data) throws {
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TransportError.httpStatus(code: http.statusCode, body: body)
        }
    }

    // MARK: - Typed endpoints (useful for decoding tests / direct calls)

    func getTransmission(_ transmissionId: String) async throws -> TransmissionResponse {
        try await transmission(transmissionId)
    }

    func transmission(_ transmissionId: String) async throws -> TransmissionResponse {
        let url = baseURL
            .appendingPathComponent("/v1/transmissions")
            .appendingPathComponent(transmissionId)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        let (data, http) = try await requestJSON(req)
        try require2xx(http, data: data)

        return try JSONDecoder().decode(TransmissionResponse.self, from: data)
    }

    func chat(threadId: String, clientRequestId: String, message: String, simulateStatus: Int? = nil) async throws -> Response {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let simulateStatus {
            req.setValue(String(simulateStatus), forHTTPHeaderField: "x-sol-simulate-status")
        }
        req.httpBody = try JSONEncoder().encode(Request(threadId: threadId, clientRequestId: clientRequestId, message: message))

        let (data, http) = try await requestJSON(req)
        DevTelemetry.persistLastChat(statusCode: http.statusCode)

        // 200 = normal ok; 202 = pending accepted (still decodes)
        try require2xx(http, data: data)

        return try JSONDecoder().decode(Response.self, from: data)
    }

    /// Submit a decision for a thread memento.
    ///
    /// Server contract: POST /v1/memento/decision
    /// Body: { threadId, mementoId, decision }
    func decideMemento(threadId: String, mementoId: String, decision: ThreadMementoDecision) async throws -> ThreadMementoDecisionResult {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/memento/decision"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = MementoDecisionRequest(threadId: threadId, mementoId: mementoId, decision: decision.rawValue)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, http) = try await requestJSON(req)
        try require2xx(http, data: data)

        let decoded = try JSONDecoder().decode(MementoDecisionResponse.self, from: data)

        return ThreadMementoDecisionResult(
            statusCode: http.statusCode,
            applied: decoded.applied ?? false,
            reason: decoded.reason,
            memento: decoded.memento
        )
    }

    // MARK: - ChatTransport / Outbox integration

    func send(envelope: PacketEnvelope) async throws -> ChatResponse {
        let simulate500 = (envelope.packetType == "chat_fail")
        let simulate202 = envelope.messageText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("/pending")

        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if simulate500 {
            req.setValue("500", forHTTPHeaderField: "x-sol-simulate-status")
        } else if simulate202 {
            req.setValue("202", forHTTPHeaderField: "x-sol-simulate-status")
        }

        let dto = Request(
            threadId: envelope.threadId.uuidString,
            clientRequestId: envelope.packetId.uuidString,
            message: envelope.messageText
        )
        req.httpBody = try JSONEncoder().encode(dto)

        let (data, http) = try await requestJSON(req)
        DevTelemetry.persistLastChat(statusCode: http.statusCode)

        let headerTxId = http.value(forHTTPHeaderField: "x-sol-transmission-id")

        // Preserve the explicit simulated-failure behavior used by client tests.
        if simulate500, http.statusCode == 500 {
            throw TransportError.simulatedFailure
        }

        if http.statusCode == 202 {
            let decoded = (try? JSONDecoder().decode(Response.self, from: data))
            let txId = headerTxId ?? decoded?.transmissionId

            return ChatResponse(
                text: "",
                statusCode: 202,
                transmissionId: txId,
                pending: true,
                threadMemento: decoded?.threadMemento,
                evidenceSummary: decoded?.evidenceSummary,
                evidence: decoded?.evidence,
                evidenceWarnings: decoded?.evidenceWarnings
            )
        }

        try require2xx(http, data: data)

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let txId = headerTxId ?? decoded.transmissionId

        return ChatResponse(
            text: decoded.assistant ?? "(no assistant text)",
            statusCode: http.statusCode,
            transmissionId: txId,
            pending: decoded.pending ?? false,
            threadMemento: decoded.threadMemento,
            evidenceSummary: decoded.evidenceSummary,
            evidence: decoded.evidence,
            evidenceWarnings: decoded.evidenceWarnings
        )
    }

    func poll(transmissionId: String) async throws -> ChatPollResponse {
        let url = baseURL
            .appendingPathComponent("/v1/transmissions")
            .appendingPathComponent(transmissionId)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        let (data, http) = try await requestJSON(req)
        try require2xx(http, data: data)

        let decoded = try JSONDecoder().decode(TransmissionResponse.self, from: data)
        let pending = decoded.pending ?? (decoded.transmission.status == "created")

        return ChatPollResponse(
            pending: pending,
            assistant: decoded.assistant,
            serverStatus: decoded.transmission.status,
            statusCode: http.statusCode,
            threadMemento: decoded.threadMemento,
            evidenceSummary: nil,  // Poll endpoint doesn't return evidence for MVP
            evidence: nil,
            evidenceWarnings: nil
        )
    }
}