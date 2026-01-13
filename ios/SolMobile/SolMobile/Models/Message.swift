//
//  Message.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/22/25.
//

import Foundation
import SwiftData

@Model
final class Message {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var creatorTypeRaw: String
    var text: String

    var thread: ConversationThread
    
    // Evidence ownership (cascade delete)
    @Relationship(deleteRule: .cascade, inverse: \Capture.message)
    var captures: [Capture]?
    
    @Relationship(deleteRule: .cascade, inverse: \ClaimSupport.message)
    var supports: [ClaimSupport]?
    
    @Relationship(deleteRule: .cascade, inverse: \ClaimMapEntry.message)
    var claims: [ClaimMapEntry]?

    init(
        id: UUID = UUID(),
        thread: ConversationThread,
        creatorType: CreatorType,
        text: String,
        createdAt: Date = Date(),
        captures: [Capture]? = nil,
        supports: [ClaimSupport]? = nil,
        claims: [ClaimMapEntry]? = nil
    ) {
        self.id = id
        self.thread = thread
        self.creatorTypeRaw = creatorType.rawValue
        self.text = text
        self.createdAt = createdAt
        self.captures = captures
        self.supports = supports
        self.claims = claims
    }

    var creatorType: CreatorType {
        get { CreatorType(rawValue: creatorTypeRaw) ?? .user }
        set { creatorTypeRaw = newValue.rawValue }
    }
}

// Evidence validation and encoding
extension Message {
    #if DEBUG
    /// True when running under XCTest. Used to avoid trapping on assertionFailure during unit tests.
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }
    #endif

    /// Validate evidence relationships at encode-time
    /// Throws structured errors for orphaned references
    func validateEvidence() throws {
        // Validate counts
        if let captures = captures, captures.count > EvidenceBounds.maxCaptures {
            #if DEBUG
            if !Self.isRunningUnitTests {
                assertionFailure("Capture count \(captures.count) exceeds max \(EvidenceBounds.maxCaptures)")
            }
            #endif
            throw EvidenceValidationError.captureCountOverflow(
                count: captures.count,
                max: EvidenceBounds.maxCaptures
            )
        }

        if let supports = supports, supports.count > EvidenceBounds.maxSupports {
            #if DEBUG
            if !Self.isRunningUnitTests {
                assertionFailure("Support count \(supports.count) exceeds max \(EvidenceBounds.maxSupports)")
            }
            #endif
            throw EvidenceValidationError.supportCountOverflow(
                count: supports.count,
                max: EvidenceBounds.maxSupports
            )
        }

        if let claims = claims, claims.count > EvidenceBounds.maxClaims {
            #if DEBUG
            if !Self.isRunningUnitTests {
                assertionFailure("Claim count \(claims.count) exceeds max \(EvidenceBounds.maxClaims)")
            }
            #endif
            throw EvidenceValidationError.claimCountOverflow(
                count: claims.count,
                max: EvidenceBounds.maxClaims
            )
        }
        
        // Build captureId and supportId sets for validation
        let captureIds = Set(captures?.map { $0.captureId } ?? [])
        let supportIds = Set(supports?.map { $0.supportId } ?? [])
        
        // Validate url_capture supports reference valid captures
        if let supports = supports {
            for support in supports where support.type == .urlCapture {
                guard let captureId = support.captureId else {
                    #if DEBUG
                    if !Self.isRunningUnitTests {
                        assertionFailure("url_capture support \(support.supportId) missing captureId")
                    }
                    #endif
                    throw EvidenceValidationError.missingCaptureId(supportId: support.supportId)
                }

                guard captureIds.contains(captureId) else {
                    #if DEBUG
                    if !Self.isRunningUnitTests {
                        assertionFailure("url_capture support \(support.supportId) references non-existent capture \(captureId)")
                    }
                    #endif
                    throw EvidenceValidationError.orphanedCaptureReference(
                        supportId: support.supportId,
                        captureId: captureId
                    )
                }
            }
        }
        
        // Validate claims reference valid supports
        if let claims = claims {
            for claim in claims {
                for supportId in claim.supportIds {
                    guard supportIds.contains(supportId) else {
                        #if DEBUG
                        if !Self.isRunningUnitTests {
                            assertionFailure("Claim \(claim.claimId) references non-existent support \(supportId)")
                        }
                        #endif
                        throw EvidenceValidationError.orphanedSupportReference(
                            claimId: claim.claimId,
                            supportId: supportId
                        )
                    }
                }
            }
        }
    }
}

// Evidence DTOs (flat payload, contract-aligned)
struct EvidencePayload: Codable {
    let captures: [CaptureDTO]
    let supports: [ClaimSupportDTO]
    let claims: [ClaimMapEntryDTO]
}

struct CaptureDTO: Codable {
    let captureId: String
    let kind: String
    let url: String
    let capturedAt: String
    let title: String?
    let source: String
}

struct ClaimSupportDTO: Codable {
    let supportId: String
    let type: String
    let captureId: String?
    let snippetText: String?
    let snippetHash: String?
    let createdAt: String
}

struct ClaimMapEntryDTO: Codable {
    let claimId: String
    let claimText: String
    let supportIds: [String]
    let createdAt: String
}

struct EvidenceSnapshot: Sendable {
    let captures: [CaptureSnapshot]
    let supports: [ClaimSupportSnapshot]
    let claims: [ClaimMapEntrySnapshot]
}

struct CaptureSnapshot: Sendable {
    let captureId: String
    let kind: String
    let url: String
    let capturedAt: Date
    let title: String?
    let source: String
}

struct ClaimSupportSnapshot: Sendable {
    let supportId: String
    let type: ClaimSupportType
    let captureId: String?
    let snippetText: String?
    let snippetHash: String?
    let createdAt: Date
}

struct ClaimMapEntrySnapshot: Sendable {
    let claimId: String
    let claimText: String
    let supportIds: [String]
    let createdAt: Date
}

extension Message {
    /// Build a value-only snapshot from SwiftData relationships.
    /// Must be called on the owning actor of this model (do not call from Task.detached without hopping).
    func makeEvidenceSnapshot() throws -> EvidenceSnapshot {
        try validateEvidence()

        let captureSnaps = (captures ?? []).map { capture in
            CaptureSnapshot(
                captureId: capture.captureId,
                kind: capture.kind,
                url: capture.url,
                capturedAt: capture.capturedAt,
                title: capture.title,
                source: capture.source
            )
        }

        let supportSnaps = try (supports ?? []).map { support -> ClaimSupportSnapshot in
            switch support.type {
            case .urlCapture:
                guard let captureId = support.captureId else {
                    throw EvidenceValidationError.missingCaptureId(supportId: support.supportId)
                }
                if support.snippetText != nil {
                    throw EvidenceValidationError.forbiddenSnippetText(supportId: support.supportId)
                }
                return ClaimSupportSnapshot(
                    supportId: support.supportId,
                    type: support.type,
                    captureId: captureId,
                    snippetText: nil,
                    snippetHash: support.snippetHash,
                    createdAt: support.createdAt
                )
            case .textSnippet:
                guard let snippetText = support.snippetText else {
                    throw EvidenceValidationError.missingSnippetText(supportId: support.supportId)
                }
                if support.captureId != nil {
                    throw EvidenceValidationError.forbiddenCaptureId(supportId: support.supportId)
                }
                return ClaimSupportSnapshot(
                    supportId: support.supportId,
                    type: support.type,
                    captureId: nil,
                    snippetText: snippetText,
                    snippetHash: support.snippetHash,
                    createdAt: support.createdAt
                )
            }
        }

        let claimSnaps = (claims ?? []).map { claim in
            ClaimMapEntrySnapshot(
                claimId: claim.claimId,
                claimText: claim.claimText,
                supportIds: claim.supportIds,
                createdAt: claim.createdAt
            )
        }

        return EvidenceSnapshot(captures: captureSnaps, supports: supportSnaps, claims: claimSnaps)
    }
}

extension EvidencePayload {
    static func from(snapshot: EvidenceSnapshot) -> EvidencePayload {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let captureDTOs = snapshot.captures.map { capture in
            CaptureDTO(
                captureId: capture.captureId,
                kind: capture.kind,
                url: capture.url,
                capturedAt: formatter.string(from: capture.capturedAt),
                title: capture.title,
                source: capture.source
            )
        }

        let supportDTOs = snapshot.supports.map { support in
            ClaimSupportDTO(
                supportId: support.supportId,
                type: support.type.rawValue,
                captureId: support.captureId,
                snippetText: support.snippetText,
                snippetHash: support.snippetHash,
                createdAt: formatter.string(from: support.createdAt)
            )
        }

        let claimDTOs = snapshot.claims.map { claim in
            ClaimMapEntryDTO(
                claimId: claim.claimId,
                claimText: claim.claimText,
                supportIds: claim.supportIds,
                createdAt: formatter.string(from: claim.createdAt)
            )
        }

        return EvidencePayload(captures: captureDTOs, supports: supportDTOs, claims: claimDTOs)
    }
}

extension Message {
    @available(*, deprecated, message: "Use makeEvidenceSnapshot() on the owning actor, then EvidencePayload.from(snapshot:).")
    func toEvidencePayload() throws -> EvidencePayload {
        let snapshot = try makeEvidenceSnapshot()
        return EvidencePayload.from(snapshot: snapshot)
    }
}
