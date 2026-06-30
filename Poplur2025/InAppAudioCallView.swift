import SwiftUI

struct InAppAudioCallView: View {
    let calleeName: String
    let onEnd: () -> Void

    @State private var phase: AudioCallPhase = .ringing
    @State private var elapsed = 0
    @State private var isMuted = false
    @State private var isSpeaker = false
    @State private var timerTask: Task<Void, Never>? = nil
    @State private var pulseScale: CGFloat = 1

    private enum AudioCallPhase { case ringing, connected }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.06, blue: 0.12), Color.black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 80)

                statusLabel
                Spacer().frame(height: 36)
                avatar
                Spacer().frame(height: 24)

                Text(calleeName)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()
                controls
                Spacer().frame(height: 52)
            }
        }
        .statusBarHidden()
        .task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { phase = .connected }
            startTimer()
        }
        .onDisappear { timerTask?.cancel() }
    }

    // MARK: - Subviews

    private var statusLabel: some View {
        Group {
            switch phase {
            case .ringing:
                Text("Calling…")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            case .connected:
                Text(CallSessionManager.formattedDuration(elapsed))
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private var avatar: some View {
        ZStack {
            if phase == .ringing {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 2)
                    .frame(width: 148, height: 148)
                    .scaleEffect(pulseScale)
                    .opacity(2 - pulseScale)
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                            pulseScale = 1.5
                        }
                    }
            }

            Circle()
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .frame(width: 108, height: 108)

            Text(String(calleeName.prefix(1)).uppercased())
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 1)
                .frame(width: 108, height: 108)
        )
    }

    private var controls: some View {
        VStack(spacing: 28) {
            HStack(spacing: 40) {
                AudioCallButton(
                    icon: isMuted ? "mic.slash.fill" : "mic.fill",
                    label: isMuted ? "Unmute" : "Mute",
                    active: isMuted
                ) { isMuted.toggle() }

                AudioCallButton(
                    icon: "phone.down.fill",
                    label: "End",
                    tint: .red,
                    size: 72
                ) {
                    timerTask?.cancel()
                    onEnd()
                }

                AudioCallButton(
                    icon: isSpeaker ? "speaker.wave.3.fill" : "speaker.fill",
                    label: "Speaker",
                    active: isSpeaker
                ) { isSpeaker.toggle() }
            }
        }
    }

    private func startTimer() {
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsed += 1
            }
        }
    }
}

private struct AudioCallButton: View {
    let icon: String
    let label: String
    var tint: Color = Color(red: 0.2, green: 0.2, blue: 0.25)
    var size: CGFloat = 60
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .poplurIconShader()
                    .font(.system(size: size == 72 ? 28 : 22, weight: .semibold))
                    .foregroundStyle(active ? Color.black : Color.white)
                    .frame(width: size, height: size)
                    .background(active ? Color(red: 0.9, green: 0.9, blue: 0.92) : tint, in: Circle())
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }
}
