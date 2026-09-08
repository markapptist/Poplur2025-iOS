import XCTest

final class NativePreloginUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestForceSignedOut", "-SkipClaySplash", "-poplur_prelogin_music_muted", "YES", "-poplur.permissionPrimer.handled.location", "YES", "-poplur.permissionPrimer.handled.photos", "YES"]
        app.launch()
    }
    func testNativeWelcomeLoginAndBack() {
        XCTAssertTrue(app.buttons["welcomeSignIn"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.webViews.count, 0, "Signed-out screens must not create a WebView")
        attach("native-welcome")
        app.buttons["welcomeSignIn"].tap()
        XCTAssertTrue(app.textFields["preloginEmail"].waitForExistence(timeout: 10))
        app.buttons["submitSignIn"].tap()
        XCTAssertTrue(app.staticTexts["preloginError"].waitForExistence(timeout: 5))
        attach("native-sign-in")
        app.buttons["preloginBack"].tap()
        XCTAssertTrue(app.buttons["welcomeSignUp"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.webViews.count, 0)
    }
    func testSignupSequenceValidationAndAccountChoices() {
        XCTAssertTrue(app.buttons["welcomeSignUp"].waitForExistence(timeout: 20))
        app.buttons["welcomeSignUp"].tap()
        XCTAssertTrue(app.buttons["Personal"].waitForExistence(timeout: 10))
        attach("native-accounts")
        app.buttons["Business"].tap()
        app.buttons["chooseAccount"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["introNext"].waitForExistence(timeout: 5))
        attach("native-business-intro")
        app.buttons["introNext"].tap()
        app.swipeUp()
        app.buttons["credentialsNext"].tap()
        XCTAssertTrue(app.staticTexts["preloginError"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.webViews.count, 0)
        attach("native-create-login")
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
