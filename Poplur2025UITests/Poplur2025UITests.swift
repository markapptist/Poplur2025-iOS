//
//  Poplur2025UITests.swift
//  Poplur2025UITests
//
//  Created by Apptist Inc. on 2025-08-03.
//

import XCTest

final class Poplur2025UITests: XCTestCase {

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
    func testCubeThemeTextureAfterSignup() throws {
        let app = XCUIApplication()
        app.launch()

        let frame = app.windows.firstMatch.frame
        let width = frame.width
        let height = frame.height

        // Mirrors WelcomeView.swift's private layout constants (sectionSpacing/buttonGap/buttonSize)
        // so we can tap its SpriteKit-rendered Sign Up button, which has no accessibility element.
        let sectionSpacing: CGFloat = 28
        let buttonGap: CGFloat = 16
        let buttonHeight: CGFloat = 52
        let signUpCenterY = (208 + sectionSpacing) + buttonHeight / 2
        let signInCenterY = signUpCenterY + buttonHeight / 2 + buttonGap + buttonHeight / 2
        _ = signInCenterY

        func tap(sceneX: CGFloat, sceneY: CGFloat) {
            let dx = sceneX / width
            let dy = 1 - (sceneY / height)
            app.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
        }

        sleep(3)
        tap(sceneX: width / 2, sceneY: signUpCenterY)

        let userCardButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'User'")).firstMatch
        XCTAssertTrue(userCardButton.waitForExistence(timeout: 10), "Account type screen did not appear")
        userCardButton.tap()

        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "Email field did not appear")
        emailField.tap()
        emailField.typeText("claude.cube.test.\(Int(Date().timeIntervalSince1970))@example.com")

        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText("TestPass123!")

        let confirmField = app.secureTextFields["Confirm password"]
        confirmField.tap()
        confirmField.typeText("TestPass123!")

        let createButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Create'")).firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 5), "Create button did not appear")
        createButton.tap()

        sleep(20)

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "PostSignupScreen"
        add(attachment)

        sleep(5)
        let screenshot2 = XCUIScreen.main.screenshot()
        let attachment2 = XCTAttachment(screenshot: screenshot2)
        attachment2.lifetime = .keepAlways
        attachment2.name = "PostSignupScreenLater"
        add(attachment2)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
