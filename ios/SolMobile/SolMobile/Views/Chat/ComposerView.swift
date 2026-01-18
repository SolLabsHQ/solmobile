//
//  ComposerView.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/22/25.
//

import SwiftUI

struct ComposerView: View {
    @Binding var text: String
    var onSend: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Message…", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            Button("Send") {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onSend(trimmed)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
