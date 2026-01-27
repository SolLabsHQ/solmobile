//
//  JournalDraftEditorView.swift
//  SolMobile
//

import SwiftUI
import UIKit

struct JournalDraftEditorPayload: Identifiable {
    let id: String
    let mode: JournalDraftMode
    let title: String
    let body: String
    let tagsSuggested: [String]
    let evidenceSpan: JournalEvidenceSpan
    let draftId: String?
    let requestId: String?
}

struct JournalDraftSaveContext {
    let title: String
    let body: String
    let didEdit: Bool
}

struct JournalDraftEditorView: View {
    let payload: JournalDraftEditorPayload
    let onComplete: (JournalDraftSaveContext) -> Void
    let onCancel: () -> Void

    @State private var titleText: String
    @State private var bodyText: String
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showErrorAlert = false
    @State private var errorMessage: String = ""
    @State private var isSaving = false
    @State private var deferShareSheetAfterAlert = false

    private let initialTitle: String
    private let initialBody: String

    init(payload: JournalDraftEditorPayload, onComplete: @escaping (JournalDraftSaveContext) -> Void, onCancel: @escaping () -> Void) {
        self.payload = payload
        self.onComplete = onComplete
        self.onCancel = onCancel
        _titleText = State(initialValue: payload.title)
        _bodyText = State(initialValue: payload.body)
        self.initialTitle = payload.title
        self.initialBody = payload.body
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Title", text: $titleText)
                    .font(.headline)

                TextEditor(text: $bodyText)
                    .frame(minHeight: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                if !payload.tagsSuggested.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tags suggested")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        WrapTagsView(tags: payload.tagsSuggested)
                    }
                }

                HStack(spacing: 12) {
                    Button("Ascend") {
                        attemptAscend()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)

                    Button("Share") {
                        presentShareSheet()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle("Journal Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheetView(activityItems: shareItems) { completed, _ in
                    showShareSheet = false
                    guard completed else { return }
                    completeExport()
                }
            }
            .alert("Export Failed", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {
                    if deferShareSheetAfterAlert {
                        deferShareSheetAfterAlert = false
                        presentShareSheet()
                    }
                }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func attemptAscend() {
        guard !isSaving else { return }
        isSaving = true

        Task {
            let result = await JournalDonationService.shared.donateEntry(title: titleText, body: bodyText)
            await MainActor.run {
                isSaving = false
                switch result {
                case .success:
                    completeExport()
                case .notAuthorized:
                    errorMessage = "Journal access is not authorized."
                    showErrorAlert = true
                    deferShareSheetAfterAlert = true
                case .unavailable:
                    presentShareSheet()
                case .failed(let message):
                    errorMessage = message ?? "Unable to export to Journal."
                    showErrorAlert = true
                    deferShareSheetAfterAlert = true
                }
            }
        }
    }

    private func presentShareSheet() {
        shareItems = [exportText]
        showShareSheet = true
    }

    private var exportText: String {
        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return body
        }
        if body.isEmpty {
            return title
        }
        return "\(title)\n\n\(body)"
    }

    private func completeExport() {
        let didEdit = titleText != initialTitle || bodyText != initialBody
        onComplete(JournalDraftSaveContext(title: titleText, body: bodyText, didEdit: didEdit))
        onCancel()
    }
}

private struct WrapTagsView: View {
    let tags: [String]

    var body: some View {
        FlexibleView(data: tags, spacing: 8, alignment: .leading) { tag in
            Text(tag)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
    }
}

private struct FlexibleView<Data: Collection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    let content: (Data.Element) -> Content
    @State private var availableWidth: CGFloat = 0

    init(data: Data, spacing: CGFloat, alignment: HorizontalAlignment, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.spacing = spacing
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { item in
                        content(item)
                    }
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { availableWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in
                        availableWidth = newValue
                    }
            }
        )
    }

    private var rows: [[Data.Element]] {
        var rows: [[Data.Element]] = [[]]
        var currentRowWidth: CGFloat = 0
        let maxWidth = availableWidth - 48

        guard maxWidth > 0 else {
            return [Array(data)]
        }

        for item in data {
            let itemWidth = CGFloat(String(describing: item).count * 7 + 24)
            if currentRowWidth + itemWidth > maxWidth {
                rows.append([item])
                currentRowWidth = itemWidth
            } else {
                rows[rows.count - 1].append(item)
                currentRowWidth += itemWidth + spacing
            }
        }
        return rows
    }
}
