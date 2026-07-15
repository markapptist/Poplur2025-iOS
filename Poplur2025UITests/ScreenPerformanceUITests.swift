import XCTest

/// Repeatable, screen-level responsiveness checks.
///
/// Each test leaves the production UI untouched and samples the app process while the selected
/// screen renders normally. Xcode records hitch time, CPU, and memory in the `.xcresult` bundle,
/// allowing runs to be compared without relying on subjective visual inspection.
@MainActor
final class ScreenPerformanceUITests: XCTestCase {
    private let sampleDuration: TimeInterval = 5
    private let measurementIterations = 3

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWelcomeRenderingPerformance() throws {
        let app = launchSignedOutApp()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        measureRendering(of: app)
    }

    func testLoginRenderingPerformance() throws {
        let app = launchSignedOutApp()
        tapWelcomeButton(.signIn, in: app)
        XCTAssertTrue(
            app.textFields["E-Mail"].waitForExistence(timeout: 10),
            "Login did not become ready for measurement"
        )
        measureRendering(of: app)
    }

    func testSignUpRenderingPerformance() throws {
        let app = launchSignedOutApp()
        tapWelcomeButton(.signUp, in: app)
        let accountTypeButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] 'User'"))
            .firstMatch
        XCTAssertTrue(
            accountTypeButton.waitForExistence(timeout: 10),
            "Sign Up did not become ready for measurement"
        )
        measureRendering(of: app)
    }

    func testFeedRenderingPerformance() throws {
        let app = launchAuthenticatedApp()
        waitForScreen("Feed", in: app)
        measureRendering(of: app)
    }

    func testMapRenderingPerformance() throws {
        let app = launchAuthenticatedApp()
        let mapButton = app.buttons["UITestTab_map"]
        XCTAssertTrue(mapButton.waitForExistence(timeout: 20), "Map test hook is missing")
        mapButton.tap()
        waitForScreen("Map", in: app)
        // Let the map finish its initial camera and tile setup before sustained-render sampling.
        Thread.sleep(forTimeInterval: 3)
        measureRendering(of: app)
    }

    private func launchSignedOutApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestForceSignedOut", "-UITestHooks", "-SkipWalletIntro"]
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
        // The approved splash is part of normal launch. Keep it outside the per-screen sample.
        Thread.sleep(forTimeInterval: 4)
        return app
    }

    private func launchAuthenticatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestAuthBypass", "-UITestHooks", "-SkipWalletIntro"]
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
        // HomeView performs substantially more one-time setup than the signed-out flow. Avoid
        // repeatedly snapshotting its accessibility tree while that work is in flight: doing so
        // can itself overload the automation connection and contaminate the performance sample.
        Thread.sleep(forTimeInterval: 30)
        waitForScreen("Feed", in: app)
        // HomeView has its own initialization cover; keep that outside Feed/Map samples.
        Thread.sleep(forTimeInterval: 5)
        return app
    }

    private enum WelcomeButton {
        case signIn
        case signUp
    }

    private func tapWelcomeButton(_ button: WelcomeButton, in app: XCUIApplication) {
        let frame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)

        // Welcome's controls are SpriteKit nodes. WelcomeScene positions them using the approved
        // 390 x 845 Good Copy reference, while XCTest coordinates use the same top-origin ratios.
        let normalizedY: CGFloat
        switch button {
        case .signIn: normalizedY = 625.0 / 845.0
        case .signUp: normalizedY = 720.0 / 845.0
        }

        app.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0.5,
                dy: normalizedY
            )
        ).tap()
    }

    private func waitForScreen(_ name: String, in app: XCUIApplication) {
        XCTAssertTrue(
            app.staticTexts["UITestCurrentScreen_\(name)"].waitForExistence(timeout: 25),
            "\(name) did not become ready for measurement"
        )
    }

    private func measureRendering(of app: XCUIApplication) {
        guard #available(iOS 26.0, *) else {
            XCTFail("Screen hitch tests require an iOS 26 or newer test destination")
            return
        }

        let options = XCTMeasureOptions()
        options.iterationCount = measurementIterations
        measure(
            metrics: [
                XCTHitchMetric(application: app),
                XCTCPUMetric(application: app),
                XCTMemoryMetric(application: app)
            ],
            options: options
        ) {
            Thread.sleep(forTimeInterval: sampleDuration)
        }
    }
}
