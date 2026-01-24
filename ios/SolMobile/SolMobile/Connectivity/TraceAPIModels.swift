//
//  TraceAPIModels.swift
//  SolMobile
//

import Foundation

struct TraceEventsRequest: Codable {
    let requestId: String
    let localUserUuid: String
    let events: [TraceEvent]
}

enum TraceEvent: Codable {
    case journalOffer(JournalOfferEvent)
    case deviceMuseObservation(DeviceMuseObservation)

    init(from decoder: Decoder) throws {
        if let event = try? JournalOfferEvent(from: decoder) {
            self = .journalOffer(event)
            return
        }
        if let event = try? DeviceMuseObservation(from: decoder) {
            self = .deviceMuseObservation(event)
            return
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown trace event type")
        )
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .journalOffer(let event):
            try event.encode(to: encoder)
        case .deviceMuseObservation(let event):
            try event.encode(to: encoder)
        }
    }
}

enum JournalOfferEventType: String, Codable {
    case journalOfferShown = "journal_offer_shown"
    case journalOfferAccepted = "journal_offer_accepted"
    case journalOfferDeclined = "journal_offer_declined"
    case journalOfferMutedOrTuned = "journal_offer_muted_or_tuned"
    case journalDraftGenerated = "journal_draft_generated"
    case journalEntrySaved = "journal_entry_saved"
    case journalEntryEditedBeforeSave = "journal_entry_edited_before_save"
}

enum JournalOfferUserAction: String, Codable {
    case save
    case edit
    case notNow = "not_now"
    case disableOrTune = "disable_or_tune"
}

struct JournalOfferEvent: Codable {
    let eventId: String
    let eventType: JournalOfferEventType
    let ts: String
    let threadId: String
    let momentId: String
    let evidenceSpan: JournalEvidenceSpan
    let phaseAtOffer: String?
    let modeSelected: JournalDraftMode?
    let userAction: JournalOfferUserAction?
    let cooldownActive: Bool?
    let latencyMs: Int?
    let refs: JournalOfferEventRefs?
    let tuning: JournalOfferEventTuning?
}

struct JournalOfferEventRefs: Codable {
    let cpbId: String?
    let draftId: String?
    let entryId: String?
    let requestId: String?
}

struct JournalOfferEventTuning: Codable {
    let newCooldownMinutes: Int?
    let avoidPeakOverwhelm: Bool?
    let offersEnabled: Bool?
}

enum DeviceMuseSource: String, Codable {
    case appleIntelligence = "apple_intelligence"
}

enum DeviceMusePhaseHint: String, Codable {
    case rising
    case peak
    case downshift
    case settled
}

struct DeviceMuseObservation: Codable {
    let observationId: String
    let ts: String
    let localUserUuid: String
    let threadId: String
    let messageId: String
    let version: String
    let source: DeviceMuseSource
    let detectedType: String
    let intensity: Double
    let confidence: Double
    let phaseHint: DeviceMusePhaseHint?
}
