//
//  RecoveryPillView.swift
//  SolMobile
//

import SwiftUI

struct RecoveryPillView: View {
    let onRestore: () -> Void

    var body: some View {
        Button(action: onRestore) {
            HStack(spacing: 6) {
                Text("👻")
                    .font(.system(size: 14))
                    .opacity(0.6)
                    .shadow(color: brandGold.opacity(0.5), radius: 4, x: 0, y: 1)

                Text("Restore")
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var brandGold: Color {
        Color(red: 0.95, green: 0.82, blue: 0.32)
    }
}

