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

struct Response: Codable {
    let ok: Bool
    let transmissionId: String?
    let modeDecision: ModeDecision?
    let assistant: String?
    let idempotentReplay: Bool?
    let pending: Bool?
    let status: String?
}

final class SolServerClient {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func chat(threadId: String, clientRequestId: String, message: String) async throws -> Response {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
