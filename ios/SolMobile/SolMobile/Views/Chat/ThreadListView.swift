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

    @Query(sort: \Thread.lastActiveAt, order: .reverse)
    private var threads: [Thread]

    @Query private var transmissions: [Transmission]


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
                                .foregroundStyle(.secondary)

                            Spacer()
                            if failedThreadIds.contains(thread.id) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
                .onDelete(perform: delete)
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
                }
            }
        }
    }

    private func createThread() {
        let t = Thread(title: "Thread \(threads.count + 1)")
        modelContext.insert(t)
    }

    private func delete(at offsets: IndexSet) {
        for idx in offsets {
            modelContext.delete(threads[idx])
        }
    }

    private var failedThreadIds: Set<UUID> {
        Set(transmissions
            .filter { $0.status == .failed }
            .map { $0.packet.threadId }
        )
    }
}
