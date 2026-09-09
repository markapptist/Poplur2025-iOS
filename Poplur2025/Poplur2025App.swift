import SwiftUI

// Only import heavy frameworks in release on real device
import FirebaseAppCheck
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
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

        #if DEBUG
        // Firebase prints the App Check debug token ONLY to the system console,
        // which is unreachable from a script here: `log stream --device-name` no
        // longer exists on macOS 26 and devicectl has no console subcommand. So a
        // debug build mirrors it into the diag log, which IS pullable over
        // devicectl, and registering a QA handset stops needing a human with
        // Xcode open. DEBUG only — a release build must never print a token that
        // would let anyone forge attestation against the enforcing callables.
        if let app = FirebaseApp.app(), let debugProvider = AppCheckDebugProvider(app: app) {
            PoplurDiagLog.append("[AppCheck] debug token: \(debugProvider.localDebugToken())")
        }
        #endif

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

        // Consumable approvals can arrive after the Store screen or even the
        // previous process is gone. Keep one account-bound StoreKit observer
        // alive for the application lifetime so verified credits are recovered
        // without asking the user to rebuild the old web bag.
        Task { @MainActor in
            PoplurCardPurchaseService.shared.startObservingTransactions()
        }

        Task { @MainActor in
            PoplurNotificationCenter.shared.configure()
            WatchRadiusSync.shared.start()
        }

        // Engagement push notifications, phase 1. This asks iOS for an APNs token
        // and wires the FCM delegate; it does NOT request notification
        // authorization — that ask stays with the clay primer card
        // (PoplurPermissionRouting.requestNotificationsAfterPrimer), because
        // Apple's sheet must never appear with no Poplur card in front of it.
        Task { @MainActor in PoplurMessaging.shared.start() }

        return true
    }

    /// Hands the APNs token to FCM.
    ///
    /// Without this, FirebaseMessaging can mint an FCM token that has no APNs
    /// token underneath it — registration looks completely healthy and every
    /// send fails silently. PoplurMessaging logs that state explicitly for the
    /// same reason.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        PoplurDiagLog.append("[PoplurMessaging] APNs token received (\(deviceToken.count) bytes)")
        // Sync from HERE, not only from the auth listener. FCM refuses to mint a
        // token before its APNs token is set, and the auth listener fires first —
        // device logs showed "No APNS token specified before fetching FCM Token"
        // on every launch, recovering a second later only because the Messaging
        // delegate fires independently. This makes the ordering deliberate rather
        // than leaving the first attempt to fail and be rescued.
        Task { @MainActor in PoplurMessaging.shared.syncTokenForCurrentUser() }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected on the simulator, which has no APNs. On a device this names a
        // real provisioning problem — most often a missing Push Notifications
        // capability or an App ID without push enabled.
        PoplurDiagLog.append("[PoplurMessaging] APNs registration FAILED: \(error.localizedDescription)")
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
    @State private var authTransitionEarliestFinish = Date.distantPast
    @Environment(\.scenePhase) private var scenePhase

    /// True only while the native signed-out flow is visible —
    /// not during the brief auth-resolving spinner, so returning signed-in users never hear
    /// a momentary blip of music before landing on HomeView.
    private var isPreLoginVisible: Bool {
        !auth.canEnterHome && !auth.isResolvingAuthState
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
                            // Keep direct-to-tab device verification behaviorally
                            // identical to the authenticated web-home route below.
                            // Without this pair, launching with
                            // -PoplurVerificationTab silently dropped Poplur's
                            // custom hardware-volume bars and restored the system
                            // HUD for the entire verification session.
                            .overlay(SystemVolumeHUDSuppressor())
                            .volumeBarsOverlay()
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
                if isVisible && !showSplash && scenePhase == .active {
                    preLoginMusic.start()
                } else {
                    preLoginMusic.stop()
                }
            }
            .onChange(of: showSplash) { _, splashing in
                if !splashing && isPreLoginVisible && scenePhase == .active {
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
                    PoplurBackgroundResourceFence.shared.enterBackground()
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
                    PoplurBackgroundResourceFence.shared.enterForeground()
                    if isPreLoginVisible && !showSplash && scenePhase == .active {
                        preLoginMusic.start()
                    }
                @unknown default:
                    break
                }
            }
            .onAppear {
                if isPreLoginVisible && !showSplash && scenePhase == .active {
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

        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        ZStack {
            if auth.canEnterHome && !auth.isResolvingAuthState {
                ZStack {
                    if PoplurWebHome.isEnabled {
                        // Phase 3: the APPROVED web home (poplur-clay-map ViewHarness
                        // home twin, ?view=home) replaces the native HomeView. Native
                        // power (camera/ML, live feed, notifications) is bridged in over
                        // later phases through the same `poplur` channel. QA can
                        // still reach HomeView with -DisableWebHome, while normal
                        // launches retain one canonical route/control owner.
                        // PostLoginHomeSurface = the web home PLUS the real native
                        // ML camera mounted behind it on the camera tab (Phase 3.5).
                        PostLoginHomeSurface(onReady: markAuthenticatedHomeReady)
                            // .container rather than a bare ignoresSafeArea(): the bare form
                            // ignores EVERY region including .keyboard, which switches off
                            // SwiftUI's automatic keyboard avoidance. The web surface then keeps
                            // its full-height frame while the keyboard sits on top of it, burying
                            // whatever field has focus. Ignoring only the container keeps the
                            // layout edge-to-edge under the status bar and home indicator, and
                            // lets the keyboard shrink the frame so the page reflows above it —
                            // every web screen, without per-screen work.
                            .ignoresSafeArea(.container, edges: .all)
                            // The approved splash is visually non-interactive, so
                            // block touches at the warmed Home surface too. Without
                            // this guard, a splash tap can pass through and unlock
                            // Feed audio underneath, exposing system media controls.
                            .allowsHitTesting(!showAuthTransition && !showSplash)
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
                        // The same native video splash covers every auth handoff.
                        PostLoginLoadingWebView()
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .zIndex(100)
                    }
                }
                .task(id: auth.currentUser?.uid) {
                    // Pre-login does not need an ad WebView or an inventory preload.
                    #if !targetEnvironment(simulator)
                    AdManager.shared.start()
                    #endif
                    await PoplurNotificationCenter.shared.refreshDailyNotificationForCurrentUser()
                    WatchRadiusSync.shared.refreshAndSendRadius()
                }
            } else if !showSplash && !auth.isResolvingAuthState {
                NativePreloginView()
                    .ignoresSafeArea(.container, edges: .all)
                    .environmentObject(auth)
                    .overlay(SystemVolumeHUDSuppressor())
                    .volumeBarsOverlay()
                    .transition(.opacity)
            }
            // A restored session warms Home beneath the one native intro.
            // Waiting to create Home until the video ended left a blank load gap.
            if showSplash || auth.isResolvingAuthState {
                PoplurClaySplashView {
                    withAnimation(.easeOut(duration: 0.3)) { showSplash = false }
                }.environmentObject(auth).ignoresSafeArea().transition(.opacity).zIndex(200)
            }
        }
        .animation(.easeOut(duration: 0.3), value: auth.isResolvingAuthState)
        .animation(.easeOut(duration: 0.3), value: showAuthTransition)
        // Sign-in and completed signup share the native video splash while Home loads.
        .onChange(of: auth.canEnterHome) { oldValue, newValue in
            guard newValue else {
                authTransitionToken += 1
                showAuthTransition = false
                isAuthenticatedHomeReady = false
                return
            }
            guard !oldValue && !auth.isResolvingAuthState && !showSplash else { return }
            if auth.didSignUp { auth.didSignUp = false }
            triggerAuthTransition()
        }
        // Cold launch as a RETURNING signed-in user: auth resolves from the
        // restoring state straight to authenticated (no isAuthenticated edge),
        // so show the same approved splash as signed-out launch.
        .onChange(of: auth.isResolvingAuthState) { _, resolving in
            guard !resolving, auth.canEnterHome, !showSplash, !showAuthTransition else { return }
            triggerAuthTransition()
        }
    }

    private func triggerAuthTransition() {
        authTransitionToken += 1
        let token = authTransitionToken
        // Physical devices can report the warmed Home document ready before a
        // delayed cover ever mounts. Present the approved signed-out splash on
        // the authentication edge itself, then enforce its authored 3.2-second
        // beat so readiness cannot skip it after a cold or cached launch.
        showAuthTransition = true
        isAuthenticatedHomeReady = false
        authTransitionEarliestFinish = Date().addingTimeInterval(
            PoplurPreloginWeb.splashDurationSeconds
        )
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
        let remaining = authTransitionEarliestFinish.timeIntervalSinceNow
        if remaining > 0 {
            let token = authTransitionToken
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                guard token == authTransitionToken,
                      auth.isAuthenticated,
                      isAuthenticatedHomeReady else { return }
                finishAuthTransitionIfReady()
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.45)) {
            showAuthTransition = false
        }
    }
}
