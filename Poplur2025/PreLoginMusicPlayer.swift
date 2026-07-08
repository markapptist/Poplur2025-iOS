import SwiftUI
import AVFoundation

/// Loops a single bundled ambient track behind the whole pre-login flow (Welcome, Login,
/// Sign Up). Mute preference persists across launches via UserDefaults.
///
/// NOTE: expects a bundled audio file named `PreLoginMusicPlayer.assetName` (mp3). Add that
/// asset to the app target — this player logs a warning and silently no-ops without it.
@MainActor
final class PreLoginMusicPlayer: ObservableObject {
    @Published var isMuted: Bool {
        didSet {
            guard oldValue != isMuted else { return }
            UserDefaults.standard.set(isMuted, forKey: Self.mutedDefaultsKey)
            applyMuteState()
        }
    }

    private var player: AVAudioPlayer?
    private static let mutedDefaultsKey = "poplur_prelogin_music_muted"
    private static let assetName = "prelogin_ambient"
    private static let playbackVolume: Float = 0.35

    init() {
        isMuted = UserDefaults.standard.bool(forKey: Self.mutedDefaultsKey)
    }

    /// Starts (or resumes) looping playback. Safe to call repeatedly.
    func start() {
        guard !ProcessInfo.processInfo.isRunningInPreviews else { return }
        if player != nil {
            applyMuteState()
            return
        }
        guard let url = Bundle.main.url(forResource: Self.assetName, withExtension: "mp3") else {
            print("[PreLoginMusicPlayer] Missing bundled asset \(Self.assetName).mp3 — background music disabled.")
            return
        }
        do {
            // .playback so the pre-login music + AI voice are audible even when the ring/silent
            // switch is on (the onboarding audio is intentional); .mixWithOthers keeps it playing
            // over any other audio the user has going and alongside the AI-guide speech synth.
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = -1
            newPlayer.volume = Self.playbackVolume
            newPlayer.prepareToPlay()
            player = newPlayer
            applyMuteState()
        } catch {
            print("[PreLoginMusicPlayer] Failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private func applyMuteState() {
        guard let player else { return }
        if isMuted {
            player.pause()
        } else if !player.isPlaying {
            player.play()
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
        .accessibilityLabel(music.isMuted ? "Unmute background music" : "Mute background music")
    }
}
