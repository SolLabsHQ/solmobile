//
//  SSEEventModels.swift
//  SolMobile
//
//  Created by SolMobile SSE.
//

import Foundation

enum SSEEventKind: String, Codable {
    case ping
    case txAccepted = "tx_accepted"
    case runStarted = "run_started"
    case assistantFinalReady = "assistant_final_ready"
    case assistantFailed = "assistant_failed"
}

struct SSESubject: Codable {
    let type: String
    let transmissionId: String?
    let threadId: String?
    let clientRequestId: String?
    let userId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case transmissionId = "transmission_id"
        case threadId = "thread_id"
        case clientRequestId = "client_request_id"
        case userId = "user_id"
    }
}

struct SSETrace: Codable {
    let traceRunId: String?

    enum CodingKeys: String, CodingKey {
        case traceRunId = "trace_run_id"
    }
}

struct SSEEventEnvelope: Codable {
    let v: Int
    let ts: String
    let kind: SSEEventKind
    let subject: SSESubject
    let trace: SSETrace?
    let payload: [String: JSONValue]
}

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}
