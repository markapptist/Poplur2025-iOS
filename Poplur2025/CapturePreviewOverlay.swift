import SwiftUI
import AVFoundation
import AVKit
import CoreLocation
import CoreImage
import UniformTypeIdentifiers

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
                        .poplurIconShader()
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
                    .poplurTextShader(intensity: 0.82)
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
                            .poplurIconShader()
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Retake")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .poplurTextShader(intensity: 0.62)
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
                        .poplurIconShader()
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(.white)
                    Text("Retake")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .poplurTextShader(intensity: 0.72)
                }
            }
            Spacer()
            Button { continueFromPreview() } label: {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .poplurIconShader()
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Color(red: 1, green: 0.22, blue: 0.22))
                    Text("Keep")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .poplurTextShader(intensity: 0.86)
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
                        .poplurTextShader(intensity: 0.82)
                        .tracking(0.8)
                    Text(meta.adConcept)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.70))
                        .poplurTextShader(intensity: 0.62)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .poplurIconShader()
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
                            .poplurIconShader()
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Retake")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .poplurTextShader(intensity: 0.64)
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
                                .poplurIconShader()
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(Color(red: 1, green: 0.22, blue: 0.22))
                        }
                        Text(isPosting ? "Broadcasting..." : "Broadcast Now")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .poplurTextShader(intensity: 0.76)
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
                        .poplurIconShader()
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(.white)
                    Text("Retake")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .poplurTextShader(intensity: 0.72)
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
                            .poplurIconShader()
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(.green)
                    }
                    Text(isPosting ? "Posting..." : "Post Anyway")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .poplurTextShader(intensity: 0.76)
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
        case "shopping": return "🛍️"; case "cartoon": return "🎨"; case "kids": return "🧸"
        case "comedy": return "😂"; case "entertainment": return "🎬"; default: return "📡"
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

    private enum Step: Equatable {
        case filters
        case creationChoice
        case adPrompt
        case adPreview(UIImage)
        case adVideoPreview(URL)
        case channel
    }

    @StateObject private var flowManager = CaptureFlowManager.shared
    @State private var step: Step = .filters
    @State private var selectedFilter: PostCaptureFilter = .original
    @State private var selectedChannel: PostCaptureChannel = PostCaptureChannel.all.first!
    @State private var videoTrimSeconds: Double = 10
    @State private var maxVideoTrimSeconds: Double = 10
    @State private var isPosting = false
    @State private var statusText = "Uploading your post..."
    @State private var usePoplurAI = false
    @State private var adPromptText: String = ""
    @State private var generatedAdImage: UIImage? = nil
    @State private var generatedAdVideoURL: URL? = nil
    @State private var generatedMeta: TVStyleMetadata? = nil
    @State private var isGenerating = false
    @State private var generationError: String? = nil
    @State private var generationStatusText = "Creating your Poplur TV ad..."
    @State private var adPulseScale: CGFloat = 1.0
    @State private var selectedMusicURL: URL? = nil
    @State private var selectedMusicTrack: MusicSearchTrack? = nil
    @State private var showMusicPicker = false
    @State private var showMusicSearch = false
    @State private var adVideoTrimSeconds: Double = 10
    @State private var adVideoMaxSeconds: Double = 10
    @FocusState private var isAdPromptFocused: Bool

    private var isVideo: Bool { videoURL != nil }
    private var isGeneratedChannelStep: Bool {
        guard case .channel = step else { return false }
        return usePoplurAI && (generatedAdImage != nil || generatedAdVideoURL != nil)
    }

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
            } else if case .adVideoPreview(let adVideoURL) = step {
                CaptureVideoPlayer(url: adVideoURL)
                    .ignoresSafeArea()
                if let meta = generatedMeta {
                    TVOverlayView(metadata: meta)
                }
            } else if isGeneratedChannelStep, let adImage = generatedAdImage {
                Image(uiImage: adImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
                if let meta = generatedMeta {
                    TVOverlayView(metadata: meta)
                }
            } else if isGeneratedChannelStep, let adVideoURL = generatedAdVideoURL {
                CaptureVideoPlayer(url: adVideoURL)
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
                case .creationChoice:
                    creationChoicePanel
                case .adPrompt:
                    adPromptPanel
                case .adPreview(let adImage):
                    adPreviewControls(adImage: adImage)
                case .adVideoPreview(let adVideoURL):
                    adVideoPreviewControls(adVideoURL: adVideoURL)
                case .channel:
                    channelPanel
                }
            }

            if isPosting || isGenerating {
                generatingOrPostingOverlay
            }
        }
        .onAppear(perform: configureVideoDuration)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if case .adPrompt = step {
                    Spacer()
                    Button("Done") {
                        isAdPromptFocused = false
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showMusicPicker) {
            MusicDocumentPicker { url in
                selectedMusicURL = url
                selectedMusicTrack = nil
            }
        }
        .sheet(isPresented: $showMusicSearch) {
            MusicSearchSheet(
                selectedTrack: selectedMusicTrack,
                onSelect: { track in
                    selectedMusicTrack = track
                    selectedMusicURL = nil
                },
                onUseLocalFile: {
                    showMusicSearch = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showMusicPicker = true
                    }
                }
            )
        }
        .onChange(of: step) { _, newStep in
            if case .adVideoPreview(let url) = newStep {
                let dur = CMTimeGetSeconds(AVURLAsset(url: url).duration)
                let safe = dur.isFinite && dur > 0 ? dur : 10
                adVideoMaxSeconds = max(1, min(safe, 60))
                adVideoTrimSeconds = min(adVideoMaxSeconds, 10)
            }
        }
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
        case .filters:        return "Edit capture"
        case .creationChoice: return "Finish post"
        case .adPrompt:       return "Describe Poplur AI"
        case .adPreview:      return "Preview Poplur AI"
        case .adVideoPreview: return "Preview Poplur AI"
        case .channel:        return "Choose channel"
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
                case .creationChoice:
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .filters }
                case .adPrompt:
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .creationChoice }
                case .adPreview:
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .adPrompt }
                case .adVideoPreview:
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .adPrompt }
                case .channel:
                    if usePoplurAI, let generatedAdImage {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .adPreview(generatedAdImage) }
                    } else if usePoplurAI, let generatedAdVideoURL {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .adVideoPreview(generatedAdVideoURL) }
                    } else {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .creationChoice }
                    }
                }
            } label: {
                Image(systemName: headerIsBack ? "chevron.left" : "xmark")
                    .poplurIconShader()
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.58), in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(headerStepTitle)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .poplurTextShader(intensity: 0.9)
                Text("\(String(format: "%.4f", coordinate.latitude)), \(String(format: "%.4f", coordinate.longitude))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .poplurTextShader(intensity: 0.58)
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
                                            .poplurIconShader()
                                            .font(.system(size: 15, weight: .black))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 48, height: 48)

                                Text(filter.displayName)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(selectedFilter == filter ? 1 : 0.72))
                                    .poplurTextShader(intensity: selectedFilter == filter ? 0.82 : 0.58)
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
                            .poplurTextShader(intensity: 0.76)
                        Spacer()
                        Text("\(Int(videoTrimSeconds.rounded()))s")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                            .poplurTextShader(intensity: 0.68)
                    }
                    Slider(value: $videoTrimSeconds, in: 1...max(maxVideoTrimSeconds, 1), step: 1)
                        .tint(Color(red: 1, green: 0.22, blue: 0.22))
                }
                .padding(.horizontal, 18)
            }

            editMusicControls

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .creationChoice }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.right.circle.fill")
                        .poplurIconShader()
                    Text("Continue")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .poplurTextShader(intensity: 0.78)
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

    private var editMusicControls: some View {
        VStack(spacing: 10) {
            Button { showMusicSearch = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: selectedMusicURL == nil && selectedMusicTrack == nil ? "music.note" : "music.note.list")
                        .poplurIconShader()
                        .font(.system(size: 15, weight: .bold))
                    Text(musicButtonTitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .poplurTextShader(intensity: 0.68)
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .poplurIconShader()
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(selectedMusicURL == nil && selectedMusicTrack == nil ? .white.opacity(0.78) : Color(red: 0.3, green: 1, blue: 0.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            if let selectedMusicTrack {
                musicTrackSummary(track: selectedMusicTrack)
            }
        }
        .padding(.horizontal, 18)
    }

    private var creationChoicePanel: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Post original or add Poplur AI?")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .poplurTextShader(intensity: 0.9)
                Text("Your edits are ready. Choose the version you want to send to a channel.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .poplurTextShader(intensity: 0.58)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)

            Button {
                usePoplurAI = false
                generatedAdImage = nil
                generatedAdVideoURL = nil
                generatedMeta = nil
                generationError = nil
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .channel }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "paperplane.fill")
                        .poplurIconShader()
                    Text("Post Original")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .poplurTextShader(intensity: 0.78)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)

            Button {
                usePoplurAI = true
                generatedAdImage = nil
                generatedAdVideoURL = nil
                generatedMeta = nil
                generationError = nil
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .adPrompt }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                        .poplurIconShader()
                    Text("Add Poplur AI")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .poplurTextShader(intensity: 0.9)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color(red: 1, green: 0.22, blue: 0.22), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
        }
        .padding(.top, 18)
        .padding(.bottom, 28)
        .background(.black.opacity(0.84))
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
                                        .poplurTextShader(intensity: 0.82)
                                    Text(channel.subtitle)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.62))
                                        .poplurTextShader(intensity: 0.56)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if selectedChannel == channel {
                                    Image(systemName: "checkmark.seal.fill")
                                        .poplurIconShader()
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

            channelValidationNotice

            Button {
                postSelectedOutput()
            } label: {
                HStack(spacing: 9) {
                    if isPosting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: usePoplurAI ? .white : .black))
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "dot.radiowaves.right")
                            .poplurIconShader()
                    }
                    Text(isPosting ? "Posting..." : "Post to Channel")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .poplurTextShader(intensity: 0.82)
                }
                .foregroundStyle(usePoplurAI ? .white : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(usePoplurAI ? Color(red: 1, green: 0.22, blue: 0.22) : Color.white, in: Capsule())
            }
            .disabled(isPosting)
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
        }
        .padding(.top, 16)
        .padding(.bottom, 28)
        .background(.black.opacity(0.84))
    }

    private var channelValidationNotice: some View {
        let recommendation = recommendedChannel(for: generatedMeta)
        let shouldMove = usePoplurAI && recommendation != nil && recommendation != selectedChannel
        return HStack(spacing: 10) {
            Image(systemName: shouldMove ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                .poplurIconShader()
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(shouldMove ? Color.yellow : Color(red: 0.30, green: 1, blue: 0.34))
            Text(shouldMove
                 ? "AI check: this fits CH \(recommendation!.number) \(recommendation!.title). It will post there instead."
                 : "AI will verify this content and move it to the right channel if needed.")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .poplurTextShader(intensity: 0.58)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 18)
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
                        .poplurIconShader()
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(isGenerating ? .yellow : .white)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        adPulseScale = 1.2
                    }
                }

                Text(isGenerating ? generationStatusText : statusText)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .poplurTextShader(intensity: 0.88)
                    .padding(.horizontal, 28)

                Text(isGenerating
                     ? "AI is trying every available Poplur generation route until it gets a result."
                    : "Your ad will be added to your profile.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.68))
                    .poplurTextShader(intensity: 0.58)
                    .padding(.horizontal, 28)
            }
        }
    }

    // MARK: - Ad prompt panel

    private var adPromptPanel: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tell Poplur AI what to make")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .poplurTextShader(intensity: 0.9)
                Text("Use one prompt. Photos generate photos, and videos generate videos.")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.60))
                    .poplurTextShader(intensity: 0.58)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                if adPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("A cinematic Poplur TV ad about...")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.34))
                        .poplurTextShader(intensity: 0.42)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                }
                TextEditor(text: $adPromptText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($isAdPromptFocused)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 132, maxHeight: 172)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .onChange(of: adPromptText) { _, newValue in
                        if newValue.count > 500 {
                            adPromptText = String(newValue.prefix(500))
                        }
                    }
            }
            .padding(.horizontal, 18)

            if let err = generationError {
                Text(err)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                    .poplurTextShader(intensity: 0.72)
                    .padding(.horizontal, 18)
            }

            Button {
                isAdPromptFocused = false
                generateAd()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                        .poplurIconShader()
                    Text("Generate Poplur AI")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .poplurTextShader(intensity: 0.78)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(adPromptEmpty ? Color.gray.opacity(0.6) : Color.white, in: Capsule())
            }
            .disabled(adPromptEmpty)
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
        }
        .padding(.top, 18)
        .padding(.bottom, 28)
        .background(.black.opacity(0.84))
    }

    private var adPromptEmpty: Bool {
        adPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Ad preview controls

    private func adPreviewControls(adImage: UIImage) -> some View {
        adPreviewControlsLayout(
            onRedo: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .adPrompt }
            },
            onBroadcast: {
                generatedAdImage = adImage
                generatedAdVideoURL = nil
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .channel }
            },
            primaryTitle: "Pick Channel",
            primaryIcon: "tv.fill",
            showFilterStrip: true,
            showTrimSlider: false
        )
    }

    private func adChannelEmoji(_ channel: String) -> String {
        switch channel {
        case "food": return "🍔"; case "fitness": return "💪"; case "sports": return "⚽"
        case "beauty": return "💄"; case "fashion": return "👗"; case "music": return "🎵"
        case "tech": return "💻"; case "news": return "📺"; case "city": return "🏙️"
        case "shopping": return "🛍️"; case "cartoon": return "🎨"; case "kids": return "🧸"
        case "comedy": return "😂"; case "entertainment": return "🎬"; default: return "📡"
        }
    }

    // MARK: - Ad generation

    private func generateAd() {
        guard !isGenerating else { return }
        generationError = nil
        generationStatusText = "Starting Poplur AI..."
        isGenerating = true

        Task {
            guard image != nil || videoURL != nil else {
                await finishGenerationFailure("No media was found. Retake and try again.")
                return
            }

            await updateGenerationStatus("Analyzing your capture...")
            let meta = await analyzeTVMetadata(image: image, videoURL: videoURL)
            let prompt = buildAdPrompt(meta: meta)
            let faceImage: UIImage? = image ?? (videoURL.flatMap { firstFrame(of: $0) })

            if isVideo {
                await generateVideoAd(meta: meta, prompt: prompt, faceImage: faceImage)
            } else {
                await generateImageAd(meta: meta, prompt: prompt, faceImage: faceImage)
            }
        }
    }

    private func generateVideoAd(meta: TVStyleMetadata, prompt: String, faceImage: UIImage?) async {
        if let faceImage {
            do {
                let videoURL = try await generationAttempt("Animating your capture with Poplur AI") {
                    try await FaceAdGenerationService.generateVideo(faceImage: faceImage, prompt: prompt)
                }
                await showGeneratedVideo(videoURL, meta: meta)
                return
            } catch {
                logGenerationFailure("face video", error)
            }
        }

        do {
            let videoURL = try await generationAttempt("Building a fresh Poplur AI video") {
                try await VideoAdGenerationService.generate(prompt: prompt)
            }
            await showGeneratedVideo(videoURL, meta: meta)
            return
        } catch {
            logGenerationFailure("text video", error)
        }

        await updateGenerationStatus("Video AI is busy. Creating a Poplur poster ad...")
        await generateImageAd(meta: meta, prompt: prompt, faceImage: faceImage)
    }

    private func generateImageAd(meta: TVStyleMetadata, prompt: String, faceImage: UIImage?) async {
        if let faceImage {
            do {
                let image = try await generationAttempt("Creating your face-aware Poplur AI ad") {
                    try await FaceAdGenerationService.generateImage(faceImage: faceImage, prompt: prompt)
                }
                await showGeneratedImage(image, meta: meta)
                return
            } catch {
                logGenerationFailure("face image", error)
            }
        }

        do {
            let image = try await generationAttempt("Creating a fresh Poplur AI ad", attempts: 3) {
                try await AdGenerationService.generate(prompt: prompt)
            }
            await showGeneratedImage(image, meta: meta)
        } catch {
            logGenerationFailure("image fallback", error)
            await finishGenerationFailure("Poplur AI could not finish this one. Check connection and tap Generate again.")
        }
    }

    private func generationAttempt<T>(
        _ status: String,
        attempts: Int = 2,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...attempts {
            let suffix = attempts > 1 ? " (\(attempt)/\(attempts))" : ""
            await updateGenerationStatus(status + suffix)
            do {
                return try await operation()
            } catch {
                lastError = error
                logGenerationFailure("\(status) attempt \(attempt)", error)
                if attempt < attempts {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                }
            }
        }
        throw lastError ?? AdGenerationError.generationFailed
    }

    private func showGeneratedImage(_ image: UIImage, meta: TVStyleMetadata) async {
        await MainActor.run {
            generatedMeta = meta
            generatedAdImage = image
            generatedAdVideoURL = nil
            isGenerating = false
            generationStatusText = "Creating your Poplur TV ad..."
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                step = .adPreview(image)
            }
        }
    }

    private func showGeneratedVideo(_ url: URL, meta: TVStyleMetadata) async {
        await MainActor.run {
            generatedMeta = meta
            generatedAdVideoURL = url
            generatedAdImage = nil
            isGenerating = false
            generationStatusText = "Creating your Poplur TV ad..."
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                step = .adVideoPreview(url)
            }
        }
    }

    private func updateGenerationStatus(_ text: String) async {
        await MainActor.run { generationStatusText = text }
    }

    private func finishGenerationFailure(_ message: String) async {
        await MainActor.run {
            generationError = message
            isGenerating = false
            generationStatusText = "Creating your Poplur TV ad..."
        }
    }

    private func logGenerationFailure(_ route: String, _ error: Error) {
        print("[PoplurAI] \(route) failed: \(error.localizedDescription)")
    }

    private func firstFrame(of url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1024, height: 1024)
        guard let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func buildAdPrompt(meta: TVStyleMetadata) -> String {
        let recommended = recommendedChannel(for: meta) ?? selectedChannel
        let channelCtx = "\(recommended.emoji) \(recommended.title)"
        let coords = String(format: "%.2f°, %.2f°", coordinate.latitude, coordinate.longitude)
        let userPrompt = adPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let userContext = userPrompt.isEmpty ? "" : "User prompt: \(userPrompt). "
        return "\(userContext)A stunning cinematic Poplur TV advertisement for \(meta.broadcastName). "
            + "\(meta.tvFormat.replacingOccurrences(of: "_", with: " ")) format. "
            + "Ad concept: \(meta.adConcept). Channel: \(channelCtx). Location: \(coords). "
            + "Ultra-high production value, broadcast television quality, vivid saturated colors, "
            + "professional product photography, advertising industry standard. No text overlays."
    }

    private func broadcastAd(_ adImage: UIImage) {
        guard !isPosting else { return }
        isPosting = true
        statusText = "Uploading your post..."

        let metadata = generatedMeta ?? fallbackMetadata()
        let finalChannel = validatedChannel(for: metadata)
        let finalMetadata = metadata.routed(to: finalChannel)
        let edits = PostCaptureEdits(
            filter: selectedFilter,
            videoTrimSeconds: nil,
            channel: finalChannel,
            tvMetadata: finalMetadata
        )

        Task {
            // Burn filter into the output image
            let filteredImage = adImage.applyingPostCaptureFilter(selectedFilter)

            if let musicURL = selectedMusicURL {
                // Image + music → bake into a video
                await MainActor.run { statusText = "Adding music…" }
                if let videoWithMusic = await OutputMusicMixer.imageWithAudio(filteredImage, audioURL: musicURL, filter: .original) {
                    await MainActor.run {
                        flowManager.capturedImage = nil
                        flowManager.capturedVideoURL = videoWithMusic
                        flowManager.completeFlow(finalCoordinate: coordinate, edits: edits)
                        onDismiss?()
                        NotificationCenter.default.post(name: Notification.Name("SwitchToProfileTab"), object: nil)
                    }
                    return
                }
            }

            await MainActor.run {
                flowManager.capturedImage = filteredImage
                flowManager.capturedVideoURL = nil
                flowManager.completeFlow(finalCoordinate: coordinate, edits: edits)
                onDismiss?()
                NotificationCenter.default.post(name: Notification.Name("SwitchToProfileTab"), object: nil)
            }
        }
    }

    private func adVideoPreviewControls(adVideoURL: URL) -> some View {
        adPreviewControlsLayout(
            onRedo: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .adPrompt }
            },
            onBroadcast: {
                generatedAdVideoURL = adVideoURL
                generatedAdImage = nil
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { step = .channel }
            },
            primaryTitle: "Pick Channel",
            primaryIcon: "tv.fill",
            showFilterStrip: true,
            showTrimSlider: true
        )
    }

    private func broadcastAdVideo(_ adVideoURL: URL) {
        guard !isPosting else { return }
        isPosting = true
        statusText = "Uploading your post..."

        let metadata = generatedMeta ?? fallbackMetadata()
        let finalChannel = validatedChannel(for: metadata)
        let finalMetadata = metadata.routed(to: finalChannel)
        let edits = PostCaptureEdits(
            filter: selectedFilter,
            videoTrimSeconds: adVideoTrimSeconds,
            channel: finalChannel,
            tvMetadata: finalMetadata
        )

        Task {
            do {
                // Download generated video to a local temp file
                await MainActor.run { statusText = "Preparing video…" }
                let (localURL, _) = try await URLSession.shared.download(from: adVideoURL)
                let raw = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".mp4")
                try FileManager.default.moveItem(at: localURL, to: raw)

                // Apply filter + trim to the output
                await MainActor.run { statusText = "Applying filter…" }
                let processed = await PostCaptureMediaProcessor.exportVideo(
                    url: raw,
                    filter: selectedFilter,
                    trimSeconds: adVideoTrimSeconds
                ) ?? raw

                // Mix in music if selected
                var dest = processed
                if let musicURL = selectedMusicURL {
                    await MainActor.run { statusText = "Adding music…" }
                    dest = await OutputMusicMixer.mixAudio(musicURL, intoVideo: processed, trimSeconds: nil) ?? processed
                }

                await MainActor.run {
                    flowManager.capturedImage = nil
                    flowManager.capturedVideoURL = dest
                    flowManager.completeFlow(finalCoordinate: coordinate, edits: edits)
                    onDismiss?()
                    NotificationCenter.default.post(name: Notification.Name("SwitchToProfileTab"), object: nil)
                }
            } catch {
                await MainActor.run {
                    isPosting = false
                    statusText = "Uploading your post..."
                    generationError = "Video download failed — try again."
                }
            }
        }
    }

    // Shared button layout used by both image and video ad previews
    private func adPreviewControlsLayout(
        onRedo: @escaping () -> Void,
        onBroadcast: @escaping () -> Void,
        primaryTitle: String = "Broadcast Now",
        primaryIcon: String = "dot.radiowaves.right",
        showFilterStrip: Bool = false,
        showTrimSlider: Bool = false
    ) -> some View {
        VStack(spacing: 14) {
            // Filter strip (shown for image output)
            if showFilterStrip {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PostCaptureFilter.allCases) { filter in
                            Button {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                    selectedFilter = filter
                                }
                            } label: {
                                VStack(spacing: 5) {
                                    Circle()
                                        .fill(filter.swatch)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            selectedFilter == filter
                                            ? Circle().stroke(.white, lineWidth: 2.5)
                                            : nil
                                        )
                                    Text(filter.displayName)
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(selectedFilter == filter ? .white : .white.opacity(0.55))
                                        .poplurTextShader(intensity: selectedFilter == filter ? 0.78 : 0.5)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }

            // Trim slider (shown for video output)
            if showTrimSlider {
                VStack(spacing: 4) {
                    HStack {
                        Text("Trim")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .poplurTextShader(intensity: 0.58)
                            .tracking(1)
                            .textCase(.uppercase)
                        Spacer()
                        Text("\(Int(adVideoTrimSeconds))s")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .poplurTextShader(intensity: 0.74)
                    }
                    Slider(value: $adVideoTrimSeconds, in: 1...adVideoMaxSeconds, step: 1)
                        .tint(.white)
                }
                .padding(.horizontal, 18)
            }

            // Music button
            Button { showMusicSearch = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: selectedMusicURL == nil && selectedMusicTrack == nil ? "music.note" : "music.note.list")
                        .poplurIconShader()
                        .font(.system(size: 15, weight: .bold))
                    Text(musicButtonTitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .poplurTextShader(intensity: 0.68)
                }
                .foregroundStyle(selectedMusicURL == nil && selectedMusicTrack == nil ? .white.opacity(0.75) : Color(red: 0.3, green: 1, blue: 0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)

            if let selectedMusicTrack {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selectedMusicTrack.provider.accent.opacity(0.85))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: "music.note")
                                .poplurIconShader()
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(.black.opacity(0.82))
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedMusicTrack.title)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .poplurTextShader(intensity: 0.76)
                            .lineLimit(1)
                        Text("\(selectedMusicTrack.artist) • \(selectedMusicTrack.provider.rawValue)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                            .poplurTextShader(intensity: 0.54)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        self.selectedMusicTrack = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .poplurIconShader()
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 18)
            }

            if let meta = generatedMeta {
                HStack(spacing: 10) {
                    Text(adChannelEmoji(meta.channel))
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meta.broadcastName)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .poplurTextShader(intensity: 0.78)
                            .tracking(0.8)
                        Text(meta.adConcept)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.70))
                            .poplurTextShader(intensity: 0.56)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "sparkles")
                        .poplurIconShader()
                        .foregroundStyle(.yellow)
                        .font(.system(size: 16))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 18)
            }

            HStack(spacing: 24) {
                Button(action: onRedo) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .poplurIconShader()
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Redo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .poplurTextShader(intensity: 0.64)
                    }
                }
                .disabled(isPosting)

                Spacer()

                Button(action: onBroadcast) {
                    VStack(spacing: 8) {
                        if isPosting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.4)
                                .frame(width: 40, height: 40)
                        } else {
                            Image(systemName: primaryIcon)
                                .poplurIconShader()
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(Color(red: 1, green: 0.22, blue: 0.22))
                        }
                        Text(isPosting ? "Broadcasting…" : primaryTitle)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .poplurTextShader(intensity: 0.76)
                    }
                }
                .disabled(isPosting)
            }
            .padding(.horizontal, 48)
        }
        .padding(.top, 16)
        .padding(.bottom, 48)
    }

    private var musicButtonTitle: String {
        if selectedMusicURL != nil { return "Music File Added" }
        if selectedMusicTrack != nil { return "Track Linked" }
        return "Add Music"
    }

    private func musicTrackSummary(track: MusicSearchTrack) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(track.provider.accent.opacity(0.85))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "music.note")
                        .poplurIconShader()
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.black.opacity(0.82))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .poplurTextShader(intensity: 0.76)
                    .lineLimit(1)
                Text("\(track.artist) • \(track.provider.rawValue)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .poplurTextShader(intensity: 0.54)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                selectedMusicTrack = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .poplurIconShader()
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.48))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func configureVideoDuration() {
        guard let videoURL else { return }
        let seconds = CMTimeGetSeconds(AVURLAsset(url: videoURL).duration)
        let safeSeconds = seconds.isFinite && seconds > 0 ? seconds : 10
        maxVideoTrimSeconds = max(1, min(safeSeconds, 60))
        videoTrimSeconds = min(maxVideoTrimSeconds, 10)
    }

    private func postSelectedOutput() {
        if usePoplurAI, let generatedAdImage {
            broadcastAd(generatedAdImage)
        } else if usePoplurAI, let generatedAdVideoURL {
            broadcastAdVideo(generatedAdVideoURL)
        } else {
            post()
        }
    }

    private func post() {
        guard !isPosting else { return }
        isPosting = true
        statusText = "Uploading your post..."

        Task {
            var processedImage = image?.applyingPostCaptureFilter(selectedFilter)
            var processedVideoURL = videoURL

            if let videoURL {
                await MainActor.run { statusText = "Trimming and styling your video..." }
                processedVideoURL = await PostCaptureMediaProcessor.exportVideo(
                    url: videoURL,
                    filter: selectedFilter,
                    trimSeconds: videoTrimSeconds
                ) ?? videoURL
            }

            if let musicURL = selectedMusicURL {
                if let videoURL = processedVideoURL {
                    await MainActor.run { statusText = "Adding music..." }
                    processedVideoURL = await OutputMusicMixer.mixAudio(musicURL, intoVideo: videoURL, trimSeconds: nil) ?? videoURL
                } else if let image = processedImage {
                    await MainActor.run { statusText = "Adding music..." }
                    if let videoWithMusic = await OutputMusicMixer.imageWithAudio(image, audioURL: musicURL, filter: .original) {
                        processedImage = nil
                        processedVideoURL = videoWithMusic
                    }
                }
            }

            let metadata = await analyzeTVMetadata(image: processedImage, videoURL: processedVideoURL)
            let finalChannel = validatedChannel(for: metadata)
            let finalMetadata = metadata.routed(to: finalChannel)
            let edits = PostCaptureEdits(
                filter: selectedFilter,
                videoTrimSeconds: processedVideoURL != nil ? videoTrimSeconds : nil,
                channel: finalChannel,
                tvMetadata: finalMetadata
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

    private func validatedChannel(for metadata: TVStyleMetadata?) -> PostCaptureChannel {
        recommendedChannel(for: metadata) ?? selectedChannel
    }

    private func recommendedChannel(for metadata: TVStyleMetadata?) -> PostCaptureChannel? {
        let text = [
            metadata?.channel,
            metadata?.adConcept,
            metadata?.caption,
            metadata?.tagline,
            metadata?.broadcastName,
            adPromptText
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let pairs: [(String, [String])] = [
            ("food", ["food", "restaurant", "burger", "pizza", "recipe", "coffee", "drink", "meal", "kitchen"]),
            ("gaming", ["gaming", "game", "stream", "console", "esport", "controller", "playthrough"]),
            ("music", ["music", "song", "studio", "concert", "artist", "album", "beat", "dj"]),
            ("sports", ["sports", "fitness", "workout", "training", "soccer", "basketball", "gym", "game day"]),
            ("style", ["style", "fashion", "beauty", "makeup", "skincare", "outfit", "hair"]),
            ("shopping", ["shopping", "shop", "buy", "haul", "drop", "deal", "store", "product"]),
            ("city", ["city", "street", "local", "news", "neighborhood", "traffic", "downtown", "tech"]),
            ("film", ["film", "movie", "cinema", "trailer", "show", "entertainment", "edit"]),
            ("french", ["french", "français", "france"]),
            ("spanish", ["spanish", "español", "spain", "latino"])
        ]

        let matchID = pairs.first { _, words in
            words.contains { text.contains($0) }
        }?.0

        return matchID.flatMap { id in PostCaptureChannel.all.first { $0.id == id } }
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

}

// CIImage-based filter application — internal so OutputMusicMixer can use it.
extension PostCaptureFilter {
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
        case "shopping": return "shopping"
        case "cartoon": return "entertainment"
        case "kids": return "entertainment"
        case "comedy": return "entertainment"
        default: return "entertainment"
        }
    }
}

private extension TVStyleMetadata {
    func routed(to channel: PostCaptureChannel) -> TVStyleMetadata {
        let target = channel.tvAnalyzerChannel
        guard self.channel != target || !broadcastName.localizedCaseInsensitiveContains(channel.title) else {
            return self
        }
        return TVStyleMetadata(
            channel: target,
            tvFormat: tvFormat,
            adConcept: adConcept,
            caption: caption,
            tagline: tagline,
            broadcastName: "POPLUR \(channel.title.uppercased())"
        )
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

private enum AdGenerationError: LocalizedError {
    case noMedia, generationFailed, downloadFailed, providerMustRunOnBackend

    var errorDescription: String? {
        switch self {
        case .noMedia: return "No media was found."
        case .generationFailed: return "AI generation failed."
        case .downloadFailed: return "Could not download generated media."
        case .providerMustRunOnBackend: return "Poplur AI generation must run through the backend so provider keys stay server-side."
        }
    }
}

// MARK: - Music picker

private struct MusicDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.audio, .movie]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

private enum AdGenerationService {
    static func generate(prompt: String) async throws -> UIImage {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#%/")
        guard let encoded = prompt.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://image.pollinations.ai/prompt/\(encoded)?width=1080&height=1920&model=flux&nologo=true&enhance=false&seed=\(Int.random(in: 0...99999))")
        else { throw AdGenerationError.generationFailed }

        var req = URLRequest(url: url, timeoutInterval: 90)
        req.setValue("Poplur/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AdGenerationError.downloadFailed }
        guard http.statusCode == 200 else {
            if let body = String(data: data, encoding: .utf8) {
                print("[FreeTierAdGenerationService] image failed \(http.statusCode): \(body)")
            }
            throw AdGenerationError.downloadFailed
        }
        guard let image = UIImage(data: data) else { throw AdGenerationError.downloadFailed }
        return image
    }
}

private enum VideoAdGenerationService {
    static func generate(prompt: String) async throws -> URL {
        _ = prompt
        // TODO: Queue POST /ai/generate/video through Poplur's backend and return the completed asset URL.
        throw AdGenerationError.providerMustRunOnBackend
    }
}
