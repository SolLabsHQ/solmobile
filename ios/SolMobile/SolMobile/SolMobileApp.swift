//
//  SolMobileApp.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/15/25.
//

import SwiftUI

@main
struct SolMobileApp: App {
    init() {
        StorageCleanupScheduler.shared.register()
        StorageCleanupScheduler.shared.schedule()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
