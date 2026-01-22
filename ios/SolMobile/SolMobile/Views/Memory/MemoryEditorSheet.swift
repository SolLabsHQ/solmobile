//
//  MemoryEditorSheet.swift
//  SolMobile
//

import SwiftUI

enum MemoryEditorMode: Identifiable {
    case create(threadId: String?, messageId: String?, initialText: String)
    case edit(memoryId: String, initialText: String)

    var id: String {
        switch self {
        case let .create(threadId, messageId, _):
            return "create_\(threadId ?? "-")_\(messageId ?? "-")"
        case let .edit(memoryId, _):
            return "edit_\(memoryId)"
        }
    }

    var initialText: String {
        switch self {
        case let .create(_, _, text):
            return text
        case let .edit(_, text):
            return text
        }
    }
}

struct MemoryEditorSheet: View {
    let mode: MemoryEditorMode
    let onComplete: (MemoryItemDTO?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    init(mode: MemoryEditorMode, onComplete: @escaping (MemoryItemDTO?) -> Void) {
        self.mode = mode
        self.onComplete = onComplete
        _text = State(initialValue: mode.initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Memory") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(trimmedText.isEmpty || isSaving)
                }
            }
            .alert("Save Failed", isPresented: $showError) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var title: String {
        switch mode {
        case .create:
            return "Add Memory"
        case .edit:
            return "Edit Memory"
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        guard !trimmedText.isEmpty else { return }
        isSaving = true

        do {
            let client = SolServerClient()
            switch mode {
            case let .create(threadId, messageId, _):
                let requestId = UUID().uuidString
                let payload = MemoryCreatePayload(
                    domain: "general",
                    title: nil,
                    tags: nil,
                    importance: nil,
                    content: trimmedText,
                    moodAnchor: nil,
                    rigorLevel: nil
                )

                let source: MemoryCreateSource?
                if let threadId, let messageId {
                    source = MemoryCreateSource(
                        threadId: threadId,
                        messageId: messageId,
                        createdAt: ISO8601DateFormatter().string(from: Date())
                    )
                } else {
                    source = nil
                }

                let request = MemoryCreateRequest(
                    requestId: requestId,
                    memory: payload,
                    source: source,
                    consent: MemoryConsent(explicitUserConsent: true)
                )

                let response = try await client.createMemory(request: request)
                onComplete(response.memory)
            case let .edit(memoryId, _):
                let request = MemoryPatchRequest(
                    requestId: UUID().uuidString,
                    patch: MemoryPatchPayload(
                        snippet: trimmedText,
                        tags: nil,
                        moodAnchor: nil
                    ),
                    consent: MemoryConsent(explicitUserConsent: true)
                )

                let response = try await client.updateMemory(memoryId: memoryId, request: request)
                onComplete(response.memory)
            }

            dismiss()
        } catch {
            errorMessage = "Unable to save memory."
            showError = true
        }

        isSaving = false
    }
}
