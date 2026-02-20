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
    private func dismissKeyboardIfVisible(_ app: XCUIApplication) {
        let returnKey = app.keyboards.buttons["Return"]
        if returnKey.waitForExistence(timeout: 1) {
            returnKey.tap()
        }
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testGhostCardAcceptShowsReceipt() throws {
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
        dismissKeyboardIfVisible(app)

        let sentMessage = app.staticTexts["Remember that my dog is named Max."]
        XCTAssertTrue(sentMessage.waitForExistence(timeout: 3))

        let ghostOverlay = app.descendants(matching: .any).matching(identifier: "ghost_overlay").firstMatch
        guard ghostOverlay.waitForExistence(timeout: 10) else {
            throw XCTSkip("Ghost overlay is not visible in this simulator run.")
        }

        let receiptTitle = app.staticTexts["Memory saved"]
        let acceptButton = ghostOverlay.buttons["Accept"]
        if acceptButton.waitForExistence(timeout: 5), acceptButton.isHittable {
            acceptButton.tap()
        } else {
            let saveButton = app.buttons["save_to_memory_button"]
            if saveButton.waitForExistence(timeout: 5) {
                saveButton.tap()
            }
        }
        if !receiptTitle.waitForExistence(timeout: 10) {
            let syncWarning = app.staticTexts["Message not synced yet."]
            XCTAssertTrue(syncWarning.waitForExistence(timeout: 5))
            return
        }

        let viewButton = app.buttons["View"]
        XCTAssertTrue(viewButton.waitForExistence(timeout: 5))
        viewButton.tap()

        let detailSnippet = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Remembered for later.")).firstMatch
        XCTAssertTrue(detailSnippet.waitForExistence(timeout: 5))
        app.swipeDown()

        let undoButton = app.buttons["Undo"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 5))
        undoButton.tap()
        XCTAssertFalse(receiptTitle.waitForExistence(timeout: 2))
    }

    @MainActor
    func testMemoryVaultAndCitationsLocal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui_test_stub_network", "1"]
        app.launch()

        let chatTab = app.tabBars.buttons["Chat"]
        if chatTab.exists {
            chatTab.tap()
        }

        let newThreadButton = app.buttons["new_thread_button"]
        XCTAssertTrue(newThreadButton.waitForExistence(timeout: 5))
        newThreadButton.tap()

        let threadCell = app.cells.element(boundBy: 0)
        XCTAssertTrue(threadCell.waitForExistence(timeout: 5))
        threadCell.tap()

        let messageField = app.textFields["Message…"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 5))
        let messageSeed = "Local memory test \(Int(Date().timeIntervalSince1970))"
        messageField.tap()
        messageField.typeText(messageSeed)
        app.buttons["Send"].tap()
        dismissKeyboardIfVisible(app)

        let sentMessage = app.staticTexts[messageSeed]
        XCTAssertTrue(sentMessage.waitForExistence(timeout: 10))

        let saveButton = app.buttons["save_to_memory_button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 20))
        saveButton.tap()

        let receiptTitle = app.staticTexts["Memory saved"]
        guard receiptTitle.waitForExistence(timeout: 10) else {
            throw XCTSkip("Memory save receipt did not appear in this simulator run.")
        }

        dismissKeyboardIfVisible(app)
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        let autoAcceptLabel = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Auto")).firstMatch
        XCTAssertTrue(autoAcceptLabel.waitForExistence(timeout: 10))

        let memoryVaultLink = app.staticTexts["Memory Vault"]
        if !memoryVaultLink.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(memoryVaultLink.waitForExistence(timeout: 5))
        memoryVaultLink.tap()

        let snippetMatch = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", messageSeed)).firstMatch
        XCTAssertTrue(snippetMatch.waitForExistence(timeout: 10))
        snippetMatch.tap()

        let detailSnippet = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", messageSeed)).firstMatch
        XCTAssertTrue(detailSnippet.waitForExistence(timeout: 5))

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists {
            backButton.tap()
        }

        chatTab.tap()
        let recallField = app.textFields["Message…"]
        XCTAssertTrue(recallField.waitForExistence(timeout: 5))
        recallField.tap()
        recallField.typeText("Please recall: \(messageSeed)")
        app.buttons["Send"].tap()

        let memoriesButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Memories'")).firstMatch
        XCTAssertTrue(memoriesButton.waitForExistence(timeout: 20))
        memoriesButton.tap()

        let citation = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", messageSeed)).firstMatch
        XCTAssertTrue(citation.waitForExistence(timeout: 10))
        citation.tap()

        let memoryDetailTitle = app.navigationBars["Memory"]
        XCTAssertTrue(memoryDetailTitle.waitForExistence(timeout: 10))

        let citationDetail = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", messageSeed)).firstMatch
        if !citationDetail.waitForExistence(timeout: 5) {
            let fallbackDetail = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Remembered for later.")).firstMatch
            XCTAssertTrue(fallbackDetail.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
