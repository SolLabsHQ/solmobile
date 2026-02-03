//
//  MemoryVaultView.swift
//  SolMobile
//

import SwiftUI
import SwiftData

struct MemoryVaultView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoryArtifact.createdAt, order: .reverse)
    private var memories: [MemoryArtifact]

    @State private var isRefreshing = false
    @State private var showClearAll = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    private var pinnedMemories: [MemoryArtifact] {
        memories.filter { ($0.lifecycleStateRaw ?? "pinned") != "archived" }
    }

    var body: some View {
        List {
            Section("Memories") {
                if pinnedMemories.isEmpty {
                    Text("No memories yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pinnedMemories) { memory in
                        NavigationLink {
                            MemoryDetailView(memory: memory)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text("👻")
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(memory.snippet ?? "(no snippet)")
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    if let threadId = memory.threadId {
                                        Text("Thread \(threadId)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if memory.ascendedAt != nil {
                                        Text("Ascended")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showClearAll = true
                } label: {
                    Text("Clear All Memories")
                }
            }
        }
        .navigationTitle("Memory Vault")
        .refreshable {
            await refreshMemories()
        }
        .onAppear {
            if memories.isEmpty {
                Task { await refreshMemories() }
            }
        }
        .sheet(isPresented: $showClearAll) {
            ClearAllMemoriesSheet { phrase in
                Task { await clearAllMemories(confirmPhrase: phrase) }
            }
        }
        .alert("Request Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func refreshMemories() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let client = SolServerClient()
            let response = try await client.listMemories(limit: 200)
            await MainActor.run {
                for item in response.memories {
                    upsertMemoryArtifact(from: item)
                }
                if response.nextCursor == nil {
                    let serverIds = Set(response.memories.map { $0.id })
                    for memory in memories where !serverIds.contains(memory.memoryId) {
                        if (memory.lifecycleStateRaw ?? "pinned") != "archived" {
                            memory.lifecycleStateRaw = "archived"
                            memory.updatedAt = Date()
                        }
                    }
                    try? modelContext.save()
                }
            }
        } catch {
            errorMessage = "Unable to refresh memories."
            showErrorAlert = true
        }
    }

    private func clearAllMemories(confirmPhrase: String) async {
        guard confirmPhrase == "DELETE ALL" else { return }
        do {
            let request = MemoryClearAllRequest(
                requestId: UUID().uuidString,
                confirm: true,
                confirmPhrase: confirmPhrase
            )
            let client = SolServerClient()
            _ = try await client.clearAllMemories(request: request)
            await MainActor.run {
                for memory in memories {
                    modelContext.delete(memory)
                }
                try? modelContext.save()
            }
        } catch {
            errorMessage = "Unable to clear memories."
            showErrorAlert = true
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

        let memory = MemoryArtifact(
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
        modelContext.insert(memory)
        try? modelContext.save()
    }
}

private struct ClearAllMemoriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phrase = ""

    let onConfirm: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Confirm") {
                    Text("Type DELETE ALL to clear your memory vault.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("DELETE ALL", text: $phrase)
                }
            }
            .navigationTitle("Clear All Memories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete", role: .destructive) {
                        onConfirm(phrase)
                        dismiss()
                    }
                    .disabled(phrase != "DELETE ALL")
                }
            }
        }
    }
}
