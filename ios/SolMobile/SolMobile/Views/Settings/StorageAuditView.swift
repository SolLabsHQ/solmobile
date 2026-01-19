//
//  StorageAuditView.swift
//  SolMobile
//

import SwiftUI
import SwiftData

struct StorageAuditView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var threads: [ConversationThread]
    @Query private var messages: [Message]

    @State private var dbSize: String = "Calculating..."
    @State private var stats: StorageCleanupStats = StorageCleanupService.loadStats()
    @State private var isRunningCleanup: Bool = false
    @State private var cleanupError: String? = nil

    var body: some View {
        List {
            Section("Storage Statistics") {
                StatRow(label: "Threads", value: "\(threads.count)")
                StatRow(label: "Messages", value: "\(messages.count)")
                StatRow(label: "Pinned Threads", value: "\(threads.filter { $0.pinned }.count)")
                StatRow(label: "Pinned Messages", value: "\(messages.filter { $0.pinned }.count)")
                StatRow(label: "Database Size", value: dbSize)
            }

            Section("Cleanup") {
                StatRow(label: "Last Run", value: formattedLastRun)
                StatRow(label: "Deleted Messages", value: "\(stats.deletedMessages)")
                StatRow(label: "Deleted Threads", value: "\(stats.deletedThreads)")

                Button("Run Cleanup Now", role: .destructive) {
                    runCleanup()
                }
                .disabled(isRunningCleanup)

                if let cleanupError {
                    Text(cleanupError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Storage Audit")
        .onAppear {
            refreshStats()
            calculateDbSize()
        }
    }

    private var formattedLastRun: String {
        guard let last = stats.lastRunAt else { return "Never" }
        return last.formatted(date: .abbreviated, time: .shortened)
    }

    private func refreshStats() {
        stats = StorageCleanupService.loadStats()
    }

    private func runCleanup() {
        cleanupError = nil
        isRunningCleanup = true

        Task {
            // Defer heavy work until after the view has rendered.
            await Task.yield()

            do {
                let service = StorageCleanupService(modelContext: modelContext)
                _ = try service.runCleanup(force: true)
                stats = StorageCleanupService.loadStats()
                calculateDbSize()
            } catch {
                cleanupError = "Cleanup failed: \(error.localizedDescription)"
            }

            isRunningCleanup = false
        }
    }

    private func calculateDbSize() {
        Task.detached {
            let total = StorageAuditHelper.computeStoreBytes()
            let formatted = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            await MainActor.run {
                dbSize = formatted
            }
        }
    }
}

private enum StorageAuditHelper {
    nonisolated static func computeStoreBytes() -> Int64 {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return 0
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: base, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let isStoreFile = name.hasSuffix(".store") || name.hasSuffix(".store-wal") || name.hasSuffix(".store-shm")
            guard isStoreFile else { continue }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }

        return total
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
