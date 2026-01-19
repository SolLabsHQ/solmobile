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
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: ModelContainerFactory.appSchema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }
}
