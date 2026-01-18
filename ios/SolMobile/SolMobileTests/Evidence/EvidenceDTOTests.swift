//
//  EvidenceDTOTests.swift
//  SolMobileTests
//
//  Tests for Evidence DTO decoding and mapping (PR #8)
//

import XCTest
import SwiftData
@testable import SolMobile

final class EvidenceDTOTests: XCTestCase {
    
    func testEvidenceSummaryDecoding() throws {
        let json = """
        {
            "captures": 2,
            "supports": 3,
            "claims": 1,
            "warnings": 0
        }
        """
        
        let data = json.data(using: .utf8)!
        let summary = try JSONDecoder().decode(EvidenceSummaryDTO.self, from: data)
        
        XCTAssertEqual(summary.captures, 2)
        XCTAssertEqual(summary.supports, 3)
        XCTAssertEqual(summary.claims, 1)
        XCTAssertEqual(summary.warnings, 0)
    }
    
    func testEvidenceWarningDecoding() throws {
        let json = """
        {
            "code": "url_length_overflow",
            "message": "1 URL exceeded max length",
            "count": 3000,
            "max": 2048,
            "urlPreview": "example.com/very/long/path/..."
        }
        """
        
        let data = json.data(using: .utf8)!
        let warning = try JSONDecoder().decode(EvidenceWarningDTO.self, from: data)
        
        XCTAssertEqual(warning.code, "url_length_overflow")
        XCTAssertEqual(warning.message, "1 URL exceeded max length")
        XCTAssertEqual(warning.count, 3000)
        XCTAssertEqual(warning.max, 2048)
        XCTAssertEqual(warning.urlPreview, "example.com/very/long/path/...")
    }
    
    func testCaptureDTODecoding() throws {
        let json = """
        {
            "captureId": "cap-1",
            "kind": "url",
            "url": "https://example.com",
            "capturedAt": "2026-01-13T10:00:00Z",
            "title": "Example",
            "source": "user_provided"
        }
        """
        
        let data = json.data(using: .utf8)!
        let capture = try JSONDecoder().decode(CaptureDTO.self, from: data)
        
        XCTAssertEqual(capture.captureId, "cap-1")
        XCTAssertEqual(capture.kind, "url")
        XCTAssertEqual(capture.url, "https://example.com")
        XCTAssertEqual(capture.title, "Example")
        XCTAssertEqual(capture.source, "user_provided")
    }
    
    func testClaimSupportDTODecoding_URLCapture() throws {
        let json = """
        {
            "supportId": "sup-1",
            "type": "url_capture",
            "createdAt": "2026-01-13T10:00:00Z",
            "captureId": "cap-1"
        }
        """
        
        let data = json.data(using: .utf8)!
        let support = try JSONDecoder().decode(ClaimSupportDTO.self, from: data)
        
        XCTAssertEqual(support.supportId, "sup-1")
        XCTAssertEqual(support.type, "url_capture")
        XCTAssertEqual(support.captureId, "cap-1")
        XCTAssertNil(support.snippetText)
    }
    
    func testClaimSupportDTODecoding_TextSnippet() throws {
        let json = """
        {
            "supportId": "sup-2",
            "type": "text_snippet",
            "createdAt": "2026-01-13T10:00:00Z",
            "snippetText": "This is a text snippet",
            "snippetHash": "hash-123"
        }
        """
        
        let data = json.data(using: .utf8)!
        let support = try JSONDecoder().decode(ClaimSupportDTO.self, from: data)
        
        XCTAssertEqual(support.supportId, "sup-2")
        XCTAssertEqual(support.type, "text_snippet")
        XCTAssertEqual(support.snippetText, "This is a text snippet")
        XCTAssertEqual(support.snippetHash, "hash-123")
        XCTAssertNil(support.captureId)
    }
    
    func testClaimMapEntryDTODecoding() throws {
        let json = """
        {
            "claimId": "claim-1",
            "claimText": "This is a claim",
            "supportIds": ["sup-1", "sup-2"],
            "createdAt": "2026-01-13T10:00:00Z"
        }
        """
        
        let data = json.data(using: .utf8)!
        let claim = try JSONDecoder().decode(ClaimMapEntryDTO.self, from: data)
        
        XCTAssertEqual(claim.claimId, "claim-1")
        XCTAssertEqual(claim.claimText, "This is a claim")
        XCTAssertEqual(claim.supportIds, ["sup-1", "sup-2"])
    }
    
    func testResponseDecoding_WithEvidence() throws {
        let json = """
        {
            "ok": true,
            "transmissionId": "tx-123",
            "assistant": "Here's the answer",
            "evidenceSummary": {
                "captures": 1,
                "supports": 1,
                "claims": 0,
                "warnings": 0
            },
            "evidence": {
                "captures": [{
                    "captureId": "cap-1",
                    "kind": "url",
                    "url": "https://example.com",
                    "capturedAt": "2026-01-13T10:00:00Z",
                    "source": "auto_detected"
                }],
                "supports": [{
                    "supportId": "sup-1",
                    "type": "url_capture",
                    "createdAt": "2026-01-13T10:00:00Z",
                    "captureId": "cap-1"
                }]
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(Response.self, from: data)
        
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.transmissionId, "tx-123")
        XCTAssertEqual(response.assistant, "Here's the answer")
        
        XCTAssertEqual(response.evidenceSummary.captures, 1)
        XCTAssertEqual(response.evidenceSummary.supports, 1)
        
        XCTAssertNotNil(response.evidence)
        XCTAssertEqual(response.evidence?.captures?.count, 1)
        XCTAssertEqual(response.evidence?.supports?.count, 1)
    }

    func testResponseDecoding_WithOutputEnvelopeClaims() throws {
        let json = """
        {
            "ok": true,
            "transmissionId": "tx-456",
            "assistant": "Hello",
            "outputEnvelope": {
                "assistant_text": "Hello",
                "meta": {
                    "meta_version": "v1",
                    "evidence_pack_id": "pack-1",
                    "used_evidence_ids": ["ev-1", "ev-2"],
                    "claims": [{
                        "claim_id": "cl-1",
                        "claim_text": "A claim",
                        "evidence_refs": [{
                            "evidence_id": "ev-1",
                            "span_id": "sp-1"
                        }]
                    }]
                }
            },
            "evidenceSummary": {
                "captures": 0,
                "supports": 0,
                "claims": 0,
                "warnings": 0
            }
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(Response.self, from: data)

        XCTAssertEqual(response.outputEnvelope?.assistantText, "Hello")
        XCTAssertEqual(response.outputEnvelope?.meta?.metaVersion, "v1")
        XCTAssertEqual(response.outputEnvelope?.meta?.evidencePackId, "pack-1")
        XCTAssertEqual(response.outputEnvelope?.meta?.usedEvidenceIds, ["ev-1", "ev-2"])
        XCTAssertEqual(response.outputEnvelope?.meta?.claims?.count, 1)
        XCTAssertEqual(response.outputEnvelope?.meta?.claims?.first?.claimId, "cl-1")
    }
}
