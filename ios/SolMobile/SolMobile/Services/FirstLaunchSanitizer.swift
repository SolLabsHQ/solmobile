//
//  FirstLaunchSanitizer.swift
//  SolMobile
//

import Foundation
import os
import SwiftData

enum FirstLaunchSanitizer {
    private static let log = Logger(subsystem: "com.sollabshq.solmobile", category: "first-launch")
    private static let firstLaunchKey = "sol.firstLaunch.v1"

    static func runIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: firstLaunchKey) == false else { return }
        defaults.set(true, forKey: firstLaunchKey)

        let context = ModelContext(container)
        let deleted = purgeAll(context: context)
        if deleted > 0 {
            log.info("first_launch_purge cleared=\(deleted, privacy: .public)")
        } else {
            log.info("first_launch_purge no_data")
        }
    }

    private static func purgeAll(context: ModelContext) -> Int {
        var deleted = 0

        deleted += purge(ConversationThread.self, context: context)
        deleted += purge(Transmission.self, context: context)
        deleted += purge(Packet.self, context: context)
        deleted += purge(DeliveryAttempt.self, context: context)
        deleted += purge(DraftRecord.self, context: context)
        deleted += purge(ThreadReadState.self, context: context)
        deleted += purge(MemoryArtifact.self, context: context)
        deleted += purge(GhostCardLedger.self, context: context)
        deleted += purge(CapturedSuggestion.self, context: context)
        deleted += purge(Message.self, context: context)
        deleted += purge(Capture.self, context: context)
        deleted += purge(ClaimSupport.self, context: context)
        deleted += purge(ClaimMapEntry.self, context: context)

        if deleted > 0 {
            try? context.save()
        }

        return deleted
    }

    private static func purge<T: PersistentModel>(_ type: T.Type, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<T>()
        let items = (try? context.fetch(descriptor)) ?? []
        for item in items {
            context.delete(item)
        }
        return items.count
    }
}
