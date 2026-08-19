import SwiftUI
import AVFoundation

struct InAppVideoCallView: View {
    let calleeName: String
    let onEnd: () -> Void

    @StateObject private var session = VideoCallSession()
    @StateObject private var filterManager = ARFilterManager()
    @State private var phase: CallPhase = .connecting
    @State private var elapsed = 0
    @State private var timerTask: Task<Void, Never>? = nil
    @State private var pipExpanded = false
    @State private var activeFilter: ARFilterManager.ARFilter = .none

    private enum CallPhase { case connecting, connected }

    // NOT allCases: the fifteen web-rail ids added to ARFilter have no bundled
    // thumbnail or tint here, so they would show as blank tiles on this rail.
    private static let filters: [ARFilterManager.ARFilter] = ARFilterManager.ARFilter.nativePickerFilters

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
            filterManager.activeFilter = .none
            await session.requestAndStart()
            try? await Task.sleep(for: .seconds(2))
            withAnimation { phase = .connected }
            startTimer()
        }
        .onChange(of: activeFilter) { _, newFilter in
            filterManager.activeFilter = newFilter
        }
        .onDisappear {
            timerTask?.cancel()
            filterManager.activeFilter = .none
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
                RemoteParticipantVideo(calleeName: calleeName)
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
                            .scaleEffect(x: session.isFrontCamera ? -1 : 1, y: 1)
                        VideoCallAREffectOverlay(filter: activeFilter)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack {
                            Spacer()
                            HStack {
                                Text(activeFilter == .none ? "You" : activeFilter.displayName)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.46), in: Capsule())
                                Spacer()
                            }
                            .padding(8)
                        }
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
                            .poplurIconShader()
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
                                    .poplurIconShader()
                                    .font(.system(size: 18, weight: .semibold))
                                    .frame(width: 46, height: 46)
                                    .background(
                                        activeFilter == filter
                                            ? Color.white
                                            : Color.white.opacity(0.15),
                                        in: Circle()
                                    )
                                    .foregroundStyle(activeFilter == filter ? Color.black : Color.white)
                                Text(filter.displayName)
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
            .opacity(phase == .connected ? 1 : 0)
            .allowsHitTesting(phase == .connected)
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

private struct RemoteParticipantVideo: View {
    let calleeName: String
    @State private var drift: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.06, blue: 0.08),
                        Color(red: 0.12, green: 0.09, blue: 0.16),
                        Color(red: 0.03, green: 0.10, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color(red: 0.22, green: 0.34, blue: 0.98).opacity(0.28))
                    .frame(width: proxy.size.width * 0.86)
                    .blur(radius: 70)
                    .offset(x: -proxy.size.width * 0.28 + drift * 34, y: -proxy.size.height * 0.18)

                Circle()
                    .fill(Color(red: 0.96, green: 0.38, blue: 0.58).opacity(0.18))
                    .frame(width: proxy.size.width * 0.7)
                    .blur(radius: 90)
                    .offset(x: proxy.size.width * 0.24 - drift * 28, y: proxy.size.height * 0.22)

                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 46, style: .continuous)
                            .fill(.white.opacity(0.08))
                            .frame(width: 172, height: 214)
                            .overlay(
                                RoundedRectangle(cornerRadius: 46, style: .continuous)
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            )

                        Circle()
                            .fill(.white.opacity(0.12))
                            .frame(width: 96, height: 96)
                            .overlay(
                                Text(String(calleeName.prefix(1)).uppercased())
                                    .font(.system(size: 42, weight: .black))
                                    .foregroundStyle(.white)
                            )
                            .offset(y: -18)

                        VStack(spacing: 8) {
                            Spacer()
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.white.opacity(0.16))
                                .frame(width: 112, height: 26)
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.white.opacity(0.10))
                                .frame(width: 86, height: 20)
                        }
                        .padding(.bottom, 28)
                    }

                    Text(calleeName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)

                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color(red: 0.38, green: 1, blue: 0.47))
                            .frame(width: 8, height: 8)
                        Text("Live video")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.74))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.28), in: Capsule())
                }
            }
            .task {
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                    drift = 1
                }
            }
        }
    }
}

private struct VideoCallAREffectOverlay: View {
    let filter: ARFilterManager.ARFilter
    @State private var shimmer = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                tint(for: filter)

                if filter != .none {
                    RoundedRectangle(cornerRadius: proxy.size.width * 0.36, style: .continuous)
                        .stroke(.white.opacity(filter == .sharpen ? 0.42 : 0.16), lineWidth: filter == .sharpen ? 1.5 : 1)
                        .frame(width: proxy.size.width * 0.54, height: proxy.size.height * 0.42)
                        .offset(y: -proxy.size.height * 0.08)
                }

                switch filter {
                case .none:
                    EmptyView()
                case .faceSmoothing:
                    Color.white.opacity(0.045).blendMode(.screen)
                case .beautyFilter:
                    cheekGlow(proxy: proxy)
                    sparkleField(proxy: proxy, tint: .pink)
                case .brightening:
                    Color.white.opacity(0.13).blendMode(.screen)
                case .glowingSkin:
                    RadialGradient(
                        colors: [.yellow.opacity(0.24), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.74
                    )
                    .blendMode(.screen)
                    sparkleField(proxy: proxy, tint: .yellow)
                case .sharpen:
                    sharpenGrid(proxy: proxy)
                case .warmth, .cool, .vintage:
                    EmptyView()
                default:
                    // Web-rail ids share the enum but never reach this rail —
                    // `filters` above is nativePickerFilters, not allCases.
                    EmptyView()
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func tint(for filter: ARFilterManager.ARFilter) -> some View {
        switch filter {
        case .none:
            EmptyView()
        case .warmth:
            Color.orange.opacity(0.18).blendMode(.overlay)
        case .cool:
            Color.blue.opacity(0.16).blendMode(.overlay)
        case .brightening:
            Color.white.opacity(0.10).blendMode(.screen)
        case .beautyFilter:
            Color.pink.opacity(0.10).blendMode(.screen)
        case .glowingSkin:
            Color.yellow.opacity(0.12).blendMode(.screen)
        case .vintage:
            Color(red: 0.6, green: 0.4, blue: 0.1).opacity(0.22).blendMode(.multiply)
        case .faceSmoothing:
            Color.white.opacity(0.05).blendMode(.screen)
        case .sharpen:
            EmptyView()
        default:
            // Web-rail ids never reach this rail (see `filters` above), but the
            // switch has to stay total now that they share the enum.
            EmptyView()
        }
    }

    private func cheekGlow(proxy: GeometryProxy) -> some View {
        ZStack {
            Circle()
                .fill(Color.pink.opacity(0.22))
                .frame(width: proxy.size.width * 0.16, height: proxy.size.width * 0.16)
                .blur(radius: 8)
                .offset(x: -proxy.size.width * 0.17, y: proxy.size.height * 0.04)
            Circle()
                .fill(Color.pink.opacity(0.22))
                .frame(width: proxy.size.width * 0.16, height: proxy.size.width * 0.16)
                .blur(radius: 8)
                .offset(x: proxy.size.width * 0.17, y: proxy.size.height * 0.04)
        }
    }

    private func sparkleField(proxy: GeometryProxy, tint: Color) -> some View {
        ZStack {
            ForEach(0..<5) { index in
                SparkleShape()
                    .fill(tint.opacity(shimmer ? 0.95 : 0.42))
                    .frame(width: 9 + CGFloat(index % 2) * 4, height: 9 + CGFloat(index % 2) * 4)
                    .offset(
                        x: CGFloat([-0.28, 0.24, -0.08, 0.34, -0.34][index]) * proxy.size.width,
                        y: CGFloat([-0.24, -0.18, 0.18, 0.12, 0.02][index]) * proxy.size.height
                    )
            }
        }
    }

    private func sharpenGrid(proxy: GeometryProxy) -> some View {
        Path { path in
            let stepX = proxy.size.width / 4
            let stepY = proxy.size.height / 5
            for index in 1..<4 {
                let x = CGFloat(index) * stepX
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: proxy.size.height))
            }
            for index in 1..<5 {
                let y = CGFloat(index) * stepY
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: proxy.size.width, y: y))
            }
        }
        .stroke(.white.opacity(0.12), lineWidth: 0.7)
    }
}

private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.midY - rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.midY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.midY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.midY - rect.height * 0.18))
        path.closeSubpath()
        return path
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
                    .poplurIconShader()
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
