import SwiftUI
import WebKit
import CoreLocation
import Photos
import UIKit
import FirebaseAuth
import FirebaseFirestore

enum PoplurWebCaptureStore {
    struct Item {
        let data: Data?
        let fileURL: URL?
        let mimeType: String
    }

    private static var items: [String: Item] = [:]
    private static let lock = NSLock()

    static func register(image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        let key = "\(UUID().uuidString).jpg"
        lock.lock()
        items[key] = Item(data: data, fileURL: nil, mimeType: "image/jpeg")
        lock.unlock()
        return key
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
    static var homeURL: URL? {
        var components = URLComponents()
        components.scheme = PoplurClayWebMap.scheme
        components.host = PoplurClayWebMap.host
        components.path = "/index.html"
        var queryItems = [
            URLQueryItem(name: "view", value: "home"),
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
        guard !preloginHandledThisLaunch else { return [] }

        var items: [URLQueryItem] = []
        if CLLocationManager().authorizationStatus == .notDetermined,
           !wasHandled(.location) {
            items.append(URLQueryItem(name: "askLocation", value: "1"))
        }
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined,
           !wasHandled(.photos) {
            items.append(URLQueryItem(name: "askPhotos", value: "1"))
        }
        return items
    }
}

struct PostLoginHomeWebView: UIViewRepresentable {
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
        onReady: @escaping () -> Void = {},
        onWebEvent: ((String, [String: Any]) -> Void)? = nil,
        nativeVoiceCommandToken: Int = 0,
        nativeVoiceCommandJSON: String? = nil
    ) {
        self.onReady = onReady
        self.onWebEvent = onWebEvent
        self.nativeVoiceCommandToken = nativeVoiceCommandToken
        self.nativeVoiceCommandJSON = nativeVoiceCommandJSON
    }

    func makeCoordinator() -> Coordinator { Coordinator(onReady: onReady, onWebEvent: onWebEvent) }

    func makeUIView(context: Context) -> WKWebView {
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

        if PoplurClayMapView.bundledRootURL() != nil, let url = PoplurWebHome.homeURL {
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
                  let webView = bridge.webView else { return }
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
                if type == "requestProfile", let webView = bridge.webView {
                    // The web ProfileTwin asks who is signed in; answer with the
                    // Firestore user doc so it shows the real signup username
                    // instead of the USERNAME placeholder.
                    Task {
                        guard let uid = Auth.auth().currentUser?.uid,
                              let snapshot = try? await Firestore.firestore()
                                  .collection("users").document(uid).getDocument(),
                              let data = snapshot.data() else { return }
                        var profile: [String: Any] = [
                            "business": (data["accountType"] as? String) == PoplurAccountType.business.rawValue
                        ]
                        let username = (data["username"] as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if let username, !username.isEmpty { profile["username"] = username }
                        guard let json = try? JSONSerialization.data(withJSONObject: profile),
                              let text = String(data: json, encoding: .utf8) else { return }
                        await MainActor.run {
                            webView.evaluateJavaScript(
                                "window.poplurProfile && window.poplurProfile(\(text)); true;"
                            )
                        }
                    }
                }
                if let onWebEvent {
                    DispatchQueue.main.async { onWebEvent(type, body) }
                }
            }
            bridge.userContentController(userContentController, didReceive: message)
        }

        private func signalHomeReady() {
            guard !didSignalReady else { return }
            didSignalReady = true
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
