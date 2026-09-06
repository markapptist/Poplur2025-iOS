import UIKit
import WebKit

@MainActor
private final class PoplurWebPolicyBridge: NSObject, WKScriptMessageHandler {
    weak var owner: PoplurManagedWebView?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        owner?.poplurWebDocumentDidBecomeReady()
    }
}

/// A WKWebView that participates in Poplur's single-heavy-renderer lease.
///
/// App-owned web screens contain several independent animation loops. WebKit
/// does not know that most of those loops are decorative, so merely capping one
/// Three.js renderer is not enough: every requestAnimationFrame source can keep
/// the GPU awake. This host installs a document-start scheduler that coalesces
/// those loops, renders a short burst while the user is interacting, and then
/// becomes event-driven. Losing visibility or the renderer lease suspends all
/// web work and media immediately.
@MainActor
final class PoplurManagedWebView: WKWebView {
    private let performanceName: String
    private let priority: Int
    private let policyBridge: PoplurWebPolicyBridge
    private var performanceRegistration: PoplurPerformanceRegistration?
    private var latestPolicy = PoplurPerformanceManager.shared.policy
    private var latestGrant = false
    private var isLightweightOverlayMode = false
    private var isLightweightOverlayRuntimeSuspended = false
    /// Valid only after the web Home explicitly reports that native MapKit is
    /// visible. Outside the reported HUD rectangles, hit-testing yields to the
    /// sibling MKMapView underneath. The default is deliberately fail-closed:
    /// a missing/stale handshake leaves the ordinary WebView fully interactive.
    private var nativeMapHitPassthroughEnabled = false
    private var nativeMapInteractiveRegions: [CGRect] = []
    private var isHostOccluded = false
    private var keepsVisibleDocumentAlive = false
    var onRuntimeActiveChange: ((Bool) -> Void)?
    var onForegroundVisibilityChange: ((Bool) -> Void)?
    private var lastReportedRuntimeActive: Bool?
    private var lastReportedForegroundVisible: Bool?

    /// Real UIKit visibility, deliberately independent of renderer/media
    /// policy. The one visible navigator must keep receiving Core Motion even
    /// when the camera HUD or heavyweight renderer is parked; hidden,
    /// covered, removed and background documents still release it.
    var poplurIsForegroundVisible: Bool {
        window != nil
            && !isHidden
            && alpha > 0.01
            && !isHostOccluded
            && UIApplication.shared.applicationState == .active
    }

    var poplurIsRuntimeActive: Bool {
        (
            latestGrant
                || keepsVisibleDocumentAlive
                || (isLightweightOverlayMode && !isLightweightOverlayRuntimeSuspended)
        )
            && window != nil
            && !isHidden
            && alpha > 0.01
            && !isHostOccluded
            && UIApplication.shared.applicationState == .active
    }

    /// Home mounts exactly one active React screen at a time. Its renderer
    /// lease may be withheld while native Camera owns the expensive renderer,
    /// but that must never suspend the foreground document's Feed/Profile
    /// media, timers, or small navigator canvas. Hidden/covered/background
    /// boundaries still close the runtime through the visibility guards above.
    func setKeepsVisibleDocumentAlive(_ enabled: Bool) {
        guard keepsVisibleDocumentAlive != enabled else {
            applyLatestPolicyToDocument()
            return
        }
        keepsVisibleDocumentAlive = enabled
        applyLatestPolicyToDocument()
    }

    init(
        performanceName: String,
        priority: Int = 100,
        frame: CGRect = .zero,
        configuration: WKWebViewConfiguration
    ) {
        let policyBridge = PoplurWebPolicyBridge()
        self.performanceName = performanceName
        self.priority = priority
        self.policyBridge = policyBridge
        PoplurWebPerformance.installBootstrap(
            into: configuration,
            messageHandler: policyBridge
        )
        super.init(frame: frame, configuration: configuration)
        policyBridge.owner = self
        poplurEnableWebInspectorInDebugBuilds()
    }

    /// Let Safari's Web Inspector attach — DEBUG builds only.
    ///
    /// Every web surface in the app is one of these, and none of them was
    /// inspectable, so a failure inside the web layer reached us on device as
    /// a bare `[WebError] Script error. :0` — no file, no line, no stack,
    /// because a cross-origin script cannot report more and the console was
    /// unreachable. That is the state a black map left us in on 6 Sep 2026:
    /// the error was logged and told us nothing.
    ///
    /// Never in Release. An inspectable WebView exposes the shipped app's
    /// internals to anyone with a cable.
    private func poplurEnableWebInspectorInDebugBuilds() {
        #if DEBUG
        isInspectable = true
        #endif
    }


    required init?(coder: NSCoder) {
        let policyBridge = PoplurWebPolicyBridge()
        performanceName = "WebView"
        priority = 100
        self.policyBridge = policyBridge
        super.init(coder: coder)
        policyBridge.owner = self
        poplurEnableWebInspectorInDebugBuilds()
        PoplurWebPerformance.installBootstrap(
            into: configuration,
            messageHandler: policyBridge
        )
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { ensurePerformanceRegistration() }
        updatePerformanceVisibility()
    }

    override var isHidden: Bool {
        didSet { updatePerformanceVisibility() }
    }

    override var alpha: CGFloat {
        didSet { updatePerformanceVisibility() }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if nativeMapHitPassthroughEnabled,
           !nativeMapInteractiveRegions.contains(where: { $0.contains(point) }) {
            return nil
        }
        return super.hitTest(point, with: event)
    }

    func poplurTearDown() {
        clearNativeMapPresentation()
        onRuntimeActiveChange?(false)
        onForegroundVisibilityChange?(false)
        lastReportedRuntimeActive = false
        lastReportedForegroundVisible = false
        performanceRegistration?.setVisible(false)
        performanceRegistration?.invalidate()
        performanceRegistration = nil
        setAllMediaPlaybackSuspended(true, completionHandler: nil)
        evaluateJavaScript(PoplurWebPerformance.purgeScript)
        stopLoading()
    }

    /// The camera tab's WebView is only a transparent HTML/CSS HUD over the
    /// native AVCapture preview. Yield its heavy-renderer lease while keeping
    /// that lightweight, interactive HUD alive; otherwise the WebView's higher
    /// priority deterministically prevents NativeCamera from ever starting.
    func setLightweightOverlayMode(_ enabled: Bool) {
        if !enabled {
            // A parked Camera HUD must never leave Feed/Map suspended after
            // the transparent camera hole closes.
            isLightweightOverlayRuntimeSuspended = false
        }
        guard isLightweightOverlayMode != enabled else {
            applyLatestPolicyToDocument()
            return
        }
        isLightweightOverlayMode = enabled
        if window != nil { ensurePerformanceRegistration() }
        updatePerformanceVisibility()
        applyLatestPolicyToDocument()
    }

    /// Applies CSS-viewport hit regions sent by HomeTwin. CSS pixels are
    /// converted into this view's points so rotation and any visual-viewport
    /// scale do not shift the clay controls away from their real hit targets.
    func setNativeMapPresentation(
        active: Bool,
        passthrough: Bool,
        cssRegions: [CGRect],
        viewportWidth: CGFloat,
        viewportHeight: CGFloat,
        viewportOffset: CGPoint
    ) {
        guard active, passthrough,
              viewportWidth.isFinite, viewportWidth > 0,
              viewportHeight.isFinite, viewportHeight > 0,
              bounds.width > 0, bounds.height > 0 else {
            nativeMapHitPassthroughEnabled = false
            nativeMapInteractiveRegions = []
            return
        }

        let scaleX = bounds.width / viewportWidth
        let scaleY = bounds.height / viewportHeight
        let boundsRect = CGRect(origin: .zero, size: bounds.size)
        nativeMapInteractiveRegions = cssRegions.compactMap { region in
            guard region.minX.isFinite, region.minY.isFinite,
                  region.width.isFinite, region.height.isFinite,
                  region.width > 0, region.height > 0 else { return nil }
            let converted = CGRect(
                x: (region.minX - viewportOffset.x) * scaleX,
                y: (region.minY - viewportOffset.y) * scaleY,
                width: region.width * scaleX,
                height: region.height * scaleY
            ).insetBy(dx: -2, dy: -2).intersection(boundsRect)
            return converted.isNull || converted.isEmpty ? nil : converted
        }
        nativeMapHitPassthroughEnabled = true
    }

    func clearNativeMapPresentation() {
        nativeMapHitPassthroughEnabled = false
        nativeMapInteractiveRegions = []
    }

    /// Pauses the transparent Camera HUD's governed rAF/timers/CSS/media while
    /// leaving the WKWebView visible and interactive. The parked preview's
    /// synchronous tap handler can therefore still ask native to restart the
    /// camera after policy recovery without an idle web runtime burning power.
    func setLightweightOverlayRuntimeSuspended(_ suspended: Bool) {
        guard isLightweightOverlayMode,
              isLightweightOverlayRuntimeSuspended != suspended else { return }
        isLightweightOverlayRuntimeSuspended = suspended
        applyLatestPolicyToDocument()
    }

    /// UIKit does not remove the presenting view when SwiftUI raises a
    /// full-screen cover, so window/hidden/alpha remain deceptively "visible".
    /// The host explicitly closes both the native lease and document runtime
    /// while another full-screen surface owns the display.
    func setHostOccluded(_ occluded: Bool) {
        guard isHostOccluded != occluded else { return }
        isHostOccluded = occluded
        if window != nil { ensurePerformanceRegistration() }
        updatePerformanceVisibility()
        applyLatestPolicyToDocument()
    }

    /// UIKit owns whether this document is genuinely foregrounded. Refresh the
    /// governed runtime directly because WebKit can miss a matching `pageshow`
    /// after the app returns from the switcher.
    func refreshApplicationLifecycle() {
        applyLatestPolicyToDocument()
    }

    private func ensurePerformanceRegistration() {
        guard performanceRegistration == nil else { return }
        performanceRegistration = PoplurPerformanceManager.shared.registerRenderer(
            name: performanceName,
            classification: .heavy,
            rateClass: .interactive,
            priority: priority,
            onPolicy: { [weak self] policy, granted in
                self?.apply(policy: policy, granted: granted)
            },
            onPurgeInactiveResources: { [weak self] in
                guard let self else { return }
                self.setAllMediaPlaybackSuspended(true, completionHandler: nil)
                self.evaluateJavaScript(PoplurWebPerformance.purgeScript)
            }
        )
    }

    private func updatePerformanceVisibility() {
        performanceRegistration?.setVisible(
            window != nil
                && !isHidden
                && alpha > 0.01
                && !isLightweightOverlayMode
                && !isHostOccluded
        )
        reportForegroundVisibility()
    }

    private func reportForegroundVisibility() {
        let foregroundVisible = poplurIsForegroundVisible
        if lastReportedForegroundVisible != foregroundVisible {
            lastReportedForegroundVisible = foregroundVisible
            onForegroundVisibilityChange?(foregroundVisible)
        }
    }

    private func apply(policy: PoplurPerformancePolicy, granted: Bool) {
        latestPolicy = policy
        latestGrant = granted
        applyLatestPolicyToDocument()
    }

    fileprivate func poplurWebDocumentDidBecomeReady() {
        // A navigation replaces the JavaScript world. The bootstrap starts
        // closed, then asks native for the current lease so a stale document-
        // creation snapshot can never create a second active heavy renderer.
        applyLatestPolicyToDocument()
    }

    private func applyLatestPolicyToDocument() {
        reportForegroundVisibility()
        let active = poplurIsRuntimeActive
        if lastReportedRuntimeActive != active {
            lastReportedRuntimeActive = active
            onRuntimeActiveChange?(active)
        }
        setAllMediaPlaybackSuspended(!active, completionHandler: nil)
        evaluateJavaScript(PoplurWebPerformance.updateScript(policy: latestPolicy, active: active))
    }
}

@MainActor
enum PoplurWebPerformance {
    private static let readyHandlerName = "poplurPerformanceReady"

    static func installBootstrap(
        into configuration: WKWebViewConfiguration,
        messageHandler: WKScriptMessageHandler
    ) {
        let manager = PoplurPerformanceManager.shared
        configuration.userContentController.add(
            messageHandler,
            name: readyHandlerName
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                // Every new document starts closed. Its ready message below
                // reapplies the view's retained, current native lease.
                source: bootstrapScript(policy: manager.policy, active: false),
                injectionTime: .atDocumentStart,
                // Home hosts the Mapbox surface in a child frame. Governing
                // only the top document leaves that frame's rAF/timers/media
                // alive after the native renderer lease is revoked.
                forMainFrameOnly: false
            )
        )
    }

    static func updateScript(policy: PoplurPerformancePolicy, active: Bool) -> String {
        let json = policyJSON(policy: policy, active: active)
        return "window.__poplurPerformanceRuntime && window.__poplurPerformanceRuntime.setPolicy(\(json)); true;"
    }

    static let purgeScript = """
        (() => {
          try { window.__poplurPerformanceRuntime?.setPolicy({active:false}); } catch (_) {}
          try { window.dispatchEvent(new Event('poplur-performance-purge')); } catch (_) {}
          try { window.speechSynthesis?.cancel(); } catch (_) {}
          return true;
        })();
        """

    private static func policyJSON(policy: PoplurPerformancePolicy, active: Bool) -> String {
        let maxDPR: Double
        let startupBurstMS: Int
        let interactionBurstMS: Int
        switch policy.mode {
        case .full:
            maxDPR = 1.25
            startupBurstMS = 3_000
            interactionBurstMS = 1_400
        case .reduced:
            maxDPR = 1
            startupBurstMS = 2_000
            interactionBurstMS = 1_000
        case .lowPower:
            maxDPR = 1
            startupBurstMS = 900
            interactionBurstMS = 700
        case .emergency:
            maxDPR = 1
            startupBurstMS = 250
            interactionBurstMS = 350
        }

        let object: [String: Any] = [
            "mode": policy.mode.diagnosticName,
            "active": active,
            "idleFPS": max(1, policy.targetFPS),
            "interactiveFPS": max(1, policy.interactiveTargetFPS),
            "startupBurstMS": startupBurstMS,
            "interactionBurstMS": interactionBurstMS,
            "particlesAllowed": policy.particlesAllowed,
            "particleDensityMultiplier": policy.particleDensityMultiplier,
            "dynamicShadowsAllowed": policy.dynamicShadowsAllowed,
            "postProcessingAllowed": policy.postProcessingAllowed,
            "maximumTextureResolution": policy.maximumPreferredTextureResolution,
            "expensiveVideoTexturesAllowed": policy.expensiveVideoTexturesAllowed,
            "maxDevicePixelRatio": maxDPR,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"active\":false,\"idleFPS\":1,\"interactiveFPS\":1,\"maxDevicePixelRatio\":1}"
        }
        return json.replacingOccurrences(of: "<", with: "\\u003c")
    }

    private static func bootstrapScript(policy: PoplurPerformancePolicy, active: Bool) -> String {
        let initial = policyJSON(policy: policy, active: active)
        return #"""
        ;(() => {
          if (window.__poplurPerformanceRuntime) {
            window.__poplurPerformanceRuntime.setPolicy(\#(initial));
            try {
              window.webkit?.messageHandlers?.poplurPerformanceReady?.postMessage('ready');
            } catch (_) {}
            return;
          }

          const nativeRAF = window.requestAnimationFrame.bind(window);
          const nativeCAF = window.cancelAnimationFrame.bind(window);
          const nativeSetTimeout = window.setTimeout.bind(window);
          const nativeClearTimeout = window.clearTimeout.bind(window);
          const nativeSetInterval = window.setInterval.bind(window);
          const nativeClearInterval = window.clearInterval.bind(window);
          const nativeDPR = Math.max(1, Number(window.devicePixelRatio) || 1);
          let policy = \#(initial);
          let pageVisible = true;
          let interactiveUntil = performance.now() + Math.max(0, Number(policy.startupBurstMS) || 0);
          let frameDriver = 0;
          let frameTimer = 0;
          let idleTimer = 0;
          let lastFrame = 0;
          let inFrameFlush = false;
          let frameSequence = 1_000_000_000;
          const frameQueue = new Map();
          let intervalSequence = 1_500_000_000;
          const intervals = new Map();
          let timeoutSequence = 1_750_000_000;
          const timeouts = new Map();
          const suspendedMedia = new Set();

          const runnable = () => policy.active !== false && pageVisible && !document.hidden;
          // The Home navigator is a single small foreground canvas. It may
          // opt into the physical display clock for smooth globe rotation and
          // immediate device-tilt response without lifting the governed rAF
          // cadence for Mapbox, weather, media, or the rest of the document.
          window.__poplurDisplayRAF = callback => nativeRAF(callback);
          window.__poplurCancelDisplayRAF = id => nativeCAF(id);
          window.__poplurDisplayActive = () => runnable();
          // The visible document has two cadences, never two lifecycle states:
          // direct manipulation gets the interactive budget, while authored
          // motion between touches continues at the lower foreground budget.
          // Only an actually hidden/covered document is suspended. This keeps
          // the globe and device-orientation cube alive without letting an
          // active Three/Mapbox loop drive a ProMotion display at 120 Hz.
          const frameRate = () => Math.max(
            1,
            Number(inInteractiveBurst() ? policy.interactiveFPS : policy.idleFPS) || 12
          );
          const frameDelay = () => 1000 / frameRate();
          const inInteractiveBurst = () => performance.now() < interactiveUntil;
          function markIdle(idle) {
            document.documentElement?.classList.toggle('poplur-performance-idle', idle);
          }

          function armIdleDeadline() {
            if (idleTimer) nativeClearTimeout(idleTimer);
            idleTimer = 0;
            if (!runnable()) return;
            const delay = Math.max(0, interactiveUntil - performance.now());
            idleTimer = nativeSetTimeout(() => {
              idleTimer = 0;
              if (!runnable()) return;
              if (inInteractiveBurst()) {
                armIdleDeadline();
                return;
              }
              // CSS animations may be the only moving work on a page. They do
              // not enqueue rAF callbacks, so the frame driver cannot be the
              // mechanism that marks the document idle.
              markIdle(true);
            }, delay + 1);
          }

          function wake(duration) {
            if (!runnable()) return;
            interactiveUntil = Math.max(
              interactiveUntil,
              performance.now() + Math.max(120, Number(duration) || Number(policy.interactionBurstMS) || 800)
            );
            markIdle(false);
            armIdleDeadline();
            intervals.forEach(armInterval);
            scheduleFrames();
          }

          function scheduleFrames() {
            if (!runnable() || frameDriver || frameTimer || frameQueue.size === 0) return;
            const delay = Math.max(0, frameDelay() - (performance.now() - lastFrame));
            if (delay > 2) {
              frameTimer = nativeSetTimeout(() => {
                frameTimer = 0;
                scheduleFrames();
              }, delay);
            } else {
              frameDriver = nativeRAF(flushFrames);
            }
          }

          function flushFrames(now) {
            frameDriver = 0;
            if (!runnable()) return;
            if (now - lastFrame + 0.5 < frameDelay()) {
              scheduleFrames();
              return;
            }
            lastFrame = now;
            const callbacks = Array.from(frameQueue.entries());
            frameQueue.clear();
            inFrameFlush = true;
            callbacks.forEach(pair => {
              try { pair[1](now); }
              catch (error) { nativeSetTimeout(() => { throw error; }, 0); }
            });
            inFrameFlush = false;
            scheduleFrames();
          }

          window.requestAnimationFrame = callback => {
            const id = ++frameSequence;
            frameQueue.set(id, callback);
            // Scheduling work does not manufacture an interaction lease. It
            // receives the bounded foreground cadence until real input calls
            // wake(), then temporarily receives the interactive cadence.
            scheduleFrames();
            return id;
          };
          window.cancelAnimationFrame = id => {
            frameQueue.delete(id);
            if (frameQueue.size === 0) {
              if (frameDriver) nativeCAF(frameDriver);
              if (frameTimer) nativeClearTimeout(frameTimer);
              frameDriver = 0;
              frameTimer = 0;
            }
          };

          function armInterval(record) {
            // Components on inactive tabs are unmounted. Timers belonging to
            // the one visible screen therefore remain functional between
            // touches, while pauseWork tears them down at the real lifecycle
            // boundary (covered/background/removed WebView).
            if (!runnable() || record.timer) return;
            record.timer = nativeSetTimeout(function tick() {
              record.timer = 0;
              if (!intervals.has(record.id)) return;
              if (runnable()) {
                try { record.callback.apply(window, record.args); }
                catch (error) { nativeSetTimeout(() => { throw error; }, 0); }
              }
              armInterval(record);
            }, record.delay);
          }
          window.setInterval = function(callback, delay) {
            if (typeof callback !== 'function') return nativeSetInterval(callback, delay);
            const id = ++intervalSequence;
            const record = {
              id,
              callback,
              args: Array.prototype.slice.call(arguments, 2),
              delay: Math.max(250, Number(delay) || 0),
              timer: 0
            };
            intervals.set(id, record);
            armInterval(record);
            return id;
          };
          window.clearInterval = id => {
            const record = intervals.get(id);
            if (!record) { nativeClearInterval(id); return; }
            if (record.timer) nativeClearTimeout(record.timer);
            intervals.delete(id);
          };

          function armTimeout(record) {
            if (!runnable() || record.timer) return;
            record.deadline = performance.now() + record.remaining;
            record.timer = nativeSetTimeout(() => {
              record.timer = 0;
              if (!timeouts.delete(record.id)) return;
              try { record.callback.apply(window, record.args); }
              catch (error) { nativeSetTimeout(() => { throw error; }, 0); }
            }, record.remaining);
          }
          window.setTimeout = function(callback, delay) {
            if (typeof callback !== 'function') return nativeSetTimeout(callback, delay);
            const id = ++timeoutSequence;
            const record = {
              id,
              callback,
              args: Array.prototype.slice.call(arguments, 2),
              remaining: Math.max(0, Number(delay) || 0),
              deadline: 0,
              timer: 0
            };
            timeouts.set(id, record);
            armTimeout(record);
            return id;
          };
          window.clearTimeout = id => {
            const record = timeouts.get(id);
            if (!record) { nativeClearTimeout(id); return; }
            if (record.timer) nativeClearTimeout(record.timer);
            timeouts.delete(id);
          };

          const mediaPrototype = window.HTMLMediaElement?.prototype;
          const nativePlay = mediaPrototype?.play;
          if (nativePlay) {
            mediaPrototype.play = function() {
              if (!runnable()) {
                suspendedMedia.add(this);
                return Promise.resolve();
              }
              return nativePlay.call(this);
            };
          }

          function pauseWork() {
            if (frameDriver) nativeCAF(frameDriver);
            if (frameTimer) nativeClearTimeout(frameTimer);
            if (idleTimer) nativeClearTimeout(idleTimer);
            frameDriver = 0;
            frameTimer = 0;
            idleTimer = 0;
            intervals.forEach(record => {
              if (record.timer) nativeClearTimeout(record.timer);
              record.timer = 0;
            });
            const pausedAt = performance.now();
            timeouts.forEach(record => {
              if (record.timer) {
                record.remaining = Math.max(0, record.deadline - pausedAt);
                nativeClearTimeout(record.timer);
              }
              record.timer = 0;
            });
            document.querySelectorAll('audio,video').forEach(media => {
              if (!media.paused) {
                suspendedMedia.add(media);
                media.pause();
              }
            });
            document.documentElement?.classList.add('poplur-performance-paused');
            try { window.speechSynthesis?.cancel(); } catch (_) {}
          }

          function resumeWork() {
            document.documentElement?.classList.remove('poplur-performance-paused');
            intervals.forEach(armInterval);
            timeouts.forEach(armTimeout);
            Array.from(suspendedMedia).forEach(media => {
              suspendedMedia.delete(media);
              if (!media.isConnected || !nativePlay) return;
              const result = nativePlay.call(media);
              result?.catch?.(() => {});
            });
            wake(Math.max(280, Number(policy.interactionBurstMS) || 800));
          }

          function sync() {
            if (runnable()) resumeWork();
            else pauseWork();
          }

          function apply(next) {
            policy = Object.assign({}, policy, next || {});
            document.documentElement?.setAttribute('data-poplur-performance-mode', policy.mode || 'LOW_POWER');
            document.documentElement?.setAttribute(
              'data-poplur-performance-active',
              policy.active === false ? 'false' : 'true'
            );
            document.documentElement?.style.setProperty(
              '--poplur-particle-density',
              String(policy.particleDensityMultiplier ?? 0)
            );
            try {
              window.dispatchEvent(new CustomEvent('poplur-performance-policy', {detail: policy}));
            } catch (_) {}
            // evaluateJavaScript updates the main frame. Relay the policy down
            // the frame tree so embedded Mapbox/media documents lose their
            // work lease in the same transition.
            document.querySelectorAll('iframe').forEach(frame => {
              try {
                frame.contentWindow?.postMessage(
                  {type: 'poplur-native-performance-policy', policy}, '*'
                );
              } catch (_) {}
            });
            sync();
          }

          try {
            Object.defineProperty(window, 'devicePixelRatio', {
              configurable: true,
              get: () => Math.min(nativeDPR, Math.max(1, Number(policy.maxDevicePixelRatio) || 1))
            });
          } catch (_) {}

          const nativeGetContext = window.HTMLCanvasElement?.prototype?.getContext;
          if (nativeGetContext) {
            window.HTMLCanvasElement.prototype.getContext = function(type, attributes) {
              if (/^webgl2?$/i.test(String(type)) || type === 'experimental-webgl') {
                attributes = Object.assign({}, attributes || {}, {
                  antialias: false,
                  powerPreference: 'low-power'
                });
              }
              return nativeGetContext.call(this, type, attributes);
            };
          }

          window.__poplurPerformanceRuntime = {
            setPolicy: apply,
            getPolicy: () => Object.assign({}, policy),
            wake: duration => {
              const requested = Number.isFinite(Number(duration))
                ? Number(duration)
                : (Number(policy.interactionBurstMS) || 800);
              // Known finite operations may finish, but page script can never
              // turn this escape hatch into an unbounded rendering lease.
              wake(Math.min(15000, Math.max(0, requested)));
            }
          };

          ['pointerdown', 'touchstart', 'keydown', 'focusin', 'wheel'].forEach(name =>
            window.addEventListener(name, () => wake(policy.interactionBurstMS), {capture: true, passive: true})
          );
          window.addEventListener('pointermove', event => {
            if (event.buttons) wake(policy.interactionBurstMS);
          }, {capture: true, passive: true});
          window.addEventListener('touchmove', () => wake(policy.interactionBurstMS), {capture: true, passive: true});
          window.addEventListener('scroll', () => wake(policy.interactionBurstMS), {capture: true, passive: true});
          window.addEventListener('message', event => {
            if (event.source !== window.parent) return;
            if (event.data?.type !== 'poplur-native-performance-policy') return;
            apply(event.data.policy);
          });
          document.addEventListener('visibilitychange', sync);
          window.addEventListener('pagehide', () => { pageVisible = false; sync(); });
          window.addEventListener('pageshow', () => { pageVisible = true; sync(); });

          function installStyle() {
            if (document.getElementById('poplur-performance-style')) return;
            const style = document.createElement('style');
            style.id = 'poplur-performance-style';
            style.textContent =
              '.poplur-performance-paused * {' +
              'animation-play-state:paused!important;' +
              '}' +
              'html[data-poplur-performance-mode="LOW_POWER"] #confetti>*:not(:nth-child(6n)) {' +
              'display:none!important;' +
              '}' +
              'html[data-poplur-performance-mode="EMERGENCY"] #confetti {' +
              'display:none!important;' +
              '}';
            (document.head || document.documentElement).appendChild(style);
          }
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', installStyle, {once: true});
          } else {
            installStyle();
          }
          apply(policy);
          try {
            window.webkit?.messageHandlers?.poplurPerformanceReady?.postMessage('ready');
          } catch (_) {}
        })();
        true;
        """#
    }
}
