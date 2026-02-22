
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

nonisolated private struct JournalOfferSnapshot: Codable, Sendable {
    let momentId: String
    let momentType: String
    let phase: String
    let confidence: String
    let evidenceSpan: JournalEvidenceSpan
    let why: [String]?
    let offerEligible: Bool

    init(from offer: JournalOffer) {
        self.momentId = offer.momentId
        self.momentType = offer.momentType
        self.phase = offer.phase
        self.confidence = offer.confidence
        self.evidenceSpan = offer.evidenceSpan
        self.why = offer.why
        self.offerEligible = offer.offerEligible
    }
}

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

    static func parseSummary(
        id: String,
        threadId: String,
        createdAt: String,
        summary: String
    ) -> ThreadMementoDTO? {
        let lines = summary
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        func value(for prefix: String) -> String? {
            lines.first(where: { $0.hasPrefix(prefix) }).map {
                String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard
            let arcRaw = value(for: "Arc:"),
            let activeRaw = value(for: "Active:"),
            let parkedRaw = value(for: "Parked:"),
            let decisionsRaw = value(for: "Decisions:"),
            let nextRaw = value(for: "Next:")
        else {
            return nil
        }

        func parseList(_ raw: String) -> [String] {
            guard raw != "(none)" else { return [] }
            return raw
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        let arc = (arcRaw == "(none)") ? "" : arcRaw

        return ThreadMementoDTO(
            id: id,
            threadId: threadId,
            createdAt: createdAt,
            version: "memento-v0.2",
            arc: arc,
            active: parseList(activeRaw),
            parked: parseList(parkedRaw),
            decisions: parseList(decisionsRaw),
            next: parseList(nextRaw)
        )
    }
}

// MARK: - Transport contracts

nonisolated struct PacketEnvelope: Sendable {
    let packetId: UUID
    let packetType: String
    let threadId: UUID
    let messageIds: [UUID]
    let messageText: String
    let requestId: String
    let contextRefsJson: String?
    let payloadJson: String?
    let threadMemento: ThreadMementoDTO?

    init(
        packetId: UUID,
        packetType: String,
        threadId: UUID,
        messageIds: [UUID],
        messageText: String,
        requestId: String,
        contextRefsJson: String?,
        payloadJson: String?,
        threadMemento: ThreadMementoDTO? = nil
    ) {
        self.packetId = packetId
        self.packetType = packetType
        self.threadId = threadId
        self.messageIds = messageIds
        self.messageText = messageText
        self.requestId = requestId
        self.contextRefsJson = contextRefsJson
        self.payloadJson = payloadJson
        self.threadMemento = threadMemento
    }
}

nonisolated struct DiagnosticsContext: Sendable {
    let attemptId: UUID
    let threadId: UUID?
    let localTransmissionId: UUID?
}

protocol ChatTransport: Sendable {
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

nonisolated struct ThreadMementoDecisionResult: Sendable {
    let statusCode: Int
    let applied: Bool
    let reason: String?
    let memento: ThreadMementoDTO?
}

protocol ChatTransportMementoDecision: Sendable {
    func decideMemento(threadId: String, mementoId: String, decision: ThreadMementoDecision) async throws -> ThreadMementoDecisionResult
}

nonisolated struct ChatPollResponse {
    let pending: Bool
    let assistant: String?
    let serverStatus: String?
    let statusCode: Int
    let responseInfo: ResponseInfo?
    let userMessageId: String?
    let assistantMessageId: String?

    let threadMemento: ThreadMementoDTO?
    let journalOffer: JournalOffer?
    
    // Evidence fields (PR #7.1 / PR #8)
    let evidenceSummary: EvidenceSummaryDTO?
    let evidence: EvidenceDTO?
    let evidenceWarnings: [EvidenceWarningDTO]?

    // OutputEnvelope (PR #23)
    let outputEnvelope: OutputEnvelopeDTO?

    init(
        pending: Bool,
        assistant: String?,
        serverStatus: String?,
        statusCode: Int,
        responseInfo: ResponseInfo?,
        userMessageId: String? = nil,
        assistantMessageId: String? = nil,
        threadMemento: ThreadMementoDTO?,
        journalOffer: JournalOffer? = nil,
        evidenceSummary: EvidenceSummaryDTO?,
        evidence: EvidenceDTO?,
        evidenceWarnings: [EvidenceWarningDTO]?,
        outputEnvelope: OutputEnvelopeDTO?
    ) {
        self.pending = pending
        self.assistant = assistant
        self.serverStatus = serverStatus
        self.statusCode = statusCode
        self.responseInfo = responseInfo
        self.userMessageId = userMessageId
        self.assistantMessageId = assistantMessageId
        self.threadMemento = threadMemento
        self.journalOffer = journalOffer
        self.evidenceSummary = evidenceSummary
        self.evidence = evidence
        self.evidenceWarnings = evidenceWarnings
        self.outputEnvelope = outputEnvelope
    }
}

enum TransportError: Error {
    case simulatedFailure
    case httpStatus(HTTPErrorInfo)
    case insecureBaseURL(reason: String)

    /// The configured transport does not support a required optional capability.
    case unsupportedTransport(capability: String)
}

nonisolated struct HTTPErrorInfo {
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

nonisolated struct ChatResponse {
    let text: String
    let statusCode: Int
    let transmissionId: String?
    let pending: Bool
    let responseInfo: ResponseInfo?
    let userMessageId: String?
    let assistantMessageId: String?

    let threadMemento: ThreadMementoDTO?
    let journalOffer: JournalOffer?
    
    // Evidence fields (PR #7.1 / PR #8)
    let evidenceSummary: EvidenceSummaryDTO?
    let evidence: EvidenceDTO?
    let evidenceWarnings: [EvidenceWarningDTO]?

    // OutputEnvelope (PR #23)
    let outputEnvelope: OutputEnvelopeDTO?

    init(
        text: String,
        statusCode: Int,
        transmissionId: String?,
        pending: Bool,
        responseInfo: ResponseInfo?,
        userMessageId: String? = nil,
        assistantMessageId: String? = nil,
        threadMemento: ThreadMementoDTO?,
        journalOffer: JournalOffer? = nil,
        evidenceSummary: EvidenceSummaryDTO?,
        evidence: EvidenceDTO?,
        evidenceWarnings: [EvidenceWarningDTO]?,
        outputEnvelope: OutputEnvelopeDTO?
    ) {
        self.text = text
        self.statusCode = statusCode
        self.transmissionId = transmissionId
        self.pending = pending
        self.responseInfo = responseInfo
        self.userMessageId = userMessageId
        self.assistantMessageId = assistantMessageId
        self.threadMemento = threadMemento
        self.journalOffer = journalOffer
        self.evidenceSummary = evidenceSummary
        self.evidence = evidence
        self.evidenceWarnings = evidenceWarnings
        self.outputEnvelope = outputEnvelope
    }
}



// MARK: - Outbox processor

@MainActor
final class TransmissionActions {

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
    private var activePolls: Set<String> = []

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
        enqueueChat(threadId: thread.id, messageId: userMessage.id)
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
    func enqueueChat(threadId: UUID, messageId: UUID) {
        guard let message = try? fetchMessage(id: messageId) else {
            outboxLog.error("enqueueChat event=missing_message thread=\(short(threadId), privacy: .public) msg=\(short(messageId), privacy: .public)")
            return
        }
        guard let thread = DebugModelValidators.threadOrNil(message), thread.id == threadId else {
            outboxLog.error("enqueueChat event=missing_thread thread=\(short(threadId), privacy: .public) msg=\(short(messageId), privacy: .public)")
            return
        }

        let messageText = message.text
        let shouldFail = messageText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("/fail")

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

    func pollTransmission(serverTransmissionId: String, reason: String) async {
        let runId = "sse-\(String(UUID().uuidString.prefix(8)))"
        guard let tx = fetchTransmissionByServerId(serverTransmissionId) else {
            outboxLog.debug("pollTransmission run=\(runId, privacy: .public) event=missing tx=\(shortOrDash(serverTransmissionId), privacy: .public) reason=\(reason, privacy: .public)")
            return
        }
        if tx.status == .succeeded {
            outboxLog.debug("pollTransmission run=\(runId, privacy: .public) event=skip_succeeded tx=\(short(tx.id), privacy: .public) reason=\(reason, privacy: .public)")
            return
        }
        if let existing = findExistingAssistantMessage(
            threadId: tx.packet.threadId,
            transmissionId: serverTransmissionId,
            assistantMessageId: nil
        ) {
            markTransmissionDelivered(txId: tx.id, reason: "poll_skip_existing")
            outboxLog.info("pollTransmission run=\(runId, privacy: .public) event=skip_existing tx=\(short(tx.id), privacy: .public) msg=\(short(existing.id), privacy: .public) reason=\(reason, privacy: .public)")
            try? modelContext.save()
            return
        }

        let attempts = sortedAttempts(tx.deliveryAttempts)
        let sel = PendingSelection(txId: tx.id, packetId: tx.packet.id, threadId: tx.packet.threadId)
        _ = await pollOnce(runId: runId, sel: sel, attempts: attempts)
        try? modelContext.save()
    }

    // Poll up to N pending transmissions (does not block sending).
    private func pollPending(runId: String, limit: Int) async {
        guard let pending = fetchPendingSelections(runId: runId, limit: limit), !pending.isEmpty else {
            return
        }

        var appendedMessages: [Message] = []
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

            if let appended = await pollOnce(runId: runId, sel: sel, attempts: attempts) {
                appendedMessages.append(appended)
            }
        }

        DebugModelValidators.assertMessagesHaveThread(
            appendedMessages,
            context: "TransmissionActions.pollPending.beforeSave"
        )
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

    private func applyServerMessageId(_ serverMessageId: String?, to message: Message) {
        guard let serverMessageId, !serverMessageId.isEmpty else { return }
        message.serverMessageId = serverMessageId
    }

    private func updateUserMessageServerId(
        messageIds: [UUID],
        serverMessageId: String?,
        fallbackServerMessageId: String?
    ) {
        guard let firstId = messageIds.first else { return }
        let resolvedServerMessageId = serverMessageId ?? fallbackServerMessageId
        let d = FetchDescriptor<Message>(predicate: #Predicate { $0.id == firstId })
        guard let message = try? modelContext.fetch(d).first else { return }
        if let resolvedServerMessageId, !resolvedServerMessageId.isEmpty {
            message.serverMessageId = resolvedServerMessageId
        }
        AppleIntelligenceObserver.shared.observeMessage(message)
    }

    @discardableResult
    private func appendAssistantMessageIfPossible(
        threadId: UUID,
        assistantText: String?,
        transmissionId: String?,
        assistantMessageId: String?,
        evidence: EvidenceDTO?,
        journalOffer: JournalOffer?,
        outputEnvelope: OutputEnvelopeDTO?,
        runId: String,
        txId: UUID,
        via: String
    ) -> Message? {
        guard let thread = resolveThread(
            threadId: threadId,
            runId: runId,
            reason: "append_assistant"
        ) else {
            outboxLog.error(
                "processQueue run=\(runId, privacy: .public) event=thread_missing_skip_message tx=\(short(txId), privacy: .public) thread=\(short(threadId), privacy: .public)"
            )
            return nil
        }

        if let existing = findExistingAssistantMessage(
            threadId: threadId,
            transmissionId: transmissionId,
            assistantMessageId: assistantMessageId
        ) {
            if DebugModelValidators.threadOrNil(existing) == nil {
                outboxLog.error(
                    "processQueue run=\(runId, privacy: .public) event=assistant_orphan_repair tx=\(short(txId), privacy: .public) thread=\(short(threadId), privacy: .public) via=\(via, privacy: .public)"
                )
                existing.thread = thread
            }
            upsertAssistantMessage(
                existing: existing,
                thread: thread,
                assistantText: assistantText,
                transmissionId: transmissionId,
                assistantMessageId: assistantMessageId,
                evidence: evidence,
                journalOffer: journalOffer,
                outputEnvelope: outputEnvelope,
                runId: runId,
                txId: txId,
                via: via
            )
            markTransmissionDelivered(txId: txId, reason: "dedupe_existing")
            outboxLog.info(
                "processQueue run=\(runId, privacy: .public) event=assistant_dedupe tx=\(short(txId), privacy: .public) via=\(via, privacy: .public)"
            )
            return existing
        }
        let previousMessage = thread.messages.last

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
        guard DebugModelValidators.threadOrNil(assistantMessage) != nil else {
            outboxLog.error(
                "processQueue run=\(runId, privacy: .public) event=thread_nil_guard tx=\(short(txId), privacy: .public) thread=\(short(threadId), privacy: .public)"
            )
            return nil
        }
        DebugModelValidators.assertMessageHasThread(
            assistantMessage,
            context: "TransmissionActions.appendAssistantMessageIfPossible.afterInit"
        )
        applyServerMessageId(assistantMessageId ?? transmissionId, to: assistantMessage)

        let evidenceModels: (captures: [Capture], supports: [ClaimSupport], claims: [ClaimMapEntry])
        do {
            evidenceModels = try assistantMessage.buildEvidenceModels(from: evidence)
        } catch {
            outboxLog.error(
                "processQueue run=\(runId, privacy: .public) event=evidence_mapping_failed tx=\(short(txId), privacy: .public) err=\(String(describing: error), privacy: .public)"
            )
            return nil
        }

        assistantMessage.hasEvidence = !evidenceModels.captures.isEmpty
            || !evidenceModels.supports.isEmpty
            || !evidenceModels.claims.isEmpty

        let previousMemoryId = assistantMessage.ghostMemoryId
        assistantMessage.applyOutputEnvelopeMeta(outputEnvelope)
        let newMemoryId = assistantMessage.ghostMemoryId
        let factNull = assistantMessage.ghostFactNull
        let ghostKind = assistantMessage.ghostKind
        prefetchLatticeMemoriesIfNeeded(for: assistantMessage)
        GhostCardReceipt.fireCanonizationIfNeeded(
            modelContext: modelContext,
            previousMemoryId: previousMemoryId,
            newMemoryId: newMemoryId,
            factNull: factNull,
            ghostKind: ghostKind
        )

        if !thread.messages.contains(where: { $0.id == assistantMessage.id }) {
            thread.messages.append(assistantMessage)
        }
        DebugModelValidators.logDuplicateMessageIds(thread: thread, context: "TransmissionActions.appendAssistantMessageIfPossible.append")
        thread.lastActiveAt = Date()

        modelContext.insert(assistantMessage)

        markTransmissionDelivered(txId: txId, reason: "assistant_appended")

        if assistantMessage.journalOfferJson == nil, let offer = journalOffer {
            let snapshot = JournalOfferSnapshot(from: offer)
            assistantMessage.journalOfferJson = try? JSONEncoder().encode(snapshot)
            if assistantMessage.journalOfferJson == nil {
                outboxLog.error(
                    "processQueue run=\(runId, privacy: .public) event=journal_offer_encode_failed tx=\(short(txId), privacy: .public)"
                )
            } else {
                outboxLog.info(
                    "processQueue run=\(runId, privacy: .public) event=journal_offer_attached tx=\(short(txId), privacy: .public) eligible=\(offer.offerEligible, privacy: .public) moment=\(offer.momentId, privacy: .public)"
                )
            }
        } else if assistantMessage.journalOfferJson == nil {
            outboxLog.debug(
                "processQueue run=\(runId, privacy: .public) event=journal_offer_missing tx=\(short(txId), privacy: .public)"
            )
        }

        if let previousMessage {
            let previousMessageId = previousMessage.id
            let d = FetchDescriptor<Message>(predicate: #Predicate { $0.id == previousMessageId })
            if let message = try? modelContext.fetch(d).first {
                AppleIntelligenceObserver.shared.observeMessage(message)
            }
        }

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
        return assistantMessage
    }

    private func findExistingAssistantMessage(
        threadId: UUID,
        transmissionId: String?,
        assistantMessageId: String?
    ) -> Message? {
        let assistantRaw = "assistant"

        if let assistantMessageId, !assistantMessageId.isEmpty {
            let descriptor = FetchDescriptor<Message>(
                predicate: #Predicate { msg in
                    msg.thread.id == threadId
                    && msg.creatorTypeRaw == assistantRaw
                    && msg.serverMessageId == assistantMessageId
                }
            )
            if let existing = try? modelContext.fetch(descriptor).first {
                return existing
            }
        }

        if let transmissionId, !transmissionId.isEmpty {
            let descriptor = FetchDescriptor<Message>(
                predicate: #Predicate { msg in
                    msg.thread.id == threadId
                    && msg.creatorTypeRaw == assistantRaw
                    && msg.transmissionId == transmissionId
                }
            )
            if let existing = try? modelContext.fetch(descriptor).first {
                return existing
            }
        }

        return nil
    }

    private func upsertAssistantMessage(
        existing: Message,
        thread: ConversationThread,
        assistantText: String?,
        transmissionId: String?,
        assistantMessageId: String?,
        evidence: EvidenceDTO?,
        journalOffer: JournalOffer?,
        outputEnvelope: OutputEnvelopeDTO?,
        runId: String,
        txId: UUID,
        via: String
    ) {
        if let assistantText, !assistantText.isEmpty {
            existing.text = assistantText
        }
        if existing.serverMessageId == nil || existing.serverMessageId?.isEmpty == true {
            applyServerMessageId(assistantMessageId ?? transmissionId, to: existing)
        }
        if (existing.transmissionId == nil || existing.transmissionId?.isEmpty == true),
           let transmissionId, !transmissionId.isEmpty {
            existing.transmissionId = transmissionId
        }

        let previousMemoryId = existing.ghostMemoryId
        existing.applyOutputEnvelopeMeta(outputEnvelope)
        let newMemoryId = existing.ghostMemoryId
        let factNull = existing.ghostFactNull
        let ghostKind = existing.ghostKind
        prefetchLatticeMemoriesIfNeeded(for: existing)
        GhostCardReceipt.fireCanonizationIfNeeded(
            modelContext: modelContext,
            previousMemoryId: previousMemoryId,
            newMemoryId: newMemoryId,
            factNull: factNull,
            ghostKind: ghostKind
        )

        if let evidence {
            let evidenceModels: (captures: [Capture], supports: [ClaimSupport], claims: [ClaimMapEntry])
            do {
                evidenceModels = try existing.buildEvidenceModels(from: evidence)
            } catch {
                outboxLog.error(
                    "processQueue run=\(runId, privacy: .public) event=evidence_mapping_failed_existing tx=\(short(txId), privacy: .public) err=\(String(describing: error), privacy: .public)"
                )
                return
            }

            if let captures = existing.captures {
                captures.forEach { modelContext.delete($0) }
            }
            if let supports = existing.supports {
                supports.forEach { modelContext.delete($0) }
            }
            if let claims = existing.claims {
                claims.forEach { modelContext.delete($0) }
            }

            existing.hasEvidence = !evidenceModels.captures.isEmpty
                || !evidenceModels.supports.isEmpty
                || !evidenceModels.claims.isEmpty

            if !evidenceModels.captures.isEmpty {
                existing.captures = evidenceModels.captures
                evidenceModels.captures.forEach { modelContext.insert($0) }
            }

            if !evidenceModels.supports.isEmpty {
                existing.supports = evidenceModels.supports
                evidenceModels.supports.forEach { modelContext.insert($0) }
            }

            if !evidenceModels.claims.isEmpty {
                existing.claims = evidenceModels.claims
                evidenceModels.claims.forEach { modelContext.insert($0) }
            }
        }

        if existing.journalOfferJson == nil, let offer = journalOffer {
            let snapshot = JournalOfferSnapshot(from: offer)
            existing.journalOfferJson = try? JSONEncoder().encode(snapshot)
            if existing.journalOfferJson == nil {
                outboxLog.error(
                    "processQueue run=\(runId, privacy: .public) event=journal_offer_encode_failed_existing tx=\(short(txId), privacy: .public)"
                )
            } else {
                outboxLog.info(
                    "processQueue run=\(runId, privacy: .public) event=journal_offer_attached_existing tx=\(short(txId), privacy: .public) eligible=\(offer.offerEligible, privacy: .public) moment=\(offer.momentId, privacy: .public)"
                )
            }
        }

        if existing.isGhostCard {
            upsertMemoryArtifact(from: existing)
        }

        if !thread.messages.contains(where: { $0.id == existing.id }) {
            thread.messages.append(existing)
        }
        DebugModelValidators.logDuplicateMessageIds(thread: thread, context: "TransmissionActions.upsertAssistantMessage.append")
        thread.lastActiveAt = Date()
    }

    private func markTransmissionDelivered(txId: UUID, reason: String) {
        guard let tx = try? fetchTransmission(id: txId) else { return }
        guard tx.status != .succeeded else { return }
        tx.status = .succeeded
        tx.lastError = nil
        outboxLog.info("processQueue event=tx_delivered tx=\(short(txId), privacy: .public) reason=\(reason, privacy: .public)")
    }

    private func resolveThread(
        threadId: UUID,
        runId: String,
        reason: String
    ) -> ConversationThread? {
        if let existing = try? fetchThread(id: threadId) {
            return existing
        }
        outboxLog.error(
            "processQueue run=\(runId, privacy: .public) event=thread_missing_skip_message reason=\(reason, privacy: .public) thread=\(short(threadId), privacy: .public)"
        )
        return nil
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
            existing.summary = message.ghostSnippet ?? existing.summary
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
            summary: message.ghostSnippet,
            moodAnchor: message.ghostMoodAnchor,
            rigorLevelRaw: message.ghostRigorLevelRaw,
            createdAt: message.createdAt,
            updatedAt: message.createdAt
        )

        modelContext.insert(artifact)
    }

    private func prefetchLatticeMemoriesIfNeeded(for message: Message) {
        let memoryIds = message.latticeMemoryIds
        guard !memoryIds.isEmpty else { return }

        var missing: [String] = []
        for memoryId in memoryIds {
            let descriptor = FetchDescriptor<MemoryArtifact>(
                predicate: #Predicate { $0.memoryId == memoryId }
            )
            if (try? modelContext.fetch(descriptor).first) == nil {
                missing.append(memoryId)
            }
        }

        guard !missing.isEmpty else { return }

        let logger = outboxLog

        Task { [weak self, missing] in
            guard let self else { return }
            let client = SolServerClient()
            for memoryId in missing {
                do {
                    let response = try await client.getMemory(memoryId: memoryId)
                    if let dto = response.memory {
                        await MainActor.run {
                            self.upsertMemoryArtifact(from: dto)
                        }
                    }
                } catch {
                    logger.error("prefetch_lattice_memory_failed id=\(memoryId, privacy: .public)")
                }
            }
        }
    }

    private func upsertMemoryArtifact(from dto: MemoryItemDTO) {
        let memoryId = dto.id
        let descriptor = FetchDescriptor<MemoryArtifact>(predicate: #Predicate { $0.memoryId == memoryId })
        let existing = (try? modelContext.fetch(descriptor))?.first

        let createdAt = dto.createdAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        let updatedAt = dto.updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) }

        if let existing {
            existing.threadId = dto.threadId
            existing.triggerMessageId = dto.triggerMessageId
            existing.typeRaw = dto.type ?? existing.typeRaw
            existing.snippet = dto.snippet ?? existing.snippet
            existing.summary = dto.summary ?? existing.summary
            existing.moodAnchor = dto.moodAnchor ?? existing.moodAnchor
            existing.rigorLevelRaw = dto.rigorLevel ?? existing.rigorLevelRaw
            existing.lifecycleStateRaw = dto.lifecycleState ?? existing.lifecycleStateRaw
            existing.memoryKindRaw = dto.memoryKind ?? existing.memoryKindRaw
            existing.tagsCsv = dto.tags?.joined(separator: ",") ?? existing.tagsCsv
            if let evidenceIds = dto.evidenceMessageIds {
                existing.evidenceMessageIdsCsv = evidenceIds.joined(separator: ",")
            }
            existing.fidelityRaw = dto.fidelity ?? existing.fidelityRaw
            existing.transitionToHazyAt = dto.transitionToHazyAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            existing.updatedAt = updatedAt ?? Date()
            return
        }

        let artifact = MemoryArtifact(
            memoryId: dto.id,
            threadId: dto.threadId,
            triggerMessageId: dto.triggerMessageId,
            typeRaw: dto.type ?? "memory",
            snippet: dto.snippet,
            summary: dto.summary,
            moodAnchor: dto.moodAnchor,
            rigorLevelRaw: dto.rigorLevel,
            lifecycleStateRaw: dto.lifecycleState,
            memoryKindRaw: dto.memoryKind,
            tagsCsv: dto.tags?.joined(separator: ","),
            evidenceMessageIdsCsv: dto.evidenceMessageIds?.joined(separator: ","),
            fidelityRaw: dto.fidelity,
            transitionToHazyAt: dto.transitionToHazyAt.flatMap { ISO8601DateFormatter().date(from: $0) },
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        modelContext.insert(artifact)
    }

    private func sendOnce(runId: String, sel: QueueSelection) async {
        guard let tx = try? fetchTransmission(id: sel.txId) else { return }

        let startNs = DispatchTime.now().uptimeNanoseconds
        var appendedMessage: Message?

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
            if sel.packetType == "chat" {
                HapticRouter.shared.terminalFailure(idempotencyKey: attemptId.uuidString)
            }
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
                if sel.packetType == "chat" {
                    HapticRouter.shared.terminalFailure(idempotencyKey: attemptId.uuidString)
                }
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
                payloadJson: nil,
                threadMemento: resolveThreadMementoForSend(runId: runId, txId: sel.txId, threadId: sel.threadId)
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

            if sel.packetType == "chat",
               response.pending || response.statusCode == 202 || response.statusCode == 200 {
                let ackKey = response.transmissionId ?? attemptId.uuidString
                HapticRouter.shared.acceptedTick(idempotencyKey: ackKey)
            }

            if let m = response.threadMemento {
                applyDraftMemento(runId: runId, freshTx: freshTx, txId: sel.txId, m: m, via: "send")
            }

            updateUserMessageServerId(
                messageIds: sel.messageIds,
                serverMessageId: response.userMessageId,
                fallbackServerMessageId: response.transmissionId
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
                _ = await pollOnce(runId: runId, sel: pendingSelection, attempts: pendingAttempts)
                try? modelContext.save()
                return
            }

            appendedMessage = appendAssistantMessageIfPossible(
                threadId: sel.threadId,
                assistantText: response.text,
                transmissionId: response.transmissionId,
                assistantMessageId: response.assistantMessageId,
                evidence: response.evidence,
                journalOffer: response.journalOffer,
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

            if sel.packetType == "chat", decision.retryable == false {
                let failKey = decision.transmissionId ?? attemptId.uuidString
                HapticRouter.shared.terminalFailure(idempotencyKey: failKey)
            }

            let outcome = decision.retryable ? "queued" : "failed"
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=\(outcome, privacy: .public) http=\(code, privacy: .public)")
        }

        if let appendedMessage {
            DebugModelValidators.assertMessageHasThread(
                appendedMessage,
                context: "TransmissionActions.sendOnce.beforeSave"
            )
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
            payloadJson: payloadJson,
            threadMemento: nil
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
                _ = await pollOnce(runId: runId, sel: pendingSelection, attempts: pendingAttempts)
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
            if tx.packet.packetType == "chat" {
                HapticRouter.shared.terminalFailure(idempotencyKey: tx.id.uuidString)
            }
            try? modelContext.save()
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
        if let payload = try? JSONEncoder().encode(m),
           let json = String(data: payload, encoding: .utf8) {
            freshTx.serverThreadMementoPayloadJSON = json
        } else {
            freshTx.serverThreadMementoPayloadJSON = nil
            outboxLog.error("processQueue run=\(runId, privacy: .public) event=memento_payload_encode_failed tx=\(short(txId), privacy: .public) memento=\(m.id, privacy: .public)")
        }

        outboxLog.info("processQueue run=\(runId, privacy: .public) event=memento_draft_saved tx=\(short(txId), privacy: .public) memento=\(m.id, privacy: .public) via=\(via, privacy: .public)")
    }

    private func resolveThreadMementoForSend(
        runId: String,
        txId: UUID,
        threadId: UUID
    ) -> ThreadMementoDTO? {
        let descriptor = FetchDescriptor<Transmission>(
            predicate: #Predicate { $0.packet.threadId == threadId },
            sortBy: [SortDescriptor(\Transmission.createdAt, order: .reverse)]
        )

        guard
            let transmissions = try? modelContext.fetch(descriptor),
            let source = transmissions.first(where: {
                $0.serverThreadMementoPayloadJSON?.isEmpty == false
                || $0.serverThreadMementoSummary?.isEmpty == false
                || $0.serverThreadMementoId?.isEmpty == false
            })
        else {
            return nil
        }

        if let payload = source.serverThreadMementoPayloadJSON, !payload.isEmpty {
            if let data = payload.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(ThreadMementoDTO.self, from: data) {
                outboxLog.info("processQueue run=\(runId, privacy: .public) event=memento_context_source tx=\(short(txId), privacy: .public) source=structured_payload_json memento=\(decoded.id, privacy: .public)")
                return decoded
            }
            outboxLog.error("processQueue run=\(runId, privacy: .public) event=memento_context_decode_failed tx=\(short(txId), privacy: .public) source=structured_payload_json")
        }

        if
            let summary = source.serverThreadMementoSummary,
            let mementoId = source.serverThreadMementoId,
            !summary.isEmpty,
            !mementoId.isEmpty
        {
            let createdAt = source.serverThreadMementoCreatedAtISO
                ?? ISO8601DateFormatter().string(from: source.createdAt)

            if let parsed = ThreadMementoFormatter.parseSummary(
                id: mementoId,
                threadId: threadId.uuidString,
                createdAt: createdAt,
                summary: summary
            ) {
                outboxLog.info("processQueue run=\(runId, privacy: .public) event=memento_context_source tx=\(short(txId), privacy: .public) source=summary_parse memento=\(parsed.id, privacy: .public)")
                return parsed
            }
        }

        outboxLog.info("processQueue run=\(runId, privacy: .public) event=memento_context_source tx=\(short(txId), privacy: .public) source=omit")
        return nil
    }

    private func pollOnce(
        runId: String,
        sel: PendingSelection,
        attempts: [DeliveryAttempt]
    ) async -> Message? {
        guard let last = activePollAttempt(attempts),
              let serverTxId = last.transmissionId,
              !serverTxId.isEmpty else {
            if let tx = try? fetchTransmission(id: sel.txId) {
                tx.status = .failed
                tx.lastError = "Missing server transmission id for pending poll"
                outboxLog.error("processQueue run=\(runId, privacy: .public) event=poll_missing_id tx=\(short(sel.txId), privacy: .public)")
                if tx.packet.packetType == "chat" {
                    HapticRouter.shared.terminalFailure(idempotencyKey: tx.id.uuidString)
                }
            }
            return nil
        }

        outboxLog.info("processQueue run=\(runId, privacy: .public) event=poll_ready tx=\(short(sel.txId), privacy: .public) serverTx=\(shortOrDash(serverTxId), privacy: .public)")

        guard let tx = try? fetchTransmission(id: sel.txId) else { return nil }
        if tx.status == .succeeded {
            outboxLog.debug("processQueue run=\(runId, privacy: .public) event=poll_skip_succeeded tx=\(short(sel.txId), privacy: .public)")
            return nil
        }
        if let existing = findExistingAssistantMessage(
            threadId: sel.threadId,
            transmissionId: serverTxId,
            assistantMessageId: nil
        ) {
            markTransmissionDelivered(txId: sel.txId, reason: "poll_existing")
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=poll_skip_existing tx=\(short(sel.txId), privacy: .public) msg=\(short(existing.id), privacy: .public)")
            return existing
        }
        if activePolls.contains(serverTxId) {
            outboxLog.debug("processQueue run=\(runId, privacy: .public) event=poll_skip_inflight tx=\(short(sel.txId), privacy: .public) serverTx=\(shortOrDash(serverTxId), privacy: .public)")
            return nil
        }
        activePolls.insert(serverTxId)
        defer { activePolls.remove(serverTxId) }

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
                return nil
            }

            let poll = try await watcher.poll(transmissionId: serverTxId, diagnostics: diagnostics)

            guard let freshTx = try? fetchTransmission(id: sel.txId) else { return nil }

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
                return nil
            }

            updateUserMessageServerId(
                messageIds: freshTx.packet.messageIds,
                serverMessageId: poll.userMessageId,
                fallbackServerMessageId: serverTxId
            )

            let appended = appendAssistantMessageIfPossible(
                threadId: sel.threadId,
                assistantText: poll.assistant,
                transmissionId: serverTxId,
                assistantMessageId: poll.assistantMessageId,
                evidence: poll.evidence,
                journalOffer: poll.journalOffer,
                outputEnvelope: poll.outputEnvelope,
                runId: runId,
                txId: sel.txId,
                via: "poll"
            )

            freshTx.status = .succeeded
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=succeeded reason=poll_complete")
            return appended
        } catch {
            outboxLog.error("processQueue run=\(runId, privacy: .public) event=poll_failed tx=\(short(sel.txId), privacy: .public) err=\(String(describing: error), privacy: .public)")

            guard let freshTx = try? fetchTransmission(id: sel.txId) else { return nil }

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

            if decision.retryable == false, freshTx.packet.packetType == "chat" {
                let failKey = decision.transmissionId ?? attemptId.uuidString
                HapticRouter.shared.terminalFailure(idempotencyKey: failKey)
            }

            let outcome = decision.retryable ? "pending" : "failed"
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=\(outcome, privacy: .public) reason=poll_failed")
        }
        return nil
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
                tx.serverThreadMementoPayloadJSON = nil
            }

            try? modelContext.save()
            outboxLog.info("memento_decision run=\(runId, privacy: .public) event=local_cleared count=\(matching.count, privacy: .public)")

            return result
        } catch {
            outboxLog.error("memento_decision run=\(runId, privacy: .public) event=server_failed err=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func retryFailed(kind: OutboxRetryKind? = nil) {
        outboxLog.info("retryFailed event=start")

        let failedRaw = TransmissionStatus.failed.rawValue
        let descriptor = FetchDescriptor<Transmission>(
            predicate: #Predicate { $0.statusRaw == failedRaw }
        )

        guard let failed = try? modelContext.fetch(descriptor) else { return }

        outboxLog.info("retryFailed event=failed_count count=\(failed.count, privacy: .public)")

        for tx in failed {
            let isMemory = tx.packet.packetType == "memory_distill"
            let matchesKind: Bool
            switch kind {
            case .chatSend:
                matchesKind = !isMemory
            case .memorySave:
                matchesKind = isMemory
            case .none:
                matchesKind = true
            }
            if !matchesKind { continue }

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

    private func fetchTransmissionByServerId(_ transmissionId: String) -> Transmission? {
        let d = FetchDescriptor<DeliveryAttempt>(
            predicate: #Predicate { $0.transmissionId == transmissionId },
            sortBy: [SortDescriptor(\DeliveryAttempt.createdAt, order: .reverse)]
        )
        guard let attempts = try? modelContext.fetch(d) else { return nil }
        return attempts.first?.transmission
    }

    private func fetchMessage(id: UUID) throws -> Message? {
        let d = FetchDescriptor<Message>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(d).first
    }
}
