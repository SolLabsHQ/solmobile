//
//  ContentView.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/15/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    private static let sharedContainer = makeModelContainer()

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
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            ConversationThread.self,
            Message.self,
            Capture.self,
            ClaimSupport.self,
            ClaimMapEntry.self,
            CapturedSuggestion.self,
            DraftRecord.self,
            Packet.self,
            Transmission.self
        ])
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [config])
        }
        return try! ModelContainer(for: schema)
    }
}

#Preview {
    ContentView()
}
