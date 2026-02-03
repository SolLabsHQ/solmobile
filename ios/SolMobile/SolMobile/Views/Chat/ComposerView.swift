//
//  ComposerView.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/22/25.
//

import SwiftUI

struct ComposerView: View {
    @Binding var text: String
    var isSendBlocked: Bool = false
    var blockedUntil: Date? = nil
    var onSend: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField("Message…", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                Button("Send") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    HapticRouter.shared.tapLight()
                    onSend(trimmed)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendBlocked)
            }

            if isSendBlocked {
                Text(blockedMessage)
                    .font(.caption)
                    .foregroundStyle(BrandColors.statusText)
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
