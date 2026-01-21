import SwiftUI
import SwiftData
import os
import Foundation
import UIKit
import EventKit
import EventKitUI
import CoreLocation

struct ThreadDetailView: View {
    private static let perfLog = OSLog(subsystem: "com.sollabshq.solmobile", category: "ThreadDetailPerf")
    private static let pendingSlowThresholdSeconds: TimeInterval = 20

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.outboxService) private var outboxService
    @Environment(\.unreadTracker) private var unreadTracker
    @ObservedObject private var budgetStore = BudgetStore.shared
    @Bindable var thread: ConversationThread
    @Query private var messages: [Message]
    @Query private var transmissions: [Transmission]
    @State private var cachedOutboxSummary = OutboxSummary(queued: 0, sending: 0, pending: 0, failed: 0)
    @State private var keyboardSignpostId = OSSignpostID(log: ThreadDetailView.perfLog)
    @State private var keyboardSignpostActive = false
    @State private var autoScrollToLatest: Bool = true
    @State private var initialScrollDone: Bool = false
    @State private var showJumpToLatest: Bool = false
    @State private var showNewMessagesPill: Bool = false
    @State private var newMessagesTargetId: UUID? = nil
    @State private var newMessagesCount: Int? = nil
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var lastVisibleAnchorId: UUID? = nil

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
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                                    .background(GeometryReader { geo in
                                        Color.clear.preference(
                                            key: MessageFramePreferenceKey.self,
                                            value: [msg.id: geo.frame(in: .named("threadScroll"))]
                                        )
                                    })
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                    }
                    .coordinateSpace(name: "threadScroll")
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { scrollViewportHeight = geo.size.height }
                                .onChange(of: geo.size.height) { _, newValue in
                                    scrollViewportHeight = newValue
                                }
                        }
                    )
                    .onPreferenceChange(MessageFramePreferenceKey.self) { frames in
                        updateVisibleAnchor(frames: frames)
                        updateAutoScroll(frames: frames)
                    }
                    .onAppear {
                        applyInitialScroll(proxy: proxy)
                    }
                    .onChange(of: messages.count) { _, _ in
                        applyInitialScroll(proxy: proxy)
                        guard let last = messages.last else { return }
                        if autoScrollToLatest {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        } else {
                            showJumpToLatest = true
                            refreshNewMessagesPill()
                        }
                    }

                    if showNewMessagesPill, let targetId = newMessagesTargetId {
                        Button(newMessagesLabel) {
                            autoScrollToLatest = false
                            showJumpToLatest = true
                            proxy.scrollTo(targetId, anchor: .top)
                        }
                        .font(.footnote)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 6)
                    }

                    if showJumpToLatest {
                        Button("Jump to latest") {
                            guard let last = messages.last else { return }
                            autoScrollToLatest = true
                            showJumpToLatest = false
                            showNewMessagesPill = false
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                        .font(.footnote)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 6)
                    }
                }
            }

            Divider()

            // Outbox banner reflects local Transmission state (queued/sending/failed).
            if let banner = outboxBanner {
                banner
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }

            ComposerView(
                text: $composerText,
                isSendBlocked: budgetStore.isBlockedNow(),
                blockedUntil: budgetStore.state.blockedUntil
            ) { text in
                send(text)
            }
            .padding(10)
        }
        .onChange(of: outboxSummary.failed + outboxSummary.queued + outboxSummary.sending + outboxSummary.pending) { _, newValue in
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
                if let unreadTracker {
                    Task { await unreadTracker.flush(threadId: thread.id) }
                }
            }
        }
        .onAppear {
            loadAcceptedMementoFromDefaults()
            updateOutboxSummary()
            restoreDraftIfNeeded()
            budgetStore.refreshIfExpired()
        }
        .onDisappear {
            if let unreadTracker {
                Task { await unreadTracker.flush(threadId: thread.id) }
            }
        }
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
            .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save to Memory") {
                    triggerMemoryDistill()
                }
            }
        }
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
        outboxService?.enqueueChat(thread: thread, userMessage: m)
    }

    private var draftStore: DraftStore {
        DraftStore(modelContext: modelContext)
    }

    private func triggerMemoryDistill() {
        guard let outboxService else { return }
        let context = buildMemoryContext()
        guard let triggerMessageId = context.last?.messageId else { return }

        let requestId = "mem:thread:\(thread.id.uuidString)"
        let payload = MemoryDistillRequest(
            threadId: thread.id.uuidString,
            triggerMessageId: triggerMessageId,
            contextWindow: context,
            requestId: requestId,
            reaffirmCount: 0
        )

        outboxService.enqueueMemoryDistill(
            threadId: thread.id,
            messageIds: context.compactMap { UUID(uuidString: $0.messageId) },
            payload: payload
        )
    }

    private func buildMemoryContext() -> [MemoryContextItem] {
        let eligible = messages.filter { message in
            !message.isGhostCard
        }

        let window = eligible.suffix(15)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return window.map { message in
            MemoryContextItem(
                messageId: message.id.uuidString,
                role: message.creatorType.rawValue,
                content: message.text,
                createdAt: formatter.string(from: message.createdAt)
            )
        }
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
                        outboxService?.retryFailed()

                        let after = outboxSummary
                        viewLog.info("[retry] after failed=\(after.failed, privacy: .public) queued=\(after.queued, privacy: .public) sending=\(after.sending, privacy: .public)")
                    }
                    .font(.footnote)
                }
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            )
        }

        if s.queued + s.sending + s.pending > 0 {
            let statusText: String
            if hasLongPending {
                statusText = "Still processing… pending \(s.pending), queued \(s.queued), sending \(s.sending)"
            } else {
                statusText = "Outbox: queued \(s.queued), pending \(s.pending), sending \(s.sending)"
            }
            return AnyView(
                HStack(spacing: 10) {
                    ProgressView()
                    Text(statusText)
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
        var pending: Int
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
    let transport = SolServerClient()
    Task {
        let actions = TransmissionActions(modelContext: modelContext, transport: transport)

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
        let transport = SolServerClient()
        Task {
            let actions = TransmissionActions(modelContext: modelContext, transport: transport)
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
            let transport = SolServerClient()
            Task {
                let actions = TransmissionActions(modelContext: modelContext, transport: transport)
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

    private var newMessagesLabel: String {
        guard let count = newMessagesCount, count > 0 else { return "New messages" }
        return "\(count) new message\(count == 1 ? "" : "s")"
    }

    private func updateOutboxSummary() {
        // Derived state from SwiftData query; cache to avoid repeated filters during renders.
        let queued = transmissions.filter { $0.status == .queued }.count
        let sending = transmissions.filter { $0.status == .sending }.count
        let pending = transmissions.filter { $0.status == .pending }.count
        let failed = transmissions.filter { $0.status == .failed }.count
        cachedOutboxSummary = OutboxSummary(queued: queued, sending: sending, pending: pending, failed: failed)
    }

    private func pendingSince(_ tx: Transmission) -> Date? {
        let attempts = tx.deliveryAttempts.sorted { $0.createdAt < $1.createdAt }
        guard let last = attempts.last, last.outcome == .pending else { return nil }

        var since = last.createdAt
        for attempt in attempts.reversed() {
            if attempt.outcome == .pending {
                since = attempt.createdAt
            } else {
                break
            }
        }
        return since
    }

    private var hasLongPending: Bool {
        guard outboxSummary.pending > 0 else { return false }
        let now = Date()
        return transmissions.contains { tx in
            guard tx.status == .pending,
                  let since = pendingSince(tx) else { return false }
            return now.timeIntervalSince(since) >= Self.pendingSlowThresholdSeconds
        }
    }

    private func applyInitialScroll(proxy: ScrollViewProxy) {
        guard !initialScrollDone else { return }
        guard !messages.isEmpty else { return }
        initialScrollDone = true

        if let state = fetchReadState() {
            if let lastViewedId = state.lastViewedMessageId,
               messages.contains(where: { $0.id == lastViewedId }) {
                autoScrollToLatest = false
                showJumpToLatest = true
                proxy.scrollTo(lastViewedId, anchor: .top)
                refreshNewMessagesPill(forceShow: true, state: state)
                return
            }

            if state.lastViewedMessageId != nil,
               let fallbackUnread = computeFirstUnreadMessageId(readUpToId: state.readUpToMessageId) {
                autoScrollToLatest = false
                showJumpToLatest = true
                proxy.scrollTo(fallbackUnread, anchor: .top)
                refreshNewMessagesPill(forceShow: true, state: state)
                return
            }
        }

        if let last = messages.last {
            autoScrollToLatest = true
            showNewMessagesPill = false
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func computeFirstUnreadMessageId(readUpToId: UUID?) -> UUID? {
        guard let readUpToId,
              let idx = messages.firstIndex(where: { $0.id == readUpToId }) else {
            return nil
        }

        let nextIndex = messages.index(after: idx)
        guard nextIndex < messages.endIndex else { return nil }
        return messages[nextIndex].id
    }

    private func fetchReadState() -> ThreadReadState? {
        let threadId = thread.id
        let d = FetchDescriptor<ThreadReadState>(predicate: #Predicate { $0.threadId == threadId })
        return try? modelContext.fetch(d).first
    }

    private func unreadCount(readUpToId: UUID?) -> Int? {
        guard let readUpToId,
              let idx = messages.firstIndex(where: { $0.id == readUpToId }) else {
            return nil
        }

        let nextIndex = messages.index(after: idx)
        guard nextIndex < messages.endIndex else { return nil }
        return messages.distance(from: nextIndex, to: messages.endIndex)
    }

    private func refreshNewMessagesPill(forceShow: Bool = false, state: ThreadReadState? = nil) {
        let readState = state ?? fetchReadState()
        guard let readState,
              let readUpToId = readState.readUpToMessageId,
              let firstUnread = computeFirstUnreadMessageId(readUpToId: readUpToId) else {
            showNewMessagesPill = false
            newMessagesTargetId = nil
            newMessagesCount = nil
            return
        }

        newMessagesTargetId = firstUnread
        newMessagesCount = unreadCount(readUpToId: readUpToId)
        showNewMessagesPill = forceShow || !autoScrollToLatest
    }

    private func updateVisibleAnchor(frames: [UUID: CGRect]) {
        guard scrollViewportHeight > 0 else { return }

        let visible = frames.filter { frame in
            frame.value.maxY >= 0 && frame.value.minY <= scrollViewportHeight
        }

        guard let newest = visible.max(by: { $0.value.maxY < $1.value.maxY })?.key else { return }

        guard newest != lastVisibleAnchorId else { return }
        lastVisibleAnchorId = newest

        if let unreadTracker {
            Task { await unreadTracker.markViewed(threadId: thread.id, messageId: newest) }
        }

        if !autoScrollToLatest {
            refreshNewMessagesPill()
        }
    }

    private func updateAutoScroll(frames: [UUID: CGRect]) {
        guard let last = messages.last,
              let frame = frames[last.id],
              scrollViewportHeight > 0 else { return }

        let isAtBottom = frame.maxY <= scrollViewportHeight + 4
        if isAtBottom {
            if !autoScrollToLatest {
                autoScrollToLatest = true
                showJumpToLatest = false
                showNewMessagesPill = false
            }
        } else if autoScrollToLatest {
            autoScrollToLatest = false
            showJumpToLatest = true
            refreshNewMessagesPill()
        }
    }

}

private struct MessageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct MessageBubble: View {
    let message: Message
    @Environment(\.modelContext) private var modelContext
    @State private var showingClaims = false
    @State private var editorMode: MemoryEditorMode?
    @State private var showDeleteConfirm = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String = ""
    @State private var activeExportSheet: ExportSheet?

    private let eventStore = EKEventStore()

    var body: some View {
        if message.isGhostCard, let ghostCard = buildGhostCardModel() {
            GhostCardComponent(card: ghostCard)
                .sheet(item: $editorMode) { mode in
                    MemoryEditorSheet(mode: mode) { updated in
                        if let updated {
                            upsertMemoryArtifact(from: updated, memoryId: updated.id)
                            message.ghostMemoryId = updated.id
                            message.ghostFactNull = false
                            message.ghostSnippet = updated.snippet ?? message.ghostSnippet
                            message.ghostRigorLevelRaw = updated.rigorLevel ?? message.ghostRigorLevelRaw
                            message.ghostMoodAnchor = updated.moodAnchor ?? message.ghostMoodAnchor
                            try? modelContext.save()
                        }
                    }
                }
                .sheet(item: $activeExportSheet) { sheet in
                    switch sheet {
                    case .reminder(let reminder):
                        ReminderSaveView(reminder: reminder, eventStore: eventStore) { _ in }
                    case .calendar(let event):
                        EventEditView(eventStore: eventStore, event: event) { _ in }
                    }
                }
                .alert("Confirm Delete", isPresented: $showDeleteConfirm) {
                    Button("Delete", role: .destructive) {
                        Task { await performDelete(confirm: true) }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This memory affects safety boundaries. Confirm to delete it.")
                }
                .alert("Action Failed", isPresented: $showErrorAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(errorMessage)
                }
        } else {
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
    }
    
    private var hasEvidence: Bool {
        message.hasEvidence
    }

    private var hasClaimsBadge: Bool {
        message.claimsCount > 0 || message.claimsTruncated
    }

    private enum ExportSheet: Identifiable {
        case reminder(reminder: EKReminder)
        case calendar(event: EKEvent)

        var id: String {
            switch self {
            case .reminder:
                return "reminder"
            case .calendar:
                return "calendar"
            }
        }
    }

    private func buildGhostCardModel() -> GhostCardModel? {
        guard let kind = message.ghostKind else { return nil }
        let cta = message.ghostCTAState

        let onEdit: (() -> Void)?
        if cta.canEdit {
            onEdit = { openEditor() }
        } else {
            onEdit = nil
        }

        let onForget: (() -> Void)?
        if cta.canForget {
            onForget = {
                if cta.requiresConfirm {
                    showDeleteConfirm = true
                } else {
                    Task { await performDelete(confirm: false) }
                }
            }
        } else {
            onForget = nil
        }

        let onAscend: (() async -> Bool)?
        if kind == .journalMoment {
            onAscend = { await donateJournalMoment() }
        } else {
            onAscend = nil
        }

        return GhostCardModel(
            kind: kind,
            title: nil,
            body: nil,
            summary: nil,
            snippet: message.ghostSnippet,
            memoryId: message.ghostMemoryId,
            rigorLevel: message.ghostRigorLevel,
            moodAnchor: message.moodAnchor,
            factNull: message.ghostFactNull,
            captureSuggestion: message.captureSuggestion,
            hapticKey: message.ghostMemoryId ?? message.id.uuidString,
            actions: GhostCardActions(
                onEdit: onEdit,
                onForget: onForget,
                onAscend: onAscend,
                onAddToCalendar: { Task { await presentEventEditor() } },
                onAddToReminder: { Task { await presentReminderEditor() } },
                onGoToThread: nil
            )
        )
    }

    private func openEditor() {
        if let memoryId = message.ghostMemoryId {
            editorMode = .edit(
                memoryId: memoryId,
                initialText: message.ghostSnippet ?? ""
            )
        } else {
            editorMode = .create(
                threadId: message.thread.id.uuidString,
                messageId: message.ghostTriggerMessageId,
                initialText: ""
            )
        }
    }

    private func performDelete(confirm: Bool) async {
        guard let memoryId = message.ghostMemoryId else {
            if message.ghostFactNull {
                return
            }
            deleteLocalMessage()
            return
        }

        do {
            let client = SolServerClient()
            try await client.deleteMemory(memoryId: memoryId, confirm: confirm ? true : nil)
            deleteLocalMessage()
            deleteMemoryArtifact(memoryId: memoryId)
        } catch {
            errorMessage = "Unable to delete memory."
            showErrorAlert = true
        }
    }

    private func deleteLocalMessage() {
        modelContext.delete(message)
        try? modelContext.save()
    }

    private func deleteMemoryArtifact(memoryId: String) {
        let descriptor = FetchDescriptor<MemoryArtifact>(predicate: #Predicate { $0.memoryId == memoryId })
        if let artifact = try? modelContext.fetch(descriptor).first {
            modelContext.delete(artifact)
            try? modelContext.save()
        }
    }

    private func upsertMemoryArtifact(from dto: MemoryItemDTO, memoryId: String) {
        let descriptor = FetchDescriptor<MemoryArtifact>(predicate: #Predicate { $0.memoryId == memoryId })
        let existing = (try? modelContext.fetch(descriptor))?.first

        if let existing {
            existing.threadId = dto.threadId
            existing.triggerMessageId = dto.triggerMessageId
            existing.typeRaw = dto.type ?? existing.typeRaw
            existing.snippet = dto.snippet ?? existing.snippet
            existing.moodAnchor = dto.moodAnchor ?? existing.moodAnchor
            existing.rigorLevelRaw = dto.rigorLevel ?? existing.rigorLevelRaw
            existing.tagsCsv = dto.tags?.joined(separator: ",") ?? existing.tagsCsv
            existing.fidelityRaw = dto.fidelity ?? existing.fidelityRaw
            existing.transitionToHazyAt = dto.transitionToHazyAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            existing.updatedAt = dto.updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
            try? modelContext.save()
            return
        }

        let createdAt = dto.createdAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        let artifact = MemoryArtifact(
            memoryId: memoryId,
            threadId: dto.threadId,
            triggerMessageId: dto.triggerMessageId,
            typeRaw: dto.type ?? "memory",
            snippet: dto.snippet,
            moodAnchor: dto.moodAnchor,
            rigorLevelRaw: dto.rigorLevel,
            tagsCsv: dto.tags?.joined(separator: ","),
            fidelityRaw: dto.fidelity,
            transitionToHazyAt: dto.transitionToHazyAt.flatMap { ISO8601DateFormatter().date(from: $0) },
            createdAt: createdAt,
            updatedAt: createdAt
        )
        modelContext.insert(artifact)
        try? modelContext.save()
    }

    private func donateJournalMoment() async -> Bool {
        guard let summary = message.ghostSnippet, !summary.isEmpty else { return false }
        let memoryId = message.ghostMemoryId
        let location = memoryId.flatMap { lookupMemoryLocation(memoryId: $0) }

        let moodLabel = message.ghostMoodAnchor
        let success = await JournalDonationService.shared.donateMoment(
            summaryText: summary,
            location: location,
            moodAnchor: moodLabel
        )

        if success, let memoryId {
            markAscended(memoryId: memoryId)
            recordJournalCapture(memoryId: memoryId, location: location, moodAnchor: moodLabel)
        }

        return success
    }

    private func lookupMemoryLocation(memoryId: String) -> CLLocationCoordinate2D? {
        let descriptor = FetchDescriptor<MemoryArtifact>(predicate: #Predicate { $0.memoryId == memoryId })
        guard let artifact = try? modelContext.fetch(descriptor).first else { return nil }
        guard let lat = artifact.locationLatitude, let lon = artifact.locationLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func markAscended(memoryId: String) {
        let descriptor = FetchDescriptor<MemoryArtifact>(predicate: #Predicate { $0.memoryId == memoryId })
        if let artifact = try? modelContext.fetch(descriptor).first {
            artifact.ascendedAt = Date()
            try? modelContext.save()
        }
    }

    private func recordJournalCapture(
        memoryId: String,
        location: CLLocationCoordinate2D?,
        moodAnchor: String?
    ) {
        let suggestionId = "journal_\(memoryId)"
        let descriptor = FetchDescriptor<CapturedSuggestion>(predicate: #Predicate { $0.suggestionId == suggestionId })
        let existing = (try? modelContext.fetch(descriptor))?.first

        if let existing {
            existing.capturedAt = Date()
            existing.destination = "journal"
            existing.locationLatitude = location?.latitude
            existing.locationLongitude = location?.longitude
            existing.sentimentLabel = moodAnchor
            try? modelContext.save()
            return
        }

        let record = CapturedSuggestion(
            suggestionId: suggestionId,
            capturedAt: Date(),
            destination: "journal",
            messageId: message.id,
            locationLatitude: location?.latitude,
            locationLongitude: location?.longitude,
            sentimentLabel: moodAnchor
        )
        modelContext.insert(record)
        try? modelContext.save()
    }

    @MainActor
    private func presentReminderEditor() async {
        guard let suggestion = message.captureSuggestion else { return }
        guard await requestReminderAccess() else { return }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = suggestion.title
        reminder.notes = suggestion.body
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        if let alarmDate = parseSuggestedDate(suggestion.suggestedDate) {
            reminder.addAlarm(EKAlarm(absoluteDate: alarmDate))
        }

        activeExportSheet = .reminder(reminder: reminder)
    }

    @MainActor
    private func presentEventEditor() async {
        guard let suggestion = message.captureSuggestion else { return }
        guard let startDate = parseSuggestedStartAt(suggestion.suggestedStartAt) else { return }

        guard await requestEventAccess() else { return }

        let event = EKEvent(eventStore: eventStore)
        event.title = suggestion.title
        event.notes = suggestion.body
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(3600)

        activeExportSheet = .calendar(event: event)
    }

    @MainActor
    private func requestEventAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestWriteOnlyAccessToEvents()
            } catch {
                errorMessage = "Calendar access failed."
                showErrorAlert = true
                return false
            }
        }
        errorMessage = "Calendar access is unavailable on this iOS version."
        showErrorAlert = true
        return false
    }

    @MainActor
    private func requestReminderAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToReminders()
            } catch {
                errorMessage = "Reminders access failed."
                showErrorAlert = true
                return false
            }
        }
        errorMessage = "Reminders access is unavailable on this iOS version."
        showErrorAlert = true
        return false
    }

    private func parseSuggestedDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)
    }

    private func parseSuggestedStartAt(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let date = Self.iso8601WithFractional.date(from: raw) {
            return date
        }
        return Self.iso8601Basic.date(from: raw)
    }

    private static let iso8601Basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

}
