//
//  JournalOfferCard.swift
//  SolMobile
//

import SwiftUI

struct JournalOfferCard: View {
    let offer: JournalOffer
    let onAssist: () -> Void
    let onVerbatim: () -> Void
    let onDecline: () -> Void
    let onTune: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "book")
                Text("Journal this moment?")
                    .font(.headline)
                Spacer()
            }

            if let why = offer.why, !why.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(why, id: \.self) { item in
                        Text("- \(item)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Save this as a quick journal entry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Help me shape it", action: onAssist)
                    .buttonStyle(.borderedProminent)
                Button("Save my words", action: onVerbatim)
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Button("Not now", action: onDecline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)

                Button("Don't ask like this", action: onTune)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}
