//
//  StorageCleanupScheduler.swift
//  SolMobile
//

import BackgroundTasks
import os
import SwiftData

final class StorageCleanupScheduler {
    static let shared = StorageCleanupScheduler()
    static let taskId = "com.sollabshq.solmobile.cleanup"

    private let log = Logger(subsystem: "com.sollabshq.solmobile", category: "StorageCleanup")

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func register() {
        guard !isRunningUnitTests else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskId, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handle(task: refreshTask)
        }
    }

    func schedule() {
        guard !isRunningUnitTests else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: StorageCleanupService.cleanupIntervalSeconds)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error("schedule failed err=\(String(describing: error), privacy: .public)")
        }
    }

    private func handle(task: BGAppRefreshTask) {
        schedule()

        let cleanupTask = Task { @MainActor in
            let container = ModelContainerFactory.shared
            let service = StorageCleanupService(modelContext: ModelContext(container))
            do {
                _ = try service.runCleanup()
                task.setTaskCompleted(success: true)
            } catch {
                log.error("background cleanup failed err=\(String(describing: error), privacy: .public)")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            cleanupTask.cancel()
        }
    }
}
