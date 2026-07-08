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
    func testFullAppScreenshotSweep() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launch()

        var shotIndex = 0
        func shot(_ name: String) {
            shotIndex += 1
            let img = XCUIScreen.main.screenshot()
            let att = XCTAttachment(screenshot: img)
            att.name = String(format: "%03d_%@", shotIndex, name)
            att.lifetime = .keepAlways
            add(att)
        }

        let frame = app.windows.firstMatch.frame
        let width = frame.width
        let height = frame.height

        // Mirrors WelcomeView.swift's private layout constants for its SpriteKit buttons (no
        // accessibility elements exist on that canvas). Pre-login only — post-login navigation
        // below uses real accessibility-identified test hooks instead (see UITestHooks.swift).
        let sectionSpacing: CGFloat = 28
        let buttonGap: CGFloat = 16
        let buttonHeight: CGFloat = 52
        let signUpCenterY = (208 + sectionSpacing) + buttonHeight / 2
        let signInCenterY = signUpCenterY + buttonHeight / 2 + buttonGap + buttonHeight / 2

        func tapWelcomeScene(x: CGFloat, y: CGFloat) {
            let dx = x / width
            let dy = 1 - (y / height)
            app.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
        }

        @discardableResult
        func tapIfExists(_ element: XCUIElement, timeout: TimeInterval = 4) -> Bool {
            if element.waitForExistence(timeout: timeout) {
                element.tap()
                return true
            }
            return false
        }

        func fillIfExists(_ element: XCUIElement, text: String, timeout: TimeInterval = 4) {
            if element.waitForExistence(timeout: timeout) {
                element.tap()
                element.typeText(text)
            }
        }

        func button(containing text: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        }

        // MARK: - Pre-login (real flow — no bypass, so these show actual user-facing screens)

        sleep(10)
        shot("Welcome")

        tapWelcomeScene(x: width / 2, y: signInCenterY)
        sleep(2)
        shot("Login")

        // Login has no back control — fresh relaunch for the Sign Up flow.
        app.terminate()
        app.launch()
        sleep(10)
        tapWelcomeScene(x: width / 2, y: signUpCenterY)
        sleep(1)
        shot("SignUp_ChooseAccount")

        // --- Business path, screenshot-only: submit() only fires at .review, so this is safely
        // abandoned afterward without creating a business account. ---
        tapIfExists(button(containing: "Business"))
        sleep(1)
        shot("SignUp_CreateLogin_Business")

        let bizStamp = Int(Date().timeIntervalSince1970)
        fillIfExists(app.textFields["Email"], text: "claude.ui.sweep.biz.\(bizStamp)@example.com")
        fillIfExists(app.secureTextFields["Password"], text: "TestPass123!")
        fillIfExists(app.secureTextFields["Confirm password"], text: "TestPass123!")

        let continueButton = button(containing: "Continue")
        tapIfExists(continueButton)
        sleep(1)
        shot("SignUp_BusinessProfile")

        fillIfExists(app.textFields["Business name"], text: "Claude Test Biz")
        fillIfExists(app.textFields["Business category"], text: "Food")
        fillIfExists(app.textFields["Address / location on map"], text: "123 Main St, Toronto")
        fillIfExists(app.textFields["Contact email"], text: "biz@example.com")

        tapIfExists(continueButton)
        sleep(1)
        shot("SignUp_Verification_Empty")

        tapIfExists(button(containing: "Verify My Business"))
        tapIfExists(app.switches.firstMatch, timeout: 2)
        tapIfExists(button(containing: "Business license"), timeout: 2)
        fillIfExists(app.textViews.firstMatch, text: "Business license on file, available on request.")
        sleep(1)
        shot("SignUp_Verification_Filled")

        tapIfExists(continueButton)
        sleep(1)
        shot("SignUp_Review")

        // MARK: - Post-login (test-hook driven — bypasses real auth entirely, so this never
        // depends on Firebase account creation succeeding or the app's own gesture recognition).

        app.terminate()
        app.launchArguments += ["-UITestAuthBypass", "-UITestHooks"]
        app.launch()
        sleep(8)

        func tapHook(_ identifier: String, timeout: TimeInterval = 8) {
            let el = app.buttons[identifier]
            if el.waitForExistence(timeout: timeout) {
                el.tap()
            } else {
                XCTFail("Missing test hook: \(identifier)")
            }
            sleep(2)
        }

        // Feed, Camera, and Map currently all share the same wheel content (HomeView.holdMenuNavItems).
        let sharedWheelIds = ["nav-home", "nav-chat", "nav-music", "nav-gifts", "nav-youtube"]
        let profileWheelIds = ["mail", "settings", "stats", "notifications", "phone", "store", "creator"]

        shot("Feed")
        for id in sharedWheelIds {
            tapHook("UITestWheel_\(id)")
            shot("Feed_\(id)")
            tapHook("UITestTab_feed")
        }

        tapHook("UITestTab_profile")
        shot("Profile")
        for id in profileWheelIds {
            tapHook("UITestWheel_\(id)")
            shot("Profile_\(id)")
            tapHook("UITestTab_profile")
        }

        tapHook("UITestTab_map")
        shot("Map")
        for id in sharedWheelIds {
            tapHook("UITestWheel_\(id)")
            shot("Map_\(id)")
            tapHook("UITestTab_map")
        }

        tapHook("UITestTab_record")
        shot("Camera")
        for id in sharedWheelIds {
            tapHook("UITestWheel_\(id)")
            shot("Camera_\(id)")
            tapHook("UITestTab_record")
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
