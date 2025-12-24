import SwiftUI
import SwiftData
import os

struct ThreadDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var thread: Thread
    @Query private var transmissions: [Transmission]
    @State private var isProcessingOutbox: Bool = false
    @State private var outboxNeedsRerun: Bool = false

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
        .onAppear { processOutbox() }
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
