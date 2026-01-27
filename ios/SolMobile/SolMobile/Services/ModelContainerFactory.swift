//
//  ModelContainerFactory.swift
//  SolMobile
//

import Foundation
import SwiftData
import os

enum ModelContainerFactory {
    private static let log = Logger(subsystem: "com.sollabshq.solmobile", category: "SwiftData")

    static var appSchema: Schema {
        Schema([
            ConversationThread.self,
            Message.self,
            Capture.self,
            ClaimSupport.self,
            ClaimMapEntry.self,
            CapturedSuggestion.self,
            MemoryArtifact.self,
            GhostCardLedger.self,
            DraftRecord.self,
            ThreadReadState.self,
            Packet.self,
            Transmission.self,
            DeliveryAttempt.self
        ])
    }

    static let shared: ModelContainer = {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SolMobile", isDirectory: true)
        let storeURL = dir.appendingPathComponent("default.store")

        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            #if DEBUG
            log.debug("swiftdata_store_dir_ready url=\(dir.path, privacy: .public)")
            #endif
        } catch {
            log.error("swiftdata_store_dir_create_failed url=\(dir.path, privacy: .public) err=\(String(describing: error), privacy: .public)")
        }

        #if DEBUG
        log.debug("swiftdata_store_url url=\(storeURL.path, privacy: .public)")
        #endif

        let config = ModelConfiguration(url: storeURL)
        return try! ModelContainer(for: appSchema, configurations: [config])
    }()

    static func makeContainer(isInMemoryOnly: Bool = false) -> ModelContainer {
        if isInMemoryOnly {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: appSchema, configurations: [config])
        }
        return shared
    }
}
