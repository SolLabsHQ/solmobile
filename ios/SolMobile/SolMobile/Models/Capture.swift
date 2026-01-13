//
//  Capture.swift
//  SolMobile
//
//  Evidence: URL capture metadata
//

import Foundation
import SwiftData

// Bounds constants (match SolServer)
enum EvidenceBounds {
    static let maxCaptures = 25
    static let maxSupports = 50
    static let maxClaims = 50
    static let maxUrlLength = 2048
    static let maxSnippetLength = 10_000
    static let maxClaimTextLength = 2000
    static let maxTitleLength = 256
    static let maxSupportIdsPerClaim = 20
}

// Validation errors (structured, fail closed)
enum EvidenceValidationError: Error, LocalizedError {
    case orphanedCaptureReference(supportId: String, captureId: String)
    case orphanedSupportReference(claimId: String, supportId: String)
    case captureCountOverflow(count: Int, max: Int)
    case supportCountOverflow(count: Int, max: Int)
    case claimCountOverflow(count: Int, max: Int)
    case supportIdsCountOverflow(claimId: String, count: Int, max: Int)
    
    var errorDescription: String? {
        switch self {
        case .orphanedCaptureReference(let supportId, let captureId):
            return "Support \(supportId) references non-existent capture \(captureId)"
        case .orphanedSupportReference(let claimId, let supportId):
            return "Claim \(claimId) references non-existent support \(supportId)"
        case .captureCountOverflow(let count, let max):
            return "Capture count \(count) exceeds maximum \(max)"
        case .supportCountOverflow(let count, let max):
            return "Support count \(count) exceeds maximum \(max)"
        case .claimCountOverflow(let count, let max):
            return "Claim count \(count) exceeds maximum \(max)"
        case .supportIdsCountOverflow(let claimId, let count, let max):
            return "Claim \(claimId) has \(count) supportIds, exceeds maximum \(max)"
        }
    }
}

@Model
final class Capture {
    @Attribute(.unique) var captureId: String
    var kind: String // "url"
    var url: String
    var capturedAt: Date
    var title: String?
    var source: String // "user_provided"
    
    // Inverse relationship: supports that reference this capture
    @Relationship(inverse: \ClaimSupport.capture)
    var supports: [ClaimSupport]?
    
    // Owner: Message owns this capture
    var message: Message
    
    init(
        captureId: String,
        kind: String = "url",
        url: String,
        capturedAt: Date = Date(),
        title: String? = nil,
        source: String = "user_provided",
        message: Message
    ) {
        // Trim url to max length
        self.captureId = captureId
        self.kind = kind
        self.url = String(url.prefix(EvidenceBounds.maxUrlLength))
        self.capturedAt = capturedAt
        self.title = title.map { String($0.prefix(EvidenceBounds.maxTitleLength)) }
        self.source = source
        self.message = message
    }
}

// Codable for JSON encoding/decoding (camelCase)
extension Capture: Codable {
    enum CodingKeys: String, CodingKey {
        case captureId
        case kind
        case url
        case capturedAt
        case title
        case source
    }
    
    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let captureId = try container.decode(String.self, forKey: .captureId)
        let kind = try container.decode(String.self, forKey: .kind)
        let url = try container.decode(String.self, forKey: .url)
        let capturedAtString = try container.decode(String.self, forKey: .capturedAt)
        let title = try container.decodeIfPresent(String.self, forKey: .title)
        let source = try container.decode(String.self, forKey: .source)
        
        // Parse ISO8601 datetime
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let capturedAt = formatter.date(from: capturedAtString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .capturedAt,
                in: container,
                debugDescription: "Invalid ISO8601 datetime"
            )
        }
        
        // Note: Message must be set after decoding by the parent
        // This initializer is for decoding only, not for creating standalone instances
        fatalError("Capture.init(from:) requires Message context - use Message decoding instead")
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(captureId, forKey: .captureId)
        try container.encode(kind, forKey: .kind)
        try container.encode(url, forKey: .url)
        
        // Encode datetime as ISO8601 string
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: capturedAt), forKey: .capturedAt)
        
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(source, forKey: .source)
    }
}
