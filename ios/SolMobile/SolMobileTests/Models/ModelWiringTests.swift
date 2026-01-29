//
//  ModelWiringTests.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import XCTest
import SwiftData
@testable import SolMobile

@MainActor
final class ModelWiringTests: XCTestCase {

    @MainActor
    func test_swiftdata_inmemory_container_can_insert_core_models() throws {
        // If you keep both Thread + ConversationThread around during refactors,
        // it’s okay to include both in tests. Remove one later when the app does.
        let schema = Schema([
            ConversationThread.self,
            Message.self,
            CapturedSuggestion.self,
            MemoryArtifact.self,
            GhostCardLedger.self,
            DraftRecord.self,
            ThreadReadState.self,
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
        XCTAssertEqual(fetchedTx.first?.packet.id, packet.id)
        XCTAssertEqual(fetchedTx.first?.packet.threadId, thread.id)

        let fetchedAttempts = try ctx.fetch(FetchDescriptor<DeliveryAttempt>())
        XCTAssertEqual(fetchedAttempts.count, 1)
        XCTAssertEqual(fetchedAttempts.first?.transmission?.id, tx.id)
    }


    @MainActor
    func test_transmissions_can_be_filtered_by_thread_via_packet_threadId() throws {
        let schema = Schema([
            ConversationThread.self,
            Message.self,
            CapturedSuggestion.self,
            MemoryArtifact.self,
            GhostCardLedger.self,
            DraftRecord.self,
            ThreadReadState.self,
            Packet.self,
            Transmission.self,
            DeliveryAttempt.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)

        // Thread A
        let a = ConversationThread(title: "A")
        ctx.insert(a)

        let aMsg = Message(thread: a, creatorType: .user, text: "a")
        a.messages.append(aMsg)
        ctx.insert(aMsg)

        let aPacket = Packet(threadId: a.id, messageIds: [aMsg.id])
        aPacket.packetType = "chat"
        ctx.insert(aPacket)

        let aTx = Transmission(packet: aPacket)
        aTx.status = .queued
        ctx.insert(aTx)

        // Thread B
        let b = ConversationThread(title: "B")
        ctx.insert(b)

        let bMsg = Message(thread: b, creatorType: .user, text: "b")
        b.messages.append(bMsg)
        ctx.insert(bMsg)

        let bPacket = Packet(threadId: b.id, messageIds: [bMsg.id])
        bPacket.packetType = "chat"
        ctx.insert(bPacket)

        let bTx = Transmission(packet: bPacket)
        bTx.status = .queued
        ctx.insert(bTx)

        try ctx.save()

        // Filter by thread id using the `Transmission.packet.threadId` seam.
        // IMPORTANT: SwiftData's #Predicate can't reliably reference properties off captured model instances.
        // Capture the UUIDs as plain values first.
        let aId = a.id
        let bId = b.id

        let dA = FetchDescriptor<Transmission>(predicate: #Predicate<Transmission> { $0.packet.threadId == aId })
        let aTxs = try ctx.fetch(dA)
        XCTAssertEqual(aTxs.count, 1)
        XCTAssertEqual(aTxs.first?.id, aTx.id)

        let dB = FetchDescriptor<Transmission>(predicate: #Predicate<Transmission> { $0.packet.threadId == bId })
        let bTxs = try ctx.fetch(dB)
        XCTAssertEqual(bTxs.count, 1)
        XCTAssertEqual(bTxs.first?.id, bTx.id)
    }

    @MainActor
    func test_delivery_attempt_backlink_points_to_transmission() throws {
        let schema = Schema([
            ConversationThread.self,
            Message.self,
            DraftRecord.self,
            ThreadReadState.self,
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

        let a = DeliveryAttempt(statusCode: 202, outcome: .pending, errorMessage: nil, transmissionId: "tx1", transmission: tx)
        tx.deliveryAttempts.append(a)
        ctx.insert(a)

        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<DeliveryAttempt>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.transmission?.id, tx.id)
    }
}
