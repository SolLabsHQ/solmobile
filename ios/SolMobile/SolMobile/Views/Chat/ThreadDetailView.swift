import SwiftUI
import SwiftData
import os
import Foundation
import UIKit

struct ThreadDetailView: View {
    private static let perfLog = OSLog(subsystem: "com.sollabshq.solmobile", category: "ThreadDetailPerf")

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var thread: ConversationThread
    @Query private var messages: [Message]
    @Query private var transmissions: [Transmission]
    @State private var isProcessingOutbox: Bool = false
    @State private var outboxNeedsRerun: Bool = false
    @State private var cachedOutboxSummary = OutboxSummary(queued: 0, sending: 0, failed: 0)
    @State private var keyboardSignpostId = OSSignpostID(log: ThreadDetailView.perfLog)
    @State private var keyboardSignpostActive = false

    // ThreadMemento (navigation artifact): model-proposed snapshot returned by SolServer.
    // We store acceptance state locally (UserDefaults) so it survives view reloads.
    @State private var acceptedMemento: MementoViewModel? = nil
    @State private var mementoRefreshToken: Int = 0

    // Transient toast for lightweight feedback (Accept/Decline/Undo).
    @State private var toastMessage: String? = nil
    @State private var toastToken: Int = 0

    // Composer draft persistence (ADR-021).
    @State private var composerText: String = ""
    @State private var draftSaveTask: Task<Void, Never>? = nil
    @State private var pendingSendClear: Bool = false

    // Trace UI-level outbox lifecycle (retry taps, coalesced reruns, etc.)
    private let viewLog = Logger(subsystem: "com.sollabshq.solmobile", category: "ThreadDetailView")

    init(thread: ConversationThread) {
        self.thread = thread

        // Scope the SwiftData query to this thread so the UI refreshes from the right slice of data.
        let tid = thread.id
        _messages = Query(
            filter: #Predicate<Message> { msg in
                msg.thread.id == tid
            },
            sort: [SortDescriptor(\.createdAt, order: .forward)]
        )
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

            // Mini toast: short-lived feedback for memento actions.
            if let toastMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                    Text(toastMessage)
                        .font(.footnote)
                    Spacer()
                }
                .padding(10)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: toastMessage)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    guard let last = messages.last else { return }
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

            ComposerView(text: $composerText) { text in
                send(text)
            }
            .padding(10)
        }
        .onChange(of: outboxSummary.failed + outboxSummary.queued + outboxSummary.sending) { _, newValue in
            viewLog.debug("[outboxBanner] refresh total=\(newValue, privacy: .public)")
        }
        .onChange(of: outboxStatusSignature) { _, _ in
            updateOutboxSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            let id = OSSignpostID(log: Self.perfLog)
            keyboardSignpostId = id
            keyboardSignpostActive = true
            os_signpost(.begin, log: Self.perfLog, name: "KeyboardShow", signpostID: id)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            guard keyboardSignpostActive else { return }
            os_signpost(.end, log: Self.perfLog, name: "KeyboardShow", signpostID: keyboardSignpostId)
            keyboardSignpostActive = false
        }
        .onChange(of: composerText) { _, newValue in
            handleComposerTextChange(newValue)
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .background {
                draftStore.forceSaveNow(threadId: thread.id, content: composerText)
            }
        }
        .onAppear {
            loadAcceptedMementoFromDefaults()
            updateOutboxSummary()
            processOutbox()
            restoreDraftIfNeeded()
        }
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send(_ text: String) {
        draftStore.forceSaveNow(threadId: thread.id, content: text)
        pendingSendClear = true
        composerText = ""

        let m = Message(thread: thread, creatorType: .user, text: text)
        thread.messages.append(m)
        thread.lastActiveAt = Date()
        modelContext.insert(m)

        viewLog.info("[send] thread=\(thread.id.uuidString.prefix(8), privacy: .public) msg=\(m.id.uuidString.prefix(8), privacy: .public) len=\(text.count, privacy: .public)")

        let tx = TransmissionActions(modelContext: modelContext)
        tx.enqueueChat(thread: thread, userMessage: m)

        processOutbox()
    }

    private var draftStore: DraftStore {
        DraftStore(modelContext: modelContext)
    }

    private func restoreDraftIfNeeded() {
        guard composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let draft = draftStore.fetchDraft(threadId: thread.id) {
            composerText = draft.content
        }
    }

    private func handleComposerTextChange(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        draftSaveTask?.cancel()

        if trimmed.isEmpty {
            if pendingSendClear {
                return
            }

            draftStore.deleteDraft(threadId: thread.id)
            return
        }

        pendingSendClear = false
        scheduleDraftSave(trimmed)
    }

    private func scheduleDraftSave(_ content: String) {
        let threadId = thread.id
        draftSaveTask = Task { [content] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                draftStore.upsertDraft(threadId: threadId, content: content)
            }
        }
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

    @MainActor
    private func showToast(_ text: String) {
        toastMessage = text

        // Token-based clear so rapid taps don't race.
        toastToken &+= 1
        let token = toastToken

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard self.toastToken == token else { return }
            self.toastMessage = nil
        }
    }

private func acceptMemento(_ m: MementoViewModel) {
    // Move current -> prev for Undo.
    if let current = UserDefaults.standard.dictionary(forKey: mementoDefaultsKeyCurrent) {
        UserDefaults.standard.set(current, forKey: mementoDefaultsKeyPrev)
    }

    // Optimistic local accept so the UI updates immediately.
    UserDefaults.standard.set(
        ["id": m.id, "summary": m.summary, "createdAtISO": m.createdAtISO as Any],
        forKey: mementoDefaultsKeyCurrent
    )

    // Mark this draft id as dismissed so we don’t re-show it.
    UserDefaults.standard.set(m.id, forKey: mementoDefaultsKeyDismissed)

    acceptedMemento = m

    // Submit to SolServer (throws on transport issues). We still keep the optimistic UI.
    Task {
        let actions = TransmissionActions(modelContext: modelContext)

        do {
            let result = try await actions.decideThreadMemento(
                threadId: thread.id,
                mementoId: m.id,
                decision: .accept
            )

            // Server may return a different id for the accepted artifact.
            if let applied = result.memento, result.applied {
                let patched = MementoViewModel(id: applied.id, summary: m.summary, createdAtISO: applied.createdAt)

                UserDefaults.standard.set(
                    ["id": patched.id, "summary": patched.summary, "createdAtISO": patched.createdAtISO as Any],
                    forKey: mementoDefaultsKeyCurrent
                )

                await MainActor.run {
                    acceptedMemento = patched
                    showToast("Accepted")
                }

                viewLog.info("[memento] accept applied serverId=\(applied.id, privacy: .public)")
            } else if result.reason == "already_accepted" {
                await MainActor.run { showToast("Already accepted") }
                viewLog.info("[memento] accept already_accepted")
            } else {
                await MainActor.run { showToast("Accept not applied") }
                viewLog.info("[memento] accept not_applied reason=\(result.reason ?? "-", privacy: .public)")
            }
        } catch {
            await MainActor.run { showToast("Accept failed") }
            viewLog.error("[memento] accept failed err=\(String(describing: error), privacy: .public)")
        }

        await MainActor.run { mementoRefreshToken &+= 1 }
    }
}

    private func declineMemento(_ m: MementoViewModel) {
        // Decline only dismisses this draft id. It does not change the accepted memento.
        UserDefaults.standard.set(m.id, forKey: mementoDefaultsKeyDismissed)

        // Submit to SolServer and clear the local draft fields so the banner disappears immediately.
        Task {
            let actions = TransmissionActions(modelContext: modelContext)
            do {
                let result = try await actions.decideThreadMemento(threadId: thread.id, mementoId: m.id, decision: .decline)

                await MainActor.run {
                    showToast(result.applied ? "Declined" : "Decline saved")
                    // Force re-evaluation (UserDefaults is not observed).
                    mementoRefreshToken &+= 1
                }
            } catch {
                await MainActor.run {
                    showToast("Decline failed")
                    // Force re-evaluation (UserDefaults is not observed).
                    mementoRefreshToken &+= 1
                }

                viewLog.error("[memento] decline failed err=\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func undoAcceptedMemento() {
        guard let prev = UserDefaults.standard.dictionary(forKey: mementoDefaultsKeyPrev) else {
            viewLog.info("[memento] undo: no prev")
            return
        }

        // Remove prev.
        UserDefaults.standard.removeObject(forKey: mementoDefaultsKeyPrev)

        if let current = UserDefaults.standard.dictionary(forKey: mementoDefaultsKeyCurrent) {

            let id = current["id"] as? String ?? ""

            // Submit to SolServer and clear the local draft fields so the banner disappears immediately.
            Task {
                let actions = TransmissionActions(modelContext: modelContext)
                do {
                    let result = try await actions.decideThreadMemento(threadId: thread.id, mementoId: id, decision: .revoke)

                    await MainActor.run {
                        showToast(result.applied ? "Undone" : "Undo saved")
                        // Force re-evaluation (UserDefaults is not observed).
                        mementoRefreshToken &+= 1
                    }
                } catch {
                    await MainActor.run {
                        showToast("Undo failed")
                        // Force re-evaluation (UserDefaults is not observed).
                        mementoRefreshToken &+= 1
                    }

                    viewLog.error("[memento] revoke failed err=\(String(describing: error), privacy: .public)")
                }
            }
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


    private var outboxSummary: OutboxSummary { cachedOutboxSummary }

    private var outboxStatusSignature: String {
        transmissions.map { $0.statusRaw }.joined(separator: "|")
    }

    private func updateOutboxSummary() {
        // Derived state from SwiftData query; cache to avoid repeated filters during renders.
        let queued = transmissions.filter { $0.status == .queued }.count
        let sending = transmissions.filter { $0.status == .sending }.count
        let failed = transmissions.filter { $0.status == .failed }.count
        cachedOutboxSummary = OutboxSummary(queued: queued, sending: sending, failed: failed)
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

        let container = modelContext.container
        let perfLog = Self.perfLog
        let signpostId = OSSignpostID(log: perfLog)
        os_signpost(.begin, log: perfLog, name: "OutboxProcess", signpostID: signpostId)
        Task.detached { [container, perfLog] in
            let tx = await MainActor.run { TransmissionActions(modelContext: ModelContext(container)) }
            await tx.processQueue()

            viewLog.info("[processOutbox] run end")
            os_signpost(.end, log: perfLog, name: "OutboxProcess", signpostID: signpostId)

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
    @State private var showingClaims = false

    var body: some View {
        HStack {
            if message.creatorType == .user { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 0) {
                Text(message.text)
                    .padding(10)
                    .background(message.creatorType == .user ? Color.gray.opacity(0.2) : Color.blue.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if message.creatorType == .assistant && hasClaimsBadge {
                    Button {
                        showingClaims = true
                    } label: {
                        Text("Evidence (\(message.claimsCount))")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    .padding(.horizontal, 10)
                    .sheet(isPresented: $showingClaims) {
                        EvidenceClaimsSheet(message: message)
                    }
                }

                if message.creatorType == .assistant, let capture = message.captureSuggestion {
                    CaptureSuggestionCard(message: message, suggestion: capture)
                        .padding(.top, 6)
                        .padding(.horizontal, 10)
                }
                
                // Evidence UI (PR #8) - only show for assistant messages with evidence
                if message.creatorType == .assistant && hasEvidence {
                    EvidenceView(
                        message: message,
                        urlOpener: SystemURLOpener()
                    )
                    .padding(.horizontal, 10)
                }
            }

            if message.creatorType != .user { Spacer(minLength: 40) }
        }
    }
    
    private var hasEvidence: Bool {
        message.hasEvidence
    }

    private var hasClaimsBadge: Bool {
        message.claimsCount > 0 || message.claimsTruncated
    }
}
