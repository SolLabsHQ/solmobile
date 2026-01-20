//
//  SolServerClientDecodingTests.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import XCTest
@testable import SolMobile

final class SolServerClientDecodingTests: XCTestCase {

    func test_threadMementoDTO_decodes_from_solserver_shape() throws {
        let json = """
        {
          "id": "m1",
          "threadId": "t1",
          "createdAt": "2025-12-25T19:21:15.279Z",
          "version": "memento-v0",
          "arc": "SolServer v0 build",
          "active": ["hello solserver"],
          "parked": [],
          "decisions": [],
          "next": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ThreadMementoDTO.self, from: json)
        XCTAssertEqual(decoded.id, "m1")
        XCTAssertEqual(decoded.threadId, "t1")
        XCTAssertEqual(decoded.createdAt, "2025-12-25T19:21:15.279Z")
        XCTAssertEqual(decoded.version, "memento-v0")
        XCTAssertEqual(decoded.arc, "SolServer v0 build")
        XCTAssertEqual(decoded.active.first, "hello solserver")
    }

    func test_decisionResult_decodes_minimal_shape() throws {
        let json = """
        {
          "ok": true,
          "decision": "accept",
          "applied": true,
          "reason": "applied",
          "memento": {
            "id": "m2",
            "threadId": "t1",
            "createdAt": "2025-12-26T00:19:38.134Z",
            "version": "memento-v0",
            "arc": "Arc",
            "active": [],
            "parked": [],
            "decisions": [],
            "next": []
          }
        }
        """.data(using: .utf8)!

        struct MementoDecisionResponse: Decodable {
            let ok: Bool
            let decision: String
            let applied: Bool
            let reason: String?
            let memento: ThreadMementoDTO?
        }

        let decoded = try JSONDecoder().decode(MementoDecisionResponse.self, from: json)
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.decision, "accept")
        XCTAssertTrue(decoded.applied)
        XCTAssertEqual(decoded.reason, "applied")
        XCTAssertEqual(decoded.memento?.id, "m2")
    }

    func test_chatResponse_decodes_success_shape_200() throws {
        let json = """
        {
          "ok": true,
          "transmissionId": "tx-200",
          "assistant": "[Ida] hello",
          "pending": false,
          "threadMemento": {
            "id": "m1",
            "threadId": "t1",
            "createdAt": "2025-12-25T19:21:15.279Z",
            "version": "memento-v0",
            "arc": "SolServer v0 build",
            "active": ["hello solserver"],
            "parked": [],
            "decisions": [],
            "next": []
          }
        }
        """.data(using: .utf8)!

        struct ChatResponseEnvelope: Decodable {
            let ok: Bool
            let transmissionId: String?
            let assistant: String?
            let pending: Bool?
            let status: String?
            let threadMemento: ThreadMementoDTO?
        }

        let decoded: ChatResponseEnvelope = try JSONDecoder().decode(ChatResponseEnvelope.self, from: json)
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.transmissionId, "tx-200")
        XCTAssertEqual(decoded.assistant, "[Ida] hello")
        XCTAssertEqual(decoded.pending, false)
        XCTAssertNil(decoded.status)
        XCTAssertEqual(decoded.threadMemento?.id, "m1")
    }

    func test_chatResponse_decodes_pending_shape_202() throws {
        // 202 responses may omit assistant text and rely on polling.
        let json = """
        {
          "ok": true,
          "transmissionId": "tx-202",
          "pending": true,
          "status": "created",
          "threadMemento": {
            "id": "m2",
            "threadId": "t1",
            "createdAt": "2025-12-26T00:19:38.134Z",
            "version": "memento-v0",
            "arc": "Arc",
            "active": [],
            "parked": [],
            "decisions": [],
            "next": []
          }
        }
        """.data(using: .utf8)!

        struct ChatResponseEnvelope: Decodable {
            let ok: Bool
            let transmissionId: String?
            let assistant: String?
            let pending: Bool?
            let status: String?
            let threadMemento: ThreadMementoDTO?
        }

        let decoded: ChatResponseEnvelope = try JSONDecoder().decode(ChatResponseEnvelope.self, from: json)
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.transmissionId, "tx-202")
        XCTAssertNil(decoded.assistant)
        XCTAssertEqual(decoded.pending, true)
        XCTAssertEqual(decoded.status, "created")
        XCTAssertEqual(decoded.threadMemento?.id, "m2")
    }

    func test_transportError_httpStatus_carriesCodeAndBody() throws {
        let err = TransportError.httpStatus(HTTPErrorInfo(code: 500, body: "boom"))

        switch err {
        case let .httpStatus(info):
            XCTAssertEqual(info.code, 500)
            XCTAssertEqual(info.body, "boom")
        default:
            XCTFail("Expected .httpStatus")
        }
    }
}
