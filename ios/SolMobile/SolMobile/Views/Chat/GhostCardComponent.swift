//
//  GhostCardComponent.swift
//  SolMobile
//

import SwiftUI
import UIKit

enum GhostCardType: String, Codable {
    case memory
    case action
    case reverie
}

struct GhostCardActions {
    var onEdit: (() -> Void)?
    var onForget: (() -> Void)?
    var onAddToCalendar: (() -> Void)?
    var onAddToReminder: (() -> Void)?
    var onGoToThread: (() -> Void)?

    init(
        onEdit: (() -> Void)? = nil,
        onForget: (() -> Void)? = nil,
        onAddToCalendar: (() -> Void)? = nil,
        onAddToReminder: (() -> Void)? = nil,
        onGoToThread: (() -> Void)? = nil
    ) {
        self.onEdit = onEdit
        self.onForget = onForget
        self.onAddToCalendar = onAddToCalendar
        self.onAddToReminder = onAddToReminder
        self.onGoToThread = onGoToThread
    }
}

struct GhostCardModel: Identifiable {
    let id: UUID
    let type: GhostCardType
    let title: String?
    let body: String?
    let summary: String?
    let actions: GhostCardActions

    init(
        id: UUID = UUID(),
        type: GhostCardType,
        title: String? = nil,
        body: String? = nil,
        summary: String? = nil,
        actions: GhostCardActions = GhostCardActions()
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.summary = summary
        self.actions = actions
    }
}

struct GhostCardComponent: View {
    let card: GhostCardModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = card.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
            }

            if let bodyText = resolvedBody, !bodyText.isEmpty {
                Text(bodyText)
                    .font(card.type == .reverie ? .body : .subheadline)
                    .foregroundStyle(.secondary)
            }

            actionRow
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accentTint)
        )
        .opacity(isVisible ? 1.0 : 0.0)
        .scaleEffect(isVisible ? 1.0 : 0.98)
        .animation(.easeOut(duration: 1.2), value: isVisible)
        .onAppear {
            guard !isVisible else { return }
            isVisible = true
            GhostCardHaptics.heartbeat()
        }
    }

    private var resolvedBody: String? {
        switch card.type {
        case .reverie:
            return card.summary ?? card.body ?? card.title
        case .memory, .action:
            return card.body ?? card.summary
        }
    }

    private var accentTint: Color {
        let base = Color.accentColor
        let opacity = colorScheme == .dark ? 0.08 : 0.05
        return base.opacity(opacity)
    }

    @ViewBuilder
    private var actionRow: some View {
        switch card.type {
        case .memory:
            HStack(spacing: 12) {
                if let onEdit = card.actions.onEdit {
                    Button("Edit", action: onEdit)
                }
                if let onForget = card.actions.onForget {
                    Button("Forget", role: .destructive, action: onForget)
                }
            }
        case .action:
            Menu {
                if let onAddToCalendar = card.actions.onAddToCalendar {
                    Button("Add to Calendar", action: onAddToCalendar)
                }
                if let onAddToReminder = card.actions.onAddToReminder {
                    Button("Add Reminder", action: onAddToReminder)
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        case .reverie:
            if let onGoToThread = card.actions.onGoToThread {
                Button("Go to Thread", action: onGoToThread)
            }
        }
    }
}

private enum GhostCardHaptics {
    static func heartbeat() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            generator.impactOccurred(intensity: 0.9)
        }
    }
}
