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
        memoryId: String?,
        rigorLevel: GhostRigorLevel?,
        moodAnchor: MoodAnchor?,
        factNull: Bool,
        onEdit: @escaping () -> Void,
        onForget: @escaping () -> Void
    ) -> GhostCardModel {
        GhostCardModel(
            kind: .memoryArtifact,
            title: title,
            body: body,
            snippet: body,
            memoryId: memoryId,
            rigorLevel: rigorLevel,
            moodAnchor: moodAnchor,
            factNull: factNull,
            hapticKey: memoryId,
            actions: GhostCardActions(
                onEdit: onEdit,
                onForget: onForget
            )
        )
    }

    static func journalCard(
        title: String?,
        body: String?,
        memoryId: String?,
        moodAnchor: MoodAnchor?,
        onAscend: @escaping () async -> Bool,
        onForget: @escaping () -> Void
    ) -> GhostCardModel {
        GhostCardModel(
            kind: .journalMoment,
            title: title,
            body: body,
            snippet: body,
            memoryId: memoryId,
            moodAnchor: moodAnchor,
            hapticKey: memoryId,
            actions: GhostCardActions(
                onForget: onForget,
                onAscend: onAscend
            )
        )
    }

    static func actionCard(
        title: String?,
        body: String?,
        suggestion: CaptureSuggestion?,
        onAddToCalendar: @escaping () -> Void,
        onAddToReminder: @escaping () -> Void
    ) -> GhostCardModel {
        GhostCardModel(
            kind: .actionProposal,
            title: title,
            body: body,
            snippet: body,
            captureSuggestion: suggestion,
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
            kind: .reverieInsight,
            summary: summary,
            actions: GhostCardActions(
                onGoToThread: onGoToThread
            )
        )
    }
}
