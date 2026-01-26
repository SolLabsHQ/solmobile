//
//  JournalingModels.swift
//  SolMobile
//

import Foundation

enum JournalDraftMode: String, Codable, CaseIterable {
    case verbatim
    case assist
}

struct JournalEvidenceSpan: Codable, Hashable {
    let startMessageId: String
    let endMessageId: String

    init(startMessageId: String, endMessageId: String) {
        self.startMessageId = startMessageId
        self.endMessageId = endMessageId
    }

    enum CodingKeys: String, CodingKey {
        case startMessageId
        case endMessageId
    }

    enum LegacyCodingKeys: String, CodingKey {
        case startMessageId = "start_message_id"
        case endMessageId = "end_message_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)

        if let value = try container.decodeIfPresent(String.self, forKey: .startMessageId) {
            startMessageId = value
        } else if let value = try legacy.decodeIfPresent(String.self, forKey: .startMessageId) {
            startMessageId = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.startMessageId,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing startMessageId")
            )
        }

        if let value = try container.decodeIfPresent(String.self, forKey: .endMessageId) {
            endMessageId = value
        } else if let value = try legacy.decodeIfPresent(String.self, forKey: .endMessageId) {
            endMessageId = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.endMessageId,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing endMessageId")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startMessageId, forKey: .startMessageId)
        try container.encode(endMessageId, forKey: .endMessageId)
    }
}

struct JournalOffer: Codable, Hashable {
    let momentId: String
    let momentType: String
    let phase: String
    let confidence: String
    let evidenceSpan: JournalEvidenceSpan
    let why: [String]?
    let offerEligible: Bool

    init(
        momentId: String,
        momentType: String,
        phase: String,
        confidence: String,
        evidenceSpan: JournalEvidenceSpan,
        why: [String]?,
        offerEligible: Bool
    ) {
        self.momentId = momentId
        self.momentType = momentType
        self.phase = phase
        self.confidence = confidence
        self.evidenceSpan = evidenceSpan
        self.why = why
        self.offerEligible = offerEligible
    }

    enum CodingKeys: String, CodingKey {
        case momentId
        case momentType
        case phase
        case confidence
        case evidenceSpan
        case why
        case offerEligible
    }

    enum LegacyCodingKeys: String, CodingKey {
        case momentId = "moment_id"
        case momentType = "moment_type"
        case phase
        case confidence
        case evidenceSpan = "evidence_span"
        case why
        case offerEligible = "offer_eligible"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)

        if let value = try container.decodeIfPresent(String.self, forKey: .momentId) {
            momentId = value
        } else if let value = try legacy.decodeIfPresent(String.self, forKey: .momentId) {
            momentId = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.momentId,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing momentId")
            )
        }

        if let value = try container.decodeIfPresent(String.self, forKey: .momentType) {
            momentType = value
        } else if let value = try legacy.decodeIfPresent(String.self, forKey: .momentType) {
            momentType = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.momentType,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing momentType")
            )
        }

        if let value = try container.decodeIfPresent(String.self, forKey: .phase) {
            phase = value
        } else if let value = try legacy.decodeIfPresent(String.self, forKey: .phase) {
            phase = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.phase,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing phase")
            )
        }

        if let value = try container.decodeIfPresent(String.self, forKey: .confidence) {
            confidence = value
        } else if let value = try legacy.decodeIfPresent(String.self, forKey: .confidence) {
            confidence = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.confidence,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing confidence")
            )
        }

        if let value = try container.decodeIfPresent(JournalEvidenceSpan.self, forKey: .evidenceSpan) {
            evidenceSpan = value
        } else if let value = try legacy.decodeIfPresent(JournalEvidenceSpan.self, forKey: .evidenceSpan) {
            evidenceSpan = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.evidenceSpan,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing evidenceSpan")
            )
        }

        why = try container.decodeIfPresent([String].self, forKey: .why)
            ?? legacy.decodeIfPresent([String].self, forKey: .why)

        if let value = try container.decodeIfPresent(Bool.self, forKey: .offerEligible) {
            offerEligible = value
        } else if let value = try legacy.decodeIfPresent(Bool.self, forKey: .offerEligible) {
            offerEligible = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.offerEligible,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing offerEligible")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(momentId, forKey: .momentId)
        try container.encode(momentType, forKey: .momentType)
        try container.encode(phase, forKey: .phase)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(evidenceSpan, forKey: .evidenceSpan)
        try container.encodeIfPresent(why, forKey: .why)
        try container.encode(offerEligible, forKey: .offerEligible)
    }
}

struct JournalOfferRecord: Codable, Hashable {
    let kind: String?
    let offerEligible: Bool
    let evidenceSpan: JournalEvidenceSpan?
    let reasonCodes: [String]?
    let mode: JournalDraftMode?
    let phase: String?
    let risk: String?
    let label: String?
    let intensityBucket: String?
    let momentId: String?
    let momentType: String?
    let confidence: String?
    let why: [String]?

    enum CodingKeys: String, CodingKey {
        case kind
        case offerEligible
        case evidenceSpan
        case reasonCodes
        case mode
        case phase
        case risk
        case label
        case intensityBucket
        case momentId
        case momentType
        case confidence
        case why
    }

    enum LegacyCodingKeys: String, CodingKey {
        case offerEligible = "offer_eligible"
        case evidenceSpan = "evidence_span"
        case reasonCodes = "reason_codes"
        case intensityBucket = "intensity_bucket"
        case momentId = "moment_id"
        case momentType = "moment_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)

        kind = try container.decodeIfPresent(String.self, forKey: .kind)

        if let value = try container.decodeIfPresent(Bool.self, forKey: .offerEligible) {
            offerEligible = value
        } else if let value = try legacy.decodeIfPresent(Bool.self, forKey: .offerEligible) {
            offerEligible = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.offerEligible,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing offerEligible")
            )
        }

        evidenceSpan = try container.decodeIfPresent(JournalEvidenceSpan.self, forKey: .evidenceSpan)
            ?? legacy.decodeIfPresent(JournalEvidenceSpan.self, forKey: .evidenceSpan)

        reasonCodes = try container.decodeIfPresent([String].self, forKey: .reasonCodes)
            ?? legacy.decodeIfPresent([String].self, forKey: .reasonCodes)

        if let raw = try container.decodeIfPresent(String.self, forKey: .mode) {
            mode = JournalDraftMode(rawValue: raw)
        } else {
            mode = nil
        }

        phase = try container.decodeIfPresent(String.self, forKey: .phase)
        risk = try container.decodeIfPresent(String.self, forKey: .risk)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        intensityBucket = try container.decodeIfPresent(String.self, forKey: .intensityBucket)
            ?? legacy.decodeIfPresent(String.self, forKey: .intensityBucket)
        momentId = try container.decodeIfPresent(String.self, forKey: .momentId)
            ?? legacy.decodeIfPresent(String.self, forKey: .momentId)
        momentType = try container.decodeIfPresent(String.self, forKey: .momentType)
            ?? legacy.decodeIfPresent(String.self, forKey: .momentType)
        confidence = try container.decodeIfPresent(String.self, forKey: .confidence)
        why = try container.decodeIfPresent([String].self, forKey: .why)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encode(offerEligible, forKey: .offerEligible)
        try container.encodeIfPresent(evidenceSpan, forKey: .evidenceSpan)
        try container.encodeIfPresent(reasonCodes, forKey: .reasonCodes)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(phase, forKey: .phase)
        try container.encodeIfPresent(risk, forKey: .risk)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(intensityBucket, forKey: .intensityBucket)
        try container.encodeIfPresent(momentId, forKey: .momentId)
        try container.encodeIfPresent(momentType, forKey: .momentType)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(why, forKey: .why)
    }

    func asJournalOffer() -> JournalOffer? {
        guard offerEligible, let span = evidenceSpan else { return nil }

        let resolvedMomentId = momentId ?? "moment_\(span.startMessageId)_\(span.endMessageId)"

        let resolvedMomentType: String = {
            if let momentType, !momentType.isEmpty { return momentType }
            switch label {
            case "overwhelm":
                return "vent"
            case "gratitude":
                return "gratitude"
            case "resolve":
                return "decision"
            case "curiosity":
                return "fun"
            case "insight":
                return "insight"
            default:
                return "insight"
            }
        }()

        let resolvedPhase = (phase?.isEmpty == false) ? (phase ?? "settled") : "settled"
        let resolvedConfidence = confidence ?? intensityBucket ?? "med"

        return JournalOffer(
            momentId: resolvedMomentId,
            momentType: resolvedMomentType,
            phase: resolvedPhase,
            confidence: resolvedConfidence,
            evidenceSpan: span,
            why: why,
            offerEligible: true
        )
    }
}
