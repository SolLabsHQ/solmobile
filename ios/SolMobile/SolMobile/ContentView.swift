//
//  ContentView.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/15/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    private static let sharedContainer = ModelContainerFactory.makeContainer(
        isInMemoryOnly: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    )
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
        .modelContainer(Self.sharedContainer)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            let context = ModelContext(Self.sharedContainer)
            let service = StorageCleanupService(modelContext: context)
            guard service.isCleanupDue() else { return }
            Task {
                await Task.yield()
                _ = try? service.runCleanup()
            }
            StorageCleanupScheduler.shared.schedule()
        }
    }

    private static func makeModelContainer() -> ModelContainer {
        ModelContainerFactory.makeContainer(
            isInMemoryOnly: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        )
    }
}

#Preview {
    ContentView()
}
