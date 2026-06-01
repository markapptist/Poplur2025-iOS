import Foundation
import SwiftUI

/// Configuration for handling screenshot mode
/// Activated when app is launched with UI_TESTING or SCREENSHOTS_MODE arguments
struct ScreenshotConfiguration {
    
    /// Check if app is running in screenshot mode
    static var isScreenshotMode: Bool {
        return ProcessInfo.processInfo.arguments.contains("SCREENSHOTS_MODE") ||
               ProcessInfo.processInfo.arguments.contains("UI_TESTING")
    }
    
    /// Check if onboarding should be skipped
    static var shouldSkipOnboarding: Bool {
        return ProcessInfo.processInfo.arguments.contains("SKIP_ONBOARDING") ||
               isScreenshotMode
    }
    
    /// Check if demo data should be used
    static var shouldUseDemoData: Bool {
        return ProcessInfo.processInfo.arguments.contains("USE_DEMO_DATA") ||
               isScreenshotMode
    }
    
    /// Configure app for screenshots
    static func configure() {
        if isScreenshotMode {
            // Disable animations for cleaner screenshots
            UIView.setAnimationsEnabled(false)
            
            // Set user defaults for clean state
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            UserDefaults.standard.set(true, forKey: "useDemoData")
            
            // Clear any existing data that might interfere
            UserDefaults.standard.set(true, forKey: "isScreenshotMode")
            
            print("📸 Screenshot mode activated")
        }
    }
    
    /// Reset configuration after screenshots
    static func reset() {
        UserDefaults.standard.removeObject(forKey: "isScreenshotMode")
        UIView.setAnimationsEnabled(true)
    }
}

// MARK: - Demo Data for Screenshots

struct DemoDataManager {
    
    /// Create beautiful demo posts for screenshots
    static func createDemoPosts() -> [Any] {
        // Return demo posts that will look good in screenshots
        // You'll need to implement this based on your Post model
        return []
    }
    
    /// Create demo user profile for screenshots
    static func createDemoProfile() -> Any? {
        // Return demo profile data
        return nil
    }
    
    /// Setup all demo data for screenshots
    static func setupForScreenshots() {
        guard ScreenshotConfiguration.isScreenshotMode else { return }
        
        // Setup demo posts
        let posts = createDemoPosts()
        // Store in your data manager
        
        // Setup demo profile
        let profile = createDemoProfile()
        // Store in your data manager
        
        print("📸 Demo data configured for screenshots")
    }
}
