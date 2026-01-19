//
//  ModelContainerFactory.swift
//  SolMobile
//

import SwiftData

enum ModelContainerFactory {
    static var appSchema: Schema {
        Schema([
            ConversationThread.self,
            Message.self,
            Capture.self,
            ClaimSupport.self,
            ClaimMapEntry.self,
            CapturedSuggestion.self,
            DraftRecord.self,
            Packet.self,
            Transmission.self,
            DeliveryAttempt.self
        ])
    }

    static func makeContainer(isInMemoryOnly: Bool = false) -> ModelContainer {
        if isInMemoryOnly {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: appSchema, configurations: [config])
        }
        return try! ModelContainer(for: appSchema)
    }
}
