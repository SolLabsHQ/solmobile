//
//  TransmissionActionsTests.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import Foundation
import XCTest
import SwiftData
@testable import SolMobile

@MainActor
final class TransmissionActionsTests: SwiftDataTestBase {

    func test_processQueue_success_marksSucceeded_andAppendsAssistant() async throws {
        // Arrange
        let transport = FakeTransport()
        transport.nextSend = {
            ChatResponse(text: "hello from server", statusCode: 200, transmissionId: "tx123", pending: false, threadMemento: nil)
        }

        let thread = ConversationThread(title: "T1")
        context.insert(thread)

        let user = Message(thread: thread, creatorType: .user, text: "hi")
        thread.messages.append(user)
        context.insert(user)

        let actions = TransmissionActions(modelContext: context, transport: transport)
        actions.enqueueChat(thread: thread, userMessage: user)

        // Act
        await actions.processQueue()

        // Assert
        let allTx = try context.fetch(FetchDescriptor<Transmission>())
        XCTAssertEqual(allTx.count, 1)
        XCTAssertEqual(allTx[0].status, .succeeded)

        XCTAssertTrue(thread.messages.contains(where: { $0.creatorType == .assistant }))
    }
}
