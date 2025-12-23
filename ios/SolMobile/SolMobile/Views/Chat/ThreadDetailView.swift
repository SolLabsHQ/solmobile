import SwiftUI
import SwiftData

struct ThreadDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var thread: Thread
    @State private var isProcessingOutbox: Bool = false

    private var sortedMessages: [Message] {
        thread.messages.sorted { $0.createdAt < $1.createdAt }
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
        .onAppear { processOutbox() }
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send(_ text: String) {
        let m = Message(thread: thread, creatorType: .user, text: text)
        thread.messages.append(m)
        thread.lastActiveAt = Date()
        modelContext.insert(m)

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
                        let tx = TransmissionActions(modelContext: modelContext)
                        tx.retryFailed()
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
        // v0: simple fetch + filter by thread
        let all = (try? modelContext.fetch(FetchDescriptor<Transmission>())) ?? []
        let mine = all.filter { $0.packet.threadId == thread.id }

        let queued = mine.filter { $0.status == .queued }.count
        let sending = mine.filter { $0.status == .sending }.count
        let failed = mine.filter { $0.status == .failed }.count
        return OutboxSummary(queued: queued, sending: sending, failed: failed)
    }

    private func processOutbox() {
        guard !isProcessingOutbox else { return }
        isProcessingOutbox = true

        Task {
            let tx = TransmissionActions(modelContext: modelContext)
            await tx.processQueue()

            // bc will update UI
            await MainActor.run { isProcessingOutbox = false }
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
