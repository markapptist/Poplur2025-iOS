import AVFoundation
import SwiftUI
import WebKit
import CoreLocation
import Photos
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UserNotifications
import ImageIO

enum PoplurWebCaptureStore {
    struct Item {
        let data: Data?
        let fileURL: URL?
        let mimeType: String
    }

    private static var items: [String: Item] = [:]
    private static var transientCameraRollKey: String?
    private static let lock = NSLock()

    static func register(image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return register(data: data, mimeType: "image/jpeg")
    }

    /// Register already-encoded capture data without another lossy round trip.
    /// Camera Roll uses this for its orientation-correct, 4K-bounded JPEG, then
    /// hands WebKit a small custom-scheme URL instead of a multi-megabyte JS string.
    static func register(data: Data, mimeType: String) -> String {
        let key = "\(UUID().uuidString).\(fileExtension(for: mimeType))"
        lock.lock()
        items[key] = Item(data: data, fileURL: nil, mimeType: mimeType)
        lock.unlock()
        return key
    }

    /// Camera Roll selections can each be several megabytes. Keep the current
    /// one alive for its composer URL, but replace the previous roll-only item
    /// on the next selection so browsing does not grow resident memory forever.
    static func registerCameraRollAsset(data: Data, mimeType: String) -> String {
        let key = "roll-\(UUID().uuidString).\(fileExtension(for: mimeType))"
        lock.lock()
        if let previous = transientCameraRollKey { items.removeValue(forKey: previous) }
        items[key] = Item(data: data, fileURL: nil, mimeType: mimeType)
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
        lock.lock()
        items[key] = Item(data: nil, fileURL: videoURL, mimeType: "video/quicktime")
        lock.unlock()
        return key
    }

    static func item(for key: String) -> Item? {
        lock.lock()
        defer { lock.unlock() }
        return items[key]
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
// Reversible: PoplurWebHome.isEnabled (UserDefaults "poplur_web_home", default on)
// flips back to the native HomeView without a rebuild if the web home regresses.

enum PoplurWebHome {
    /// Feature flag: flip off to fall back to the native HomeView.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "poplur_web_home") as? Bool ?? true
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

/// One-shot cleanup of web caches left by builds that shared a cache key.
enum PoplurWebCache {
    private static var purged = false

    static func purgeStaleOnce() {
        guard !purged else { return }
        purged = true
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
            PoplurDiagLog.append("[PoplurWebCache] cleared stale web caches")
        }
    }
}

struct PostLoginHomeWebView: UIViewRepresentable {
    /// The page currently hosting Home. The camera layer lives outside this
    /// view's coordinator but must reach the same document to hand it detection
    /// boxes, so the live web view is published here rather than threaded
    /// through every intermediate type.
    static weak var liveWebView: WKWebView?

    /// Hand the web overlay real boxes. JSON matches `Detection` in
    /// poplur-clay-map/src/mlDetect.ts: x/y/w/h normalised 0..1, top-left origin.
    static func sendDetections(_ json: String) {
        guard let webView = liveWebView else { return }
        webView.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('poplur-native-detections', { detail: \(json) })); true;"
        )
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
    /// Monotonic token + JSON payload generated by the native speech
    /// recognizer. The coordinator forwards each token to the shared Home as a
    /// stable CustomEvent, where it drives the same tab/channel state as touch.
    let nativeVoiceCommandToken: Int
    let nativeVoiceCommandJSON: String?

    init(
        initialView: String = "home",
        onReady: @escaping () -> Void = {},
        onWebEvent: ((String, [String: Any]) -> Void)? = nil,
        nativeVoiceCommandToken: Int = 0,
        nativeVoiceCommandJSON: String? = nil
    ) {
        self.initialView = initialView
        self.onReady = onReady
        self.onWebEvent = onWebEvent
        self.nativeVoiceCommandToken = nativeVoiceCommandToken
        self.nativeVoiceCommandJSON = nativeVoiceCommandJSON
    }

    func makeCoordinator() -> Coordinator { Coordinator(onReady: onReady, onWebEvent: onWebEvent) }

    func makeUIView(context: Context) -> WKWebView {
        // Drop anything WKWebView cached from a PREVIOUS build of the bundle.
        //
        // The `?v=` cache key was CFBundleVersion+ShortVersionString, which are
        // `6` and `0.1` on every build — so the key never changed and the web
        // view kept answering from cache no matter how many times the app was
        // rebuilt and reinstalled. The visible result was two builds at once:
        // stale CSS laid over new markup, counters printing through each other.
        // buildStamp now tracks the build, but caches written under the OLD
        // constant key are still on disk, so clear them once at startup.
        PoplurWebCache.purgeStaleOnce()

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "poplur")
        config.userContentController.add(context.coordinator, name: "homeReady")
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

        let webView = WKWebView(frame: .zero, configuration: config)
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
        // Without a uiDelegate, WebKit shows its OWN permission sheets for
        // geolocation and getUserMedia — separate from, and on top of, the OS
        // permissions the app already holds. The shared clay bridge answers them
        // by forwarding the decision the user already made.
        webView.uiDelegate = context.coordinator.bridge
        Self.liveWebView = webView

        if PoplurClayMapView.bundledRootURL() != nil, let url = PoplurWebHome.url(for: initialView) {
            webView.load(URLRequest(url: url))
        } else {
            print("[PostLoginHomeWebView] ClayMapWeb bundle missing — run poplur-clay-map/scripts/sync-mobile.sh")
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onReady = onReady
        context.coordinator.deliverNativeVoiceCommand(
            token: nativeVoiceCommandToken,
            json: nativeVoiceCommandJSON
        )
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "poplur")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "homeReady")
    }

    private static let readinessScript = #"""
        (() => {
          let sent = false;
          const signalReady = () => {
            if (sent) return;
            sent = true;
            window.webkit.messageHandlers.homeReady.postMessage({ type: "ready" });
          };
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

    /// Punch-through only for the camera tab (see the opacity note above).
    static func setCameraHole(_ on: Bool, on webView: WKWebView) {
        webView.isOpaque = !on
        let opaqueBg = UIColor(red: 5/255, green: 4/255, blue: 7/255, alpha: 1)
        webView.backgroundColor = on ? .clear : opaqueBg
        webView.scrollView.backgroundColor = webView.backgroundColor
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, CLLocationManagerDelegate {
        let bridge = PoplurClayMapView.Coordinator()
        var onReady: () -> Void
        let onWebEvent: ((String, [String: Any]) -> Void)?
        private var didSignalReady = false
        private var lastNativeVoiceCommandToken = 0
        private var pendingNativeVoiceCommand: (token: Int, json: String)?
        private let locationRequester = CLLocationManager()
        private var locationPermissionRequestInFlight = false
        private var photoPermissionRequestInFlight = false
        private var notificationObservers: [NSObjectProtocol] = []

        init(onReady: @escaping () -> Void, onWebEvent: ((String, [String: Any]) -> Void)? = nil) {
            self.onReady = onReady
            self.onWebEvent = onWebEvent
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
                forName: Notification.Name("CaptureComplete"), object: nil, queue: .main
            ) { [weak self] note in
                self?.deliverNativeCapture(note)
            })
        }

        deinit {
            notificationObservers.forEach(NotificationCenter.default.removeObserver)
        }

        func deliverNativeVoiceCommand(token: Int, json: String?) {
            guard token > lastNativeVoiceCommandToken, let json else { return }
            guard didSignalReady, let webView = bridge.webView else {
                pendingNativeVoiceCommand = (token, json)
                return
            }
            lastNativeVoiceCommandToken = token
            pendingNativeVoiceCommand = nil
            webView.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent('poplur-native-voice-command', { detail: \(json) })); true;"
            )
        }

        private func flushPendingNativeVoiceCommand() {
            guard let pendingNativeVoiceCommand else { return }
            deliverNativeVoiceCommand(
                token: pendingNativeVoiceCommand.token,
                json: pendingNativeVoiceCommand.json
            )
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
                return
            }
            if let body = message.body as? [String: Any],
               let type = body["type"] as? String {
                // The shared Home reports its own first painted frame through
                // the normal Poplur bridge. Prefer that concrete signal over
                // the document-load fallback installed above: a warm Home can
                // reveal immediately, while a genuinely cold bundle remains
                // covered by the approved splash until React has painted.
                if type == "homeReady" {
                    signalHomeReady()
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
                if type == "radioScope", let scope = body["scope"] as? String,
                   ["screen", "app", "outside"].contains(scope) {
                    UserDefaults.standard.set(scope, forKey: "poplur.radio.scope")
                    if scope == "outside" {
                        let session = AVAudioSession.sharedInstance()
                        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                        try? session.setActive(true)
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
                if type == "feedChannelChanged" {
                    // The web feed reports channel changes; the shell owns the
                    // AdMob gate and presentation, exactly as the native
                    // FeedView did before the feed went web.
                    let channel = (body["channelId"] as? String) ?? "unknown"
                    let index = (body["index"] as? NSNumber)?.intValue ?? 0
                    if FeedAdProbabilitySettings.shouldShowGoogleMobileAd(
                        for: index, namespace: "web_\(channel)"
                    ) {
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
                if type == "tabChanged", let webView = bridge.webView {
                    let isCamera = (body["tab"] as? String) == "post"
                    DispatchQueue.main.async {
                        PostLoginHomeWebView.setCameraHole(isCamera, on: webView)
                    }
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
                    return
                }
                if type == "requestProfile", let webView = bridge.webView {
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
                    pushProfile(localProfile, into: webView)

                    Task {
                        guard let uid = authUser?.uid,
                              let snapshot = try? await Firestore.firestore()
                                  .collection("users").document(uid).getDocument(),
                              let data = snapshot.data() else { return }
                        var profile = localProfile
                        profile["business"] =
                            (data["accountType"] as? String) == PoplurAccountType.business.rawValue

                        let username = (data["username"] as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if let username, !username.isEmpty { profile["username"] = username }
                        if profile["photo"] == nil,
                           let remotePhoto = data["profilePictureURL"] as? String,
                           !remotePhoto.isEmpty {
                            profile["photo"] = remotePhoto
                        }
                        await MainActor.run { self.pushProfile(profile, into: webView) }
                    }
                }
                if let onWebEvent {
                    DispatchQueue.main.async { onWebEvent(type, body) }
                }
            }
            bridge.userContentController(userContentController, didReceive: message)
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

                presenter.present(PoplurInAppBrowserViewController(url: url), animated: true)
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
            guard let json = try? JSONSerialization.data(withJSONObject: profile),
                  let text = String(data: json, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                "window.poplurProfile && window.poplurProfile(\(text)); " +
                "window.dispatchEvent(new CustomEvent('poplur-native-profile', {detail: \(text)})); true;"
            )
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
                    _ = try await reference.putDataAsync(data)
                    let downloadURL = try await reference.downloadURL()
                    try await Firestore.firestore().collection("users").document(uid).setData(
                        ["profilePictureURL": downloadURL.absoluteString],
                        merge: true
                    )
                } catch {
                    print("[PostLoginHomeWebView] profile photo cloud sync failed: \(error.localizedDescription)")
                }
            }
        }

        private func signalHomeReady() {
            guard !didSignalReady else { return }
            didSignalReady = true
            if let webView = bridge.webView {
                PoplurThermalProbe.sendCurrent(to: webView)
            }
            flushPendingNativeVoiceCommand()
            DispatchQueue.main.async { [onReady] in onReady() }
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
