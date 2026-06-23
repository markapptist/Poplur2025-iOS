import SwiftUI
import AVFoundation

private let brandPink = Color(red: 1.0, green: 45/255, blue: 150/255)
private let brandDark = Color(red: 0.05, green: 0.0, blue: 0.06)

/// Full-screen Poplur-branded "Up Next" screen with ElevenLabs voice-over.
/// Appears before each feed post; auto-advances when audio finishes.
struct FeedBumperView: View {
    let audioData: Data
    let onFinished: () -> Void

    @State private var player: AVAudioPlayer?
    @State private var showSkip = false
    @State private var barHeights: [CGFloat] = Array(repeating: 0.3, count: 7)
    @State private var waveTimer: Timer?
    @State private var logoPulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            brandDark.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Text("POPLUR")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(brandPink)
                        .tracking(3)
                    Spacer()
                    Text("UP NEXT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .tracking(2)
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)

                Spacer()

                // Center identity
                VStack(spacing: 32) {
                    // Actual Poplur logo
                    ZStack {
                        Circle()
                            .fill(brandPink.opacity(0.08))
                            .frame(width: 148, height: 148)
                            .scaleEffect(logoPulse)
                        Circle()
                            .strokeBorder(brandPink.opacity(0.18), lineWidth: 1)
                            .frame(width: 148, height: 148)
                            .scaleEffect(logoPulse)
                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    Text("UP NEXT")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .tracking(5)

                    // Audio waveform equalizer bars
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(0..<7, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(brandPink.opacity(0.6 + Double(barHeights[i]) * 0.4))
                                .frame(width: 4, height: 10 + barHeights[i] * 46)
                                .animation(.easeInOut(duration: 0.18), value: barHeights[i])
                        }
                    }
                    .frame(height: 56)
                    .opacity(player?.isPlaying == true ? 1 : 0.25)
                }

                Spacer()

                // Bottom row
                HStack {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(brandPink)
                            .frame(width: 6, height: 6)
                        Text("POPLUR")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(brandPink)
                            .tracking(1.5)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(brandPink.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    if showSkip {
                        Button { finish() } label: {
                            HStack(spacing: 6) {
                                Text("SKIP")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .tracking(1.5)
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { teardown() }
    }

    private func setupPlayer() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { }

        guard let p = try? AVAudioPlayer(data: audioData) else {
            finish(); return
        }
        player = p
        p.play()
        animateBars()
        animateLogo()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.3)) { showSkip = true }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + p.duration + 0.3) {
            finish()
        }
    }

    private func animateBars() {
        waveTimer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { _ in
            for i in 0..<barHeights.count {
                barHeights[i] = CGFloat.random(in: 0.1...1.0)
            }
        }
    }

    private func animateLogo() {
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            logoPulse = 1.06
        }
    }

    private func teardown() {
        waveTimer?.invalidate()
        waveTimer = nil
        player?.stop()
        player = nil
    }

    private func finish() {
        teardown()
        onFinished()
    }
}
