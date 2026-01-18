//
//  SwiftDataTestHarness.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import XCTest
import SwiftData

@testable import SolMobile

@MainActor
final class SwiftDataTestHarness {
    let container: ModelContainer
    let context: ModelContext

    init(file: StaticString = #filePath, line: UInt = #line) {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)

            container = try ModelContainer(
                for: ConversationThread.self,
                Message.self,
                Capture.self,
                ClaimSupport.self,
                ClaimMapEntry.self,
                Packet.self,
                Transmission.self,
                DeliveryAttempt.self,
                configurations: config
            )
            context = ModelContext(container)
        } catch {
            XCTFail("Failed to create in-memory SwiftData container: \(error)", file: file, line: line)
            fatalError()
        }
    }

    func save(file: StaticString = #filePath, line: UInt = #line) {
        do { try context.save() }
        catch { XCTFail("SwiftData save failed: \(error)", file: file, line: line) }
    }

    // MARK: - Factories

    func makeThread(title: String = "Thread 1") -> ConversationThread {
        let t = ConversationThread(title: title)
        context.insert(t)
        return t
    }

    func makeUserMessage(thread: ConversationThread, text: String) -> Message {
        let m = Message(thread: thread, creatorType: .user, text: text)
        thread.messages.append(m)
        context.insert(m)
        return m
    }

    func makePacket(thread: ConversationThread, messageIds: [UUID], type: String = "chat") -> Packet {
        let p = Packet(packetType: type, threadId: thread.id, messageIds: messageIds)
        context.insert(p)
        return p
    }

    func makeTransmission(packet: Packet, status: TransmissionStatus = .queued) -> Transmission {
        let tx = Transmission(status: status, packet: packet)
        context.insert(tx)
        return tx
    }

    func fetchQueuedTransmissions() -> [Transmission] {
        let queuedRaw = TransmissionStatus.queued.rawValue
        let d = FetchDescriptor<Transmission>(predicate: #Predicate { $0.statusRaw == queuedRaw })
        return (try? context.fetch(d)) ?? []
    }
}
