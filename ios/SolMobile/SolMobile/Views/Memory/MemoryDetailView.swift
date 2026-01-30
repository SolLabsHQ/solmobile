//
//  MemoryDetailView.swift
//  SolMobile
//

import SwiftUI
import SwiftData

struct MemoryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var editorMode: MemoryEditorMode?
    @State private var showDeleteConfirm = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String = ""
    @State private var isFetching = false

    @Bindable var memory: MemoryArtifact

    var body: some View {
        List {
            Section("Snippet") {
                Text(memory.snippet ?? "(no snippet)")
            }

            if let summary = memory.summary, !summary.isEmpty {
                Section("Summary") {
                    Text(summary)
                }
            }

            Section("Origin") {
                if let threadId = memory.threadId {
                    Text("Thread: \(threadId)")
                }
            }

            Section("Metadata") {
                if let kind = memory.memoryKindRaw {
                    Text("Kind: \(kind)")
                }
                if let state = memory.lifecycleStateRaw {
                    Text("Lifecycle: \(state)")
                }
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
        .task(id: memory.memoryId) {
            await fetchMemoryDetailIfNeeded()
        }
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

    private func fetchMemoryDetailIfNeeded() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        do {
            let response = try await SolServerClient().getMemory(memoryId: memory.memoryId)
            if let dto = response.memory {
                await MainActor.run {
                    applyUpdate(dto)
                }
            }
        } catch {
            // Keep detail view usable even if server fetch fails.
        }
    }

    private func applyUpdate(_ dto: MemoryItemDTO) {
        memory.snippet = dto.snippet ?? memory.snippet
        memory.summary = dto.summary ?? memory.summary
        memory.moodAnchor = dto.moodAnchor ?? memory.moodAnchor
        memory.rigorLevelRaw = dto.rigorLevel ?? memory.rigorLevelRaw
        memory.lifecycleStateRaw = dto.lifecycleState ?? memory.lifecycleStateRaw
        memory.memoryKindRaw = dto.memoryKind ?? memory.memoryKindRaw
        memory.tagsCsv = dto.tags?.joined(separator: ",") ?? memory.tagsCsv
        if let evidenceIds = dto.evidenceMessageIds {
            memory.evidenceMessageIdsCsv = evidenceIds.joined(separator: ",")
        }
        memory.updatedAt = dto.updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        try? modelContext.save()
    }
}
