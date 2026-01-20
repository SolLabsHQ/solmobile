//
//  OutboxRefreshScheduler.swift
//  SolMobile
//
//  Created by SolMobile Outbox.
//

import BackgroundTasks
import os

final class OutboxRefreshScheduler {
    static let shared = OutboxRefreshScheduler()
    static let taskId = "com.sollabshq.solmobile.outboxRefresh"

    private let log = Logger(subsystem: "com.sollabshq.solmobile", category: "OutboxRefresh")
    private var handler: (() async -> Void)?

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func register(handler: @escaping () async -> Void) {
        guard !isRunningUnitTests else { return }
        self.handler = handler
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskId, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handle(task: refreshTask)
        }
    }

    func schedule() {
        guard !isRunningUnitTests else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error("schedule failed err=\(String(describing: error), privacy: .public)")
        }
    }

    private func handle(task: BGAppRefreshTask) {
        schedule()

        guard let handler else {
            task.setTaskCompleted(success: false)
            return
        }

        let refreshTask = Task {
            await handler()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }
    }
}
