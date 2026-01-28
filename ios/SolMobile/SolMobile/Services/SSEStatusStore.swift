//
//  SSEStatusStore.swift
//  SolMobile
//
//  Created by SolMobile SSE.
//

import Foundation
import Combine

@MainActor
final class SSEStatusStore: ObservableObject {
    static let shared = SSEStatusStore()

    enum ConnectionState: String {
        case connected
        case connecting
        case disconnected
    }

    struct FailureDetail: Equatable {
        let code: String?
        let detail: String?
        let retryable: Bool?
        let retryAfterMs: Double?
        let category: String?
    }

    struct TransmissionStage: Equatable {
        let kind: SSEEventKind
        let transmissionId: String
        let threadId: String?
        let updatedAt: Date
        let failure: FailureDetail?
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var syncPending: Bool = false
    @Published private(set) var lastEventAt: Date? = nil
    @Published private(set) var transmissionStages: [String: TransmissionStage] = [:]
    @Published private(set) var latestStageByThread: [String: TransmissionStage] = [:]

    private let syncPendingDelay: TimeInterval = 60
    private var pendingTask: Task<Void, Never>?

    func markConnecting() {
        state = .connecting
        syncPending = false
        cancelPendingTask()
    }

    func markConnected() {
        state = .connected
        syncPending = false
        cancelPendingTask()
    }

    func markDisconnected() {
        state = .disconnected
        scheduleSyncPending()
    }

    func markEventReceived() {
        lastEventAt = Date()
    }

    func recordEnvelope(_ envelope: SSEEventEnvelope) {
        guard let transmissionId = envelope.subject.transmissionId else { return }
        let failureDetail = envelope.kind == .assistantFailed
            ? parseFailureDetail(from: envelope.payload)
            : nil
        let stage = TransmissionStage(
            kind: envelope.kind,
            transmissionId: transmissionId,
            threadId: envelope.subject.threadId,
            updatedAt: Date(),
            failure: failureDetail
        )
        transmissionStages[transmissionId] = stage
        if let threadId = envelope.subject.threadId, !threadId.isEmpty {
            latestStageByThread[threadId] = stage
        }
    }

    func latestStage(forThreadId threadId: String) -> TransmissionStage? {
        latestStageByThread[threadId]
    }

    func failureDetail(forThreadId threadId: String) -> FailureDetail? {
        guard let stage = latestStageByThread[threadId], stage.kind == .assistantFailed else { return nil }
        return stage.failure
    }

    private func scheduleSyncPending() {
        cancelPendingTask()
        pendingTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.syncPendingDelay * 1_000_000_000))
            guard self.state == .disconnected else { return }
            self.syncPending = true
        }
    }

    private func cancelPendingTask() {
        pendingTask?.cancel()
        pendingTask = nil
    }

    private func parseFailureDetail(from payload: [String: JSONValue]) -> FailureDetail {
        let code = payload["code"]?.stringValue
        let detail = payload["detail"]?.stringValue
        let retryable = payload["retryable"]?.boolValue
        let retryAfterMs = payload["retry_after_ms"]?.numberValue
        let category = payload["category"]?.stringValue
        return FailureDetail(
            code: code,
            detail: detail,
            retryable: retryable,
            retryAfterMs: retryAfterMs,
            category: category
        )
    }
}
