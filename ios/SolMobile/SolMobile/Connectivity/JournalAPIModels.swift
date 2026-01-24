//
//  JournalAPIModels.swift
//  SolMobile
//

import Foundation

struct JournalDraftRequest: Codable {
    let requestId: String
    let threadId: String
    let mode: JournalDraftMode
    let evidenceSpan: JournalEvidenceSpan
    let cpbRefs: [JournalDraftCpbRef]?
    let preferences: JournalDraftPreferences?
}

struct JournalDraftCpbRef: Codable {
    let cpbId: String
    let type: JournalDraftCpbType?
}

enum JournalDraftCpbType: String, Codable {
    case journalStyle
}

struct JournalDraftPreferences: Codable {
    let maxLines: Int?
    let includeTagsSuggested: Bool?
}

struct JournalDraftEnvelope: Codable {
    let type: String
    let draftId: String
    let threadId: String
    let mode: JournalDraftMode
    let title: String
    let body: String
    let tagsSuggested: [String]?
    let sourceSpan: JournalDraftSourceSpan
    let meta: JournalDraftMeta
}

struct JournalDraftSourceSpan: Codable {
    let threadId: String
    let startMessageId: String
    let endMessageId: String
}

struct JournalDraftMeta: Codable {
    let usedCpbIds: [String]
    let assumptions: [JournalDraftNote]
    let unknowns: [JournalDraftNote]
    let evidenceBinding: JournalDraftEvidenceBinding
}

struct JournalDraftEvidenceBinding: Codable {
    let sourceSpan: JournalDraftSourceSpan
    let nonInvention: Bool
}

struct JournalDraftNote: Codable {
    let id: String
    let text: String
}
