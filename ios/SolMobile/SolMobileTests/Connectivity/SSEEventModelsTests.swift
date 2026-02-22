//
//  SSEEventModelsTests.swift
//  SolMobileTests
//

import XCTest
@testable import SolMobile

@MainActor
final class SSEEventModelsTests: XCTestCase {
    func testEnvelopeDecodingMapsSnakeCaseAndPayload() throws {
        let json = """
        {
          "v": 1,
          "ts": "2026-02-17T00:00:00Z",
          "kind": "tx_accepted",
          "subject": {
            "type": "transmission",
            "transmission_id": "tx-100",
            "thread_id": "thread-100",
            "client_request_id": "cr-100",
            "user_id": "user-100"
          },
          "trace": { "trace_run_id": "trace-1" },
          "payload": {
            "code": "OK",
            "retryable": true,
            "retry_after_ms": 500,
            "extra": { "k": "v" },
            "list": [1, "two", false]
          }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let envelope = try JSONDecoder().decode(SSEEventEnvelope.self, from: data)

        XCTAssertEqual(envelope.v, 1)
        XCTAssertEqual(envelope.kind, .txAccepted)
        XCTAssertEqual(envelope.subject.transmissionId, "tx-100")
        XCTAssertEqual(envelope.subject.threadId, "thread-100")
        XCTAssertEqual(envelope.subject.clientRequestId, "cr-100")
        XCTAssertEqual(envelope.subject.userId, "user-100")
        XCTAssertEqual(envelope.trace?.traceRunId, "trace-1")

        if case .string(let code) = envelope.payload["code"] {
            XCTAssertEqual(code, "OK")
        } else {
            XCTFail("Expected code payload as string")
        }

        if case .bool(let retryable) = envelope.payload["retryable"] {
            XCTAssertTrue(retryable)
        } else {
            XCTFail("Expected retryable payload as bool")
        }

        if case .number(let retryAfterMs) = envelope.payload["retry_after_ms"] {
            XCTAssertEqual(retryAfterMs, 500)
        } else {
            XCTFail("Expected retry_after_ms payload as number")
        }
    }

    func testJSONValueDecodesPrimitiveTypes() throws {
        let json = """
        {
          "string": "hello",
          "number": 2.5,
          "bool": true,
          "null": null,
          "object": { "a": 1 },
          "array": [1, "two", false]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: data)

        if case .string(let value) = decoded["string"] {
            XCTAssertEqual(value, "hello")
        } else {
            XCTFail("Expected string value")
        }

        if case .number(let value) = decoded["number"] {
            XCTAssertEqual(value, 2.5)
        } else {
            XCTFail("Expected number value")
        }

        if case .bool(let value) = decoded["bool"] {
            XCTAssertTrue(value)
        } else {
            XCTFail("Expected bool value")
        }

        if case .null = decoded["null"] {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected null value")
        }

        if case .object(let objectValue) = decoded["object"] {
            if case .number(let nested) = objectValue["a"] {
                XCTAssertEqual(nested, 1)
            } else {
                XCTFail("Expected object.a to be number")
            }
        } else {
            XCTFail("Expected object value")
        }

        if case .array(let arrayValue) = decoded["array"] {
            XCTAssertEqual(arrayValue.count, 3)
        } else {
            XCTFail("Expected array value")
        }
    }
}
