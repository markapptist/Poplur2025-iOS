import SwiftUI

// Only import heavy frameworks in release on real device
import FirebaseAppCheck
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

        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        #endif

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
            CubeSkinStore.shared.syncAppIcon()
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

#if DEBUG
private enum PoplurVerificationLaunch {
    static var tab: AppTab? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let tabFlagIndex = arguments.firstIndex(of: "-PoplurVerificationTab") else { return nil }
        let tabValueIndex = arguments.index(after: tabFlagIndex)
        guard arguments.indices.contains(tabValueIndex) else { return nil }

        switch arguments[tabValueIndex].lowercased() {
        case "map": return .map
        case "record": return .record
        case "feed": return .feed
        case "profile": return .profile
        default: return nil
        }
    }

    static func previewTab(for tab: AppTab) -> PreviewAppTab {
        switch tab {
        case .map:
            return .map
        case .record:
            return .record
        case .feed, .settings:
            return .feed
        case .profile:
            return .profile
        }
    }
}
#endif

@main
struct Poplur2025App: App {
    // Attach AppDelegate to SwiftUI lifecycle
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var auth: AuthViewModel
    @StateObject private var stripeCoordinator = StripeTransitionCoordinator()

    init() {
        FirebaseBootstrap.configureIfNeeded()
        _auth = StateObject(wrappedValue: AuthViewModel())
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                #if DEBUG
                if let verificationTab = PoplurVerificationLaunch.tab {
                    HomeView(initialTab: verificationTab)
                        .environmentObject(AuthViewModel(previewAuthenticated: true))
                        .environment(\.layoutPreviewMode, true)
                        .environment(\.homeViewIsPreviewRuntime, true)
                        .environment(\.previewSelectedTab, PoplurVerificationLaunch.previewTab(for: verificationTab))
                } else {
                    authenticatedContent
                }
                #else
                authenticatedContent
                #endif
            }
            .toolbar(.hidden, for: .navigationBar)
            .poplurGlobalShaderScope(textIntensity: 0.72, iconIntensity: 0.72)
            // Global rounded font for the entire app
            .environment(\.font, .system(size: 16, weight: .semibold, design: .rounded))
            .environmentObject(stripeCoordinator)
            .overlay {
                if stripeCoordinator.isVisible {
                    StripeTransitionOverlay(coordinator: stripeCoordinator)
                        .ignoresSafeArea()
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

    @ViewBuilder
    private var authenticatedContent: some View {
        ZStack {
            if auth.isResolvingAuthState {
                ZStack {
                    Color.white.ignoresSafeArea()
                    if SettingsStore.shared.use3DLoadingScreen {
                        LoginCubeView()
                            .frame(width: 200, height: 200)
                    } else {
                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                    }
                }
                .transition(.opacity)
            } else if auth.isAuthenticated {
                HomeView()
                    .environmentObject(auth)
                    .task(id: auth.currentUser?.uid) {
                        await PoplurNotificationCenter.shared.refreshDailyNotificationForCurrentUser()
                        WatchRadiusSync.shared.refreshAndSendRadius()
                    }
                    .transition(.scale(scale: 0.88, anchor: .bottom).combined(with: .opacity))
            } else {
                WelcomeView()
                    .environmentObject(auth)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: auth.isAuthenticated)
        .animation(.easeOut(duration: 0.3), value: auth.isResolvingAuthState)
    }
}
