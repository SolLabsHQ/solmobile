import SwiftUI
import SwiftData
import os
import Foundation

struct ThreadDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var thread: Thread
    @Query private var transmissions: [Transmission]
    @State private var isProcessingOutbox: Bool = false
    @State private var outboxNeedsRerun: Bool = false

    // ThreadMemento (navigation artifact): model-proposed snapshot returned by SolServer.
    // We store acceptance state locally (UserDefaults) so it survives view reloads.
    @State private var acceptedMemento: MementoViewModel? = nil
    @State private var mementoRefreshToken: Int = 0

    // Trace UI-level outbox lifecycle (retry taps, coalesced reruns, etc.)
    private let viewLog = Logger(subsystem: "com.sollabshq.solmobile", category: "ThreadDetailView")

    private var sortedMessages: [Message] {
        thread.messages.sorted { $0.createdAt < $1.createdAt }
    }

    init(thread: Thread) {
        self.thread = thread

        // Scope the SwiftData query to this thread so the UI refreshes from the right slice of data.
        let tid = thread.id
        _transmissions = Query(
            filter: #Predicate<Transmission> { tx in
                tx.packet.threadId == tid
            },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        VStack(spacing: 0) {

            // Accepted ThreadMemento (navigation snapshot).
            if let acceptedMemento {
                mementoAcceptedCard(acceptedMemento)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }

            // Pending ThreadMemento draft from latest server response.
            if let pending = pendingMementoCandidate {
                mementoPendingCard(pending)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(sortedMessages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                }
                .onChange(of: sortedMessages.count) { _, _ in
                    guard let last = sortedMessages.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }

            Divider()

            // Outbox banner reflects local Transmission state (queued/sending/failed).
            if let banner = outboxBanner {
                banner
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }

            ComposerView { text in
                send(text)
            }
            .padding(10)
        }
        .onChange(of: outboxSummary.failed + outboxSummary.queued + outboxSummary.sending) { _, newValue in
            viewLog.debug("[outboxBanner] refresh total=\(newValue, privacy: .public)")
        }
        .onAppear {
            loadAcceptedMementoFromDefaults()
            processOutbox()
        }
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send(_ text: String) {
        let m = Message(thread: thread, creatorType: .user, text: text)
        thread.messages.append(m)
        thread.lastActiveAt = Date()
        modelContext.insert(m)

        viewLog.info("[send] thread=\(thread.id.uuidString.prefix(8), privacy: .public) msg=\(m.id.uuidString.prefix(8), privacy: .public) len=\(text.count, privacy: .public)")

        let tx = TransmissionActions(modelContext: modelContext)
        tx.enqueueChat(thread: thread, userMessage: m)

        processOutbox()
    }

    private var outboxBanner: AnyView? {
        let s = outboxSummary

        if s.failed > 0 {
            return AnyView(
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Failed to send \(s.failed) item\(s.failed == 1 ? "" : "s").")
                        .font(.footnote)
                    Spacer()
                    Button("Retry") {
                        viewLog.info("[retry] tapped")

                        let before = outboxSummary
                        viewLog.info("[retry] before failed=\(before.failed, privacy: .public) queued=\(before.queued, privacy: .public) sending=\(before.sending, privacy: .public)")

                        let tx = TransmissionActions(modelContext: modelContext)
                        tx.retryFailed()

                        let after = outboxSummary
                        viewLog.info("[retry] after failed=\(after.failed, privacy: .public) queued=\(after.queued, privacy: .public) sending=\(after.sending, privacy: .public)")

                        processOutbox()
                    }
                    .font(.footnote)
                }
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            )
        }

        if s.queued + s.sending > 0 {
            return AnyView(
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Sending…")
                        .font(.footnote)
                    Spacer()
                }
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            )
        }

        return nil
    }

    private struct OutboxSummary {
        var queued: Int
        var sending: Int
        var failed: Int
    }

    // MARK: - ThreadMemento UI + state

    private struct MementoViewModel: Equatable {
        let id: String
        let summary: String
        let createdAtISO: String?
    }

    private var mementoDefaultsKeyCurrent: String {
        "sol.threadMemento.current.\(thread.id.uuidString)"
    }

    private var mementoDefaultsKeyPrev: String {
        "sol.threadMemento.prev.\(thread.id.uuidString)"
    }

    private var mementoDefaultsKeyDismissed: String {
        "sol.threadMemento.dismissed.\(thread.id.uuidString)"
    }

    private func mementoAcceptedCard(_ m: MementoViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Thread memento")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Undo") {
                    viewLog.info("[memento] undo tapped")
                    undoAcceptedMemento()
                }
                .font(.footnote)
            }

            Text(m.summary)
                .font(.footnote)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func mementoPendingCard(_ m: MementoViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                Text("Memento draft")
                    .font(.footnote)
                Spacer()
            }

            Text(m.summary)
                .font(.footnote)
                .textSelection(.enabled)

            // Keep buttons vertical to avoid the "whole bar is one button" feel.
            VStack(spacing: 8) {
                Button {
                    viewLog.info("[memento] accept tapped id=\(m.id, privacy: .public)")
                    acceptMemento(m)
                } label: {
                    Text("Accept")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewLog.info("[memento] decline tapped id=\(m.id, privacy: .public)")
                    declineMemento(m)
                } label: {
                    Text("Decline")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func loadAcceptedMementoFromDefaults() {
        guard let raw = UserDefaults.standard.dictionary(forKey: mementoDefaultsKeyCurrent) else {
            acceptedMemento = nil
            return
        }

        let id = raw["id"] as? String ?? ""
        let summary = raw["summary"] as? String ?? ""
        let createdAtISO = raw["createdAtISO"] as? String

        if !id.isEmpty, !summary.isEmpty {
            acceptedMemento = MementoViewModel(id: id, summary: summary, createdAtISO: createdAtISO)
        } else {
            acceptedMemento = nil
        }
    }

    private func acceptMemento(_ m: MementoViewModel) {
        // Move current -> prev for Undo.
        if let current = UserDefaults.standard.dictionary(forKey: mementoDefaultsKeyCurrent) {
            UserDefaults.standard.set(current, forKey: mementoDefaultsKeyPrev)
        }

        UserDefaults.standard.set(
            ["id": m.id, "summary": m.summary, "createdAtISO": m.createdAtISO as Any],
            forKey: mementoDefaultsKeyCurrent
        )

        // Mark this draft id as dismissed so we don’t re-show it.
        UserDefaults.standard.set(m.id, forKey: mementoDefaultsKeyDismissed)

        acceptedMemento = m
        mementoRefreshToken &+= 1
    }

    private func declineMemento(_ m: MementoViewModel) {
        // Decline only dismisses this draft id. It does not change the accepted memento.
        UserDefaults.standard.set(m.id, forKey: mementoDefaultsKeyDismissed)
        mementoRefreshToken &+= 1
    }

    private func undoAcceptedMemento() {
        guard let prev = UserDefaults.standard.dictionary(forKey: mementoDefaultsKeyPrev) else {
            viewLog.info("[memento] undo: no prev")
            return
        }

        // Swap current <-> prev.
        if let current = UserDefaults.standard.dictionary(forKey: mementoDefaultsKeyCurrent) {
            UserDefaults.standard.set(current, forKey: mementoDefaultsKeyPrev)
        }
        UserDefaults.standard.set(prev, forKey: mementoDefaultsKeyCurrent)

        loadAcceptedMementoFromDefaults()
    }

    private var pendingMementoCandidate: MementoViewModel? {
        // Link to a local state token so Accept/Decline can force a re-evaluation even though
        // UserDefaults changes are not automatically observed.
        _ = mementoRefreshToken

        // v0: best effort.
        // Look at the latest Transmission for this thread and read the server-proposed ThreadMemento draft
        // that `TransmissionActions` persisted from the SolServer response.
        guard let latest = transmissions.first else {
            return nil
        }

        guard
            let id = latest.serverThreadMementoId,
            let summary = latest.serverThreadMementoSummary,
            !id.isEmpty,
            !summary.isEmpty
        else {
            return nil
        }

        let extracted = MementoViewModel(
            id: id,
            summary: summary,
            createdAtISO: latest.serverThreadMementoCreatedAtISO
        )

        // Do not show if the user already accepted/declined this id.
        let dismissedId = UserDefaults.standard.string(forKey: mementoDefaultsKeyDismissed)
        if dismissedId == extracted.id {
            return nil
        }

        // Do not show if it matches the current accepted.
        if acceptedMemento?.id == extracted.id {
            return nil
        }

        return extracted
    }


    private var outboxSummary: OutboxSummary {
        // Live derived state: @Query updates when SwiftData changes.
        // NOTE: `transmissions` is already scoped to this thread via init().
        let queued = transmissions.filter { $0.status == .queued }.count
        let sending = transmissions.filter { $0.status == .sending }.count
        let failed = transmissions.filter { $0.status == .failed }.count

        return OutboxSummary(queued: queued, sending: sending, failed: failed)
    }

    private func processOutbox() {
        viewLog.info("[processOutbox] called isProcessing=\(isProcessingOutbox, privacy: .public)")

        // Coalesce calls: if we're already processing, request another pass and exit.
        guard !isProcessingOutbox else {
            outboxNeedsRerun = true
            viewLog.info("[processOutbox] coalesce: needsRerun=true")
            return
        }

        isProcessingOutbox = true

        viewLog.info("[processOutbox] run start")

        Task {
            let tx = TransmissionActions(modelContext: modelContext)
            await tx.processQueue()

            viewLog.info("[processOutbox] run end")

            await MainActor.run {
                isProcessingOutbox = false

                if outboxNeedsRerun {
                    outboxNeedsRerun = false
                    viewLog.info("[processOutbox] rerun requested -> kicking")
                    processOutbox()
                }
            }
        }
    }
}

private struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.creatorType == .user { Spacer(minLength: 40) }

            Text(message.text)
                .padding(10)
                .background(message.creatorType == .user ? Color.gray.opacity(0.2) : Color.blue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if message.creatorType != .user { Spacer(minLength: 40) }
        }
    }
}
