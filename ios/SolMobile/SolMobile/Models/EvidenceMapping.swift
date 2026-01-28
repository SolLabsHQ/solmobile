//
//  EvidenceMapping.swift
//  SolMobile
//
//  DTO → SwiftData Model mapping for Evidence (PR #8)
//

import Foundation
import SwiftData

enum EvidenceMappingError: Error {
    case invalidCaptureTimestamp(captureId: String, value: String)
    case invalidSupportTimestamp(supportId: String, value: String)
    case invalidClaimTimestamp(claimId: String, value: String)
}

extension Message {
    /// Build Evidence models from DTOs without inserting them.
    /// Must be called on the ModelContext's actor (typically @MainActor).
    func buildEvidenceModels(from evidence: EvidenceDTO?) throws -> (
        captures: [Capture],
        supports: [ClaimSupport],
        claims: [ClaimMapEntry]
    ) {
        guard let evidence = evidence else { return ([], [], []) }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var captures: [Capture] = []
        var supports: [ClaimSupport] = []
        var claims: [ClaimMapEntry] = []

        if let captureDTOs = evidence.captures {
            for dto in captureDTOs {
                guard let capturedAt = formatter.date(from: dto.capturedAt) else {
                    throw EvidenceMappingError.invalidCaptureTimestamp(
                        captureId: dto.captureId,
                        value: dto.capturedAt
                    )
                }
                let capture = Capture(
                    captureId: dto.captureId,
                    kind: dto.kind,
                    url: dto.url,
                    capturedAt: capturedAt,
                    title: dto.title,
                    source: normalizeCaptureSource(dto.source),
                    message: self
                )
                captures.append(capture)
            }
        }

        if let supportDTOs = evidence.supports {
            for dto in supportDTOs {
                guard let createdAt = formatter.date(from: dto.createdAt) else {
                    throw EvidenceMappingError.invalidSupportTimestamp(
                        supportId: dto.supportId,
                        value: dto.createdAt
                    )
                }
                guard let type = ClaimSupportType(rawValue: dto.type) else {
                    throw EvidenceValidationError.invalidSupportType(
                        supportId: dto.supportId,
                        type: dto.type
                    )
                }
                let support = try ClaimSupport(
                    supportId: dto.supportId,
                    type: type,
                    captureId: dto.captureId,
                    snippetText: dto.snippetText,
                    snippetHash: dto.snippetHash,
                    createdAt: createdAt,
                    message: self
                )
                supports.append(support)
            }
        }

        if let claimDTOs = evidence.claims {
            for dto in claimDTOs {
                guard let createdAt = formatter.date(from: dto.createdAt) else {
                    throw EvidenceMappingError.invalidClaimTimestamp(
                        claimId: dto.claimId,
                        value: dto.createdAt
                    )
                }
                let claim = try ClaimMapEntry(
                    claimId: dto.claimId,
                    claimText: dto.claimText,
                    supportIds: dto.supportIds,
                    createdAt: createdAt,
                    message: self
                )
                claims.append(claim)
            }
        }

        return (captures, supports, claims)
    }
}

nonisolated private func normalizeCaptureSource(_ source: String) -> String {
    switch source {
    case "user_provided":
        return "user_provided"
    case "auto_detected", "auto_extracted":
        return "auto_detected"
    default:
        return "auto_detected"
    }
}
