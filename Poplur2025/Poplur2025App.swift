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
        return env["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || env["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
            || env["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil
    }
}

private enum FirebaseBootstrap {
    static func configureIfNeeded() {
        guard !PreviewEnv.isPreview else {
            print("[FirebaseBootstrap] Preview mode - skipping Firebase initialization")
            return
        }

        guard FirebaseApp.app() == nil else { return }

        FirebaseApp.configure()

        // Disable Firestore offline persistence in simulator to avoid disk space issues.
        #if targetEnvironment(simulator)
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = false
        Firestore.firestore().settings = settings
        #endif
    }
}

// AppDelegate: configure SDKs
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        // Exit early if in preview mode
        guard !PreviewEnv.isPreview else {
            print("[AppDelegate] Running in Preview mode - skipping all SDK initialization")
            return true
        }

        // Always configure Firebase (needed for Auth).
        FirebaseBootstrap.configureIfNeeded()

        // Defer ad SDK init to after first frame — MobileAds.shared.start() is synchronous
        // and can block the main thread for 100–300 ms, delaying first render.
        DispatchQueue.main.async {
            #if !DEBUG && !targetEnvironment(simulator) && canImport(GoogleMobileAds)
            MobileAds.shared.start(completionHandler: nil)
            #endif
            #if !targetEnvironment(simulator)
            AdManager.shared.start()
            #endif
        }

        Task { @MainActor in
            PoplurNotificationCenter.shared.configure()
            WatchRadiusSync.shared.start()
        }

        // Replicate API key — sourced from Secrets.swift (gitignored, never committed)
        if UserDefaults.standard.string(forKey: "poplur_replicate_key") == nil {
            UserDefaults.standard.set(Secrets.replicateAPIKey, forKey: "poplur_replicate_key")
        }

        // Claude API key for AI bumper scripts
        if !Secrets.claudeAPIKey.isEmpty {
            UserDefaults.standard.set(Secrets.claudeAPIKey, forKey: "poplur_claude_key")
        }

        // ElevenLabs TTS key — free tier, no card needed (elevenlabs.io)
        if !Secrets.elevenLabsAPIKey.isEmpty {
            UserDefaults.standard.set(Secrets.elevenLabsAPIKey, forKey: "poplur_elevenlabs_key")
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

    @StateObject private var auth: AuthViewModel

    init() {
        FirebaseBootstrap.configureIfNeeded()
        _auth = StateObject(wrappedValue: AuthViewModel())
    }
    
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
                        .task(id: auth.currentUser?.uid) {
                            await PoplurNotificationCenter.shared.refreshDailyNotificationForCurrentUser()
                            WatchRadiusSync.shared.refreshAndSendRadius()
                        }
                } else {
                    WelcomeView()
                        .environmentObject(auth)
                        .environmentObject(isometricBarSettings)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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

                let navigationAppearance = UINavigationBarAppearance()
                navigationAppearance.configureWithTransparentBackground()
                navigationAppearance.backgroundEffect = nil
                navigationAppearance.backgroundColor = .clear
                navigationAppearance.setBackIndicatorImage(UIImage(), transitionMaskImage: UIImage())
                UINavigationBar.appearance().standardAppearance = navigationAppearance
                UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
                UINavigationBar.appearance().compactAppearance = navigationAppearance
                UIBarButtonItem.appearance().setBackButtonTitlePositionAdjustment(
                    UIOffset(horizontal: -1000, vertical: 0),
                    for: .default
                )
            }
        }
    }
}
