import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit

// MARK: - Notification name (shared between DeviceVolumeObserver and HomeView)

extension Notification.Name {
    static let feedHardwareVolumeChanged = Notification.Name("FeedHardwareVolumeChanged")
}

// MARK: - Device Volume Observer

@MainActor
final class DeviceVolumeObserver: ObservableObject {
    @Published private(set) var level: Float
    @Published private(set) var isShowing: Bool = false

    private let session = AVAudioSession.sharedInstance()
    private var volumeNotificationObserver: NSObjectProtocol?
    private var volumeObservation: NSKeyValueObservation?
    private var hideTask: Task<Void, Never>?
    private var diagnosticsTimer: Timer?
    private var lastVolumePopTime: TimeInterval = 0
    private var lastShownLevel: Float = 0
    private var lastShowTime: TimeInterval = 0
    private var isSuppressed = false

    private let volumeChangeEpsilon: Float = 0.005
    private let duplicateDisplayInterval: TimeInterval = 1.35

    init() {
        level = AVAudioSession.sharedInstance().outputVolume
        lastShownLevel = level

        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

        // KVO on outputVolume is the PRIMARY signal, and the reason the bars had
        // stopped appearing at all.
        //
        // This class used to rely solely on the notification below —
        // `AVSystemController_SystemVolumeDidChangeNotification`, which is private
        // and undocumented. It is not contractual, and when it stops being
        // delivered nothing fires, `isShowing` never flips, and the meter simply
        // never shows — with no error anywhere to say so. That is exactly what
        // happened: re-attaching the overlay to the web home did not bring the
        // bars back, because the observer itself was never hearing anything.
        //
        // `outputVolume` is KVO-compliant public API. The notification is kept
        // alongside it because it carries the change REASON, which is the only
        // way to tell a hardware press from a programmatic change — but it is now
        // an enhancement, not the thing the feature depends on.
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let level = change.newValue else { return }
            Task { @MainActor [weak self] in self?.handleVolumeChange(level) }
        }

        // DELIBERATELY NOT touching the audio session here.
        //
        // A previous version of this claimed the session at launch (`.ambient` +
        // setActive) so KVO would deliver before any audio had played. It killed
        // sound app-wide: this object is a @StateObject on the App, so it ran
        // before FeedAudioManager/FPSAudio/the guide configured their own
        // categories, and `.ambient` obeys the silent switch. A volume meter must
        // never be the thing that decides the app's audio policy — the managers
        // that actually play audio own that, and KVO delivers once any of them
        // has activated the session.
        // Audio diagnostics. "No sound" has been guessed at twice now; this
        // prints what the session ACTUALLY is on the device so the next answer is
        // read rather than inferred. `.ambient`/`.soloAmbient` obey the silent
        // switch and `.playback` does not, so the category alone often explains
        // a silent app. Also reports whether the meter is being asked to show,
        // which separates "the observer is deaf" from "the bars are hidden".
        #if DEBUG
        diagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            let s = AVAudioSession.sharedInstance()
            let showing = self?.isShowing ?? false
            let line = "[PoplurAudio] category=\(s.category.rawValue) mode=\(s.mode.rawValue)"
                + " outputVolume=\(String(format: "%.2f", s.outputVolume))"
                + " otherAudio=\(s.isOtherAudioPlaying) outputs=\(s.currentRoute.outputs.map(\.portType.rawValue))"
                + " barsShowing=\(showing)"
            print(line)
            PoplurDiagLog.append(line)
        }
        #endif

        volumeNotificationObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AVSystemController_SystemVolumeDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSystemVolumeNotification(notification)
        }
    }

    deinit {
        if let volumeNotificationObserver {
            NotificationCenter.default.removeObserver(volumeNotificationObserver)
        }
        volumeObservation?.invalidate()
        hideTask?.cancel()
        diagnosticsTimer?.invalidate()
    }

    func showForHardwareVolumePress(level newLevel: Float? = nil) {
        if isSuppressed { setSuppressed(false) }
        handleVolumeChange(newLevel ?? session.outputVolume, forceShow: true)
    }

    func setSuppressed(_ suppressed: Bool) {
        isSuppressed = suppressed
        if suppressed {
            hideTask?.cancel()
            isShowing = false
        }
    }

    private nonisolated func handleSystemVolumeNotification(_ notification: Notification) {
        let notifiedLevel = notification.userInfo?["AVSystemController_AudioVolumeNotificationParameter"] as? Float
        let reason = notification.userInfo?["AVSystemController_AudioVolumeChangeReasonNotificationParameter"] as? String
        let nextLevel = notifiedLevel ?? AVAudioSession.sharedInstance().outputVolume
        let isExplicitVolumeChange = reason == "ExplicitVolumeChange"

        Task { @MainActor in
            let clampedLevel = max(0, min(1, nextLevel))
            let changed = abs(clampedLevel - self.level) > self.volumeChangeEpsilon
            guard isExplicitVolumeChange, changed else {
                self.level = clampedLevel
                return
            }
            NotificationCenter.default.post(name: .feedHardwareVolumeChanged, object: nil, userInfo: [
                "level": clampedLevel,
                "reason": reason ?? "unknown",
                "isExplicit": true
            ])
            self.handleVolumeChange(clampedLevel)
        }
    }

    private func handleVolumeChange(_ newLevel: Float, forceShow: Bool = false) {
        let clampedLevel = max(0, min(1, newLevel))
        let changed = abs(clampedLevel - level) > volumeChangeEpsilon
        level = clampedLevel
        guard !isSuppressed else { return }
        guard changed || forceShow else { return }

        let now = Date().timeIntervalSinceReferenceDate
        // At the rails, a press changes NOTHING — pressing volume-up at 1.0 (or
        // down at 0) produces no value change, so a change-driven observer stays
        // silent and the meter never appears. Reported from the device as "bars
        // only come up when I press volume down", with the volume already at
        // 1.00. iOS shows its own HUD on every press regardless, so matching that
        // means still showing at the rails; only genuine rapid REPEATS of the
        // same level are swallowed.
        let atRail = clampedLevel >= 1 - volumeChangeEpsilon || clampedLevel <= volumeChangeEpsilon
        let duplicateForcedEvent = forceShow
            && !changed
            && !atRail
            && abs(clampedLevel - lastShownLevel) <= volumeChangeEpsilon
            && now - lastShowTime < duplicateDisplayInterval
        guard !duplicateForcedEvent else { return }

        lastShownLevel = clampedLevel
        lastShowTime = now
        // This feature has silently failed once already, with nothing anywhere to
        // say the observer had gone deaf. One line so "are the bars broken?" is a
        // log question rather than another round of guessing.
        let volLine = "[PoplurVolume] show level=\(clampedLevel) forceShow=\(forceShow)"
        print(volLine)
        PoplurDiagLog.append(volLine)
        playVolumePop()
        showTemporarily()
    }

    private func playVolumePop() {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastVolumePopTime > 0.08 else { return }
        lastVolumePopTime = now
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.45)
    }

    private func showTemporarily() {
        hideTask?.cancel()
        if !isShowing {
            withAnimation(.easeOut(duration: 0.12)) { isShowing = true }
        }
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            withAnimation(.easeIn(duration: 0.18)) { isShowing = false }
        }
    }
}

// MARK: - System HUD suppressor

/// Keeps iOS from drawing its own volume HUD, so only PoplurVolumeBars is seen.
///
/// iOS suppresses its HUD when a real MPVolumeView with a visible slider is laid
/// out in the window. "Real" is the operative word: the previous mounting gave it
/// a 1x1 frame at opacity 0.01, which is small enough that the system kept
/// drawing its own HUD anyway — the user saw BOTH meters at once. So the view is
/// given honest dimensions and moved off-screen instead of being shrunk to
/// nothing. `.offset` keeps it laid out (unlike `.hidden()` or zero size, which
/// take it out of consideration entirely).
struct SystemVolumeHUDSuppressor: View {
    @EnvironmentObject private var volumeObserver: DeviceVolumeObserver

    var body: some View {
        VolumeSliderBridge { level in
            volumeObserver.showForHardwareVolumePress(level: level)
        }
        // It must not be OCCLUDED. That was the real regression: this is mounted
        // with `.overlay(...)`, not `.background(...)`. In the native HomeView —
        // where suppression worked — the bridge is a plain sibling in the ZStack,
        // i.e. on top. Moving to the web home put it in a `.background()`, behind
        // an opaque Color fill AND an opaque WKWebView, so iOS stopped counting it
        // and drew its own HUD next to ours. Size was never the problem: HomeView
        // used 1x1 and it worked. Being visible-in-principle is the requirement.
        .frame(width: 120, height: 30)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The hidden MPVolumeView, plus the only volume signal that needs nothing else.
///
/// Two mechanisms were tried and both failed for opposite reasons:
///   - `AVSystemController_SystemVolumeDidChangeNotification` is private and no
///     longer delivered, so the meter never appeared at all.
///   - KVO on `AVAudioSession.outputVolume` only fires while the session is
///     ACTIVE, so it needed this class to claim the session — and claiming it at
///     launch killed sound app-wide (`.ambient` obeys the silent switch and ran
///     before the real audio managers configured theirs). Proof it was the only
///     thing delivering: with the activation, six volume events were logged; with
///     it reverted, zero.
/// MPVolumeView already has to exist here to suppress the system HUD, and it
/// carries a UISlider whose value tracks system volume. Reading that costs no
/// audio session, no private API, and no ownership of the app's audio policy.
struct VolumeSliderBridge: UIViewRepresentable {
    let onVolume: (Float) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onVolume: onVolume) }

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 120, height: 30))
        view.showsRouteButton = false
        // Required: no visible slider means no HUD suppression.
        view.showsVolumeSlider = true
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        // The slider is created asynchronously, so attaching once in makeUIView
        // is unreliable — retry until it exists.
        context.coordinator.attach(to: uiView)
    }

    final class Coordinator: NSObject {
        private let onVolume: (Float) -> Void
        private weak var slider: UISlider?

        init(onVolume: @escaping (Float) -> Void) { self.onVolume = onVolume }

        private var reportedMiss = false

        func attach(to view: MPVolumeView) {
            guard slider == nil else { return }
            guard let found = view.subviews.compactMap({ $0 as? UISlider }).first else {
                // If MPVolumeView never populates a slider it is not really live,
                // which would explain BOTH the missing HUD suppression and where
                // the volume signal is (or is not) coming from. Say so once.
                if !reportedMiss {
                    reportedMiss = true
                    PoplurDiagLog.append("[PoplurVolume] MPVolumeView has NO UISlider yet"
                        + " (subviews=\(view.subviews.map { String(describing: type(of: $0)) }))"
                        + " window=\(view.window != nil) size=\(view.bounds.size)")
                }
                return
            }
            slider = found
            found.addTarget(self, action: #selector(volumeChanged(_:)), for: .valueChanged)
            // Attach happens before layout, so window=false / 0x0 here is normal
            // and says nothing. What decides HUD suppression is the SETTLED
            // geometry, so check once the layout pass has run rather than making
            // the user press a button at the right moment to find out.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak view] in
                guard let view else { return }
                PoplurDiagLog.append("[PoplurVolume] settled: window=\(view.window != nil)"
                    + " size=\(view.bounds.size) hidden=\(view.isHidden) alpha=\(view.alpha)"
                    + " superSize=\(view.superview?.bounds.size ?? .zero)")
            }
        }

        @objc private func volumeChanged(_ sender: UISlider) {
            // Report the SETTLED geometry, not the attach-time snapshot. At
            // attach the view is legitimately 0x0 with no window; what matters is
            // whether it is laid out by the time a press happens, because iOS only
            // suppresses its HUD for a view that is genuinely in the hierarchy.
            if let view = sender.superview {
                PoplurDiagLog.append("[PoplurVolume] press: window=\(view.window != nil)"
                    + " size=\(view.bounds.size) superSize=\(view.superview?.bounds.size ?? .zero)"
                    + " hidden=\(view.isHidden) alpha=\(view.alpha)")
            }
            onVolume(sender.value)
        }
    }
}

// MARK: - Volume Bars View

struct PoplurVolumeBars: View {
    let volumeLevel: Float

    private let barCount = 18
    private let meterGreen = Color(red: 0.23, green: 1.0, blue: 0.18)

    var body: some View {
        let activeLevel = Int(ceil(Double(max(0, min(1, volumeLevel))) * Double(barCount)))
        VStack(spacing: 6.4) {
            ForEach((0..<barCount).reversed(), id: \.self) { index in
                let active = index < activeLevel
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(meterGreen.opacity(active ? 1.0 : 0.18))
                    .shadow(color: meterGreen.opacity(active ? 0.55 : 0), radius: 3, x: 0, y: 0)
                    .frame(width: 32, height: 8)
            }
        }
        .frame(width: 64, height: 320)
        .drawingGroup()
    }
}

// MARK: - Volume Overlay Modifier

/// Adds the volume-level meter overlay when the observer says it's visible.
/// Apply to any root view that might be presented above HomeView (e.g. fullScreenCover targets).
struct VolumeOverlayModifier: ViewModifier {
    @EnvironmentObject private var volumeObserver: DeviceVolumeObserver

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            if volumeObserver.isShowing {
                PoplurVolumeBars(volumeLevel: volumeObserver.level)
                    .frame(width: 64, height: 320)
                    .padding(.trailing, 28)
                    .padding(.bottom, 170)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Volume \(Int(volumeObserver.level * 100)) percent")
            }
        }
    }
}

extension View {
    func volumeBarsOverlay() -> some View {
        modifier(VolumeOverlayModifier())
    }
}
