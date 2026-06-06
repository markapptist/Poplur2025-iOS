import XCTest

/// Screenshot automation tests for App Store Connect
/// Run with: fastlane snapshot
class SnapshotUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        
        // Setup snapshot helper (provided by fastlane)
        setupSnapshot(app)
        
        // Add launch arguments for clean screenshots
        app.launchArguments += [
            "UI_TESTING",
            "SCREENSHOTS_MODE",
            "SKIP_ONBOARDING",
            "USE_DEMO_DATA",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        
        // Disable animations for cleaner screenshots
        app.launchArguments += ["-UIViewAnimationDuration", "0.01"]
        
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Screenshot Tests
    
    func testGenerateAllScreenshots() throws {
        // Give app time to fully load
        sleep(2)
        
        // Screenshot 1: Map View with 3D pins
        takeScreenshot(name: "01-MapView")
        
        // Screenshot 2: Feed with posts
        navigateToFeed()
        sleep(2)
        takeScreenshot(name: "02-FeedView")
        
        // Screenshot 3: Camera/Create Post
        navigateToCamera()
        sleep(1)
        takeScreenshot(name: "03-CameraView")
        
        // Screenshot 4: Profile
        navigateToProfile()
        sleep(2)
        takeScreenshot(name: "04-ProfileView")
        
        // Screenshot 5: Map with location selection
        navigateToMap()
        sleep(1)
        // Tap on map to show location selection
        let map = app.otherElements["MapView"]
        if map.exists {
            map.tap()
            sleep(1)
            takeScreenshot(name: "05-LocationSelection")
        }
    }
    
    // MARK: - Individual Screenshot Tests
    
    func testMapViewScreenshot() throws {
        sleep(2)
        takeScreenshot(name: "01-MapView")
    }
    
    func testFeedViewScreenshot() throws {
        navigateToFeed()
        sleep(2)
        takeScreenshot(name: "02-FeedView")
    }
    
    func testCameraViewScreenshot() throws {
        navigateToCamera()
        sleep(1)
        takeScreenshot(name: "03-CameraView")
    }
    
    func testProfileViewScreenshot() throws {
        navigateToProfile()
        sleep(2)
        takeScreenshot(name: "04-ProfileView")
    }
    
    // MARK: - Navigation Helpers
    
    private func navigateToMap() {
        let tabBar = app.tabBars.firstMatch
        let mapButton = tabBar.buttons["Map"]
        if mapButton.waitForExistence(timeout: 5) {
            mapButton.tap()
        }
    }
    
    private func navigateToFeed() {
        let tabBar = app.tabBars.firstMatch
        let feedButton = tabBar.buttons["Feed"]
        if feedButton.waitForExistence(timeout: 5) {
            feedButton.tap()
        }
    }
    
    private func navigateToCamera() {
        let tabBar = app.tabBars.firstMatch
        let cameraButton = tabBar.buttons["Camera"]
        if cameraButton.waitForExistence(timeout: 5) {
            cameraButton.tap()
        }
    }
    
    private func navigateToProfile() {
        let tabBar = app.tabBars.firstMatch
        let profileButton = tabBar.buttons["Profile"]
        if profileButton.waitForExistence(timeout: 5) {
            profileButton.tap()
        }
    }
    
    // MARK: - Screenshot Helper
    
    private func takeScreenshot(name: String) {
        // This calls fastlane's snapshot function
        snapshot(name)
    }
}

// MARK: - XCUIElement Extensions

extension XCUIElement {
    /// Waits for element to exist and then taps it
    func tapWhenReady(timeout: TimeInterval = 5) {
        _ = self.waitForExistence(timeout: timeout)
        if self.exists && self.isHittable {
            self.tap()
        }
    }
    
    /// Waits for element with custom timeout
    @discardableResult
    func waitForExistence(timeout: TimeInterval = 5) -> Bool {
        return self.waitForExistence(timeout: timeout)
    }
}
