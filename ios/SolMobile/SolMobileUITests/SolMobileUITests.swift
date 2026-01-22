//
//  SolMobileUITests.swift
//  SolMobileUITests
//
//  Created by Jassen A. McNulty on 12/15/25.
//

import XCTest

final class SolMobileUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testSaveToMemoryShowsGhostOverlay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui_test_stub_network", "1"]
        app.launch()

        let chatTab = app.tabBars.buttons["Chat"]
        if chatTab.exists {
            chatTab.tap()
        }

        let newThreadButton = app.buttons["new_thread_button"]
        XCTAssertTrue(newThreadButton.waitForExistence(timeout: 3))
        newThreadButton.tap()

        let threadCell = app.cells.element(boundBy: 0)
        XCTAssertTrue(threadCell.waitForExistence(timeout: 3))
        threadCell.tap()

        let messageField = app.textFields["Message…"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 3))
        messageField.tap()
        messageField.typeText("Remember that my dog is named Max.")
        app.buttons["Send"].tap()

        let sentMessage = app.staticTexts["Remember that my dog is named Max."]
        XCTAssertTrue(sentMessage.waitForExistence(timeout: 3))

        let saveButton = app.buttons["save_to_memory_button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        saveButton.tap()

        let ghostOverlay = app.descendants(matching: .any).matching(identifier: "ghost_overlay").firstMatch
        XCTAssertTrue(ghostOverlay.waitForExistence(timeout: 10))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
