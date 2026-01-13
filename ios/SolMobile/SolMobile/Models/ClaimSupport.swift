//
//  ClaimSupport.swift
//  SolMobile
//
//  Evidence: Support for claims (url_capture or text_snippet)
//

import Foundation
import SwiftData

enum ClaimSupportType: String, Codable {
    case urlCapture = "url_capture"
    case textSnippet = "text_snippet"
}

@Model
final class ClaimSupport {
    @Attribute(.unique) var supportId: String
    private(set) var typeRaw: String
    private(set) var captureId: String? // Required for url_capture, forbidden for text_snippet
    private(set) var snippetText: String? // Required for text_snippet, forbidden for url_capture
    var snippetHash: String?
    var createdAt: Date
    
    // Relationship to Capture (for url_capture type only)
    var capture: Capture?
    
    // Owner: Message owns this support
    var message: Message
    
    init(
        supportId: String,
        type: ClaimSupportType,
        captureId: String? = nil,
        snippetText: String? = nil,
        snippetHash: String? = nil,
        createdAt: Date = Date(),
        message: Message
    ) throws {
        self.supportId = supportId
        self.typeRaw = type.rawValue
        let trimmedSnippet = snippetText.map { String($0.prefix(EvidenceBounds.maxSnippetLength)) }
        try ClaimSupport.validate(
            supportId: supportId,
            type: type,
            captureId: captureId,
            snippetText: trimmedSnippet
        )
        self.captureId = captureId
        self.snippetText = trimmedSnippet
        self.snippetHash = snippetHash
        self.createdAt = createdAt
        self.message = message
    }

    var type: ClaimSupportType {
        get {
            ClaimSupportType(rawValue: typeRaw) ?? .textSnippet
        }
    }

    func setUrlCapture(captureId: String) throws {
        try ClaimSupport.validate(
            supportId: supportId,
            type: .urlCapture,
            captureId: captureId,
            snippetText: nil
        )
        typeRaw = ClaimSupportType.urlCapture.rawValue
        self.captureId = captureId
        self.snippetText = nil
    }

    func setTextSnippet(snippetText: String, snippetHash: String? = nil) throws {
        let trimmedSnippet = String(snippetText.prefix(EvidenceBounds.maxSnippetLength))
        try ClaimSupport.validate(
            supportId: supportId,
            type: .textSnippet,
            captureId: nil,
            snippetText: trimmedSnippet
        )
        typeRaw = ClaimSupportType.textSnippet.rawValue
        captureId = nil
        self.snippetText = trimmedSnippet
        self.snippetHash = snippetHash
    }

    private static func validate(
        supportId: String,
        type: ClaimSupportType,
        captureId: String?,
        snippetText: String?
    ) throws {
        switch type {
        case .urlCapture:
            guard let captureId, !captureId.isEmpty else {
                throw EvidenceValidationError.missingCaptureId(supportId: supportId)
            }
            if snippetText != nil {
                throw EvidenceValidationError.forbiddenSnippetText(supportId: supportId)
            }
        case .textSnippet:
            guard let snippetText, !snippetText.isEmpty else {
                throw EvidenceValidationError.missingSnippetText(supportId: supportId)
            }
            if captureId != nil {
                throw EvidenceValidationError.forbiddenCaptureId(supportId: supportId)
            }
        }
    }
}

// Codable for JSON encoding/decoding (camelCase)
extension ClaimSupport: Codable {
    enum CodingKeys: String, CodingKey {
        case supportId
        case type
        case captureId
        case snippetText
        case snippetHash
        case createdAt
    }
    
    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let supportId = try container.decode(String.self, forKey: .supportId)
        let typeRaw = try container.decode(String.self, forKey: .type)
        let captureId = try container.decodeIfPresent(String.self, forKey: .captureId)
        let snippetText = try container.decodeIfPresent(String.self, forKey: .snippetText)
        let snippetHash = try container.decodeIfPresent(String.self, forKey: .snippetHash)
        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        
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
        
        guard let type = ClaimSupportType(rawValue: typeRaw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Invalid type: \(typeRaw)"
            )
        }
        try ClaimSupport.validate(
            supportId: supportId,
            type: type,
            captureId: captureId,
            snippetText: snippetText
        )
        
        // Note: Message must be set after decoding by the parent
        fatalError("ClaimSupport.init(from:) requires Message context - use Message decoding instead")
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try ClaimSupport.validate(
            supportId: supportId,
            type: type,
            captureId: captureId,
            snippetText: snippetText
        )
        
        try container.encode(supportId, forKey: .supportId)
        try container.encode(type.rawValue, forKey: .type)
        switch type {
        case .urlCapture:
            try container.encode(captureId, forKey: .captureId)
        case .textSnippet:
            try container.encode(snippetText, forKey: .snippetText)
        }
        try container.encodeIfPresent(snippetHash, forKey: .snippetHash)
        
        // Encode datetime as ISO8601 string
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: createdAt), forKey: .createdAt)
    }
}
