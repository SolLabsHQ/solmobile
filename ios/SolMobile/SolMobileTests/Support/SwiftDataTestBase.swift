//
//  SwiftDataTestBase.swift
//  SolMobile
//
//  Created by Jassen A. McNulty on 12/26/25.
//

import XCTest
import SwiftData
@testable import SolMobile

@MainActor
class SwiftDataTestBase: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    enum MockError: Error { case unexpectedSend }

    override func setUp() {
        super.setUp()

        // ⚠️ Replace model types with what your app actually uses.
        let schema = Schema([
            ConversationThread.self,
            Message.self,
            Packet.self,
            Transmission.self,
            DeliveryAttempt.self      
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }
}
