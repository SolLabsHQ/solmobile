//
//  OutputEnvelope.swift
//  SolMobile
//
//  DTOs for OutputEnvelope v0-min + claim storage helpers (PR #23)
//

import Foundation

struct OutputEnvelopeDTO: Codable {
    let assistantText: String
    let notificationPolicy: String?
    let meta: OutputEnvelopeMetaDTO?

    init(assistantText: String, notificationPolicy: String?, meta: OutputEnvelopeMetaDTO?) {
        self.assistantText = assistantText
        self.notificationPolicy = notificationPolicy
        self.meta = meta
    }

    enum CodingKeys: String, CodingKey {
        case assistantText
        case notificationPolicy
        case meta
    }

    enum LegacyCodingKeys: String, CodingKey {
        case assistantText = "assistant_text"
        case notificationPolicy = "notification_policy"
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)

        if let value = try container.decodeIfPresent(String.self, forKey: .assistantText) {
            assistantText = value
        } else if let value = try legacy.decodeIfPresent(String.self, forKey: .assistantText) {
            assistantText = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.assistantText,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing assistantText")
            )
        }

        notificationPolicy = try container.decodeIfPresent(String.self, forKey: .notificationPolicy)
            ?? legacy.decodeIfPresent(String.self, forKey: .notificationPolicy)
        meta = try container.decodeIfPresent(OutputEnvelopeMetaDTO.self, forKey: .meta)
            ?? legacy.decodeIfPresent(OutputEnvelopeMetaDTO.self, forKey: .meta)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(assistantText, forKey: .assistantText)
        try container.encodeIfPresent(notificationPolicy, forKey: .notificationPolicy)
        try container.encodeIfPresent(meta, forKey: .meta)
    }
}

struct OutputEnvelopeMetaDTO: Codable {
    let metaVersion: String?
    let claims: [OutputEnvelopeClaimDTO]?
    let usedEvidenceIds: [String]?
    let evidencePackId: String?
    let captureSuggestion: CaptureSuggestion?
    let displayHint: String?
    let ghostKind: String?
    let ghostType: String?
    let memoryId: String?
    let triggerMessageId: String?
    let rigorLevel: String?
    let snippet: String?
    let factNull: Bool?
    let moodAnchor: String?
    let journalOffer: JournalOffer?
    let lattice: LatticeMetaDTO?

    enum CodingKeys: String, CodingKey {
        case metaVersion
        case claims
        case usedEvidenceIds
        case evidencePackId
        case captureSuggestion
        case displayHint
        case ghostKind
        case ghostType
        case memoryId
        case triggerMessageId
        case rigorLevel
        case snippet
        case factNull
        case moodAnchor
        case journalOffer
        case lattice
    }

    enum LegacyCodingKeys: String, CodingKey {
        case metaVersion = "meta_version"
        case claims
        case usedEvidenceIds = "used_evidence_ids"
        case evidencePackId = "evidence_pack_id"
        case captureSuggestion = "capture_suggestion"
        case displayHint = "display_hint"
        case ghostKind = "ghost_kind"
        case ghostType = "ghost_type"
        case memoryId = "memory_id"
        case triggerMessageId = "trigger_message_id"
        case rigorLevel = "rigor_level"
        case snippet
        case factNull = "fact_null"
        case moodAnchor = "mood_anchor"
        case journalOffer = "journal_offer"
        case lattice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)

        func decodeIfPresent<T: Decodable>(_ type: T.Type, key: CodingKeys, legacyKey: LegacyCodingKeys) -> T? {
            return (try? container.decodeIfPresent(T.self, forKey: key))
                ?? (try? legacy.decodeIfPresent(T.self, forKey: legacyKey))
        }

        metaVersion = decodeIfPresent(String.self, key: .metaVersion, legacyKey: .metaVersion)
        claims = decodeIfPresent([OutputEnvelopeClaimDTO].self, key: .claims, legacyKey: .claims)
        usedEvidenceIds = decodeIfPresent([String].self, key: .usedEvidenceIds, legacyKey: .usedEvidenceIds)
        evidencePackId = decodeIfPresent(String.self, key: .evidencePackId, legacyKey: .evidencePackId)
        captureSuggestion = decodeIfPresent(CaptureSuggestion.self, key: .captureSuggestion, legacyKey: .captureSuggestion)
        displayHint = decodeIfPresent(String.self, key: .displayHint, legacyKey: .displayHint)
        ghostKind = decodeIfPresent(String.self, key: .ghostKind, legacyKey: .ghostKind)
        ghostType = decodeIfPresent(String.self, key: .ghostType, legacyKey: .ghostType)
        memoryId = decodeIfPresent(String.self, key: .memoryId, legacyKey: .memoryId)
        triggerMessageId = decodeIfPresent(String.self, key: .triggerMessageId, legacyKey: .triggerMessageId)
        rigorLevel = decodeIfPresent(String.self, key: .rigorLevel, legacyKey: .rigorLevel)
        snippet = decodeIfPresent(String.self, key: .snippet, legacyKey: .snippet)
        factNull = decodeIfPresent(Bool.self, key: .factNull, legacyKey: .factNull)
        moodAnchor = decodeIfPresent(String.self, key: .moodAnchor, legacyKey: .moodAnchor)
        journalOffer = decodeIfPresent(JournalOffer.self, key: .journalOffer, legacyKey: .journalOffer)
        lattice = decodeIfPresent(LatticeMetaDTO.self, key: .lattice, legacyKey: .lattice)
    }

    init(
        metaVersion: String?,
        claims: [OutputEnvelopeClaimDTO]?,
        usedEvidenceIds: [String]?,
        evidencePackId: String?,
        captureSuggestion: CaptureSuggestion? = nil,
        displayHint: String? = nil,
        ghostKind: String? = nil,
        ghostType: String? = nil,
        memoryId: String? = nil,
        triggerMessageId: String? = nil,
        rigorLevel: String? = nil,
        snippet: String? = nil,
        factNull: Bool? = nil,
        moodAnchor: String? = nil,
        journalOffer: JournalOffer? = nil,
        lattice: LatticeMetaDTO? = nil
    ) {
        self.metaVersion = metaVersion
        self.claims = claims
        self.usedEvidenceIds = usedEvidenceIds
        self.evidencePackId = evidencePackId
        self.captureSuggestion = captureSuggestion
        self.displayHint = displayHint
        self.ghostKind = ghostKind
        self.ghostType = ghostType
        self.memoryId = memoryId
        self.triggerMessageId = triggerMessageId
        self.rigorLevel = rigorLevel
        self.snippet = snippet
        self.factNull = factNull
        self.moodAnchor = moodAnchor
        self.journalOffer = journalOffer
        self.lattice = lattice
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(metaVersion, forKey: .metaVersion)
        try container.encodeIfPresent(claims, forKey: .claims)
        try container.encodeIfPresent(usedEvidenceIds, forKey: .usedEvidenceIds)
        try container.encodeIfPresent(evidencePackId, forKey: .evidencePackId)
        try container.encodeIfPresent(captureSuggestion, forKey: .captureSuggestion)
        try container.encodeIfPresent(displayHint, forKey: .displayHint)
        try container.encodeIfPresent(ghostKind, forKey: .ghostKind)
        try container.encodeIfPresent(ghostType, forKey: .ghostType)
        try container.encodeIfPresent(memoryId, forKey: .memoryId)
        try container.encodeIfPresent(triggerMessageId, forKey: .triggerMessageId)
        try container.encodeIfPresent(rigorLevel, forKey: .rigorLevel)
        try container.encodeIfPresent(snippet, forKey: .snippet)
        try container.encodeIfPresent(factNull, forKey: .factNull)
        try container.encodeIfPresent(moodAnchor, forKey: .moodAnchor)
        try container.encodeIfPresent(journalOffer, forKey: .journalOffer)
        try container.encodeIfPresent(lattice, forKey: .lattice)
    }
}

struct LatticeMetaDTO: Codable {
    let status: String?
    let retrievalTrace: LatticeRetrievalTraceDTO?
    let scores: [String: LatticeScoreDTO]?
    let counts: LatticeCountsDTO?
    let bytesTotal: Int?
    let timingsMs: LatticeTimingsDTO?
    let warnings: [String]?

    enum CodingKeys: String, CodingKey {
        case status
        case retrievalTrace = "retrieval_trace"
        case scores
        case counts
        case bytesTotal = "bytes_total"
        case timingsMs = "timings_ms"
        case warnings
    }
}

struct LatticeScoreDTO: Codable {
    let method: String?
    let value: Double?
}

struct LatticeRetrievalTraceDTO: Codable {
    let memoryIds: [String]?
    let mementoIds: [String]?
    let policyCapsuleIds: [String]?

    enum CodingKeys: String, CodingKey {
        case memoryIds = "memory_ids"
        case mementoIds = "memento_ids"
        case policyCapsuleIds = "policy_capsule_ids"
    }
}

struct LatticeCountsDTO: Codable {
    let memories: Int?
    let mementos: Int?
    let policyCapsules: Int?
}

struct LatticeTimingsDTO: Codable {
    let latticeTotal: Int?
    let latticeDb: Int?
    let modelTotal: Int?
    let requestTotal: Int?

    enum CodingKeys: String, CodingKey {
        case latticeTotal = "lattice_total"
        case latticeDb = "lattice_db"
        case modelTotal = "model_total"
        case requestTotal = "request_total"
    }
}

struct OutputEnvelopeClaimDTO: Codable {
    let claimId: String
    let claimText: String
    let evidenceRefs: [OutputEnvelopeEvidenceRefDTO]

    init(claimId: String, claimText: String, evidenceRefs: [OutputEnvelopeEvidenceRefDTO]) {
        self.claimId = claimId
        self.claimText = claimText
        self.evidenceRefs = evidenceRefs
    }

    enum CodingKeys: String, CodingKey {
        case claimId
        case claimText
        case evidenceRefs
    }

    enum LegacyCodingKeys: String, CodingKey {
        case claimId = "claim_id"
        case claimText = "claim_text"
        case evidenceRefs = "evidence_refs"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)

        if let value = try container.decodeIfPresent(String.self, forKey: .claimId) {
            claimId = value
        } else if let value = try legacy.decodeIfPresent(String.self, forKey: .claimId) {
            claimId = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.claimId,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing claimId")
            )
        }

        if let value = try container.decodeIfPresent(String.self, forKey: .claimText) {
            claimText = value
        } else if let value = try legacy.decodeIfPresent(String.self, forKey: .claimText) {
            claimText = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.claimText,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing claimText")
            )
        }

        evidenceRefs = try container.decodeIfPresent([OutputEnvelopeEvidenceRefDTO].self, forKey: .evidenceRefs)
            ?? legacy.decodeIfPresent([OutputEnvelopeEvidenceRefDTO].self, forKey: .evidenceRefs)
            ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(claimId, forKey: .claimId)
        try container.encode(claimText, forKey: .claimText)
        try container.encode(evidenceRefs, forKey: .evidenceRefs)
    }
}

struct OutputEnvelopeEvidenceRefDTO: Codable {
    let evidenceId: String
    let spanId: String?

    init(evidenceId: String, spanId: String?) {
        self.evidenceId = evidenceId
        self.spanId = spanId
    }

    enum CodingKeys: String, CodingKey {
        case evidenceId
        case spanId
    }

    enum LegacyCodingKeys: String, CodingKey {
        case evidenceId = "evidence_id"
        case spanId = "span_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)

        if let value = try container.decodeIfPresent(String.self, forKey: .evidenceId) {
            evidenceId = value
        } else if let value = try legacy.decodeIfPresent(String.self, forKey: .evidenceId) {
            evidenceId = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.evidenceId,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing evidenceId")
            )
        }

        spanId = try container.decodeIfPresent(String.self, forKey: .spanId)
            ?? legacy.decodeIfPresent(String.self, forKey: .spanId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(evidenceId, forKey: .evidenceId)
        try container.encodeIfPresent(spanId, forKey: .spanId)
    }
}

nonisolated struct CaptureSuggestion: Codable, Hashable {
    let suggestionId: String?
    let suggestionType: SuggestionType
    let title: String
    let body: String?
    let suggestedDate: String?
    let suggestedStartAt: String?

    init(
        suggestionId: String?,
        suggestionType: SuggestionType,
        title: String,
        body: String?,
        suggestedDate: String?,
        suggestedStartAt: String?
    ) {
        self.suggestionId = suggestionId
        self.suggestionType = suggestionType
        self.title = title
        self.body = body
        self.suggestedDate = suggestedDate
        self.suggestedStartAt = suggestedStartAt
    }

    enum SuggestionType: String, Codable {
        case journalEntry = "journal_entry"
        case reminder = "reminder"
        case calendarEvent = "calendar_event"
    }

    enum CodingKeys: String, CodingKey {
        case suggestionId
        case suggestionType
        case title
        case body
        case suggestedDate
        case suggestedStartAt
    }

    enum LegacyCodingKeys: String, CodingKey {
        case suggestionId = "suggestion_id"
        case suggestionType = "suggestion_type"
        case title
        case body
        case suggestedDate = "suggested_date"
        case suggestedStartAt = "suggested_start_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)

        suggestionId = try container.decodeIfPresent(String.self, forKey: .suggestionId)
            ?? legacy.decodeIfPresent(String.self, forKey: .suggestionId)

        if let value = try container.decodeIfPresent(SuggestionType.self, forKey: .suggestionType) {
            suggestionType = value
        } else if let value = try legacy.decodeIfPresent(SuggestionType.self, forKey: .suggestionType) {
            suggestionType = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.suggestionType,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing suggestionType")
            )
        }

        if let value = try container.decodeIfPresent(String.self, forKey: .title) {
            title = value
        } else if let value = try legacy.decodeIfPresent(String.self, forKey: .title) {
            title = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.title,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing title")
            )
        }

        body = try container.decodeIfPresent(String.self, forKey: .body)
            ?? legacy.decodeIfPresent(String.self, forKey: .body)
        suggestedDate = try container.decodeIfPresent(String.self, forKey: .suggestedDate)
            ?? legacy.decodeIfPresent(String.self, forKey: .suggestedDate)
        suggestedStartAt = try container.decodeIfPresent(String.self, forKey: .suggestedStartAt)
            ?? legacy.decodeIfPresent(String.self, forKey: .suggestedStartAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(suggestionId, forKey: .suggestionId)
        try container.encode(suggestionType, forKey: .suggestionType)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(suggestedDate, forKey: .suggestedDate)
        try container.encodeIfPresent(suggestedStartAt, forKey: .suggestedStartAt)
    }
}

extension Message {
    // Guardrail: keep SwiftData row size + decode cost bounded; store scalars when claims blob is too large.
    static let maxClaimsJsonBytes = 32 * 1024

    func applyOutputEnvelopeMeta(_ envelope: OutputEnvelopeDTO?) {
        evidenceMetaVersion = nil
        evidencePackId = nil
        usedEvidenceIdsCsv = nil
        claimsCount = 0
        claimsJson = nil
        claimsTruncated = false
        captureSuggestionJson = nil
        captureSuggestionId = nil
        captureSuggestionTypeRaw = nil
        captureSuggestionTitle = nil
        ghostDisplayHint = nil
        ghostKindRaw = nil
        ghostTypeRaw = nil
        ghostMemoryId = nil
        ghostTriggerMessageId = nil
        ghostRigorLevelRaw = nil
        ghostSnippet = nil
        ghostFactNull = false
        ghostMoodAnchor = nil
        journalOfferJson = nil
        journalOfferShownAt = nil
        latticeStatusRaw = nil
        latticeMemoryIdsCsv = nil

        guard let meta = envelope?.meta else { return }

        evidenceMetaVersion = meta.metaVersion
        evidencePackId = meta.evidencePackId
        ghostDisplayHint = meta.displayHint
        ghostKindRaw = meta.ghostKind
        ghostTypeRaw = meta.ghostType
        ghostMemoryId = meta.memoryId
        ghostTriggerMessageId = meta.triggerMessageId
        ghostRigorLevelRaw = meta.rigorLevel
        ghostSnippet = meta.snippet
        ghostFactNull = meta.factNull ?? false
        ghostMoodAnchor = meta.moodAnchor

        if let offer = meta.journalOffer {
            journalOfferJson = try? JSONEncoder().encode(offer)
        }

        if let lattice = meta.lattice {
            latticeStatusRaw = lattice.status
            if let memoryIds = lattice.retrievalTrace?.memoryIds, !memoryIds.isEmpty {
                latticeMemoryIdsCsv = memoryIds.joined(separator: ",")
            }
        }

        if let suggestion = meta.captureSuggestion {
            let trimmedId = suggestion.suggestionId?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedId = (trimmedId?.isEmpty == false) ? trimmedId : nil
            let fallbackId = resolvedId
                ?? transmissionId.map { "cap_\($0)" }
                ?? "cap_local_\(id.uuidString)"
            let normalized = CaptureSuggestion(
                suggestionId: fallbackId,
                suggestionType: suggestion.suggestionType,
                title: suggestion.title,
                body: suggestion.body,
                suggestedDate: suggestion.suggestedDate,
                suggestedStartAt: suggestion.suggestedStartAt
            )

            captureSuggestionId = fallbackId
            captureSuggestionTypeRaw = suggestion.suggestionType.rawValue
            captureSuggestionTitle = suggestion.title
            captureSuggestionJson = try? JSONEncoder().encode(normalized)
        }

        if let ids = meta.usedEvidenceIds {
            let unique = Array(Set(ids)).sorted()
            usedEvidenceIdsCsv = unique.isEmpty ? nil : unique.joined(separator: ",")
        }

        guard let claims = meta.claims else { return }

        claimsCount = claims.count
        guard !claims.isEmpty else { return }

        do {
            let data = try JSONEncoder().encode(claims)
            if data.count > Self.maxClaimsJsonBytes {
                claimsTruncated = true
                claimsJson = nil
                return
            }
            claimsJson = data
        } catch {
            claimsTruncated = true
            claimsJson = nil
        }
    }

    var captureSuggestion: CaptureSuggestion? {
        guard let data = captureSuggestionJson else { return nil }
        return try? JSONDecoder().decode(CaptureSuggestion.self, from: data)
    }

    var journalOffer: JournalOffer? {
        guard let data = journalOfferJson else { return nil }
        return try? JSONDecoder().decode(JournalOffer.self, from: data)
    }
}
