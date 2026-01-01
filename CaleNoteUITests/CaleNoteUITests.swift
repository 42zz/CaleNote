//
//  CaleNoteUITests.swift
//  CaleNoteUITests
//
//  Created by Masaya Kawai on 2025/12/20.
//

import XCTest

final class CaleNoteUITests: XCTestCase {
    private enum LaunchArg {
        static let uiTesting = "UI_TESTING"
        static let reset = "UI_TESTING_RESET"
        static let seed = "UI_TESTING_SEED"
        static let completeOnboarding = "UI_TESTING_COMPLETE_ONBOARDING"
        static let mockAuth = "UI_TESTING_MOCK_AUTH"
        static let skipSync = "UI_TESTING_SKIP_SYNC"
        static let darkMode = "UI_TESTING_DARK_MODE"
        static let lightMode = "UI_TESTING_LIGHT_MODE"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingFlow() throws {
        let app = launchApp(seedData: true, completeOnboarding: false, darkMode: false)

        waitForExistence(app.navigationBars["CaleNoteへようこそ"])
        capture(app, name: "Onboarding - Welcome")

        app.buttons["onboardingPrimaryButton"].tap()
        waitForExistence(app.navigationBars["Googleアカウント連携"])

        let signInButton = app.buttons["onboardingGoogleSignInButton"]
        waitForExistence(signInButton)
        signInButton.tap()

        waitForExistence(app.staticTexts["onboardingSignedInLabel"])
        capture(app, name: "Onboarding - Signed In")

        app.buttons["onboardingPrimaryButton"].tap()
        waitForExistence(app.navigationBars["初期設定"])

        let calendarToggle = app.switches["onboardingCalendarToggle_ui-test-primary"]
        waitForExistence(calendarToggle)
        calendarToggle.tap()
        calendarToggle.tap()

        app.buttons["onboardingPrimaryButton"].tap()
        waitForExistence(app.navigationBars["使い方のポイント"])

        app.buttons["onboardingPrimaryButton"].tap()
        waitForExistence(app.buttons["newEntryFab"])
        capture(app, name: "Timeline - After Onboarding")
    }

    @MainActor
    func testEntryCreationAndEdit() throws {
        let app = launchApp(seedData: true, completeOnboarding: true, darkMode: false)

        let fab = app.buttons["newEntryFab"]
        waitForExistence(fab)
        fab.tap()

        let titleField = app.textFields["entryTitleField"]
        waitForExistence(titleField)
        titleField.tap()
        titleField.typeText("UI Test New Entry")

        let bodyEditor = app.textViews["entryBodyEditor"]
        waitForExistence(bodyEditor)
        bodyEditor.tap()
        bodyEditor.typeText("本文のテストです #テスト")

        app.buttons["entrySaveButton"].tap()

        let newEntryRow = app.cells["timelineRow_UI Test New Entry"]
        waitForExistence(newEntryRow)
        capture(app, name: "Timeline - New Entry")

        newEntryRow.tap()
        let editButton = app.buttons["entryDetailEditButton"]
        waitForExistence(editButton)
        editButton.tap()

        let editTitleField = app.textFields["entryTitleField"]
        waitForExistence(editTitleField)
        replaceText(editTitleField, with: "UI Test Updated Entry")
        app.buttons["entrySaveButton"].tap()

        waitForExistence(app.staticTexts["UI Test Updated Entry"])
        capture(app, name: "Entry Detail - Updated")
    }

    @MainActor
    func testSearchFlow() throws {
        let app = launchApp(seedData: true, completeOnboarding: true, darkMode: false)

        let searchButton = app.buttons["searchButton"]
        waitForExistence(searchButton)
        searchButton.tap()

        let searchField = app.searchFields.firstMatch
        waitForExistence(searchField)
        searchField.tap()
        searchField.typeText("UI Test Seeded")

        let result = app.staticTexts["UI Test Seeded Entry"]
        waitForExistence(result)
        capture(app, name: "Search - Results")
    }

    @MainActor
    func testSidebarCalendarSelection() throws {
        let app = launchApp(seedData: true, completeOnboarding: true, darkMode: false)

        let sidebarButton = app.buttons["sidebarToggleButton"]
        waitForExistence(sidebarButton)
        sidebarButton.tap()

        let sidebar = app.otherElements["sidebarView"]
        waitForExistence(sidebar)

        let calendarRow = app.buttons["calendarRow_ui-test-primary"]
        waitForExistence(calendarRow)

        let beforeValue = calendarRow.value as? String
        calendarRow.tap()
        let afterValue = calendarRow.value as? String

        XCTAssertNotEqual(beforeValue, afterValue)
        capture(app, name: "Sidebar - Calendar Toggle")
    }

    @MainActor
    func testSnapshotsDarkMode() throws {
        let app = launchApp(seedData: true, completeOnboarding: true, darkMode: true)
        waitForExistence(app.buttons["newEntryFab"])

        capture(app, name: "Snapshot - Timeline Dark")
        XCUIDevice.shared.orientation = .landscapeLeft
        capture(app, name: "Snapshot - Timeline Dark Landscape")
        XCUIDevice.shared.orientation = .portrait
    }
}

private extension CaleNoteUITests {
    @discardableResult
    func launchApp(seedData: Bool, completeOnboarding: Bool, darkMode: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        var args = [
            LaunchArg.uiTesting,
            LaunchArg.reset,
            LaunchArg.mockAuth,
            LaunchArg.skipSync
        ]
        if seedData { args.append(LaunchArg.seed) }
        if completeOnboarding { args.append(LaunchArg.completeOnboarding) }
        args.append(darkMode ? LaunchArg.darkMode : LaunchArg.lightMode)
        app.launchArguments = args
        app.launch()
        return app
    }

    func waitForExistence(_ element: XCUIElement, timeout: TimeInterval = 6) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
    }

    func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func replaceText(_ element: XCUIElement, with text: String) {
        element.tap()
        if let existing = element.value as? String {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            element.typeText(deleteString)
        }
        element.typeText(text)
    }
}
