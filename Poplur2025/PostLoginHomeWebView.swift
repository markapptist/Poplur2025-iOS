import AVFoundation
import SwiftUI
import WebKit
import os.log
import CoreLocation
import Photos
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import UserNotifications
import ImageIO

enum PoplurWebCaptureStore {
    struct Item {
        let data: Data?
        let fileURL: URL?
        let mimeType: String
    }

    private struct Entry {
        let item: Item
        let memoryCost: Int
        let ownsTemporaryFile: Bool
        var accessSequence: UInt64
    }

    /// Captures are short-lived hand-offs into the web composer, not a media
    /// library. Keep their resident bytes and openable URLs strictly bounded.
    private static let itemLimit = 6
    private static let memoryByteLimit = 32 * 1_024 * 1_024
    private static var items: [String: Entry] = [:]
    private static var memoryByteCount = 0
    private static var accessSequence: UInt64 = 0
    private static var transientCameraRollKey: String?
    private static var transientVideoKey: String?
    private static let lock = NSLock()

    static func register(image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return register(data: data, mimeType: "image/jpeg")
    }

    /// Register already-encoded capture data without another lossy round trip.
    /// Camera Roll uses this for its orientation-correct, 4K-bounded JPEG, then
    /// hands WebKit a small custom-scheme URL instead of a multi-megabyte JS string.
    static func register(data: Data, mimeType: String) -> String? {
        guard data.count <= memoryByteLimit else { return nil }
        let key = "\(UUID().uuidString).\(fileExtension(for: mimeType))"
        lock.lock()
        insertLocked(
            Item(data: data, fileURL: nil, mimeType: mimeType),
            for: key,
            memoryCost: data.count,
            ownsTemporaryFile: false
        )
        lock.unlock()
        return key
    }

    /// Camera Roll selections can each be several megabytes. Keep the current
    /// one alive for its composer URL, but replace the previous roll-only item
    /// on the next selection so browsing does not grow resident memory forever.
    static func registerCameraRollAsset(data: Data, mimeType: String) -> String? {
        guard data.count <= memoryByteLimit else { return nil }
        let key = "roll-\(UUID().uuidString).\(fileExtension(for: mimeType))"
        lock.lock()
        if let previous = transientCameraRollKey { removeLocked(previous) }
        insertLocked(
            Item(data: data, fileURL: nil, mimeType: mimeType),
            for: key,
            memoryCost: data.count,
            ownsTemporaryFile: false
        )
        transientCameraRollKey = key
        lock.unlock()
        return key
    }

    private static func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/png": return "png"
        case "image/heic", "image/heif": return "heic"
        default: return "jpg"
        }
    }

    static func register(videoURL: URL) -> String {
        let ext = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension
        let key = "\(UUID().uuidString).\(ext)"
        let mimeType = ext.lowercased() == "mp4" ? "video/mp4" : "video/quicktime"
        lock.lock()
        if let previous = transientVideoKey { removeLocked(previous) }
        insertLocked(
            Item(data: nil, fileURL: videoURL, mimeType: mimeType),
            for: key,
            memoryCost: 0,
            ownsTemporaryFile: PoplurTemporaryFileOwnership.isOwned(videoURL)
        )
        transientVideoKey = key
        lock.unlock()
        return key
    }

    /// A selected Photos video stays file-backed all the way into WebKit. This
    /// avoids decoding it into a base64 payload just to write it back to disk.
    static func registerCameraRollVideoAsset(videoURL: URL) -> String {
        register(videoURL: videoURL)
    }

    static func item(for key: String) -> Item? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = items[key] else { return nil }
        accessSequence &+= 1
        entry.accessSequence = accessSequence
        items[key] = entry
        return entry.item
    }

    static func remove(_ key: String) {
        lock.lock()
        removeLocked(key)
        lock.unlock()
    }

    static func purge() {
        lock.lock()
        for key in Array(items.keys) {
            removeLocked(key)
        }
        memoryByteCount = 0
        transientCameraRollKey = nil
        transientVideoKey = nil
        lock.unlock()
    }

    private static func insertLocked(
        _ item: Item,
        for key: String,
        memoryCost: Int,
        ownsTemporaryFile: Bool
    ) {
        removeLocked(key)
        accessSequence &+= 1
        items[key] = Entry(
            item: item,
            memoryCost: memoryCost,
            ownsTemporaryFile: ownsTemporaryFile,
            accessSequence: accessSequence
        )
        memoryByteCount += memoryCost

        while items.count > itemLimit || memoryByteCount > memoryByteLimit {
            guard let oldestKey = items.min(by: {
                $0.value.accessSequence < $1.value.accessSequence
            })?.key else { break }
            removeLocked(oldestKey)
        }
    }

    private static func removeLocked(_ key: String) {
        guard let removed = items.removeValue(forKey: key) else { return }
        memoryByteCount = max(0, memoryByteCount - removed.memoryCost)
        if transientCameraRollKey == key { transientCameraRollKey = nil }
        if transientVideoKey == key { transientVideoKey = nil }
        if removed.ownsTemporaryFile, let fileURL = removed.item.fileURL {
            PoplurTemporaryFileOwnership.deleteIfOwned(fileURL)
        }
    }
}

/// Durable home-profile media lives outside the short-lived camera hand-off
/// store. It is served through the same custom scheme as captures, so WKWebView
/// can range-seek the ten-second clip after an app relaunch without receiving a
/// large base64 message from JavaScript again.
enum PoplurProfileSelfieStore {
    private static let extensionKey = "poplur.profile.selfieVideoExtension"

    private static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func fileExtension(for mimeType: String) -> String? {
        switch mimeType.lowercased() {
        case "video/mp4", "video/mp4;codecs=avc1.42e01e": return "mp4"
        case "video/webm", "video/webm;codecs=vp8": return "webm"
        case "video/quicktime": return "mov"
        default: return nil
        }
    }

    private static func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        default: return "video/quicktime"
        }
    }

    static func sourceURL() -> String? {
        guard let ext = UserDefaults.standard.string(forKey: extensionKey),
              FileManager.default.fileExists(atPath: videoURL(extension: ext).path) else { return nil }
        return "\(PoplurClayWebMap.scheme)://\(PoplurClayWebMap.host)/profile-selfie.\(ext)"
    }

    static func item(for relativePath: String) -> (url: URL, mimeType: String)? {
        guard relativePath.hasPrefix("/profile-selfie."),
              !relativePath.dropFirst("/profile-selfie.".count).contains("/"),
              let ext = UserDefaults.standard.string(forKey: extensionKey),
              relativePath == "/profile-selfie.\(ext)" else { return nil }
        let url = videoURL(extension: ext)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (url, mimeType(for: ext))
    }

    @discardableResult
    static func persist(data: Data, mimeType: String) -> String? {
        guard !data.isEmpty, data.count <= 12_000_000,
              let ext = fileExtension(for: mimeType) else { return nil }
        let destination = videoURL(extension: ext)
        do {
            for staleExtension in ["mp4", "webm", "mov"] where staleExtension != ext {
                try? FileManager.default.removeItem(at: videoURL(extension: staleExtension))
            }
            try data.write(to: destination, options: .atomic)
            UserDefaults.standard.set(ext, forKey: extensionKey)
            return sourceURL()
        } catch {
            print("[PostLoginHomeWebView] failed to persist profile selfie: \(error.localizedDescription)")
            return nil
        }
    }

    static func extensionForPersistedVideo() -> String? {
        UserDefaults.standard.string(forKey: extensionKey)
    }

    private static func videoURL(extension ext: String) -> URL {
        directory.appendingPathComponent("profile-selfie.\(ext)")
    }
}

// MARK: - Post-login HOME Web Embed (Phase 3)
//
// The approved post-login home is the poplur-clay-map ViewHarness home twin,
// served at ?view=home. It ships in the SAME bundle the clay map already embeds
// (ClayMapWeb/, synced by poplur-clay-map/scripts/sync-mobile.sh) — App.tsx routes
// to <ViewHarness> whenever a ?view= / #view is present, else the map. So the home
// reuses the exact custom-scheme + bridge infrastructure PoplurClayMapView ships:
// the same origin, scheme handler, and `poplur` message channel.
//
// This intentionally REPLACES the native HomeView with the approved web home. The
// home's tabs (map/feed/camera/profile) are the web twin today; real device power
// (native camera + ML, live feed, notifications) is bridged in over later phases
// through the same JS⇄native `poplur` channel that already drives the map's
// haptics/flyTo and the pre-login screens' Firebase auth — the shell lands first,
// functionality is wired in tab by tab.
//
// Reversible for QA with the explicit -DisableWebHome launch argument. Normal
// launches always use one canonical shell so a retained development default
// cannot switch the map route and its control owner between app installs.

enum PoplurWebHome {
    /// The shared web Home is the production route. Keep the legacy native
    /// Home reachable only through an intentional QA launch configuration.
    static var isEnabled: Bool {
        !ProcessInfo.processInfo.arguments.contains("-DisableWebHome")
    }

    /// The approved home twin: the shared clay bundle opened on its home tab.
    /// `tabs=1` shows the bottom tab pills; the scheme handler ignores the query
    /// and serves index.html, while App.tsx reads ?view / #view to pick the view.
    static var homeURL: URL? { url(for: "home") }

    static func url(for view: String) -> URL? {
        var components = URLComponents()
        components.scheme = PoplurClayWebMap.scheme
        components.host = PoplurClayWebMap.host
        components.path = "/index.html"
        var queryItems = [
            URLQueryItem(name: "view", value: view),
            URLQueryItem(name: "tabs", value: "1"),
            URLQueryItem(name: "v", value: PoplurPreloginWeb.buildStamp)
        ]
        if PoplurNativeAdaptiveMap.isEnabled {
            // Home keeps drawing the approved clay HUD, but it must not mount
            // the Mapbox/WebGL iframe while the native renderer owns Map.
            queryItems.append(URLQueryItem(name: "nativeMap", value: "1"))
        }
        queryItems.append(contentsOf: PoplurPermissionRouting.homePrimerQueryItems())
        components.queryItems = queryItems
        return components.url
    }
}

/// Per-process routing between the signed-out and authenticated permission
/// primers. A signed-out user answers the approved pre-login cards; that launch
/// must not immediately show the same cards again while auth hands off to Home.
/// The handoff marker resets naturally on a cold launch, while each answered
/// permission persists in UserDefaults so a returning signed-in user receives
/// Home's custom cards only for genuinely unanswered, still-undecided access.
enum PoplurPermissionRouting {
    enum Permission: String {
        case location
        case photos
        case notifications
    }

    private static var preloginHandledThisLaunch = false
    private static let handledKeyPrefix = "poplur.permissionPrimer.handled."

    static func markPreloginHandledThisLaunch(permission: Permission? = nil) {
        preloginHandledThisLaunch = true
        if let permission { markHandled(permission) }
    }

    static func markHandled(_ permission: Permission) {
        UserDefaults.standard.set(true, forKey: handledKeyPrefix + permission.rawValue)
    }

    private static func wasHandled(_ permission: Permission) -> Bool {
        UserDefaults.standard.bool(forKey: handledKeyPrefix + permission.rawValue)
    }

    static func homePrimerQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []

        // Location and photos ARE asked by the signed-out pre-login cards, so a
        // launch that just answered them must not be shown the same two again
        // while auth hands off to Home.
        if !preloginHandledThisLaunch {
            if CLLocationManager().authorizationStatus == .notDetermined,
               !wasHandled(.location) {
                items.append(URLQueryItem(name: "askLocation", value: "1"))
            }
            if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined,
               !wasHandled(.photos) {
                items.append(URLQueryItem(name: "askPhotos", value: "1"))
            }
        }

        // Notifications are NOT part of the pre-login set, so the handoff guard
        // must not suppress them — doing so meant a user who signed in on this
        // launch was never offered the card at all. Status is async-only, so it
        // is sampled once per launch (see refreshNotificationStatus).
        // NOT asked on launch any more.
        //
        // Apple's notification sheet cannot be replaced or restyled — requesting
        // the permission always shows it — so the only thing an app controls is
        // WHEN it asks. Queuing the card automatically on the first authenticated
        // launch meant the system sheet arrived seconds after opening the app,
        // unprompted, which reads as the app throwing an OS alert at you.
        //
        // The ask now belongs to an explicit action: `requestNotifications` from
        // the web (the Settings control) still routes to
        // requestNotificationsAfterPrimer(), so notifications remain available —
        // they are opt-in rather than prompted.
        //
        // The STATUS is still reported, so the web knows whether tapping the
        // NOTIFICATIONS tile should raise the clay card or do nothing. Without
        // this the tile could not tell "never asked" from "already answered",
        // and the OS prompt is one-shot — asking twice is not possible.
        if notificationsUndetermined, !wasHandled(.notifications) {
            items.append(URLQueryItem(name: "notificationsUndetermined", value: "1"))
        }
        return items
    }

    /// UNUserNotificationCenter only reports status through a callback, but the
    /// Home URL is built synchronously. Sample it at launch so the primer can
    /// be queued without blocking, and treat "unknown yet" as "do not ask".
    private(set) static var notificationsUndetermined = false

    static func refreshNotificationStatus(_ done: (() -> Void)? = nil) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let undetermined = settings.authorizationStatus == .notDetermined
            DispatchQueue.main.async {
                notificationsUndetermined = undetermined
                done?()
            }
        }
    }

    /// Fired ONLY by the web card's Allow. Apple's sheet is one-shot per
    /// install, so it must never appear cold — see the Poplur card in
    /// HomeTwin.tsx.
    static func requestNotificationsAfterPrimer() {
        markHandled(.notifications)
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                guard granted else { return }
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            }
    }
}

/// Build-stamped cleanup of web caches left by an older embedded bundle. The
/// first navigation waits for the one required migration, and subsequent app
/// launches with the same bundle never churn WebKit's disk or memory caches.
@MainActor
enum PoplurWebCache {
    private static let completedBuildKey = "poplur.webCache.completedBuild.v2"
    private static var migrationInFlight = false
    private static var waiters: [() -> Void] = []

    static func prepareForCurrentBuild(completion: @escaping () -> Void) {
        let buildStamp = PoplurPreloginWeb.buildStamp
        if UserDefaults.standard.string(forKey: completedBuildKey) == buildStamp {
            completion()
            return
        }

        waiters.append(completion)
        guard !migrationInFlight else { return }
        migrationInFlight = true
        URLCache.shared.removeAllCachedResponses()
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
        ]
        WKWebsiteDataStore.default().removeData(
            ofTypes: types,
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) {
            Task { @MainActor in
                UserDefaults.standard.set(buildStamp, forKey: completedBuildKey)
                migrationInFlight = false
                let pending = waiters
                waiters.removeAll(keepingCapacity: false)
                PoplurDiagLog.append("[PoplurWebCache] migrated caches for \(buildStamp)")
                pending.forEach { $0() }
            }
        }
    }
}

struct PostLoginHomeWebView: UIViewRepresentable {
    /// The page currently hosting Home. The camera layer lives outside this
    /// view's coordinator but must reach the same document to hand it detection
    /// boxes, so the live web view is published here rather than threaded
    /// through every intermediate type.
    static weak var liveWebView: WKWebView?
    /// The coordinator owns renderer recovery, while the SwiftUI scene owns
    /// foreground state. Keeping the active coordinator here lets a deferred
    /// recovery resume only after UIKit has brought the app forward again.
    static weak var liveCoordinator: Coordinator?
    /// `evaluateJavaScript` completions are asynchronous. A parked delivery
    /// must not suspend the HUD after a newer running delivery has already
    /// reopened it, so every state handoff owns a monotonically newer token.
    @MainActor private static var cameraBudgetStateToken: UInt64 = 0
    /// The native-map experiment can own the Map tab without leaving the web
    /// navigator's motion pipeline running underneath it. Kept here as well as
    /// on the live coordinator so a toggle made just before WebKit is created is
    /// applied when the host comes online.
    @MainActor private static var nativeMapRendererActive = false

    /// Call from the native map host when its renderer becomes or stops being
    /// the visible Map-tab implementation. Other tabs keep their own motion
    /// policy; Camera can still request display-rate aiming.
    @MainActor
    static func setNativeMapRendererActive(_ active: Bool) {
        nativeMapRendererActive = active
        liveCoordinator?.setNativeMapRendererActive(active)
    }

    /// Hand the web overlay real boxes. JSON matches `Detection` in
    /// poplur-clay-map/src/mlDetect.ts: x/y/w/h normalised 0..1, top-left origin.
    static func sendDetections(_ json: String) {
        guard let webView = liveWebView else { return }
        webView.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('poplur-native-detections', { detail: \(json) })); true;"
        )
    }

    /// Native is the source of truth for the physical sensor lease. The web
    /// keeps only a small state object so a thermally parked camera can show
    /// its retained frame and require an explicit tap before restarting.
    @MainActor
    static func sendCameraBudgetState(_ update: CameraColdBudgetUpdate) {
        guard let webView = liveWebView else { return }
        cameraBudgetStateToken &+= 1
        let deliveryToken = cameraBudgetStateToken
        let managedWebView = webView as? PoplurManagedWebView
        if update.state != .parked {
            // Wake the HUD before telling React that capture is live so its
            // bounded indicators can paint immediately.
            managedWebView?.setLightweightOverlayRuntimeSuspended(false)
        }
        let payload: [String: Any] = [
            "state": update.state.rawValue,
            "reason": update.reason.rawValue,
            "canResume": update.canResume,
            "windowMs": update.windowMilliseconds
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('poplur-camera-budget', { detail: \(json) })); true;"
        ) { _, _ in
            guard update.state == .parked else { return }
            // Deliver the parked state first so React paints the retained-frame
            // resume affordance, then stop all governed HUD work. DOM pointer
            // events and the native message bridge remain available.
            DispatchQueue.main.async {
                guard Self.cameraBudgetStateToken == deliveryToken,
                      Self.liveWebView === webView else { return }
                managedWebView?.setLightweightOverlayRuntimeSuspended(true)
            }
        }
    }

    /// Mirrors the real UIKit lifecycle into the shared Home document. A
    /// WKWebView may emit `pagehide` on background without a paired `pageshow`,
    /// which used to leave the camera's native preview visible with all web HUD
    /// controls unmounted after reopening the app.
    @MainActor
    static func setApplicationActive(_ active: Bool) {
        guard let webView = liveWebView else { return }
        let activeLiteral = active ? "true" : "false"
        // WKWebView can miss pageshow after an app foreground cycle. Replaying it
        // lets the web runtime resume its own animation and media scheduling too.
        let lifecycleScript = active
            ? "window.dispatchEvent(new Event('pageshow')); window.dispatchEvent(new CustomEvent('poplur-native-app-lifecycle', { detail: { active: \(activeLiteral) } })); true;"
            : "window.dispatchEvent(new CustomEvent('poplur-native-app-lifecycle', { detail: { active: \(activeLiteral) } })); true;"
        webView.evaluateJavaScript(lifecycleScript)

        let refresh = { [weak webView] in
            guard let webView, Self.liveWebView === webView else { return }
            (webView as? PoplurManagedWebView)?.refreshApplicationLifecycle()
        }
        if active {
            // `scenePhase` can become active a run-loop turn before UIKit's
            // applicationState updates. Let the host state settle first.
            DispatchQueue.main.async(execute: refresh)
            liveCoordinator?.recoverIfNeeded()
        } else {
            refresh()
        }
    }

    /// The web layer's spoken voice. WKWebView's own speechSynthesis is
    /// unreliable on device (lines are silently dropped without a fresh user
    /// gesture), which is why the map's AI host was mute on iOS while working
    /// in every desktop browser. The web asks; native speaks.
    final class PoplurWebSpeech {
        static let shared = PoplurWebSpeech()
        private let synth = AVSpeechSynthesizer()
        func speak(_ text: String, rate: Double?, pitch: Double?) {
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            synth.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-CA")
                ?? AVSpeechSynthesisVoice(language: "en-US")
            // The web sends SpeechSynthesis-style values (~1.0 = normal); AV's
            // scale is 0..1 with ~0.5 as natural speech. Map around that.
            utterance.rate = Float(0.52 * (rate ?? 1.0))
            utterance.pitchMultiplier = Float(pitch ?? 1.0)
            utterance.volume = 0.92
            PoplurEQSync.shared.configureAudioSession(for: .voicePrompt)
            synth.speak(utterance)
        }
        func cancel() { synth.stopSpeaking(at: .immediate) }
    }

    let initialView: String
    let onReady: () -> Void
    /// Tap on bridge events the host cares about (tabChanged / cameraShutter /
    /// cameraControl → the native web-home camera layer). Every message still
    /// flows to the shared clay bridge afterwards.
    let onWebEvent: ((String, [String: Any]) -> Void)?
    init(
        initialView: String = "home",
        onReady: @escaping () -> Void = {},
        onWebEvent: ((String, [String: Any]) -> Void)? = nil
    ) {
        self.initialView = initialView
        self.onReady = onReady
        self.onWebEvent = onWebEvent
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            initialWebTab: initialView == "camera" ? "post" : initialView,
            homeURL: PoplurWebHome.url(for: initialView),
            onReady: onReady,
            onWebEvent: onWebEvent
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "poplur")
        config.userContentController.add(context.coordinator, name: "homeReady")
        // Capture renderer exceptions in the existing bounded device log.
        // Install before the bundle executes so a React root failure is visible.
        config.userContentController.addUserScript(WKUserScript(
            source: """
            (() => {
              let count = 0;
              const report = (kind, error, fallback) => {
                if (++count > 20) return;
                const text = String(error && ((error.message || '') + ' ' + (error.stack || '')) || fallback || 'unknown').slice(0, 3000);
                window.webkit.messageHandlers.poplur.postMessage({type: 'profile', line: '[WebError] ' + kind + ' ' + text});
              };
              window.addEventListener('error', event => {
                if (event.message) report('error', event.error, event.message + ' ' + event.filename + ':' + event.lineno);
              });
              window.addEventListener('unhandledrejection', event => report('rejection', event.reason));
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let backgroundAudio = Self.backgroundAudioPreference()
        config.userContentController.addUserScript(
            WKUserScript(
                source: Self.backgroundAudioBootstrapScript(
                    enabled: backgroundAudio.enabled,
                    scope: backgroundAudio.scope
                ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        config.userContentController.addUserScript(
            WKUserScript(
                source: Self.readinessScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        if let webRoot = PoplurClayMapView.bundledRootURL() {
            config.setURLSchemeHandler(
                PoplurClayMapView.ClayMapSchemeHandler(rootDirectory: webRoot),
                forURLScheme: PoplurClayWebMap.scheme
            )
        }

        let webView = PoplurManagedWebView(
            performanceName: "PostLoginHomeWeb",
            priority: 140,
            configuration: config
        )
        // OPAQUE by default. A transparent WKWebView made WebKit fail to
        // composite media layers: the map iframe ran (audio playing) without
        // ever being visible, and feed clips never started. Transparency is now
        // switched on ONLY while the camera tab is front (see setCameraHole),
        // which is the only surface that needs the punch-through.
        webView.isOpaque = true
        webView.backgroundColor = UIColor(red: 5/255, green: 4/255, blue: 7/255, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.overrideUserInterfaceStyle = .dark
        context.coordinator.bridge.webView = webView
        webView.onForegroundVisibilityChange = { active in
            context.coordinator.setWebForegroundActive(active)
        }
        // This host unmounts inactive tabs in React. Keep the one visible tab
        // fully alive even when the heavy-renderer arbiter temporarily denies
        // its lease; native background/cover/teardown remain hard boundaries.
        webView.setKeepsVisibleDocumentAlive(true)
        // Without a uiDelegate, WebKit shows its OWN permission sheets for
        // geolocation and getUserMedia — separate from, and on top of, the OS
        // permissions the app already holds. The shared clay bridge answers them
        // by forwarding the decision the user already made.
        webView.uiDelegate = context.coordinator.bridge
        // Readiness must not depend exclusively on a JavaScript timer. When
        // the device enters the thermal tripwire during launch, the managed
        // scheduler intentionally parks page timers; waiting on one of those
        // timers left the approved splash on screen forever. A completed main
        // navigation starts a short native backstop that cannot be suspended
        // by the web performance policy.
        webView.navigationDelegate = context.coordinator
        Self.liveWebView = webView
        Self.liveCoordinator = context.coordinator
        context.coordinator.setNativeMapRendererActive(Self.nativeMapRendererActive)

        if PoplurClayMapView.bundledRootURL() != nil, let url = PoplurWebHome.url(for: initialView) {
            // A cache migration is rare (only when the embedded build stamp
            // changes), but navigation must wait for it. Starting both at once
            // lets WebKit delete bytes underneath the first document load.
            PoplurWebCache.prepareForCurrentBuild { [weak webView] in
                guard let webView, Self.liveWebView === webView else { return }
                webView.load(URLRequest(url: url))
            }
        } else {
            print("[PostLoginHomeWebView] ClayMapWeb bundle missing — run poplur-clay-map/scripts/sync-mobile.sh")
        }
        return webView
    }

    private static func backgroundAudioPreference() -> (enabled: Bool, scope: String) {
        let enabled = SettingsStore.shared.backgroundAudioEnabled
        guard enabled else { return (false, "screen") }
        let storedScope = UserDefaults.standard.string(forKey: "poplur.radio.scope")
        let scope = storedScope == "outside" ? "outside" : "app"
        return (true, scope)
    }

    private static func backgroundAudioBootstrapScript(enabled: Bool, scope: String) -> String {
        let enabledValue = enabled ? "true" : "false"
        return """
        (() => {
          const state = { enabled: \(enabledValue), scope: \"\(scope)\" };
          window.__poplurNativeBackgroundAudio = state;
          try {
            localStorage.setItem('poplur.radio.scope', state.scope);
            localStorage.setItem('poplur.radio.background', state.enabled ? '1' : '0');
            if (state.enabled) localStorage.setItem('poplur.radio.scope.explicit.v1', '1');
            else localStorage.removeItem('poplur.radio.scope.explicit.v1');
          } catch (_) {}
        })();
        """
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onReady = onReady
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        setNativeMapRendererActive(false)
        PoplurNotificationCenter.shared.stopServerInboxListener(owner: coordinator.notificationInboxOwner)
        (uiView as? PoplurManagedWebView)?.clearNativeMapPresentation()
        (uiView as? PoplurManagedWebView)?.poplurTearDown()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "poplur")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "homeReady")
        // The feed-posts listener must not outlive the web view it posts into.
        coordinator.feedPostsRegistration?.remove()
        coordinator.feedPostsRegistration = nil
        if liveWebView === uiView { liveWebView = nil }
        if liveCoordinator === coordinator { liveCoordinator = nil }
        PoplurWebCaptureStore.purge()
    }

    private static let readinessScript = #"""
        (() => {
          let sent = false;
          let readyBackstop = 0;
          const signalReady = () => {
            if (sent) return;
            sent = true;
            if (readyBackstop) clearTimeout(readyBackstop);
            window.webkit.messageHandlers.homeReady.postMessage({ type: "ready" });
          };
          // rAF is deliberately unable to wake an idle managed document. Keep
          // the visual two-frame signal below, but guarantee this document-end
          // script releases the launch cover even if load/fonts finish after
          // the startup rendering lease has expired.
          readyBackstop = setTimeout(signalReady, 750);
          const afterLoad = () => {
            const fontsReady = document.fonts?.ready ?? Promise.resolve();
            Promise.resolve(fontsReady).then(() => {
              requestAnimationFrame(() => requestAnimationFrame(() => {
                setTimeout(signalReady, 250);
              }));
            });
          };
          if (document.readyState === "complete") afterLoad();
          else window.addEventListener("load", afterLoad, { once: true });
        })();
        """#

    /// Punch-through for a native renderer under the approved web HUD. Camera
    /// and the adaptive native map are mutually exclusive owners of this hole.
    static func setCameraHole(_ on: Bool, on webView: WKWebView) {
        // The native renderer is the sole heavy surface on this tab. The web
        // layer remains alive only as its transparent controls/readout.
        (webView as? PoplurManagedWebView)?.setLightweightOverlayMode(on)
        webView.isOpaque = !on
        let opaqueBg = UIColor(red: 5/255, green: 4/255, blue: 7/255, alpha: 1)
        webView.backgroundColor = on ? .clear : opaqueBg
        webView.scrollView.backgroundColor = webView.backgroundColor
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, CLLocationManagerDelegate {
        let bridge = PoplurClayMapView.Coordinator()
        var onReady: () -> Void
        let onWebEvent: ((String, [String: Any]) -> Void)?
        private var didSignalReady = false
        private let locationRequester = CLLocationManager()
        private var locationPermissionRequestInFlight = false
        private var photoPermissionRequestInFlight = false
        private var notificationObservers: [NSObjectProtocol] = []
        private var currentWebTab: String
        private var webReportsLiveCamera = false
        private var nativeMapPresentationActive = false
        private let homeURL: URL?
        private var recoveryWorkItem: DispatchWorkItem?
        /// The live feed-posts forward. See deliverFeedPosts. fileprivate, like
        /// notificationInboxOwner: the outer struct's dismantleUIView removes it.
        fileprivate var feedPostsRegistration: ListenerRegistration?
        /// The account's own posts, fetched once per arm on their own task and merged into every
        /// forward without delaying it. See deliverFeedPosts.
        fileprivate var ownFeedDocuments: [QueryDocumentSnapshot] = []
        fileprivate var ownFeedDocumentsUid: String?
        /// Snapshot sequence, so a slow older forward never lands after a newer one.
        private var feedPostsSequence = 0
        private var recoveryAttempt = 0
        private var recoveryPending = false
        private var webForegroundActive = false
        private var webMotionLeaseActive = false
        private var nativeMapRendererActive = false
        private var navigatorReportsMotionActive = false
        private var navigatorReportsAiming = false
        private static let navigatorMotionDemandLeaseTTL: TimeInterval = 6
        private var navigatorMotionDemandExpiryWorkItem: DispatchWorkItem?
        private var navigatorMotionDemandLeaseGeneration: UInt = 0
        private var lastMotionDeliveryUptime: TimeInterval = 0
        private var lastDeliveredRoll: Double?
        private var lastDeliveredPitch: Double?
        private var lastDeliveredHeading: Double?
        private var activeStoreCheckoutRequestID: String?
        private var activeStoreCheckoutProductCounts: [String: Int] = [:]
        private var pendingDMThreadID: String?
        fileprivate let notificationInboxOwner = UUID()

        init(
            initialWebTab: String,
            homeURL: URL?,
            onReady: @escaping () -> Void,
            onWebEvent: ((String, [String: Any]) -> Void)? = nil
        ) {
            currentWebTab = initialWebTab
            self.homeURL = homeURL
            self.onReady = onReady
            self.onWebEvent = onWebEvent
            pendingDMThreadID = UserDefaults.standard.string(forKey: "poplur.pendingDMThreadId")
            super.init()
            locationRequester.delegate = self
            locationRequester.desiredAccuracy = kCLLocationAccuracyHundredMeters
            notificationObservers.append(NotificationCenter.default.addObserver(
                forName: Notification.Name("PostUploadSuccess"), object: nil, queue: .main
            ) { [weak self] note in
                self?.deliverUploadResult(success: true, note: note)
            })
            notificationObservers.append(NotificationCenter.default.addObserver(
                forName: Notification.Name("PostUploadFailed"), object: nil, queue: .main
            ) { [weak self] note in
                self?.deliverUploadResult(success: false, note: note)
            })
            notificationObservers.append(NotificationCenter.default.addObserver(
                forName: Notification.Name("PostUploadProgress"), object: nil, queue: .main
            ) { [weak self] note in
                self?.deliverUploadProgress(note)
            })
            notificationObservers.append(NotificationCenter.default.addObserver(
                forName: Notification.Name("CaptureComplete"), object: nil, queue: .main
            ) { [weak self] note in
                self?.deliverNativeCapture(note)
            })
            notificationObservers.append(NotificationCenter.default.addObserver(
                forName: Notification.Name("CubeMotionUpdate"), object: nil, queue: .main
            ) { [weak self] note in
                guard let self,
                      let webView = self.bridge.webView,
                      (webView as? PoplurManagedWebView)?.poplurIsForegroundVisible == true,
                      let roll = note.userInfo?["roll"] as? Double,
                      let pitch = note.userInfo?["pitch"] as? Double else { return }
                let heading = note.userInfo?["heading"] as? Double
                self.deliverMotion(roll: roll, pitch: pitch, heading: heading, on: webView)
            })
            notificationObservers.append(NotificationCenter.default.addObserver(
                forName: AdManager.feedAdVisibilityNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let webView = self?.bridge.webView else { return }
                let open = (note.userInfo?["open"] as? Bool) == true
                webView.evaluateJavaScript(
                    "window.dispatchEvent(new CustomEvent('poplur-native-feed-ad',{detail:{open:\(open)}}));true;",
                    completionHandler: nil
                )
            })
            notificationObservers.append(NotificationCenter.default.addObserver(
                forName: .poplurCardPurchaseRecovered, object: nil, queue: .main
            ) { [weak self] note in
                self?.deliverRecoveredStorePurchase(note)
            })
            notificationObservers.append(NotificationCenter.default.addObserver(
                forName: .OpenDMsRequested, object: nil, queue: .main
            ) { [weak self] note in
                guard let self,
                      let threadID = note.userInfo?["threadId"] as? String,
                      !threadID.isEmpty,
                      threadID.count <= 200 else { return }
                self.pendingDMThreadID = threadID
                self.deliverPendingDMDeepLink()
            })
        }

        func setWebForegroundActive(_ active: Bool) {
            webForegroundActive = active
            if active {
                // A new/foreground document has no guarantee it heard the last
                // event emitted before WebKit committed or resumed. Reset the
                // bridge dedupe and replay Core Motion's latest real sample.
                lastMotionDeliveryUptime = 0
                lastDeliveredRoll = nil
                lastDeliveredPitch = nil
                lastDeliveredHeading = nil
            } else {
                // Never carry a stale web demand across a native lifecycle
                // suspension. The governed renderer republishes its current
                // demand after the matching foreground edge.
                navigatorReportsMotionActive = false
                navigatorReportsAiming = false
                cancelNavigatorMotionDemandExpiry()
            }
            syncMotionLease()
            if active { replayLatestMotion() }
        }

        private func cancelNavigatorMotionDemandExpiry() {
            navigatorMotionDemandLeaseGeneration &+= 1
            navigatorMotionDemandExpiryWorkItem?.cancel()
            navigatorMotionDemandExpiryWorkItem = nil
        }

        private func renewNavigatorMotionDemandExpiry() {
            cancelNavigatorMotionDemandExpiry()
            guard navigatorReportsMotionActive else { return }
            let generation = navigatorMotionDemandLeaseGeneration
            let workItem = DispatchWorkItem { [weak self] in
                guard let self,
                      self.navigatorMotionDemandLeaseGeneration == generation else { return }
                self.navigatorMotionDemandExpiryWorkItem = nil
                self.navigatorMotionDemandLeaseGeneration &+= 1
                guard self.navigatorReportsMotionActive else { return }
                self.navigatorReportsMotionActive = false
                self.navigatorReportsAiming = false
                self.syncMotionLease()
            }
            navigatorMotionDemandExpiryWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.navigatorMotionDemandLeaseTTL,
                execute: workItem
            )
        }

        func setNativeMapRendererActive(_ active: Bool) {
            guard nativeMapRendererActive != active else { return }
            nativeMapRendererActive = active
            // Reopening the fallback must deliver one retained pose even if it
            // matches the sample last seen before native took over.
            if !active {
                lastMotionDeliveryUptime = 0
                lastDeliveredRoll = nil
                lastDeliveredPitch = nil
                lastDeliveredHeading = nil
            }
            syncMotionLease()
            if !active { replayLatestMotion() }
        }

        private func syncMotionLease() {
            // Motion belongs to the navigator's governed render demand, not to
            // the foreground WebView. CubeTab3D is mounted on every web tab;
            // tying this lease only to foreground visibility kept CMMotionManager
            // and a 20 Hz JavaScript bridge running across Feed, Camera, Profile,
            // and every subscreen after the WebGL renderer had already parked.
            // The web now raises `navigatorReportsMotionActive` for finite
            // interaction/model-animation windows and lowers it at the same
            // idle edge that releases renderer demand.
            let eligible = webForegroundActive
                && navigatorReportsMotionActive
                && !(nativeMapRendererActive && currentWebTab == "map")
            webMotionLeaseActive = eligible
            guard eligible else {
                CubeMotionPoster.shared.stop(owner: "web-home")
                return
            }
            let samplingRate: CubeMotionPoster.SamplingRate =
                currentWebTab == "post" && navigatorReportsAiming
                    ? .cameraAim
                    : .navigator
            CubeMotionPoster.shared.start(owner: "web-home", samplingRate: samplingRate)
        }

        private func replayLatestMotion() {
            guard webMotionLeaseActive,
                  let webView = bridge.webView,
                  (webView as? PoplurManagedWebView)?.poplurIsForegroundVisible == true,
                  let sample = CubeMotionPoster.shared.latestSample else { return }
            deliverMotion(roll: sample.roll, pitch: sample.pitch, heading: sample.heading, on: webView)
        }

        /// Shortest angular distance in degrees, so a pan across north
        /// (359.9° -> 0.1°) reads as 0.2 and not 359.8. 0.5° matches the 0.008
        /// rad used for roll/pitch closely enough that a resting phone stays
        /// just as quiet on the bridge as it was before heading existed.
        private func headingUnchanged(_ heading: Double?) -> Bool {
            guard let heading else { return true }
            guard let last = lastDeliveredHeading else { return false }
            var delta = (heading - last).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            return abs(delta) < 0.5
        }

        /// This tiny dispatch deliberately has no completion-based lock. WebKit
        /// can omit an evaluateJavaScript completion while its governed timers
        /// are idle; the old lock then permanently stopped live cube motion.
        /// Core Motion is leased at a bounded 20/30 Hz according to visible
        /// demand and delivery is limited to the genuinely foreground document,
        /// so callback-free dispatch stays bounded without coupling motion to
        /// page inactivity policy.
        private func deliverMotion(roll: Double, pitch: Double, heading: Double?, on webView: WKWebView) {
            guard webMotionLeaseActive,
                  (webView as? PoplurManagedWebView)?.poplurIsForegroundVisible == true else { return }
            let now = ProcessInfo.processInfo.systemUptime
            // Keep the bridge aligned with the hardware lease: ordinary clay
            // parallax is 20 Hz, while the camcorder retains direct 30 Hz aim.
            let deliveryRate = currentWebTab == "post" && navigatorReportsAiming
                ? CubeMotionPoster.SamplingRate.cameraAim.rawValue
                : CubeMotionPoster.SamplingRate.navigator.rawValue
            guard now - lastMotionDeliveryUptime >= (1.0 / deliveryRate) else { return }
            // Heading has to be part of this test, not just part of the payload.
            // Panning a level phone around the room is almost pure heading: roll
            // and pitch barely move, so on a roll/pitch-only gate every sample of
            // the exact gesture the compass facing exists to serve was dropped
            // before it reached the bridge.
            if let lastRoll = lastDeliveredRoll,
               let lastPitch = lastDeliveredPitch,
               abs(roll - lastRoll) < 0.008,
               abs(pitch - lastPitch) < 0.008,
               headingUnchanged(heading) {
                return
            }
            lastMotionDeliveryUptime = now
            lastDeliveredRoll = roll
            lastDeliveredPitch = pitch
            lastDeliveredHeading = heading
            // Omitted entirely when the device has no heading, so the web keeps
            // its existing parallax-only behaviour rather than seeing a bogus one.
            let headingField = heading.map { ",heading:\($0)" } ?? ""
            webView.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent('poplur-native-motion',{detail:{roll:\(roll),pitch:\(pitch)\(headingField)}}));true;",
                completionHandler: nil
            )
        }

        deinit {
            feedPostsRegistration?.remove()
            recoveryWorkItem?.cancel()
            navigatorMotionDemandExpiryWorkItem?.cancel()
            notificationObservers.forEach(NotificationCenter.default.removeObserver)
            CubeMotionPoster.shared.stop(owner: "web-home")
            let owner = notificationInboxOwner
            Task { @MainActor in
                PoplurNotificationCenter.shared.stopServerInboxListener(owner: owner)
            }
        }

        private func deliverUploadResult(success: Bool, note: Notification) {
            guard let requestID = note.userInfo?["requestId"] as? String,
                  let webView = bridge.webView else {
                print("[PostLoginHomeWebView] upload result DROPPED (requestId or webView missing) success=\(success)")
                return
            }
            print("[PostLoginHomeWebView] upload result → web: success=\(success) requestId=\(requestID)")
            var result: [String: Any] = ["requestId": requestID, "ok": success]
            if let message = note.userInfo?["message"] as? String { result["error"] = message }
            guard let data = try? JSONSerialization.data(withJSONObject: result),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent('poplur-upload-result', { detail: \(json) })); true;"
            )
        }

        private func deliverUploadProgress(_ note: Notification) {
            guard let requestID = note.userInfo?["requestId"] as? String,
                  let fraction = note.userInfo?["fraction"] as? Double,
                  let webView = bridge.webView else { return }
            let phase = (note.userInfo?["phase"] as? String) ?? "UPLOADING"
            let payload: [String: Any] = [
                "requestId": requestID,
                "fraction": min(1, max(0, fraction)),
                "phase": phase
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent('poplur-upload-progress', { detail: \(json) })); true;"
            )
        }

        private func deliverNativeCapture(_ note: Notification) {
            guard let webView = bridge.webView else { return }

            let key: String
            let kind: String
            if let image = note.userInfo?["image"] as? UIImage,
               let imageKey = PoplurWebCaptureStore.register(image: image) {
                key = imageKey
                kind = "photo"
            } else if let videoURL = note.userInfo?["videoURL"] as? URL {
                key = PoplurWebCaptureStore.register(videoURL: videoURL)
                kind = "video"
            } else {
                return
            }

            let source = "\(PoplurClayWebMap.scheme)://\(PoplurClayWebMap.host)/captures/\(key)"
            let payload: [String: Any] = ["kind": kind, "src": source]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent('poplur-native-capture', { detail: \(json) })); true;"
            )
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "homeReady" {
                signalHomeReady()
                pushAuthToken()
                return
            }
            // Every message this coordinator handles is ALSO re-delivered to
            // `bridge` by the forward at the end of this method, because that
            // forward is unconditional. The map coordinator acts on exactly
            // four types, so anything else is already a no-op there — but for
            // a type BOTH sides handle, the forward runs the work twice. That
            // is how publishPost came to publish two posts per tap for 24
            // days. Forward only what the map coordinator uniquely owns.
            var forwardToBridge = true
            if let body = message.body as? [String: Any],
               let type = body["type"] as? String {
                forwardToBridge = Self.bridgeOwnedTypes.contains(type)
                // The shared Home reports its own first painted frame through
                // the normal Poplur bridge. Prefer that concrete signal over
                // the document-load fallback installed above: a warm Home can
                // reveal immediately, while a genuinely cold bundle remains
                // covered by the approved splash until React has painted.
                if type == "homeReady" {
                    signalHomeReady()
                    pushAuthToken()
                }
                if type == "phoneRingtone" {
                    let action = body["action"] as? String
                    if action == "start" {
                        PoplurWebRingtone.shared.start()
                    } else if action == "stop" {
                        PoplurWebRingtone.shared.stop()
                    }
                }
                // The web layer cannot mint a Firebase ID token — this process
                // owns auth — but Meshy generation is authorized server-side by
                // role, so it needs one. It asks; we answer.
                if type == "requestAuthToken" {
                    pushAuthToken()
                }
                // The notifications screen lives in the web bundle; the push
                // used to be an unrelated daily Firestore summary on a single
                // reused identifier, which is why the same one arrived over and
                // over while the screen said something else. The web now
                // forwards each row it logs, and it is scheduled with that
                // row's own id so the two finally agree.
                if type == "notification",
                   let id = body["id"] as? String,
                   let title = body["title"] as? String {
                    let detail = body["detail"] as? String ?? ""
                    let kind = body["kind"] as? String
                    Task { @MainActor in
                        await PoplurNotificationCenter.shared.scheduleFromWeb(
                            id: id, title: title, detail: detail, kind: kind
                        )
                    }
                }
                if type == "notificationsRequested" {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        PoplurNotificationCenter.shared.reconnectServerInboxListener(
                            owner: self.notificationInboxOwner
                        ) { [weak self] rows in
                            self?.pushNotificationInbox(rows)
                        }
                    }
                }
                if type == "notificationsStopped" {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        PoplurNotificationCenter.shared.stopServerInboxListener(
                            owner: self.notificationInboxOwner
                        )
                    }
                }
                if type == "notificationsRead" {
                    Task { @MainActor [weak self] in
                        let ids = body["ids"] as? [String] ?? []
                        if ids.isEmpty {
                            PoplurNotificationCenter.shared.markAllRead()
                        } else {
                            await PoplurNotificationCenter.shared.markNotificationsRead(ids: ids)
                        }
                        self?.pushNotificationInbox(PoplurNotificationCenter.shared.notifications)
                    }
                }
                if type == "notificationDismissed", let id = body["id"] as? String {
                    Task { @MainActor [weak self] in
                        await PoplurNotificationCenter.shared.dismissNotifications(ids: [id])
                        self?.pushNotificationInbox(PoplurNotificationCenter.shared.notifications)
                    }
                }
                if type == "notificationsCleared", let ids = body["ids"] as? [String] {
                    Task { @MainActor [weak self] in
                        await PoplurNotificationCenter.shared.dismissNotifications(ids: ids)
                        self?.pushNotificationInbox(PoplurNotificationCenter.shared.notifications)
                    }
                }
                if type == "requestAccountPrivacy", let webView = bridge.webView {
                    Task { [weak self] in
                        guard let self else { return }
                        guard let uid = Auth.auth().currentUser?.uid else {
                            await MainActor.run {
                                self.pushAccountPrivacy(
                                    privateAccount: false,
                                    ghostMode: false,
                                    ok: false,
                                    message: "Sign in to load privacy.",
                                    into: webView
                                )
                            }
                            return
                        }
                        let snapshot = try? await Firestore.firestore()
                            .collection("users").document(uid).getDocument()
                        let data = snapshot?.data()
                        let privateAccount = data?["privateAccount"] as? Bool == true
                        let ghostMode = data?["ghostMode"] as? Bool == true
                        do {
                            let result = try await Functions.functions(region: "us-central1")
                                .httpsCallable("setAccountLocationPrivacy")
                                .call([
                                    "privateAccount": privateAccount,
                                    "ghostMode": ghostMode
                                ])
                            let settled = result.data as? [String: Any]
                            await MainActor.run {
                                self.pushAccountPrivacy(
                                    privateAccount: settled?["privateAccount"] as? Bool ?? privateAccount,
                                    ghostMode: settled?["ghostMode"] as? Bool ?? ghostMode,
                                    into: webView
                                )
                            }
                        } catch {
                            await MainActor.run {
                                self.pushAccountPrivacy(
                                    privateAccount: privateAccount,
                                    ghostMode: ghostMode,
                                    ok: false,
                                    message: error.localizedDescription,
                                    into: webView
                                )
                            }
                        }
                    }
                }
                if type == "accountPrivacyChanged", let webView = bridge.webView {
                    guard let privateAccount = body["privateAccount"] as? Bool,
                          let ghostMode = body["ghostMode"] as? Bool else {
                        pushAccountPrivacy(
                            privateAccount: false,
                            ghostMode: false,
                            ok: false,
                            message: "Privacy settings were invalid.",
                            into: webView
                        )
                        return
                    }
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            let result = try await Functions.functions(region: "us-central1")
                                .httpsCallable("setAccountLocationPrivacy")
                                .call([
                                    "privateAccount": privateAccount,
                                    "ghostMode": ghostMode
                                ])
                            let settled = result.data as? [String: Any]
                            await MainActor.run {
                                self.pushAccountPrivacy(
                                    privateAccount: settled?["privateAccount"] as? Bool ?? privateAccount,
                                    ghostMode: settled?["ghostMode"] as? Bool ?? ghostMode,
                                    into: webView
                                )
                            }
                        } catch {
                            await MainActor.run {
                                self.pushAccountPrivacy(
                                    privateAccount: privateAccount,
                                    ghostMode: ghostMode,
                                    ok: false,
                                    message: error.localizedDescription,
                                    into: webView
                                )
                            }
                        }
                    }
                }
                // The web layer's own heat probe. A WKWebView's console.log never
                // reaches this process's stdout, so the probe hands its line to
                // native and native prints it — that is what makes it readable
                // with `devicectl device process launch --console`.
                if type == "profile", let line = body["line"] as? String {
                    print(line)
                    PoplurDiagLog.append(line)
                }
                // SIGN OUT. Phase 3 put this web surface in front of native
                // Home, which left AppSettingsView — and with it the only
                // sign-out in the product — under a ProfileView that no longer
                // mounts. A signed-in build therefore had no route back to
                // pre-login short of deleting the app. Web Settings now asks,
                // and the session is ended here because the shell owns it:
                // AuthViewModel's state listener flips isAuthenticated and
                // Poplur2025App swaps back to the pre-login surface on its own.
                if type == "signOut" {
                    PoplurWebCaptureStore.purge()
                    NotificationCenter.default.post(name: .StopMapAudio, object: nil)
                    NotificationCenter.default.post(name: .PoplurSignOutRequested, object: nil)
                    return
                }
                if type == "publishPost" {
                    // The camera composer lives in THIS WebView, but the only
                    // publishPost handler was on the old native map host — so a
                    // post finished here never started an upload, and the
                    // composer sat on "Uploading…" until its 90s timeout. The
                    // upload path posts PostUploadSuccess/Failed, which this
                    // class already forwards back as poplur-upload-result.
                    WebPostPublisher.handle(body)
                }
                // Settings → CAMERA. Mirrored into UserDefaults because the
                // native announcer and the capture session read them from
                // outside the WebView, where localStorage does not exist.
                if type == "cameraAiVoice", let on = body["enabled"] as? Bool {
                    UserDefaults.standard.set(on ? "1" : "0", forKey: "poplur.cameraAiVoice")
                    return
                }
                if type == "cameraDetectDefault", let on = body["enabled"] as? Bool {
                    UserDefaults.standard.set(on ? "1" : "0", forKey: "poplur.cameraDetectDefault")
                    return
                }
                // In-app video calls. The WEB owns the peer connection — the
                // chat it belongs to is a page in this WebView — and native
                // owns Firestore, so this carries offers, answers and ICE
                // between the two sides. No media passes here; that is peer
                // to peer.
                if type == "callStart", let webView = bridge.webView {
                    let otherUID = (body["otherId"] as? String) ?? ""
                    let callerName = (body["callerName"] as? String)
                    let video = (body["video"] as? Bool) ?? false
                    let context = (body["context"] as? String) == "house" ? "house" : nil
                    let requestID = (body["requestId"] as? String) ?? ""
                    Task { @MainActor [weak self, weak webView] in
                        let callID = await PoplurCallSignalling.shared.startCall(
                            to: otherUID,
                            callerName: callerName,
                            video: video,
                            context: context
                        )
                        guard let self, let webView, self.bridge.webView === webView else { return }
                        self.pushWalletPassMessage(
                            ["type": "poplurCallStarted", "callId": callID ?? "",
                             "ok": callID != nil, "requestId": requestID],
                            into: webView
                        )
                    }
                    return
                }
                if type == "callAnswerJoin" {
                    // The callee accepted: start relaying before their answer
                    // is produced, so the caller's candidates are not missed.
                    PoplurCallSignalling.shared.observe((body["callId"] as? String) ?? "")
                    return
                }
                if type == "callDescription" {
                    Task { @MainActor in
                        await PoplurCallSignalling.shared.publishDescription(
                            (body["callId"] as? String) ?? "",
                            type: (body["sdpType"] as? String) ?? "offer",
                            sdp: (body["sdp"] as? String) ?? ""
                        )
                    }
                    return
                }
                if type == "callCandidate" {
                    Task { @MainActor in
                        await PoplurCallSignalling.shared.publishCandidate(
                            (body["callId"] as? String) ?? "",
                            candidate: (body["candidate"] as? [String: Any]) ?? [:]
                        )
                    }
                    return
                }
                if type == "callEnd" {
                    Task { @MainActor in
                        await PoplurCallSignalling.shared.endCall((body["callId"] as? String) ?? "")
                    }
                    return
                }
                if type == "callDecline" {
                    Task { @MainActor in
                        await PoplurCallSignalling.shared.declineCall((body["callId"] as? String) ?? "")
                    }
                    return
                }
                if type == "callAccept" {
                    Task { @MainActor in
                        await PoplurCallSignalling.shared.acceptCall((body["callId"] as? String) ?? "")
                    }
                    return
                }
                if type == "callWatchIncoming", let webView = bridge.webView {
                    PoplurCallSignalling.shared.onEvent = { [weak self, weak webView] event in
                        guard let self, let webView, self.bridge.webView === webView else { return }
                        self.pushWalletPassMessage(event, into: webView)
                    }
                    PoplurCallSignalling.shared.observeIncoming()
                    return
                }
                // The Poplur phone's address book: favourites, people you have
                // a chat with, and people your radius has actually crossed.
                if type == "requestPhoneContacts", let webView = bridge.webView {
                    // The radius and the position ride on the request: the
                    // ledger is the web's, and a second copy here would drift.
                    let radiusKm = (body["radiusKm"] as? NSNumber)?.doubleValue
                    let lat = (body["latitude"] as? NSNumber)?.doubleValue
                    let lng = (body["longitude"] as? NSNumber)?.doubleValue
                    let requestID = body["requestId"] as? String
                    Task { @MainActor [weak self, weak webView] in
                        let contacts = await PoplurPhoneContacts.shared.contacts(
                            radiusKm: radiusKm, latitude: lat, longitude: lng
                        )
                        guard let self, let webView, self.bridge.webView === webView else { return }
                        var response: [String: Any] = [
                            "type": "poplurPhoneContacts",
                            "contacts": contacts,
                        ]
                        if let requestID { response["requestId"] = requestID }
                        self.pushWalletPassMessage(
                            response,
                            into: webView
                        )
                    }
                    return
                }
                if type == "togglePhoneFavourite", let webView = bridge.webView {
                    let otherUID = (body["contactId"] as? String) ?? ""
                    let on = (body["favourite"] as? Bool) ?? false
                    let name = body["name"] as? String
                    Task { @MainActor [weak self, weak webView] in
                        await PoplurPhoneContacts.shared.setFavourite(otherUID, on, name: name)
                        // Re-read rather than patching the page's copy: the sort
                        // order changes when a favourite moves to the top, and
                        // one source of truth is cheaper than two that drift.
                        let contacts = await PoplurPhoneContacts.shared.contacts()
                        guard let self, let webView, self.bridge.webView === webView else { return }
                        self.pushWalletPassMessage(
                            ["type": "poplurPhoneContacts", "contacts": contacts],
                            into: webView
                        )
                    }
                    return
                }
                // Direct messages. The chat screen is a page inside this
                // WebView and the bundle has no Firebase, so every read and
                // write crosses here. Threads and messages arrive as LIVE
                // snapshots rather than one-shot fetches: a chat that only
                // updates when you reopen it is not a chat.
                if type == "requestDMThreads", let webView = bridge.webView {
                    PoplurDirectMessages.shared.observeThreads { [weak self, weak webView] threads in
                        guard let self, let webView, self.bridge.webView === webView else { return }
                        self.pushWalletPassMessage(
                            ["type": "poplurDMThreads", "threads": threads],
                            into: webView
                        )
                    }
                    return
                }
                if type == "openDMThread", let webView = bridge.webView {
                    let threadID = (body["threadId"] as? String) ?? ""
                    guard !threadID.isEmpty, threadID.count <= 200 else { return }
                    PoplurDirectMessages.shared.observeThread(
                        threadID,
                        onChange: { [weak self, weak webView] messages in
                            guard let self, let webView, self.bridge.webView === webView else { return }
                            self.pushWalletPassMessage(
                                ["type": "poplurDMMessages", "threadId": threadID, "messages": messages],
                                into: webView
                            )
                        },
                        onState: { [weak self, weak webView] state in
                            guard let self, let webView, self.bridge.webView === webView else { return }
                            var payload = state
                            payload["type"] = "poplurDMThreadState"
                            self.pushWalletPassMessage(payload, into: webView)
                        }
                    )
                    return
                }
                if type == "closeDMThread" {
                    PoplurDirectMessages.shared.closeThread()
                    return
                }
                if type == "setDMTyping" {
                    let threadID = (body["threadId"] as? String) ?? ""
                    let typing = (body["typing"] as? Bool) ?? false
                    guard !threadID.isEmpty, threadID.count <= 200 else { return }
                    Task { @MainActor in
                        await PoplurDirectMessages.shared.setTyping(threadID, typing: typing)
                    }
                    return
                }
                if type == "deleteDMThread", let webView = bridge.webView {
                    let threadID = (body["threadId"] as? String) ?? ""
                    Task { @MainActor [weak self, weak webView] in
                        let ok = await PoplurDirectMessages.shared.hideThread(threadID)
                        guard let self, let webView, self.bridge.webView === webView else { return }
                        self.pushWalletPassMessage([
                            "type": "poplurDMThreadHidden",
                            "threadId": threadID,
                            "ok": ok,
                        ], into: webView)
                    }
                    return
                }
                if type == "sendDMAttachment", let webView = bridge.webView {
                    let otherUID = (body["otherId"] as? String) ?? ""
                    let threadID = (body["threadId"] as? String) ?? ""
                    let source = (body["source"] as? String) ?? ""
                    let kind = (body["kind"] as? String) ?? ""
                    let clientMessageID = (body["clientMessageId"] as? String) ?? ""
                    let durationMillis = (body["durationMillis"] as? NSNumber)?.intValue
                    Task { @MainActor [weak self, weak webView] in
                        let ok = await PoplurDirectMessages.shared.sendAttachment(
                            to: otherUID,
                            threadID: threadID,
                            source: source,
                            kind: kind,
                            clientMessageID: clientMessageID,
                            durationMillis: durationMillis
                        )
                        guard let self, let webView, self.bridge.webView === webView else { return }
                        self.pushWalletPassMessage(
                            ok
                                ? ["type": "poplurDMSent", "clientMessageId": clientMessageID]
                                : [
                                    "type": "poplurDMSendFailed",
                                    "clientMessageId": clientMessageID,
                                    "text": kind == "audio" ? "Voice message" : kind == "video" ? "Video" : "Photo",
                                ],
                            into: webView
                        )
                    }
                    return
                }
                if type == "sendDM", let webView = bridge.webView {
                    let otherUID = (body["otherId"] as? String) ?? ""
                    let text = (body["text"] as? String) ?? ""
                    let clientMessageID = (body["clientMessageId"] as? String) ?? ""
                    Task { @MainActor [weak self, weak webView] in
                        let ok = await PoplurDirectMessages.shared.send(
                            to: otherUID,
                            text: text,
                            clientMessageID: clientMessageID
                        )
                        guard let self, let webView, self.bridge.webView === webView else { return }
                        self.pushWalletPassMessage(
                            ok
                                ? ["type": "poplurDMSent", "clientMessageId": clientMessageID]
                                : [
                                    "type": "poplurDMSendFailed",
                                    "clientMessageId": clientMessageID,
                                    "text": text,
                                ],
                            into: webView
                        )
                    }
                    return
                }
                // Block and Report, from the visited profile's Poplur dialog.
                // The page keeps its own block list so the feed and map empty
                // at once; the durable record is users/{me}/blocked/{them},
                // the symmetric boundary firestore.rules enforces on messages
                // and engagement, and it is native's to write because native
                // owns identity in this shell. A report is a write-once note
                // to Poplur (reports/{auto}); nothing on the client reads it.
                if type == "blockUser" || type == "unblockUser" || type == "reportUser" {
                    let otherUID = ((body["userId"] as? String) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let handle = String(((body["username"] as? String) ?? "").prefix(48))
                    guard !otherUID.isEmpty, otherUID.count <= 128,
                          let uid = Auth.auth().currentUser?.uid, uid != otherUID else { return }
                    let firestore = Firestore.firestore()
                    if type == "unblockUser" {
                        // The mirror of the block below: the durable record
                        // goes, so the rules' boundary lifts on the next read.
                        // The web side has already put their pops back locally.
                        firestore.collection("users").document(uid)
                            .collection("blocked").document(otherUID)
                            .delete { error in
                                if let error {
                                    os_log("[PostLoginHomeWebView] unblock delete failed: %{public}@",
                                           log: .default, type: .error, error.localizedDescription)
                                }
                            }
                    } else if type == "blockUser" {
                        firestore.collection("users").document(uid)
                            .collection("blocked").document(otherUID)
                            .setData(["blockedAt": FieldValue.serverTimestamp(), "username": handle]) { error in
                                if let error {
                                    os_log("[PostLoginHomeWebView] block write failed: %{public}@",
                                           log: .default, type: .error, error.localizedDescription)
                                }
                            }
                    } else {
                        let reason = String(((body["reason"] as? String) ?? "profile").prefix(64))
                        firestore.collection("reports").addDocument(data: [
                            "reporterId": uid,
                            "userId": otherUID,
                            "username": handle,
                            "reason": reason,
                            "source": "profile",
                            "platform": "ios",
                            "createdAt": FieldValue.serverTimestamp(),
                        ]) { error in
                            if let error {
                                os_log("[PostLoginHomeWebView] report write failed: %{public}@",
                                       log: .default, type: .error, error.localizedDescription)
                            }
                        }
                    }
                    return
                }
                // Add to Apple Wallet. PassKit can only be presented from
                // native, and this store is a page inside the WebView, so the
                // page asks and native does the work. The FIRST version of this
                // was a SwiftUI button in RadiusStoreView — orphaned along with
                // the rest of HomeView when the home became a web surface, so
                // it never rendered at all. Same lesson as ML detection and the
                // AR filters before it: a capability wired only to the old
                // native path is a capability nobody can reach.
                if type == "poplurWalletPassAvailability", let webView = bridge.webView {
                    Task { @MainActor [weak self, weak webView] in
                        guard let self, let webView, self.bridge.webView === webView else { return }
                        let owned = await PoplurWalletPassService.shared.ownedCardIDs()
                        self.pushWalletPassMessage(
                            ["type": "poplurWalletPassAvailabilityResult", "cardIds": owned],
                            into: webView
                        )
                    }
                    return
                }
                if type == "poplurWalletPassRequested", let webView = bridge.webView {
                    let cardID = (body["cardId"] as? String) ?? ""
                    guard !cardID.isEmpty, cardID.count <= 64 else {
                        pushWalletPassMessage(
                            ["type": "poplurWalletPassResult", "status": "failure",
                             "message": "Unknown card."],
                            into: webView
                        )
                        return
                    }
                    Task { @MainActor [weak self, weak webView] in
                        guard let self, let webView, self.bridge.webView === webView else { return }
                        let outcome = await PoplurWalletPassService.shared.addToWallet(cardID: cardID)
                        var payload: [String: Any] = ["type": "poplurWalletPassResult"]
                        switch outcome {
                        case .added:
                            payload["status"] = "success"
                        case .failed(let message):
                            payload["status"] = "failure"
                            payload["message"] = message
                        }
                        self.pushWalletPassMessage(payload, into: webView)
                    }
                    return
                }
                if PoplurAnalyticsRelay.handles(type) { PoplurAnalyticsRelay.handle(type: type, body: body); return }
                // Store checkout remains a web-owned bag, but payment and
                // fulfillment cross this native boundary. StoreKit authorizes
                // each consumable; the server verifies its signed JWS and
                // grants credits before native finishes the transaction.
                if type == "poplurStoreCheckoutRequested", let webView = bridge.webView {
                    let rawRequestID = (body["requestId"] as? String) ?? ""
                    let requestID = rawRequestID.count <= 160 ? rawRequestID : ""
                    let rawItems = body["items"]
                    guard !requestID.isEmpty,
                          let productCounts = Self.storeCheckoutProductCounts(from: rawItems) else {
                        pushStoreCheckoutResult(
                            PoplurCardCheckoutResult(
                                status: .failure,
                                message: "The bag could not be validated. Please review it and try again.",
                                completedProductCounts: [:],
                                creditsAdded: 0,
                                availableCredits: nil
                            ),
                            requestID: requestID,
                            into: webView
                        )
                        return
                    }
                    guard activeStoreCheckoutRequestID == nil else {
                        pushStoreCheckoutResult(
                            PoplurCardCheckoutResult(
                                status: .failure,
                                message: "Another App Store checkout is already in progress.",
                                completedProductCounts: [:],
                                creditsAdded: 0,
                                availableCredits: nil
                            ),
                            requestID: requestID,
                            into: webView
                        )
                        return
                    }
                    activeStoreCheckoutRequestID = requestID
                    activeStoreCheckoutProductCounts = productCounts
                    Task { @MainActor [weak self, weak webView] in
                        let result = await PoplurCardPurchaseService.shared.checkout(
                            rawItems: rawItems
                        ) { [weak self, weak webView] pendingResult in
                            guard let self, let webView, self.bridge.webView === webView else { return }
                            self.deliverStoreCheckoutResult(
                                pendingResult,
                                requestID: requestID,
                                into: webView
                            )
                        }
                        guard let self, let webView, self.bridge.webView === webView else { return }
                        self.deliverStoreCheckoutResult(result, requestID: requestID, into: webView)
                    }
                    return
                }
                // Profile themes are shared with the native fallback through one
                // stable-ID store. The manifest-owned status-bar value is derived
                // again natively instead of trusting arbitrary web colors.
                if type == "profileThemeChanged", let webView = bridge.webView {
                    let stableID = (body["id"] as? String)
                        ?? (body["themeID"] as? String)
                        ?? (body["themeId"] as? String)
                    guard let stableID else { return }
                    let requestedStatusBar = body["statusBar"] as? String
                    Task { @MainActor [weak self, weak webView] in
                        let selectedTheme = ProfileThemeStore.shared.select(stableID: stableID)
                        if let requestedStatusBar,
                           requestedStatusBar != selectedTheme.webStatusBarValue {
                            print("[PostLoginHomeWebView] ignored mismatched profile theme status bar for \(stableID)")
                        }
                        guard let self, let webView else { return }
                        self.pushProfileTheme(selectedTheme, into: webView)
                    }
                    return
                }
                if type == "requestProfileTheme", let webView = bridge.webView {
                    Task { @MainActor [weak self, weak webView] in
                        guard let self, let webView else { return }
                        self.pushProfileTheme(ProfileThemeStore.shared.selectedTheme, into: webView)
                    }
                    return
                }
                if type == "appIconChanged", let webView = bridge.webView {
                    let stableID = (body["id"] as? String)
                        ?? (body["iconID"] as? String)
                        ?? (body["iconId"] as? String)
                    guard let stableID, let requestedIcon = PoplurAppIcon(rawValue: stableID) else {
                        Task { @MainActor [weak self, weak webView] in
                            guard let self, let webView else { return }
                            self.pushAppIcon(
                                AppIconStore.shared.selectedIcon,
                                accepted: false,
                                message: "Unknown app icon ID.",
                                into: webView
                            )
                        }
                        return
                    }
                    Task { @MainActor [weak self, weak webView] in
                        AppIconStore.shared.apply(requestedIcon) { [weak self, weak webView] accepted, message in
                            guard let self, let webView else { return }
                            self.pushAppIcon(
                                AppIconStore.shared.selectedIcon,
                                accepted: accepted,
                                message: message,
                                into: webView
                            )
                        }
                    }
                    return
                }
                if type == "requestAppIcon", let webView = bridge.webView {
                    Task { @MainActor [weak self, weak webView] in
                        guard let self, let webView else { return }
                        AppIconStore.shared.refreshFromSystem()
                        self.pushAppIcon(
                            AppIconStore.shared.selectedIcon,
                            accepted: true,
                            message: nil,
                            into: webView
                        )
                    }
                    return
                }
                // The clay permission card was answered. Nothing native listened
                // for this before, which is why the primer and the real dialog
                // were unsequenced: the map asked iOS directly on load and the
                // bare alert arrived on its own. Native now takes its cue from
                // here — a yes on the card is what fires the ONE system prompt.
                if type == "permissionHandled", let permission = body["permission"] as? String {
                    let granted = (body["granted"] as? Bool) ?? false
                    NotificationCenter.default.post(
                        name: Notification.Name("PoplurPermissionHandled"),
                        object: nil,
                        userInfo: ["permission": permission, "granted": granted]
                    )
                    return
                }
                // Feed hold menu → SHARE. The share sheet is a system surface,
                // so the web can only ask for it; presenting it is native's job.
                if type == "sharePost" {
                    let title = (body["title"] as? String) ?? "poplur"
                    let user = (body["user"] as? String) ?? ""
                    let line = user.isEmpty ? title : "\(title) — \(user)"
                    var items: [Any] = [line]
                    let rawLink = ((body["link"] as? String) ?? (body["url"] as? String))?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let suppliedURL: URL? = {
                        guard let rawLink, !rawLink.isEmpty,
                              let components = URLComponents(string: rawLink),
                              components.scheme?.lowercased() == "https",
                              !(components.host?.isEmpty ?? true),
                              components.user == nil,
                              components.password == nil
                        else { return nil }
                        // Fragment/query are legitimate share links; clearing
                        // neither keeps signed station/story URLs intact.
                        return components.url
                    }()
                    // postId is the immutable identity. Prefer its canonical
                    // URL over a generic/channel link supplied by the caller.
                    // Link-only surfaces such as Radio still use suppliedURL.
                    if let postId = body["postId"] as? String, !postId.isEmpty,
                       let url = URL(string: "https://poplur.com/p/\(postId)") {
                        items.append(url)
                    } else if let suppliedURL {
                        items.append(suppliedURL)
                    }
                    DispatchQueue.main.async {
                        guard let scene = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first(where: { $0.activationState == .foregroundActive }),
                              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                        else { return }
                        var presenter = root
                        while let next = presenter.presentedViewController { presenter = next }
                        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
                        // iPad has no modal share sheet — without an anchor this
                        // is a crash, not a layout problem.
                        sheet.popoverPresentationController?.sourceView = presenter.view
                        sheet.popoverPresentationController?.sourceRect = CGRect(
                            x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 40,
                            width: 0, height: 0
                        )
                        presenter.present(sheet, animated: true)
                    }
                    return
                }
                if type == "shareReferral" {
                    let code = (body["code"] as? String) ?? ""
                    let link = (body["link"] as? String) ?? "https://poplur.com"
                    let text = "Join me on Poplur — use my code \(code) and we both get credits and the whole map."
                    var items: [Any] = [text]
                    if let url = URL(string: link) { items.append(url) }
                    DispatchQueue.main.async {
                        guard let scene = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first(where: { $0.activationState == .foregroundActive }),
                              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                        else { return }
                        var presenter = root
                        while let next = presenter.presentedViewController { presenter = next }
                        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
                        sheet.popoverPresentationController?.sourceView = presenter.view
                        sheet.popoverPresentationController?.sourceRect = CGRect(
                            x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 40,
                            width: 0, height: 0
                        )
                        presenter.present(sheet, animated: true)
                    }
                    return
                }
                if type == "radioScope", let scope = body["scope"] as? String,
                   ["screen", "app", "outside"].contains(scope) {
                    UserDefaults.standard.set(scope, forKey: "poplur.radio.scope")
                    SettingsStore.shared.backgroundAudioEnabled = scope != "screen"
                    if scope == "outside" {
                        let session = AVAudioSession.sharedInstance()
                        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                        try? session.setActive(true)
                    }
                    return
                }
                if type == "requestBackgroundAudio", let webView = bridge.webView {
                    pushBackgroundAudioPreference(into: webView)
                    return
                }
                if type == "radioPlayback",
                   let state = body["state"] as? String,
                   let scope = body["scope"] as? String {
                    Task { @MainActor in
                        PoplurBackgroundResourceFence.shared.updateWebRadio(
                            state: state,
                            scope: scope
                        )
                    }
                    return
                }
                if type == "speak", let text = body["text"] as? String {
                    PoplurWebSpeech.shared.speak(
                        text,
                        rate: body["rate"] as? Double,
                        pitch: body["pitch"] as? Double
                    )
                    return
                }
                if type == "cancelSpeak" {
                    PoplurWebSpeech.shared.cancel()
                    return
                }
                if type == "openInAppBrowser" {
                    guard let rawURL = body["url"] as? String,
                          let components = URLComponents(string: rawURL),
                          components.scheme?.lowercased() == "https",
                          components.host?.isEmpty == false,
                          let url = components.url else {
                        print("[PostLoginHomeWebView] blocked invalid in-app browser URL")
                        return
                    }
                    presentInAppBrowser(url)
                    return
                }
                if type == "requestLocation" {
                    // Home posts this after its custom clay card's Allow. The
                    // primer must not raise Apple's system prompt; use an
                    // already-granted capability if one exists and defer the
                    // real ask until a location feature is invoked.
                    PoplurPermissionRouting.markHandled(.location)
                    let status = locationRequester.authorizationStatus
                    if status == .authorizedWhenInUse || status == .authorizedAlways {
                        locationRequester.requestLocation()
                    } else {
                        print("[PostLoginHomeWebView] location primer accepted in-app; system prompt deferred (status: \(status.rawValue))")
                    }
                }
                if type == "requestCameraRoll", let webView = bridge.webView {
                    // The web roll's primer Allow is not an OS permission ask.
                    // Show existing authorized photos; the actual Camera Roll
                    // action owns any later system request.
                    PoplurPermissionRouting.markHandled(.photos)
                    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                    guard status == .authorized || status == .limited else {
                        print("[PostLoginHomeWebView] photo primer accepted in-app; system prompt deferred (status: \(status.rawValue))")
                        return
                    }
                    DispatchQueue.main.async { WebCameraRollProvider.pushAuthorized(into: webView) }
                }
                if type == "requestProfileCameraRoll", let webView = bridge.webView {
                    // This comes from an explicit channel-button switch inside
                    // profile photo capture, so it is the right user gesture to
                    // request Photos access when authorization is undecided.
                    PoplurPermissionRouting.markHandled(.photos)
                    DispatchQueue.main.async { WebCameraRollProvider.push(into: webView) }
                    return
                }
                if type == "requestCameraRollAsset", let webView = bridge.webView {
                    guard let requestId = body["requestId"] as? String,
                          let assetId = body["assetId"] as? String else {
                        print("[PostLoginHomeWebView] camera-roll source request missing identifiers")
                        return
                    }
                    let maxPixelSize = (body["maxPixelSize"] as? NSNumber)?.intValue
                    WebCameraRollProvider.pushAsset(
                        requestId: requestId,
                        assetId: assetId,
                        maxPixelSize: maxPixelSize,
                        into: webView
                    )
                    return
                }
                if type == "feedAdProbabilityChanged" {
                    // The web feed mixer sets the blend now. Settings is
                    // unreachable behind the web home (AppSettingsView is
                    // orphaned), so without this the placement split could only
                    // ever be its stored default on a shipped build.
                    //
                    // The shell stays the source of truth: it normalizes and
                    // persists, and every placement decision below still reads
                    // FeedAdProbabilitySettings rather than anything the page
                    // sent. Photos and video creatives are both Poplur creative
                    // from here, so they arrive collapsed into one share.
                    guard let poplur = (body["poplurAdPercent"] as? NSNumber)?.doubleValue,
                          let google = (body["googleMobileAdPercent"] as? NSNumber)?.doubleValue else {
                        print("[PostLoginHomeWebView] feed ad mix update missing percentages")
                        return
                    }
                    DispatchQueue.main.async {
                        FeedAdProbabilitySettings.shared.setPercentages(
                            poplur: poplur,
                            googleMobile: google
                        )
                    }
                    return
                }
                if type == "feedChannelChanged" || type == "feedContentAdvanced" {
                    // Native inventory follows real feed progression. The old
                    // bridge only heard channel-button presses, so an entire
                    // session of clips could complete without ever requesting
                    // a real ad.
                    let channel = (body["channelId"] as? String) ?? "unknown"
                    let index = (body["index"] as? NSNumber)?.intValue ?? 0
                    let isContentAdvance = type == "feedContentAdvanced"
                    let namespace = isContentAdvance
                        ? "web_\(channel)_content"
                        : "web_\(channel)"
                    // Feed content needs a cadence guarantee. A small channel
                    // can have only two or three clips, and a stable random
                    // hash may place every one outside the network band.
                    // Every second completed post is still a natural break in
                    // the stream, while making real Google inventory visible
                    // in an ordinary viewing session.
                    let shouldPresent: Bool
                    if isContentAdvance {
                        let sequence = (body["sequence"] as? NSNumber)?.intValue ?? 0
                        shouldPresent = sequence > 0 && sequence % 2 == 0
                    } else {
                        shouldPresent = FeedAdProbabilitySettings.shouldShowGoogleMobileAd(
                            for: index, namespace: namespace
                        )
                    }
                    if shouldPresent {
                        DispatchQueue.main.async {
                            AdManager.shared.presentInterstitialOverKeyWindow()
                        }
                    }
                }
                if type == "requestNotifications" {
                    // The Poplur card's Allow is the ONLY thing that raises
                    // Apple's notification sheet.
                    PoplurPermissionRouting.requestNotificationsAfterPrimer()
                }
                if type == "permissionHandled",
                   let rawPermission = body["permission"] as? String,
                   let permission = PoplurPermissionRouting.Permission(rawValue: rawPermission) {
                    // A custom Don't Allow is a complete answer too. Persist it
                    // without touching the one-shot OS prompt, so a later cold
                    // authenticated launch does not repeat the primer.
                    PoplurPermissionRouting.markHandled(permission)
                }
                if type == "nativeMapPresentation", let webView = bridge.webView {
                    applyNativeMapPresentation(body, to: webView)
                }
                if type == "navigatorMotionDemandChanged",
                   let aiming = body["aiming"] as? Bool {
                    // `active` is omitted by older embedded web bundles. Treat
                    // those as active without a TTL for compatibility. Current
                    // bundles renew an explicit active lease while the governed
                    // navigator has work; a frozen/lost bridge can therefore no
                    // longer leave Core Motion sampling an untouched phone.
                    let explicitActive = body["active"] as? Bool
                    let active = explicitActive ?? true
                    if navigatorReportsMotionActive != active
                        || navigatorReportsAiming != aiming {
                        navigatorReportsMotionActive = active
                        navigatorReportsAiming = aiming
                        syncMotionLease()
                    }
                    if explicitActive == true {
                        renewNavigatorMotionDemandExpiry()
                    } else {
                        // Explicit false ends the lease now. Legacy messages
                        // intentionally retain their pre-heartbeat behaviour.
                        cancelNavigatorMotionDemandExpiry()
                    }
                }
                if type == "tabChanged", let tab = body["tab"] as? String {
                    // Record the surface in the diagnostics stream. The thermal
                    // soak reads this log to attribute heat, and until now it
                    // could not name the screen: PoplurPerformanceManager only
                    // knows the registered RENDERER (PostLoginHomeWeb covers
                    // every web tab), and snapshots are event-driven, so a
                    // settled dwell is pure silence. Every measured dwell to
                    // date says "Home" by inference, never by record. One line
                    // per user-initiated tab change: no polling, no timer.
                    if tab != currentWebTab {
                        PoplurDiagLog.append("[WebTab] committed=\(tab) previous=\(currentWebTab)")
                    }
                    currentWebTab = tab
                    if tab != "post" { webReportsLiveCamera = false }
                    if tab != "map", nativeMapPresentationActive,
                       let webView = bridge.webView {
                        nativeMapPresentationActive = false
                        (webView as? PoplurManagedWebView)?.clearNativeMapPresentation()
                        PostLoginHomeWebView.setNativeMapRendererActive(false)
                    }
                    syncMotionLease()
                    // The lease remains owned across web tabs, so start() has
                    // no edge on which to replay its latest sample. Reset only
                    // bridge dedupe and push the retained attitude after the
                    // destination has committed; otherwise a still-held phone
                    // can leave that page's navigator in its neutral pose.
                    lastMotionDeliveryUptime = 0
                    lastDeliveredRoll = nil
                    lastDeliveredPitch = nil
                    lastDeliveredHeading = nil
                    replayLatestMotion()
                    updateCameraHole()
                }
                if type == "cameraLiveVisibilityChanged" {
                    let visible = (body["visible"] as? Bool) == true
                    // A page teardown while the app is backgrounded is not a
                    // navigation away from Camera. Keep the punch-through and
                    // desired camera state ready for the matching foreground
                    // event instead of accepting a stale queued bridge message.
                    if !visible,
                       (body["lifecycleHidden"] as? Bool) == true {
                        return
                    }
                    webReportsLiveCamera = visible
                    updateCameraHole()
                }
                if type == "fetchProductImage", let webView = bridge.webView,
                   let target = body["url"] as? String {
                    // The commerce card wants the advertiser's own artwork. The
                    // WebView cannot fetch it (CORS on a custom scheme), so the
                    // shell does and answers on window.poplurProductImage.
                    PoplurProductImage.handle(urlString: target, webView: webView)
                }
                if type == "saveProfilePhoto", let rawPhoto = body["photo"] as? String {
                    persistProfilePhoto(rawPhoto)
                    return
                }
                if type == "saveProfilePhotoAsset", let rawSource = body["src"] as? String {
                    guard let sourceURL = URL(string: rawSource),
                          sourceURL.scheme == PoplurClayWebMap.scheme,
                          sourceURL.host == PoplurClayWebMap.host,
                          sourceURL.pathComponents.contains("captures"),
                          let item = PoplurWebCaptureStore.item(for: sourceURL.lastPathComponent),
                          item.mimeType.lowercased().hasPrefix("image/"),
                          let data = item.data else {
                        print("[PostLoginHomeWebView] rejected invalid profile photo asset")
                        return
                    }
                    persistProfilePhotoData(data)
                    PoplurWebCaptureStore.remove(sourceURL.lastPathComponent)
                    return
                }
                if type == "saveProfileSelfieVideo", let rawVideo = body["video"] as? String {
                    persistProfileSelfieVideo(rawVideo, into: bridge.webView)
                    return
                }
                if type == "saveProfileSelfieVideoAsset", let rawSource = body["src"] as? String {
                    guard let sourceURL = URL(string: rawSource),
                          sourceURL.scheme == PoplurClayWebMap.scheme,
                          sourceURL.host == PoplurClayWebMap.host,
                          sourceURL.pathComponents.contains("captures"),
                          let item = PoplurWebCaptureStore.item(for: sourceURL.lastPathComponent),
                          item.mimeType.lowercased().hasPrefix("video/") else {
                        print("[PostLoginHomeWebView] rejected invalid profile selfie asset")
                        return
                    }
                    if let data = item.data {
                        persistProfileSelfieVideoData(data, mimeType: item.mimeType)
                        PoplurWebCaptureStore.remove(sourceURL.lastPathComponent)
                    } else if let fileURL = item.fileURL, let webView = bridge.webView {
                        persistProfileSelfieVideoFile(
                            fileURL,
                            into: webView,
                            captureKey: sourceURL.lastPathComponent
                        )
                    } else {
                        print("[PostLoginHomeWebView] profile selfie asset has no readable source")
                    }
                    return
                }
                // The username had NO writer on the live path. The only one
                // was EditProfileView, which the web home orphaned, so every
                // handle in the product was per-device: invisible to other
                // devices and to the server, which is why a server-minted
                // wallet pass showed a uid prefix instead of a name.
                if type == "saveProfileUsername" {
                    guard let raw = Self.sanitizedUsername(body["username"] as? String),
                          let uid = Auth.auth().currentUser?.uid else { return }
                    Task {
                        do {
                            try await Firestore.firestore().collection("users").document(uid)
                                .setData(["username": raw], merge: true)
                            PoplurDiagLog.append("[PoplurProfile] username saved: \(raw)")
                        } catch {
                            PoplurDiagLog.append(
                                "[PoplurProfile] username save FAILED: \(error.localizedDescription)"
                            )
                        }
                    }
                    return
                }
                if type == "requestProfile", let webView = bridge.webView {
                    // The page asking for the profile is the reliable "we are
                    // signed in and the profile matters right now" moment, and
                    // it happens once per launch. Fire-and-forget: the backfill
                    // must never delay the answer the page is waiting for.
                    PoplurProfileBackfill.run()
                    // Answer immediately from Auth/local disk, then refresh from
                    // Firestore. A single network-dependent callback used to
                    // leave USERNAME on screen whenever auth or Firestore was
                    // briefly late during the profile tab transition.
                    let authUser = Auth.auth().currentUser
                    var localProfile: [String: Any] = ["business": false]
                    if let fallbackName = Self.authUsername(authUser) {
                        localProfile["username"] = fallbackName
                    }
                    if let localPhoto = Self.persistedProfilePhotoDataURI() {
                        localProfile["photo"] = localPhoto
                    } else if let remotePhoto = authUser?.photoURL?.absoluteString {
                        localProfile["photo"] = remotePhoto
                    }
                    if let localSelfie = PoplurProfileSelfieStore.sourceURL() {
                        localProfile["video"] = localSelfie
                    }
                    pushProfile(localProfile, into: webView)

                    Task {
                        guard let uid = authUser?.uid,
                              let snapshot = try? await Firestore.firestore()
                                  .collection("users").document(uid).getDocument(),
                              let data = snapshot.data() else { return }
                        var profile = localProfile
                        profile["business"] =
                            (data["accountType"] as? String) == PoplurAccountType.business.rawValue
                        profile["privateAccount"] = data["privateAccount"] as? Bool == true
                        profile["ghostMode"] = data["ghostMode"] as? Bool == true

                        let username = (data["username"] as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if let username, !username.isEmpty {
                            profile["username"] = username
                        } else if let derived = Self.sanitizedUsername(localProfile["username"] as? String) {
                            // The account has never had a username, because
                            // nothing on the live path could set one: the only
                            // writer was the orphaned EditProfileView. Every
                            // device therefore showed a name derived from Auth
                            // while the DOCUMENT stayed empty — which is why a
                            // server-minted wallet pass fell back to a uid
                            // prefix, and why a handle never followed the user
                            // to a second device.
                            //
                            // Auth is the one place a name genuinely exists, so
                            // settle the account from it once. Written before
                            // the push so the page and the document agree.
                            try? await Firestore.firestore().collection("users")
                                .document(uid).setData(["username": derived], merge: true)
                            profile["username"] = derived
                            PoplurDiagLog.append("[PoplurProfile] seeded username: \(derived)")
                        }
                        // `profilePictureURL` is canonical, while older RN and
                        // Android builds wrote `photoURL` / `avatarUrl`. Pull to
                        // refresh must prefer the account record over a stale
                        // per-device preview and understand every field we have
                        // shipped, otherwise the same account can have a photo
                        // on one platform and "not set" on another.
                        let remotePhoto = ["profilePictureURL", "avatarUrl", "photoURL"]
                            .compactMap { data[$0] as? String }
                            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        if let remotePhoto {
                            profile["photo"] = remotePhoto
                        }
                        if profile["video"] == nil,
                           let remoteSelfie = data["profileSelfieVideoURL"] as? String,
                           !remoteSelfie.isEmpty {
                            profile["video"] = remoteSelfie
                        }
                        await MainActor.run { self.pushProfile(profile, into: webView) }
                    }
                }
                if type == "requestProfilePosts", let webView = bridge.webView {
                    deliverProfilePosts(into: webView)
                }
                if type == "requestFeedPosts", let webView = bridge.webView {
                    deliverFeedPosts(into: webView)
                }
                if type == "deleteProfilePost", let webView = bridge.webView {
                    deleteProfilePost(body, from: webView)
                }
                if type == "requestProfileTracks", let webView = bridge.webView {
                    deliverProfileTracks(into: webView)
                }
                if type == "requestNearbyTracks", let webView = bridge.webView {
                    deliverNearbyTracks(body, into: webView)
                }
                if type == "publishTrack" {
                    WebTrackPublisher.handle(body)
                }
                if let onWebEvent {
                    DispatchQueue.main.async { onWebEvent(type, body) }
                }
            }
            if forwardToBridge {
                bridge.userContentController(userContentController, didReceive: message)
            }
        }

        /// Message types the map bridge coordinator acts on. `pop` and `poiTap`
        /// exist ONLY there (haptics, sound, POI selection), so they must be
        /// forwarded. `profile` is deliberately included even though this class
        /// also handles it: the map side merely prints the web heat probe's
        /// report line, and that print is the probe's only voice on this tab.
        /// `publishPost` is deliberately ABSENT — this class owns it.
        private static let bridgeOwnedTypes: Set<String> = ["pop", "poiTap", "profile"]

        private func applyNativeMapPresentation(
            _ body: [String: Any],
            to webView: WKWebView
        ) {
            let requestedActive = (body["active"] as? Bool) == true
            let active = PoplurNativeAdaptiveMap.isEnabled && requestedActive
            nativeMapPresentationActive = active

            let managed = webView as? PoplurManagedWebView
            guard active else {
                managed?.clearNativeMapPresentation()
                PostLoginHomeWebView.setNativeMapRendererActive(false)
                updateCameraHole()
                return
            }

            let regions = (body["regions"] as? [[String: Any]] ?? []).compactMap { item -> CGRect? in
                guard let x = (item["x"] as? NSNumber)?.doubleValue,
                      let y = (item["y"] as? NSNumber)?.doubleValue,
                      let width = (item["width"] as? NSNumber)?.doubleValue,
                      let height = (item["height"] as? NSNumber)?.doubleValue else { return nil }
                return CGRect(x: x, y: y, width: width, height: height)
            }
            let viewportWidth = (body["viewportWidth"] as? NSNumber)?.doubleValue ?? 0
            let viewportHeight = (body["viewportHeight"] as? NSNumber)?.doubleValue ?? 0
            let viewportOffsetX = (body["viewportOffsetX"] as? NSNumber)?.doubleValue ?? 0
            let viewportOffsetY = (body["viewportOffsetY"] as? NSNumber)?.doubleValue ?? 0
            managed?.setNativeMapPresentation(
                active: true,
                passthrough: (body["passthrough"] as? Bool) == true,
                cssRegions: regions,
                viewportWidth: CGFloat(viewportWidth),
                viewportHeight: CGFloat(viewportHeight),
                viewportOffset: CGPoint(x: viewportOffsetX, y: viewportOffsetY)
            )
            PostLoginHomeWebView.setNativeMapRendererActive(true)
            updateCameraHole()
        }

        private func updateCameraHole() {
            guard let webView = bridge.webView else { return }
            let shouldRevealLiveCamera = currentWebTab == "post" && webReportsLiveCamera
            let shouldRevealNativeMap = PoplurNativeAdaptiveMap.isEnabled
                && nativeMapPresentationActive
            DispatchQueue.main.async {
                PostLoginHomeWebView.setCameraHole(
                    shouldRevealLiveCamera || shouldRevealNativeMap,
                    on: webView
                )
            }
        }

        /// Opens commerce links in Apple's isolated in-app browser. The remote
        /// page never enters the Poplur WKWebView, so it cannot access the
        /// `poplur` script-message channel or any app-injected JavaScript.
        private func presentInAppBrowser(_ url: URL) {
            DispatchQueue.main.async {
                guard let presenter = Self.activePresenter() else {
                    print("[PostLoginHomeWebView] no active view controller for in-app browser")
                    return
                }
                // Poplur's own browser, not Safari's. SFSafariViewController
                // wears Safari's chrome and offers "Open in the <app>" banners,
                // so a click-through read as leaving Poplur — while the web
                // layer's ad window was telling the user the page had stayed
                // inside it. See PoplurInAppBrowser for why it builds its own
                // WKWebView configuration rather than reusing the app's.
                guard !(presenter is PoplurInAppBrowserViewController) else { return }
                guard let home = self.bridge.webView as? PoplurManagedWebView,
                      presenter.viewIfLoaded?.window != nil,
                      !presenter.isBeingDismissed else {
                    print("[PostLoginHomeWebView] in-app browser presenter is not ready")
                    return
                }

                // UIKit leaves a full-screen presenter's view attached. Park
                // the signed-in Home document explicitly before the external
                // WKWebView acquires its own heavy-renderer lease.
                home.setHostOccluded(true)
                let browser = PoplurInAppBrowserViewController(url: url) { [weak home] in
                    home?.setHostOccluded(false)
                }
                presenter.present(browser, animated: true) {
                    if browser.presentingViewController == nil {
                        browser.presentationFailed()
                    }
                }
                // UIKit may decline presentation without running completion
                // (for example during another controller transition). Check
                // on the next main-loop turn and release the same one-shot
                // occlusion lease in that failure path.
                DispatchQueue.main.async { [weak presenter, weak browser] in
                    guard let browser,
                          browser.presentingViewController == nil,
                          presenter?.presentedViewController !== browser else { return }
                    browser.presentationFailed()
                }
            }
        }

        private static func activePresenter() -> UIViewController? {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                  let window = scene.windows.first(where: { $0.isKeyWindow })
                    ?? scene.windows.first(where: { !$0.isHidden }),
                  let root = window.rootViewController else {
                return nil
            }
            return topViewController(from: root)
        }

        private static func topViewController(from controller: UIViewController) -> UIViewController {
            if let presented = controller.presentedViewController {
                return topViewController(from: presented)
            }
            if let navigation = controller as? UINavigationController,
               let visible = navigation.visibleViewController {
                return topViewController(from: visible)
            }
            if let tabs = controller as? UITabBarController,
               let selected = tabs.selectedViewController {
                return topViewController(from: selected)
            }
            return controller
        }

        private static func profilePhotoFileURL() -> URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("profile.jpg")
        }

        private static func persistedProfilePhotoDataURI() -> String? {
            guard let data = try? Data(contentsOf: profilePhotoFileURL()), !data.isEmpty else { return nil }
            let preview = profilePhotoPreviewData(from: data) ?? data
            return "data:image/jpeg;base64,\(preview.base64EncodedString())"
        }

        private static func profilePhotoPreviewData(from data: Data) -> Data? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_280,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: image, scale: 1, orientation: .up)
                .jpegData(compressionQuality: 0.9)
        }

        /// The only shape the account accepts. Bounded and character-checked
        /// rather than trusted: this lands in a document that a wallet pass, a
        /// chat thread and the phone's address book all render.
        static func sanitizedUsername(_ value: String?) -> String? {
            let raw = (value ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "@", with: "")
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_."))
            let kept = String(raw.unicodeScalars.filter { allowed.contains($0) })
            guard !kept.isEmpty else { return nil }
            return String(kept.prefix(30))
        }

        private static func authUsername(_ user: FirebaseAuth.User?) -> String? {
            if let displayName = user?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !displayName.isEmpty {
                return displayName
            }
            if let emailName = user?.email?.components(separatedBy: "@").first?
                .trimmingCharacters(in: .whitespacesAndNewlines), !emailName.isEmpty {
                return emailName
            }
            return nil
        }

        private func pushProfile(_ profile: [String: Any], into webView: WKWebView) {
            var payload = profile
            if let uid = Auth.auth().currentUser?.uid {
                payload["uid"] = uid
            }
            guard let json = try? JSONSerialization.data(withJSONObject: payload),
                  let text = String(data: json, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                "window.poplurProfile && window.poplurProfile(\(text)); " +
                "window.dispatchEvent(new CustomEvent('poplur-native-profile', {detail: \(text)})); true;"
            )
        }

        private func pushAccountPrivacy(
            privateAccount: Bool,
            ghostMode: Bool,
            ok: Bool = true,
            message: String? = nil,
            into webView: WKWebView
        ) {
            var payload: [String: Any] = [
                "privateAccount": privateAccount,
                "ghostMode": ghostMode,
                "ok": ok
            ]
            if let message, !message.isEmpty { payload["message"] = message }
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let text = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent('poplur-native-account-privacy', {detail: \(text)})); true;"
            )
        }

        private func pushProfileTheme(_ theme: ProfileTheme, into webView: WKWebView) {
            let payload = [
                "id": theme.rawValue,
                "statusBar": theme.webStatusBarValue
            ]
            guard let json = try? JSONSerialization.data(withJSONObject: payload),
                  let text = String(data: json, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                "window.poplurProfileTheme && window.poplurProfileTheme(\(text)); " +
                "window.dispatchEvent(new CustomEvent('poplur-native-profile-theme', {detail: \(text)})); true;"
            )
        }

        private func pushAppIcon(
            _ icon: PoplurAppIcon,
            accepted: Bool,
            message: String?,
            into webView: WKWebView
        ) {
            var payload: [String: Any] = [
                "id": icon.rawValue,
                "accepted": accepted
            ]
            if let message { payload["message"] = message }
            guard let json = try? JSONSerialization.data(withJSONObject: payload),
                  let text = String(data: json, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent('poplur-native-app-icon', {detail: \(text)})); true;"
            )
        }

        private func pushBackgroundAudioPreference(into webView: WKWebView) {
            let preference = PostLoginHomeWebView.backgroundAudioPreference()
            let payload: [String: Any] = [
                "enabled": preference.enabled,
                "scope": preference.scope
            ]
            guard let json = try? JSONSerialization.data(withJSONObject: payload),
                  let text = String(data: json, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                "window.__poplurNativeBackgroundAudio = \(text); " +
                "window.dispatchEvent(new CustomEvent('poplur-native-background-audio', {detail: \(text)})); true;"
            )
        }

        /// Same delivery the checkout result uses, so the page receives both
        /// through one `message` listener.
        private func pushWalletPassMessage(_ payload: [String: Any], into webView: WKWebView) {
            guard let json = try? JSONSerialization.data(withJSONObject: payload),
                  let text = String(data: json, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.postMessage(\(text), '*'); true;")
        }

        private func pushStoreCheckoutResult(
            _ result: PoplurCardCheckoutResult,
            requestID: String,
            into webView: WKWebView
        ) {
            let payload = result.webPayload(requestID: requestID)
            guard let json = try? JSONSerialization.data(withJSONObject: payload),
                  let text = String(data: json, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                "window.postMessage(\(text), '*'); " +
                "window.dispatchEvent(new CustomEvent('poplur-native-store-checkout-result', {detail: \(text)})); true;"
            )
        }

        private func deliverStoreCheckoutResult(
            _ result: PoplurCardCheckoutResult,
            requestID: String,
            into webView: WKWebView
        ) {
            guard activeStoreCheckoutRequestID == requestID else { return }
            pushStoreCheckoutResult(result, requestID: requestID, into: webView)
            if result.status != .pending {
                activeStoreCheckoutRequestID = nil
                activeStoreCheckoutProductCounts = [:]
            }
        }

        private func deliverRecoveredStorePurchase(_ note: Notification) {
            guard let requestID = activeStoreCheckoutRequestID,
                  let webView = bridge.webView,
                  let productID = note.userInfo?[PoplurCardPurchaseRecoveryNotification.productIDKey] as? String,
                  let recovery = note.object as? PoplurCardCheckoutResult,
                  let remaining = activeStoreCheckoutProductCounts[productID],
                  remaining > 0 else { return }

            if remaining == 1 { activeStoreCheckoutProductCounts.removeValue(forKey: productID) }
            else { activeStoreCheckoutProductCounts[productID] = remaining - 1 }
            let hasMore = activeStoreCheckoutProductCounts.values.contains(where: { $0 > 0 })
            let routed = PoplurCardCheckoutResult(
                status: hasMore ? .pending : .success,
                message: recovery.message,
                completedProductCounts: [productID: 1],
                creditsAdded: recovery.creditsAdded,
                availableCredits: recovery.availableCredits
            )
            deliverStoreCheckoutResult(routed, requestID: requestID, into: webView)
        }

        private static func storeCheckoutProductCounts(from rawItems: Any?) -> [String: Int]? {
            guard let items = rawItems as? [[String: Any]], !items.isEmpty else { return nil }
            var productCounts: [String: Int] = [:]
            var total = 0
            for item in items {
                guard let cardID = item["cardId"] as? String,
                      let productID = PoplurCardPurchaseService.productIDByCardID[cardID],
                      (item["iosProductId"] as? String) == productID,
                      let quantityNumber = item["quantity"] as? NSNumber else { return nil }
                let rawQuantity = quantityNumber.doubleValue
                guard rawQuantity.rounded(.towardZero) == rawQuantity,
                      rawQuantity >= 1,
                      rawQuantity <= 10 else { return nil }
                let quantity = Int(rawQuantity)
                total += quantity
                guard total <= 20 else { return nil }
                productCounts[productID, default: 0] += quantity
            }
            return productCounts
        }

        /// ProfileTwin is the shipping Profile surface, so the native shell is
        /// its authenticated Firestore boundary. Send a bounded metadata page;
        /// the web grid renders still previews and opens only one selected
        /// video, avoiding the decoder explosion that a video-per-tile grid had.
        private func deliverProfilePosts(into webView: WKWebView) {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            Task {
                do {
                    let snapshot = try await Firestore.firestore()
                        .collection("posts")
                        .whereField("userID", isEqualTo: uid)
                        .limit(to: 64)
                        .getDocuments()

                    func createdMillis(_ data: [String: Any]) -> Double {
                        if let value = data["createdAtMillis"] as? NSNumber {
                            return value.doubleValue
                        }
                        if let timestamp = data["createdAt"] as? Timestamp {
                            return timestamp.dateValue().timeIntervalSince1970 * 1000
                        }
                        return 0
                    }

                    let rows: [[String: Any]] = snapshot.documents
                        .sorted { createdMillis($0.data()) > createdMillis($1.data()) }
                        .compactMap { document in
                            let data = document.data()
                            guard let mediaURL = (data["mediaURL"] as? String)?
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                                  !mediaURL.isEmpty else { return nil }
                            let lowerURL = mediaURL.lowercased()
                            let inferredType = lowerURL.contains(".mp4")
                                || lowerURL.contains(".mov")
                                || lowerURL.contains(".m4v")
                                || lowerURL.contains(".webm")
                                ? "video" : "photo"
                            var row: [String: Any] = [
                                "id": document.documentID,
                                "mediaURL": mediaURL,
                                "mediaType": (data["mediaType"] as? String) ?? inferredType,
                                "createdAtMillis": createdMillis(data)
                            ]
                            if let poster = data["posterURL"] as? String, !poster.isEmpty {
                                row["posterURL"] = poster
                            }
                            // The poster's chosen clay pin. The Map stands this
                            // model up, so a colour that never crosses the bridge
                            // silently becomes the default pink on device.
                            if let pinColor = data["pinColor"] as? String,
                               ["red", "purple", "blue", "green", "orange"].contains(pinColor) {
                                row["pinColor"] = pinColor
                            }
                            // The poster's picture, so a visited profile can show a
                            // real face — or say none is set — instead of a stand-in
                            // head. Same field order as the web normalisers.
                            if let photo = ["profilePictureURL", "avatarURL", "avatarUrl", "photoURL"]
                                .compactMap({ data[$0] as? String })
                                .first(where: { $0.hasPrefix("https://") }) {
                                row["profilePictureURL"] = photo
                            }
                            if let caption = data["caption"] as? String, !caption.isEmpty {
                                row["caption"] = caption
                            }
                            if let channel = data["channelId"] as? String, !channel.isEmpty {
                                row["channelId"] = channel
                            }
                            // The public origin, same shape and same rules as
                            // deliverFeedPosts. Without it the profile rail's
                            // map button never appears on device: the web only
                            // builds `origin` from locationVisibility ==
                            // "approximate" plus originLatitude/Longitude, so
                            // omitting them here left every profile post
                            // originless and `locatedPost` permanently null —
                            // the button is conditional, so it simply vanished
                            // rather than failing visibly. A hidden origin
                            // stays hidden, which is why "hidden" is forwarded
                            // as itself and never carries coordinates.
                            let visibility = data["locationVisibility"] as? String
                            if visibility == "hidden" {
                                row["locationVisibility"] = "hidden"
                            } else if visibility == "approximate",
                                      let latitude = data["latitude"] as? NSNumber,
                                      let longitude = data["longitude"] as? NSNumber,
                                      abs(latitude.doubleValue) <= 90,
                                      abs(longitude.doubleValue) <= 180 {
                                row["locationVisibility"] = "approximate"
                                row["originLatitude"] = latitude.doubleValue
                                row["originLongitude"] = longitude.doubleValue
                            }
                            return row
                        }

                    let payload: [String: Any] = ["posts": rows]
                    guard let encoded = try? JSONSerialization.data(withJSONObject: payload),
                          let json = String(data: encoded, encoding: .utf8) else { return }
                    await MainActor.run {
                        guard self.bridge.webView === webView else { return }
                        webView.evaluateJavaScript(
                            "window.dispatchEvent(new CustomEvent('poplur-native-profile-posts', {detail: \(json)}));true;",
                            completionHandler: nil
                        )
                    }
                } catch {
                    print("[PostLoginHomeWebView] profile posts query failed: \(error.localizedDescription)")
                }
            }
        }

        /// The production Feed consumes the media rows users actually publish.
        /// Bundled creatives remain a browser-preview fallback, not a substitute
        /// for authenticated Firestore posts inside the app.
        private func deliverFeedPosts(into webView: WKWebView) {
            guard Auth.auth().currentUser != nil else {
                os_log("[feedRelay] no signed-in user; not forwarding", log: .default, type: .error)
                return
            }
            os_log("[feedRelay] arming feed listener", log: .default, type: .error)
            // Live, not one-shot. Inside the shell the Map is fed ONLY by this
            // forward — its own Firestore client never runs on device — so a
            // single getDocuments() meant a post published after launch never
            // reached the phone's map until the next cold start. A listener
            // re-forwards on every change; a repeat request simply re-arms it.
            // The newest 96 alone lose this account's own posts once the board
            // outpaces them — and the Profile's map button, the Map's own claims
            // and the Feed all read this forward. Fetch what this account wrote,
            // whatever its age, on its own task and cache it; the forward below
            // merges the cache synchronously, so its timing never changes (an
            // await in the forward let the sequence guard drop every forward
            // while the board kept moving — the phone showed an empty map).
            // When the cache first fills, re-arm once so the next forward carries it.
            if let uid = Auth.auth().currentUser?.uid, ownFeedDocumentsUid != uid {
                ownFeedDocumentsUid = uid
                ownFeedDocuments = []
                Task { [weak self, weak webView] in
                    guard let own = try? await Firestore.firestore()
                        .collection("posts")
                        .whereField("userID", isEqualTo: uid)
                        .limit(to: 64)
                        .getDocuments() else { return }
                    await MainActor.run {
                        guard let self, let webView, self.ownFeedDocumentsUid == uid else { return }
                        self.ownFeedDocuments = own.documents
                        if !own.documents.isEmpty { self.deliverFeedPosts(into: webView) }
                    }
                }
            }
            feedPostsRegistration?.remove()
            feedPostsRegistration = Firestore.firestore()
                .collection("posts")
                .order(by: "createdAt", descending: true)
                .limit(to: 96)
                .addSnapshotListener { [weak self, weak webView] snapshot, error in
                    // Both weak: the registration is owned by self, and a strong
                    // webView capture here would pin the web view, whose user
                    // content controller pins this coordinator — a cycle that
                    // keeps deinit (and this remove) from ever running.
                    guard let self, let webView else { return }
                    guard let snapshot else {
                        os_log("[feedRelay] listener failed: %{public}@", log: .default, type: .error, error?.localizedDescription ?? "unknown")
                        return
                    }
                    os_log("[feedRelay] listener fired: %d documents", log: .default, type: .error, snapshot.documents.count)
                    self.feedPostsSequence += 1
                    let sequence = self.feedPostsSequence
                    Task {
                    func createdMillis(_ data: [String: Any]) -> Double {
                        if let value = data["createdAtMillis"] as? NSNumber {
                            return value.doubleValue
                        }
                        if let timestamp = data["createdAt"] as? Timestamp {
                            return timestamp.dateValue().timeIntervalSince1970 * 1000
                        }
                        return 0
                    }

                    let seen = Set(snapshot.documents.map(\.documentID))
                    let documents = snapshot.documents + self.ownFeedDocuments.filter { !seen.contains($0.documentID) }
                    let rows: [[String: Any]] = documents
                        .sorted { createdMillis($0.data()) > createdMillis($1.data()) }
                        .compactMap { document in
                            let data = document.data()
                            // playbackURL first, mediaURL as the fallback — by
                            // CONTENT, not by presence. Seeded documents carry
                            // playbackURL as the empty string, and `??` only
                            // falls through for nil, so "" won, failed the
                            // isEmpty check, and the post never left this
                            // filter. Same trap, same fix, in nativeFeedPosts.ts.
                            // (Resolved before the guard: a trailing closure inside
                            // a guard condition reads as the guard's body.)
                            let mediaCandidates = [data["playbackURL"], data["mediaURL"]]
                                .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                            guard (data["audience"] as? String ?? "public") == "public",
                                  (data["status"] as? String ?? "published") == "published",
                                  let mediaURL = mediaCandidates.first(where: { !$0.isEmpty }) else { return nil }
                            let lowerURL = mediaURL.lowercased()
                            let inferredType = lowerURL.contains(".mp4")
                                || lowerURL.contains(".mov")
                                || lowerURL.contains(".m4v")
                                || lowerURL.contains(".webm")
                                ? "video" : "photo"
                            var row: [String: Any] = [
                                "id": document.documentID,
                                "mediaURL": mediaURL,
                                "mediaType": (data["mediaType"] as? String) ?? inferredType,
                                "createdAtMillis": createdMillis(data),
                                "channelId": (data["channelId"] as? String) ?? "live"
                            ]
                            if let storedName = (data["username"] as? String)?
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                               !storedName.isEmpty {
                                row["username"] = storedName
                            }
                            if let ownerID = ((data["userID"] as? String)
                                ?? (data["userId"] as? String)
                                ?? (data["ownerId"] as? String))?
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                               !ownerID.isEmpty {
                                row["ownerId"] = ownerID
                            }
                            if let poster = data["posterURL"] as? String, !poster.isEmpty {
                                row["posterURL"] = poster
                            }
                            // The poster's chosen clay pin. The Map stands this
                            // model up, so a colour that never crosses the bridge
                            // silently becomes the default pink on device.
                            if let pinColor = data["pinColor"] as? String,
                               ["red", "purple", "blue", "green", "orange"].contains(pinColor) {
                                row["pinColor"] = pinColor
                            }
                            // The poster's picture, so a visited profile can show a
                            // real face — or say none is set — instead of a stand-in
                            // head. Same field order as the web normalisers.
                            if let photo = ["profilePictureURL", "avatarURL", "avatarUrl", "photoURL"]
                                .compactMap({ data[$0] as? String })
                                .first(where: { $0.hasPrefix("https://") }) {
                                row["profilePictureURL"] = photo
                            }
                            if let caption = data["caption"] as? String, !caption.isEmpty {
                                row["caption"] = caption
                            }
                            // Provenance for test mode: the web's reach rule lets the synthetic
                            // beta cohort's pops reach every viewer while the simulation switch
                            // is on. Without these two fields the phone could not tell a tester's
                            // pop from anyone else's.
                            if let journey = data["syntheticJourney"] as? String, !journey.isEmpty {
                                row["syntheticJourney"] = journey
                            }
                            if data["syntheticBeta"] as? Bool == true {
                                row["syntheticBeta"] = true
                            }
                            // radiusMeters is the canonical field; `radius` is its
                            // legacy twin. A post carrying only radiusMeters used to
                            // cross the bridge with no radius at all, and every reach
                            // check downstream fails closed on 0 — the Map ghosted it
                            // and the Feed dropped it. Same order as nativeFeedPosts.ts.
                            if let radius = (data["radiusMeters"] ?? data["radius"] ?? data["organicRadiusMeters"]) as? NSNumber {
                                row["radiusMeters"] = radius
                            }
                            if let views = data["viewCount"] as? NSNumber {
                                row["viewCount"] = max(0, views.intValue)
                            }
                            if let likes = data["likeCount"] as? NSNumber {
                                row["likeCount"] = max(0, likes.intValue)
                            }
                            if let comments = data["commentCount"] as? NSNumber {
                                row["commentCount"] = max(0, comments.intValue)
                            }
                            if let shares = data["shareCount"] as? NSNumber {
                                row["shareCount"] = max(0, shares.intValue)
                            }
                            let visibility = data["locationVisibility"] as? String
                            if visibility == "hidden" {
                                row["locationVisibility"] = "hidden"
                            } else if visibility == "approximate",
                                      let latitude = data["latitude"] as? NSNumber,
                                      let longitude = data["longitude"] as? NSNumber,
                                      abs(latitude.doubleValue) <= 90,
                                      abs(longitude.doubleValue) <= 180 {
                                row["locationVisibility"] = "approximate"
                                row["originLatitude"] = latitude.doubleValue
                                row["originLongitude"] = longitude.doubleValue
                            }
                            return row
                        }

                    // Every post written by this app before today carries no
                    // username: iOS read Auth.displayName, which nothing here
                    // ever sets. The handle the person chose has been in
                    // users/{uid} the whole time, so resolve it for the rows
                    // that lack one rather than shipping a placeholder that
                    // makes every stranger look like the same "Poplur user".
                    os_log("[feedRelay] built %d rows (seq %d)", log: .default, type: .error, rows.count, sequence)
                    let named = await Self.namedRows(rows)

                    let payload: [String: Any] = ["posts": named]
                    guard let encoded = try? JSONSerialization.data(withJSONObject: payload),
                          let json = String(data: encoded, encoding: .utf8) else { return }
                    await MainActor.run {
                        guard self.bridge.webView === webView, sequence == self.feedPostsSequence else {
                            os_log("[feedRelay] dropped seq %d (current %d, sameWebView %d)", log: .default, type: .error, sequence, self.feedPostsSequence, self.bridge.webView === webView ? 1 : 0)
                            return
                        }
                        os_log("[feedRelay] dispatching %d posts (seq %d)", log: .default, type: .error, named.count, sequence)
                        webView.evaluateJavaScript(
                            "window.dispatchEvent(new CustomEvent('poplur-native-feed-posts', {detail: \(json)}));true;",
                            completionHandler: nil
                        )
                    }
                    }
                }
        }

        /// Fills in the handle for rows whose post document has none.
        ///
        /// Posts written by this app never carried a username: the upload read
        /// `Auth.displayName`, and nothing on iOS has ever set it — the handle
        /// lives in `users/{uid}`. Rather than migrate every historical row, the
        /// name is resolved on the way to the web, from the same cache the rest
        /// of the app already uses, so one lookup serves every post an owner has.
        /// A row whose owner genuinely has no username keeps none, and the web's
        /// own fallback shows a per-account handle instead of one shared alias.
        private static func namedRows(_ rows: [[String: Any]]) async -> [[String: Any]] {
            let missing = rows.compactMap { row -> String? in
                guard row["username"] == nil else { return nil }
                return row["ownerId"] as? String
            }
            guard !missing.isEmpty else { return rows }
            let owners = Array(Set(missing))
            await UsernameCache.shared.prefetch(uids: owners)
            var resolved: [String: String] = [:]
            for owner in owners {
                if let name = await UsernameCache.shared.username(for: owner)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !name.isEmpty {
                    resolved[owner] = name
                }
            }
            guard !resolved.isEmpty else { return rows }
            return rows.map { row in
                guard row["username"] == nil,
                      let owner = row["ownerId"] as? String,
                      let name = resolved[owner] else { return row }
                var named = row
                named["username"] = name
                return named
            }
        }

        /// Deletes only a post owned by the currently authenticated account.
        /// The web bundle is an untrusted caller: both identifiers are bounded
        /// before they reach a Firestore path, and ownership is read from the
        /// authoritative post document rather than accepted from JavaScript.
        private func deleteProfilePost(_ body: [String: Any], from webView: WKWebView) {
            let requestID = Self.boundedBridgeID(body["requestId"])
            let postID = Self.boundedBridgeID(body["postId"])
            guard let requestID, let postID else {
                deliverProfilePostDeleteResult(
                    requestID: requestID ?? "",
                    postID: postID ?? "",
                    ok: false,
                    error: "invalid_request",
                    into: webView
                )
                return
            }
            guard let uid = Auth.auth().currentUser?.uid else {
                deliverProfilePostDeleteResult(
                    requestID: requestID,
                    postID: postID,
                    ok: false,
                    error: "signed_out",
                    into: webView
                )
                return
            }

            Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                let reference = Firestore.firestore().collection("posts").document(postID)
                do {
                    let snapshot = try await reference.getDocument()
                    guard snapshot.exists else {
                        await MainActor.run {
                            self.deliverProfilePostDeleteResult(
                                requestID: requestID,
                                postID: postID,
                                ok: false,
                                error: "not_found",
                                into: webView
                            )
                        }
                        return
                    }
                    let postData = snapshot.data() ?? [:]
                    let ownerID = (postData["userID"] as? String)
                        ?? (postData["userId"] as? String)
                    guard ownerID == uid else {
                        await MainActor.run {
                            self.deliverProfilePostDeleteResult(
                                requestID: requestID,
                                postID: postID,
                                ok: false,
                                error: "forbidden",
                                into: webView
                            )
                        }
                        return
                    }

                    // New posts record their owned Storage paths. Delete only
                    // paths inside this account's posts folder; legacy rows
                    // without those fields remain document-only rather than
                    // trusting an arbitrary download URL from JavaScript.
                    for key in ["mediaStoragePath", "posterStoragePath"] {
                        guard let path = Self.ownedPostStoragePath(postData[key], uid: uid) else {
                            continue
                        }
                        try? await Storage.storage().reference(withPath: path).delete()
                    }
                    try await reference.delete()
                    await MainActor.run {
                        self.deliverProfilePostDeleteResult(
                            requestID: requestID,
                            postID: postID,
                            ok: true,
                            into: webView
                        )
                    }
                } catch {
                    await MainActor.run {
                        self.deliverProfilePostDeleteResult(
                            requestID: requestID,
                            postID: postID,
                            ok: false,
                            error: "delete_failed",
                            into: webView
                        )
                    }
                }
            }
        }

        private static func boundedBridgeID(_ value: Any?) -> String? {
            guard let value = value as? String,
                  !value.isEmpty,
                  value.utf8.count <= 128,
                  value.unicodeScalars.allSatisfy({ scalar in
                      scalar.value >= 0x21 && scalar.value <= 0x7E
                          && scalar != "/" && scalar != "\\"
                  }) else { return nil }
            return value
        }

        private static func ownedPostStoragePath(_ value: Any?, uid: String) -> String? {
            guard let path = value as? String,
                  path.utf8.count <= 240,
                  path.hasPrefix("posts/\(uid)/"),
                  !path.contains(".."),
                  String(path.dropFirst("posts/\(uid)/".count)).contains("/") == false else {
                return nil
            }
            return path
        }

        private func deliverProfilePostDeleteResult(
            requestID: String,
            postID: String,
            ok: Bool,
            error: String? = nil,
            into webView: WKWebView
        ) {
            guard bridge.webView === webView else { return }
            var payload: [String: Any] = [
                "requestId": requestID,
                "postId": postID,
                "ok": ok
            ]
            if let error { payload["error"] = error }
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent('poplur-native-profile-post-delete-result', {detail: \(json)}));true;",
                completionHandler: nil
            )
        }

        /// The signed-in user's posted MUSIC, for the iPod's shelf.
        ///
        /// Same shape as deliverProfilePosts and for the same reason: the web
        /// layer holds no Firestore credentials, so the authenticated shell
        /// does the read and hands back rows. What travels is a POINTER —
        /// `url` for a file Poplur hosts (a real stream URL the handheld can
        /// fetch and decode) or `permalink` for a SoundCloud track, which
        /// plays in their embedded player because their audio is not ours to
        /// fetch. A row naming neither is dropped here rather than shipped to
        /// a client that could only fail to play it.
        private func deliverProfileTracks(into webView: WKWebView) {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            Task {
                do {
                    let snapshot = try await Firestore.firestore()
                        .collection("tracks")
                        .whereField("userID", isEqualTo: uid)
                        .limit(to: 128)
                        .getDocuments()

                    func createdMillis(_ data: [String: Any]) -> Double {
                        if let value = data["createdAtMillis"] as? NSNumber {
                            return value.doubleValue
                        }
                        if let timestamp = data["createdAt"] as? Timestamp {
                            return timestamp.dateValue().timeIntervalSince1970 * 1000
                        }
                        return 0
                    }

                    func text(_ data: [String: Any], _ key: String) -> String? {
                        guard let raw = (data[key] as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                              !raw.isEmpty else { return nil }
                        return raw
                    }

                    let rows: [[String: Any]] = snapshot.documents
                        .sorted { createdMillis($0.data()) > createdMillis($1.data()) }
                        .compactMap { document in
                            let data = document.data()
                            let audioURL = text(data, "audioURL")
                            let permalink = text(data, "permalink")
                            // No pointer, no track.
                            guard audioURL != nil || permalink != nil else { return nil }

                            var row: [String: Any] = [
                                "id": document.documentID,
                                "title": text(data, "title") ?? "Untitled",
                                "postedAt": createdMillis(data)
                            ]
                            if let audioURL { row["url"] = audioURL }
                            if let permalink { row["permalink"] = permalink }
                            if let artist = text(data, "artist") { row["artist"] = artist }
                            if let place = text(data, "place") { row["place"] = place }
                            if let licence = text(data, "licence") { row["licence"] = licence }
                            if let mood = text(data, "mood") { row["mood"] = mood }
                            if let lat = data["lat"] as? NSNumber { row["lat"] = lat.doubleValue }
                            if let lng = data["lng"] as? NSNumber { row["lng"] = lng.doubleValue }
                            if let bpm = data["bpm"] as? NSNumber { row["bpm"] = bpm.doubleValue }
                            if let duration = data["duration"] as? NSNumber {
                                row["duration"] = duration.doubleValue
                            }
                            row["postedBy"] = text(data, "postedBy") ?? uid
                            return row
                        }

                    let payload: [String: Any] = ["tracks": rows]
                    guard let encoded = try? JSONSerialization.data(withJSONObject: payload),
                          let json = String(data: encoded, encoding: .utf8) else { return }
                    await MainActor.run {
                        guard self.bridge.webView === webView else { return }
                        webView.evaluateJavaScript(
                            "window.dispatchEvent(new CustomEvent('poplur-native-profile-tracks', {detail: \(json)}));true;",
                            completionHandler: nil
                        )
                    }
                } catch {
                    print("[PostLoginHomeWebView] profile tracks query failed: \(error.localizedDescription)")
                }
            }
        }

        /// Nearby community music is a different query from the signed-in
        /// artist's own profile shelf. The WebView supplies the location/ring;
        /// native performs the authenticated Firestore read and returns only
        /// Poplur-hosted Studio tracks. Distance is rechecked in the web layer.
        private func deliverNearbyTracks(_ body: [String: Any], into webView: WKWebView) {
            guard let lat = (body["latitude"] as? NSNumber)?.doubleValue,
                  let lng = (body["longitude"] as? NSNumber)?.doubleValue,
                  abs(lat) <= 90, abs(lng) <= 180 else { return }
            let radiusKm = min(2_000, max(1, (body["radiusKm"] as? NSNumber)?.doubleValue ?? 120))
            let requestID = (body["requestId"] as? String) ?? ""

            func distanceKm(_ otherLat: Double, _ otherLng: Double) -> Double {
                let toRad = { (value: Double) in value * .pi / 180 }
                let dLat = toRad(otherLat - lat)
                let dLng = toRad(otherLng - lng)
                let lat1 = toRad(lat)
                let lat2 = toRad(otherLat)
                let h = pow(sin(dLat / 2), 2)
                    + cos(lat1) * cos(lat2) * pow(sin(dLng / 2), 2)
                return 6_371 * 2 * asin(min(1, sqrt(h)))
            }

            func push(_ rows: [[String: Any]]) async {
                let payload: [String: Any] = ["requestId": requestID, "tracks": rows]
                guard let encoded = try? JSONSerialization.data(withJSONObject: payload),
                      let json = String(data: encoded, encoding: .utf8) else { return }
                await MainActor.run {
                    guard self.bridge.webView === webView else { return }
                    webView.evaluateJavaScript(
                        "window.dispatchEvent(new CustomEvent('poplur-native-nearby-tracks', {detail: \(json)}));true;",
                        completionHandler: nil
                    )
                }
            }

            Task {
                do {
                    let snapshot = try await Firestore.firestore()
                        .collection("tracks")
                        .limit(to: 256)
                        .getDocuments()

                    func text(_ data: [String: Any], _ key: String) -> String? {
                        guard let raw = (data[key] as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                              !raw.isEmpty else { return nil }
                        return raw
                    }
                    func createdMillis(_ data: [String: Any]) -> Double {
                        if let value = data["createdAtMillis"] as? NSNumber { return value.doubleValue }
                        if let timestamp = data["createdAt"] as? Timestamp {
                            return timestamp.dateValue().timeIntervalSince1970 * 1_000
                        }
                        return 0
                    }

                    let rows: [[String: Any]] = snapshot.documents.compactMap { document in
                        let data = document.data()
                        guard let audioURL = text(data, "audioURL"),
                              let trackLat = (data["lat"] as? NSNumber)?.doubleValue,
                              let trackLng = (data["lng"] as? NSNumber)?.doubleValue else { return nil }
                        let distance = distanceKm(trackLat, trackLng)
                        guard distance <= radiusKm else { return nil }
                        var row: [String: Any] = [
                            "id": document.documentID,
                            "title": text(data, "title") ?? "Untitled",
                            "url": audioURL,
                            "lat": trackLat,
                            "lng": trackLng,
                            "place": text(data, "place") ?? String(format: "%.1f km away", distance),
                            "postedAt": createdMillis(data),
                            "postedBy": text(data, "postedBy") ?? text(data, "userID") ?? "Poplur artist"
                        ]
                        if let artist = text(data, "artist") { row["artist"] = artist }
                        if let licence = text(data, "licence") { row["licence"] = licence }
                        if let mood = text(data, "mood") { row["mood"] = mood }
                        if let bpm = data["bpm"] as? NSNumber { row["bpm"] = bpm.doubleValue }
                        if let duration = data["duration"] as? NSNumber { row["duration"] = duration.doubleValue }
                        row["distanceKm"] = distance
                        return row
                    }.sorted {
                        (($0["distanceKm"] as? Double) ?? Double.greatestFiniteMagnitude)
                            < (($1["distanceKm"] as? Double) ?? Double.greatestFiniteMagnitude)
                    }
                    await push(rows)
                } catch {
                    print("[PostLoginHomeWebView] nearby tracks query failed: \(error.localizedDescription)")
                    await push([])
                }
            }
        }

        private func persistProfilePhoto(_ dataURI: String) {
            guard let comma = dataURI.firstIndex(of: ","),
                  dataURI[..<comma].lowercased().contains("image/jpeg"),
                  let data = Data(base64Encoded: String(dataURI[dataURI.index(after: comma)...])),
                  !data.isEmpty else {
                print("[PostLoginHomeWebView] rejected invalid profile photo")
                return
            }
            persistProfilePhotoData(data)
        }

        private func persistProfilePhotoData(_ data: Data) {
            guard !data.isEmpty,
                  data.count <= 25_000_000,
                  UIImage(data: data) != nil else {
                print("[PostLoginHomeWebView] rejected invalid profile photo data")
                return
            }
            do {
                try data.write(to: Self.profilePhotoFileURL(), options: .atomic)
                NotificationCenter.default.post(name: Notification.Name("ProfilePhotoUpdated"), object: UIImage(data: data))
            } catch {
                print("[PostLoginHomeWebView] failed to persist profile photo: \(error.localizedDescription)")
                return
            }

            guard let uid = Auth.auth().currentUser?.uid else { return }
            Task {
                do {
                    let reference = Storage.storage().reference().child("profile_pictures/\(uid).jpg")
                    _ = try await reference.putDataAsync(
                        data,
                        metadata: PoplurProfileUpload.imageMetadata()
                    )
                    let downloadURL = try await reference.downloadURL()
                    try await Firestore.firestore().collection("users").document(uid).setData(
                        ["profilePictureURL": downloadURL.absoluteString],
                        merge: true
                    )
                } catch {
                    PoplurDiagLog.append(
                        "[PoplurProfile] photo cloud sync FAILED: \(error.localizedDescription)"
                    )
                }
            }
        }

        private func persistProfileSelfieVideo(_ dataURI: String, into webView: WKWebView? = nil) {
            guard let comma = dataURI.firstIndex(of: ","),
                  dataURI[..<comma].lowercased().hasPrefix("data:video/"),
                  let mimeType = dataURI[..<comma]
                    .dropFirst("data:".count)
                    .split(separator: ";", maxSplits: 1)
                    .first.map(String.init),
                  let data = Data(base64Encoded: String(dataURI[dataURI.index(after: comma)...])) else {
                print("[PostLoginHomeWebView] rejected invalid profile selfie video")
                return
            }
            persistProfileSelfieVideoData(data, mimeType: mimeType, into: webView)
        }

        private func persistProfileSelfieVideoData(
            _ data: Data,
            mimeType: String,
            into webView: WKWebView? = nil
        ) {
            guard let localURL = PoplurProfileSelfieStore.persist(data: data, mimeType: mimeType) else {
                print("[PostLoginHomeWebView] rejected profile selfie video data")
                return
            }
            if let webView { pushProfile(["video": localURL], into: webView) }
            guard let uid = Auth.auth().currentUser?.uid else { return }
            Task {
                do {
                    let ext = PoplurProfileSelfieStore.extensionForPersistedVideo() ?? "mp4"
                    let reference = Storage.storage().reference().child("profile_selfies/\(uid).\(ext)")
                    _ = try await reference.putDataAsync(
                        data,
                        metadata: PoplurProfileUpload.videoMetadata(forExtension: ext)
                    )
                    let downloadURL = try await reference.downloadURL()
                    try await Firestore.firestore().collection("users").document(uid).setData(
                        ["profileSelfieVideoURL": downloadURL.absoluteString],
                        merge: true
                    )
                } catch {
                    PoplurDiagLog.append(
                        "[PoplurProfile] selfie cloud sync FAILED: \(error.localizedDescription)"
                    )
                }
            }
        }

        /// Photo-library videos can be long and several hundred megabytes. The
        /// profile is intentionally a ten-second selfie, so export only its
        /// opening ten seconds at a compact 720p-class preset before persisting
        /// or syncing it. The browser stays on its temporary preview until the
        /// durable custom-scheme URL is delivered below.
        private func persistProfileSelfieVideoFile(
            _ sourceURL: URL,
            into webView: WKWebView,
            captureKey: String
        ) {
            let asset = AVURLAsset(url: sourceURL)
            guard let exporter = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPreset1280x720
            ) else {
                print("[PostLoginHomeWebView] profile selfie export session unavailable")
                return
            }
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("profile-selfie-export-\(UUID().uuidString).mp4")
            try? FileManager.default.removeItem(at: temporaryURL)
            exporter.outputURL = temporaryURL
            exporter.outputFileType = .mp4
            let duration = min(asset.duration, CMTime(seconds: 10, preferredTimescale: 600))
            exporter.timeRange = CMTimeRange(start: .zero, duration: duration)
            exporter.exportAsynchronously { [weak self] in
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                guard exporter.status == .completed,
                      let data = try? Data(contentsOf: temporaryURL) else {
                    print("[PostLoginHomeWebView] profile selfie export failed: \(exporter.error?.localizedDescription ?? "unknown")")
                    return
                }
                DispatchQueue.main.async {
                    self?.persistProfileSelfieVideoData(data, mimeType: "video/mp4", into: webView)
                    PoplurWebCaptureStore.remove(captureKey)
                }
            }
        }

        /// Hand the web layer a short-lived Firebase ID token.
        ///
        /// It is a bearer credential, so it is pushed on demand rather than
        /// stored: the web keeps it in a module variable for its hour and never
        /// writes it to localStorage, where anything else in the document could
        /// read it. Sent for the SAME reason the key lives in a function — the
        /// server has to know who is asking before it spends credits.
        func pushAuthToken() {
            guard let user = Auth.auth().currentUser else { return }
            user.getIDToken { token, error in
                guard let token, error == nil else { return }
                DispatchQueue.main.async { [weak self] in
                    // `self?.webView` is ambiguous inside the Coordinator: it
                    // conforms to WKNavigationDelegate, whose webView(_:…)
                    // methods are also members, so the compiler cannot tell a
                    // property reference from a method reference. Every other
                    // access in this class goes through the bridge — do the
                    // same here.
                    guard let webView = self?.bridge.webView else { return }
                    // JSON-encode: a raw interpolation of a token into a script
                    // string is an injection waiting to happen.
                    guard let payload = try? JSONSerialization.data(
                        withJSONObject: ["token": token, "expiresIn": 3600]
                    ), let json = String(data: payload, encoding: .utf8) else { return }
                    webView.evaluateJavaScript(
                        "window.dispatchEvent(new CustomEvent('poplur-native-auth-token', { detail: \(json) })); true;",
                        completionHandler: nil
                    )
                }
            }
        }

        @MainActor
        private func pushNotificationInbox(_ items: [PoplurDeviceNotification]) {
            guard let webView = bridge.webView else { return }
            let rows: [[String: Any]] = items.map { item in
                var row: [String: Any] = [
                    "id": item.id,
                    "kind": item.webKind ?? item.kind.rawValue,
                    "title": item.title,
                    "detail": item.detail,
                    "createdAtMillis": item.createdAt.timeIntervalSince1970 * 1_000,
                    "unread": item.isUnread
                ]
                if let actorHandle = item.actorHandle { row["actorHandle"] = actorHandle }
                if let postId = item.postId { row["postId"] = postId }
                if let threadId = item.threadId { row["threadId"] = threadId }
                return row
            }
            let payload: [String: Any] = [
                "type": "poplurNotifications",
                "notifications": rows
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.postMessage(\(json), '*'); true;", completionHandler: nil)
        }

        private func signalHomeReady() {
            guard !didSignalReady else { return }
            didSignalReady = true
            if let webView = bridge.webView {
                PoplurThermalProbe.sendCurrent(to: webView)
            }
            // The document listener now exists. Replay once so an unchanged
            // handset attitude is not lost merely because native began sampling
            // a fraction of a second before React installed its handler.
            lastMotionDeliveryUptime = 0
            lastDeliveredRoll = nil
            lastDeliveredPitch = nil
            lastDeliveredHeading = nil
            replayLatestMotion()
            deliverPendingDMDeepLink()
            DispatchQueue.main.async { [onReady] in onReady() }
        }

        private func deliverPendingDMDeepLink() {
            guard didSignalReady,
                  let webView = bridge.webView,
                  let threadID = pendingDMThreadID,
                  !threadID.isEmpty,
                  threadID.count <= 200 else { return }
            pendingDMThreadID = nil
            UserDefaults.standard.removeObject(forKey: "poplur.pendingDMThreadId")
            pushWalletPassMessage(
                ["type": "poplurOpenDM", "threadId": threadID],
                into: webView
            )
        }

        /// WebKit can kill its web-content process under memory pressure while
        /// keeping the native HUD and the WKWebView itself alive. Without a
        /// reload, that leaves the exact permanent black Home surface seen on
        /// device. Retry the embedded document with a small bounded backoff;
        /// backgrounded apps defer until `setApplicationActive(true)` above.
        func recoverIfNeeded() {
            guard recoveryPending, let webView = bridge.webView else { return }
            scheduleRecovery(of: webView, reason: "foreground")
        }

        private func scheduleRecovery(of webView: WKWebView, reason: String) {
            guard let homeURL else {
                print("[PostLoginHomeWebView] cannot recover web renderer: home URL missing")
                return
            }
            recoveryPending = true
            guard UIApplication.shared.applicationState == .active else { return }
            guard recoveryWorkItem == nil else { return }

            let attempt = min(recoveryAttempt + 1, 4)
            recoveryAttempt = attempt
            let delay = min(0.18 * pow(2.0, Double(attempt - 1)), 1.5)
            let work = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView, self.bridge.webView === webView else { return }
                self.recoveryWorkItem = nil
                guard UIApplication.shared.applicationState == .active else { return }
                self.didSignalReady = false
                self.recoveryPending = false
                PostLoginHomeWebView.setCameraHole(false, on: webView)
                print("[PostLoginHomeWebView] reloading terminated web renderer (\(reason), attempt \(attempt))")
                webView.load(URLRequest(url: homeURL, cachePolicy: .reloadIgnoringLocalCacheData))
            }
            recoveryWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            PoplurDiagLog.append("[WebError] web-content process terminated")
            scheduleRecovery(of: webView, reason: "web-content process terminated")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            scheduleRecovery(of: webView, reason: "provisional navigation failed")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            scheduleRecovery(of: webView, reason: "navigation failed")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            recoveryWorkItem?.cancel()
            recoveryWorkItem = nil
            recoveryPending = false
            recoveryAttempt = 0
            // Let WebKit commit one compositor turn, then release the native
            // cover even if the document's governed rAF/timer queue is parked.
            // `signalHomeReady` is idempotent, so the concrete web first-paint
            // signal still wins whenever it arrives earlier.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                self?.signalHomeReady()
            }
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            let status = manager.authorizationStatus
            guard status != .notDetermined else { return }
            locationPermissionRequestInFlight = false
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            } else {
                print("[PostLoginHomeWebView] location permission not granted: \(status.rawValue)")
            }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let location = locations.last, let webView = bridge.webView else { return }
            let payload: [String: Any] = [
                "type": "poplur-location",
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "accuracy": location.horizontalAccuracy
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                """
                (function () {
                  var location = \(json);
                  window.__poplurNativeLocation = location;
                  window.postMessage(location, '*');
                  window.dispatchEvent(new CustomEvent('poplur-location', { detail: location }));
                  window.dispatchEvent(new CustomEvent('poplur-native-location', { detail: location }));
                  var frame = document.querySelector('iframe[title="Poplur clay map"]');
                  if (frame && frame.contentWindow) frame.contentWindow.postMessage(location, '*');
                })();
                true;
                """
            )
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            locationPermissionRequestInFlight = false
            print("[PostLoginHomeWebView] current-location request failed: \(error.localizedDescription)")
        }
    }
}
/// The WebView must never create its own Web Audio ringtone: doing so changes
/// the process-wide iOS audio session and may stop feed or radio playback.
/// This native ringer uses `.ambient`, so it automatically follows the real
/// phone's Silent/Ring switch. If media already owns audio, it stays quiet
/// while the web call UI continues to animate and vibrate.
private final class PoplurWebRingtone {
    static let shared = PoplurWebRingtone()

    private var player: AVAudioPlayer?
    private var cycleTask: Task<Void, Never>?

    private init() {}

    func start() {
        stop()
        guard PoplurEQSync.shared.prepareAudioSessionForPhoneRingtone() else { return }
        playBurst()
        cycleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.playBurst() }
            }
        }
    }

    func stop() {
        cycleTask?.cancel()
        cycleTask = nil
        player?.stop()
        player = nil
    }

    private func playBurst() {
        guard PoplurEQSync.shared.prepareAudioSessionForPhoneRingtone(),
              let data = DTMFToneGenerator.generateTone(for: "ring", duration: 1.3),
              let player = try? AVAudioPlayer(data: data) else { return }
        self.player?.stop()
        self.player = player
        player.volume = 0.72
        player.play()
    }
}
