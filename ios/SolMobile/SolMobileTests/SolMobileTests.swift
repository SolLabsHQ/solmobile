//
//  SolMobileTests.swift
//  SolMobileTests
//
//  Created by Jassen A. McNulty on 12/15/25.
//

import XCTest
@testable import SolMobile

/// Keep this file as a lightweight smoke test container.
/// Real tests live under `SolMobileTests/` (Support/Mocks/Fixtures/Actions/Models/Connectivity).
@MainActor
final class SolMobileSmokeTests: XCTestCase {

    func testModuleLoadsAndCoreTypesLink() {
        // If this compiles and runs, the test target is wired correctly.
        _ = TransmissionActions.self
        _ = SolServerClient.self

        // Models
        _ = ConversationThread.self
        _ = Message.self
        _ = Packet.self
        _ = Transmission.self
        _ = DeliveryAttempt.self
        _ = ThreadReadState.self
    }
}
