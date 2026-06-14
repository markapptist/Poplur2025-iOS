//
//  FeedFullscreenPageView.swift
//  Fullscreen Feed Page with Video/Image Support
//

import SwiftUI
import AVFoundation
import AVKit
import CoreLocation
import FirebaseFirestore

// MARK: - Fullscreen Feed Page View

struct FeedFullscreenPageView: View {
    let post: FeedPost
    let displayName: String
    var onMediaReady: () -> Void = {}
    var onUserTapped: (String) -> Void

    @State private var imagePhaseDebug: String = ""
    @State private var debugPlayerTimeControl: AVPlayer.TimeControlStatus = .waitingToPlayAtSpecifiedRate
    @State private var debugItemStatus: AVPlayerItem.Status = .unknown
    @State private var didReportMediaReady = false

    // Added for playback stuck detection and UI overlay
    @State private var forceVideoPlaceholder: Bool = false
    @State private var playbackStuck: Bool = false

    private var coordinateText: String {
        String(format: "%.4f, %.4f", post.latitude, post.longitude)
    }

    // REPLACED directVideoURL property with updated logic
    private var directVideoURL: URL? {
        guard let url = URL(string: post.mediaURL) else { return nil }
        let lower = url.absoluteString.lowercased()

        // If it's the Apple devstreaming segment (fileSequenceX.mp4), treat as non-direct video so we don't try to play a fragment.
        if lower.contains("devstreaming-cdn.apple.com"),
           lower.contains("filesequence"),
            lower.hasSuffix(".mp4") {
            return nil
        }

        // Broaden detection: handle querystrings and common video hints
        let videoHints = [".mp4", ".m3u8", "/prog_index.m3u8", "video.mp4", "format=mp4", "format=hls", "type=video"]
        let isVideo = videoHints.contains { lower.contains($0) }
        return isVideo ? url : nil
    }

    // Replaced custom PlayerLayer with AVKit.VideoPlayer for reliability
    struct VideoPlayerContainer: View {
        let url: URL
        let mediaKey: String
        @Binding var hudTimeControl: AVPlayer.TimeControlStatus
        @Binding var hudItemStatus: AVPlayerItem.Status
        @Binding var playbackStuck: Bool
        let onReadyToDisplay: () -> Void
        @State private var player: AVPlayer? = nil
        @State private var itemObservation: NSKeyValueObservation? = nil

        @State private var timeObserver: Any? = nil
        @State private var endObserver: Any? = nil
        
        @State private var pauseObserver: Any? = nil

        @State private var itemFailed: Bool = false
        @State private var isReadyToDisplay: Bool = false

        private func setupPlayer() {
            guard player == nil else { return }
            
            // Configure audio session for playback with mixing disabled so audio is audible
            DispatchQueue.main.async {
                let session = AVAudioSession.sharedInstance()
                do {
                    try session.setCategory(.playback, mode: .moviePlayback, options: [])
                    try session.setActive(true, options: [])
                } catch {
                    print("[Video] Audio session setup failed (main): \(error)")
                }
            }

            let assetOptions: [String: Any] = [
                "AVURLAssetAllowsCellularAccessKey": true,
                "AVURLAssetAllowsConstrainedNetworkAccessKey": true
            ]
            let asset = AVURLAsset(url: url, options: assetOptions)
            asset.resourceLoader.preloadsEligibleContentKeys = true

            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 0
            let p = AVPlayer(playerItem: item)
            p.allowsExternalPlayback = false
            p.isMuted = false
            p.automaticallyWaitsToMinimizeStalling = false
            p.preventsDisplaySleepDuringVideoPlayback = true

            itemObservation = item.observe(\.status, options: [.initial, .new]) { _, _ in
                DispatchQueue.main.async {
                    self.hudItemStatus = item.status
                    print("[Video] Item status changed to: \(item.status.rawValue)")
                    switch item.status {
                    case .readyToPlay:
                        self.itemFailed = false
                        self.playbackStuck = false
                        p.seek(to: CMTime(seconds: 0.01, preferredTimescale: 600))
                        FeedAudioManager.shared.playExclusively(p)
                        p.playImmediately(atRate: 1.0)
                        self.hudTimeControl = p.timeControlStatus
                    case .failed:
                        self.itemFailed = true
                        self.playbackStuck = true
                        if let err = item.error { print("[Video] Item failed: \(err)") }
                        NotificationCenter.default.post(name: Notification.Name("FeedAdvanceOnMediaFailure"), object: nil)
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                p.seek(to: .zero)
                p.playImmediately(atRate: 1.0)
            }

            player = p
            FeedAudioManager.shared.register(p)
            p.play()
            timeObserver = p.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                queue: .main
            ) { time in
                if time.seconds > 0.05 || p.timeControlStatus == .playing {
                    self.isReadyToDisplay = true
                    self.playbackStuck = false
                    self.onReadyToDisplay()
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.hudTimeControl = p.timeControlStatus }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if p.timeControlStatus != .playing {
                    p.playImmediately(atRate: 1.0)
                }
                self.hudTimeControl = p.timeControlStatus
                if p.timeControlStatus == .playing || p.currentTime().seconds > 0.05 {
                    self.isReadyToDisplay = true
                    self.playbackStuck = false
                    self.onReadyToDisplay()
                }
            }

            // Removed two existing playback stuck checks at 3s and 5s and replaced with a single 8s check
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                let notPlaying = (self.hudTimeControl != .playing)
                let notReady = (self.hudItemStatus != .readyToPlay)
                if notPlaying && notReady {
                    self.playbackStuck = true
                    print("[Video] Playback appears stuck after 8s: timeControl=\(self.hudTimeControl.rawValue) item=\(self.hudItemStatus.rawValue)")
                }
            }
        }

        var body: some View {
            ZStack {
                VideoLoadingPlaceholder(mediaKey: mediaKey)
                    .opacity(isReadyToDisplay ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: isReadyToDisplay)

                if let player {
                    PlayerLayerView(player: player, onReadyToDisplay: onReadyToDisplay, isReadyToDisplay: $isReadyToDisplay)
                        .opacity(isReadyToDisplay ? 1 : 0.01)
                        .animation(.easeOut(duration: 0.2), value: isReadyToDisplay)
                        .onAppear {
                            if player.timeControlStatus != .playing {
                                player.playImmediately(atRate: 1.0)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                if let p = self.player, p.timeControlStatus != .playing {
                                    p.playImmediately(atRate: 1.0)
                                    self.hudTimeControl = p.timeControlStatus
                                    if p.timeControlStatus == .playing {
                                        self.playbackStuck = false
                                    }
                                }
                            }
                        }
                }
            }
            .onAppear {
                setupPlayer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .PauseGlobalFeedAudio)) { _ in
                teardownPlayer()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                teardownPlayer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .PauseFeedAudio)) { _ in
                player?.pause()
            }
            .onReceive(NotificationCenter.default.publisher(for: .ResumeFeedAudio)) { _ in
                resumePlayer()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                resumePlayer()
            }
            .onDisappear {
                teardownPlayer()
            }
        }

        private func resumePlayer() {
            if let player {
                player.playImmediately(atRate: 1.0)
                hudTimeControl = player.timeControlStatus
            } else {
                setupPlayer()
            }
        }

        private func teardownPlayer() {
            if let token = pauseObserver {
                NotificationCenter.default.removeObserver(token)
                pauseObserver = nil
            }
            if let token = endObserver {
                NotificationCenter.default.removeObserver(token)
                endObserver = nil
            }
            playbackStuck = false
            isReadyToDisplay = false
            if let obs = timeObserver, let p = player {
                p.removeTimeObserver(obs)
            }
            timeObserver = nil
            itemObservation = nil
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
        }
    }

    struct PlayerLayerView: UIViewRepresentable {
        let player: AVPlayer?
        let onReadyToDisplay: () -> Void
        @Binding var isReadyToDisplay: Bool

        func makeUIView(context: Context) -> PlayerHostingView {
            let view = PlayerHostingView()
            view.backgroundColor = .black
            view.translatesAutoresizingMaskIntoConstraints = false
            view.playerLayer.videoGravity = .resizeAspectFill
            view.onReadyForDisplayChanged = { ready in
                DispatchQueue.main.async {
                    if isReadyToDisplay != ready {
                        isReadyToDisplay = ready
                    }
                    if ready {
                        onReadyToDisplay()
                    }
                }
            }
            view.player = player
            return view
        }

        func updateUIView(_ uiView: PlayerHostingView, context: Context) {
            uiView.onReadyForDisplayChanged = { ready in
                DispatchQueue.main.async {
                    if isReadyToDisplay != ready {
                        isReadyToDisplay = ready
                    }
                    if ready {
                        onReadyToDisplay()
                    }
                }
            }
            uiView.player = player
            uiView.playerLayer.videoGravity = .resizeAspectFill
            uiView.setNeedsLayout()
            uiView.layoutIfNeeded()
        }
    }

    final class PlayerHostingView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var onReadyForDisplayChanged: ((Bool) -> Void)? {
            didSet {
                notifyReadyForDisplay()
            }
        }
        private var readyPollWorkItem: DispatchWorkItem?

        var player: AVPlayer? {
            get { playerLayer.player }
            set {
                playerLayer.player = newValue
                notifyReadyForDisplay()
                startReadyPolling()
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        deinit {
            readyPollWorkItem?.cancel()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
            playerLayer.videoGravity = .resizeAspectFill
            startReadyPolling()
        }

        private func startReadyPolling(attempt: Int = 0) {
            readyPollWorkItem?.cancel()
            guard playerLayer.player != nil else { return }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.notifyReadyForDisplay()

                if !self.playerLayer.isReadyForDisplay && attempt < 240 {
                    self.startReadyPolling(attempt: attempt + 1)
                }
            }
            readyPollWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
        }

        private func notifyReadyForDisplay() {
            onReadyForDisplayChanged?(playerLayer.isReadyForDisplay)
        }
    }

    private var debugTimeControlText: String {
        switch debugPlayerTimeControl {
        case .paused: return "paused"
        case .waitingToPlayAtSpecifiedRate: return "waiting"
        case .playing: return "playing"
        @unknown default: return "unknown"
        }
    }

    private var debugItemStatusText: String {
        switch debugItemStatus {
        case .unknown: return "unknown"
        case .readyToPlay: return "ready"
        case .failed: return "failed"
        @unknown default: return "unknown"
        }
    }

    // REPLACED body implementation with a thin wrapper delegating to contentView to reduce type-checking complexity
    var body: some View {
        GeometryReader { geo in
            contentView(size: geo.size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.5) {
                    // Long press to show post location on map with user annotation
                    let coordinate = CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude)
                    print("📍 [FeedFullscreenPageView] Long press - showing post location: \(coordinate.latitude), \(coordinate.longitude)")
                    
                    // Haptic feedback
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    
                    // Fetch user profile info asynchronously
                    Task {
                        // Get username
                        let username = await UsernameCache.shared.username(for: post.userID)
                        
                        // Get profile image URL if available (from Firestore user document)
                        var profileImageURL: String? = nil
                        #if !POP_PREVIEW_LIGHT
                        #if canImport(FirebaseFirestore)
                        do {
                            let db = Firestore.firestore()
                            let userDoc = try await db.collection("users").document(post.userID).getDocument()
                            if let data = userDoc.data(),
                               let urlString = data["profilePictureURL"] as? String {
                                profileImageURL = urlString
                            }
                        } catch {
                            print("⚠️ [FeedFullscreenPageView] Failed to fetch profile image: \(error.localizedDescription)")
                        }
                        #endif
                        #endif
                        
                        await MainActor.run {
                            // Prepare user info with coordinate as CLLocationCoordinate2D object
                            var userInfo: [String: Any] = [
                                "coordinate": coordinate,
                                "userID": post.userID,
                                "username": username ?? displayName,
                                "radius": Double(post.radius)
                            ]
                            
                            // Add profile image URL if available
                            if let profileURL = profileImageURL {
                                userInfo["profileImageURL"] = profileURL
                            }
                            
                            // Add location metadata if available
                            if let cityName = post.cityName {
                                userInfo["cityName"] = cityName
                            }
                            if let countryName = post.countryName {
                                userInfo["countryName"] = countryName
                            }
                            if let countryFlag = post.countryFlag {
                                userInfo["countryFlag"] = countryFlag
                            }
                            
                            print("📍 [FeedFullscreenPageView] Posting ShowLocationOnMap with coordinate: \(coordinate.latitude), \(coordinate.longitude)")
                            print("   Username: \(username ?? displayName), Profile URL: \(profileImageURL ?? "nil")")
                            if let city = post.cityName, let country = post.countryName {
                                print("   Location: \(city), \(country) \(post.countryFlag ?? "")")
                            }
                            print("   Radius: \(Int(post.radius))m")
                            
                            // ALSO store in MapStateManager for when MapView isn't loaded yet
                            print("📍 [FeedFullscreenPageView] Setting pending post location in MapStateManager")
                            MapStateManager.shared.setPendingPostLocation(
                                coordinate,
                                userID: post.userID,
                                username: username ?? displayName,
                                profileImageURL: profileImageURL,
                                radius: Double(post.radius),
                                cityName: post.cityName,
                                countryName: post.countryName,
                                countryFlag: post.countryFlag
                            )
                            
                            // Post notification to show location on map
                            NotificationCenter.default.post(
                                name: Notification.Name("ShowLocationOnMap"),
                                object: nil,
                                userInfo: userInfo
                            )
                            
                            // Wait a moment before switching tabs
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                // Switch to map tab
                                NotificationCenter.default.post(
                                    name: Notification.Name("SwitchToMapTab"),
                                    object: nil
                                )
                            }
                        }
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    @ViewBuilder
    private func contentView(size: CGSize) -> some View {
        let isVideo = (directVideoURL != nil)
        
        ZStack {
            Color.black
                .ignoresSafeArea()
                .zIndex(0)

            if isVideo, let videoURL = directVideoURL {
                videoContent(size: size, videoURL: videoURL)
            } else if let url = URL(string: post.mediaURL) {
                imageContent(size: size, url: url)
            } else {
                unavailableMediaView(isVideo: false)
                    .onAppear {
                        reportMediaReady()
                    }
            }
            
            // Username overlay in top-right corner
            topRightInfo(size: size)
                .zIndex(10)
        }
    }

    private struct VideoLoadingPlaceholder: View {
        let mediaKey: String

        var body: some View {
            ZStack {
                Color.black
                ProgressView()
                    .tint(.white)
            }
        }
    }

    @ViewBuilder
    private func videoContent(size: CGSize, videoURL: URL) -> some View {
        VideoPlayerContainer(
            url: videoURL,
            mediaKey: post.mediaURL,
            hudTimeControl: $debugPlayerTimeControl,
            hudItemStatus: $debugItemStatus,
            playbackStuck: $playbackStuck,
            onReadyToDisplay: reportMediaReady
        )
            .id(videoURL.absoluteString)
            .frame(width: size.width, height: size.height)
            .background(Color.black)
    }

    @ViewBuilder
    private func imageContent(size: CGSize, url: URL) -> some View {
        AsyncImage(url: url, transaction: Transaction(animation: .none)) { phase in
            switch phase {
            case .empty:
                ZStack {
                    Color.black
                    ProgressView()
                        .tint(.white)
                }
                .frame(width: size.width, height: size.height)
            case .success(let img):
                img
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .onAppear {
                        reportMediaReady()
                    }
            case .failure:
                unavailableMediaView(isVideo: false)
                    .frame(width: size.width, height: size.height)
                    .onAppear {
                        reportMediaReady()
                    }
            @unknown default:
                unavailableMediaView(isVideo: false)
                    .onAppear {
                        reportMediaReady()
                    }
            }
        }
        .id("image_\(post.id)_\(url.absoluteString)")
    }

    private func unavailableMediaView(isVideo: Bool) -> some View {
        ZStack {
            Color.black
            Image(systemName: isVideo ? "play.slash.fill" : "photo")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func reportMediaReady() {
        guard !didReportMediaReady else { return }
        didReportMediaReady = true
        onMediaReady()
    }

    private var playerHUD: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("player: \(debugTimeControlText)")
            Text("item: \(debugItemStatusText)")
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundColor(.white)
        .padding(8)
        .background(Color.black.opacity(0.55), in: Capsule())
        .padding(.top, 8)
        .padding(.leading, 12)
    }

    @ViewBuilder
    private var nonBlockingLoadingOverlay: some View {
        EmptyView()
    }

    private var mediaURLBadge: some View {
        Text(post.mediaURL)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundColor(.white.opacity(0.95))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
    }

    private func topRightInfo(size: CGSize) -> some View {
        HStack(spacing: 12) {
            // Left side: Flag + Channel emoji
            HStack(spacing: 8) {
                if let flag = post.countryFlag {
                    Text(flag)
                        .font(.system(size: 32))
                }
                // Channel emoji placeholder (you can pass this from FeedPost or derive from category)
                Text("🍔")  // This should come from the post's channel/category
                    .font(.system(size: 32))
            }
            
            // Right side: Username and coordinates
            VStack(alignment: .leading, spacing: 4) {
                Button(action: { onUserTapped(post.userID) }) {
                    Text(displayName.isEmpty ? "User" : displayName)
                        .font(.system(size: 20, weight: .bold, design: .default))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Text(String(format: "%.4f, %.4f", post.latitude, post.longitude))
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            Spacer()
        }
        .padding(.leading, 16)
        .padding(.top, 60)  // ✅ Increased from 40 to 60 to push label down
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(true)
    }
    
}
