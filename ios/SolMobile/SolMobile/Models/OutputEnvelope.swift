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

    enum CodingKeys: String, CodingKey {
        case metaVersion = "meta_version"
        case claims
        case usedEvidenceIds = "used_evidence_ids"
        case evidencePackId = "evidence_pack_id"
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

extension Message {
    static let maxClaimsJsonBytes = 32 * 1024

    func applyOutputEnvelopeMeta(_ envelope: OutputEnvelopeDTO?) {
        evidenceMetaVersion = nil
        evidencePackId = nil
        usedEvidenceIdsCsv = nil
        claimsCount = 0
        claimsJson = nil
        claimsTruncated = false

        guard let meta = envelope?.meta else { return }

        evidenceMetaVersion = meta.metaVersion
        evidencePackId = meta.evidencePackId

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
}
