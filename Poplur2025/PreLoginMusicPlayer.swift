import SwiftUI
import AVFoundation

/// Keeps the pre-login flow on the same audio treatment as Map: a local radio stream mixed
/// with the Poplur AI host. Mute preference persists across launches via UserDefaults.
@MainActor
final class PreLoginMusicPlayer: ObservableObject {
    @Published var isMuted: Bool {
        didSet {
            guard oldValue != isMuted else { return }
            UserDefaults.standard.set(isMuted, forKey: Self.mutedDefaultsKey)
            applyMuteState()
        }
    }

    @Published private(set) var currentChannelTitle = "CBC Radio One Toronto"
    @Published private(set) var currentAIScript = "Poplur AI is mixing your local radio."

    private var player: AVPlayer?
    private static let mutedDefaultsKey = "poplur_prelogin_music_muted"
    private static let radioURL = URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/CBC_R1_TOR_H.mp3")!
    private static let channelTitle = "CBC Radio One Toronto"
    private static let aiStatusText = "Poplur AI is mixing your local radio."
    private static let openingScript = "Welcome to Poplur Radio, live from your area. Poplur AI is mixing the local radio with what is happening around you. Stay with us."
    private static let playbackVolume: Float = 0.42

    init() {
        isMuted = UserDefaults.standard.bool(forKey: Self.mutedDefaultsKey)
    }

    /// Starts (or resumes) looping playback. Safe to call repeatedly.
    func start() {
        guard !ProcessInfo.processInfo.isRunningInPreviews, !isMuted else { return }
        if player != nil {
            applyMuteState()
            return
        }
        do {
            // .playback keeps the intentional onboarding audio audible with the ring/silent
            // switch on; .mixWithOthers lets the local radio and Poplur AI share the session.
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            let newPlayer = AVPlayer(url: Self.radioURL)
            newPlayer.volume = Self.playbackVolume
            player = newPlayer
            applyMuteState()
        } catch {
            print("[PreLoginMusicPlayer] Failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.pause()
        player = nil
        PoplurMapRadioHost.shared.stop()
    }

    private func applyMuteState() {
        if isMuted { stop(); return }
        guard let player else { start(); return }
        if !isMuted {
            player.volume = Self.playbackVolume
            player.play()
            if !PoplurMapRadioHost.shared.isLive {
                PoplurMapRadioHost.shared.speak(
                    Self.openingScript,
                    cityName: "your area",
                    stopTitle: "Welcome",
                    stationName: Self.channelTitle
                )
            }
        }
    }

}

private extension ProcessInfo {
    var isRunningInPreviews: Bool {
        environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }
}

/// Brand-styled mute toggle — white capsule, pink accent icon, matching the Sign In / Sign Up
/// button treatment on the Welcome screen. Placed in the top-left corner of the pre-login area.
struct PoplurMuteButton: View {
    @ObservedObject var music: PreLoginMusicPlayer

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred(intensity: 0.4)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                music.isMuted.toggle()
            }
        } label: {
            Image(systemName: music.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(DS.Color.accent)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(music.isMuted ? "Unmute local radio" : "Mute local radio")
    }
}
