//
//  AppModel.swift
//  SolMobile
//
//  Created by SolMobile App Model.
//

import Foundation
import SwiftData

@MainActor
final class AppModel {
    let container: ModelContainer
    let outboxService: OutboxService
    let unreadTracker: UnreadTrackerActor

    init() {
        UITestNetworkStub.enableIfNeeded()
        let useInMemory = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || UITestNetworkStub.isEnabled
        container = ModelContainerFactory.makeContainer(isInMemoryOnly: useInMemory)
        if !useInMemory {
            var descriptor = FetchDescriptor<ConversationThread>()
            descriptor.fetchLimit = 1
            let context = ModelContext(container)
            _ = try? context.fetch(descriptor)
            #if DEBUG
            DebugModelValidators.pruneOrphanMessages(modelContext: context, reason: "app_init")
            #endif
        }
        outboxService = OutboxService(container: container)
        unreadTracker = UnreadTrackerActor(container: container)

        SSEService.shared.bind(outboxService: outboxService)
        SSEService.shared.start()

        outboxService.start()
        OutboxRefreshScheduler.shared.register { [weak outboxService] in
            await outboxService?.runBackgroundRefresh()
        }
        OutboxRefreshScheduler.shared.schedule()
    }
}
