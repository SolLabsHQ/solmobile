//
//  ModelWiringTests.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import XCTest
import SwiftData
@testable import SolMobile

final class ModelWiringTests: XCTestCase {

    @MainActor
    func test_swiftdata_inmemory_container_can_insert_core_models() throws {
        // If you keep both Thread + ConversationThread around during refactors,
        // it’s okay to include both in tests. Remove one later when the app does.
        let schema = Schema([
            ConversationThread.self,
            Message.self,
            Packet.self,
            Transmission.self,
            DeliveryAttempt.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)

        let thread = ConversationThread(title: "wire")
        ctx.insert(thread)

        let msg = Message(thread: thread, creatorType: .user, text: "hi")
        thread.messages.append(msg)
        ctx.insert(msg)

        let packet = Packet(threadId: thread.id, messageIds: [msg.id])
        packet.packetType = "chat"
        ctx.insert(packet)

        let tx = Transmission(packet: packet)
        tx.status = .queued
        ctx.insert(tx)

        let att = DeliveryAttempt(statusCode: 202, outcome: .pending, errorMessage: nil, transmissionId: "tx1", transmission: tx)
        tx.deliveryAttempts.append(att)
        ctx.insert(att)

        try ctx.save()

        let fetchedThreads = try ctx.fetch(FetchDescriptor<ConversationThread>())
        XCTAssertEqual(fetchedThreads.count, 1)

        let fetchedTx = try ctx.fetch(FetchDescriptor<Transmission>())
        XCTAssertEqual(fetchedTx.count, 1)
        XCTAssertEqual(fetchedTx.first?.deliveryAttempts.count, 1)
    }
}
