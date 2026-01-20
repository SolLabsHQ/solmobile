//
//  SolMobileApp.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/15/25.
//

import SwiftUI
import SwiftData

@main
struct SolMobileApp: App {
    @State private var appModel = AppModel()

    init() {
        StorageCleanupScheduler.shared.register()
        StorageCleanupScheduler.shared.schedule()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.outboxService, appModel.outboxService)
                .environment(\.unreadTracker, appModel.unreadTracker)
                .modelContainer(appModel.container)
        }
    }
}
