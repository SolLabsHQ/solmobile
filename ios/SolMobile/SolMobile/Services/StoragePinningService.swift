//
//  StoragePinningService.swift
//  SolMobile
//
//  ADR-008 Save to Memory behavior
//

import Foundation
import SwiftData

@MainActor
final class StoragePinningService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func pinThreadAndMessages(thread: ConversationThread, messages: [Message]) {
        guard !thread.pinned else { return }
        thread.pinned = true
        for message in messages {
            message.pinned = true
        }
        try? modelContext.save()
    }
}
