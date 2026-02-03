//
//  SolServerClient.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/23/25.
//

import Foundation
import Security

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
    let userMessageId: String?
    let assistantMessageId: String?

    // Present when SolServer auto-saves a ThreadMemento (Option 1).
    let threadMemento: ThreadMementoDTO?
    let journalOffer: JournalOfferRecord?
    
    // Evidence fields (PR #7.1 / PR #8)
    let evidenceSummary: EvidenceSummaryDTO  // Always present in successful responses
    let evidence: EvidenceDTO?  // Omitted when none
    let evidenceWarnings: [EvidenceWarningDTO]?  // Omitted when none

    enum CodingKeys: String, CodingKey {
        case ok
        case transmissionId
        case modeDecision
        case assistant
        case outputEnvelope
        case idempotentReplay
        case pending
        case status
        case userMessageId
        case assistantMessageId
        case messageId
        case threadMemento
        case journalOffer
        case evidenceSummary
        case evidence
        case evidenceWarnings
    }

    enum LegacyCodingKeys: String, CodingKey {
        case userMessageId = "user_message_id"
        case messageId = "message_id"
        case assistantMessageId = "assistant_message_id"
        case journalOffer = "journal_offer"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)

        ok = try container.decode(Bool.self, forKey: .ok)
        transmissionId = try container.decodeIfPresent(String.self, forKey: .transmissionId)
        modeDecision = try container.decodeIfPresent(ModeDecision.self, forKey: .modeDecision)
        assistant = try container.decodeIfPresent(String.self, forKey: .assistant)
        outputEnvelope = try container.decodeIfPresent(OutputEnvelopeDTO.self, forKey: .outputEnvelope)
        idempotentReplay = try container.decodeIfPresent(Bool.self, forKey: .idempotentReplay)
        pending = try container.decodeIfPresent(Bool.self, forKey: .pending)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        threadMemento = try container.decodeIfPresent(ThreadMementoDTO.self, forKey: .threadMemento)
        journalOffer = try container.decodeIfPresent(JournalOfferRecord.self, forKey: .journalOffer)
            ?? legacy.decodeIfPresent(JournalOfferRecord.self, forKey: .journalOffer)
        evidenceSummary = try container.decode(EvidenceSummaryDTO.self, forKey: .evidenceSummary)
        evidence = try container.decodeIfPresent(EvidenceDTO.self, forKey: .evidence)
        evidenceWarnings = try container.decodeIfPresent([EvidenceWarningDTO].self, forKey: .evidenceWarnings)

        userMessageId = try container.decodeIfPresent(String.self, forKey: .userMessageId)
            ?? container.decodeIfPresent(String.self, forKey: .messageId)
            ?? legacy.decodeIfPresent(String.self, forKey: .userMessageId)
            ?? legacy.decodeIfPresent(String.self, forKey: .messageId)
        assistantMessageId = try container.decodeIfPresent(String.self, forKey: .assistantMessageId)
            ?? legacy.decodeIfPresent(String.self, forKey: .assistantMessageId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(transmissionId, forKey: .transmissionId)
        try container.encodeIfPresent(modeDecision, forKey: .modeDecision)
        try container.encodeIfPresent(assistant, forKey: .assistant)
        try container.encodeIfPresent(outputEnvelope, forKey: .outputEnvelope)
        try container.encodeIfPresent(idempotentReplay, forKey: .idempotentReplay)
        try container.encodeIfPresent(pending, forKey: .pending)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(userMessageId, forKey: .userMessageId)
        try container.encodeIfPresent(assistantMessageId, forKey: .assistantMessageId)
        try container.encodeIfPresent(threadMemento, forKey: .threadMemento)
        try container.encode(evidenceSummary, forKey: .evidenceSummary)
        try container.encodeIfPresent(evidence, forKey: .evidence)
        try container.encodeIfPresent(evidenceWarnings, forKey: .evidenceWarnings)
        try container.encodeIfPresent(journalOffer, forKey: .journalOffer)
    }
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
    let outputEnvelope: OutputEnvelopeDTO?
    let userMessageId: String?
    let assistantMessageId: String?

    // Present once the transmission is completed and the server has a memento snapshot.
    let threadMemento: ThreadMementoDTO?
    let journalOffer: JournalOfferRecord?

    enum CodingKeys: String, CodingKey {
        case ok
        case transmission
        case pending
        case assistant
        case outputEnvelope
        case userMessageId
        case assistantMessageId
        case messageId
        case threadMemento
        case journalOffer
    }

    enum LegacyCodingKeys: String, CodingKey {
        case userMessageId = "user_message_id"
        case messageId = "message_id"
        case assistantMessageId = "assistant_message_id"
        case journalOffer = "journal_offer"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)

        ok = try container.decode(Bool.self, forKey: .ok)
        transmission = try container.decode(TransmissionDTO.self, forKey: .transmission)
        pending = try container.decodeIfPresent(Bool.self, forKey: .pending)
        assistant = try container.decodeIfPresent(String.self, forKey: .assistant)
        outputEnvelope = try container.decodeIfPresent(OutputEnvelopeDTO.self, forKey: .outputEnvelope)
        threadMemento = try container.decodeIfPresent(ThreadMementoDTO.self, forKey: .threadMemento)
        journalOffer = try container.decodeIfPresent(JournalOfferRecord.self, forKey: .journalOffer)
            ?? legacy.decodeIfPresent(JournalOfferRecord.self, forKey: .journalOffer)

        userMessageId = try container.decodeIfPresent(String.self, forKey: .userMessageId)
            ?? container.decodeIfPresent(String.self, forKey: .messageId)
            ?? legacy.decodeIfPresent(String.self, forKey: .userMessageId)
            ?? legacy.decodeIfPresent(String.self, forKey: .messageId)
        assistantMessageId = try container.decodeIfPresent(String.self, forKey: .assistantMessageId)
            ?? legacy.decodeIfPresent(String.self, forKey: .assistantMessageId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ok, forKey: .ok)
        try container.encode(transmission, forKey: .transmission)
        try container.encodeIfPresent(pending, forKey: .pending)
        try container.encodeIfPresent(assistant, forKey: .assistant)
        try container.encodeIfPresent(outputEnvelope, forKey: .outputEnvelope)
        try container.encodeIfPresent(userMessageId, forKey: .userMessageId)
        try container.encodeIfPresent(assistantMessageId, forKey: .assistantMessageId)
        try container.encodeIfPresent(threadMemento, forKey: .threadMemento)
        try container.encodeIfPresent(journalOffer, forKey: .journalOffer)
    }
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

final class SolServerClient: ChatTransportPolling, ChatTransportMementoDecision, @unchecked Sendable {
    private let baseURLProvider: () -> URL
    var baseURL: URL { baseURLProvider() }
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
        self.baseURLProvider = { baseURL }
        self.redirectTracker = redirectTracker
        let resolvedConfig = configuration
        if #available(iOS 13.0, *) {
            resolvedConfig.tlsMinimumSupportedProtocolVersion = .TLSv12
        }
        Self.applyUITestProtocolIfNeeded(resolvedConfig)
        self.session = URLSession(
            configuration: resolvedConfig,
            delegate: redirectTracker,
            delegateQueue: nil
        )
    }

    init(
        baseURLProvider: @escaping () -> URL,
        configuration: URLSessionConfiguration = .default,
        redirectTracker: RedirectTracker = RedirectTracker()
    ) {
        self.baseURLProvider = baseURLProvider
        self.redirectTracker = redirectTracker
        let resolvedConfig = configuration
        if #available(iOS 13.0, *) {
            resolvedConfig.tlsMinimumSupportedProtocolVersion = .TLSv12
        }
        Self.applyUITestProtocolIfNeeded(resolvedConfig)
        self.session = URLSession(
            configuration: resolvedConfig,
            delegate: redirectTracker,
            delegateQueue: nil
        )
    }

    private static func applyUITestProtocolIfNeeded(_ configuration: URLSessionConfiguration) {
        guard UITestNetworkStub.isEnabled else { return }
        var classes = configuration.protocolClasses ?? []
        if !classes.contains(where: { $0 == UITestURLProtocol.self }) {
            classes.insert(UITestURLProtocol.self, at: 0)
        }
        configuration.protocolClasses = classes
    }

    /// Convenience init for app runtime where Settings controls the base URL.
    convenience init(configuration: URLSessionConfiguration = .default) {
        self.init(baseURLProvider: { SolServerBaseURL.effectiveURL() }, configuration: configuration)
    }

    // MARK: - Low-level HTTP helper

    private func requestJSON(
        _ req: URLRequest,
        diagnostics: DiagnosticsContext? = nil
    ) async throws -> (Data, HTTPURLResponse, ResponseInfo) {
        var authorizedReq = req
        applyUserIdHeader(&authorizedReq)
        applyLocalUserUuidHeader(&authorizedReq)
        applyAuthHeader(&authorizedReq)

        if AppEnvironment.current.requiresHTTPS,
           let url = authorizedReq.url,
           url.scheme?.lowercased() != "https" {
            let error = TransportError.insecureBaseURL(reason: "HTTPS required in \(AppEnvironment.current.rawValue)")
            DiagnosticsStore.recordAsync(
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

        let request = authorizedReq
        let hadAuthorization = request.value(forHTTPHeaderField: "Authorization") != nil
        let started = Date()
        let taskKey = UUID().uuidString

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { [weak self] data, response, error in
                guard let self else {
                    continuation.resume(throwing: URLError(.cancelled))
                    return
                }
                let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
                let redirectChain = self.redirectTracker.consumeChain(taskKey: taskKey)

                if let error {
                    let decision = RetryPolicy.classify(statusCode: nil, body: nil, headers: nil, error: error)
                    DiagnosticsStore.recordAsync(
                        method: request.httpMethod ?? "GET",
                        url: request.url,
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
                        requestHeaders: request.allHTTPHeaderFields,
                        requestBody: request.httpBody,
                        hadAuthorization: hadAuthorization
                    )
                    continuation.resume(throwing: error)
                    return
                }

                guard let data, let http = response as? HTTPURLResponse else {
                    let error = URLError(.badServerResponse)
                    DiagnosticsStore.recordAsync(
                        method: request.httpMethod ?? "GET",
                        url: request.url,
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
                        requestHeaders: request.allHTTPHeaderFields,
                        requestBody: request.httpBody,
                        hadAuthorization: hadAuthorization
                    )
                    continuation.resume(throwing: error)
                    return
                }

                let headers = normalizedHeaders(http.allHeaderFields)
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
                let traceRunId = extractTraceRunId(headers: headers, body: bodyString)
                let transmissionId = extractTransmissionId(headers: headers, body: bodyString)

                DiagnosticsStore.recordAsync(
                    method: request.httpMethod ?? "GET",
                    url: request.url,
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
                    requestHeaders: request.allHTTPHeaderFields,
                    requestBody: request.httpBody,
                    hadAuthorization: hadAuthorization
                )

                continuation.resume(returning: (data, http, responseInfo))
            }
            task.taskDescription = taskKey
            task.resume()
        }
    }

    private func applyAuthHeader(_ req: inout URLRequest) {
        guard let token = KeychainStore.read(key: KeychainKeys.stagingApiKey), !token.isEmpty else {
            return
        }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // SolServer staging accepts x-sol-api-key; send both for compatibility.
        req.setValue(token, forHTTPHeaderField: "x-sol-api-key")
    }

    private func applyUserIdHeader(_ req: inout URLRequest) {
        if req.value(forHTTPHeaderField: "x-sol-user-id") != nil {
            return
        }
        if req.value(forHTTPHeaderField: "x-user-id") != nil {
            return
        }
        req.setValue(UserIdentity.resolvedId(), forHTTPHeaderField: "x-sol-user-id")
    }

    private func applyLocalUserUuidHeader(_ req: inout URLRequest) {
        if req.value(forHTTPHeaderField: "x-sol-local-user-uuid") != nil {
            return
        }
        req.setValue(LocalIdentity.localUserUuid(), forHTTPHeaderField: "x-sol-local-user-uuid")
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

    // MARK: - Memory endpoints (PR #8)

    func distillMemory(request: MemoryDistillRequest) async throws -> MemoryDistillResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/memories/distill"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, http, responseInfo) = try await requestJSON(req)
        try require2xx(http, data: data, responseInfo: responseInfo)
        return try JSONDecoder().decode(MemoryDistillResponse.self, from: data)
    }

    func saveMemorySpan(request: MemorySpanSaveRequest) async throws -> MemoryCreateResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/memories"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, http, responseInfo) = try await requestJSON(req)
        try require2xx(http, data: data, responseInfo: responseInfo)
        return try JSONDecoder().decode(MemoryCreateResponse.self, from: data)
    }

    func listMemories(
        scope: String? = nil,
        threadId: String? = nil,
        lifecycleState: String? = nil,
        memoryKind: String? = nil,
        cursor: String? = nil,
        limit: Int? = nil,
        domain: String? = nil,
        tagsAny: [String]? = nil
    ) async throws -> MemoryListResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/memories"), resolvingAgainstBaseURL: false)
        var query: [URLQueryItem] = []
        if let scope { query.append(.init(name: "scope", value: scope)) }
        if let threadId { query.append(.init(name: "thread_id", value: threadId)) }
        if let lifecycleState { query.append(.init(name: "lifecycle_state", value: lifecycleState)) }
        if let memoryKind { query.append(.init(name: "memory_kind", value: memoryKind)) }
        if let cursor { query.append(.init(name: "cursor", value: cursor)) }
        if let limit { query.append(.init(name: "limit", value: String(limit))) }
        if let domain { query.append(.init(name: "domain", value: domain)) }
        if let tagsAny, !tagsAny.isEmpty {
            query.append(.init(name: "tags_any", value: tagsAny.joined(separator: ",")))
        }
        if !query.isEmpty {
            components?.queryItems = query
        }

        guard let url = components?.url else {
            throw TransportError.httpStatus(
                HTTPErrorInfo(code: 0, body: "Invalid memories URL", headers: [:], finalURL: nil, redirectChain: [])
            )
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        let (data, http, responseInfo) = try await requestJSON(req)
        try require2xx(http, data: data, responseInfo: responseInfo)
        return try JSONDecoder().decode(MemoryListResponse.self, from: data)
    }

    func createMemory(request: MemoryCreateRequest) async throws -> MemoryCreateResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/memories"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, http, responseInfo) = try await requestJSON(req)
        try require2xx(http, data: data, responseInfo: responseInfo)
        return try JSONDecoder().decode(MemoryCreateResponse.self, from: data)
    }

    func updateMemory(memoryId: String, request: MemoryPatchRequest) async throws -> MemoryPatchResponse {
        let url = baseURL.appendingPathComponent("/v1/memories").appendingPathComponent(memoryId)
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, http, responseInfo) = try await requestJSON(req)
        try require2xx(http, data: data, responseInfo: responseInfo)
        return try JSONDecoder().decode(MemoryPatchResponse.self, from: data)
    }

    func deleteMemory(memoryId: String, confirm: Bool? = nil) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/memories").appendingPathComponent(memoryId), resolvingAgainstBaseURL: false)
        if let confirm {
            components?.queryItems = [URLQueryItem(name: "confirm", value: confirm ? "true" : "false")]
        }
        guard let url = components?.url else {
            throw TransportError.httpStatus(
                HTTPErrorInfo(code: 0, body: "Invalid memories delete URL", headers: [:], finalURL: nil, redirectChain: [])
            )
        }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"

        let (data, http, responseInfo) = try await requestJSON(req)
        try require2xx(http, data: data, responseInfo: responseInfo)
        _ = data
    }

    func getMemory(memoryId: String) async throws -> MemoryDetailResponse {
        let url = baseURL.appendingPathComponent("/v1/memories").appendingPathComponent(memoryId)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        let (data, http, responseInfo) = try await requestJSON(req)
        try require2xx(http, data: data, responseInfo: responseInfo)
        return try JSONDecoder().decode(MemoryDetailResponse.self, from: data)
    }

    func batchDeleteMemories(request: MemoryBatchDeleteRequest) async throws -> MemoryBatchDeleteResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/memories/batch_delete"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, http, responseInfo) = try await requestJSON(req)
        try require2xx(http, data: data, responseInfo: responseInfo)
        return try JSONDecoder().decode(MemoryBatchDeleteResponse.self, from: data)
    }

    func clearAllMemories(request: MemoryClearAllRequest) async throws -> MemoryBatchDeleteResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/memories/clear_all"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, http, responseInfo) = try await requestJSON(req)
        try require2xx(http, data: data, responseInfo: responseInfo)
        return try JSONDecoder().decode(MemoryBatchDeleteResponse.self, from: data)
    }

    // MARK: - Journal drafts + trace events (PR10)

    func createJournalDraft(request: JournalDraftRequest) async throws -> JournalDraftEnvelope {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/journal/drafts"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, http, responseInfo) = try await requestJSON(req)
        try require2xx(http, data: data, responseInfo: responseInfo)
        return try JSONDecoder().decode(JournalDraftEnvelope.self, from: data)
    }

    func postTraceEvents(request: TraceEventsRequest) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/trace/events"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, http, responseInfo) = try await requestJSON(req)
        try require2xx(http, data: data, responseInfo: responseInfo)
        _ = data
    }

    // MARK: - ChatTransport / Outbox integration

    func send(envelope: PacketEnvelope, diagnostics: DiagnosticsContext? = nil) async throws -> ChatResponse {
        if envelope.packetType == "memory_distill" {
            return try await sendMemoryDistill(envelope: envelope, diagnostics: diagnostics)
        }

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
            clientRequestId: envelope.requestId,
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
                userMessageId: decoded?.userMessageId,
                assistantMessageId: decoded?.assistantMessageId,
                threadMemento: decoded?.threadMemento,
                journalOffer: decoded?.journalOffer?.asJournalOffer(),
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
            text: decoded.assistant ?? "",
            statusCode: http.statusCode,
            transmissionId: txId,
            pending: decoded.pending ?? false,
            responseInfo: responseInfo,
            userMessageId: decoded.userMessageId,
            assistantMessageId: decoded.assistantMessageId,
            threadMemento: decoded.threadMemento,
            journalOffer: decoded.journalOffer?.asJournalOffer(),
            evidenceSummary: decoded.evidenceSummary,
            evidence: decoded.evidence,
            evidenceWarnings: decoded.evidenceWarnings,
            outputEnvelope: decoded.outputEnvelope
        )
    }

    private func sendMemoryDistill(
        envelope: PacketEnvelope,
        diagnostics: DiagnosticsContext?
    ) async throws -> ChatResponse {
        guard let payload = envelope.payloadJson?.data(using: .utf8) else {
            throw TransportError.httpStatus(
                HTTPErrorInfo(code: 0, body: "Missing distill payload", headers: [:], finalURL: nil, redirectChain: [])
            )
        }

        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/memories/distill"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload

        let (data, http, responseInfo) = try await requestJSON(req, diagnostics: diagnostics)
        try require2xx(http, data: data, responseInfo: responseInfo)

        let decoded = try? JSONDecoder().decode(MemoryDistillResponse.self, from: data)
        let txId = decoded?.transmissionId

        return ChatResponse(
            text: "",
            statusCode: http.statusCode,
            transmissionId: txId,
            pending: true,
            responseInfo: responseInfo,
            userMessageId: nil,
            assistantMessageId: nil,
            threadMemento: nil,
            journalOffer: nil,
            evidenceSummary: nil,
            evidence: nil,
            evidenceWarnings: nil,
            outputEnvelope: nil
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
            userMessageId: decoded.userMessageId,
            assistantMessageId: decoded.assistantMessageId,
            threadMemento: decoded.threadMemento,
            journalOffer: decoded.journalOffer?.asJournalOffer(),
            evidenceSummary: nil,  // Poll endpoint doesn't return evidence for MVP
            evidence: nil,
            evidenceWarnings: nil,
            outputEnvelope: decoded.outputEnvelope
        )
    }
}

nonisolated func normalizedHeaders(_ headers: [AnyHashable: Any]) -> [String: String] {
    var normalized: [String: String] = [:]
    for (key, value) in headers {
        let keyString = String(describing: key).lowercased()
        normalized[keyString] = String(describing: value)
    }
    return normalized
}

nonisolated func extractTraceRunId(headers: [String: String], body: String?) -> String? {
    if let trace = headers["x-sol-trace-run-id"], !trace.isEmpty {
        return trace
    }
    return RetryPolicy.parseErrorEnvelope(from: body)?.traceRunId
}

nonisolated func extractTransmissionId(headers: [String: String], body: String?) -> String? {
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
