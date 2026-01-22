
//
//  TransmissionAction.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/22/25.
//

import Foundation
import SwiftData
import os

// MARK: - Logging


// MARK: - Small helpers

nonisolated private func msSince(_ startNs: UInt64) -> Double {
    let endNs = DispatchTime.now().uptimeNanoseconds
    return Double(endNs &- startNs) / 1_000_000.0
}

nonisolated private func short(_ id: UUID) -> String {
    String(id.uuidString.prefix(8))
}

nonisolated private func shortOrDash(_ s: String?) -> String {
    (s?.isEmpty == false) ? s! : "-"
}

nonisolated private func timeWithSeconds(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = .autoupdatingCurrent
    f.timeZone = .autoupdatingCurrent
    f.dateFormat = "h:mm:ss a"
    return f.string(from: d)
}

// MARK: - ThreadMemento formatting

/// ThreadMemento is a navigation artifact returned by SolServer.
/// It is not durable knowledge; the client may choose to Accept / Decline / Revoke.
nonisolated private enum ThreadMementoFormatter {
    static func format(_ m: ThreadMementoDTO) -> String {
        func join(_ xs: [String]) -> String {
            guard !xs.isEmpty else { return "(none)" }
            return xs.joined(separator: " | ")
        }

        let arc = m.arc.isEmpty ? "(none)" : m.arc

        return [
            "Arc: \(arc)",
            "Active: \(join(m.active))",
            "Parked: \(join(m.parked))",
            "Decisions: \(join(m.decisions))",
            "Next: \(join(m.next))",
        ].joined(separator: "\n")
    }
}

// MARK: - Transport contracts

struct PacketEnvelope: Sendable {
    let packetId: UUID
    let packetType: String
    let threadId: UUID
    let messageIds: [UUID]
    let messageText: String
    let requestId: String
    let contextRefsJson: String?
    let payloadJson: String?
}

struct DiagnosticsContext: Sendable {
    let attemptId: UUID
    let threadId: UUID?
    let localTransmissionId: UUID?
}

protocol ChatTransport {
    func send(envelope: PacketEnvelope, diagnostics: DiagnosticsContext?) async throws -> ChatResponse
}

/// Optional capability: some transports can poll server-side delivery for pending (202) transmissions.
protocol ChatTransportPolling: ChatTransport {
    func poll(transmissionId: String, diagnostics: DiagnosticsContext?) async throws -> ChatPollResponse
}

// ThreadMemento decisions are user-controlled. In v0 they are applied server-side.
// - accept: draft -> accepted
// - decline: draft -> discarded
// - revoke: accepted -> cleared
// The client submits the decision and clears local draft fields for immediate UI updates.
enum ThreadMementoDecision: String, Codable, Sendable {
    /// Accept the current draft memento (promote to accepted).
    case accept

    /// Decline the current draft memento (discard draft).
    case decline

    /// Revoke the currently accepted memento (clear accepted state).
    /// In v0 this is a simple “forget it” switch; no historical restore.
    case revoke
}

struct ThreadMementoDecisionResult: Sendable {
    let statusCode: Int
    let applied: Bool
    let reason: String?
    let memento: ThreadMementoDTO?
}

protocol ChatTransportMementoDecision {
    func decideMemento(threadId: String, mementoId: String, decision: ThreadMementoDecision) async throws -> ThreadMementoDecisionResult
}

struct ChatPollResponse {
    let pending: Bool
    let assistant: String?
    let serverStatus: String?
    let statusCode: Int
    let responseInfo: ResponseInfo?

    let threadMemento: ThreadMementoDTO?
    
    // Evidence fields (PR #7.1 / PR #8)
    let evidenceSummary: EvidenceSummaryDTO?
    let evidence: EvidenceDTO?
    let evidenceWarnings: [EvidenceWarningDTO]?

    // OutputEnvelope (PR #23)
    let outputEnvelope: OutputEnvelopeDTO?
}

enum TransportError: Error {
    case simulatedFailure
    case httpStatus(HTTPErrorInfo)
    case insecureBaseURL(reason: String)

    /// The configured transport does not support a required optional capability.
    case unsupportedTransport(capability: String)
}

struct HTTPErrorInfo {
    let code: Int
    let body: String
    let headers: [String: String]
    let finalURL: URL?
    let redirectChain: [RedirectHop]

    init(
        code: Int,
        body: String,
        headers: [String: String] = [:],
        finalURL: URL? = nil,
        redirectChain: [RedirectHop] = []
    ) {
        self.code = code
        self.body = body
        self.headers = headers
        self.finalURL = finalURL
        self.redirectChain = redirectChain
    }
}

struct ChatResponse {
    let text: String
    let statusCode: Int
    let transmissionId: String?
    let pending: Bool
    let responseInfo: ResponseInfo?

    let threadMemento: ThreadMementoDTO?
    
    // Evidence fields (PR #7.1 / PR #8)
    let evidenceSummary: EvidenceSummaryDTO?
    let evidence: EvidenceDTO?
    let evidenceWarnings: [EvidenceWarningDTO]?

    // OutputEnvelope (PR #23)
    let outputEnvelope: OutputEnvelopeDTO?
}



// MARK: - Outbox processor

nonisolated final class TransmissionActions {

    private let outboxLog = Logger(subsystem: "com.sollabshq.solmobile", category: "Outbox")

    private let modelContext: ModelContext
    private let transport: any ChatTransport
    private let statusWatcher: TransmissionStatusWatcher?

    // v0 retry derivation (local-first): derived from DeliveryAttempt ledger.
    private let maxSendAttempts: Int = 6
    private let backoffCapSeconds: TimeInterval = 10
    private let pendingFastIntervalSeconds: TimeInterval = 2
    private let pendingLinearStartSeconds: TimeInterval = 10
    private let pendingLinearStepSeconds: TimeInterval = 2
    private let pendingSlowThresholdSeconds: TimeInterval = 60
    private let pendingSlowIntervalSeconds: TimeInterval = 20
    private let sendingStaleThresholdSeconds: TimeInterval = 60

    init(
        modelContext: ModelContext,
        transport: any ChatTransport,
        statusWatcher: TransmissionStatusWatcher? = nil
    ) {
        self.modelContext = modelContext
        self.transport = transport
        if let statusWatcher {
            self.statusWatcher = statusWatcher
        } else if let polling = transport as? any ChatTransportPolling {
            self.statusWatcher = PollingTransmissionStatusWatcher(transport: polling)
        } else {
            self.statusWatcher = nil
        }
    }

    private func backoffSeconds(forAttemptCount attemptCount: Int) -> TimeInterval {
        // attemptCount is prior attempts; 0 means "try now".
        guard attemptCount > 0 else { return 0 }
        let exp = min(attemptCount - 1, 10) // safety
        let secs = pow(2.0, Double(exp))
        return min(secs, backoffCapSeconds)
    }

    private func pendingSinceIfActive(_ attempts: [DeliveryAttempt]) -> Date? {
        guard let last = attempts.last else { return nil }

        if last.outcome == .pending {
            // Find the start of the trailing contiguous pending streak.
            var since = last.createdAt
            for a in attempts.reversed() {
                if a.outcome == .pending {
                    since = a.createdAt
                } else {
                    break
                }
            }
            return since
        }

        if last.source == .poll,
           last.outcome == .failed,
           last.retryableInferred == true {
            if let lastPending = attempts.reversed().first(where: { $0.outcome == .pending }) {
                return lastPending.createdAt
            }
            return last.createdAt
        }

        return nil
    }

    private func activePollAttempt(_ attempts: [DeliveryAttempt]) -> DeliveryAttempt? {
        guard let last = attempts.last else { return nil }
        if last.outcome == .pending {
            return last
        }
        if last.source == .poll,
           last.outcome == .failed,
           last.retryableInferred == true {
            return last
        }
        return nil
    }

    func enqueueChat(thread: ConversationThread, userMessage: Message) {
        let shouldFail = userMessage.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("/fail")

        enqueueChat(
            threadId: thread.id,
            messageId: userMessage.id,
            messageText: userMessage.text,
            shouldFail: shouldFail
        )
    }

    func enqueueMemoryDistill(
        threadId: UUID,
        messageIds: [UUID],
        payload: MemoryDistillRequest
    ) {
        let queuedRaw = TransmissionStatus.queued.rawValue
        let pendingRaw = TransmissionStatus.pending.rawValue
        let sendingRaw = TransmissionStatus.sending.rawValue
        let descriptor = FetchDescriptor<Transmission>(
            predicate: #Predicate {
                $0.packet.packetType == "memory_distill"
                    && $0.packet.threadId == threadId
                    && ($0.statusRaw == queuedRaw || $0.statusRaw == pendingRaw || $0.statusRaw == sendingRaw)
            },
            sortBy: [SortDescriptor(\Transmission.createdAt, order: .reverse)]
        )

        let existing = (try? modelContext.fetch(descriptor))?.first
        guard let encodedPayload = encodeMemoryPayload(
            payload,
            existing: existing
        ) else {
            outboxLog.error("enqueue_distill event=encode_failed thread=\(short(threadId), privacy: .public)")
            return
        }

        if let existing {
            existing.packet.payloadJson = encodedPayload
            existing.packet.messageIds = messageIds
            existing.packet.messageText = nil
            existing.lastError = nil
            if existing.status != .sending {
                existing.status = .queued
            }
            outboxLog.info("enqueue_distill event=updated tx=\(short(existing.id), privacy: .public) thread=\(short(threadId), privacy: .public)")
            try? modelContext.save()
            return
        }

        let packet = Packet(
            packetType: "memory_distill",
            threadId: threadId,
            messageIds: messageIds,
            messageText: nil,
            contextRefsJson: nil,
            payloadJson: encodedPayload
        )

        let tx = Transmission(
            type: "memory_distill",
            requestId: payload.requestId,
            status: .queued,
            packet: packet
        )

        modelContext.insert(packet)
        modelContext.insert(tx)
        try? modelContext.save()
        outboxLog.info("enqueue_distill event=created tx=\(short(tx.id), privacy: .public) thread=\(short(threadId), privacy: .public)")
    }

    private func encodeMemoryPayload(_ payload: MemoryDistillRequest, existing: Transmission?) -> String? {
        let existingPayload = existing?.packet.payloadJson.flatMap { json in
            try? JSONDecoder().decode(MemoryDistillRequest.self, from: Data(json.utf8))
        }

        let existingCount = existingPayload?.reaffirmCount ?? 0
        let incomingCount = payload.reaffirmCount ?? 0
        let reaffirm = (existingPayload == nil) ? incomingCount : max(existingCount + 1, incomingCount)

        let requestId = existing?.requestId ?? payload.requestId
        let updated = MemoryDistillRequest(
            threadId: payload.threadId,
            triggerMessageId: payload.triggerMessageId,
            contextWindow: payload.contextWindow,
            requestId: requestId,
            reaffirmCount: reaffirm,
            consent: payload.consent
        )

        if let data = try? JSONEncoder().encode(updated) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    func enqueueChat(threadId: UUID, messageId: UUID, messageText: String?, shouldFail: Bool) {
        outboxLog.info("enqueueChat thread=\(short(threadId), privacy: .public) msg=\(short(messageId), privacy: .public) shouldFail=\(shouldFail, privacy: .public)")

        let packet = Packet(
            threadId: threadId,
            messageIds: [messageId],
            messageText: messageText
        )
        packet.packetType = shouldFail ? "chat_fail" : "chat"

        outboxLog.info("enqueueChat packet=\(short(packet.id), privacy: .public) type=\(packet.packetType, privacy: .public)")

        modelContext.insert(packet)

        let tx = Transmission(packet: packet)
        modelContext.insert(tx)

        outboxLog.info("enqueueChat tx=\(short(tx.id), privacy: .public) status=queued")

        try? modelContext.save()
    }

    func processQueue(pollLimit: Int = 1, pollFirst: Bool = true) async {
        let runId = String(UUID().uuidString.prefix(8))
        outboxLog.info("processQueue run=\(runId, privacy: .public) event=start")

        defer {
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=end")
        }

        recoverStaleSending(runId: runId, now: Date())

        if pollFirst {
            await pollPending(runId: runId, limit: pollLimit)
        }
        await sendNextQueued(runId: runId)
        let trailingPollLimit = pollFirst ? 1 : pollLimit
        await pollPending(runId: runId, limit: trailingPollLimit)
    }

    // Poll up to N pending transmissions (does not block sending).
    private func pollPending(runId: String, limit: Int) async {
        guard let pending = fetchPendingSelections(runId: runId, limit: limit), !pending.isEmpty else {
            return
        }

        for sel in pending {
            guard let tx = try? fetchTransmission(id: sel.txId) else { continue }
            let now = Date()
            let attempts = sortedAttempts(tx.deliveryAttempts)

            guard let pendingSince = pendingSinceIfActive(attempts) else {
                recoverPendingWithoutActiveAttempt(runId: runId, tx: tx, attemptCount: attempts.count)
                continue
            }

            if shouldRespectPollBackoffAndExit(
                runId: runId,
                txId: sel.txId,
                attempts: attempts,
                pendingSince: pendingSince,
                now: now
            ) {
                continue
            }

            await pollOnce(runId: runId, sel: sel, attempts: attempts)
        }

        try? modelContext.save()
    }

    private func sendNextQueued(runId: String) async {
        guard let sel = fetchNextQueuedSelection(runId: runId) else {
            return
        }

        // Fetch a fresh Transmission instance for mutation.
        guard let tx = try? fetchTransmission(id: sel.txId) else {
            return
        }

        outboxLog.info(
            "processQueue run=\(runId, privacy: .public) event=selected tx=\(short(sel.txId), privacy: .public) packet=\(short(sel.packetId), privacy: .public) type=\(sel.packetType, privacy: .public) thread=\(short(sel.threadId), privacy: .public)"
        )

        let now = Date()
        let attempts = sortedAttempts(tx.deliveryAttempts)
        let sendAttempts = attempts.filter { $0.source == .send }
        let sendAttemptCount = sendAttempts.count

        // Client-side terminal conditions.
        if enforceSendAttemptLimit(runId: runId, tx: tx, txId: sel.txId, sendAttemptCount: sendAttemptCount) {
            return
        }

        // Respect backoff (quiet exit, remain queued).
        if shouldRespectSendBackoffAndExit(runId: runId, txId: sel.txId, sendAttempts: sendAttempts, sendAttemptCount: sendAttemptCount, now: now) {
            return
        }

        if sel.packetType == "memory_distill" {
            await sendMemoryDistillOnce(runId: runId, sel: sel)
        } else {
            await sendOnce(runId: runId, sel: sel)
        }
    }

    // MARK: - Outbox helpers (v0)

    private struct QueueSelection {
        let txId: UUID
        let packetId: UUID
        let packetType: String
        let threadId: UUID
        let messageIds: [UUID]
        let firstMessageId: UUID?
        let messageText: String?
        let payloadJson: String?
    }

    private struct PendingSelection {
        let txId: UUID
        let packetId: UUID
        let threadId: UUID
    }

    private func fetchNextQueuedSelection(runId: String) -> QueueSelection? {
        let queuedRaw = TransmissionStatus.queued.rawValue
        let descriptor = FetchDescriptor<Transmission>(
            predicate: #Predicate { $0.statusRaw == queuedRaw },
            sortBy: [SortDescriptor(\Transmission.createdAt, order: .forward)]
        )

        let sendingRaw = TransmissionStatus.sending.rawValue
        let sendingDescriptor = FetchDescriptor<Transmission>(
            predicate: #Predicate { $0.statusRaw == sendingRaw }
        )

        guard let queued = try? modelContext.fetch(descriptor) else {
            outboxLog.error("processQueue run=\(runId, privacy: .public) event=fetch_failed scope=queued")
            return nil
        }

        outboxLog.info("processQueue run=\(runId, privacy: .public) event=queued_count count=\(queued.count, privacy: .public)")

        guard let sending = try? modelContext.fetch(sendingDescriptor) else {
            outboxLog.error("processQueue run=\(runId, privacy: .public) event=fetch_failed scope=sending")
            return nil
        }

        let sendingThreadIds = Set(sending.map { $0.packet.threadId })

        guard let tx = queued.first(where: { !sendingThreadIds.contains($0.packet.threadId) }) else {
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=empty")
            return nil
        } // v0: one in-flight send per thread

        let packet = tx.packet
        return QueueSelection(
            txId: tx.id,
            packetId: packet.id,
            packetType: packet.packetType,
            threadId: packet.threadId,
            messageIds: packet.messageIds,
            firstMessageId: packet.messageIds.first,
            messageText: packet.messageText,
            payloadJson: packet.payloadJson
        )
    }

    private func fetchPendingSelections(runId: String, limit: Int) -> [PendingSelection]? {
        guard limit > 0 else { return [] }

        let pendingRaw = TransmissionStatus.pending.rawValue
        let descriptor = FetchDescriptor<Transmission>(
            predicate: #Predicate { $0.statusRaw == pendingRaw },
            sortBy: [SortDescriptor(\Transmission.createdAt, order: .forward)]
        )

        guard let pending = try? modelContext.fetch(descriptor) else {
            outboxLog.error("processQueue run=\(runId, privacy: .public) event=fetch_failed scope=pending")
            return nil
        }

        if pending.isEmpty {
            return []
        }

        return pending.prefix(limit).map { tx in
            PendingSelection(txId: tx.id, packetId: tx.packet.id, threadId: tx.packet.threadId)
        }
    }

    private func recoverStaleSending(runId: String, now: Date) {
        let sendingRaw = TransmissionStatus.sending.rawValue
        let descriptor = FetchDescriptor<Transmission>(
            predicate: #Predicate { $0.statusRaw == sendingRaw },
            sortBy: [SortDescriptor(\Transmission.createdAt, order: .forward)]
        )

        guard let sending = try? modelContext.fetch(descriptor) else {
            outboxLog.error("processQueue run=\(runId, privacy: .public) event=fetch_failed scope=sending")
            return
        }

        let stale = sending.filter { now.timeIntervalSince($0.createdAt) >= sendingStaleThresholdSeconds }
        guard !stale.isEmpty else { return }

        for tx in stale {
            tx.status = .queued
            tx.lastError = "Recovered stale sending transmission"
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=sending_recovered tx=\(short(tx.id), privacy: .public)")
        }

        try? modelContext.save()
    }

    private func sortedAttempts(_ attempts: [DeliveryAttempt]) -> [DeliveryAttempt] {
        attempts.sorted { $0.createdAt < $1.createdAt }
    }

    private func ensureRequestId(for tx: Transmission) -> (String, Bool) {
        let trimmed = tx.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            tx.requestId = tx.packet.id.uuidString
            return (tx.requestId, true)
        }
        return (tx.requestId, false)
    }

    private func recordAttempt(
        tx: Transmission,
        attemptId: UUID,
        statusCode: Int,
        outcome: DeliveryOutcome,
        source: DeliveryAttemptSource,
        errorMessage: String?,
        transmissionId: String?,
        retryableInferred: Bool?,
        retryAfterSeconds: Double?,
        finalURL: String?
    ) {
        let attempt = DeliveryAttempt(
            id: attemptId,
            statusCode: statusCode,
            outcome: outcome,
            source: source,
            errorMessage: errorMessage,
            transmissionId: transmissionId,
            retryableInferred: retryableInferred,
            retryAfterSeconds: retryAfterSeconds,
            finalURL: finalURL,
            transmission: tx
        )
        tx.deliveryAttempts.append(attempt)
        tx.deliveryAttempts.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
        modelContext.insert(attempt)
    }

    private func statusCode(from error: Error) -> Int {
        switch error {
        case TransportError.simulatedFailure:
            return 500
        case let TransportError.httpStatus(info):
            return info.code
        case TransportError.insecureBaseURL:
            return -1
        default:
            return -1
        }
    }

    private func errorMessage(from error: Error) -> String {
        switch error {
        case let TransportError.httpStatus(info):
            return info.body.isEmpty ? String(describing: error) : info.body
        case let TransportError.insecureBaseURL(reason):
            return reason
        default:
            return String(describing: error)
        }
    }

    private func httpErrorInfo(from error: Error) -> HTTPErrorInfo? {
        if case let TransportError.httpStatus(info) = error {
            return info
        }
        return nil
    }

    private func retryDecision(for error: Error) -> RetryDecision {
        if case TransportError.insecureBaseURL = error {
            return RetryDecision(
                retryable: false,
                source: .parseFailedDefault,
                retryAfterSeconds: nil,
                errorCode: "insecure_base_url",
                traceRunId: nil,
                transmissionId: nil
            )
        }

        if case TransportError.simulatedFailure = error {
            return RetryPolicy.classify(statusCode: nil, body: nil, headers: nil, error: error)
        }

        if let info = httpErrorInfo(from: error) {
            return RetryPolicy.classify(statusCode: info.code, body: info.body, headers: info.headers, error: error)
        }

        return RetryPolicy.classify(statusCode: nil, body: nil, headers: nil, error: error)
    }

    private func appendAssistantMessageIfPossible(
        threadId: UUID,
        assistantText: String?,
        transmissionId: String?,
        evidence: EvidenceDTO?,
        outputEnvelope: OutputEnvelopeDTO?,
        runId: String,
        txId: UUID,
        via: String
    ) {
        guard let thread = try? fetchThread(id: threadId) else { return }

        let text: String
        if let assistantText, !assistantText.isEmpty {
            text = assistantText
        } else {
            let hasGhostKind = outputEnvelope?.meta?.ghostKind != nil || outputEnvelope?.meta?.ghostType != nil
            if hasGhostKind {
                text = ""
            } else {
                text = "(missing assistant text)"
            }
        }
        let assistantMessage = Message(
            thread: thread,
            creatorType: .assistant,
            text: text,
            transmissionId: transmissionId
        )

        let evidenceModels: (captures: [Capture], supports: [ClaimSupport], claims: [ClaimMapEntry])

        do {
            evidenceModels = try assistantMessage.buildEvidenceModels(from: evidence)
        } catch {
            outboxLog.error(
                "processQueue run=\(runId, privacy: .public) event=evidence_mapping_failed tx=\(short(txId), privacy: .public) err=\(String(describing: error), privacy: .public)"
            )
            return
        }

        assistantMessage.hasEvidence = !evidenceModels.captures.isEmpty
            || !evidenceModels.supports.isEmpty
            || !evidenceModels.claims.isEmpty

        assistantMessage.applyOutputEnvelopeMeta(outputEnvelope)

        thread.messages.append(assistantMessage)
        thread.lastActiveAt = Date()

        modelContext.insert(assistantMessage)

        if assistantMessage.isGhostCard {
            upsertMemoryArtifact(from: assistantMessage)
        }

        if !evidenceModels.captures.isEmpty {
            assistantMessage.captures = evidenceModels.captures
            for capture in evidenceModels.captures {
                modelContext.insert(capture)
            }
        }

        if !evidenceModels.supports.isEmpty {
            assistantMessage.supports = evidenceModels.supports
            for support in evidenceModels.supports {
                modelContext.insert(support)
            }
        }

        if !evidenceModels.claims.isEmpty {
            assistantMessage.claims = evidenceModels.claims
            for claim in evidenceModels.claims {
                modelContext.insert(claim)
            }
        }

        DraftStore(modelContext: modelContext).deleteDraft(threadId: threadId)

        outboxLog.info("processQueue run=\(runId, privacy: .public) event=assistant_appended tx=\(short(txId), privacy: .public) via=\(via, privacy: .public)")
    }

    private func upsertMemoryArtifact(from message: Message) {
        guard let memoryId = message.ghostMemoryId, !memoryId.isEmpty else { return }

        let descriptor = FetchDescriptor<MemoryArtifact>(
            predicate: #Predicate { $0.memoryId == memoryId }
        )

        let existing = (try? modelContext.fetch(descriptor))?.first
        let typeRaw: String
        switch message.ghostKind {
        case .journalMoment:
            typeRaw = "journal"
        case .actionProposal:
            typeRaw = "action"
        case .memoryArtifact, .reverieInsight, .conflictResolver, .evidenceReceipt, .none:
            typeRaw = "memory"
        }

        if let existing {
            existing.threadId = message.thread.id.uuidString
            existing.triggerMessageId = message.ghostTriggerMessageId ?? existing.triggerMessageId
            existing.typeRaw = typeRaw
            existing.snippet = message.ghostSnippet ?? existing.snippet
            existing.moodAnchor = message.ghostMoodAnchor ?? existing.moodAnchor
            existing.rigorLevelRaw = message.ghostRigorLevelRaw ?? existing.rigorLevelRaw
            existing.updatedAt = Date()
            return
        }

        let artifact = MemoryArtifact(
            memoryId: memoryId,
            threadId: message.thread.id.uuidString,
            triggerMessageId: message.ghostTriggerMessageId,
            typeRaw: typeRaw,
            snippet: message.ghostSnippet,
            moodAnchor: message.ghostMoodAnchor,
            rigorLevelRaw: message.ghostRigorLevelRaw,
            createdAt: message.createdAt,
            updatedAt: message.createdAt
        )

        modelContext.insert(artifact)
    }

    private func sendOnce(runId: String, sel: QueueSelection) async {
        guard let tx = try? fetchTransmission(id: sel.txId) else { return }

        let startNs = DispatchTime.now().uptimeNanoseconds

        if await isBudgetBlockedNow() {
            tx.status = .failed
            tx.lastError = "budget_exceeded"
            let attemptId = UUID()

            recordAttempt(
                tx: tx,
                attemptId: attemptId,
                statusCode: 422,
                outcome: .failed,
                source: .send,
                errorMessage: "budget_exceeded(local)",
                transmissionId: nil,
                retryableInferred: false,
                retryAfterSeconds: nil,
                finalURL: nil
            )

            outboxLog.info(
                "processQueue run=\(runId, privacy: .public) event=budget_blocked tx=\(short(sel.txId), privacy: .public)"
            )
            try? modelContext.save()
            return
        }

        tx.status = .sending
        tx.lastError = nil
        outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=sending")

        let attemptId = UUID()
        let diagnostics = DiagnosticsContext(
            attemptId: attemptId,
            threadId: sel.threadId,
            localTransmissionId: sel.txId
        )

        do {
            let rawText = sel.messageText
                ?? (sel.firstMessageId.flatMap { try? fetchMessage(id: $0)?.text })
                ?? ""
            let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                tx.status = .failed
                tx.lastError = "Missing message text for send"

                recordAttempt(
                    tx: tx,
                    attemptId: attemptId,
                    statusCode: -1,
                    outcome: .failed,
                    source: .send,
                    errorMessage: tx.lastError,
                    transmissionId: nil,
                    retryableInferred: false,
                    retryAfterSeconds: nil,
                    finalURL: nil
                )

                outboxLog.error("processQueue run=\(runId, privacy: .public) event=missing_text tx=\(short(sel.txId), privacy: .public)")
                try? modelContext.save()
                return
            }

            let userText = rawText

            outboxLog.debug("processQueue run=\(runId, privacy: .public) event=context tx=\(short(sel.txId), privacy: .public) userTextLen=\(userText.count, privacy: .public)")

            let (requestId, didBackfill) = ensureRequestId(for: tx)
            if didBackfill {
                try? modelContext.save()
            }
            let envelope = PacketEnvelope(
                packetId: sel.packetId,
                packetType: sel.packetType,
                threadId: sel.threadId,
                messageIds: sel.messageIds,
                messageText: userText,
                requestId: requestId,
                contextRefsJson: nil,
                payloadJson: nil
            )

            outboxLog.info("processQueue run=\(runId, privacy: .public) event=send tx=\(short(sel.txId), privacy: .public)")

            let response = try await transport.send(envelope: envelope, diagnostics: diagnostics)

            outboxLog.info(
                "processQueue run=\(runId, privacy: .public) event=transport_ok tx=\(short(sel.txId), privacy: .public) http=\(response.statusCode, privacy: .public) pending=\(response.pending, privacy: .public) ms=\(msSince(startNs), format: .fixed(precision: 1))"
            )

            guard let freshTx = try? fetchTransmission(id: sel.txId) else { return }

            let outcome: DeliveryOutcome = (response.pending || response.statusCode == 202)
                ? .pending
                : (response.statusCode == 200 ? .succeeded : .failed)

            recordAttempt(
                tx: freshTx,
                attemptId: attemptId,
                statusCode: response.statusCode,
                outcome: outcome,
                source: .send,
                errorMessage: nil,
                transmissionId: response.transmissionId,
                retryableInferred: nil,
                retryAfterSeconds: nil,
                finalURL: response.responseInfo?.finalURL?.absoluteString
            )

            if let m = response.threadMemento {
                applyDraftMemento(runId: runId, freshTx: freshTx, txId: sel.txId, m: m, via: "send")
            }

            if response.pending || response.statusCode == 202 {
                freshTx.status = .pending
                outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=pending reason=pending")
                try? modelContext.save()

                let pendingSelection = PendingSelection(
                    txId: sel.txId,
                    packetId: sel.packetId,
                    threadId: sel.threadId
                )
                let pendingAttempts = sortedAttempts(freshTx.deliveryAttempts)
                await pollOnce(runId: runId, sel: pendingSelection, attempts: pendingAttempts)
                try? modelContext.save()
                return
            }

            appendAssistantMessageIfPossible(
                threadId: sel.threadId,
                assistantText: response.text,
                transmissionId: response.transmissionId,
                evidence: response.evidence,
                outputEnvelope: response.outputEnvelope,
                runId: runId,
                txId: sel.txId,
                via: "send"
            )

            freshTx.status = .succeeded
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=succeeded")
        } catch {
            outboxLog.error(
                "processQueue run=\(runId, privacy: .public) event=transport_failed tx=\(short(sel.txId), privacy: .public) ms=\(msSince(startNs), format: .fixed(precision: 1)) err=\(String(describing: error), privacy: .public)"
            )

            guard let freshTx = try? fetchTransmission(id: sel.txId) else { return }

            let decision = retryDecision(for: error)
            let code = statusCode(from: error)
            let msg = errorMessage(from: error)
            if let info = await budgetExceededInfo(from: error) {
                await applyBudgetExceeded(info)
            }

            let errorInfo = httpErrorInfo(from: error)

            recordAttempt(
                tx: freshTx,
                attemptId: attemptId,
                statusCode: code,
                outcome: .failed,
                source: .send,
                errorMessage: msg,
                transmissionId: decision.transmissionId,
                retryableInferred: decision.retryable,
                retryAfterSeconds: decision.retryAfterSeconds,
                finalURL: errorInfo?.finalURL?.absoluteString
            )

            freshTx.status = decision.retryable ? .queued : .failed
            freshTx.lastError = msg

            let outcome = decision.retryable ? "queued" : "failed"
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=\(outcome, privacy: .public) http=\(code, privacy: .public)")
        }

        try? modelContext.save()
    }

    private func sendMemoryDistillOnce(runId: String, sel: QueueSelection) async {
        guard let tx = try? fetchTransmission(id: sel.txId) else { return }

        let startNs = DispatchTime.now().uptimeNanoseconds

        tx.status = .sending
        tx.lastError = nil
        outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=sending")

        let attemptId = UUID()
        let diagnostics = DiagnosticsContext(
            attemptId: attemptId,
            threadId: sel.threadId,
            localTransmissionId: sel.txId
        )

        guard let payloadJson = sel.payloadJson, !payloadJson.isEmpty else {
            tx.status = .failed
            tx.lastError = "Missing distill payload for send"

            recordAttempt(
                tx: tx,
                attemptId: attemptId,
                statusCode: -1,
                outcome: .failed,
                source: .send,
                errorMessage: tx.lastError,
                transmissionId: nil,
                retryableInferred: false,
                retryAfterSeconds: nil,
                finalURL: nil
            )

            outboxLog.error("processQueue run=\(runId, privacy: .public) event=missing_payload tx=\(short(sel.txId), privacy: .public)")
            try? modelContext.save()
            return
        }

        let envelope = PacketEnvelope(
            packetId: sel.packetId,
            packetType: sel.packetType,
            threadId: sel.threadId,
            messageIds: sel.messageIds,
            messageText: "",
            requestId: tx.requestId,
            contextRefsJson: nil,
            payloadJson: payloadJson
        )

        do {
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=send_distill tx=\(short(sel.txId), privacy: .public)")

            let response = try await transport.send(envelope: envelope, diagnostics: diagnostics)

            outboxLog.info(
                "processQueue run=\(runId, privacy: .public) event=transport_ok tx=\(short(sel.txId), privacy: .public) http=\(response.statusCode, privacy: .public) pending=\(response.pending, privacy: .public) ms=\(msSince(startNs), format: .fixed(precision: 1))"
            )

            guard let freshTx = try? fetchTransmission(id: sel.txId) else { return }

            let outcome: DeliveryOutcome = (response.pending || response.statusCode == 202)
                ? .pending
                : (response.statusCode == 200 ? .succeeded : .failed)

            recordAttempt(
                tx: freshTx,
                attemptId: attemptId,
                statusCode: response.statusCode,
                outcome: outcome,
                source: .send,
                errorMessage: nil,
                transmissionId: response.transmissionId,
                retryableInferred: nil,
                retryAfterSeconds: nil,
                finalURL: response.responseInfo?.finalURL?.absoluteString
            )

            if response.pending || response.statusCode == 202 {
                freshTx.status = .pending
                outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=pending reason=pending")
                try? modelContext.save()

                let pendingSelection = PendingSelection(
                    txId: sel.txId,
                    packetId: sel.packetId,
                    threadId: sel.threadId
                )
                let pendingAttempts = sortedAttempts(freshTx.deliveryAttempts)
                await pollOnce(runId: runId, sel: pendingSelection, attempts: pendingAttempts)
                try? modelContext.save()
                return
            }

            freshTx.status = .succeeded
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=succeeded")
        } catch {
            outboxLog.error(
                "processQueue run=\(runId, privacy: .public) event=transport_failed tx=\(short(sel.txId), privacy: .public) ms=\(msSince(startNs), format: .fixed(precision: 1)) err=\(String(describing: error), privacy: .public)"
            )

            guard let freshTx = try? fetchTransmission(id: sel.txId) else { return }

            let decision = retryDecision(for: error)
            let code = statusCode(from: error)
            let msg = errorMessage(from: error)

            let errorInfo = httpErrorInfo(from: error)

            recordAttempt(
                tx: freshTx,
                attemptId: attemptId,
                statusCode: code,
                outcome: .failed,
                source: .send,
                errorMessage: msg,
                transmissionId: decision.transmissionId,
                retryableInferred: decision.retryable,
                retryAfterSeconds: decision.retryAfterSeconds,
                finalURL: errorInfo?.finalURL?.absoluteString
            )

            freshTx.status = decision.retryable ? .queued : .failed
            freshTx.lastError = msg

            let outcome = decision.retryable ? "queued" : "failed"
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=\(outcome, privacy: .public) http=\(code, privacy: .public)")
        }

        try? modelContext.save()
    }

    private func budgetExceededInfo(from error: Error) async -> BudgetExceededInfo? {
        guard case let TransportError.httpStatus(info) = error, info.code == 422 else { return nil }
        return await MainActor.run {
            BudgetStore.shared.parseBudgetExceeded(from: info.body)
        }
    }

    private func isBudgetBlockedNow() async -> Bool {
        await MainActor.run {
            BudgetStore.shared.isBlockedNow()
        }
    }

    private func applyBudgetExceeded(_ info: BudgetExceededInfo) async {
        await MainActor.run {
            BudgetStore.shared.applyBudgetExceeded(blockedUntil: info.blockedUntil)
        }
    }

    private func enforceSendAttemptLimit(
        runId: String,
        tx: Transmission,
        txId: UUID,
        sendAttemptCount: Int
    ) -> Bool {
        if sendAttemptCount >= maxSendAttempts {
            // Client-side terminal: too many send attempts.
            tx.status = .failed
            tx.lastError = "Max retry attempts exceeded (\(maxSendAttempts))"

            recordAttempt(
                tx: tx,
                attemptId: UUID(),
                statusCode: -1,
                outcome: .failed,
                source: .terminal,
                errorMessage: tx.lastError,
                transmissionId: nil,
                retryableInferred: false,
                retryAfterSeconds: nil,
                finalURL: nil
            )

            outboxLog.error("processQueue run=\(runId, privacy: .public) event=terminal_max_attempts tx=\(short(txId), privacy: .public) attempts=\(sendAttemptCount, privacy: .public)")
            return true
        }

        return false
    }

    private func shouldRespectSendBackoffAndExit(
        runId: String,
        txId: UUID,
        sendAttempts: [DeliveryAttempt],
        sendAttemptCount: Int,
        now: Date
    ) -> Bool {
        guard let last = sendAttempts.last else { return false }

        let backoff = backoffSeconds(forAttemptCount: sendAttemptCount)
        let retryAfter = last.retryAfterSeconds ?? 0
        let wait = max(backoff, retryAfter)
        let nextAt = last.createdAt.addingTimeInterval(wait)

        if now < nextAt {
            // Respect backoff: keep queued and exit quietly.
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=backoff tx=\(short(txId), privacy: .public) waitSec=\(wait, privacy: .public) nextAt=\(timeWithSeconds(nextAt), privacy: .public)")
            return true
        }

        return false
    }

    private func pollIntervalSeconds(pendingAge: TimeInterval, pollAttemptCount: Int) -> TimeInterval {
        if pendingAge <= pendingLinearStartSeconds {
            return pendingFastIntervalSeconds
        }

        if pendingAge <= pendingSlowThresholdSeconds {
            let steps = max(0, pollAttemptCount - 1)
            let interval = pendingFastIntervalSeconds + (TimeInterval(steps) * pendingLinearStepSeconds)
            return min(interval, pendingSlowIntervalSeconds)
        }

        return pendingSlowIntervalSeconds
    }

    private func shouldRespectPollBackoffAndExit(
        runId: String,
        txId: UUID,
        attempts: [DeliveryAttempt],
        pendingSince: Date,
        now: Date
    ) -> Bool {
        let pollAttempts = attempts.filter { $0.source == .poll }
        guard let lastPoll = pollAttempts.last else { return false }

        let pendingAge = now.timeIntervalSince(pendingSince)
        let wait = pollIntervalSeconds(pendingAge: pendingAge, pollAttemptCount: pollAttempts.count)
        let nextAt = lastPoll.createdAt.addingTimeInterval(wait)

        if now < nextAt {
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=poll_backoff tx=\(short(txId), privacy: .public) waitSec=\(wait, privacy: .public) nextAt=\(timeWithSeconds(nextAt), privacy: .public)")
            return true
        }

        return false
    }

    private func applyDraftMemento(runId: String, freshTx: Transmission, txId: UUID, m: ThreadMementoDTO, via: String) {
        freshTx.serverThreadMementoId = m.id
        freshTx.serverThreadMementoCreatedAtISO = m.createdAt
        freshTx.serverThreadMementoSummary = ThreadMementoFormatter.format(m)

        outboxLog.info("processQueue run=\(runId, privacy: .public) event=memento_draft_saved tx=\(short(txId), privacy: .public) memento=\(m.id, privacy: .public) via=\(via, privacy: .public)")
    }

    private func pollOnce(
        runId: String,
        sel: PendingSelection,
        attempts: [DeliveryAttempt]
    ) async {
        guard let last = activePollAttempt(attempts),
              let serverTxId = last.transmissionId,
              !serverTxId.isEmpty else {
            if let tx = try? fetchTransmission(id: sel.txId) {
                tx.status = .failed
                tx.lastError = "Missing server transmission id for pending poll"
                outboxLog.error("processQueue run=\(runId, privacy: .public) event=poll_missing_id tx=\(short(sel.txId), privacy: .public)")
            }
            return
        }

        outboxLog.info("processQueue run=\(runId, privacy: .public) event=poll_ready tx=\(short(sel.txId), privacy: .public) serverTx=\(shortOrDash(serverTxId), privacy: .public)")

        guard let tx = try? fetchTransmission(id: sel.txId) else { return }

        let attemptId = UUID()
        let diagnostics = DiagnosticsContext(
            attemptId: attemptId,
            threadId: sel.threadId,
            localTransmissionId: sel.txId
        )

        do {
            guard let watcher = statusWatcher else {
                outboxLog.error("processQueue run=\(runId, privacy: .public) event=poll_unavailable tx=\(short(sel.txId), privacy: .public)")
                tx.status = .failed
                tx.lastError = "Transport does not support polling"
                return
            }

            let poll = try await watcher.poll(transmissionId: serverTxId, diagnostics: diagnostics)

            guard let freshTx = try? fetchTransmission(id: sel.txId) else { return }

            recordAttempt(
                tx: freshTx,
                attemptId: attemptId,
                statusCode: poll.statusCode,
                outcome: poll.pending ? .pending : .succeeded,
                source: .poll,
                errorMessage: nil,
                transmissionId: serverTxId,
                retryableInferred: nil,
                retryAfterSeconds: nil,
                finalURL: poll.responseInfo?.finalURL?.absoluteString
            )

            if let m = poll.threadMemento {
                applyDraftMemento(runId: runId, freshTx: freshTx, txId: sel.txId, m: m, via: "poll")
            }

            if poll.pending {
                freshTx.status = .pending
                outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=pending reason=pending_poll")
                return
            }

            appendAssistantMessageIfPossible(
                threadId: sel.threadId,
                assistantText: poll.assistant,
                transmissionId: serverTxId,
                evidence: poll.evidence,
                outputEnvelope: poll.outputEnvelope,
                runId: runId,
                txId: sel.txId,
                via: "poll"
            )

            freshTx.status = .succeeded
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=succeeded reason=poll_complete")
        } catch {
            outboxLog.error("processQueue run=\(runId, privacy: .public) event=poll_failed tx=\(short(sel.txId), privacy: .public) err=\(String(describing: error), privacy: .public)")

            guard let freshTx = try? fetchTransmission(id: sel.txId) else { return }

            let decision = retryDecision(for: error)
            let errorInfo = httpErrorInfo(from: error)
            recordAttempt(
                tx: freshTx,
                attemptId: attemptId,
                statusCode: statusCode(from: error),
                outcome: .failed,
                source: .poll,
                errorMessage: errorMessage(from: error),
                transmissionId: decision.transmissionId ?? serverTxId,
                retryableInferred: decision.retryable,
                retryAfterSeconds: decision.retryAfterSeconds,
                finalURL: errorInfo?.finalURL?.absoluteString
            )

            freshTx.status = decision.retryable ? .pending : .failed
            freshTx.lastError = errorMessage(from: error)

            let outcome = decision.retryable ? "pending" : "failed"
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=\(outcome, privacy: .public) reason=poll_failed")
        }
    }

    /// Submit a ThreadMemento decision to SolServer and clear matching local draft fields so UI updates immediately.
    ///
    /// v0 behavior:
    /// - SolServer is the source of truth for draft/accepted/declined state.
    /// - SolMobile clears local draft fields (id/summary) after a successful decision so the banner disappears
    ///   without requiring a manual view refresh.
    func decideThreadMemento(threadId: UUID, mementoId: String, decision: ThreadMementoDecision) async throws -> ThreadMementoDecisionResult {

        let runId = String(UUID().uuidString.prefix(8))

        outboxLog.info(
            "memento_decision run=\(runId, privacy: .public) event=start thread=\(short(threadId), privacy: .public) decision=\(decision.rawValue, privacy: .public) memento=\(mementoId, privacy: .public)"
        )

        guard let decider = self.transport as? any ChatTransportMementoDecision else {
            outboxLog.error("memento_decision run=\(runId, privacy: .public) event=unsupported transport=\(String(describing: type(of: self.transport)), privacy: .public)")

            throw TransportError.unsupportedTransport(capability: "memento_decision")
        }

        do {
            let result = try await decider.decideMemento(
                threadId: threadId.uuidString,
                mementoId: mementoId,
                decision: decision
            )

            outboxLog.info("memento_decision run=\(runId, privacy: .public) event=server_ok http=\(result.statusCode, privacy: .public) applied=\(result.applied, privacy: .public) reason=\(shortOrDash(result.reason), privacy: .public)")

            // Clear any local draft fields that match this memento id.
            let d = FetchDescriptor<Transmission>(predicate: #Predicate { $0.packet.threadId == threadId })
            let all = (try? modelContext.fetch(d)) ?? []

            let matching = all.filter { $0.serverThreadMementoId == mementoId }
            for tx in matching {
                tx.serverThreadMementoId = nil
                tx.serverThreadMementoCreatedAtISO = nil
                tx.serverThreadMementoSummary = nil
            }

            try? modelContext.save()
            outboxLog.info("memento_decision run=\(runId, privacy: .public) event=local_cleared count=\(matching.count, privacy: .public)")

            return result
        } catch {
            outboxLog.error("memento_decision run=\(runId, privacy: .public) event=server_failed err=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func retryFailed() {
        outboxLog.info("retryFailed event=start")

        let failedRaw = TransmissionStatus.failed.rawValue
        let descriptor = FetchDescriptor<Transmission>(
            predicate: #Predicate { $0.statusRaw == failedRaw }
        )

        guard let failed = try? modelContext.fetch(descriptor) else { return }

        outboxLog.info("retryFailed event=failed_count count=\(failed.count, privacy: .public)")

        for tx in failed {
            outboxLog.info("retryFailed event=tx tx=\(short(tx.id), privacy: .public) packetType=\(tx.packet.packetType, privacy: .public)")

            // DEBUG: one-shot fail test, only fail the first attempt.
            if tx.packet.packetType == "chat_fail" {
                tx.packet.packetType = "chat"
                outboxLog.info("retryFailed event=flip_one_shot tx=\(short(tx.id), privacy: .public) from=chat_fail to=chat")
            }

            tx.status = .queued
            tx.lastError = nil

            outboxLog.info("retryFailed event=status tx=\(short(tx.id), privacy: .public) to=queued")
        }

        try? modelContext.save()
        outboxLog.info("retryFailed event=end")
    }

    private func recoverPendingWithoutActiveAttempt(runId: String, tx: Transmission, attemptCount: Int) {
        guard tx.status == .pending else { return }
        tx.status = .queued
        tx.lastError = "Recovered pending transmission without active attempt"
        outboxLog.info(
            "processQueue run=\(runId, privacy: .public) event=pending_recovered tx=\(short(tx.id), privacy: .public) attempts=\(attemptCount, privacy: .public)"
        )
    }

    // MARK: - SwiftData fetch helpers

    private func fetchThread(id: UUID) throws -> ConversationThread? {
        let d = FetchDescriptor<ConversationThread>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(d).first
    }

    private func fetchTransmission(id: UUID) throws -> Transmission? {
        let d = FetchDescriptor<Transmission>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(d).first
    }

    private func fetchMessage(id: UUID) throws -> Message? {
        let d = FetchDescriptor<Message>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(d).first
    }
}
