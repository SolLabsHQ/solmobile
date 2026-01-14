//
//  EvidenceMapping.swift
//  SolMobile
//
//  DTO → SwiftData Model mapping for Evidence (PR #8)
//

import Foundation
import SwiftData

extension Message {
    /// Map Evidence DTOs to SwiftData models and attach to this message
    /// Must be called on the ModelContext's actor (typically @MainActor)
    ///
    /// - Parameters:
    ///   - evidence: Optional evidence DTO from server response
    ///   - context: ModelContext for creating SwiftData objects
    ///
    /// - Note: Initializes relationship arrays if nil before appending
    func mapAndAttachEvidence(from evidence: EvidenceDTO?, context: ModelContext) {
        guard let evidence = evidence else { return }
        
        // Map Captures
        if let captureDTOs = evidence.captures {
            // Initialize relationship if nil
            if self.captures == nil {
                self.captures = []
            }
            
            for dto in captureDTOs {
                let capture = Capture(
                    captureId: dto.captureId,
                    kind: dto.kind,
                    url: dto.url,
                    capturedAt: ISO8601DateFormatter().date(from: dto.capturedAt) ?? Date(),
                    source: dto.source,
                    message: self
                )
                context.insert(capture)
                self.captures!.append(capture)
            }
        }
        
        // Map Supports
        if let supportDTOs = evidence.supports {
            // Initialize relationship if nil
            if self.supports == nil {
                self.supports = []
            }
            
            for dto in supportDTOs {
                let support = ClaimSupport(
                    supportId: dto.supportId,
                    type: dto.type,
                    createdAt: ISO8601DateFormatter().date(from: dto.createdAt) ?? Date(),
                    captureId: dto.captureId,
                    snippetText: dto.snippetText,
                    message: self
                )
                context.insert(support)
                self.supports!.append(support)
            }
        }
        
        // Map Claims
        if let claimDTOs = evidence.claims {
            // Initialize relationship if nil
            if self.claims == nil {
                self.claims = []
            }
            
            for dto in claimDTOs {
                let claim = ClaimMapEntry(
                    claimId: dto.claimId,
                    claimText: dto.claimText,
                    supportIds: dto.supportIds,
                    createdAt: ISO8601DateFormatter().date(from: dto.createdAt) ?? Date(),
                    message: self
                )
                context.insert(claim)
                self.claims!.append(claim)
            }
        }
    }
}
