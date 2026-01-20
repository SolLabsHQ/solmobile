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
    let outputEnvelope: OutputEnvelopeDTO?
    let idempotentReplay: Bool?
    let pending: Bool?
    let status: String?

    // Present when SolServer auto-saves a ThreadMemento (Option 1).
    let threadMemento: ThreadMementoDTO?
    
    // Evidence fields (PR #7.1 / PR #8)
    let evidenceSummary: EvidenceSummaryDTO  // Always present in successful responses
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
    private let redirectTracker: RedirectTracker

    // Dev telemetry keys used by Settings/dev UI
    private enum DevTelemetry {
        static let lastChatStatusCodeKey = "sol.dev.lastChatStatusCode"
        static let lastChatStatusAtKey = "sol.dev.lastChatStatusAt"
        static let lastChatURLKey = "sol.dev.lastChatURL"
        static let lastChatMethodKey = "sol.dev.lastChatMethod"

        static func persistLastChat(statusCode: Int, method: String, url: URL?) {
            UserDefaults.standard.set(statusCode, forKey: lastChatStatusCodeKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastChatStatusAtKey)
            if let url = url?.absoluteString {
                UserDefaults.standard.set(url, forKey: lastChatURLKey)
            }
            UserDefaults.standard.set(method, forKey: lastChatMethodKey)
        }
    }

    init(
        baseURL: URL,
        configuration: URLSessionConfiguration = .default,
        redirectTracker: RedirectTracker = RedirectTracker()
    ) {
        self.baseURL = baseURL
        self.redirectTracker = redirectTracker
        self.session = URLSession(
            configuration: configuration,
            delegate: redirectTracker,
            delegateQueue: nil
        )
    }

    /// Convenience init for app runtime where Settings controls the base URL.
    convenience init(configuration: URLSessionConfiguration = .default) {
        self.init(baseURL: SolServerBaseURL.effectiveURL(), configuration: configuration)
    }

    // MARK: - Low-level HTTP helper

    private func requestJSON(
        _ req: URLRequest,
        diagnostics: DiagnosticsContext? = nil
    ) async throws -> (Data, HTTPURLResponse, ResponseInfo) {
        var authorizedReq = req
        applyAuthHeader(&authorizedReq)

        if AppEnvironment.current.requiresHTTPS,
           let url = authorizedReq.url,
           url.scheme?.lowercased() != "https" {
            let error = TransportError.insecureBaseURL(reason: "HTTPS required in \(AppEnvironment.current.rawValue)")
            DiagnosticsStore.shared.record(
                method: authorizedReq.httpMethod ?? "GET",
                url: authorizedReq.url,
                responseURL: nil,
                redirectChain: [],
                status: nil,
                latencyMs: nil,
                retryableInferred: false,
                retryableSource: RetryableSource.parseFailedDefault.rawValue,
                parsedErrorCode: "insecure_base_url",
                traceRunId: nil,
                attemptId: diagnostics?.attemptId.uuidString,
                threadId: diagnostics?.threadId?.uuidString,
                localTransmissionId: diagnostics?.localTransmissionId?.uuidString,
                transmissionId: nil,
                error: error,
                responseData: nil,
                responseHeaders: nil,
                requestHeaders: authorizedReq.allHTTPHeaderFields,
                requestBody: authorizedReq.httpBody,
                hadAuthorization: authorizedReq.value(forHTTPHeaderField: "Authorization") != nil
            )
            throw error
        }

        let hadAuthorization = authorizedReq.value(forHTTPHeaderField: "Authorization") != nil
        let started = Date()

        return try await withCheckedThrowingContinuation { continuation in
            var taskId = 0
            let task = session.dataTask(with: authorizedReq) { data, response, error in
                let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
                let redirectChain = self.redirectTracker.consumeChain(taskId: taskId)

                if let error {
                    let decision = RetryPolicy.classify(statusCode: nil, body: nil, headers: nil, error: error)
                    DiagnosticsStore.shared.record(
                        method: authorizedReq.httpMethod ?? "GET",
                        url: authorizedReq.url,
                        responseURL: response?.url,
                        redirectChain: redirectChain,
                        status: nil,
                        latencyMs: latencyMs,
                        retryableInferred: decision.retryable,
                        retryableSource: decision.source.rawValue,
                        parsedErrorCode: decision.errorCode,
                        traceRunId: decision.traceRunId,
                        attemptId: diagnostics?.attemptId.uuidString,
                        threadId: diagnostics?.threadId?.uuidString,
                        localTransmissionId: diagnostics?.localTransmissionId?.uuidString,
                        transmissionId: decision.transmissionId,
                        error: error,
                        responseData: nil,
                        responseHeaders: nil,
                        requestHeaders: authorizedReq.allHTTPHeaderFields,
                        requestBody: authorizedReq.httpBody,
                        hadAuthorization: hadAuthorization
                    )
                    continuation.resume(throwing: error)
                    return
                }

                guard let data, let http = response as? HTTPURLResponse else {
                    let error = URLError(.badServerResponse)
                    DiagnosticsStore.shared.record(
                        method: authorizedReq.httpMethod ?? "GET",
                        url: authorizedReq.url,
                        responseURL: response?.url,
                        redirectChain: redirectChain,
                        status: nil,
                        latencyMs: latencyMs,
                        retryableInferred: true,
                        retryableSource: RetryableSource.networkError.rawValue,
                        parsedErrorCode: nil,
                        traceRunId: nil,
                        attemptId: diagnostics?.attemptId.uuidString,
                        threadId: diagnostics?.threadId?.uuidString,
                        localTransmissionId: diagnostics?.localTransmissionId?.uuidString,
                        transmissionId: nil,
                        error: error,
                        responseData: nil,
                        responseHeaders: nil,
                        requestHeaders: authorizedReq.allHTTPHeaderFields,
                        requestBody: authorizedReq.httpBody,
                        hadAuthorization: hadAuthorization
                    )
                    continuation.resume(throwing: error)
                    return
                }

                let headers = self.normalizedHeaders(http.allHeaderFields)
                let responseInfo = ResponseInfo(
                    statusCode: http.statusCode,
                    headers: headers,
                    finalURL: http.url,
                    redirectChain: redirectChain
                )

                let bodyString = String(data: data, encoding: .utf8)
                let decision = RetryPolicy.classify(
                    statusCode: http.statusCode,
                    body: bodyString,
                    headers: headers,
                    error: nil
                )
                let traceRunId = self.extractTraceRunId(headers: headers, body: bodyString)
                let transmissionId = self.extractTransmissionId(headers: headers, body: bodyString)

                DiagnosticsStore.shared.record(
                    method: authorizedReq.httpMethod ?? "GET",
                    url: authorizedReq.url,
                    responseURL: responseInfo.finalURL,
                    redirectChain: redirectChain,
                    status: http.statusCode,
                    latencyMs: latencyMs,
                    retryableInferred: decision.retryable,
                    retryableSource: decision.source.rawValue,
                    parsedErrorCode: decision.errorCode,
                    traceRunId: traceRunId,
                    attemptId: diagnostics?.attemptId.uuidString,
                    threadId: diagnostics?.threadId?.uuidString,
                    localTransmissionId: diagnostics?.localTransmissionId?.uuidString,
                    transmissionId: transmissionId ?? decision.transmissionId,
                    error: nil,
                    responseData: data,
                    responseHeaders: http.allHeaderFields,
                    requestHeaders: authorizedReq.allHTTPHeaderFields,
                    requestBody: authorizedReq.httpBody,
                    hadAuthorization: hadAuthorization
                )

                continuation.resume(returning: (data, http, responseInfo))
            }
            taskId = task.taskIdentifier
            task.resume()
        }
    }

    private func applyAuthHeader(_ req: inout URLRequest) {
        guard let token = KeychainStore.read(key: KeychainKeys.stagingApiKey), !token.isEmpty else {
            return
        }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func require2xx(_ http: HTTPURLResponse, data: Data, responseInfo: ResponseInfo) throws {
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TransportError.httpStatus(
                HTTPErrorInfo(
                    code: http.statusCode,
                    body: body,
                    headers: responseInfo.headers,
                    finalURL: responseInfo.finalURL,
                    redirectChain: responseInfo.redirectChain
                )
            )
        }
    }

    private func normalizedHeaders(_ headers: [AnyHashable: Any]) -> [String: String] {
        var normalized: [String: String] = [:]
        for (key, value) in headers {
            let keyString = String(describing: key).lowercased()
            normalized[keyString] = String(describing: value)
        }
        return normalized
    }

    private func extractTraceRunId(headers: [String: String], body: String?) -> String? {
        if let trace = headers["x-sol-trace-run-id"], !trace.isEmpty {
            return trace
        }
        return RetryPolicy.parseErrorEnvelope(from: body)?.traceRunId
    }

    private func extractTransmissionId(headers: [String: String], body: String?) -> String? {
        if let id = headers["x-sol-transmission-id"], !id.isEmpty {
            return id
        }
        if let parsed = RetryPolicy.parseErrorEnvelope(from: body), let id = parsed.transmissionId {
            return id
        }
        guard let body, let data = body.data(using: .utf8) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let id = json["transmissionId"] as? String, !id.isEmpty {
            return id
        }
        if let id = json["transmission_id"] as? String, !id.isEmpty {
            return id
        }
        return nil
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

        let (data, http, responseInfo) = try await requestJSON(req)
        try require2xx(http, data: data, responseInfo: responseInfo)

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

        let (data, http, responseInfo) = try await requestJSON(req)
        DevTelemetry.persistLastChat(statusCode: http.statusCode, method: req.httpMethod ?? "POST", url: req.url)

        // 200 = normal ok; 202 = pending accepted (still decodes)
        try require2xx(http, data: data, responseInfo: responseInfo)

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

        let (data, http, responseInfo) = try await requestJSON(req)
        try require2xx(http, data: data, responseInfo: responseInfo)

        let decoded = try JSONDecoder().decode(MementoDecisionResponse.self, from: data)

        return ThreadMementoDecisionResult(
            statusCode: http.statusCode,
            applied: decoded.applied ?? false,
            reason: decoded.reason,
            memento: decoded.memento
        )
    }

    // MARK: - ChatTransport / Outbox integration

    func send(envelope: PacketEnvelope, diagnostics: DiagnosticsContext? = nil) async throws -> ChatResponse {
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

        let (data, http, responseInfo) = try await requestJSON(req, diagnostics: diagnostics)
        DevTelemetry.persistLastChat(statusCode: http.statusCode, method: req.httpMethod ?? "POST", url: req.url)

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
                responseInfo: responseInfo,
                threadMemento: decoded?.threadMemento,
                evidenceSummary: decoded?.evidenceSummary,
                evidence: decoded?.evidence,
                evidenceWarnings: decoded?.evidenceWarnings,
                outputEnvelope: decoded?.outputEnvelope
            )
        }

        try require2xx(http, data: data, responseInfo: responseInfo)

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let txId = headerTxId ?? decoded.transmissionId

        return ChatResponse(
            text: decoded.assistant ?? "(no assistant text)",
            statusCode: http.statusCode,
            transmissionId: txId,
            pending: decoded.pending ?? false,
            responseInfo: responseInfo,
            threadMemento: decoded.threadMemento,
            evidenceSummary: decoded.evidenceSummary,
            evidence: decoded.evidence,
            evidenceWarnings: decoded.evidenceWarnings,
            outputEnvelope: decoded.outputEnvelope
        )
    }

    func poll(transmissionId: String, diagnostics: DiagnosticsContext? = nil) async throws -> ChatPollResponse {
        let url = baseURL
            .appendingPathComponent("/v1/transmissions")
            .appendingPathComponent(transmissionId)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        let (data, http, responseInfo) = try await requestJSON(req, diagnostics: diagnostics)
        try require2xx(http, data: data, responseInfo: responseInfo)

        let decoded = try JSONDecoder().decode(TransmissionResponse.self, from: data)
        let pending = decoded.pending ?? (decoded.transmission.status == "created")

        return ChatPollResponse(
            pending: pending,
            assistant: decoded.assistant,
            serverStatus: decoded.transmission.status,
            statusCode: http.statusCode,
            responseInfo: responseInfo,
            threadMemento: decoded.threadMemento,
            evidenceSummary: nil,  // Poll endpoint doesn't return evidence for MVP
            evidence: nil,
            evidenceWarnings: nil,
            outputEnvelope: nil
        )
    }
}
