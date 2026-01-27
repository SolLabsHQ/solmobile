//
//  GhostCardMetadata.swift
//  SolMobile
//

import Foundation

enum GhostKind: String, Codable, CaseIterable {
    case memoryArtifact = "memory_artifact"
    case journalMoment = "journal_moment"
    case actionProposal = "action_proposal"
    case reverieInsight = "reverie_insight"
    case conflictResolver = "conflict_resolver"
    case evidenceReceipt = "evidence_receipt"

    static func resolve(ghostKindRaw: String?, ghostTypeRaw: String?) -> GhostKind? {
        if let kind = ghostKindRaw, let resolved = GhostKind(rawValue: kind) {
            return resolved
        }

        guard let legacy = ghostTypeRaw?.lowercased() else { return nil }
        switch legacy {
        case "memory":
            return .memoryArtifact
        case "journal":
            return .journalMoment
        case "action":
            return .actionProposal
        case "reverie":
            return .reverieInsight
        case "conflict":
            return .conflictResolver
        case "evidence":
            return .evidenceReceipt
        default:
            return nil
        }
    }

    static func fromMemoryType(_ raw: String?) -> GhostKind? {
        guard let raw = raw?.lowercased() else { return nil }
        switch raw {
        case "memory":
            return .memoryArtifact
        case "journal":
            return .journalMoment
        case "action":
            return .actionProposal
        default:
            return nil
        }
    }
}

enum GhostRigorLevel: String {
    case normal
    case high
}

struct GhostCTAState {
    let canEdit: Bool
    let canForget: Bool
    let requiresConfirm: Bool
}

enum MoodAnchor: String {
    case breakthrough
    case resolve
    case nostalgia
    case standardFact = "standard_fact"
    case insight

    var intensity: Double {
        switch self {
        case .breakthrough:
            return 1.0
        case .resolve:
            return 0.9
        case .nostalgia:
            return 0.4
        case .standardFact:
            return 0.5
        case .insight:
            return 0.65
        }
    }
}

extension Message {
    var ghostKind: GhostKind? {
        GhostKind.resolve(ghostKindRaw: ghostKindRaw, ghostTypeRaw: ghostTypeRaw)
    }

    var isAscendEligible: Bool {
        ghostKindRaw == GhostKind.journalMoment.rawValue
    }

    var ghostRigorLevel: GhostRigorLevel? {
        guard let raw = ghostRigorLevelRaw else { return nil }
        return GhostRigorLevel(rawValue: raw)
    }

    var moodAnchor: MoodAnchor? {
        guard let raw = ghostMoodAnchor?.lowercased() else { return nil }
        return MoodAnchor(rawValue: raw)
    }

    var isGhostCard: Bool {
        guard ghostKind != nil else { return false }
        if ghostDisplayHint == "ghost_card" {
            return true
        }
        #if DEBUG
        if !Message.isRunningUnitTests {
            assertionFailure("ghost_kind present without display_hint=ghost_card")
        }
        #endif
        return true
    }

    var ghostCTAState: GhostCTAState {
        let hasMemoryId = ghostMemoryId?.isEmpty == false
        let isManualEntry = ghostFactNull
        let canEdit = hasMemoryId || isManualEntry
        let canForget = hasMemoryId && !isManualEntry
        let requiresConfirm = ghostRigorLevel == .high
        return GhostCTAState(
            canEdit: canEdit,
            canForget: canForget,
            requiresConfirm: requiresConfirm
        )
    }
}
