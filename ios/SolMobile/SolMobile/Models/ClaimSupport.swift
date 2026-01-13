//
//  ClaimSupport.swift
//  SolMobile
//
//  Evidence: Support for claims (url_capture or text_snippet)
//

import Foundation
import SwiftData

@Model
final class ClaimSupport {
    @Attribute(.unique) var supportId: String
    var type: String // "url_capture" or "text_snippet"
    var captureId: String? // Required for url_capture, optional for text_snippet
    var snippetText: String? // Optional for url_capture, required for text_snippet
    var snippetHash: String?
    var createdAt: Date
    
    // Relationship to Capture (for url_capture type only)
    var capture: Capture?
    
    // Owner: Message owns this support
    var message: Message
    
    init(
        supportId: String,
        type: String,
        captureId: String? = nil,
        snippetText: String? = nil,
        snippetHash: String? = nil,
        createdAt: Date = Date(),
        message: Message
    ) {
        self.supportId = supportId
        self.type = type
        self.captureId = captureId
        // Trim snippetText to max length
        self.snippetText = snippetText.map { String($0.prefix(EvidenceBounds.maxSnippetLength)) }
        self.snippetHash = snippetHash
        self.createdAt = createdAt
        self.message = message
        
        // Validation: type-specific requirements
        #if DEBUG
        switch type {
        case "url_capture":
            assert(captureId != nil, "url_capture requires captureId")
        case "text_snippet":
            assert(snippetText != nil, "text_snippet requires snippetText")
        default:
            assertionFailure("Invalid ClaimSupport type: \(type)")
        }
        #endif
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
        let type = try container.decode(String.self, forKey: .type)
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
        
        // Validate type-specific requirements
        switch type {
        case "url_capture":
            guard captureId != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .captureId,
                    in: container,
                    debugDescription: "url_capture requires captureId"
                )
            }
        case "text_snippet":
            guard snippetText != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .snippetText,
                    in: container,
                    debugDescription: "text_snippet requires snippetText"
                )
            }
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Invalid type: \(type)"
            )
        }
        
        // Note: Message must be set after decoding by the parent
        fatalError("ClaimSupport.init(from:) requires Message context - use Message decoding instead")
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Validate type-specific requirements at encode-time
        switch type {
        case "url_capture":
            guard captureId != nil else {
                #if DEBUG
                fatalError("url_capture requires captureId")
                #else
                throw EvidenceValidationError.orphanedCaptureReference(
                    supportId: supportId,
                    captureId: "missing"
                )
                #endif
            }
        case "text_snippet":
            guard snippetText != nil else {
                #if DEBUG
                fatalError("text_snippet requires snippetText")
                #else
                throw EncodingError.invalidValue(
                    self,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "text_snippet requires snippetText"
                    )
                )
                #endif
            }
        default:
            #if DEBUG
            fatalError("Invalid ClaimSupport type: \(type)")
            #else
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Invalid type: \(type)"
                )
            )
            #endif
        }
        
        try container.encode(supportId, forKey: .supportId)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(captureId, forKey: .captureId)
        try container.encodeIfPresent(snippetText, forKey: .snippetText)
        try container.encodeIfPresent(snippetHash, forKey: .snippetHash)
        
        // Encode datetime as ISO8601 string
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: createdAt), forKey: .createdAt)
    }
}
