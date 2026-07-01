import SwiftUI
import AVFoundation

/// Audio-only Poplur host bumper. It intentionally renders nothing so the AI
/// speaks over the feed instead of taking users to a separate screen.
struct FeedBumperView: View {
    let payload: BumperPayload
    let onFinished: () -> Void

    @State private var player: AVAudioPlayer?
    @State private var speechSynthesizer: AVSpeechSynthesizer?
    @State private var waveTimer: Timer?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        .onAppear { setupPlayer() }
        .onDisappear { teardown() }
    }

    private func setupPlayer() {
        PoplurEQSync.shared.begin(.feedBumper)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { }

        if let audioData = payload.audioData,
           let p = try? AVAudioPlayer(data: audioData) {
            player = p
            p.volume = 1.0
            p.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + p.duration + 0.3) {
                finish()
            }
        } else {
            speakFallbackScript()
        }

    }

    private func speakFallbackScript() {
        let synth = AVSpeechSynthesizer()
        speechSynthesizer = synth

        let utterance = AVSpeechUtterance(string: payload.script)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.46
        utterance.pitchMultiplier = 1.02
        utterance.volume = 1.0
        synth.speak(utterance)

        let estimatedDuration = max(3.0, min(12.0, Double(payload.script.split(separator: " ").count) / 2.5))
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration + 0.35) {
            finish()
        }
    }

    private func teardown() {
        waveTimer?.invalidate()
        waveTimer = nil
        player?.stop()
        player = nil
        speechSynthesizer?.stopSpeaking(at: .immediate)
        speechSynthesizer = nil
        PoplurEQSync.shared.end(.feedBumper)
    }

    private func finish() {
        teardown()
        onFinished()
    }
}
