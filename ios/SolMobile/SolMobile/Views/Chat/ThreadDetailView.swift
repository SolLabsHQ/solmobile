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
    private static let keyboardDismissThreshold: CGFloat = 32

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.outboxService) private var outboxService
    @Environment(\.unreadTracker) private var unreadTracker
    @AppStorage(ThreadContextSettings.modeKey) private var threadContextMode: String = ThreadContextSettings.Mode.auto.rawValue
    @AppStorage(ThreadContextSettings.showKey) private var showThreadContext: Bool = false
    @ObservedObject private var budgetStore = BudgetStore.shared
    @ObservedObject private var sseStatus = SSEStatusStore.shared
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
    @State private var composerHeight: CGFloat = 0
    @State private var outboxBannerHeight: CGFloat = 0
    @State private var starlightState: StarlightState = .idle
    @State private var starlightPendingSince: Date? = nil
    @State private var starlightFlashTask: Task<Void, Never>? = nil
    @State private var lastAssistantMessageId: UUID? = nil
    @State private var seededAssistantArrival: Bool = false

    private enum GhostOverlayMode: Equatable {
        case full
        case hidden
    }

    @State private var ghostOverlayMode: GhostOverlayMode = .full
    @State private var ghostSnoozeTask: Task<Void, Never>? = nil
    @State private var ghostHandleAscendTrigger: Bool = false
    @State private var showRecoveryPill: Bool = false
    @State private var recoveryPillTask: Task<Void, Never>? = nil

    // ThreadMemento (navigation artifact): server-proposed snapshot (draft or latest thread context).
    // We store acceptance state locally (UserDefaults) so it survives view reloads.
    @State private var acceptedMemento: MementoViewModel? = nil
    @State private var mementoRefreshToken: Int = 0

    // Transient toast for lightweight feedback (Accept/Decline/Undo).
    @State private var toastMessage: String? = nil
    @State private var toastToken: Int = 0
    @State private var threadContextDismissed: Bool = false

    // Memory accept receipt (View + Undo).
    @State private var memoryReceipt: MemoryReceipt? = nil
    @State private var activeMemoryDetail: MemoryDetailRoute? = nil

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

    // Messages excluding ghosts for scrollable display.
    private var displayMessages: [Message] {
        messages.filter { !$0.isGhostCard }
    }

    // Most recent ghost message for overlay.
    private var latestGhostMessage: Message? {
        // Show the most recent ghost card as an overlay (does not participate in List/VStack layout).
        messages.last(where: { $0.isGhostCard })
    }

    private var latestAssistantMessageId: UUID? {
        messages.last(where: { $0.creatorType == .assistant && !$0.isGhostCard })?.id
    }

    private func isGhostSaved(_ ghost: Message) -> Bool {
        guard ghost.ghostFactNull == false else { return false }
        return ghost.ghostMemoryId?.isEmpty == false
    }

    private func isGhostManualEntry(_ ghost: Message) -> Bool {
        ghost.ghostFactNull
    }

    private func isGhostPending(_ ghost: Message) -> Bool {
        ghost.ghostFactNull == false && ghost.ghostMemoryId?.isEmpty != false
    }

    private func receiptWindowSeconds(for ghost: Message) -> TimeInterval {
        ghost.ghostRigorLevelRaw == "high" ? 5 : 3
    }

    private func ghostSnoozeKey(for ghost: Message) -> String {
        // Retrigger snooze when the ghost updates in place (placeholder -> real memory).
        let mem = ghost.ghostMemoryId ?? "nil"
        let factNull = ghost.ghostFactNull ? "1" : "0"
        let rigor = ghost.ghostRigorLevelRaw ?? ""
        return "\(ghost.id.uuidString)|\(mem)|\(factNull)|\(rigor)"
    }

    private func preferredOverlayMode(for ghost: Message, isTyping: Bool) -> GhostOverlayMode {
        if isGhostManualEntry(ghost) && isTyping {
            return .hidden
        }
        return .full
    }

    private func scheduleGhostAutoSnooze(_ ghost: Message) {
        ghostSnoozeTask?.cancel()

        guard isGhostSaved(ghost) else { return }

        let delay = receiptWindowSeconds(for: ghost)
        ghostSnoozeTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if latestGhostMessage?.id == ghost.id {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        ghostOverlayMode = .hidden
                    }
                }
            }
        }
    }

    private func dismissGhostOverlay(_ ghost: Message) {
        withAnimation(.easeInOut(duration: 0.2)) {
            ghostOverlayMode = .hidden
        }
        presentRecoveryPill(for: ghost)
    }

    private func presentRecoveryPill(for ghost: Message) {
        recoveryPillTask?.cancel()
        showRecoveryPill = true
        let duration = ghost.ghostRigorLevelRaw == "high" ? 5.0 : 3.0
        recoveryPillTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            showRecoveryPill = false
        }
    }

    private func restoreGhostOverlay() {
        recoveryPillTask?.cancel()
        showRecoveryPill = false
        withAnimation(.easeInOut(duration: 0.15)) {
            ghostOverlayMode = .full
        }
        if let ghost = latestGhostMessage {
            scheduleGhostAutoSnooze(ghost)
        }
    }

    @ViewBuilder
    private var ghostOverlay: some View {
        if let ghost = latestGhostMessage, ghostOverlayMode == .full {
            MuseOverlayHost(
                canAscend: ghost.isAscendEligible && JournalDonationService.isJournalAvailable,
                onDismiss: { dismissGhostOverlay(ghost) },
                onAscend: { ghostHandleAscendTrigger = true }
            ) {
                MessageBubble(
                    message: ghost,
                    scrollViewportHeight: scrollViewportHeight,
                    handleAscendTrigger: $ghostHandleAscendTrigger,
                    onMemoryOfferAccept: { memoryId in
                        acceptMemoryOffer(memoryId: memoryId)
                    }
                )
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .animation(.easeIn(duration: 1.2), value: ghost.id)
            .task(id: ghostSnoozeKey(for: ghost)) {
                await MainActor.run {
                    let typing = !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let mode = preferredOverlayMode(for: ghost, isTyping: typing)
                    ghostOverlayMode = mode
                    if mode == .hidden, isGhostManualEntry(ghost), typing {
                        presentRecoveryPill(for: ghost)
                    }
                    scheduleGhostAutoSnooze(ghost)
                }
            }
        }
    }

    @ViewBuilder
    private var recoveryPillOverlay: some View {
        if showRecoveryPill {
            RecoveryPillView {
                restoreGhostOverlay()
            }
            .padding(.leading, 12)
            .padding(.bottom, composerHeight + outboxBannerHeight + 12)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var mainStack: some View {
        VStack(spacing: 0) {

        // Accepted ThreadMemento (navigation snapshot).
        if let acceptedMemento {
            mementoAcceptedCard(acceptedMemento)
                .padding(.horizontal, 10)
                .padding(.top, 8)
        }

        if let receipt = memoryReceipt {
            memoryReceiptCard(receipt)
                .padding(.horizontal, 10)
                .padding(.top, 8)
        }

        // Thread context or pending ThreadMemento draft from latest server response.
        if let pending = pendingMementoCandidate {
            Group {
                if pending.kind == .latest {
                    mementoContextCard(pending)
                } else {
                    mementoPendingCard(pending)
                }
            }
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
                        ForEach(displayMessages) { msg in
                            MessageBubble(
                                message: msg,
                                scrollViewportHeight: scrollViewportHeight,
                                onMemoryOfferAccept: { memoryId in
                                    acceptMemoryOffer(memoryId: memoryId)
                                }
                            )
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
                .scrollDismissesKeyboard(.never)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onEnded { value in
                            let dy = value.translation.height
                            let dx = value.translation.width
                            guard dy > Self.keyboardDismissThreshold, abs(dy) > abs(dx) else { return }
                            KeyboardDismiss.dismiss()
                        }
                )
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
                    guard let last = displayMessages.last else { return }
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
                        guard let last = displayMessages.last else { return }
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
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { outboxBannerHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, newValue in
                                outboxBannerHeight = newValue
                            }
                    }
                )
        }

        ComposerView(
            text: $composerText,
            starlightState: starlightState,
            isSendBlocked: budgetStore.isBlockedNow(),
            blockedUntil: budgetStore.state.blockedUntil
        ) { text in
            send(text)
        }
        .padding(10)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { composerHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, newValue in
                        composerHeight = newValue
                    }
            }
        )
        }

    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mainStack
            ghostOverlay
            recoveryPillOverlay
        }
        .onChange(of: outboxSummary.failed + outboxSummary.queued + outboxSummary.sending + outboxSummary.pending) { _, newValue in
            viewLog.debug("[outboxBanner] refresh total=\(newValue, privacy: .public)")
        }
        .onChange(of: outboxStatusSignature) { _, _ in
            updateOutboxSummary()
            refreshStarlightPending()
        }
        .onChange(of: sseStatus.isWorking) { _, _ in
            refreshStarlightFromSSE()
        }
        .onChange(of: sseStatus.workingTimedOut) { _, timedOut in
            if timedOut {
                starlightState = .idle
                starlightPendingSince = nil
            }
        }
        .onChange(of: latestAssistantMessageId) { _, newId in
            guard seededAssistantArrival else {
                seededAssistantArrival = true
                lastAssistantMessageId = newId
                return
            }
            if let newId, newId != lastAssistantMessageId {
                handleAssistantArrival()
            }
            lastAssistantMessageId = newId
        }
        .onChange(of: latestGhostMessage?.id) { _, newId in
            ghostSnoozeTask?.cancel()
            ghostHandleAscendTrigger = false
            recoveryPillTask?.cancel()
            showRecoveryPill = false
            guard let ghost = latestGhostMessage, newId != nil else {
                ghostOverlayMode = .full
                return
            }
            let typing = !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let mode = preferredOverlayMode(for: ghost, isTyping: typing)
            ghostOverlayMode = mode
            if mode == .hidden, isGhostManualEntry(ghost), typing {
                presentRecoveryPill(for: ghost)
            }
            scheduleGhostAutoSnooze(ghost)
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
            // If the user starts typing, snooze the overlay so it doesn't feel like it blocks the flow.
            let typing = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if typing, let ghost = latestGhostMessage, ghostOverlayMode == .full {
                if isGhostManualEntry(ghost) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        ghostOverlayMode = .hidden
                    }
                    presentRecoveryPill(for: ghost)
                }
            }
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
            refreshStarlightPending()
            lastAssistantMessageId = latestAssistantMessageId
            seededAssistantArrival = true
            restoreDraftIfNeeded()
            budgetStore.refreshIfExpired()
        }
        .onDisappear {
            ghostSnoozeTask?.cancel()
            recoveryPillTask?.cancel()
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
                .accessibilityIdentifier("save_to_memory_button")
            }
        }
        .onChange(of: showThreadContext) { _, newValue in
            if newValue {
                threadContextDismissed = false
            }
        }
        .onChange(of: thread.id) { _, _ in
            threadContextDismissed = false
        }
        .sheet(item: $activeMemoryDetail) { route in
            MemoryCitationDetailSheet(memoryId: route.id)
        }
    }

    private func send(_ text: String) {
        draftStore.forceSaveNow(threadId: thread.id, content: text)
        guard let resolvedThread = resolveThreadForSend() else {
            showToast("Thread not ready. Try again.")
            viewLog.error("[send] thread_missing thread=\(thread.id.uuidString.prefix(8), privacy: .public)")
            return
        }
        pendingSendClear = true
        composerText = ""

        let m = Message(thread: resolvedThread, creatorType: .user, text: text)
        guard DebugModelValidators.threadOrNil(m) != nil else {
            showToast("Thread not ready. Try again.")
            viewLog.error("[send] thread_nil_guard thread=\(resolvedThread.id.uuidString.prefix(8), privacy: .public) msg=\(m.id.uuidString.prefix(8), privacy: .public)")
            return
        }
        DebugModelValidators.assertMessageHasThread(m, context: "ThreadDetailView.send.beforeInsert")
        resolvedThread.messages.append(m)
        resolvedThread.lastActiveAt = Date()
        modelContext.insert(m)

        viewLog.info("[send] thread=\(thread.id.uuidString.prefix(8), privacy: .public) msg=\(m.id.uuidString.prefix(8), privacy: .public) len=\(text.count, privacy: .public)")
        outboxService?.enqueueChat(thread: resolvedThread, userMessage: m)
    }

    private func resolveThreadForSend() -> ConversationThread? {
        let threadId = thread.id
        let d = FetchDescriptor<ConversationThread>(
            predicate: #Predicate<ConversationThread> { $0.id == threadId }
        )
        if let resolved = try? modelContext.fetch(d).first {
            return resolved
        }
        return nil
    }

    private var draftStore: DraftStore {
        DraftStore(modelContext: modelContext)
    }

    private func triggerMemoryDistill() {
        guard let anchorMessageId = resolveMemoryAnchorMessageId() else {
            showToast("Message not synced yet.")
            return
        }

        let requestId = "mem:thread:\(thread.id.uuidString):\(anchorMessageId)"
        let payload = MemorySpanSaveRequest(
            requestId: requestId,
            threadId: thread.id.uuidString,
            anchorMessageId: anchorMessageId,
            window: nil,
            memoryKind: nil,
            tags: nil,
            consent: MemoryConsent(explicitUserConsent: true)
        )

        Task {
            do {
                let response = try await SolServerClient().saveMemorySpan(request: payload)
                if let memory = response.memory {
                    await MainActor.run {
                        upsertMemoryArtifact(from: memory, memoryId: memory.id)
                        presentMemoryReceipt(memoryId: memory.id)
                    }
                } else {
                    showToast("Memory saved")
                }
            } catch {
                showToast("Unable to save memory.")
            }
        }
    }

    private func resolveMemoryAnchorMessageId() -> String? {
        let eligible = messages.filter { !$0.isGhostCard }
        return eligible.last { $0.resolvedServerMessageId != nil }?.resolvedServerMessageId
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

    private var latestSSEStage: SSEStatusStore.TransmissionStage? {
        sseStatus.latestStage(forThreadId: thread.id.uuidString)
    }

    private var sseFailureDetail: SSEStatusStore.FailureDetail? {
        sseStatus.failureDetail(forThreadId: thread.id.uuidString)
    }

    private var outboxBanner: AnyView? {
        let s = outboxSummary

        if let failure = sseFailureDetail,
           latestSSEStage?.kind == .assistantFailed {
            let detail = failure.detail ?? "Request failed."
            let codeSuffix = failure.code.map { " (\($0))" } ?? ""
            return AnyView(
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("\(detail)\(codeSuffix)")
                        .font(.footnote)
                    Spacer()
                    if failure.retryable == true {
                        Button("Retry") {
                            viewLog.info("[retry] sse failure retry tapped")
                            outboxService?.retryFailed()
                        }
                        .font(.footnote)
                    }
                }
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            )
        }

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

        if sseStatus.syncPending {
            return AnyView(
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sync pending — reconnecting…")
                        .font(.footnote)
                    Spacer()
                }
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            )
        }

        if s.queued + s.sending + s.pending > 0 {
            let statusText: String
            if let stage = latestSSEStage, stage.kind == .runStarted {
                statusText = "Thinking…"
            } else if let stage = latestSSEStage, stage.kind == .txAccepted {
                statusText = "Sent/Queued…"
            } else if s.sending > 0 {
                statusText = "Sending…"
            } else if hasLongPending {
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

    private static let mementoLatestPrefix = "memento_latest_"

    private enum MementoKind: Equatable {
        case latest
        case draft
    }

    private struct MementoViewModel: Equatable {
        let id: String
        let summary: String
        let createdAtISO: String?
        let kind: MementoKind
    }

    private struct MemoryReceipt: Identifiable, Equatable {
        let id = UUID()
        let memoryId: String
    }

    private struct MemoryDetailRoute: Identifiable, Equatable {
        let id: String
    }

    fileprivate struct MemoryCitationDetailSheet: View {
        @Environment(\.modelContext) private var modelContext
        let memoryId: String
        @State private var memory: MemoryArtifact?

        var body: some View {
            NavigationStack {
                if let memory {
                    MemoryDetailView(memory: memory)
                } else {
                    VStack(spacing: 12) {
                        Text("Memory not found")
                            .font(.headline)
                        Text(memoryId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding()
                }
            }
            .task(id: memoryId) {
                await fetchMemoryIfNeeded()
            }
        }

        private func fetchMemoryIfNeeded() async {
            let descriptor = FetchDescriptor<MemoryArtifact>(
                predicate: #Predicate { $0.memoryId == memoryId }
            )
            if let cached = (try? modelContext.fetch(descriptor))?.first {
                memory = cached
                return
            }

            do {
                let response = try await SolServerClient().getMemory(memoryId: memoryId)
                if let dto = response.memory {
                    await MainActor.run {
                        upsertMemoryArtifact(from: dto)
                        memory = (try? modelContext.fetch(descriptor))?.first
                    }
                }
            } catch {
                // keep placeholder if fetch fails
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
                try? modelContext.save()
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
            try? modelContext.save()
        }
    }

    fileprivate struct MemoryCitationsSheet: View {
        @Environment(\.modelContext) private var modelContext
        let memoryIds: [String]

        var body: some View {
            NavigationStack {
                List {
                    ForEach(memoryIds, id: \.self) { memoryId in
                        NavigationLink {
                            MemoryCitationDetailSheet(memoryId: memoryId)
                        } label: {
                            if let memory = resolveMemory(memoryId) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(memory.snippet ?? "(no snippet)")
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    Text(memoryId)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(memoryId)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    Text("Tap to fetch")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Memory References")
            }
        }

        private func resolveMemory(_ memoryId: String) -> MemoryArtifact? {
            let descriptor = FetchDescriptor<MemoryArtifact>(
                predicate: #Predicate { $0.memoryId == memoryId }
            )
            return (try? modelContext.fetch(descriptor))?.first
        }
    }

    private var resolvedThreadContextMode: ThreadContextSettings.Mode {
        ThreadContextSettings.normalized(threadContextMode)
    }

    private var isThreadContextEnabled: Bool {
        resolvedThreadContextMode == .auto
    }

    private var shouldShowThreadContext: Bool {
        isThreadContextEnabled && showThreadContext && !threadContextDismissed
    }

    private func isThreadContextMementoId(_ id: String) -> Bool {
        id.hasPrefix(Self.mementoLatestPrefix)
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

    private func mementoContextCard(_ m: MementoViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                Text("Thread context (debug)")
                    .font(.footnote)
                Spacer()
            }

            Text(m.summary)
                .font(.footnote)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .gesture(
            DragGesture()
                .onEnded { value in
                    guard value.translation.height < -60 else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        threadContextDismissed = true
                    }
                }
        )
    }

    private func loadAcceptedMementoFromDefaults() {
        guard let raw = UserDefaults.standard.dictionary(forKey: mementoDefaultsKeyCurrent) else {
            acceptedMemento = nil
            return
        }

        let id = raw["id"] as? String ?? ""
        let summary = raw["summary"] as? String ?? ""
        let createdAtISO = raw["createdAtISO"] as? String

        if !id.isEmpty, !summary.isEmpty, !isThreadContextMementoId(id) {
            acceptedMemento = MementoViewModel(id: id, summary: summary, createdAtISO: createdAtISO, kind: .draft)
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

    private func memoryReceiptCard(_ receipt: MemoryReceipt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Memory saved")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Undo") {
                    undoMemoryAccept(memoryId: receipt.memoryId)
                }
                .font(.footnote)
            }

            HStack(spacing: 12) {
                Button("View") {
                    activeMemoryDetail = MemoryDetailRoute(id: receipt.memoryId)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func presentMemoryReceipt(memoryId: String) {
        markMemoryAccepted(memoryId: memoryId)
        memoryReceipt = MemoryReceipt(memoryId: memoryId)
    }

    private func acceptMemoryOffer(memoryId: String) {
        Task {
            await fetchMemoryDetailIfNeeded(memoryId: memoryId)
            await MainActor.run {
                presentMemoryReceipt(memoryId: memoryId)
                showToast("Accepted")
            }
        }
    }

    private func undoMemoryAccept(memoryId: String) {
        Task {
            do {
                let client = SolServerClient()
                try await client.deleteMemory(memoryId: memoryId, confirm: true)
                await MainActor.run {
                    deleteMemoryArtifact(memoryId: memoryId)
                    memoryReceipt = nil
                    showToast("Undone")
                }
            } catch {
                showToast("Undo failed")
            }
        }
    }

    private func markMemoryAccepted(memoryId: String) {
        let descriptor = FetchDescriptor<MemoryArtifact>(predicate: #Predicate { $0.memoryId == memoryId })
        if let artifact = try? modelContext.fetch(descriptor).first {
            artifact.acceptedAt = Date()
            try? modelContext.save()
        }
    }

    private func fetchMemoryDetailIfNeeded(memoryId: String) async {
        let descriptor = FetchDescriptor<MemoryArtifact>(predicate: #Predicate { $0.memoryId == memoryId })
        if (try? modelContext.fetch(descriptor).first) != nil {
            return
        }
        do {
            let response = try await SolServerClient().getMemory(memoryId: memoryId)
            if let memory = response.memory {
                await MainActor.run {
                    upsertMemoryArtifact(from: memory, memoryId: memory.id)
                }
            }
        } catch {
            showToast("Unable to load memory.")
        }
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
            updatedAt: createdAt
        )
        modelContext.insert(artifact)
        try? modelContext.save()
    }

    private func acceptMemento(_ m: MementoViewModel) {
        guard !isThreadContextMementoId(m.id) else {
            viewLog.info("[memento] accept blocked for thread context id=\(m.id, privacy: .public)")
            return
        }
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
        Task { @MainActor in
            let actions = TransmissionActions(modelContext: modelContext, transport: transport)

            do {
                let result = try await actions.decideThreadMemento(
                    threadId: thread.id,
                    mementoId: m.id,
                    decision: .accept
                )

                // Server may return a different id for the accepted artifact.
                if let applied = result.memento, result.applied {
                    let patched = MementoViewModel(id: applied.id, summary: m.summary, createdAtISO: applied.createdAt, kind: .draft)

                    UserDefaults.standard.set(
                        ["id": patched.id, "summary": patched.summary, "createdAtISO": patched.createdAtISO as Any],
                        forKey: mementoDefaultsKeyCurrent
                    )

                    acceptedMemento = patched
                    showToast("Accepted")

                    viewLog.info("[memento] accept applied serverId=\(applied.id, privacy: .public)")
                } else if result.reason == "already_accepted" {
                    showToast("Already accepted")
                    viewLog.info("[memento] accept already_accepted")
                } else {
                    showToast("Accept not applied")
                    viewLog.info("[memento] accept not_applied reason=\(result.reason ?? "-", privacy: .public)")
                }
            } catch {
                showToast("Accept failed")
                viewLog.error("[memento] accept failed err=\(String(describing: error), privacy: .public)")
            }

            mementoRefreshToken &+= 1
        }
    }

    private func declineMemento(_ m: MementoViewModel) {
        guard !isThreadContextMementoId(m.id) else {
            viewLog.info("[memento] decline blocked for thread context id=\(m.id, privacy: .public)")
            return
        }
        // Decline only dismisses this draft id. It does not change the accepted memento.
        UserDefaults.standard.set(m.id, forKey: mementoDefaultsKeyDismissed)

        // Submit to SolServer and clear the local draft fields so the banner disappears immediately.
        let transport = SolServerClient()
        Task { @MainActor in
            let actions = TransmissionActions(modelContext: modelContext, transport: transport)
            do {
                let result = try await actions.decideThreadMemento(threadId: thread.id, mementoId: m.id, decision: .decline)

                showToast(result.applied ? "Declined" : "Decline saved")
                // Force re-evaluation (UserDefaults is not observed).
                mementoRefreshToken &+= 1
            } catch {
                showToast("Decline failed")
                // Force re-evaluation (UserDefaults is not observed).
                mementoRefreshToken &+= 1

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
            guard !isThreadContextMementoId(id) else {
                viewLog.info("[memento] undo blocked for thread context id=\(id, privacy: .public)")
                return
            }

            // Submit to SolServer and clear the local draft fields so the banner disappears immediately.
            let transport = SolServerClient()
            Task { @MainActor in
                let actions = TransmissionActions(modelContext: modelContext, transport: transport)
                do {
                    let result = try await actions.decideThreadMemento(threadId: thread.id, mementoId: id, decision: .revoke)

                    showToast(result.applied ? "Undone" : "Undo saved")
                    // Force re-evaluation (UserDefaults is not observed).
                    mementoRefreshToken &+= 1
                } catch {
                    showToast("Undo failed")
                    // Force re-evaluation (UserDefaults is not observed).
                    mementoRefreshToken &+= 1

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
        // Look at the latest Transmission for this thread and read the server-proposed ThreadMemento
        // that `TransmissionActions` persisted from the SolServer response (draft or latest context).
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

        let kind: MementoKind = isThreadContextMementoId(id) ? .latest : .draft
        let extracted = MementoViewModel(
            id: id,
            summary: summary,
            createdAtISO: latest.serverThreadMementoCreatedAtISO,
            kind: kind
        )

        if extracted.kind == .latest {
            return shouldShowThreadContext ? extracted : nil
        }

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
        if (failed == 0) && (queued + sending + pending == 0) {
            outboxBannerHeight = 0
        }
    }

    private func refreshStarlightPending() {
        guard starlightState != .flash else { return }
        if let pendingSince = pendingChatSince() {
            if starlightState == .idle {
                starlightState = .pending
            }
            if starlightPendingSince == nil || pendingSince < (starlightPendingSince ?? pendingSince) {
                starlightPendingSince = pendingSince
            }
        } else if starlightState == .pending {
            starlightState = .idle
            starlightPendingSince = nil
        }
    }

    private func refreshStarlightFromSSE() {
        guard starlightState != .flash else { return }
        if sseStatus.isWorking {
            if starlightState == .idle {
                starlightState = .pending
            }
            if starlightPendingSince == nil {
                starlightPendingSince = Date()
            }
            return
        }
        if pendingChatSince() == nil && starlightState == .pending {
            starlightState = .idle
            starlightPendingSince = nil
        }
    }

    private func handleAssistantArrival() {
        fireArrivalHaptic()
        starlightFlashTask?.cancel()
        starlightState = .flash
        starlightPendingSince = nil
        starlightFlashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            starlightState = .idle
        }
    }

    private func fireArrivalHaptic() {
        guard PhysicalityManager.canFireHaptics() else { return }
        let delta = starlightPendingSince.map { Date().timeIntervalSince($0) } ?? 0
        if delta < 1.2 {
            GhostCardHaptics.softImpact()
            return
        }

        let scaled = min(max((delta - 1.2) / 4.0, 0.0), 1.0)
        let intensity = min(1.2, 1.0 + (0.2 * scaled))
        GhostCardHaptics.heartbeat(intensity: intensity)
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

    private func pendingChatSince() -> Date? {
        transmissions
            .filter { $0.status == .pending && $0.packet.packetType == "chat" }
            .compactMap(pendingSince)
            .min()
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
        guard !displayMessages.isEmpty else { return }
        initialScrollDone = true

        if let state = fetchReadState() {
            if let lastViewedId = state.lastViewedMessageId,
               displayMessages.contains(where: { $0.id == lastViewedId }) {
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

        if let last = displayMessages.last {
            autoScrollToLatest = true
            showNewMessagesPill = false
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func computeFirstUnreadMessageId(readUpToId: UUID?) -> UUID? {
        guard let readUpToId,
              let idx = displayMessages.firstIndex(where: { $0.id == readUpToId }) else {
            return nil
        }

        let nextIndex = displayMessages.index(after: idx)
        guard nextIndex < displayMessages.endIndex else { return nil }
        return displayMessages[nextIndex].id
    }

    private func fetchReadState() -> ThreadReadState? {
        let threadId = thread.id
        let d = FetchDescriptor<ThreadReadState>(predicate: #Predicate { $0.threadId == threadId })
        return try? modelContext.fetch(d).first
    }

    private func unreadCount(readUpToId: UUID?) -> Int? {
        guard let readUpToId,
              let idx = displayMessages.firstIndex(where: { $0.id == readUpToId }) else {
            return nil
        }

        let nextIndex = displayMessages.index(after: idx)
        guard nextIndex < displayMessages.endIndex else { return nil }
        return displayMessages.distance(from: nextIndex, to: displayMessages.endIndex)
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
        guard let last = displayMessages.last,
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

enum JournalPresentationState: Equatable {
    case idle
    case alert(message: String, showShareSheet: Bool)
    case shareSheet

    static func nextStateOnAlertDismiss(_ state: JournalPresentationState) -> JournalPresentationState {
        if case let .alert(_, showShareSheet) = state, showShareSheet {
            return .shareSheet
        }
        return .idle
    }
}

private struct MessageBubble: View {
    let message: Message
    let scrollViewportHeight: CGFloat
    @Binding var handleAscendTrigger: Bool
    let onMemoryOfferAccept: ((String) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @State private var showingClaims = false
    @State private var editorMode: MemoryEditorMode?
    @State private var showDeleteConfirm = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String = ""
    @State private var showMemoryCitations = false
    @State private var activeExportSheet: ExportSheet?
    @State private var activeDraft: JournalDraftEditorPayload?
    @State private var activeDraftOffer: JournalOffer?
    @State private var showOfferTuning = false
    @State private var suppressJournalOffer = false
    @State private var journalPresentation: JournalPresentationState = .idle
    @State private var journalShareItems: [Any] = []
    @State private var journalShareCompletion: ((Bool, String?) -> Void)?
    @State private var journalOfferVisible = false
    @State private var journalOfferGateLogged = false

    private let eventStore = EKEventStore()
    private let log = Logger(subsystem: "com.sollabshq.solmobile", category: "MessageBubble")

    init(
        message: Message,
        scrollViewportHeight: CGFloat,
        handleAscendTrigger: Binding<Bool> = .constant(false),
        onMemoryOfferAccept: ((String) -> Void)? = nil
    ) {
        self.message = message
        self.scrollViewportHeight = scrollViewportHeight
        self._handleAscendTrigger = handleAscendTrigger
        self.onMemoryOfferAccept = onMemoryOfferAccept
    }

    var body: some View {
        if message.isGhostCard, let ghostCard = buildGhostCardModel() {
            GhostCardComponent(card: ghostCard, externalAscendTrigger: $handleAscendTrigger)
                .accessibilityIdentifier("ghost_overlay")
                .accessibilityElement(children: .contain)
                .sheet(item: $editorMode) { mode in
                    MemoryEditorSheet(mode: mode) { updated in
                        if let updated {
                            let previousMemoryId = message.ghostMemoryId
                            upsertMemoryArtifact(from: updated, memoryId: updated.id)
                            message.ghostMemoryId = updated.id
                            message.ghostFactNull = false
                            message.ghostSnippet = updated.snippet ?? message.ghostSnippet
                            message.ghostRigorLevelRaw = updated.rigorLevel ?? message.ghostRigorLevelRaw
                            message.ghostMoodAnchor = updated.moodAnchor ?? message.ghostMoodAnchor
                            GhostCardReceipt.fireCanonizationIfNeeded(
                                modelContext: modelContext,
                                previousMemoryId: previousMemoryId,
                                newMemoryId: message.ghostMemoryId,
                                factNull: message.ghostFactNull,
                                ghostKind: message.ghostKind
                            )
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
                .sheet(isPresented: showJournalShareSheet) {
                    ShareSheetView(activityItems: journalShareItems) { completed, activityType in
                        journalPresentation = .idle
                        let completion = journalShareCompletion
                        journalShareCompletion = nil
                        completion?(completed, activityType)
                    }
                }
                .alert("Journal Export", isPresented: showJournalAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(journalAlertMessage)
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

                    if shouldShowLatticeOfflineBadge {
                        Text("LATTICE_OFFLINE")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                            .padding(.top, 6)
                            .padding(.horizontal, 10)
                    }

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

                    if let offer = visibleJournalOffer {
                        JournalOfferCard(
                            offer: offer,
                            onAssist: { handleOfferAccepted(offer: offer, mode: .assist) },
                            onVerbatim: { handleOfferAccepted(offer: offer, mode: .verbatim) },
                            onDecline: { handleOfferDeclined(offer: offer) },
                            onTune: { showOfferTuning = true }
                        )
                        .padding(.top, 8)
                        .padding(.horizontal, 10)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        updateJournalOfferVisibility(frame: geo.frame(in: .named("threadScroll")), offer: offer)
                                    }
                                    .onChange(of: geo.frame(in: .named("threadScroll"))) { _, newFrame in
                                        updateJournalOfferVisibility(frame: newFrame, offer: offer)
                                    }
                            }
                        )
                        .confirmationDialog("Offer tuning", isPresented: $showOfferTuning, titleVisibility: .visible) {
                            Button("Disable offers", role: .destructive) {
                                handleOfferTuning(
                                    offer: offer,
                                    tuning: JournalOfferEventTuning(newCooldownMinutes: nil, avoidPeakOverwhelm: nil, offersEnabled: false)
                                )
                            }
                            Button("Cooldown 30 minutes") {
                                handleOfferTuning(
                                    offer: offer,
                                    tuning: JournalOfferEventTuning(newCooldownMinutes: 30, avoidPeakOverwhelm: nil, offersEnabled: nil)
                                )
                            }
                            Button("Cooldown 120 minutes") {
                                handleOfferTuning(
                                    offer: offer,
                                    tuning: JournalOfferEventTuning(newCooldownMinutes: 120, avoidPeakOverwhelm: nil, offersEnabled: nil)
                                )
                            }
                            Button("Cancel", role: .cancel) { }
                        }
                    }

                    // Evidence UI (PR #8) - only show for assistant messages with evidence
                    if message.creatorType == .assistant && hasEvidence {
                        EvidenceView(
                            message: message,
                            urlOpener: SystemURLOpener()
                        )
                        .padding(.horizontal, 10)
                    }

                    if message.creatorType == .assistant && !message.latticeMemoryIds.isEmpty {
                        Button {
                            showMemoryCitations = true
                        } label: {
                            Label("Memories (\(message.latticeMemoryIds.count))", systemImage: "brain")
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                    }
                }

                if message.creatorType != .user { Spacer(minLength: 40) }
            }
            .sheet(item: $activeDraft) { payload in
                JournalDraftEditorView(
                    payload: payload,
                    onComplete: { context in
                        handleDraftSaved(context: context, offer: activeDraftOffer, payload: payload)
                    },
                    onCancel: {
                        activeDraft = nil
                        activeDraftOffer = nil
                    }
                )
            }
            .sheet(isPresented: $showMemoryCitations) {
                ThreadDetailView.MemoryCitationsSheet(memoryIds: message.latticeMemoryIds)
            }
            .onAppear {
                logJournalOfferGateIfNeeded()
            }
            .onChange(of: message.journalOfferJson) { _, _ in
                logJournalOfferGateIfNeeded()
            }
        }
    }
    
    private var hasEvidence: Bool {
        message.hasEvidence
    }

    private var shouldShowLatticeOfflineBadge: Bool {
        guard message.creatorType == .assistant else { return false }
        guard message.latticeStatusRaw == "fail" else { return false }
        guard AppEnvironment.current != .prod else { return false }
        return isDevBadgeEnabled
    }

    private var isDevBadgeEnabled: Bool {
        if let raw = Bundle.main.infoDictionary?["LATTICE_DEV_BADGE"] as? String {
            return raw == "1" || raw.lowercased() == "true"
        }
        if let raw = Bundle.main.infoDictionary?["LATTICE_DEV_BADGE"] as? Bool {
            return raw
        }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private var hasClaimsBadge: Bool {
        message.claimsCount > 0 || message.claimsTruncated
    }

    private var visibleJournalOffer: JournalOffer? {
        guard !suppressJournalOffer else { return nil }
        guard message.creatorType == .assistant else { return nil }
        guard let offer = message.journalOffer, offer.offerEligible else { return nil }
        guard JournalStyleSettings.offersEnabled else { return nil }
        guard !JournalStyleSettings.isCooldownActive() else { return nil }
        return offer
    }

    private func logJournalOfferGateIfNeeded() {
        guard !journalOfferGateLogged else { return }
        guard let offer = message.journalOffer else { return }
        journalOfferGateLogged = true
        let cooldownActive = JournalStyleSettings.isCooldownActive()
        log.info(
            "journal_offer_gate msg=\(message.id.uuidString, privacy: .public) eligible=\(offer.offerEligible, privacy: .public) offersEnabled=\(JournalStyleSettings.offersEnabled, privacy: .public) cooldownActive=\(cooldownActive, privacy: .public) suppressed=\(suppressJournalOffer, privacy: .public)"
        )
    }

    private static let traceTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private struct ShareOutcome {
        let completed: Bool
        let destination: String?
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

    private var journalAlertMessage: String {
        if case let .alert(message, _) = journalPresentation {
            return message
        }
        return ""
    }

    private var showJournalAlert: Binding<Bool> {
        Binding(
            get: {
                if case .alert = journalPresentation {
                    return true
                }
                return false
            },
            set: { newValue in
                guard !newValue else { return }
                journalPresentation = JournalPresentationState.nextStateOnAlertDismiss(journalPresentation)
            }
        )
    }

    private var showJournalShareSheet: Binding<Bool> {
        Binding(
            get: {
                if case .shareSheet = journalPresentation {
                    return true
                }
                return false
            },
            set: { newValue in
                if !newValue {
                    journalPresentation = .idle
                }
            }
        )
    }

    private func handleOfferShownIfNeeded(offer: JournalOffer) {
        guard message.journalOfferShownAt == nil else { return }
        message.journalOfferShownAt = Date()
        JournalStyleSettings.markOfferShown()
        try? modelContext.save()

        let event = makeJournalOfferEvent(
            type: .journalOfferShown,
            offer: offer,
            cooldownActive: false
        )
        postTraceEvent(.journalOffer(event))
    }

    private func updateJournalOfferVisibility(frame: CGRect, offer: JournalOffer) {
        guard !journalOfferVisible else { return }
        let viewportHeight = scrollViewportHeight
        guard viewportHeight > 0 else { return }
        guard frame.maxY > 0, frame.minY < viewportHeight else { return }
        journalOfferVisible = true
        handleOfferShownIfNeeded(offer: offer)
    }

    private func handleOfferAccepted(offer: JournalOffer, mode: JournalDraftMode) {
        handleOfferShownIfNeeded(offer: offer)
        suppressJournalOffer = true

        let action: JournalOfferUserAction = (mode == .assist) ? .edit : .save
        let accepted = makeJournalOfferEvent(
            type: .journalOfferAccepted,
            offer: offer,
            modeSelected: mode,
            userAction: action,
            cooldownActive: JournalStyleSettings.isCooldownActive()
        )
        postTraceEvent(.journalOffer(accepted))

        switch mode {
        case .assist:
            let requestId = UUID().uuidString
            let cpbId = JournalStyleSettings.cpbId
            let cpbRefs = cpbId.map { [JournalDraftCpbRef(cpbId: $0, type: .journalStyle)] }
            let request = JournalDraftRequest(
                requestId: requestId,
                threadId: message.thread.id.uuidString,
                mode: .assist,
                evidenceSpan: offer.evidenceSpan,
                cpbRefs: cpbRefs,
                preferences: JournalDraftPreferences(
                    maxLines: JournalStyleSettings.maxLinesDefault,
                    includeTagsSuggested: true
                )
            )

            let startNs = DispatchTime.now().uptimeNanoseconds
            Task {
                do {
                    let draft = try await SolServerClient().createJournalDraft(request: request)
                    let elapsedMs = Int(Double(DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000.0)
                    let refs = JournalOfferEventRefs(
                        cpbId: cpbId,
                        draftId: draft.draftId,
                        entryId: nil,
                        requestId: requestId
                    )
                    let generated = makeJournalOfferEvent(
                        type: .journalDraftGenerated,
                        offer: offer,
                        modeSelected: .assist,
                        latencyMs: elapsedMs,
                        refs: refs
                    )
                    postTraceEvent(.journalOffer(generated))

                    let payload = JournalDraftEditorPayload(
                        id: draft.draftId,
                        mode: draft.mode,
                        title: draft.title,
                        body: draft.body,
                        tagsSuggested: draft.tagsSuggested ?? [],
                        evidenceSpan: offer.evidenceSpan,
                        draftId: draft.draftId,
                        requestId: requestId
                    )
                    await MainActor.run {
                        activeDraftOffer = offer
                        activeDraft = payload
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Unable to create journal draft."
                        showErrorAlert = true
                        suppressJournalOffer = false
                    }
                }
            }
        case .verbatim:
            Task {
                await handleVerbatimShare(offer: offer)
            }
        }
    }

    private func handleOfferDeclined(offer: JournalOffer) {
        handleOfferShownIfNeeded(offer: offer)
        suppressJournalOffer = true
        let declined = makeJournalOfferEvent(
            type: .journalOfferDeclined,
            offer: offer,
            userAction: .notNow,
            cooldownActive: JournalStyleSettings.isCooldownActive()
        )
        postTraceEvent(.journalOffer(declined))
    }

    private func handleOfferTuning(offer: JournalOffer, tuning: JournalOfferEventTuning) {
        handleOfferShownIfNeeded(offer: offer)
        suppressJournalOffer = true

        if let offersEnabled = tuning.offersEnabled {
            JournalStyleSettings.setOffersEnabled(offersEnabled)
        }
        if let newCooldown = tuning.newCooldownMinutes {
            JournalStyleSettings.setCooldownMinutes(newCooldown)
        }
        if let avoid = tuning.avoidPeakOverwhelm {
            JournalStyleSettings.setAvoidPeakOverwhelm(avoid)
        }

        let tuned = makeJournalOfferEvent(
            type: .journalOfferMutedOrTuned,
            offer: offer,
            userAction: .disableOrTune,
            tuning: tuning
        )
        postTraceEvent(.journalOffer(tuned))
    }

    private func handleDraftSaved(
        context: JournalDraftSaveContext,
        offer: JournalOffer?,
        payload: JournalDraftEditorPayload
    ) {
        guard let offer else { return }

        let cpbId = JournalStyleSettings.cpbId
        let refs = JournalOfferEventRefs(
            cpbId: cpbId,
            draftId: payload.draftId,
            entryId: nil,
            requestId: payload.requestId
        )

        if context.didEdit {
            let edited = makeJournalOfferEvent(
                type: .journalEntryEditedBeforeSave,
                offer: offer,
                modeSelected: payload.mode,
                refs: refs
            )
            postTraceEvent(.journalOffer(edited))
        }

        let saved = makeJournalOfferEvent(
            type: .journalEntrySaved,
            offer: offer,
            modeSelected: payload.mode,
            refs: refs
        )
        postTraceEvent(.journalOffer(saved))
    }

    private func postTraceEvent(_ event: TraceEvent) {
        Task {
            let requestId = UUID().uuidString
            let eventId = traceEventId(from: event)
            let eventType = traceEventType(from: event)
            let request = TraceEventsRequest(
                requestId: requestId,
                localUserUuid: LocalIdentity.localUserUuid(),
                events: [event]
            )
            do {
                try await SolServerClient().postTraceEvents(request: request)
                log.debug("trace.post.succeeded requestId=\(requestId, privacy: .public) eventId=\(eventId ?? "nil", privacy: .public) eventType=\(eventType ?? "unknown", privacy: .public)")
            } catch {
                log.debug("trace.post.failed requestId=\(requestId, privacy: .public) eventId=\(eventId ?? "nil", privacy: .public) eventType=\(eventType ?? "unknown", privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func traceEventId(from event: TraceEvent) -> String? {
        switch event {
        case .journalOffer(let offerEvent):
            return offerEvent.eventId
        case .deviceMuseObservation(let observation):
            return observation.observationId
        }
    }

    private func traceEventType(from event: TraceEvent) -> String? {
        switch event {
        case .journalOffer(let offerEvent):
            return offerEvent.eventType.rawValue
        case .deviceMuseObservation:
            return "device_muse_observation"
        }
    }

    private func makeJournalOfferEvent(
        type: JournalOfferEventType,
        offer: JournalOffer,
        modeSelected: JournalDraftMode? = nil,
        userAction: JournalOfferUserAction? = nil,
        cooldownActive: Bool? = nil,
        latencyMs: Int? = nil,
        refs: JournalOfferEventRefs? = nil,
        tuning: JournalOfferEventTuning? = nil
    ) -> JournalOfferEvent {
        JournalOfferEvent(
            eventId: UUID().uuidString,
            eventType: type,
            ts: Self.traceTimestampFormatter.string(from: Date()),
            threadId: message.thread.id.uuidString,
            momentId: offer.momentId,
            evidenceSpan: offer.evidenceSpan,
            phaseAtOffer: offer.phase,
            modeSelected: modeSelected,
            userAction: userAction,
            cooldownActive: cooldownActive,
            latencyMs: latencyMs,
            refs: refs,
            tuning: tuning
        )
    }

    @MainActor
    private func handleVerbatimShare(offer: JournalOffer) async {
        guard let payload = buildVerbatimDraftPayload(for: offer) else { return }
        let outcome = await exportJournalViaShareSheet(title: payload.title, body: payload.body)
        let event = makeJournalOfferEvent(
            type: .journalEntrySaved,
            offer: offer,
            modeSelected: .verbatim,
            userAction: .save
        )
        if outcome.completed {
            postTraceEvent(.journalOffer(event))
        }

        if !outcome.completed {
            suppressJournalOffer = false
        }
    }

    private func buildVerbatimDraftPayload(for offer: JournalOffer) -> JournalDraftEditorPayload? {
        guard let spanMessages = resolveEvidenceSpanMessages(span: offer.evidenceSpan) else {
            errorMessage = "Unable to locate the journal span."
            showErrorAlert = true
            suppressJournalOffer = false
            return nil
        }

        let userMessages = spanMessages.filter { $0.creatorType == .user }
        guard !userMessages.isEmpty else {
            errorMessage = "No user messages found for this span."
            showErrorAlert = true
            suppressJournalOffer = false
            return nil
        }

        let title = makeDraftTitle(from: userMessages.first?.text ?? "")
        let body = userMessages.map { $0.text }.joined(separator: "\n\n")
        let draftId = "local-\(UUID().uuidString)"

        return JournalDraftEditorPayload(
            id: draftId,
            mode: .verbatim,
            title: title,
            body: body,
            tagsSuggested: [],
            evidenceSpan: offer.evidenceSpan,
            draftId: nil,
            requestId: nil
        )
    }

    private func resolveEvidenceSpanMessages(span: JournalEvidenceSpan) -> [Message]? {
        let threadId = message.thread.id
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { $0.thread.id == threadId },
            sortBy: [SortDescriptor(\Message.createdAt, order: .forward)]
        )
        guard let allMessages = try? modelContext.fetch(descriptor) else { return nil }

        let startIndex = allMessages.firstIndex { $0.resolvedServerMessageId == span.startMessageId }
        let endIndex = allMessages.firstIndex { $0.resolvedServerMessageId == span.endMessageId }

        guard let startIndex, let endIndex else { return nil }
        let lower = min(startIndex, endIndex)
        let upper = max(startIndex, endIndex)
        return Array(allMessages[lower...upper])
    }

    private func makeDraftTitle(from text: String) -> String {
        let words = text.split(separator: " ")
        let prefix = words.prefix(6).joined(separator: " ")
        let title = words.count > 6 ? "\(prefix)..." : String(prefix)
        if title.isEmpty {
            return "Journal Entry"
        }
        return String(title.prefix(200))
    }

    private func buildGhostCardModel() -> GhostCardModel? {
        guard let kind = message.ghostKind else { return nil }
        let cta = message.ghostCTAState
        let canAscend = message.isAscendEligible && JournalDonationService.isJournalAvailable

        let onEdit: (() -> Void)?
        if cta.canEdit {
            onEdit = { openEditor() }
        } else {
            onEdit = nil
        }

        let onAccept: (() -> Void)?
        if kind == .memoryArtifact, let memoryId = message.ghostMemoryId, !message.ghostFactNull {
            onAccept = {
                onMemoryOfferAccept?(memoryId)
            }
        } else {
            onAccept = nil
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
        if canAscend {
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
                onAccept: onAccept,
                onEdit: onEdit,
                onForget: onForget,
                onAscend: onAscend,
                onAddToCalendar: {
                    KeyboardDismiss.dismiss()
                    Task { await presentEventEditor() }
                },
                onAddToReminder: {
                    KeyboardDismiss.dismiss()
                    Task { await presentReminderEditor() }
                },
                onGoToThread: nil
            )
        )
    }

    private func openEditor() {
        KeyboardDismiss.dismiss()
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
        guard JournalDonationService.isJournalAvailable else {
            journalPresentation = .alert(message: "Journal isn't available on this device.", showShareSheet: false)
            return false
        }

        if JournalDonationService.supportsDirectDonation {
            let result = await JournalDonationService.shared.donateMoment(
                summaryText: summary,
                location: location,
                moodAnchor: moodLabel
            )

            switch result {
            case .success:
                if let memoryId {
                    markAscended(memoryId: memoryId)
                    recordJournalCapture(memoryId: memoryId, location: location, moodAnchor: moodLabel)
                }
                return true
            case .notAuthorized, .failed:
                let outcome = await exportJournalViaShareSheet(
                    title: "Journal",
                    body: summary,
                    showAlert: true,
                    alertMessage: "Journal export failed. You can share a copy instead."
                )
                if outcome.completed, let memoryId {
                    markAscended(memoryId: memoryId)
                    recordJournalCapture(memoryId: memoryId, location: location, moodAnchor: moodLabel)
                }
                return outcome.completed
            case .unavailable:
                break
            }
        }

        let outcome = await exportJournalViaShareSheet(title: "Journal", body: summary)
        if outcome.completed, let memoryId {
            markAscended(memoryId: memoryId)
            recordJournalCapture(memoryId: memoryId, location: location, moodAnchor: moodLabel)
        }
        return outcome.completed
    }

    @MainActor
    private func exportJournalViaShareSheet(
        title: String,
        body: String,
        showAlert: Bool = false,
        alertMessage: String? = nil
    ) async -> ShareOutcome {
        await withCheckedContinuation { continuation in
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let text: String
            if trimmedTitle.isEmpty {
                text = trimmedBody
            } else if trimmedBody.isEmpty {
                text = trimmedTitle
            } else {
                text = "\(trimmedTitle)\n\n\(trimmedBody)"
            }

            journalShareItems = [text]
            journalShareCompletion = { completed, destination in
                continuation.resume(returning: ShareOutcome(completed: completed, destination: destination))
            }
            if showAlert, let alertMessage {
                journalPresentation = .alert(message: alertMessage, showShareSheet: true)
            } else {
                journalPresentation = .shareSheet
            }
        }
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
