//
//  MemoryAPIModels.swift
//  SolMobile
//

import Foundation

nonisolated struct MemoryContextItem: Codable {
    let messageId: String
    let role: String
    let content: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case role
        case content
        case createdAt = "created_at"
    }
}

nonisolated struct MemoryDistillRequest: Codable {
    let threadId: String
    let triggerMessageId: String
    let contextWindow: [MemoryContextItem]
    let requestId: String
    let reaffirmCount: Int?
    let consent: MemoryConsent

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case triggerMessageId = "trigger_message_id"
        case contextWindow = "context_window"
        case requestId = "request_id"
        case reaffirmCount = "reaffirm_count"
        case consent
    }
}

struct MemorySpanWindow: Codable {
    let before: Int?
    let after: Int?
}

struct MemorySpanSaveRequest: Codable {
    let requestId: String
    let threadId: String
    let anchorMessageId: String
    let window: MemorySpanWindow?
    let memoryKind: String?
    let tags: [String]?
    let consent: MemoryConsent

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case threadId = "thread_id"
        case anchorMessageId = "anchor_message_id"
        case window
        case memoryKind = "memory_kind"
        case tags
        case consent
    }
}

nonisolated struct MemoryDistillResponse: Codable {
    let requestId: String?
    let transmissionId: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case transmissionId = "transmission_id"
        case status
    }
}

struct MemoryListResponse: Decodable {
    let requestId: String?
    let memories: [MemoryItemDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case memories
        case items
        case nextCursor = "next_cursor"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        if let items = try container.decodeIfPresent([MemoryItemDTO].self, forKey: .memories) {
            memories = items
        } else {
            memories = try container.decodeIfPresent([MemoryItemDTO].self, forKey: .items) ?? []
        }
    }
}

struct MemoryItemDTO: Decodable {
    let id: String
    let threadId: String?
    let triggerMessageId: String?
    let type: String?
    let snippet: String?
    let summary: String?
    let moodAnchor: String?
    let rigorLevel: String?
    let lifecycleState: String?
    let memoryKind: String?
    let isSafeForAutoAccept: Bool?
    let tags: [String]?
    let evidenceMessageIds: [String]?
    let fidelity: String?
    let transitionToHazyAt: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case memoryId = "memory_id"
        case threadId = "thread_id"
        case triggerMessageId = "trigger_message_id"
        case type
        case snippet
        case summary
        case moodAnchor = "mood_anchor"
        case rigorLevel = "rigor_level"
        case lifecycleState = "lifecycle_state"
        case memoryKind = "memory_kind"
        case isSafeForAutoAccept = "is_safe_for_auto_accept"
        case tags
        case evidenceMessageIds = "evidence_message_ids"
        case fidelity
        case transitionToHazyAt = "transition_to_hazy_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .memoryId)
        guard let resolvedId = id else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected id or memory_id"
                )
            )
        }

        self.id = resolvedId
        threadId = try container.decodeIfPresent(String.self, forKey: .threadId)
        triggerMessageId = try container.decodeIfPresent(String.self, forKey: .triggerMessageId)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        moodAnchor = try container.decodeIfPresent(String.self, forKey: .moodAnchor)
        rigorLevel = try container.decodeIfPresent(String.self, forKey: .rigorLevel)
        lifecycleState = try container.decodeIfPresent(String.self, forKey: .lifecycleState)
        memoryKind = try container.decodeIfPresent(String.self, forKey: .memoryKind)
        isSafeForAutoAccept = try container.decodeIfPresent(Bool.self, forKey: .isSafeForAutoAccept)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        evidenceMessageIds = try container.decodeIfPresent([String].self, forKey: .evidenceMessageIds)
        fidelity = try container.decodeIfPresent(String.self, forKey: .fidelity)
        transitionToHazyAt = try container.decodeIfPresent(String.self, forKey: .transitionToHazyAt)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct MemoryPatchPayload: Codable {
    let snippet: String?
    let tags: [String]?
    let moodAnchor: String?
    let memoryKind: String?

    enum CodingKeys: String, CodingKey {
        case snippet
        case tags
        case moodAnchor = "mood_anchor"
        case memoryKind = "memory_kind"
    }
}

struct MemoryPatchRequest: Codable {
    let requestId: String
    let patch: MemoryPatchPayload
    let consent: MemoryConsent

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case patch
        case consent
    }
}

struct MemoryPatchResponse: Decodable {
    let requestId: String?
    let memory: MemoryItemDTO?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case memory
    }
}

struct MemoryCreatePayload: Codable {
    let domain: String
    let title: String?
    let tags: [String]?
    let importance: String?
    let content: String
    let moodAnchor: String?
    let rigorLevel: String?

    enum CodingKeys: String, CodingKey {
        case domain
        case title
        case tags
        case importance
        case content
        case moodAnchor = "mood_anchor"
        case rigorLevel = "rigor_level"
    }
}

struct MemoryDetailResponse: Decodable {
    let requestId: String?
    let memory: MemoryItemDTO?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case memory
    }
}

struct MemoryCreateRequest: Codable {
    let requestId: String
    let memory: MemoryCreatePayload
    let source: MemoryCreateSource?
    let consent: MemoryConsent

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case memory
        case source
        case consent
    }
}

struct MemoryCreateResponse: Decodable {
    let requestId: String?
    let memory: MemoryItemDTO?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case memory
    }
}

struct MemoryCreateSource: Codable {
    let threadId: String?
    let messageId: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case messageId = "message_id"
        case createdAt = "created_at"
    }
}

struct MemoryConsent: Codable {
    let explicitUserConsent: Bool

    enum CodingKeys: String, CodingKey {
        case explicitUserConsent = "explicit_user_consent"
    }
}

struct MemoryBatchDeleteRequest: Codable {
    let requestId: String
    let filter: MemoryBatchDeleteFilter
    let confirm: Bool

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case filter
        case confirm
    }
}

struct MemoryBatchDeleteFilter: Codable {
    let threadId: String?
    let domain: String?
    let tagsAny: [String]?
    let createdBefore: String?

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case domain
        case tagsAny = "tags_any"
        case createdBefore = "created_before"
    }
}

struct MemoryClearAllRequest: Codable {
    let requestId: String
    let confirm: Bool
    let confirmPhrase: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case confirm
        case confirmPhrase = "confirm_phrase"
    }
}

struct MemoryDeleteResponse: Codable {
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
    }
}

struct MemoryBatchDeleteResponse: Codable {
    let requestId: String?
    let deletedCount: Int?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case deletedCount = "deleted_count"
    }
}
