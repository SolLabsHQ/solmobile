//
//  ClaimMapEntry.swift
//  SolMobile
//
//  Evidence: Claim with supporting evidence references
//

import Foundation
import SwiftData

@Model
final class ClaimMapEntry {
    @Attribute(.unique) var claimId: String
    var claimText: String
    var supportIds: [String] // References to ClaimSupport.supportId (max 20)
    var createdAt: Date
    
    // Owner: Message owns this claim
    var message: Message
    
    init(
        claimId: String,
        claimText: String,
        supportIds: [String],
        createdAt: Date = Date(),
        message: Message
    ) throws {
        self.claimId = claimId
        // Trim claimText to max length
        self.claimText = String(claimText.prefix(EvidenceBounds.maxClaimTextLength))
        
        // Enforce supportIds count at model boundary
        if supportIds.count > EvidenceBounds.maxSupportIdsPerClaim {
            throw EvidenceValidationError.supportIdsCountOverflow(
                claimId: claimId,
                count: supportIds.count,
                max: EvidenceBounds.maxSupportIdsPerClaim
            )
        }
        self.supportIds = supportIds
        self.createdAt = createdAt
        self.message = message
    }
}

// Codable for JSON encoding/decoding (camelCase)
extension ClaimMapEntry: Codable {
    enum CodingKeys: String, CodingKey {
        case claimId
        case claimText
        case supportIds
        case createdAt
    }
    
    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let claimId = try container.decode(String.self, forKey: .claimId)
        let claimText = try container.decode(String.self, forKey: .claimText)
        let supportIds = try container.decode([String].self, forKey: .supportIds)
        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        
        // Validate supportIds count
        guard supportIds.count <= EvidenceBounds.maxSupportIdsPerClaim else {
            throw DecodingError.dataCorruptedError(
                forKey: .supportIds,
                in: container,
                debugDescription: "supportIds count \(supportIds.count) exceeds max \(EvidenceBounds.maxSupportIdsPerClaim)"
            )
        }
        
        // Parse ISO8601 datetime
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let createdAt = formatter.date(from: createdAtString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "Invalid ISO8601 datetime"
            )
        }
        
        // Note: Message must be set after decoding by the parent
        fatalError("ClaimMapEntry.init(from:) requires Message context - use Message decoding instead")
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Validate supportIds count at encode-time
        guard supportIds.count <= EvidenceBounds.maxSupportIdsPerClaim else {
            #if DEBUG
            fatalError("supportIds count \(supportIds.count) exceeds max \(EvidenceBounds.maxSupportIdsPerClaim)")
            #else
            throw EvidenceValidationError.supportIdsCountOverflow(
                claimId: claimId,
                count: supportIds.count,
                max: EvidenceBounds.maxSupportIdsPerClaim
            )
            #endif
        }
        
        try container.encode(claimId, forKey: .claimId)
        try container.encode(claimText, forKey: .claimText)
        try container.encode(supportIds, forKey: .supportIds)
        
        // Encode datetime as ISO8601 string
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: createdAt), forKey: .createdAt)
    }
}
