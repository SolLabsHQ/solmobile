//
//  ContentView.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/15/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
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
        .modelContainer(for: [
            ConversationThread.self,
            Message.self,
            Packet.self,
            Transmission.self
        ])
    }
}

#Preview {
    ContentView()
}
