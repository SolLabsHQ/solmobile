//
//  SolServerClientRequestTests.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import XCTest
@testable import SolMobile

final class SolServerClientRequestTests: XCTestCase {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    private func jsonData(_ obj: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: obj, options: [])
    }

    private func requestBodyData(_ req: URLRequest) throws -> Data {
        if let body = req.httpBody { return body }
        guard let stream = req.httpBodyStream else {
            throw XCTSkip("Request had no httpBody or httpBodyStream")
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 16 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read < 0 { break }
            if read == 0 { break }
            data.append(buffer, count: read)
        }

        return data
    }

    // NOTE: Change these to your actual initializer shape if needed.
    private func makeClient() -> SolServerClient {
        let session = makeSession()
        return SolServerClient(
            baseURL: URL(string: "http://127.0.0.1:3333")!,
            session: session
        )
    }

    func test_chat_200_buildsRequest_andDecodesResponse() async throws {
        let client = makeClient()

        URLProtocolStub.requestHandler = { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.url?.path, "/v1/chat")
            XCTAssertTrue((req.value(forHTTPHeaderField: "Content-Type") ?? "").contains("application/json"))

            let body = try self.requestBodyData(req)
            let decoded = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            XCTAssertEqual(decoded["threadId"] as? String, "t1")
            XCTAssertEqual(decoded["clientRequestId"] as? String, "c1")
            XCTAssertEqual(decoded["message"] as? String, "hello")

            let responseObj: [String: Any] = [
                "ok": true,
                "transmissionId": "tx-200",
                "assistant": "[Ida] hi",
                "pending": false,
                "threadMemento": [
                    "id": "m1",
                    "threadId": "t1",
                    "createdAt": "2025-12-25T19:21:15.279Z",
                    "version": "memento-v0",
                    "arc": "Arc",
                    "active": ["a"],
                    "parked": [],
                    "decisions": [],
                    "next": []
                ]
            ]

            return URLProtocolStub.StubbedResponse(
                statusCode: 200,
                headers: ["content-type": "application/json"],
                body: self.jsonData(responseObj)
            )
        }

        // NOTE: Rename to your actual API.
        let res = try await client.chat(threadId: "t1", clientRequestId: "c1", message: "hello")

        XCTAssertEqual(res.transmissionId, "tx-200")
        XCTAssertTrue(res.pending == false)
        XCTAssertEqual(res.assistant, "[Ida] hi")
        XCTAssertEqual(res.threadMemento?.id, "m1")
    }

    func test_chat_202_pending_decodes_andPreservesTransmissionId() async throws {
        let client = makeClient()

        URLProtocolStub.requestHandler = { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.url?.path, "/v1/chat")

            let responseObj: [String: Any] = [
                "ok": true,
                "transmissionId": "tx-202",
                "pending": true,
                "status": "created",
                "threadMemento": [
                    "id": "m2",
                    "threadId": "t1",
                    "createdAt": "2025-12-26T00:19:38.134Z",
                    "version": "memento-v0",
                    "arc": "Arc",
                    "active": [],
                    "parked": [],
                    "decisions": [],
                    "next": []
                ]
            ]

            return URLProtocolStub.StubbedResponse(
                statusCode: 202,
                headers: ["content-type": "application/json", "x-sol-transmission-id": "tx-202"],
                body: self.jsonData(responseObj)
            )
        }

        // NOTE: Rename to your actual API.
        let res = try await client.chat(threadId: "t1", clientRequestId: "c1", message: "/pending please")

        XCTAssertEqual(res.transmissionId, "tx-202")
        XCTAssertTrue(res.pending == true)
        XCTAssertNil(res.assistant) // or empty string, depending on your API contract
        XCTAssertEqual(res.threadMemento?.id, "m2")
    }

    func test_chat_simulateStatus_setsHeader() async throws {
        let client = makeClient()

        URLProtocolStub.requestHandler = { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.url?.path, "/v1/chat")
            XCTAssertEqual(req.value(forHTTPHeaderField: "x-sol-simulate-status"), "202")

            let responseObj: [String: Any] = [
                "ok": true,
                "transmissionId": "tx-sim",
                "pending": true,
                "status": "created"
            ]

            return URLProtocolStub.StubbedResponse(
                statusCode: 202,
                headers: ["content-type": "application/json"],
                body: self.jsonData(responseObj)
            )
        }

        let res = try await client.chat(
            threadId: "t1",
            clientRequestId: "c1",
            message: "hello",
            simulateStatus: 202
        )

        XCTAssertEqual(res.transmissionId, "tx-sim")
        XCTAssertEqual(res.pending, true)
    }

    func test_chat_500_throws_andCarriesBody() async {
        let client = makeClient()

        URLProtocolStub.requestHandler = { req in
            XCTAssertEqual(req.url?.path, "/v1/chat")
            return URLProtocolStub.StubbedResponse(
                statusCode: 500,
                headers: ["content-type": "application/json"],
                body: #"{"ok":false,"error":"boom"}"#.data(using: .utf8)!
            )
        }

        do {
            _ = try await client.chat(threadId: "t1", clientRequestId: "c1", message: "hi")
            XCTFail("Expected throw")
        } catch let TransportError.httpStatus(code, body) {
            XCTAssertEqual(code, 500)
            XCTAssertTrue(body.contains("boom"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_mementoDecision_200_postsCorrectShape_andDecodes() async throws {
        let client = makeClient()

        URLProtocolStub.requestHandler = { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.url?.path, "/v1/memento/decision")

            let body = try self.requestBodyData(req)
            let decoded = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            XCTAssertEqual(decoded["threadId"] as? String, "t1")
            XCTAssertEqual(decoded["mementoId"] as? String, "m1")
            XCTAssertEqual(decoded["decision"] as? String, "accept")

            let responseObj: [String: Any] = [
                "ok": true,
                "decision": "accept",
                "applied": true,
                "reason": "applied",
                "memento": [
                    "id": "m1",
                    "threadId": "t1",
                    "createdAt": "2025-12-26T00:19:38.134Z",
                    "version": "memento-v0",
                    "arc": "Arc",
                    "active": [],
                    "parked": [],
                    "decisions": [],
                    "next": []
                ]
            ]

            return URLProtocolStub.StubbedResponse(
                statusCode: 200,
                headers: ["content-type": "application/json"],
                body: self.jsonData(responseObj)
            )
        }

        // NOTE: Rename to your actual API.
        let res = try await client.decideMemento(threadId: "t1", mementoId: "m1", decision: .accept)

        XCTAssertTrue(res.applied)
        XCTAssertEqual(res.reason, "applied")
        XCTAssertEqual(res.memento?.id, "m1")
    }

    func test_mementoDecision_non2xx_throwsHttpStatus_withBody() async {
        let client = makeClient()

        URLProtocolStub.requestHandler = { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.url?.path, "/v1/memento/decision")
            return URLProtocolStub.StubbedResponse(
                statusCode: 409,
                headers: ["content-type": "application/json"],
                body: #"{"ok":true,"applied":false,"reason":"already_accepted"}"#.data(using: .utf8)!
            )
        }

        do {
            _ = try await client.decideMemento(threadId: "t1", mementoId: "m1", decision: .accept)
            XCTFail("Expected throw")
        } catch let TransportError.httpStatus(code, body) {
            XCTAssertEqual(code, 409)
            XCTAssertTrue(body.contains("already_accepted"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_transmission_200_buildsRequest_andDecodesResponse() async throws {
        let client = makeClient()

        URLProtocolStub.requestHandler = { req in
            XCTAssertEqual(req.httpMethod, "GET")
            XCTAssertEqual(req.url?.path, "/v1/transmissions/tx1")

            let responseObj: [String: Any] = [
                "ok": true,
                "transmission": [
                    "id": "tx1",
                    "status": "completed"
                ],
                "pending": false,
                "assistant": "hi",
                "threadMemento": [
                    "id": "m9",
                    "threadId": "t1",
                    "createdAt": "2025-12-26T00:19:38.134Z",
                    "version": "memento-v0",
                    "arc": "Arc",
                    "active": [],
                    "parked": [],
                    "decisions": [],
                    "next": []
                ]
            ]

            return URLProtocolStub.StubbedResponse(
                statusCode: 200,
                headers: ["content-type": "application/json"],
                body: self.jsonData(responseObj)
            )
        }

        let res = try await client.transmission("tx1")
        XCTAssertEqual(res.transmission.id, "tx1")
        XCTAssertEqual(res.transmission.status, "completed")
        XCTAssertEqual(res.pending, false)
        XCTAssertEqual(res.assistant, "hi")
        XCTAssertEqual(res.threadMemento?.id, "m9")
    }

    func test_transmission_non2xx_throwsHttpStatus_withBody() async {
        let client = makeClient()

        URLProtocolStub.requestHandler = { req in
            XCTAssertEqual(req.httpMethod, "GET")
            XCTAssertEqual(req.url?.path, "/v1/transmissions/tx-bad")
            return URLProtocolStub.StubbedResponse(
                statusCode: 404,
                headers: ["content-type": "application/json"],
                body: #"{"ok":false,"error":"nope"}"#.data(using: .utf8)!
            )
        }

        do {
            _ = try await client.transmission("tx-bad")
            XCTFail("Expected throw")
        } catch let TransportError.httpStatus(code, body) {
            XCTAssertEqual(code, 404)
            XCTAssertTrue(body.contains("nope"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
