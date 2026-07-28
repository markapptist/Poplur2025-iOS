import SwiftUI
import WebKit
import CoreLocation
import Photos

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

    init(onReady: @escaping () -> Void = {}, onWebEvent: ((String, [String: Any]) -> Void)? = nil) {
        self.onReady = onReady
        self.onWebEvent = onWebEvent
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
        private let locationRequester = CLLocationManager()
        private var locationPermissionRequestInFlight = false
        private var photoPermissionRequestInFlight = false
        private var uploadResultObservers: [NSObjectProtocol] = []

        init(onReady: @escaping () -> Void, onWebEvent: ((String, [String: Any]) -> Void)? = nil) {
            self.onReady = onReady
            self.onWebEvent = onWebEvent
            super.init()
            locationRequester.delegate = self
            locationRequester.desiredAccuracy = kCLLocationAccuracyHundredMeters
            uploadResultObservers.append(NotificationCenter.default.addObserver(
                forName: Notification.Name("PostUploadSuccess"), object: nil, queue: .main
            ) { [weak self] note in
                self?.deliverUploadResult(success: true, note: note)
            })
            uploadResultObservers.append(NotificationCenter.default.addObserver(
                forName: Notification.Name("PostUploadFailed"), object: nil, queue: .main
            ) { [weak self] note in
                self?.deliverUploadResult(success: false, note: note)
            })
        }

        deinit {
            uploadResultObservers.forEach(NotificationCenter.default.removeObserver)
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

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "homeReady" {
                guard !didSignalReady else { return }
                didSignalReady = true
                DispatchQueue.main.async { [onReady] in onReady() }
                return
            }
            if let body = message.body as? [String: Any],
               let type = body["type"] as? String {
                if type == "requestLocation" {
                    // Home posts this only after its custom clay card's Allow.
                    // Never raise an OS prompt from startup or view mounting.
                    PoplurPermissionRouting.markHandled(.location)
                    let status = locationRequester.authorizationStatus
                    if status == .notDetermined {
                        guard !locationPermissionRequestInFlight else { return }
                        locationPermissionRequestInFlight = true
                        locationRequester.requestWhenInUseAuthorization()
                    } else if status == .authorizedWhenInUse || status == .authorizedAlways {
                        locationRequester.requestLocation()
                    } else {
                        print("[PostLoginHomeWebView] location status already decided: \(status.rawValue)")
                    }
                }
                if type == "requestCameraRoll", let webView = bridge.webView {
                    // The web roll's Allow → real OS photo permission → recent
                    // photo thumbnails pushed back as data URIs.
                    PoplurPermissionRouting.markHandled(.photos)
                    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                    if status == .notDetermined {
                        guard !photoPermissionRequestInFlight else { return }
                        photoPermissionRequestInFlight = true
                    }
                    DispatchQueue.main.async { WebCameraRollProvider.push(into: webView) }
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
                if let onWebEvent {
                    DispatchQueue.main.async { onWebEvent(type, body) }
                }
            }
            bridge.userContentController(userContentController, didReceive: message)
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
