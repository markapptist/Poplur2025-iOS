import SwiftUI
import AVKit
import CoreLocation
import CoreImage

// MARK: - TV analysis state

private enum TVState {
    case idle
    case analyzing
    case ready(TVStyleMetadata)
    case failed
}

// MARK: - Preview overlay

/// Preview overlay shown after capturing photo or video.
/// Runs AI broadcast analysis before posting, adding TV-style channel detection and overlays.
struct CapturePreviewOverlay: View {
    let image: UIImage?
    let videoURL: URL?
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var flowManager = CaptureFlowManager.shared

    @State private var isPosting = false
    @State private var tvState: TVState = .idle
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Media
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
            } else if let videoURL {
                CaptureVideoPlayer(url: videoURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
            }

            // Bottom controls
            VStack {
                Spacer()
                bottomControls
            }
        }
        .onAppear {
            print("📸 [CapturePreview] Appeared - Flow: \(flowManager.currentFlow.map { flow -> String in flow.isMapFirst ? "Map→Camera" : flow.isCameraFirst ? "Camera→Map" : "None" } ?? "None")")
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Scanning overlay

    private var scanningOverlay: some View {
        ZStack {
            Color.black.opacity(0.54)
            VStack(spacing: 18) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(Color.red.opacity(0.55 - Double(i) * 0.14), lineWidth: 1.5)
                            .frame(width: 40 + CGFloat(i) * 24,
                                   height: 40 + CGFloat(i) * 24)
                            .scaleEffect(pulseScale)
                    }
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulseScale = 1.18
                    }
                }

                Text("SCANNING BROADCAST")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .tracking(2.8)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Bottom controls

    @ViewBuilder
    private var bottomControls: some View {
        switch tvState {

        case .idle:
            idleButtons

        case .analyzing:
            // Keep UI locked while scanning; user can still retake
            HStack(spacing: 24) {
                Button { close() } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Retake")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 48)

        case .ready(let meta):
            readyButtons(meta: meta)

        case .failed:
            failedButtons
        }
    }

    private var idleButtons: some View {
        HStack(spacing: 24) {
            Button { close() } label: {
                VStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(.white)
                    Text("Retake")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            Spacer()
            Button { continueFromPreview() } label: {
                VStack(spacing: 8) {
                    Image(systemName: flowManager.currentFlow?.isMapFirst == true ? "slider.horizontal.3" : "mappin.and.ellipse")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Color(red: 1, green: 0.22, blue: 0.22))
                    Text(flowManager.currentFlow?.isMapFirst == true ? "Filters" : "Location")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.bottom, 48)
    }

    private func readyButtons(meta: TVStyleMetadata) -> some View {
        VStack(spacing: 14) {
            // Channel detection badge
            HStack(spacing: 10) {
                Text(channelEmoji(for: meta.channel))
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.broadcastName)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .tracking(0.8)
                    Text(meta.adConcept)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 18))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.black.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 18)

            // Action buttons
            HStack(spacing: 24) {
                Button { close() } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Retake")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .disabled(isPosting)

                Spacer()

                Button { post() } label: {
                    VStack(spacing: 8) {
                        if isPosting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.4)
                                .frame(width: 40, height: 40)
                        } else {
                            Image(systemName: "dot.radiowaves.right")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(Color(red: 1, green: 0.22, blue: 0.22))
                        }
                        Text(isPosting ? "Broadcasting..." : "Broadcast Now")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(isPosting)
            }
            .padding(.horizontal, 48)
        }
        .padding(.bottom, 48)
    }

    private var failedButtons: some View {
        HStack(spacing: 24) {
            Button { close() } label: {
                VStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(.white)
                    Text("Retake")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            Spacer()
            Button { post() } label: {
                VStack(spacing: 8) {
                    if isPosting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(.green)
                    }
                    Text(isPosting ? "Posting..." : "Post Anyway")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .disabled(isPosting)
        }
        .padding(.horizontal, 48)
        .padding(.bottom, 48)
    }

    // MARK: - Actions

    private func close() {
        if let onDismiss { onDismiss() } else { dismiss() }
    }

    private func startTVAnalysis() {
        tvState = .analyzing
        Task {
            do {
                let meta: TVStyleMetadata
                if let image {
                    meta = try await TVStyleAnalyzer.shared.analyze(image: image)
                } else if let videoURL {
                    meta = try await TVStyleAnalyzer.shared.analyze(videoURL: videoURL)
                } else {
                    tvState = .failed
                    return
                }
                await MainActor.run { tvState = .ready(meta) }
            } catch {
                print("📡 [TVAnalyzer] Failed: \(error)")
                await MainActor.run { tvState = .failed }
            }
        }
    }

    private func post() {
        guard !isPosting else { return }
        isPosting = true
        if let flow = flowManager.currentFlow, flow.isMapFirst {
            handleMapToCameraFlow()
        } else {
            handleCameraToMapFlow()
        }
    }

    private func continueFromPreview() {
        if let flow = flowManager.currentFlow, flow.isMapFirst, let coordinate = flow.preselectedCoordinate {
            flowManager.capturedImage = image
            flowManager.capturedVideoURL = videoURL
            flowManager.confirmLocation(coordinate)
            close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NotificationCenter.default.post(
                    name: .showPostCaptureEditor,
                    object: nil,
                    userInfo: [
                        "image": image as Any,
                        "videoURL": videoURL as Any,
                        "latitude": coordinate.latitude,
                        "longitude": coordinate.longitude
                    ]
                )
            }
        } else {
            handleCameraToMapFlow()
        }
    }

    private func handleMapToCameraFlow() {
        guard let coordinate = flowManager.currentFlow?.preselectedCoordinate else {
            isPosting = false
            return
        }
        NotificationCenter.default.post(
            name: Notification.Name("SetCameraCoordinate"), object: nil,
            userInfo: ["latitude": coordinate.latitude, "longitude": coordinate.longitude])
        if let image {
            NotificationCenter.default.post(name: Notification.Name("UploadImageToCurrentCoordinate"), object: image)
        } else if let videoURL {
            NotificationCenter.default.post(name: Notification.Name("UploadVideoToCurrentCoordinate"), object: videoURL)
        }
        flowManager.completeFlow(finalCoordinate: coordinate)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("SwitchToProfileTab"), object: nil)
            }
        }
    }

    private func handleCameraToMapFlow() {
        flowManager.startCameraToMapFlow(image: image, videoURL: videoURL)
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: Notification.Name("OpenMapToSelectPostLocation"), object: nil,
                userInfo: ["image": image as Any, "videoURL": videoURL as Any])
        }
    }

    private func channelEmoji(for channel: String) -> String {
        switch channel {
        case "food": return "🍔"; case "fitness": return "💪"; case "sports": return "⚽"
        case "beauty": return "💄"; case "fashion": return "👗"; case "music": return "🎵"
        case "tech": return "💻"; case "news": return "📺"; case "city": return "🏙️"
        case "entertainment": return "🎬"; default: return "📡"
        }
    }
}

// MARK: - Video player (unchanged)

private struct CaptureVideoPlayer: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        configure(view, context: context)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        guard context.coordinator.url != url else {
            uiView.playerLayer.videoGravity = .resizeAspectFill
            uiView.setNeedsLayout()
            return
        }
        configure(uiView, context: context)
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.observer.map(NotificationCenter.default.removeObserver)
        coordinator.statusObserver?.invalidate()
        coordinator.player?.pause()
        uiView.playerLayer.player = nil
        coordinator.player = nil
        coordinator.observer = nil
        coordinator.statusObserver = nil
        coordinator.url = nil
    }

    private func configure(_ view: PlayerContainerView, context: Context) {
        context.coordinator.observer.map(NotificationCenter.default.removeObserver)
        context.coordinator.statusObserver?.invalidate()
        context.coordinator.player?.pause()
        let item   = AVPlayerItem(asset: AVURLAsset(url: url))
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.setNeedsLayout()
        context.coordinator.player = player
        context.coordinator.url    = url
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak player] _ in
            player?.seek(to: .zero); player?.play()
        }
        context.coordinator.statusObserver = item.observe(\.status, options: [.initial, .new]) { item, _ in
            DispatchQueue.main.async { [weak player] in
                if item.status == .readyToPlay { player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero); player?.play() }
            }
        }
    }

    final class Coordinator {
        var player: AVPlayer?; var url: URL?
        var observer: NSObjectProtocol?; var statusObserver: NSKeyValueObservation?
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .black; playerLayer.videoGravity = .resizeAspectFill }
        required init?(coder: NSCoder) { super.init(coder: coder); backgroundColor = .black; playerLayer.videoGravity = .resizeAspectFill }
        override func layoutSubviews() { super.layoutSubviews(); playerLayer.frame = bounds; playerLayer.videoGravity = .resizeAspectFill }
    }
}

// MARK: - Post-capture composer

struct PostCaptureComposerOverlay: View {
    let image: UIImage?
    let videoURL: URL?
    let coordinate: CLLocationCoordinate2D
    var onDismiss: (() -> Void)? = nil

    private enum Step {
        case filters
        case channel
        case adPrompt
        case adPreview(UIImage)
    }

    @StateObject private var flowManager = CaptureFlowManager.shared
    @State private var step: Step = .filters
    @State private var selectedFilter: PostCaptureFilter = .original
    @State private var selectedChannel: PostCaptureChannel = PostCaptureChannel.all.first!
    @State private var videoTrimSeconds: Double = 10
    @State private var maxVideoTrimSeconds: Double = 10
    @State private var isPosting = false
    @State private var statusText = "AI feed service is preparing your Poplur TV post..."
    @State private var whoText: String = ""
    @State private var whatText: String = ""
    @State private var whereText: String = ""
    @State private var whyText: String = ""
    @State private var generatedMeta: TVStyleMetadata? = nil
    @State private var isGenerating = false
    @State private var generationError: String? = nil
    @State private var adPulseScale: CGFloat = 1.0

    private var isVideo: Bool { videoURL != nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if case .adPreview(let adImage) = step {
                Image(uiImage: adImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
                if let meta = generatedMeta {
                    TVOverlayView(metadata: meta)
                }
            } else {
                mediaPreview
                    .ignoresSafeArea()
            }

            VStack {
                header
                Spacer()
                switch step {
                case .filters:
                    filterPanel
                case .channel:
                    channelPanel
                case .adPrompt:
                    adPromptPanel
                case .adPreview(let adImage):
                    adPreviewControls(adImage: adImage)
                }
            }

            if isPosting || isGenerating {
                generatingOrPostingOverlay
            }
        }
        .onAppear(perform: configureVideoDuration)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if let image {
            Image(uiImage: image.applyingPostCaptureFilter(selectedFilter))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else if let videoURL {
            ZStack {
                CaptureVideoPlayer(url: videoURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .saturation(selectedFilter == .noir ? 0 : 1)
                    .contrast(selectedFilter == .pop || selectedFilter == .chrome ? 1.18 : 1)
                selectedFilter.previewOverlay
            }
        }
    }

    private var headerStepTitle: String {
        switch step {
        case .filters:  return "Edit capture"
        case .channel:  return "Choose channel"
        case .adPrompt: return "Describe your ad"
        case .adPreview: return "Your TV ad"
        }
    }

    private var headerIsBack: Bool {
        if case .filters = step { return false }
        return true
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                switch step {
                case .filters:
                    flowManager.cancelFlow()
                    onDismiss?()
                case .channel:
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .filters }
                case .adPrompt:
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .channel }
                case .adPreview:
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .adPrompt }
                }
            } label: {
                Image(systemName: headerIsBack ? "chevron.left" : "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.58), in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(headerStepTitle)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(String(format: "%.4f", coordinate.latitude)), \(String(format: "%.4f", coordinate.longitude))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.72), .black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private var filterPanel: some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PostCaptureFilter.allCases) { filter in
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                selectedFilter = filter
                            }
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(filter.swatch)
                                    if selectedFilter == filter {
                                        Circle()
                                            .stroke(.white, lineWidth: 3)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 15, weight: .black))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 48, height: 48)

                                Text(filter.displayName)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(selectedFilter == filter ? 1 : 0.72))
                            }
                            .frame(width: 66)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }

            if isVideo {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Trim")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(Int(videoTrimSeconds.rounded()))s")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    Slider(value: $videoTrimSeconds, in: 1...max(maxVideoTrimSeconds, 1), step: 1)
                        .tint(Color(red: 1, green: 0.22, blue: 0.22))
                }
                .padding(.horizontal, 18)
            }

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .channel }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "tv.fill")
                    Text("Pick Channel")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
        }
        .padding(.top, 18)
        .padding(.bottom, 28)
        .background(.black.opacity(0.78))
    }

    private var channelPanel: some View {
        VStack(spacing: 14) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(PostCaptureChannel.all) { channel in
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                                selectedChannel = channel
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(channel.emoji)
                                    .font(.system(size: 27))
                                    .frame(width: 42)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("CH \(channel.number)  \(channel.title)")
                                        .font(.system(size: 14, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text(channel.subtitle)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.62))
                                        .lineLimit(1)
                                }
                                Spacer()
                                if selectedChannel == channel {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(Color(red: 0.30, green: 1, blue: 0.34))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                selectedChannel == channel
                                ? Color.white.opacity(0.16)
                                : Color.white.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
            .frame(maxHeight: 360)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .adPrompt }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                    Text("Create Ad")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
        }
        .padding(.top, 16)
        .padding(.bottom, 28)
        .background(.black.opacity(0.84))
    }

    private var generatingOrPostingOverlay: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(
                                (isGenerating ? Color.yellow : Color.white).opacity(0.5 - Double(i) * 0.12),
                                lineWidth: 1.5
                            )
                            .frame(width: 48 + CGFloat(i) * 22, height: 48 + CGFloat(i) * 22)
                            .scaleEffect(adPulseScale)
                    }
                    Image(systemName: isGenerating ? "sparkles" : "dot.radiowaves.right")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(isGenerating ? .yellow : .white)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        adPulseScale = 1.2
                    }
                }

                Text(isGenerating ? "Creating your Poplur TV ad…" : statusText)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)

                Text(isGenerating
                     ? "AI is generating a custom \(selectedChannel.emoji) \(selectedChannel.title) ad from your content."
                     : "Your ad will be added to your profile.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.68))
                    .padding(.horizontal, 28)
            }
        }
    }

    // MARK: - Ad prompt panel

    private var adPromptPanel: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tell AI about your post")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Answer any or all — AI uses these to generate your \(selectedChannel.emoji) \(selectedChannel.title) ad.")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)

            VStack(spacing: 10) {
                adQuestionField(emoji: "👤", label: "Who", placeholder: "Who is this about?", text: $whoText)
                adQuestionField(emoji: "⚡️", label: "What", placeholder: "What is happening?", text: $whatText)
                adQuestionField(emoji: "📍", label: "Where", placeholder: "Where does this take place?", text: $whereText)
                adQuestionField(emoji: "💡", label: "Why", placeholder: "Why does this matter?", text: $whyText)
            }
            .padding(.horizontal, 18)

            if let err = generationError {
                Text(err)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                    .padding(.horizontal, 18)
            }

            Button { generateAd() } label: {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                    Text("Generate Ad")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(adQuestionsEmpty ? Color.gray.opacity(0.6) : Color.white, in: Capsule())
            }
            .disabled(adQuestionsEmpty)
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
        }
        .padding(.top, 18)
        .padding(.bottom, 28)
        .background(.black.opacity(0.84))
    }

    private var adQuestionsEmpty: Bool {
        [whoText, whatText, whereText, whyText]
            .allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func adQuestionField(emoji: String, label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 20))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.50))
                    .tracking(1.2)
                    .textCase(.uppercase)
                TextField(placeholder, text: text)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .submitLabel(.next)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Ad preview controls

    private func adPreviewControls(adImage: UIImage) -> some View {
        VStack(spacing: 14) {
            if let meta = generatedMeta {
                HStack(spacing: 10) {
                    Text(adChannelEmoji(meta.channel))
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meta.broadcastName)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .tracking(0.8)
                        Text(meta.adConcept)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.70))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 16))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 18)
            }

            HStack(spacing: 24) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .adPrompt }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Redo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .disabled(isPosting)

                Spacer()

                Button { broadcastAd(adImage) } label: {
                    VStack(spacing: 8) {
                        if isPosting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.4)
                                .frame(width: 40, height: 40)
                        } else {
                            Image(systemName: "dot.radiowaves.right")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(Color(red: 1, green: 0.22, blue: 0.22))
                        }
                        Text(isPosting ? "Broadcasting…" : "Broadcast Now")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(isPosting)
            }
            .padding(.horizontal, 48)
        }
        .padding(.top, 16)
        .padding(.bottom, 48)
    }

    private func adChannelEmoji(_ channel: String) -> String {
        switch channel {
        case "food": return "🍔"; case "fitness": return "💪"; case "sports": return "⚽"
        case "beauty": return "💄"; case "fashion": return "👗"; case "music": return "🎵"
        case "tech": return "💻"; case "news": return "📺"; case "city": return "🏙️"
        case "entertainment": return "🎬"; default: return "📡"
        }
    }

    // MARK: - Ad generation

    private func generateAd() {
        generationError = nil
        isGenerating = true

        Task {
            do {
                let meta: TVStyleMetadata
                if let image {
                    meta = try await TVStyleAnalyzer.shared.analyze(image: image)
                } else if let videoURL {
                    meta = try await TVStyleAnalyzer.shared.analyze(videoURL: videoURL)
                } else {
                    throw AdGenerationError.noMedia
                }

                let fluxPrompt = buildAdPrompt(meta: meta)
                let adImage = try await AdGenerationService.generate(prompt: fluxPrompt)

                await MainActor.run {
                    generatedMeta = meta
                    isGenerating = false
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        step = .adPreview(adImage)
                    }
                }
            } catch {
                print("🎬 [AdGeneration] Failed: \(error)")
                await MainActor.run {
                    isGenerating = false
                    generationError = "Generation failed — check your internet connection and try again."
                }
            }
        }
    }

    private func buildAdPrompt(meta: TVStyleMetadata) -> String {
        let channelCtx = "\(selectedChannel.emoji) \(selectedChannel.title)"
        let coords = String(format: "%.2f°, %.2f°", coordinate.latitude, coordinate.longitude)
        var parts: [String] = []
        let who   = whoText.trimmingCharacters(in: .whitespaces)
        let what  = whatText.trimmingCharacters(in: .whitespaces)
        let where_ = whereText.trimmingCharacters(in: .whitespaces)
        let why   = whyText.trimmingCharacters(in: .whitespaces)
        if !who.isEmpty    { parts.append("Subject: \(who)") }
        if !what.isEmpty   { parts.append("Action: \(what)") }
        if !where_.isEmpty { parts.append("Setting: \(where_)") }
        if !why.isEmpty    { parts.append("Message: \(why)") }
        let userContext = parts.isEmpty ? "" : parts.joined(separator: ". ") + ". "
        return "\(userContext)A stunning cinematic TV advertisement for \(meta.broadcastName). "
            + "\(meta.tvFormat.replacingOccurrences(of: "_", with: " ")) format. "
            + "Ad concept: \(meta.adConcept). Channel: \(channelCtx). Location: \(coords). "
            + "Ultra-high production value, broadcast television quality, vivid saturated colors, "
            + "professional product photography, advertising industry standard. No text overlays."
    }

    private func broadcastAd(_ adImage: UIImage) {
        guard !isPosting else { return }
        isPosting = true
        statusText = "Broadcasting your Poplur TV ad…"

        let metadata = generatedMeta ?? fallbackMetadata()
        let edits = PostCaptureEdits(
            filter: selectedFilter,
            videoTrimSeconds: nil,
            channel: selectedChannel,
            tvMetadata: metadata
        )

        flowManager.capturedImage = adImage
        flowManager.capturedVideoURL = nil
        flowManager.completeFlow(finalCoordinate: coordinate, edits: edits)
        onDismiss?()
        NotificationCenter.default.post(name: Notification.Name("SwitchToProfileTab"), object: nil)
    }

    private func configureVideoDuration() {
        guard let videoURL else { return }
        let seconds = CMTimeGetSeconds(AVURLAsset(url: videoURL).duration)
        let safeSeconds = seconds.isFinite && seconds > 0 ? seconds : 10
        maxVideoTrimSeconds = max(1, min(safeSeconds, 60))
        videoTrimSeconds = min(maxVideoTrimSeconds, 10)
    }

    private func post() {
        guard !isPosting else { return }
        isPosting = true
        statusText = "AI feed service is turning this into Poplur TV content..."

        Task {
            let processedImage = image?.applyingPostCaptureFilter(selectedFilter)
            var processedVideoURL = videoURL

            if let videoURL {
                await MainActor.run { statusText = "Trimming and styling your video..." }
                processedVideoURL = await PostCaptureMediaProcessor.exportVideo(
                    url: videoURL,
                    filter: selectedFilter,
                    trimSeconds: videoTrimSeconds
                ) ?? videoURL
            }

            let metadata = await analyzeTVMetadata(image: processedImage, videoURL: processedVideoURL)
            let edits = PostCaptureEdits(
                filter: selectedFilter,
                videoTrimSeconds: isVideo ? videoTrimSeconds : nil,
                channel: selectedChannel,
                tvMetadata: metadata
            )

            await MainActor.run {
                flowManager.capturedImage = processedImage
                flowManager.capturedVideoURL = processedVideoURL
                flowManager.completeFlow(finalCoordinate: coordinate, edits: edits)
                onDismiss?()
                NotificationCenter.default.post(name: Notification.Name("SwitchToProfileTab"), object: nil)
            }
        }
    }

    private func analyzeTVMetadata(image: UIImage?, videoURL: URL?) async -> TVStyleMetadata {
        do {
            if let image {
                return try await TVStyleAnalyzer.shared.analyze(image: image)
            }
            if let videoURL {
                return try await TVStyleAnalyzer.shared.analyze(videoURL: videoURL)
            }
        } catch {
            print("📡 [TVAnalyzer] Falling back after post-capture analysis failed: \(error)")
        }
        return fallbackMetadata()
    }

    private func fallbackMetadata() -> TVStyleMetadata {
        TVStyleMetadata(
            channel: selectedChannel.tvAnalyzerChannel,
            tvFormat: "highlight_reel",
            adConcept: "\(selectedChannel.title.lowercased()) local broadcast",
            caption: "LOCAL SIGNAL",
            tagline: "A fresh Poplur moment is now live from the map.",
            broadcastName: "POPLUR \(selectedChannel.title.uppercased())"
        )
    }
}

// MARK: - Post-capture media processing

private enum PostCaptureMediaProcessor {
    static func exportVideo(url: URL, filter: PostCaptureFilter, trimSeconds: Double?) async -> URL? {
        let asset = AVURLAsset(url: url)
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        let requestedSeconds = trimSeconds ?? durationSeconds
        let exportSeconds = min(max(requestedSeconds, 1), durationSeconds.isFinite ? durationSeconds : requestedSeconds)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("poplur-edited-\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            return nil
        }

        export.outputURL = outputURL
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        if exportSeconds.isFinite && exportSeconds > 0 {
            export.timeRange = CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: exportSeconds, preferredTimescale: 600)
            )
        }
        if filter != .original {
            export.videoComposition = AVVideoComposition(asset: asset) { request in
                let source = request.sourceImage.clampedToExtent()
                let output = filter.apply(to: source).cropped(to: request.sourceImage.extent)
                request.finish(with: output, context: nil)
            }
        }

        return await withCheckedContinuation { continuation in
            export.exportAsynchronously {
                if export.status == .completed {
                    continuation.resume(returning: outputURL)
                } else {
                    try? FileManager.default.removeItem(at: outputURL)
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Filter helpers

private extension PostCaptureFilter {
    var displayName: String {
        switch self {
        case .original: return "Original"
        case .pop: return "Pop"
        case .noir: return "Noir"
        case .chrome: return "Chrome"
        case .warm: return "Warm"
        case .cool: return "Cool"
        }
    }

    var swatch: LinearGradient {
        switch self {
        case .original:
            return LinearGradient(colors: [.gray, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .pop:
            return LinearGradient(colors: [.pink, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .noir:
            return LinearGradient(colors: [.white, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .chrome:
            return LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .warm:
            return LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .cool:
            return LinearGradient(colors: [.blue, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder
    var previewOverlay: some View {
        switch self {
        case .original:
            EmptyView()
        case .pop:
            Color.pink.opacity(0.16).blendMode(.screen)
        case .noir:
            Color.black.opacity(0.10).blendMode(.multiply)
        case .chrome:
            Color.cyan.opacity(0.14).blendMode(.overlay)
        case .warm:
            Color.orange.opacity(0.18).blendMode(.softLight)
        case .cool:
            Color.blue.opacity(0.18).blendMode(.softLight)
        }
    }

    func apply(to input: CIImage) -> CIImage {
        switch self {
        case .original:
            return input
        case .pop:
            return ciFiltered("CIPhotoEffectProcess", input: input) ?? input
        case .noir:
            return ciFiltered("CIPhotoEffectNoir", input: input) ?? input
        case .chrome:
            return ciFiltered("CIPhotoEffectChrome", input: input) ?? input
        case .warm:
            return temperatureFiltered(input, neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 8200, y: 0)) ?? input
        case .cool:
            return temperatureFiltered(input, neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 4400, y: 0)) ?? input
        }
    }

    private func ciFiltered(_ name: String, input: CIImage) -> CIImage? {
        guard let filter = CIFilter(name: name) else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        return filter.outputImage
    }

    private func temperatureFiltered(_ input: CIImage, neutral: CIVector, target: CIVector) -> CIImage? {
        guard let filter = CIFilter(name: "CITemperatureAndTint") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(neutral, forKey: "inputNeutral")
        filter.setValue(target, forKey: "inputTargetNeutral")
        return filter.outputImage
    }
}

private extension PostCaptureChannel {
    var tvAnalyzerChannel: String {
        switch id {
        case "food": return "food"
        case "music": return "music"
        case "city": return "city"
        case "sports": return "sports"
        case "style": return "fashion"
        case "film": return "entertainment"
        default: return "entertainment"
        }
    }
}

private extension UIImage {
    func applyingPostCaptureFilter(_ filter: PostCaptureFilter) -> UIImage {
        guard filter != .original, let cgImage else { return self }
        let input = CIImage(cgImage: cgImage)
        let output = filter.apply(to: input)
        let context = CIContext(options: nil)
        guard let rendered = context.createCGImage(output, from: input.extent) else { return self }
        return UIImage(cgImage: rendered, scale: scale, orientation: imageOrientation)
    }
}

// MARK: - Ad generation service

private enum AdGenerationError: Error {
    case noMedia, generationFailed, downloadFailed
}

private enum AdGenerationService {
    /// Generates an ad image via Pollinations.ai (free, no API key required).
    static func generate(prompt: String) async throws -> UIImage {
        guard let encoded = prompt.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://image.pollinations.ai/prompt/\(encoded)?width=1080&height=1920&model=flux&nologo=true&enhance=false&seed=\(Int.random(in: 0...99999))")
        else { throw AdGenerationError.generationFailed }

        var req = URLRequest(url: url, timeoutInterval: 90)
        req.setValue("Poplur/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let image = UIImage(data: data)
        else { throw AdGenerationError.downloadFailed }
        return image
    }
}
