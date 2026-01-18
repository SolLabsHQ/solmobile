//
//  OutputEnvelope.swift
//  SolMobile
//
//  DTOs for OutputEnvelope v0-min + claim storage helpers (PR #23)
//

import Foundation

struct OutputEnvelopeDTO: Codable {
    let assistantText: String
    let meta: OutputEnvelopeMetaDTO?

    enum CodingKeys: String, CodingKey {
        case assistantText = "assistant_text"
        case meta
    }
}

struct OutputEnvelopeMetaDTO: Codable {
    let metaVersion: String?
    let claims: [OutputEnvelopeClaimDTO]?
    let usedEvidenceIds: [String]?
    let evidencePackId: String?
    let captureSuggestion: CaptureSuggestion?

    enum CodingKeys: String, CodingKey {
        case metaVersion = "meta_version"
        case claims
        case usedEvidenceIds = "used_evidence_ids"
        case evidencePackId = "evidence_pack_id"
        case captureSuggestion = "capture_suggestion"
    }

    init(
        metaVersion: String?,
        claims: [OutputEnvelopeClaimDTO]?,
        usedEvidenceIds: [String]?,
        evidencePackId: String?,
        captureSuggestion: CaptureSuggestion? = nil
    ) {
        self.metaVersion = metaVersion
        self.claims = claims
        self.usedEvidenceIds = usedEvidenceIds
        self.evidencePackId = evidencePackId
        self.captureSuggestion = captureSuggestion
    }
}

struct OutputEnvelopeClaimDTO: Codable {
    let claimId: String
    let claimText: String
    let evidenceRefs: [OutputEnvelopeEvidenceRefDTO]

    enum CodingKeys: String, CodingKey {
        case claimId = "claim_id"
        case claimText = "claim_text"
        case evidenceRefs = "evidence_refs"
    }
}

struct OutputEnvelopeEvidenceRefDTO: Codable {
    let evidenceId: String
    let spanId: String?

    enum CodingKeys: String, CodingKey {
        case evidenceId = "evidence_id"
        case spanId = "span_id"
    }
}

nonisolated struct CaptureSuggestion: Codable, Hashable {
    let suggestionId: String?
    let suggestionType: SuggestionType
    let title: String
    let body: String?
    let suggestedDate: String?
    let suggestedStartAt: String?

    enum SuggestionType: String, Codable {
        case journalEntry = "journal_entry"
        case reminder = "reminder"
        case calendarEvent = "calendar_event"
    }

    enum CodingKeys: String, CodingKey {
        case suggestionId = "suggestion_id"
        case suggestionType = "suggestion_type"
        case title
        case body
        case suggestedDate = "suggested_date"
        case suggestedStartAt = "suggested_start_at"
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

        guard let meta = envelope?.meta else { return }

        evidenceMetaVersion = meta.metaVersion
        evidencePackId = meta.evidencePackId

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
}
