//
//  GhostCardRegistry.swift
//  SolMobile
//

import SwiftUI

enum GhostCardRegistry {
    static func view(for card: GhostCardModel) -> some View {
        GhostCardComponent(card: card)
    }

    static func memoryCard(
        title: String?,
        body: String?,
        onEdit: @escaping () -> Void,
        onForget: @escaping () -> Void
    ) -> GhostCardModel {
        GhostCardModel(
            type: .memory,
            title: title,
            body: body,
            actions: GhostCardActions(
                onEdit: onEdit,
                onForget: onForget
            )
        )
    }

    static func actionCard(
        title: String?,
        body: String?,
        onAddToCalendar: @escaping () -> Void,
        onAddToReminder: @escaping () -> Void
    ) -> GhostCardModel {
        GhostCardModel(
            type: .action,
            title: title,
            body: body,
            actions: GhostCardActions(
                onAddToCalendar: onAddToCalendar,
                onAddToReminder: onAddToReminder
            )
        )
    }

    static func reverieCard(
        summary: String?,
        onGoToThread: @escaping () -> Void
    ) -> GhostCardModel {
        GhostCardModel(
            type: .reverie,
            summary: summary,
            actions: GhostCardActions(
                onGoToThread: onGoToThread
            )
        )
    }
}
