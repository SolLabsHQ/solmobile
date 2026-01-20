//
//  ContentView.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/15/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
//        VStack {
//            Image(systemName: "globe")
//                .imageScale(.large)
//                .foregroundStyle(.tint)
//            Text("Hello, world!")
//        }
//        .padding()
        TabView {
            ThreadListView()
                .tabItem { Label("Chat", systemImage: "message") }
//
//            AnchorsView()
//                .tabItem { Label("Anchors", systemImage: "bookmark") }
//
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            let context = ModelContext(modelContext.container)
            let service = StorageCleanupService(modelContext: context)
            guard service.isCleanupDue() else { return }
            Task {
                await Task.yield()
                _ = try? service.runCleanup()
            }
            StorageCleanupScheduler.shared.schedule()
        }
    }
}

#Preview {
    ContentView()
}
