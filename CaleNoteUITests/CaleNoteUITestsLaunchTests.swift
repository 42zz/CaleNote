//
//  CaleNoteUITestsLaunchTests.swift
//  CaleNoteUITests
//
//  Created by Masaya Kawai on 2025/12/20.
//

import XCTest

final class CaleNoteUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "UI_TESTING",
            "UI_TESTING_RESET",
            "UI_TESTING_SEED",
            "UI_TESTING_COMPLETE_ONBOARDING",
            "UI_TESTING_MOCK_AUTH",
            "UI_TESTING_SKIP_SYNC",
            "UI_TESTING_LIGHT_MODE"
        ]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
