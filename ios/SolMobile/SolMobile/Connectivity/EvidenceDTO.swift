//
//  EvidenceDTO.swift
//  SolMobile
//
//  Evidence DTOs for decoding server responses (PR #7.1 / PR #8)
//

import Foundation

// MARK: - Evidence Summary (always present in response)

struct EvidenceSummaryDTO: Codable {
    let captures: Int
    let supports: Int
    let claims: Int
    let warnings: Int
}

// MARK: - Evidence Warning (fail-open URL handling)

struct EvidenceWarningDTO: Codable {
    let code: String  // invalid_url_format, url_length_overflow, url_count_overflow, unsupported_protocol
    let message: String
    let count: Int?
    let max: Int?
    let urlPreview: String?  // Redacted: host + truncated path, no scheme, no query/fragment
}

// MARK: - Evidence Graph (omitted when none)

struct EvidenceDTO: Codable {
    let captures: [CaptureDTO]?
    let supports: [ClaimSupportDTO]?
    let claims: [ClaimMapEntryDTO]?
}

// MARK: - Capture

struct CaptureDTO: Codable {
    let captureId: String
    let kind: String  // "url"
    let url: String
    let capturedAt: String  // ISO-8601
    let title: String?
    let source: String  // "user_provided" | "auto_detected"
}

// MARK: - ClaimSupport (discriminated union)

struct ClaimSupportDTO: Codable {
    let supportId: String
    let type: String  // "url_capture" | "text_snippet"
    let createdAt: String  // ISO-8601
    
    // url_capture fields
    let captureId: String?
    
    // text_snippet fields
    let snippetText: String?
    let snippetHash: String?
}

// MARK: - ClaimMapEntry

struct ClaimMapEntryDTO: Codable {
    let claimId: String
    let claimText: String
    let supportIds: [String]
    let createdAt: String  // ISO-8601
}
