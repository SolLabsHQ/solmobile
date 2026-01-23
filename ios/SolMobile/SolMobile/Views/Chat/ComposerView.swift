//
//  ComposerView.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/22/25.
//

import SwiftUI

struct ComposerView: View {
    @Binding var text: String
    var starlightState: StarlightState = .idle
    var isSendBlocked: Bool = false
    var blockedUntil: Date? = nil
    var onSend: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                StarlightPulseView(state: starlightState)
                    .frame(width: 12, height: 12)
                TextField("Message…", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                Button("Send") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSend(trimmed)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendBlocked)
            }

            if isSendBlocked {
                Text(blockedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var blockedMessage: String {
        if let blockedUntil {
            return "Budget limit reached. Try again after \(blockedUntil.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Budget limit reached. Try again later."
    }
}
