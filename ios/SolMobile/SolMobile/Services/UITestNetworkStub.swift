//
//  UITestNetworkStub.swift
//  SolMobile
//

import Foundation

enum UITestNetworkStub {
    nonisolated private static let argument = "-ui_test_stub_network"

    nonisolated static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    nonisolated static func enableIfNeeded() {
        guard isEnabled else { return }
        URLProtocol.registerClass(UITestURLProtocol.self)
    }
}

nonisolated final class UITestURLProtocol: URLProtocol {
    private static let contentType = "application/json; charset=utf-8"
    private static let defaultSnippet = "Remembered for later."
    private static let defaultMemoryId = "mem-123"

    nonisolated(unsafe) private static var lastDistillTransmissionId: String = UUID().uuidString.lowercased()

    override nonisolated class func canInit(with request: URLRequest) -> Bool {
        guard UITestNetworkStub.isEnabled else { return false }
        guard let url = request.url else { return false }
        return url.path.hasPrefix("/v1/")
    }

    override nonisolated class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override nonisolated func startLoading() {
        guard let url = request.url else {
            finishWithError(code: 400, body: "{\"error\":\"invalid_url\"}")
            return
        }

        let path = url.path
        let method = request.httpMethod ?? "GET"

        if method == "POST" && path == "/v1/chat" {
            respondChat()
            return
        }

        if method == "POST" && path == "/v1/memories/distill" {
            respondDistill()
            return
        }

        if method == "GET" && path.hasPrefix("/v1/transmissions/") {
            let transmissionId = path.components(separatedBy: "/").last ?? "tx-stub"
            respondTransmission(id: transmissionId)
            return
        }

        if method == "GET" && path.hasPrefix("/v1/memories/") {
            let memoryId = path.components(separatedBy: "/").last ?? Self.defaultMemoryId
            respondMemoryDetail(id: memoryId)
            return
        }

        if method == "DELETE" && path.hasPrefix("/v1/memories/") {
            respondMemoryDelete()
            return
        }

        finishWithError(code: 404, body: "{\"error\":\"not_found\"}")
    }

    override nonisolated func stopLoading() {}

    override nonisolated init(
        request: URLRequest,
        cachedResponse: CachedURLResponse?,
        client: URLProtocolClient?
    ) {
        super.init(request: request, cachedResponse: cachedResponse, client: client)
    }

    private func respondChat() {
        let response: [String: Any] = [
            "ok": true,
            "transmissionId": UUID().uuidString.lowercased(),
            "assistant": "Noted.",
            "pending": false,
            "status": "completed",
            "evidenceSummary": [
                "captures": 0,
                "supports": 0,
                "claims": 0,
                "warnings": 0
            ],
            "outputEnvelope": [
                "assistant_text": "Noted.",
                "notification_policy": "muted",
                "meta": [
                    "display_hint": "ghost_card",
                    "ghost_kind": "memory_artifact",
                    "memory_id": Self.defaultMemoryId,
                    "rigor_level": "normal",
                    "snippet": Self.defaultSnippet,
                    "fact_null": false
                ]
            ]
        ]

        respondJSON(statusCode: 200, json: response, headers: [:])
    }

    private func respondDistill() {
        let transmissionId = UUID().uuidString.lowercased()
        Self.lastDistillTransmissionId = transmissionId

        let response: [String: Any] = [
            "request_id": "stub-request",
            "transmission_id": transmissionId,
            "status": "pending"
        ]

        respondJSON(
            statusCode: 202,
            json: response,
            headers: ["x-sol-transmission-id": transmissionId]
        )
    }

    private func respondTransmission(id: String) {
        let response: [String: Any] = [
            "ok": true,
            "transmission": [
                "id": id,
                "status": "completed"
            ],
            "pending": false,
            "assistant": "",
            "outputEnvelope": [
                "assistant_text": "",
                "notification_policy": "muted",
                "meta": [
                    "display_hint": "ghost_card",
                    "ghost_kind": "memory_artifact",
                    "memory_id": Self.defaultMemoryId,
                    "rigor_level": "normal",
                    "snippet": Self.defaultSnippet,
                    "fact_null": false
                ]
            ]
        ]

        respondJSON(statusCode: 200, json: response, headers: [:])
    }

    private func respondMemoryDetail(id: String) {
        let response: [String: Any] = [
            "request_id": "stub-memory-detail",
            "memory": [
                "memory_id": id,
                "type": "memory",
                "snippet": Self.defaultSnippet,
                "summary": Self.defaultSnippet,
                "lifecycle_state": "pinned",
                "memory_kind": "preference",
                "created_at": "2026-01-01T00:00:00.000Z",
                "updated_at": "2026-01-01T00:00:00.000Z"
            ]
        ]
        respondJSON(statusCode: 200, json: response, headers: [:])
    }

    private func respondMemoryDelete() {
        let response: [String: Any] = [
            "request_id": "stub-memory-delete"
        ]
        respondJSON(statusCode: 200, json: response, headers: [:])
    }

    private func respondJSON(statusCode: Int, json: [String: Any], headers: [String: String]) {
        let data = (try? JSONSerialization.data(withJSONObject: json, options: [])) ?? Data()
        let mergedHeaders = headers.merging(["Content-Type": Self.contentType]) { _, new in new }
        let http = HTTPURLResponse(
            url: request.url ?? URL(string: "http://localhost")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: mergedHeaders
        )!

        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func finishWithError(code: Int, body: String) {
        let headers = ["Content-Type": Self.contentType]
        let http = HTTPURLResponse(
            url: request.url ?? URL(string: "http://localhost")!,
            statusCode: code,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
