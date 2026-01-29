//
//  OutputEnvelopeStorageTests.swift
//  SolMobile
//

import XCTest
import SwiftData
@testable import SolMobile

@MainActor
final class OutputEnvelopeStorageTests: XCTestCase {

    @MainActor
    func test_applyOutputEnvelopeMeta_storesClaimsJsonAndScalars() throws {
        let schema = Schema([ConversationThread.self, Message.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)

        let thread = ConversationThread(title: "OutputEnvelope")
        ctx.insert(thread)

        let message = Message(thread: thread, creatorType: .assistant, text: "Hello")
        ctx.insert(message)

        let claim = OutputEnvelopeClaimDTO(
            claimId: "cl-1",
            claimText: "A claim",
            evidenceRefs: [
                OutputEnvelopeEvidenceRefDTO(evidenceId: "ev-2", spanId: nil),
                OutputEnvelopeEvidenceRefDTO(evidenceId: "ev-1", spanId: "sp-1")
            ]
        )
        let meta = OutputEnvelopeMetaDTO(
            metaVersion: "v1",
            claims: [claim],
            usedEvidenceIds: ["ev-2", "ev-1"],
            evidencePackId: "pack-1"
        )
        let envelope = OutputEnvelopeDTO(assistantText: "Hello", notificationPolicy: nil, meta: meta)

        message.applyOutputEnvelopeMeta(envelope)

        XCTAssertEqual(message.evidenceMetaVersion, "v1")
        XCTAssertEqual(message.evidencePackId, "pack-1")
        XCTAssertEqual(message.usedEvidenceIdsCsv, "ev-1,ev-2")
        XCTAssertEqual(message.claimsCount, 1)
        XCTAssertFalse(message.claimsTruncated)
        XCTAssertNotNil(message.claimsJson)

        let decoded = try JSONDecoder().decode([OutputEnvelopeClaimDTO].self, from: message.claimsJson ?? Data())
        XCTAssertEqual(decoded.first?.claimId, "cl-1")
    }

    @MainActor
    func test_applyOutputEnvelopeMeta_truncatesOversizedClaimsJson() throws {
        let schema = Schema([ConversationThread.self, Message.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)

        let thread = ConversationThread(title: "OutputEnvelope")
        ctx.insert(thread)

        let message = Message(thread: thread, creatorType: .assistant, text: "Hello")
        ctx.insert(message)

        let bigText = String(repeating: "a", count: Message.maxClaimsJsonBytes + 1024)
        let claim = OutputEnvelopeClaimDTO(
            claimId: "cl-oversize",
            claimText: bigText,
            evidenceRefs: [OutputEnvelopeEvidenceRefDTO(evidenceId: "ev-1", spanId: nil)]
        )
        let meta = OutputEnvelopeMetaDTO(
            metaVersion: "v1",
            claims: [claim],
            usedEvidenceIds: ["ev-1"],
            evidencePackId: "pack-1"
        )
        let envelope = OutputEnvelopeDTO(assistantText: "Hello", notificationPolicy: nil, meta: meta)

        message.applyOutputEnvelopeMeta(envelope)

        XCTAssertEqual(message.claimsCount, 1)
        XCTAssertTrue(message.claimsTruncated)
        XCTAssertNil(message.claimsJson)
    }

    @MainActor
    func test_applyOutputEnvelopeMeta_storesCaptureSuggestion() throws {
        let schema = Schema([ConversationThread.self, Message.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)

        let thread = ConversationThread(title: "OutputEnvelope")
        ctx.insert(thread)

        let message = Message(thread: thread, creatorType: .assistant, text: "Hello", transmissionId: "tx-1")
        ctx.insert(message)

        let suggestion = CaptureSuggestion(
            suggestionId: nil,
            suggestionType: .journalEntry,
            title: "Reflection",
            body: "Write it down.",
            suggestedDate: "2026-01-17",
            suggestedStartAt: nil
        )
        let meta = OutputEnvelopeMetaDTO(
            metaVersion: "v1",
            claims: nil,
            usedEvidenceIds: nil,
            evidencePackId: nil,
            captureSuggestion: suggestion
        )
        let envelope = OutputEnvelopeDTO(assistantText: "Hello", notificationPolicy: nil, meta: meta)

        message.applyOutputEnvelopeMeta(envelope)

        XCTAssertEqual(message.captureSuggestionId, "cap_tx-1")
        XCTAssertEqual(message.captureSuggestionTypeRaw, "journal_entry")
        XCTAssertEqual(message.captureSuggestionTitle, "Reflection")
        XCTAssertNotNil(message.captureSuggestionJson)

        let decoded = try JSONDecoder().decode(CaptureSuggestion.self, from: message.captureSuggestionJson ?? Data())
        XCTAssertEqual(decoded.suggestionType, .journalEntry)
        XCTAssertEqual(decoded.suggestionId, "cap_tx-1")
    }
}
