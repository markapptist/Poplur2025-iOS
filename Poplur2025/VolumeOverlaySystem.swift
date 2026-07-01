import SwiftUI
import AVFoundation
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
    private var hideTask: Task<Void, Never>?
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
        hideTask?.cancel()
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
            self.level = clampedLevel
            guard isExplicitVolumeChange else { return }
            NotificationCenter.default.post(name: .feedHardwareVolumeChanged, object: nil, userInfo: [
                "level": clampedLevel,
                "reason": reason ?? "unknown",
                "isExplicit": true
            ])
            self.handleVolumeChange(clampedLevel, forceShow: isExplicitVolumeChange)
        }
    }

    private func handleVolumeChange(_ newLevel: Float, forceShow: Bool = false) {
        let clampedLevel = max(0, min(1, newLevel))
        let changed = abs(clampedLevel - level) > volumeChangeEpsilon
        level = clampedLevel
        guard !isSuppressed else { return }
        guard changed || forceShow else { return }

        let now = Date().timeIntervalSinceReferenceDate
        let duplicateForcedEvent = forceShow
            && !changed
            && abs(clampedLevel - lastShownLevel) <= volumeChangeEpsilon
            && now - lastShowTime < duplicateDisplayInterval
        guard !duplicateForcedEvent else { return }

        lastShownLevel = clampedLevel
        lastShowTime = now
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
