import SwiftUI

// Only import heavy frameworks in release on real device
import FirebaseCore
import FirebaseFirestore
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

// Detect when running inside Xcode Previews
private enum PreviewEnv {
    static var isPreview: Bool {
        let env = ProcessInfo.processInfo.environment
        // Xcode sets one of these when hosting previews
        return env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || env["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }
}

// AppDelegate: configure SDKs
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if !PreviewEnv.isPreview {
            // Always configure Firebase (needed for Auth)
            if FirebaseApp.app() == nil {
                FirebaseApp.configure()
                
                // Disable Firestore offline persistence in simulator to avoid disk space issues
                #if targetEnvironment(simulator)
                let settings = FirestoreSettings()
                settings.isPersistenceEnabled = false
                Firestore.firestore().settings = settings
                #endif
            }
            
            // Only start ads in release builds on real devices
            #if !DEBUG && !targetEnvironment(simulator) && canImport(GoogleMobileAds)
            MobileAds.shared.start(completionHandler: nil)
            #endif
            
            #if !targetEnvironment(simulator)
            AdManager.shared.start()
            #endif
        } else {
            // Skip heavy SDK bootstrap in previews to avoid timeouts/crashes
            print("[AppDelegate] Skipping Firebase/Ads init in Previews")
        }
        return true
    }
}

// Optional: only needed if you explicitly configured a SceneDelegate in Info.plist.
// If you do not reference this class in UIApplicationSceneManifest, you can delete it.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    // No Snapchat URL handling anymore
}

@main
struct Poplur2025App: App {
    // Attach AppDelegate to SwiftUI lifecycle
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var auth = AuthViewModel()
    
    @StateObject private var isometricBarSettings: IsometricBarSettings = {
        let s = IsometricBarSettings()
        s.horizontalOffset = 24
        s.bottomOffset = 12
        s.barWidth = 98
        s.barHeight = 390
        s.barTiltDegrees = -8
        return s
    }()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if auth.isAuthenticated {
                    HomeView()
                        .environmentObject(auth)
                        .environmentObject(isometricBarSettings)
                } else {
                    WelcomeView()
                        .environmentObject(auth)
                        .environmentObject(isometricBarSettings)
                }
            }
            .onAppear {
                let appearance = UITabBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundEffect = nil
                appearance.backgroundColor = .clear
                UITabBar.appearance().standardAppearance = appearance
                if #available(iOS 15.0, *) {
                    UITabBar.appearance().scrollEdgeAppearance = appearance
                }
                UITabBar.appearance().isTranslucent = true
            }
        }
    }
}
