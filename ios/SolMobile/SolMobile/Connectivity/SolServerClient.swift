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

final class SolServerClient {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func transmission(_ transmissionId: String) async throws -> TransmissionResponse {
        let url = baseURL
            .appendingPathComponent("/v1/transmissions")
            .appendingPathComponent(transmissionId)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SolServer", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }

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

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        // 200 = normal ok; 202 = pending replay case (we still decode response)
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SolServer", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }
}
