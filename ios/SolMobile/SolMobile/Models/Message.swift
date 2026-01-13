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
    /// Validate evidence relationships at encode-time
    /// Throws structured errors for orphaned references
    func validateEvidence() throws {
        // Validate counts
        if let captures = captures, captures.count > EvidenceBounds.maxCaptures {
            #if DEBUG
            fatalError("Capture count \(captures.count) exceeds max \(EvidenceBounds.maxCaptures)")
            #else
            throw EvidenceValidationError.captureCountOverflow(
                count: captures.count,
                max: EvidenceBounds.maxCaptures
            )
            #endif
        }
        
        if let supports = supports, supports.count > EvidenceBounds.maxSupports {
            #if DEBUG
            fatalError("Support count \(supports.count) exceeds max \(EvidenceBounds.maxSupports)")
            #else
            throw EvidenceValidationError.supportCountOverflow(
                count: supports.count,
                max: EvidenceBounds.maxSupports
            )
            #endif
        }
        
        if let claims = claims, claims.count > EvidenceBounds.maxClaims {
            #if DEBUG
            fatalError("Claim count \(claims.count) exceeds max \(EvidenceBounds.maxClaims)")
            #else
            throw EvidenceValidationError.claimCountOverflow(
                count: claims.count,
                max: EvidenceBounds.maxClaims
            )
            #endif
        }
        
        // Build captureId and supportId sets for validation
        let captureIds = Set(captures?.map { $0.captureId } ?? [])
        let supportIds = Set(supports?.map { $0.supportId } ?? [])
        
        // Validate url_capture supports reference valid captures
        if let supports = supports {
            for support in supports where support.type == "url_capture" {
                guard let captureId = support.captureId else {
                    #if DEBUG
                    fatalError("url_capture support \(support.supportId) missing captureId")
                    #else
                    throw EvidenceValidationError.orphanedCaptureReference(
                        supportId: support.supportId,
                        captureId: "missing"
                    )
                    #endif
                }
                
                guard captureIds.contains(captureId) else {
                    #if DEBUG
                    fatalError("url_capture support \(support.supportId) references non-existent capture \(captureId)")
                    #else
                    throw EvidenceValidationError.orphanedCaptureReference(
                        supportId: support.supportId,
                        captureId: captureId
                    )
                    #endif
                }
            }
        }
        
        // Validate claims reference valid supports
        if let claims = claims {
            for claim in claims {
                for supportId in claim.supportIds {
                    guard supportIds.contains(supportId) else {
                        #if DEBUG
                        fatalError("Claim \(claim.claimId) references non-existent support \(supportId)")
                        #else
                        throw EvidenceValidationError.orphanedSupportReference(
                            claimId: claim.claimId,
                            supportId: supportId
                        )
                        #endif
                    }
                }
            }
        }
    }
}
