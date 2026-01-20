//
//  RetryPolicy.swift
//  SolMobile
//
//  Created by SolMobile Retry Policy.
//

import Foundation

nonisolated enum RetryableSource: String, Codable {
    case explicitField = "explicit_field"
    case httpStatus = "http_status"
    case networkError = "network_error"
    case parseFailedDefault = "parse_failed_default"
}

nonisolated struct ParsedErrorEnvelope {
    let errorCode: String?
    let retryable: Bool?
    let traceRunId: String?
    let transmissionId: String?
}

nonisolated struct RetryDecision {
    let retryable: Bool
    let source: RetryableSource
    let retryAfterSeconds: TimeInterval?
    let errorCode: String?
    let traceRunId: String?
    let transmissionId: String?
}

nonisolated enum RetryPolicy {
    static func classify(
        statusCode: Int?,
        body: String?,
        headers: [String: String]?,
        error: Error?
    ) -> RetryDecision {
        let parsed = parseErrorEnvelope(from: body)
        let traceRunId = parsed?.traceRunId
        let transmissionId = parsed?.transmissionId
        let errorCode = parsed?.errorCode

        guard let statusCode else {
            return RetryDecision(
                retryable: true,
                source: .networkError,
                retryAfterSeconds: nil,
                errorCode: errorCode,
                traceRunId: traceRunId,
                transmissionId: transmissionId
            )
        }

        if statusCode == 429 {
            return RetryDecision(
                retryable: true,
                source: .httpStatus,
                retryAfterSeconds: retryAfterSeconds(from: headers),
                errorCode: errorCode,
                traceRunId: traceRunId,
                transmissionId: transmissionId
            )
        }

        if statusCode >= 500 {
            return RetryDecision(
                retryable: true,
                source: .httpStatus,
                retryAfterSeconds: nil,
                errorCode: errorCode,
                traceRunId: traceRunId,
                transmissionId: transmissionId
            )
        }

        if statusCode == 422 {
            return RetryDecision(
                retryable: false,
                source: .httpStatus,
                retryAfterSeconds: nil,
                errorCode: errorCode,
                traceRunId: traceRunId,
                transmissionId: transmissionId
            )
        }

        if statusCode >= 400 {
            if let retryable = parsed?.retryable {
                return RetryDecision(
                    retryable: retryable,
                    source: .explicitField,
                    retryAfterSeconds: nil,
                    errorCode: errorCode,
                    traceRunId: traceRunId,
                    transmissionId: transmissionId
                )
            }

            return RetryDecision(
                retryable: false,
                source: .parseFailedDefault,
                retryAfterSeconds: nil,
                errorCode: errorCode,
                traceRunId: traceRunId,
                transmissionId: transmissionId
            )
        }

        return RetryDecision(
            retryable: false,
            source: .httpStatus,
            retryAfterSeconds: nil,
            errorCode: errorCode,
            traceRunId: traceRunId,
            transmissionId: transmissionId
        )
    }

    static func parseErrorEnvelope(from body: String?) -> ParsedErrorEnvelope? {
        guard let body, !body.isEmpty else { return nil }
        guard let data = body.data(using: .utf8) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let errorCode = stringValue(json["error"])
            ?? stringValue(json["error_code"])
            ?? stringValue(json["errorCode"])
            ?? stringValue((json["error"] as? [String: Any])?["code"])
            ?? stringValue((json["error"] as? [String: Any])?["error_code"])

        let retryable = boolValue(json["retryable"])
            ?? boolValue((json["error"] as? [String: Any])?["retryable"])

        let traceRunId = stringValue(json["traceRunId"])
            ?? stringValue(json["trace_run_id"])
            ?? stringValue((json["trace"] as? [String: Any])?["traceRunId"])

        let transmissionId = stringValue(json["transmissionId"])
            ?? stringValue(json["transmission_id"])

        return ParsedErrorEnvelope(
            errorCode: errorCode,
            retryable: retryable,
            traceRunId: traceRunId,
            transmissionId: transmissionId
        )
    }

    static func retryAfterSeconds(from headers: [String: String]?) -> TimeInterval? {
        guard let headers else { return nil }
        let retryAfterValue = headers.first { $0.key.lowercased() == "retry-after" }?.value
        guard let value = retryAfterValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(value) {
            return max(0, seconds)
        }

        if let date = httpDate(from: value) {
            let delta = date.timeIntervalSince(Date())
            return max(0, delta)
        }

        return nil
    }

    private static func httpDate(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let str = value as? String, !str.isEmpty {
            return str
        }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let b = value as? Bool {
            return b
        }
        return nil
    }
}
