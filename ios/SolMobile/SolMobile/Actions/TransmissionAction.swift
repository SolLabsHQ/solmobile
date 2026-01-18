
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

private func msSince(_ startNs: UInt64) -> Double {
    let endNs = DispatchTime.now().uptimeNanoseconds
    return Double(endNs &- startNs) / 1_000_000.0
}

private func short(_ id: UUID) -> String {
    String(id.uuidString.prefix(8))
}

private func shortOrDash(_ s: String?) -> String {
    (s?.isEmpty == false) ? s! : "-"
}

private let timeWithSecondsFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = .autoupdatingCurrent
    f.timeZone = .autoupdatingCurrent
    f.dateFormat = "h:mm:ss a"
    return f
}()

private func timeWithSeconds(_ d: Date) -> String {
    timeWithSecondsFormatter.string(from: d)
}

// MARK: - ThreadMemento formatting

/// ThreadMemento is a navigation artifact returned by SolServer.
/// It is not durable knowledge; the client may choose to Accept / Decline / Revoke.
private enum ThreadMementoFormatter {
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
    let contextRefsJson: String?
    let payloadJson: String?
}

protocol ChatTransport {
    func send(envelope: PacketEnvelope) async throws -> ChatResponse
}

/// Optional capability: some transports can poll server-side delivery for pending (202) transmissions.
protocol ChatTransportPolling: ChatTransport {
    func poll(transmissionId: String) async throws -> ChatPollResponse
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
    case httpStatus(code: Int, body: String)

    /// The configured transport does not support a required optional capability.
    case unsupportedTransport(capability: String)
}

struct ChatResponse {
    let text: String
    let statusCode: Int
    let transmissionId: String?
    let pending: Bool

    let threadMemento: ThreadMementoDTO?
    
    // Evidence fields (PR #7.1 / PR #8)
    let evidenceSummary: EvidenceSummaryDTO?
    let evidence: EvidenceDTO?
    let evidenceWarnings: [EvidenceWarningDTO]?

    // OutputEnvelope (PR #23)
    let outputEnvelope: OutputEnvelopeDTO?
}



// MARK: - Outbox processor

@MainActor
final class TransmissionActions {

    private let outboxLog = Logger(subsystem: "com.sollabshq.solmobile", category: "Outbox")

    private let modelContext: ModelContext
    private let transport: any ChatTransport

    // v0 retry derivation (local-first): derived from DeliveryAttempt ledger.
    private let pendingTTLSeconds: TimeInterval = 30
    private let maxAttempts: Int = 6
    private let backoffCapSeconds: TimeInterval = 10

    init(modelContext: ModelContext, transport: (any ChatTransport)? = nil) {
        self.modelContext = modelContext
        self.transport = transport ?? SolServerClient()
    }

    private func backoffSeconds(forAttemptCount attemptCount: Int) -> TimeInterval {
        // attemptCount is prior attempts; 0 means "try now".
        guard attemptCount > 0 else { return 0 }
        let exp = min(attemptCount - 1, 10) // safety
        let secs = pow(2.0, Double(exp))
        return min(secs, backoffCapSeconds)
    }

    private func pendingSinceIfActive(_ attempts: [DeliveryAttempt]) -> Date? {
        // Pending is "active" only if the last attempt outcome is pending.
        guard let last = attempts.last, last.outcome == .pending else { return nil }

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

    func enqueueChat(thread: ConversationThread, userMessage: Message) {
        let shouldFail = userMessage.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("/fail")

        outboxLog.info("enqueueChat thread=\(short(thread.id), privacy: .public) msg=\(short(userMessage.id), privacy: .public) shouldFail=\(shouldFail, privacy: .public)")

        let packet = Packet(threadId: thread.id, messageIds: [userMessage.id])
        packet.packetType = shouldFail ? "chat_fail" : "chat"

        outboxLog.info("enqueueChat packet=\(short(packet.id), privacy: .public) type=\(packet.packetType, privacy: .public)")

        modelContext.insert(packet)

        let tx = Transmission(packet: packet)
        modelContext.insert(tx)

        outboxLog.info("enqueueChat tx=\(short(tx.id), privacy: .public) status=queued")

        try? modelContext.save()
    }

    func processQueue() async {
        let runId = String(UUID().uuidString.prefix(8))
        outboxLog.info("processQueue run=\(runId, privacy: .public) event=start")

        defer {
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=end")
        }

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
        let attemptCount = attempts.count

        // If the last attempt is pending and we have a server transmissionId, poll instead of re-sending.
        if await handlePendingPollIfNeeded(runId: runId, txId: sel.txId, threadId: sel.threadId, attempts: attempts) {
            return
        }

        // Client-side terminal conditions.
        if enforceTerminalConditions(runId: runId, tx: tx, txId: sel.txId, attempts: attempts, attemptCount: attemptCount, now: now) {
            return
        }

        // Respect backoff (quiet exit, remain queued).
        if shouldRespectBackoffAndExit(runId: runId, txId: sel.txId, attempts: attempts, attemptCount: attemptCount, now: now) {
            return
        }

        await sendOnce(runId: runId, sel: sel)
    }

    // MARK: - Outbox helpers (v0)

    private struct QueueSelection {
        let txId: UUID
        let packetId: UUID
        let packetType: String
        let threadId: UUID
        let messageIds: [UUID]
        let firstMessageId: UUID?
    }

    private func fetchNextQueuedSelection(runId: String) -> QueueSelection? {
        let queuedRaw = TransmissionStatus.queued.rawValue
        let descriptor = FetchDescriptor<Transmission>(
            predicate: #Predicate { $0.statusRaw == queuedRaw },
            sortBy: [SortDescriptor(\Transmission.createdAt, order: .forward)]
        )

        guard let queued = try? modelContext.fetch(descriptor) else {
            outboxLog.error("processQueue run=\(runId, privacy: .public) event=fetch_failed scope=queued")
            return nil
        }

        outboxLog.info("processQueue run=\(runId, privacy: .public) event=queued_count count=\(queued.count, privacy: .public)")

        guard let tx = queued.first else {
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=empty")
            return nil
        } // v0: one in-flight at a time

        let packet = tx.packet
        return QueueSelection(
            txId: tx.id,
            packetId: packet.id,
            packetType: packet.packetType,
            threadId: packet.threadId,
            messageIds: packet.messageIds,
            firstMessageId: packet.messageIds.first
        )
    }

    private func sortedAttempts(_ attempts: [DeliveryAttempt]) -> [DeliveryAttempt] {
        attempts.sorted { $0.createdAt < $1.createdAt }
    }

    private func recordAttempt(
        tx: Transmission,
        statusCode: Int,
        outcome: DeliveryOutcome,
        errorMessage: String?,
        transmissionId: String?
    ) {
        let attempt = DeliveryAttempt(
            statusCode: statusCode,
            outcome: outcome,
            errorMessage: errorMessage,
            transmissionId: transmissionId,
            transmission: tx
        )
        tx.deliveryAttempts.append(attempt)
        modelContext.insert(attempt)
    }

    private func statusCode(from error: Error) -> Int {
        switch error {
        case TransportError.simulatedFailure:
            return 500
        case let TransportError.httpStatus(code, _):
            return code
        default:
            return -1
        }
    }

    private func errorMessage(from error: Error) -> String {
        switch error {
        case let TransportError.httpStatus(_, body):
            return body.isEmpty ? String(describing: error) : body
        default:
            return String(describing: error)
        }
    }

    private func appendAssistantMessageIfPossible(
        threadId: UUID,
        assistantText: String,
        transmissionId: String?,
        evidence: EvidenceDTO?,
        outputEnvelope: OutputEnvelopeDTO?,
        runId: String,
        txId: UUID,
        via: String
    ) {
        guard let thread = try? fetchThread(id: threadId) else { return }

        let text = assistantText.isEmpty ? "(no assistant text)" : assistantText
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

    private func sendOnce(runId: String, sel: QueueSelection) async {
        guard let tx = try? fetchTransmission(id: sel.txId) else { return }

        let startNs = DispatchTime.now().uptimeNanoseconds

        tx.status = .sending
        tx.lastError = nil
        outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=sending")

        do {
            let userText = (sel.firstMessageId.flatMap { try? fetchMessage(id: $0)?.text }) ?? ""

            outboxLog.debug("processQueue run=\(runId, privacy: .public) event=context tx=\(short(sel.txId), privacy: .public) userTextLen=\(userText.count, privacy: .public)")

            let envelope = PacketEnvelope(
                packetId: sel.packetId,
                packetType: sel.packetType,
                threadId: sel.threadId,
                messageIds: sel.messageIds,
                messageText: userText,
                contextRefsJson: nil,
                payloadJson: nil
            )

            outboxLog.info("processQueue run=\(runId, privacy: .public) event=send tx=\(short(sel.txId), privacy: .public)")

            let response = try await transport.send(envelope: envelope)

            outboxLog.info(
                "processQueue run=\(runId, privacy: .public) event=transport_ok tx=\(short(sel.txId), privacy: .public) http=\(response.statusCode, privacy: .public) pending=\(response.pending, privacy: .public) ms=\(msSince(startNs), format: .fixed(precision: 1))"
            )

            guard let freshTx = try? fetchTransmission(id: sel.txId) else { return }

            let outcome: DeliveryOutcome = (response.pending || response.statusCode == 202)
                ? .pending
                : (response.statusCode == 200 ? .succeeded : .failed)

            recordAttempt(
                tx: freshTx,
                statusCode: response.statusCode,
                outcome: outcome,
                errorMessage: nil,
                transmissionId: response.transmissionId
            )

            if let m = response.threadMemento {
                applyDraftMemento(runId: runId, freshTx: freshTx, txId: sel.txId, m: m, via: "send")
            }

            if response.pending || response.statusCode == 202 {
                freshTx.status = .queued
                outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=queued reason=pending")
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

            let code = statusCode(from: error)
            let msg = errorMessage(from: error)

            recordAttempt(
                tx: freshTx,
                statusCode: code,
                outcome: .failed,
                errorMessage: msg,
                transmissionId: nil
            )

            freshTx.status = .failed
            freshTx.lastError = msg

            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(sel.txId), privacy: .public) to=failed http=\(code, privacy: .public)")
        }

        try? modelContext.save()
    }

    private func enforceTerminalConditions(
        runId: String,
        tx: Transmission,
        txId: UUID,
        attempts: [DeliveryAttempt],
        attemptCount: Int,
        now: Date
    ) -> Bool {
        if attemptCount >= maxAttempts {
            // Client-side terminal: too many attempts.
            tx.status = .failed
            tx.lastError = "Max retry attempts exceeded (\(maxAttempts))"

            let attempt = DeliveryAttempt(
                statusCode: -1,
                outcome: .failed,
                errorMessage: tx.lastError,
                transmissionId: nil,
                transmission: tx
            )
            tx.deliveryAttempts.append(attempt)
            modelContext.insert(attempt)

            outboxLog.error("processQueue run=\(runId, privacy: .public) event=terminal_max_attempts tx=\(short(txId), privacy: .public) attempts=\(attemptCount, privacy: .public)")
            return true
        }

        if let pendingSince = pendingSinceIfActive(attempts) {
            let age = now.timeIntervalSince(pendingSince)

            if age > pendingTTLSeconds {
                // Client-side terminal: pending too long.
                tx.status = .failed
                tx.lastError = "Timed out waiting for delivery (pending > \(Int(pendingTTLSeconds))s)"

                let attempt = DeliveryAttempt(
                    statusCode: 408,
                    outcome: .failed,
                    errorMessage: tx.lastError,
                    transmissionId: nil,
                    transmission: tx
                )
                tx.deliveryAttempts.append(attempt)
                modelContext.insert(attempt)

                outboxLog.error("processQueue run=\(runId, privacy: .public) event=terminal_pending_ttl tx=\(short(txId), privacy: .public) ageSec=\(age, privacy: .public) ttlSec=\(self.pendingTTLSeconds, privacy: .public)")
                return true
            }
        }

        return false
    }

    private func shouldRespectBackoffAndExit(
        runId: String,
        txId: UUID,
        attempts: [DeliveryAttempt],
        attemptCount: Int,
        now: Date
    ) -> Bool {
        if let lastAt = attempts.last?.createdAt {
            let wait = backoffSeconds(forAttemptCount: attemptCount)
            let nextAt = lastAt.addingTimeInterval(wait)

            if now < nextAt {
                // Respect backoff: keep queued and exit quietly.
                outboxLog.info("processQueue run=\(runId, privacy: .public) event=backoff tx=\(short(txId), privacy: .public) waitSec=\(wait, privacy: .public) nextAt=\(timeWithSeconds(nextAt), privacy: .public)")
                return true
            }
        }

        return false
    }

    private func applyDraftMemento(runId: String, freshTx: Transmission, txId: UUID, m: ThreadMementoDTO, via: String) {
        freshTx.serverThreadMementoId = m.id
        freshTx.serverThreadMementoCreatedAtISO = m.createdAt
        freshTx.serverThreadMementoSummary = ThreadMementoFormatter.format(m)

        outboxLog.info("processQueue run=\(runId, privacy: .public) event=memento_draft_saved tx=\(short(txId), privacy: .public) memento=\(m.id, privacy: .public) via=\(via, privacy: .public)")
    }

    private func handlePendingPollIfNeeded(
        runId: String,
        txId: UUID,
        threadId: UUID,
        attempts: [DeliveryAttempt]
    ) async -> Bool {
        guard let last = attempts.last,
              last.outcome == .pending,
              let serverTxId = last.transmissionId,
              !serverTxId.isEmpty else {
            return false
        }

        outboxLog.info("processQueue run=\(runId, privacy: .public) event=poll_ready tx=\(short(txId), privacy: .public) serverTx=\(shortOrDash(serverTxId), privacy: .public)")

        guard let tx = try? fetchTransmission(id: txId) else { return true }

        // Mark as sending during poll for consistent UI semantics.
        tx.status = .sending
        tx.lastError = nil
        outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(txId), privacy: .public) to=sending reason=poll")

        do {
            guard let polling = transport as? any ChatTransportPolling else {
                outboxLog.error("processQueue run=\(runId, privacy: .public) event=poll_unavailable tx=\(short(txId), privacy: .public)")

                tx.status = .failed
                tx.lastError = "Transport does not support polling"
                return true
            }

            let poll = try await polling.poll(transmissionId: serverTxId)

            guard let freshTx = try? fetchTransmission(id: txId) else { return true }

            // Record a poll attempt so backoff/TTL derivation stays honest.
            recordAttempt(
                tx: freshTx,
                statusCode: poll.statusCode,
                outcome: poll.pending ? .pending : .succeeded,
                errorMessage: nil,
                transmissionId: serverTxId
            )

            if let m = poll.threadMemento {
                applyDraftMemento(runId: runId, freshTx: freshTx, txId: txId, m: m, via: "poll")
            }

            if poll.pending {
                freshTx.status = .queued
                outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(txId), privacy: .public) to=queued reason=pending_poll")
                return true
            }

            let assistantText = (poll.assistant?.isEmpty == false) ? poll.assistant! : "(no assistant text)"

            appendAssistantMessageIfPossible(
                threadId: threadId,
                assistantText: assistantText,
                transmissionId: serverTxId,
                evidence: poll.evidence,
                outputEnvelope: nil,
                runId: runId,
                txId: txId,
                via: "poll"
            )

            freshTx.status = .succeeded
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(txId), privacy: .public) to=succeeded reason=poll_complete")
            return true
        } catch {
            outboxLog.error("processQueue run=\(runId, privacy: .public) event=poll_failed tx=\(short(txId), privacy: .public) err=\(String(describing: error), privacy: .public)")

            guard let freshTx = try? fetchTransmission(id: txId) else { return true }

            recordAttempt(
                tx: freshTx,
                statusCode: -1,
                outcome: .failed,
                errorMessage: String(describing: error),
                transmissionId: serverTxId
            )

            freshTx.status = .failed
            freshTx.lastError = String(describing: error)

            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(txId), privacy: .public) to=failed reason=poll_failed")
            return true
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

        outboxLog.info("retryFailed event=end")
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
