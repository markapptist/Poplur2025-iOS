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

        PoplurDiagLog.markLaunch()
        // Read the phone's own thermal state rather than asking whether it feels
        // hot. Also enables battery reporting, which the probe includes.
        UIDevice.current.isBatteryMonitoringEnabled = true
        Task { @MainActor in PoplurThermalProbe.start() }

        // Always configure Firebase (needed for Auth).
        FirebaseBootstrap.configureIfNeeded()

        // Listen for the capture flows' "upload this" notifications. Without this
        // observer every capture route (native overlay, map post, web composer)
        // showed an uploading banner and then dropped the media on the floor.
        PostUploadService.shared.start()

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
    @State private var isAuthenticatedHomeReady = false
    @State private var authTransitionToken = 0
    @State private var isWelcomePanelVisible = true
    @State private var showSplash: Bool
    @Environment(\.scenePhase) private var scenePhase

    /// Phase 1 web-embed migration: the pre-login flow (splash + welcome) is the
    /// APPROVED web screens hosted in a WKWebView (`PreloginWebView`) rather than
    /// native remakes. Flip to `false` to restore the native clay splash +
    /// `WelcomeView` path — the migration is deliberately kept minimal and
    /// reversible. When on: the native clay splash is neutralized (the web splash
    /// shows instead) and the native pre-login music is silenced (the web splash
    /// plays its own radio bed).
    private let usePreloginWebEmbed = true

    /// True only while WelcomeView (or its Login/Sign Up pushes) is the visible screen —
    /// not during the brief auth-resolving spinner, so returning signed-in users never hear
    /// a momentary blip of music before landing on HomeView.
    private var isPreLoginVisible: Bool {
        !auth.isAuthenticated && !auth.isResolvingAuthState
    }

    init() {
        FirebaseBootstrap.configureIfNeeded()
        _auth = StateObject(wrappedValue: AuthViewModel())
        _showSplash = State(
            initialValue: !ProcessInfo.processInfo.arguments.contains("-SkipClaySplash")
        )
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                #if DEBUG
                if ProcessInfo.processInfo.environment["FPS_DEMO"] == "1" {
                    // Launch straight into the native SpriteKit game (bypasses login) for verification.
                    PoplurFPSGameSheet()
                } else if let verificationTab = PoplurVerificationLaunch.tab {
                    if PoplurWebHome.isEnabled {
                        // Physical verification must exercise the same approved
                        // web Home surface customers receive. The old path
                        // mounted native HomeView in preview mode, which drew a
                        // complete legacy chrome layer over the current Home.
                        PostLoginHomeSurface(initialTab: verificationTab)
                    } else {
                        HomeView(initialTab: verificationTab)
                            .environmentObject(AuthViewModel(previewAuthenticated: true))
                            .environment(\.layoutPreviewMode, true)
                            .environment(\.homeViewIsPreviewRuntime, true)
                            .environment(\.previewSelectedTab, PoplurVerificationLaunch.previewTab(for: verificationTab))
                    }
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
            .environmentObject(preLoginMusic)
            .overlay {
                if stripeCoordinator.isVisible {
                    StripeTransitionOverlay(coordinator: stripeCoordinator)
                        .ignoresSafeArea()
                }
            }
            .overlay(alignment: .topLeading) {
                // The web pre-login owns its own audio + mute affordance, so the
                // native pre-login mute button is hidden while the web embed runs.
                if isPreLoginVisible && !isWelcomePanelVisible && !usePreloginWebEmbed {
                    PoplurMuteButton(music: preLoginMusic)
                        .padding(.leading, 20)
                        .padding(.top, 12)
                        .transition(.opacity)
                }
            }
            #if DEBUG
            .overlay(alignment: .topTrailing) {
                if ProcessInfo.processInfo.arguments.contains("-PoplurPerformanceOverlay") {
                    PoplurPerformanceDiagnosticsView()
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: .poplurWelcomePanelVisibilityChanged)) { note in
                isWelcomePanelVisible = (note.object as? Bool) ?? true
            }
            // Web Settings asked to end the session. The app owns AuthViewModel,
            // so the sign-out happens here; the auth state listener then flips
            // isAuthenticated and the pre-login surface comes back on its own.
            .onReceive(NotificationCenter.default.publisher(for: .PoplurSignOutRequested)) { _ in
                auth.signOut()
            }
            .onChange(of: isPreLoginVisible) { _, isVisible in
                if isVisible && !showSplash && !usePreloginWebEmbed {
                    preLoginMusic.start()
                } else {
                    preLoginMusic.stop()
                }
            }
            .onChange(of: showSplash) { _, splashing in
                if !splashing && isPreLoginVisible && !usePreloginWebEmbed {
                    preLoginMusic.start()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    PoplurPerformanceManager.shared.setApplicationLifecycle(.background)
                    preLoginMusic.stop()
                    NotificationCenter.default.post(name: .StopMapAudio, object: nil)
                    PostLoginHomeWebView.PoplurWebSpeech.shared.cancel()
                    CameraAIAnnouncer.shared.resetSession()
                case .inactive:
                    PoplurPerformanceManager.shared.setApplicationLifecycle(.inactive)
                    preLoginMusic.stop()
                    NotificationCenter.default.post(name: .StopMapAudio, object: nil)
                    // The VOICE, too. Everything else the app plays is an audio
                    // session this handler already closes, but speech comes out
                    // of AVSpeechSynthesizer instances that keep talking through
                    // a minimised app on their own. The web gate cancels its own
                    // line, and that is the right lever while the WebView is
                    // alive — but it cannot speak for the native announcer, and
                    // a backgrounded WebView may never get to run its handler at
                    // all. Stopping here is host-side and unconditional.
                    PostLoginHomeWebView.PoplurWebSpeech.shared.cancel()
                    CameraAIAnnouncer.shared.resetSession()
                case .active:
                    PoplurPerformanceManager.shared.setApplicationLifecycle(.active)
                    if isPreLoginVisible && !showSplash && !usePreloginWebEmbed {
                        preLoginMusic.start()
                    }
                @unknown default:
                    break
                }
            }
            .onAppear {
                if isPreLoginVisible && !showSplash && !usePreloginWebEmbed {
                    preLoginMusic.start()
                }
                // Sample notification authorization early: the Home URL is
                // built synchronously and needs to know whether to queue the
                // Poplur notifications card.
                PoplurPermissionRouting.refreshNotificationStatus()
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
            .overlay {
                // Phase 1: the native clay splash is neutralized — the APPROVED
                // web splash (inside PreloginWebView) is the only intro now, so no
                // native clay-intro plays before the web screens. Guarded by the
                // flag so flipping it off restores the native splash overlay.
                if showSplash && !usePreloginWebEmbed {
                    PoplurClaySplashView {
                        withAnimation(.easeOut(duration: 0.45)) {
                            showSplash = false
                        }
                    }
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
                // Match the approved, logo-free launch frame while Firebase restores the session.
                // This is intentionally content-free: no unapproved loading screen is presented.
                Color(red: 0.039, green: 0.027, blue: 0.035).ignoresSafeArea()
                    .transition(.opacity)
            } else if auth.isAuthenticated {
                ZStack {
                    if PoplurWebHome.isEnabled {
                        // Phase 3: the APPROVED web home (poplur-clay-map ViewHarness
                        // home twin, ?view=home) replaces the native HomeView. Native
                        // power (camera/ML, live feed, notifications) is bridged in over
                        // later phases through the same `poplur` channel. Flag-reversible
                        // to HomeView via UserDefaults "poplur_web_home".
                        // PostLoginHomeSurface = the web home PLUS the real native
                        // ML camera mounted behind it on the camera tab (Phase 3.5).
                        PostLoginHomeSurface(onReady: markAuthenticatedHomeReady)
                            .ignoresSafeArea()
                            // The approved splash is visually non-interactive, so
                            // block touches at the warmed Home surface too. Without
                            // this guard, a splash tap can pass through and unlock
                            // Feed audio underneath, exposing system media controls.
                            .allowsHitTesting(!showAuthTransition)
                            // The custom volume meter is NATIVE, and it moved out from
                            // under us when the home became a web surface: HomeView
                            // carried PoplurVolumeBars, and Phase 3 replaced HomeView
                            // with this WebView. The web twin cannot stand in — a page
                            // can neither read the iOS output volume nor suppress the
                            // system HUD, so the bars simply vanished post-login while
                            // pre-login (which kept this pair) still showed them.
                            // Same treatment as the pre-login embed below.
                            .overlay(SystemVolumeHUDSuppressor())
                            .volumeBarsOverlay()
                    } else {
                        HomeView()
                            .environmentObject(auth)
                            .onAppear {
                                // Let native Home complete its first layout pass before
                                // allowing the loading surface to reveal it.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    markAuthenticatedHomeReady()
                                }
                            }
                    }

                    if showAuthTransition {
                        // Only mount the approved clay barber-pole splash if the home
                        // has not become ready after its brief fast-path window. A
                        // cached feed should open directly without a loading screen.
                        PostLoginLoadingWebView(page: .splash)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .zIndex(100)
                    }
                }
                .task(id: auth.currentUser?.uid) {
                    await PoplurNotificationCenter.shared.refreshDailyNotificationForCurrentUser()
                    WatchRadiusSync.shared.refreshAndSendRadius()
                }
            } else if usePreloginWebEmbed {
                // Phase 1/2: the approved web splash → welcome, hosted edge-to-edge
                // in a WKWebView. Hands back to the post-login/home branch above
                // when auth resolves (Firebase state listener flips isAuthenticated).
                PreloginWebView(auth: auth, onComplete: {
                    // Phase-2 completion handoff. The web flow's `complete` action
                    // arrives here as the single native seam to the post-login path.
                    // Entry into HomeView still requires auth.isAuthenticated, which
                    // Phase 3 flips via real Firebase auth — so this does NOT fake a
                    // signed-in state, it just marks the handoff point.
                    print("[Poplur2025App] pre-login web flow reported complete — handing off to post-login path (Phase 3 gates real entry via auth state)")
                })
                    .ignoresSafeArea()
                    // Pre-login volume: the web radio changes the system volume, so
                    // suppress the iOS HUD (hidden MPVolumeView) and show the app's
                    // custom PoplurVolumeBars instead — mirroring HomeView. The
                    // deviceVolumeObserver env object is already injected app-level.
                    // The bridge sits behind the WebView (hidden); volumeBarsOverlay
                    // is a native overlay above the web content that ignores touches.
                    .overlay(SystemVolumeHUDSuppressor())
                    .volumeBarsOverlay()
                    .transition(.opacity)
            } else {
                WelcomeView()
                    .environmentObject(auth)
                    .volumeBarsOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: auth.isResolvingAuthState)
        .animation(.easeOut(duration: 0.3), value: showAuthTransition)
        // Explicit sign-IN and sign-UP both show the approved web Loading screen
        // (clay globe) before the home reveals — the moments the user asked to
        // cover. didSignUp is still cleared so it doesn't leak into later state.
        .onChange(of: auth.isAuthenticated) { oldValue, newValue in
            guard newValue else {
                authTransitionToken += 1
                showAuthTransition = false
                isAuthenticatedHomeReady = false
                return
            }
            guard !oldValue && !auth.isResolvingAuthState else { return }
            if auth.didSignUp { auth.didSignUp = false }
            triggerAuthTransition()
        }
        // Cold launch as a RETURNING signed-in user: auth resolves from the
        // restoring state straight to authenticated (no isAuthenticated edge), so
        // cover the home/map warm-up (globe→city fly-in + 3D load) with the same
        // Loading screen instead of dropping onto a half-booted map.
        .onChange(of: auth.isResolvingAuthState) { _, resolving in
            guard !resolving, auth.isAuthenticated, !showAuthTransition else { return }
            triggerAuthTransition()
        }
    }

    private func triggerAuthTransition() {
        authTransitionToken += 1
        let token = authTransitionToken
        showAuthTransition = false
        isAuthenticatedHomeReady = false
        // Give a warm/cached Home one first-paint window to reveal immediately.
        // If its local web bundle has not painted after that point, cover only
        // that real wait with the approved clay barber-pole splash. The previous
        // 350 ms window outlasted the generic readiness fallback, suppressing the
        // splash even on physical-device cold loads.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard token == authTransitionToken,
                  !isAuthenticatedHomeReady,
                  auth.isAuthenticated else { return }
            showAuthTransition = true
        }
        // Absolute native escape hatch. Neither the managed JavaScript clock,
        // WebKit navigation callbacks nor a renderer lease is allowed to own
        // the lifetime of this cover. A warm-device thermal tripwire can park
        // all three; without this independent deadline the splash WebView (and
        // its media process) could remain mounted forever. Home may continue
        // recovering behind it, but the cover itself is always dismantled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard token == authTransitionToken, auth.isAuthenticated else { return }
            isAuthenticatedHomeReady = true
            finishAuthTransitionIfReady()
        }
    }

    private func markAuthenticatedHomeReady() {
        guard auth.isAuthenticated else { return }
        isAuthenticatedHomeReady = true
        finishAuthTransitionIfReady()
    }

    private func finishAuthTransitionIfReady() {
        guard showAuthTransition, isAuthenticatedHomeReady else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            showAuthTransition = false
        }
    }
}
