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
            _ = try? ModelContext(container).fetch(descriptor)
        }
        outboxService = OutboxService(container: container)
        unreadTracker = UnreadTrackerActor(container: container)

        outboxService.start()
        OutboxRefreshScheduler.shared.register { [weak outboxService] in
            await outboxService?.runBackgroundRefresh()
        }
        OutboxRefreshScheduler.shared.schedule()
    }
}
