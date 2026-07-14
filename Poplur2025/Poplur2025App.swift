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

        return true
    }

    /// The app is portrait-only except while the PoplurFPS game is on screen, which
    /// may rotate to landscape (immersive) or portrait (arcade cabinet).
    static var fpsGameActive = false
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.fpsGameActive ? .allButUpsideDown : .portrait
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
    @StateObject private var deviceVolumeObserver = DeviceVolumeObserver()
    @StateObject private var preLoginMusic = PreLoginMusicPlayer()
    @State private var showAuthTransition = false
    @State private var isWelcomePanelVisible = true
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

    /// True only while WelcomeView (or its Login/Sign Up pushes) is the visible screen —
    /// not during the brief auth-resolving spinner, so returning signed-in users never hear
    /// a momentary blip of music before landing on HomeView.
    private var isPreLoginVisible: Bool {
        !auth.isAuthenticated && !auth.isResolvingAuthState
    }

    init() {
        FirebaseBootstrap.configureIfNeeded()
        _auth = StateObject(wrappedValue: AuthViewModel())
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                #if DEBUG
                if ProcessInfo.processInfo.environment["FPS_DEMO"] == "1" {
                    // Launch straight into the native SpriteKit game (bypasses login) for verification.
                    PoplurFPSGameSheet()
                } else if let verificationTab = PoplurVerificationLaunch.tab {
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
            .environmentObject(auth)
            .environmentObject(deviceVolumeObserver)
            .overlay {
                if stripeCoordinator.isVisible {
                    StripeTransitionOverlay(coordinator: stripeCoordinator)
                        .ignoresSafeArea()
                }
            }
            .overlay(alignment: .topLeading) {
                if isPreLoginVisible && !isWelcomePanelVisible {
                    PoplurMuteButton(music: preLoginMusic)
                        .padding(.leading, 20)
                        .padding(.top, 12)
                        .transition(.opacity)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .poplurWelcomePanelVisibilityChanged)) { note in
                isWelcomePanelVisible = (note.object as? Bool) ?? true
            }
            .onChange(of: isPreLoginVisible) { _, isVisible in
                if isVisible && !showSplash {
                    preLoginMusic.start()
                } else {
                    preLoginMusic.stop()
                }
            }
            .onChange(of: showSplash) { _, splashing in
                // once the splash clears, start pre-login music if we landed on Welcome
                if !splashing && isPreLoginVisible {
                    preLoginMusic.start()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background, .inactive:
                    preLoginMusic.stop()
                    NotificationCenter.default.post(name: .StopMapAudio, object: nil)
                case .active:
                    if isPreLoginVisible && !showSplash {
                        preLoginMusic.start()
                    }
                @unknown default:
                    break
                }
            }
            .onAppear {
                if isPreLoginVisible && !showSplash {
                    preLoginMusic.start()
                }
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
            // Cold-launch clay splash: plays over everything, then routes underneath.
            .overlay {
                if showSplash {
                    PoplurClaySplashView(onFinished: {
                        withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
                    })
                    .environmentObject(auth)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        ZStack {
            if auth.isResolvingAuthState {
                // The clay splash is the only launch loader now — no white spinning-cube cover.
                // Auth resolves behind the splash, so this dark placeholder is never actually seen.
                Color(red: 0.039, green: 0.027, blue: 0.035).ignoresSafeArea()
                    .transition(.opacity)
            } else if showAuthTransition {
                // Post-login: auth transition video
                LoadingTransitionVideoView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
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
                    .volumeBarsOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: auth.isAuthenticated)
        .animation(.easeOut(duration: 0.3), value: auth.isResolvingAuthState)
        .animation(.easeOut(duration: 0.3), value: showAuthTransition)
        // Returning users: no transition — skip straight to HomeView when auth resolves.
        // Fire auth transition only when the user explicitly signs in or signs up.
        .onChange(of: auth.isAuthenticated) { oldValue, newValue in
            guard newValue && !oldValue && !auth.isResolvingAuthState else { return }
            if auth.didSignUp {
                // New sign-up: play stripe animation, reset flag.
                auth.didSignUp = false
                stripeCoordinator.trigger { }
            } else {
                // Explicit sign-in: show the loading video before revealing the feed.
                triggerAuthTransition()
            }
        }
    }

    private func triggerAuthTransition() {
        showAuthTransition = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                showAuthTransition = false
            }
        }
    }
}
