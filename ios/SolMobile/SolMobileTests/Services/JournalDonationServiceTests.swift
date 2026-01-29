//
//  JournalDonationServiceTests.swift
//  SolMobileTests
//

import XCTest
@testable import SolMobile

@MainActor
final class JournalDonationServiceTests: XCTestCase {
    func test_donateMoment_returnsUnavailableWhenDirectDonationUnsupported() async {
        let result = await JournalDonationService.shared.donateMoment(
            summaryText: "Test moment",
            location: nil,
            moodAnchor: nil
        )

        switch result {
        case .unavailable:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected unavailable when direct donation is unsupported")
        }
    }
}
