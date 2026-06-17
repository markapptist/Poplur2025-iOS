import SwiftUI
import AVFoundation

struct InAppVideoCallView: View {
    let calleeName: String
    let onEnd: () -> Void

    @StateObject private var session = VideoCallSession()
    @State private var phase: CallPhase = .connecting
    @State private var elapsed = 0
    @State private var timerTask: Task<Void, Never>? = nil
    @State private var pipExpanded = false
    @State private var activeFilter: ARFilterManager.ARFilter = .none

    private enum CallPhase { case connecting, connected }

    private static let filters: [ARFilterManager.ARFilter] = [
        .none, .warmth, .cool, .brightening, .vintage, .beautyFilter, .glowingSkin
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            remoteArea
            localPip
            topOverlay
            filterStrip
            bottomControls
        }
        .statusBarHidden()
        .task {
            await session.requestAndStart()
            // Simulate remote connection after 2 seconds
            try? await Task.sleep(for: .seconds(2))
            withAnimation { phase = .connected }
            startTimer()
        }
        .onDisappear {
            timerTask?.cancel()
            session.stop()
        }
    }

    // MARK: - Remote video area

    private var remoteArea: some View {
        ZStack {
            if phase == .connecting {
                VStack(spacing: 20) {
                    Spacer()
                    pulsatingAvatar
                    Text(calleeName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Connecting…")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Spacer()
                }
            } else {
                // Remote stream placeholder — swap for AgoraRtcKit remote view when integrated
                ZStack {
                    Color(red: 0.07, green: 0.07, blue: 0.1)
                    VStack(spacing: 12) {
                        Circle()
                            .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
                            .frame(width: 96, height: 96)
                            .overlay(
                                Text(String(calleeName.prefix(1)).uppercased())
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                        Text(calleeName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Local camera pip

    private var localPip: some View {
        VStack {
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 60)
        .padding(.trailing, 16)
        .overlay(alignment: .topTrailing) {
            Group {
                if session.cameraAuthorized {
                    ZStack {
                        AVPreviewLayerView(session: session.captureSession)
                        filterOverlay(activeFilter)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
                    .onTapGesture { withAnimation(.spring()) { pipExpanded.toggle() } }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(red: 0.12, green: 0.12, blue: 0.16))
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
                }
            }
            .frame(width: pipExpanded ? 160 : 110, height: pipExpanded ? 213 : 146)
            .padding(.top, 60)
            .padding(.trailing, 16)
            .animation(.spring(duration: 0.3), value: pipExpanded)
        }
    }

    // MARK: - Top overlay

    private var topOverlay: some View {
        VStack {
            HStack {
                Spacer()
                if phase == .connected {
                    Text(CallSessionManager.formattedDuration(elapsed))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
            }
            .padding(.top, 56)
            Spacer()
        }
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack {
            Spacer()
            HStack(spacing: 32) {
                VideoCallButton(icon: session.isMuted ? "mic.slash.fill" : "mic.fill",
                                tint: session.isMuted ? .red : controlGray,
                                label: session.isMuted ? "Unmute" : "Mute") {
                    session.toggleMute()
                }

                VideoCallButton(icon: "phone.down.fill", tint: .red, label: "End", size: 72) {
                    timerTask?.cancel()
                    session.stop()
                    onEnd()
                }

                VideoCallButton(icon: "arrow.triangle.2.circlepath.camera.fill",
                                tint: controlGray, label: "Flip") {
                    session.flipCamera()
                }
            }
            .padding(.bottom, 52)
        }
    }

    // MARK: - Filter strip

    private var filterStrip: some View {
        VStack {
            Spacer()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Self.filters) { filter in
                        Button {
                            withAnimation(.spring(duration: 0.25)) { activeFilter = filter }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: filter.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .frame(width: 46, height: 46)
                                    .background(
                                        activeFilter == filter
                                            ? Color.white
                                            : Color.white.opacity(0.15),
                                        in: Circle()
                                    )
                                    .foregroundStyle(activeFilter == filter ? Color.black : Color.white)
                                Text(filter.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial.opacity(0.8))
            .padding(.bottom, 132)
        }
    }

    @ViewBuilder
    private func filterOverlay(_ filter: ARFilterManager.ARFilter) -> some View {
        switch filter {
        case .none:         EmptyView()
        case .warmth:       Color.orange.opacity(0.16).blendMode(.overlay)
        case .cool:         Color.blue.opacity(0.14).blendMode(.overlay)
        case .brightening:  Color.white.opacity(0.10).blendMode(.screen)
        case .beautyFilter: Color.pink.opacity(0.10).blendMode(.screen)
        case .glowingSkin:  Color.yellow.opacity(0.12).blendMode(.screen)
        case .vintage:      Color(red: 0.6, green: 0.4, blue: 0.1).opacity(0.22).blendMode(.multiply)
        case .faceSmoothing: Color.white.opacity(0.05).blendMode(.screen)
        case .sharpen:      EmptyView()
        }
    }

    // MARK: - Helpers

    private var controlGray: Color { Color(red: 0.22, green: 0.22, blue: 0.26) }

    private var pulsatingAvatar: some View {
        ZStack {
            ForEach(0..<3) { i in
                PulseRing(index: i)
            }
            Circle()
                .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
                .frame(width: 96, height: 96)
            Text(String(calleeName.prefix(1)).uppercased())
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
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

// MARK: - Supporting views

private struct PulseRing: View {
    let index: Int
    @State private var scale: CGFloat = 1

    var body: some View {
        Circle()
            .stroke(Color.white.opacity(0.15 - Double(index) * 0.04), lineWidth: 1.5)
            .frame(width: 96 + CGFloat(index + 1) * 36,
                   height: 96 + CGFloat(index + 1) * 36)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(
                    .easeOut(duration: 1.6)
                    .repeatForever(autoreverses: false)
                    .delay(Double(index) * 0.5)
                ) { scale = 1.35 }
            }
    }
}

private struct VideoCallButton: View {
    let icon: String
    let tint: Color
    let label: String
    var size: CGFloat = 58
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: size == 72 ? 28 : 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(tint, in: Circle())
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .buttonStyle(.plain)
    }
}
