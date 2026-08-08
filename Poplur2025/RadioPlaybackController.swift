import AVFoundation
import Foundation

@MainActor
final class RadioPlaybackController: ObservableObject {
    static let shared = RadioPlaybackController()

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTitle = "CBC Radio One - Toronto"

    private var player: AVPlayer?
    private let defaultStationURL = URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/CBCR1_TORONTO_HLS.m3u8")!

    private init() {}

    func play(url: URL? = nil, title: String? = nil) {
        let mode = SettingsStore.shared.radioPlaybackMode
        configureAudioSession(for: mode)
        currentTitle = title ?? currentTitle

        if player == nil || player?.currentItem == nil {
            player = AVPlayer(url: url ?? defaultStationURL)
        }

        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
    }

    func applyMode(_ mode: RadioPlaybackMode) {
        configureAudioSession(for: mode)
        if mode == .screenOnly {
            NotificationCenter.default.post(name: .RadioPlaybackRequiresScreenOnly, object: nil)
        }
    }

    func didLeaveRadioScreen() {
        if SettingsStore.shared.radioPlaybackMode == .screenOnly {
            stop()
        }
    }

    private func configureAudioSession(for mode: RadioPlaybackMode) {
        do {
            let session = AVAudioSession.sharedInstance()
            switch mode {
            case .screenOnly:
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            case .inApp:
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            case .outsideApp:
                try session.setCategory(.playback, mode: .default, options: [])
            }
            try session.setActive(true)
        } catch {
            print("[RadioPlaybackController] Audio session failed: \(error.localizedDescription)")
        }
    }
}

extension Notification.Name {
    static let RadioPlaybackRequiresScreenOnly = Notification.Name("RadioPlaybackRequiresScreenOnly")
}
