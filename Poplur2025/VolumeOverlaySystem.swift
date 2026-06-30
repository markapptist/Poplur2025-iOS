import SwiftUI
import AVFoundation
import Combine
import AudioToolbox

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
    private var observation: NSKeyValueObservation?
    private var volumeNotificationObserver: NSObjectProtocol?
    private var refreshTimer: AnyCancellable?
    private var hideTask: Task<Void, Never>?
    private var volumePopPlayer: AVAudioPlayer?
    private var lastVolumePopTime: TimeInterval = 0
    private var isSuppressed = false

    init() {
        level = AVAudioSession.sharedInstance().outputVolume

        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

        Task { @MainActor in
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        observation = session.observe(\.outputVolume, options: [.old, .new]) { [weak self] session, change in
            let nextLevel = change.newValue ?? session.outputVolume
            Task { @MainActor in
                self?.handleVolumeChange(nextLevel, forceShow: true)
            }
        }
        volumeNotificationObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AVSystemController_SystemVolumeDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSystemVolumeNotification(notification)
        }
        refreshTimer = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.handleVolumeChange(self.session.outputVolume)
            }
    }

    deinit {
        observation?.invalidate()
        if let volumeNotificationObserver {
            NotificationCenter.default.removeObserver(volumeNotificationObserver)
        }
        refreshTimer?.cancel()
        hideTask?.cancel()
        volumePopPlayer?.stop()
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

        Task { @MainActor in
            NotificationCenter.default.post(name: .feedHardwareVolumeChanged, object: nil, userInfo: [
                "level": nextLevel,
                "reason": reason ?? "unknown"
            ])
            self.handleVolumeChange(nextLevel, forceShow: reason == nil || reason == "ExplicitVolumeChange")
        }
    }

    private func handleVolumeChange(_ newLevel: Float, forceShow: Bool = false) {
        let clampedLevel = max(0, min(1, newLevel))
        let changed = abs(clampedLevel - level) > 0.005
        level = clampedLevel
        guard !isSuppressed else { return }
        if changed || forceShow {
            playVolumePop()
            showTemporarily()
        }
    }

    private func playVolumePop() {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastVolumePopTime > 0.08 else { return }
        lastVolumePopTime = now

        guard let url = Bundle.main.url(forResource: "pop", withExtension: "mp3")
                ?? Bundle.main.url(forResource: "pop", withExtension: "wav") else {
            AudioServicesPlaySystemSound(1104)
            return
        }

        do {
            try? session.setActive(true)
            if volumePopPlayer == nil {
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = 0
                player.volume = 0.9
                player.prepareToPlay()
                volumePopPlayer = player
            }
            volumePopPlayer?.currentTime = 0
            volumePopPlayer?.play()
        } catch {
            AudioServicesPlaySystemSound(1104)
        }
    }

    private func showTemporarily() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) { isShowing = true }
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
