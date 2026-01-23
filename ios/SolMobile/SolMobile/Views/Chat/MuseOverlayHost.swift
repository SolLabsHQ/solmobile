//
//  MuseOverlayHost.swift
//  SolMobile
//

import SwiftUI

struct MuseOverlayHost<Content: View>: View {
    let canAscend: Bool
    let onDismiss: () -> Void
    let onAscend: () -> Void
    let content: Content

    init(
        canAscend: Bool,
        onDismiss: @escaping () -> Void,
        onAscend: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.canAscend = canAscend
        self.onDismiss = onDismiss
        self.onAscend = onAscend
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                content
                    .padding(.top, 10)
                    .padding(.leading, 10)

                MuseHandleView(
                    canAscend: canAscend,
                    onDismiss: onDismiss,
                    onAscend: onAscend
                )
                .offset(x: -6, y: -6)
            }
            .padding(.top, geo.safeAreaInsets.top + 12)
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct MuseHandleView: View {
    let canAscend: Bool
    let onDismiss: () -> Void
    let onAscend: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var echoScale: CGFloat = 1.0
    @State private var echoOpacity: Double = 0.0
    @State private var bounceScale: CGFloat = 1.0

    private let handleSize: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .stroke(brandGold.opacity(0.6), lineWidth: 1)
                .scaleEffect(echoScale)
                .opacity(echoOpacity)
                .allowsHitTesting(false)

            Text("👻")
                .font(.system(size: 24))
                .opacity(0.6)
                .shadow(color: brandGold.opacity(0.4), radius: 4, x: 0, y: 1)
        }
        .frame(width: handleSize, height: handleSize)
        .background(.ultraThinMaterial, in: Circle())
        .shadow(color: brandGold.opacity(0.35), radius: 6, x: 0, y: 2)
        .scaleEffect(bounceScale)
        .contentShape(Circle())
        .onAppear {
            runEcho()
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if dx < -30, abs(dx) > abs(dy) {
                        onDismiss()
                    } else if dy < -30, abs(dy) > abs(dx), canAscend {
                        onAscend()
                    }
                }
        )
    }

    private var brandGold: Color {
        Color(red: 0.95, green: 0.82, blue: 0.32)
    }

    private func runEcho() {
        guard !reduceMotion else { return }

        echoScale = 1.0
        echoOpacity = 0.6
        bounceScale = 1.0

        withAnimation(.easeOut(duration: 0.4)) {
            echoScale = 1.4
            echoOpacity = 0.0
        }

        withAnimation(.easeOut(duration: 0.2)) {
            bounceScale = 1.08
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.2)) {
                bounceScale = 1.0
            }
        }
    }
}
