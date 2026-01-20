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
        container = ModelContainerFactory.makeContainer(
            isInMemoryOnly: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        )
        outboxService = OutboxService(container: container)
        unreadTracker = UnreadTrackerActor(container: container)

        outboxService.start()
        OutboxRefreshScheduler.shared.register { [weak outboxService] in
            await outboxService?.runBackgroundRefresh()
        }
        OutboxRefreshScheduler.shared.schedule()
    }
}
