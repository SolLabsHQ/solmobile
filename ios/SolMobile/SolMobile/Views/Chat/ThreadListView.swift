//
//  ThreadListView.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/22/25.
//

import SwiftUI
import SwiftData

struct ThreadListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ConversationThread.lastActiveAt, order: .reverse)
    private var threads: [ConversationThread]

    @Query private var transmissions: [Transmission]
    @State private var didRunDraftCleanup = false
    @State private var didScheduleStorageCleanup = false
    @State private var pendingDeleteOffsets: IndexSet? = nil
    @State private var showDeleteWarning = false


    var body: some View {
        NavigationStack {
            List {
                ForEach(threads) { thread in
                    NavigationLink {
                        ThreadDetailView(thread: thread)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thread.title)
                                .font(.headline)
                            Text(thread.lastActiveAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(BrandColors.timeLaneText)

                            Spacer()
                            if failedThreadIds.contains(thread.id) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    pendingDeleteOffsets = offsets
                    showDeleteWarning = true
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createThread()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New Thread")
                    .accessibilityIdentifier("new_thread_button")
                }
            }
            .onAppear {
                guard !didRunDraftCleanup else { return }
                didRunDraftCleanup = true
                try? DraftStore(modelContext: modelContext).cleanupExpiredDrafts()
                scheduleStorageCleanupIfDue()
                StorageCleanupScheduler.shared.schedule()
            }
            .alert("Delete Thread?", isPresented: $showDeleteWarning) {
                Button("Delete", role: .destructive) {
                    if let offsets = pendingDeleteOffsets {
                        delete(at: offsets)
                    }
                    pendingDeleteOffsets = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteOffsets = nil
                }
            } message: {
                Text("This deletes your conversation history. Saved memories remain in your Vault unless deleted separately.")
            }
        }
    }

    private func createThread() {
        let t = ConversationThread(title: "Thread \(threads.count + 1)")
        modelContext.insert(t)
    }

    private func delete(at offsets: IndexSet) {
        for idx in offsets {
            DraftStore(modelContext: modelContext).deleteDraft(threadId: threads[idx].id)
            modelContext.delete(threads[idx])
        }
    }

    private func scheduleStorageCleanupIfDue() {
        guard !didScheduleStorageCleanup else { return }

        let service = StorageCleanupService(modelContext: modelContext)
        guard service.isCleanupDue() else { return }
        didScheduleStorageCleanup = true

        Task {
            // Defer heavy work until after the list renders.
            await Task.yield()
            _ = try? service.runCleanup()
        }
    }

    private var failedThreadIds: Set<UUID> {
        Set(transmissions
            .filter { $0.status == .failed }
            .map { $0.packet.threadId }
        )
    }
}
