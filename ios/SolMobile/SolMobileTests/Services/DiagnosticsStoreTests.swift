//
//  DiagnosticsStoreTests.swift
//  SolMobileTests
//

import XCTest
@testable import SolMobile

@MainActor
final class DiagnosticsStoreTests: XCTestCase {
    private static let sharedStore = DiagnosticsStore.makeTestStore()

    override func setUp() async throws {
        try await super.setUp()
        Self.sharedStore.clear()
    }

    override func tearDown() async throws {
        Self.sharedStore.clear()
        try await super.tearDown()
    }
    func testRedactedRequestHeadersDropSensitiveFields() {
        let headers = [
            "Authorization": "Bearer real",
            "Cookie": "a=b",
            "X-Api-Key": "secret",
            "X-Token-Value": "token",
            "X-Secret-Thing": "secret",
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]

        let redacted = DiagnosticsStore.redactedRequestHeaders(headers)

        XCTAssertNil(redacted["Authorization"])
        XCTAssertNil(redacted["Cookie"])
        XCTAssertNil(redacted["X-Api-Key"])
        XCTAssertNil(redacted["X-Token-Value"])
        XCTAssertNil(redacted["X-Secret-Thing"])
        XCTAssertEqual(redacted["Content-Type"], "application/json")
        XCTAssertEqual(redacted["Accept"], "application/json")
    }

    func testRedactedURLStringMasksSensitiveQueryParams() {
        let url = URL(string: "https://example.com/path?api_key=123&token=abc&sig=1&signature=2&expires=3&foo=bar")!
        let redacted = DiagnosticsStore.redactedURLString(from: url)
        let components = URLComponents(string: redacted)
        let items = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(items["api_key"], "<redacted>")
        XCTAssertEqual(items["token"], "<redacted>")
        XCTAssertEqual(items["sig"], "<redacted>")
        XCTAssertEqual(items["signature"], "<redacted>")
        XCTAssertEqual(items["expires"], "<redacted>")
        XCTAssertEqual(items["foo"], "bar")
    }

    func testCurlCommandUsesRedactedAuthorizationAndContentType() {
        let entry = DiagnosticsEntry(
            method: "POST",
            url: "https://example.com/v1/chat",
            responseURL: nil,
            redirectChain: [],
            status: 401,
            latencyMs: 120,
            retryableInferred: nil,
            retryableSource: nil,
            parsedErrorCode: nil,
            traceRunId: nil,
            attemptId: nil,
            threadId: nil,
            localTransmissionId: nil,
            transmissionId: nil,
            errorDomain: nil,
            errorCode: nil,
            errorDescription: nil,
            responseSnippet: "unauthorized",
            safeResponseHeaders: [:],
            requestHeaders: ["Accept": "application/json"],
            requestBodySnippet: "{\"message\":\"hi\"}",
            hadAuthorization: true
        )

        let curl = Self.sharedStore.curlCommand(for: entry)

        XCTAssertTrue(curl.contains("-X POST"))
        XCTAssertTrue(curl.contains("Authorization: Bearer <API_KEY>"))
        XCTAssertTrue(curl.contains("Content-Type: application/json"))
        XCTAssertTrue(curl.contains("--data-raw"))
        XCTAssertFalse(curl.contains("Bearer real"))
    }

    func testRingBufferTrimsToFiftyEntries() {
        let store = Self.sharedStore

        for index in 0..<60 {
            let entry = DiagnosticsEntry(
                method: "GET",
                url: "https://example.com/\(index)",
                responseURL: nil,
                redirectChain: [],
                status: 200,
                latencyMs: 10,
                retryableInferred: nil,
                retryableSource: nil,
                parsedErrorCode: nil,
                traceRunId: nil,
                attemptId: nil,
                threadId: nil,
                localTransmissionId: nil,
                transmissionId: nil,
                errorDomain: nil,
                errorCode: nil,
                errorDescription: nil,
                responseSnippet: nil,
                safeResponseHeaders: [:],
                requestHeaders: [:],
                requestBodySnippet: nil,
                hadAuthorization: false
            )
            store.appendForTesting(entry)
        }

        XCTAssertEqual(store.entries.count, 50)
        XCTAssertEqual(store.entries.first?.url, "https://example.com/59")
        XCTAssertEqual(store.entries.last?.url, "https://example.com/10")
    }

    func testExportIncludesRedactionMarker() {
        let export = Self.sharedStore.exportText()

        XCTAssertTrue(export.contains("DIAGNOSTICS_EXPORT_REDACTED=true"))
        XCTAssertTrue(export.contains("exported_at="))
        XCTAssertTrue(export.contains("app_version="))
    }
}
