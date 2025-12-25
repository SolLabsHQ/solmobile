//
//  TransmissionAction.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/22/25.
//

import Foundation
import SwiftData
import os

private let transportLog = Logger(subsystem: "com.sollabshq.solmobile", category: "Transport")

// Dev telemetry keys (UserDefaults) for quick transport health visibility.
private enum DevTelemetry {
    static let lastChatStatusCodeKey = "sol.dev.lastChatStatusCode"
    static let lastChatStatusAtKey = "sol.dev.lastChatStatusAt"

    static func persistLastChat(statusCode: Int) {
        UserDefaults.standard.set(statusCode, forKey: lastChatStatusCodeKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastChatStatusAtKey)
    }
}


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

// ThreadMemento is a navigation artifact returned by SolServer.
// It is not durable knowledge; the client may choose to Accept or Decline.
private enum ThreadMementoFormatter {
    static func format(_ m: ThreadMementoDTO) -> String {
        func join(_ xs: [String]) -> String { xs.isEmpty ? "(none)" : xs.joined(separator: " | ") }

        return [
            "Arc: \(m.arc.isEmpty ? "(none)" : m.arc)",
            "Active: \(join(m.active))",
            "Parked: \(join(m.parked))",
            "Decisions: \(join(m.decisions))",
            "Next: \(join(m.next))",
        ].joined(separator: "\n")
    }
}

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
        self.transport = transport ?? StubChatTransport()
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

    func enqueueChat(thread: Thread, userMessage: Message) {
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

        let queuedRaw = TransmissionStatus.queued.rawValue
        let descriptor = FetchDescriptor<Transmission>(
            predicate: #Predicate { $0.statusRaw == queuedRaw },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        guard let queued = try? modelContext.fetch(descriptor) else {
            outboxLog.error("processQueue run=\(runId, privacy: .public) event=fetch_failed scope=queued")
            return
        }

        outboxLog.info("processQueue run=\(runId, privacy: .public) event=queued_count count=\(queued.count, privacy: .public)")

        guard let tx = queued.first else {
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=empty")
            return
        } // v0: one in-flight at a time

        // Snapshot identifiers before we suspend.
        let txId = tx.id
        let packet = tx.packet
        let threadId = packet.threadId
        let firstMessageId = packet.messageIds.first

        outboxLog.info("processQueue run=\(runId, privacy: .public) event=selected tx=\(short(txId), privacy: .public) packet=\(short(packet.id), privacy: .public) type=\(packet.packetType, privacy: .public) thread=\(short(threadId), privacy: .public)")

        // Derive retry/backoff/timeout from local attempt ledger.
        let now = Date()
        let attempts = tx.deliveryAttempts.sorted { $0.createdAt < $1.createdAt }
        let attemptCount = attempts.count

        // If the last attempt is pending and we have a server transmissionId, poll instead of re-sending.
        if let last = attempts.last,
           last.outcome == .pending,
           let serverTxId = last.transmissionId,
           !serverTxId.isEmpty {

            outboxLog.info("processQueue run=\(runId, privacy: .public) event=poll_ready tx=\(short(txId), privacy: .public) serverTx=\(shortOrDash(serverTxId), privacy: .public)")

            // Mark as sending during poll for consistent UI semantics.
            tx.status = .sending
            tx.lastError = nil
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(txId), privacy: .public) to=sending reason=poll")

            do {
                guard let polling = transport as? any ChatTransportPolling else {
                    outboxLog.error("processQueue run=\(runId, privacy: .public) event=poll_unavailable tx=\(short(txId), privacy: .public)")

                    tx.status = .failed
                    tx.lastError = "Transport does not support polling"
                    return
                }

                let poll = try await polling.poll(transmissionId: serverTxId)

                guard let freshTx = try? fetchTransmission(id: txId) else { return }

                // Record a poll attempt so backoff/TTL derivation stays honest.
                let pollAttempt = DeliveryAttempt(
                    statusCode: poll.statusCode,
                    outcome: poll.pending ? .pending : .succeeded,
                    errorMessage: nil,
                    transmissionId: serverTxId,
                    transmission: freshTx
                )
                freshTx.deliveryAttempts.append(pollAttempt)
                modelContext.insert(pollAttempt)

                if let m = poll.threadMemento {
                    freshTx.serverThreadMementoId = m.id
                    freshTx.serverThreadMementoCreatedAtISO = m.createdAt
                    freshTx.serverThreadMementoSummary = ThreadMementoFormatter.format(m)

                    outboxLog.info("processQueue run=\(runId, privacy: .public) event=memento_draft_saved tx=\(short(txId), privacy: .public) memento=\(m.id, privacy: .public) via=poll")
                }

                if poll.pending {
                    freshTx.status = .queued
                    outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(txId), privacy: .public) to=queued reason=pending_poll")
                    return
                }

                // Completed: append assistant message (if provided) and mark succeeded.
                let assistantText = (poll.assistant?.isEmpty == false) ? poll.assistant! : "(no assistant text)"

                if let thread = try? fetchThread(id: threadId) {
                    let assistantMessage = Message(thread: thread, creatorType: .assistant, text: assistantText)

                    thread.messages.append(assistantMessage)
                    thread.lastActiveAt = Date()

                    modelContext.insert(assistantMessage)

                    outboxLog.info("processQueue run=\(runId, privacy: .public) event=assistant_appended tx=\(short(txId), privacy: .public) via=poll")
                }

                freshTx.status = .succeeded
                outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(txId), privacy: .public) to=succeeded reason=poll_complete")
                return
            } catch {
                outboxLog.error("processQueue run=\(runId, privacy: .public) event=poll_failed tx=\(short(txId), privacy: .public) err=\(String(describing: error), privacy: .public)")

                guard let freshTx = try? fetchTransmission(id: txId) else { return }

                let attempt = DeliveryAttempt(
                    statusCode: -1,
                    outcome: .failed,
                    errorMessage: String(describing: error),
                    transmissionId: serverTxId,
                    transmission: freshTx
                )
                freshTx.deliveryAttempts.append(attempt)
                modelContext.insert(attempt)

                freshTx.status = .failed
                freshTx.lastError = String(describing: error)

                outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(txId), privacy: .public) to=failed reason=poll_failed")
                return
            }
        }

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
            return
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
                return
            }
        }

        if let lastAt = attempts.last?.createdAt {
            let wait = backoffSeconds(forAttemptCount: attemptCount)
            let nextAt = lastAt.addingTimeInterval(wait)

            if now < nextAt {
                // Respect backoff: keep queued and exit quietly.
                outboxLog.info("processQueue run=\(runId, privacy: .public) event=backoff tx=\(short(txId), privacy: .public) waitSec=\(wait, privacy: .public) nextAt=\(timeWithSeconds(nextAt), privacy: .public)")
                return
            }
        }

        let startNs = DispatchTime.now().uptimeNanoseconds

        tx.status = .sending
        tx.lastError = nil

        outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(txId), privacy: .public) to=sending")

        do {
            let packet = tx.packet
            let userText = (firstMessageId.flatMap { try? fetchMessage(id: $0)?.text }) ?? ""

            outboxLog.debug("processQueue run=\(runId, privacy: .public) event=context tx=\(short(txId), privacy: .public) userTextLen=\(userText.count, privacy: .public)")

            let envelope = PacketEnvelope(
                packetId: packet.id,
                packetType: packet.packetType,
                threadId: packet.threadId,
                messageIds: packet.messageIds,
                messageText: userText,
                contextRefsJson: packet.contextRefsJson,
                payloadJson: packet.payloadJson
            )

            // IMPORTANT: Don't mutate SwiftData models after the await unless refetched.
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=send tx=\(short(txId), privacy: .public)")

            let response = try await transport.send(envelope: envelope)

            outboxLog.info("processQueue run=\(runId, privacy: .public) event=transport_ok tx=\(short(txId), privacy: .public) http=\(response.statusCode, privacy: .public) pending=\(response.pending, privacy: .public) ms=\(msSince(startNs), format: .fixed(precision: 1))")

            guard let freshTx = try? fetchTransmission(id: txId) else { return }

            // Record attempt (local-first observability).
            let outcome: DeliveryOutcome = (response.pending || response.statusCode == 202)
                ? .pending
                : (response.statusCode == 200 ? .succeeded : .failed)

            let attempt = DeliveryAttempt(
                statusCode: response.statusCode,
                outcome: outcome,
                errorMessage: nil,
                transmissionId: response.transmissionId,
                transmission: freshTx
            )
            freshTx.deliveryAttempts.append(attempt)
            modelContext.insert(attempt)

            if let m = response.threadMemento {
                freshTx.serverThreadMementoId = m.id
                freshTx.serverThreadMementoCreatedAtISO = m.createdAt
                freshTx.serverThreadMementoSummary = ThreadMementoFormatter.format(m)

                outboxLog.info("processQueue run=\(runId, privacy: .public) event=memento_draft_saved tx=\(short(txId), privacy: .public) memento=\(m.id, privacy: .public) via=send")
            }

            // Pending: keep queued so a future outbox pass can poll server-side completion.
            if response.pending || response.statusCode == 202 {
                // Accepted but not delivered yet: keep it eligible for another outbox pass.
                freshTx.status = .queued
                outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(txId), privacy: .public) to=queued reason=pending")
                return
            }

            // Delivered: append assistant message and mark succeeded.
            if let thread = try? fetchThread(id: threadId) {
                let assistantText = response.text.isEmpty ? "(no assistant text)" : response.text
                let assistantMessage = Message(thread: thread, creatorType: .assistant, text: assistantText)

                thread.messages.append(assistantMessage)
                thread.lastActiveAt = Date()

                modelContext.insert(assistantMessage)

                outboxLog.info("processQueue run=\(runId, privacy: .public) event=assistant_appended tx=\(short(txId), privacy: .public)")
            }

            freshTx.status = .succeeded
            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(txId), privacy: .public) to=succeeded")
        }
        catch {
            outboxLog.error("processQueue run=\(runId, privacy: .public) event=transport_failed tx=\(short(txId), privacy: .public) ms=\(msSince(startNs), format: .fixed(precision: 1)) err=\(String(describing: error), privacy: .public)")

            guard let freshTx = try? fetchTransmission(id: txId) else { return }

            // Best-effort HTTP status extraction for observability.
            let statusCode: Int = {
                switch error {
                case ChatTransportError.simulatedFailure:
                    return 500
                case let ChatTransportError.httpStatus(code, _):
                    return code
                default:
                    return -1
                }
            }()

            let errorMessage: String = {
                switch error {
                case let ChatTransportError.httpStatus(_, body):
                    return body.isEmpty ? String(describing: error) : body
                default:
                    return String(describing: error)
                }
            }()

            let attempt = DeliveryAttempt(
                statusCode: statusCode,
                outcome: .failed,
                errorMessage: errorMessage,
                transmissionId: nil,
                transmission: freshTx
            )
            freshTx.deliveryAttempts.append(attempt)
            modelContext.insert(attempt)

            freshTx.status = .failed
            freshTx.lastError = errorMessage

            outboxLog.info("processQueue run=\(runId, privacy: .public) event=status tx=\(short(txId), privacy: .public) to=failed http=\(statusCode, privacy: .public)")
        }

        outboxLog.info("processQueue run=\(runId, privacy: .public) event=end")
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

    private func fetchThread(id: UUID) throws -> Thread? {
        let d = FetchDescriptor<Thread>(predicate: #Predicate { $0.id == id })
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

// Optional capability: some transports can poll server-side delivery for pending (202) transmissions.
protocol ChatTransportPolling: ChatTransport {
    func poll(transmissionId: String) async throws -> ChatPollResponse
}

struct ChatPollResponse {
    let pending: Bool
    let assistant: String?
    let serverStatus: String?
    let statusCode: Int

    let threadMemento: ThreadMementoDTO?
}

enum ChatTransportError: Error {
    case simulatedFailure
    case httpStatus(code: Int, body: String)
}

struct ChatResponse {
    let text: String
    let statusCode: Int
    let transmissionId: String?
    let pending: Bool

    let threadMemento: ThreadMementoDTO?
}

private struct SolServerChatRequestDTO: Codable {
    let threadId: String
    let clientRequestId: String
    let message: String
}

private struct SolServerChatResponseDTO: Codable {
    let ok: Bool
    let transmissionId: String?
    let assistant: String?
    let idempotentReplay: Bool?
    let pending: Bool?
    let status: String?

    let threadMemento: ThreadMementoDTO?
}

private struct SolServerTransmissionResponseDTO: Codable {
    struct TransmissionDTO: Codable {
        let id: String
        let status: String
    }

    let ok: Bool
    let transmission: TransmissionDTO
    let pending: Bool?
    let assistant: String?

    let threadMemento: ThreadMementoDTO?
}

struct StubChatTransport: ChatTransportPolling {
    func poll(transmissionId: String) async throws -> ChatPollResponse {
        let startNs = DispatchTime.now().uptimeNanoseconds

        let url = baseURL
            .appendingPathComponent("/v1/transmissions")
            .appendingPathComponent(transmissionId)

        transportLog.debug("poll event=url url=\(url.absoluteString, privacy: .public)")

        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        transportLog.info("poll event=response http=\(http.statusCode, privacy: .public) ms=\(msSince(startNs), format: .fixed(precision: 1)) tx=\(shortOrDash(transmissionId), privacy: .public)")

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            transportLog.error("poll event=error http=\(http.statusCode, privacy: .public) bodyLen=\(body.count, privacy: .public)")
            throw ChatTransportError.httpStatus(code: http.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(SolServerTransmissionResponseDTO.self, from: data)
        let pending = decoded.pending ?? (decoded.transmission.status == "created")

        transportLog.info("poll event=decoded pending=\(pending, privacy: .public) serverStatus=\(decoded.transmission.status, privacy: .public) assistantLen=\((decoded.assistant ?? "").count, privacy: .public)")

        return ChatPollResponse(
            pending: pending,
            assistant: decoded.assistant,
            serverStatus: decoded.transmission.status,
            statusCode: http.statusCode,
            threadMemento: decoded.threadMemento
        )
    }

    // Base URL is driven by Settings (@AppStorage -> UserDefaults)
    private var baseURL: URL {
        let raw = (UserDefaults.standard.string(forKey: "solserver.baseURL") ?? "http://127.0.0.1:3333")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Hard fallback for safety
        return URL(string: raw) ?? URL(string: "http://127.0.0.1:3333")!
    }

    func send(envelope: PacketEnvelope) async throws -> ChatResponse {
        let startNs = DispatchTime.now().uptimeNanoseconds

        transportLog.info("send event=start packet=\(short(envelope.packetId), privacy: .public) thread=\(short(envelope.threadId), privacy: .public) type=\(envelope.packetType, privacy: .public)")

        // v0: keep simulated failure path for pipeline testing
        let simulate500 = (envelope.packetType == "chat_fail")

        let url = baseURL.appendingPathComponent("/v1/chat")

        transportLog.debug("send event=url url=\(url.absoluteString, privacy: .public)")

        // build request
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // set for request failures
        if simulate500 {
            req.setValue("500", forHTTPHeaderField: "x-sol-simulate-status")
            transportLog.info("send event=simulate http=500")
        }

        let simulate202 = envelope.messageText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("/pending")

        if simulate202 {
            req.setValue("202", forHTTPHeaderField: "x-sol-simulate-status")
            transportLog.info("send event=simulate http=202")
        }

        // Use packetId as idempotency key so retries dedupe server-side.
        let dto = SolServerChatRequestDTO(
            threadId: envelope.threadId.uuidString,
            clientRequestId: envelope.packetId.uuidString,
            message: envelope.messageText
        )

        req.httpBody = try JSONEncoder().encode(dto)

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // Persist for Settings/Dev UI.
        DevTelemetry.persistLastChat(statusCode: http.statusCode)

        let headerTxId = http.value(forHTTPHeaderField: "x-sol-transmission-id")
        transportLog.info("send event=response http=\(http.statusCode, privacy: .public) ms=\(msSince(startNs), format: .fixed(precision: 1)) tx=\(shortOrDash(headerTxId), privacy: .public)")

        // If 500 returns and we are simulation flow, send correct simulation failure error.
        if simulate500, http.statusCode == 500 {
            transportLog.error("send event=simulated_failure http=500 action=throw")
            throw ChatTransportError.simulatedFailure
        }

        if simulate202, http.statusCode == 202 {
            transportLog.info("send event=simulated_pending http=202")
        }
        // 202 means accepted/pending. We return pending=true and rely on outbox polling to complete it.
        // If server replies "pending" (202), this is NOT a delivered assistant message.
        // We return pending=true so the queue can keep the Transmission queued/sending.
        if http.statusCode == 202 {
            let decoded = (try? JSONDecoder().decode(SolServerChatResponseDTO.self, from: data))
            let txId = headerTxId ?? decoded?.transmissionId
            transportLog.info("send event=pending http=202 tx=\(shortOrDash(txId), privacy: .public)")
            return ChatResponse(
                text: "",
                statusCode: 202,
                transmissionId: txId,
                pending: true,
                threadMemento: decoded?.threadMemento
            )
        }

        // If a 2XX response then good; else throw with status preserved for retry/attempt recording.
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            transportLog.error("send event=error http=\(http.statusCode, privacy: .public) bodyLen=\(body.count, privacy: .public)")
            throw ChatTransportError.httpStatus(code: http.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(SolServerChatResponseDTO.self, from: data)
        let txId = headerTxId ?? decoded.transmissionId
        let isPending = (decoded.pending ?? false) || http.statusCode == 202
        transportLog.info("send event=decoded assistantLen=\((decoded.assistant ?? "").count, privacy: .public) pending=\(isPending, privacy: .public) tx=\(shortOrDash(txId), privacy: .public)")

        return ChatResponse(
            text: decoded.assistant ?? "(no assistant text)",
            statusCode: http.statusCode,
            transmissionId: txId,
            pending: isPending,
            threadMemento: decoded.threadMemento
        )
    }
}
