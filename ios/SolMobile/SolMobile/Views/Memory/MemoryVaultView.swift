//
//  MemoryVaultView.swift
//  SolMobile
//

import SwiftUI
import SwiftData

struct MemoryVaultView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(PhysicalityManager.storageKey) private var physicalityEnabled: Bool = true

    @Query(sort: \MemoryArtifact.createdAt, order: .reverse)
    private var memories: [MemoryArtifact]

    @State private var isRefreshing = false
    @State private var showClearAll = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    var body: some View {
        List {
            Section("Physicality") {
                Toggle("Physicality", isOn: $physicalityEnabled)
            }

            Section("Memories") {
                if memories.isEmpty {
                    Text("No memories yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(memories) { memory in
                        NavigationLink {
                            MemoryDetailView(memory: memory)
                        } label: {
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
                        modelContext.delete(memory)
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
            existing.moodAnchor = dto.moodAnchor ?? existing.moodAnchor
            existing.rigorLevelRaw = dto.rigorLevel ?? existing.rigorLevelRaw
            existing.tagsCsv = dto.tags?.joined(separator: ",") ?? existing.tagsCsv
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
            moodAnchor: dto.moodAnchor,
            rigorLevelRaw: dto.rigorLevel,
            tagsCsv: dto.tags?.joined(separator: ","),
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

private struct MemoryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var editorMode: MemoryEditorMode?
    @State private var showDeleteConfirm = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String = ""

    @Bindable var memory: MemoryArtifact

    var body: some View {
        List {
            Section("Snippet") {
                Text(memory.snippet ?? "(no snippet)")
            }

            Section("Origin") {
                if let threadId = memory.threadId {
                    Text("Thread: \(threadId)")
                }
            }

            Section("Metadata") {
                if let rigor = memory.rigorLevelRaw {
                    Text("Rigor: \(rigor)")
                }
                if let mood = memory.moodAnchor {
                    Text("Mood: \(mood)")
                }
                if let fidelity = memory.fidelityRaw {
                    Text("Fidelity: \(fidelity)")
                }
                if let hazy = memory.transitionToHazyAt {
                    Text("Hazy At: \(hazy.formatted())")
                }
            }

            Section {
                Button("Edit") {
                    editorMode = .edit(memoryId: memory.memoryId, initialText: memory.snippet ?? "")
                }

                Button(role: .destructive) {
                    if memory.rigorLevelRaw == "high" {
                        showDeleteConfirm = true
                    } else {
                        Task { await deleteMemory(confirm: false) }
                    }
                } label: {
                    Text("Forget")
                }
            }
        }
        .navigationTitle("Memory")
        .sheet(item: $editorMode) { mode in
            MemoryEditorSheet(mode: mode) { updated in
                if let updated {
                    applyUpdate(updated)
                }
            }
        }
        .alert("Confirm Delete", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await deleteMemory(confirm: true) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This memory affects safety boundaries. Confirm to delete it.")
        }
        .alert("Request Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func deleteMemory(confirm: Bool) async {
        do {
            let client = SolServerClient()
            try await client.deleteMemory(memoryId: memory.memoryId, confirm: confirm ? true : nil)
            await MainActor.run {
                modelContext.delete(memory)
                try? modelContext.save()
            }
        } catch {
            errorMessage = "Unable to delete memory."
            showErrorAlert = true
        }
    }

    private func applyUpdate(_ dto: MemoryItemDTO) {
        memory.snippet = dto.snippet ?? memory.snippet
        memory.moodAnchor = dto.moodAnchor ?? memory.moodAnchor
        memory.rigorLevelRaw = dto.rigorLevel ?? memory.rigorLevelRaw
        memory.tagsCsv = dto.tags?.joined(separator: ",") ?? memory.tagsCsv
        memory.updatedAt = dto.updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        try? modelContext.save()
    }
}
