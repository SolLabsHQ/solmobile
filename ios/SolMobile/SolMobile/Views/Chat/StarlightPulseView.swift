//
//  StarlightPulseView.swift
//  SolMobile
//

import SwiftUI

enum StarlightState: Equatable {
    case idle
    case pending
    case flash
}

struct StarlightPulseView: View {
    let state: StarlightState

    @State private var breatheOn = false
    @State private var flashProgress: CGFloat = 1.0

    private let size: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .fill(starlightColor)
                .opacity(baseOpacity)

            Circle()
                .stroke(starlightColor.opacity(0.9), lineWidth: 1.2)
                .scaleEffect(1.0 + (0.4 * flashProgress))
                .opacity(1.0 - flashProgress)
                .animation(.easeOut(duration: 0.35), value: flashProgress)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .background(.ultraThinMaterial, in: Circle())
        .onAppear {
            updateAnimation(for: state)
        }
        .onChange(of: state) { _, newValue in
            updateAnimation(for: newValue)
        }
    }

    private var starlightColor: Color {
        Color(red: 0.95, green: 0.82, blue: 0.32)
    }

    private var baseOpacity: Double {
        switch state {
        case .idle:
            return 0.0
        case .pending:
            return breatheOn ? 0.7 : 0.2
        case .flash:
            return 0.85
        }
    }

    private func updateAnimation(for state: StarlightState) {
        switch state {
        case .idle:
            breatheOn = false
            flashProgress = 1.0
        case .pending:
            flashProgress = 1.0
            if !breatheOn {
                breatheOn = false
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    breatheOn = true
                }
            }
        case .flash:
            breatheOn = false
            flashProgress = 0.0
            withAnimation(.easeOut(duration: 0.35)) {
                flashProgress = 1.0
            }
        }
    }
}
