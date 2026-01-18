//
//  DiagnosticsStore.swift
//  SolMobile
//
//  Created by SolMobile Diagnostics.
//

import Foundation

struct DiagnosticsEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let method: String
    let url: String
    let status: Int?
    let latencyMs: Int?
    let errorDomain: String?
    let errorCode: Int?
    let errorDescription: String?
    let responseSnippet: String?
    let safeResponseHeaders: [String: String]
    let requestHeaders: [String: String]
    let requestBodySnippet: String?
    let hadAuthorization: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        method: String,
        url: String,
        status: Int?,
        latencyMs: Int?,
        errorDomain: String?,
        errorCode: Int?,
        errorDescription: String?,
        responseSnippet: String?,
        safeResponseHeaders: [String: String],
        requestHeaders: [String: String],
        requestBodySnippet: String?,
        hadAuthorization: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.url = url
        self.status = status
        self.latencyMs = latencyMs
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.errorDescription = errorDescription
        self.responseSnippet = responseSnippet
        self.safeResponseHeaders = safeResponseHeaders
        self.requestHeaders = requestHeaders
        self.requestBodySnippet = requestBodySnippet
        self.hadAuthorization = hadAuthorization
    }

    func exportText() -> String {
        var lines: [String] = []
        lines.append("Time: \(DiagnosticsEntry.isoFormatter.string(from: timestamp))")
        lines.append("Request: \(method) \(url)")

        if let status {
            lines.append("Status: HTTP \(status)")
        } else {
            lines.append("Status: (no response)")
        }

        if let latencyMs {
            lines.append("Latency: \(latencyMs)ms")
        }

        if let errorDescription {
            lines.append("Error: \(errorDescription)")
            if let errorDomain, let errorCode {
                lines.append("Error detail: \(errorDomain) (\(errorCode))")
            }
        }

        if !safeResponseHeaders.isEmpty {
            let headerPairs = safeResponseHeaders
                .sorted(by: { $0.key.lowercased() < $1.key.lowercased() })
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            lines.append("Response headers: \(headerPairs)")
        }

        if let responseSnippet, !responseSnippet.isEmpty {
            lines.append("Response snippet: \(responseSnippet)")
        }

        if !requestHeaders.isEmpty {
            let headerPairs = requestHeaders
                .sorted(by: { $0.key.lowercased() < $1.key.lowercased() })
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            lines.append("Request headers: \(headerPairs)")
        }

        if let requestBodySnippet, !requestBodySnippet.isEmpty {
            lines.append("Request body: \(requestBodySnippet)")
        }

        return lines.joined(separator: "\n")
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

@MainActor
final class DiagnosticsStore: ObservableObject {
    static let shared = DiagnosticsStore()

    @Published private(set) var entries: [DiagnosticsEntry] = []

    private let maxEntries = 50
    private let storageKey: String
    private let persistEnabled: Bool

    init(storageKey: String = "sol.dev.diagnostics.entries", persistEnabled: Bool = true) {
        self.storageKey = storageKey
        self.persistEnabled = persistEnabled
        if persistEnabled {
            load()
        }
    }

    static func makeTestStore() -> DiagnosticsStore {
        DiagnosticsStore(storageKey: "sol.dev.diagnostics.entries.test.\(UUID().uuidString)", persistEnabled: false)
    }

    nonisolated func record(
        method: String,
        url: URL?,
        status: Int?,
        latencyMs: Int?,
        error: Error?,
        responseData: Data?,
        responseHeaders: [AnyHashable: Any]?,
        requestHeaders: [String: String]?,
        requestBody: Data?,
        hadAuthorization: Bool
    ) {
        let urlString = DiagnosticsStore.redactedURLString(from: url)
        let safeHeaders = DiagnosticsStore.safeResponseHeaders(from: responseHeaders)
        let redactedHeaders = DiagnosticsStore.redactedRequestHeaders(requestHeaders)
        let responseSnippet = DiagnosticsStore.responseSnippet(from: responseData, status: status)
        let requestBodySnippet = DiagnosticsStore.bodySnippet(from: requestBody, limit: 500)
        let nsError = error as NSError?

        let entry = DiagnosticsEntry(
            method: method,
            url: urlString,
            status: status,
            latencyMs: latencyMs,
            errorDomain: nsError?.domain,
            errorCode: nsError?.code,
            errorDescription: nsError?.localizedDescription,
            responseSnippet: responseSnippet,
            safeResponseHeaders: safeHeaders,
            requestHeaders: redactedHeaders,
            requestBodySnippet: requestBodySnippet,
            hadAuthorization: hadAuthorization
        )

        Task { @MainActor in
            self.append(entry)
        }
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    func exportText() -> String {
        if entries.isEmpty {
            return "SolMobile Diagnostics\n(no entries)"
        }

        return "SolMobile Diagnostics\n\n" + entries.map { $0.exportText() }.joined(separator: "\n\n")
    }

    func lastFailureEntry() -> DiagnosticsEntry? {
        entries.first { entry in
            if let status = entry.status {
                return status >= 400
            }
            return entry.errorDescription != nil
        }
    }

    func curlCommand(for entry: DiagnosticsEntry) -> String {
        var parts: [String] = ["curl", "-X", entry.method, "'\(entry.url)'" ]

        if entry.hadAuthorization {
            parts.append("-H")
            parts.append("'Authorization: Bearer <API_KEY>'")
        }

        if let body = entry.requestBodySnippet, !body.isEmpty {
            if !entry.requestHeaders.keys.contains(where: { $0.lowercased() == "content-type" }) {
                parts.append("-H")
                parts.append("'Content-Type: application/json'")
            }
        }

        if !entry.requestHeaders.isEmpty {
            let headers = entry.requestHeaders
                .sorted(by: { $0.key.lowercased() < $1.key.lowercased() })
            for (key, value) in headers {
                parts.append("-H")
                parts.append("'\(key): \(value)'" )
            }
        }

        if let body = entry.requestBodySnippet, !body.isEmpty {
            parts.append("--data-raw")
            parts.append("'\(DiagnosticsStore.shellEscape(body))'")
        }

        return parts.joined(separator: " ")
    }

    func appendForTesting(_ entry: DiagnosticsEntry) {
        append(entry)
    }

    private func append(_ entry: DiagnosticsEntry) {
        var updated = [entry]
        updated.append(contentsOf: entries)
        if updated.count > maxEntries {
            updated = Array(updated.prefix(maxEntries))
        }
        entries = updated
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([DiagnosticsEntry].self, from: data) {
            entries = decoded
        }
    }

    private func persist() {
        guard persistEnabled else { return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func responseSnippet(from data: Data?, status: Int?) -> String? {
        guard let status, status >= 400 else { return nil }
        return bodySnippet(from: data, limit: 400)
    }

    private static func bodySnippet(from data: Data?, limit: Int) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let text = String(data: data, encoding: .utf8) ?? "(non-utf8 body)"
        if text.count <= limit {
            return text
        }
        let idx = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<idx])
    }

    private static func safeResponseHeaders(from headers: [AnyHashable: Any]?) -> [String: String] {
        guard let headers else { return [:] }
        let allowed = ["server", "cf-ray", "fly-request-id", "content-type"]
        var result: [String: String] = [:]

        for (key, value) in headers {
            let keyString = String(describing: key).lowercased()
            guard allowed.contains(keyString) else { continue }
            result[keyString] = String(describing: value)
        }

        return result
    }

    static func redactedRequestHeaders(_ headers: [String: String]?) -> [String: String] {
        guard let headers else { return [:] }
        var redacted: [String: String] = [:]
        for (key, value) in headers {
            if isSensitiveHeaderName(key) {
                continue
            }
            redacted[key] = value
        }
        return redacted
    }

    private static func shellEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    static func redactedURLString(from url: URL?) -> String {
        guard let url else { return "(unknown url)" }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        if let queryItems = components.queryItems, !queryItems.isEmpty {
            let redacted = queryItems.map { item in
                let lower = item.name.lowercased()
                if shouldRedactQueryParam(lower) {
                    return URLQueryItem(name: item.name, value: "<redacted>")
                }
                return item
            }
            components.queryItems = redacted
        }
        return components.string ?? url.absoluteString
    }

    static func isSensitiveHeaderName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower == "authorization" || lower == "cookie" {
            return true
        }
        return lower.contains("key") || lower.contains("token") || lower.contains("secret")
    }

    private static func shouldRedactQueryParam(_ name: String) -> Bool {
        let sensitive = ["api_key", "token", "sig", "signature", "expires"]
        return sensitive.contains(where: { name.contains($0) })
    }
}
