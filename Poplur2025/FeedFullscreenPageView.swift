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
    var onUserTapped: (String) -> Void

    @State private var imagePhaseDebug: String = ""
    @State private var debugPlayerTimeControl: AVPlayer.TimeControlStatus = .waitingToPlayAtSpecifiedRate
    @State private var debugItemStatus: AVPlayerItem.Status = .unknown

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
        @Binding var hudTimeControl: AVPlayer.TimeControlStatus
        @Binding var hudItemStatus: AVPlayerItem.Status
        @Binding var playbackStuck: Bool
        @State private var player: AVPlayer? = nil
        @State private var itemObservation: NSKeyValueObservation? = nil
        @State private var queuePlayer: AVQueuePlayer? = nil
        @State private var looper: AVPlayerLooper? = nil

        @State private var timeObserver: Any? = nil
        
        @State private var pauseObserver: Any? = nil

        @State private var itemFailed: Bool = false

        private func setupPlayer() {
            guard player == nil, queuePlayer == nil else { return }
            
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

            let isMP4 = url.absoluteString.lowercased().hasSuffix(".mp4")

            if isMP4 {
                // Use AVQueuePlayer + AVPlayerLooper for seamless mp4 looping
                let asset = AVURLAsset(url: url)
                _ = ["playable"]
                asset.resourceLoader.preloadsEligibleContentKeys = true

                let q = AVQueuePlayer()
                q.allowsExternalPlayback = false
                q.isMuted = false
                q.automaticallyWaitsToMinimizeStalling = true
                q.preventsDisplaySleepDuringVideoPlayback = true

                // Load required key using modern async API
                Task { [self] in
                    do {
                        let playable = try await asset.load(.isPlayable)
                        guard playable else {
                            await MainActor.run {
                                self.itemFailed = true
                                self.playbackStuck = true
                            }
                            print("[Video] MP4 asset not playable")
                            NotificationCenter.default.post(name: Notification.Name("FeedAdvanceOnMediaFailure"), object: nil)
                            return
                        }
                        let item = AVPlayerItem(asset: asset)
                        item.preferredForwardBufferDuration = 0
                        q.automaticallyWaitsToMinimizeStalling = false

                        await MainActor.run {
                            self.itemObservation = item.observe(\.status, options: [.initial, .new]) { _, _ in
                                self.hudItemStatus = item.status
                                print("[Video] MP4 item status: \(item.status.rawValue)")
                                switch item.status {
                                case .readyToPlay:
                                    self.itemFailed = false
                                    self.playbackStuck = false
                                    q.removeAllItems()
                                    self.looper = AVPlayerLooper(player: q, templateItem: item)
                                    self.player = q
                                    q.seek(to: CMTime(seconds: 0.01, preferredTimescale: 600))
                                    FeedAudioManager.shared.playExclusively(q)
                                    self.hudTimeControl = q.timeControlStatus
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        if q.timeControlStatus != .playing {
                                            q.seek(to: CMTime(seconds: 0.02, preferredTimescale: 600))
                                            q.playImmediately(atRate: 1.0)
                                            self.hudTimeControl = q.timeControlStatus
                                            if q.timeControlStatus == .playing { self.playbackStuck = false }
                                        }
                                    }
                                case .failed:
                                    self.itemFailed = true
                                    if let err = item.error { print("[Video] MP4 item failed: \(err)") }
                                case .unknown:
                                    break
                                @unknown default:
                                    break
                                }
                            }
                        }
                    } catch {
                        await MainActor.run { self.playbackStuck = true }
                        print("[Video] MP4 asset load failed: \(error)")
                        NotificationCenter.default.post(name: Notification.Name("FeedAdvanceOnMediaFailure"), object: nil)
                    }
                }
            } else {
                // HLS or other stream types: standard AVPlayer with end observer
                let asset = AVURLAsset(url: url)
                _ = ["playable"]
                asset.resourceLoader.preloadsEligibleContentKeys = true

                // Load required key using modern async API
                Task { [self] in
                    do {
                        let playable = try await asset.load(.isPlayable)
                        guard playable else {
                            await MainActor.run { self.playbackStuck = true }
                            print("[Video] HLS asset not playable")
                            NotificationCenter.default.post(name: Notification.Name("FeedAdvanceOnMediaFailure"), object: nil)
                            return
                        }
                        let item = AVPlayerItem(asset: asset)
                        item.preferredForwardBufferDuration = 0
                        let p = AVPlayer(playerItem: item)
                        p.allowsExternalPlayback = false
                        p.isMuted = false
                        p.automaticallyWaitsToMinimizeStalling = false
                        p.preventsDisplaySleepDuringVideoPlayback = true

                        await MainActor.run {
                            self.itemObservation = item.observe(\.status, options: [.initial, .new]) { _, _ in
                                self.hudItemStatus = item.status
                                print("[Video] Item status changed to: \(item.status.rawValue)")
                                switch item.status {
                                case .readyToPlay:
                                    self.itemFailed = false
                                    self.playbackStuck = false
                                    let current = self.player ?? p
                                    current.seek(to: CMTime(seconds: 0.01, preferredTimescale: 600))
                                    FeedAudioManager.shared.playExclusively(current)
                                    current.playImmediately(atRate: 1.0)
                                    self.hudTimeControl = current.timeControlStatus
                                case .failed:
                                    self.itemFailed = true
                                    if let err = item.error { print("[Video] Item failed: \(err)") }
                                case .unknown:
                                    break
                                @unknown default:
                                    break
                                }
                            }

                            self.player = p
                            FeedAudioManager.shared.register(p)

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.hudTimeControl = p.timeControlStatus }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.hudTimeControl = p.timeControlStatus }
                        }
                    } catch {
                        await MainActor.run { self.playbackStuck = true }
                        print("[Video] HLS asset load failed: \(error)")
                        NotificationCenter.default.post(name: Notification.Name("FeedAdvanceOnMediaFailure"), object: nil)
                    }
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
            Group {
                if let player {
                    PlayerLayerView(player: player)
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
                } else {
                    Color.black
                }
            }
            .onAppear {
                setupPlayer()
            }
            .onDisappear {
                if let token = pauseObserver {
                    NotificationCenter.default.removeObserver(token)
                    pauseObserver = nil
                }
                self.playbackStuck = false
                if let obs = timeObserver, let p = player {
                    p.removeTimeObserver(obs)
                }
                timeObserver = nil
                player?.pause()
                (player as? AVQueuePlayer)?.removeAllItems()
                player = nil
                queuePlayer = nil
                looper = nil
                itemObservation = nil
            }
            .overlay(
                Group {
                    if itemFailed {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 28, weight: .bold))
                            Text("Video failed to start. Showing placeholder.")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(12)
                        .background(Color.black.opacity(0.7), in: Capsule())
                        .foregroundColor(.white)
                    } else if playbackStuck {
                        LinearGradient(colors: [.clear, .white.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
            )
        }
    }

    struct PlayerLayerView: UIViewRepresentable {
        let player: AVPlayer?

        func makeUIView(context: Context) -> PlayerHostingView {
            let view = PlayerHostingView()
            view.backgroundColor = .black
            view.translatesAutoresizingMaskIntoConstraints = false
            view.playerLayer.videoGravity = .resizeAspect
            view.player = player
            return view
        }

        func updateUIView(_ uiView: PlayerHostingView, context: Context) {
            uiView.player = player
            uiView.playerLayer.videoGravity = .resizeAspect
            uiView.setNeedsLayout()
            uiView.layoutIfNeeded()
        }
    }

    final class PlayerHostingView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
            playerLayer.videoGravity = .resizeAspect
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .zIndex(0)

            if isVideo, let videoURL = directVideoURL {
                videoContent(size: size, videoURL: videoURL)
            } else if let url = URL(string: post.mediaURL) {
                imageContent(size: size, url: url)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Invalid media URL")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }

    @ViewBuilder
    private func videoContent(size: CGSize, videoURL: URL) -> some View {
        VideoPlayerContainer(url: videoURL, hudTimeControl: $debugPlayerTimeControl, hudItemStatus: $debugItemStatus, playbackStuck: $playbackStuck)
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
                        .scaleEffect(1.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            case .success(let img):
                img
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
            case .failure:
                ZStack {
                    Color.black
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.yellow)
                        Text("Image failed to load")
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            @unknown default:
                Color.black
            }
        }
        .id("image_\(post.id)_\(url.absoluteString)")
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
        // Show a subtle shimmer when playback appears stuck; explicit failure UI is handled inside VideoPlayerContainer
        if playbackStuck {
            LinearGradient(colors: [.clear, .white.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
                .transition(.opacity)
        } else {
            EmptyView()
        }
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
        VStack(alignment: .trailing, spacing: 6) {
            Button(action: { onUserTapped(post.userID) }) {
                Text(displayName.isEmpty ? "User" : displayName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Text(String(format: "%.4f, %.4f", post.latitude, post.longitude))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.55), in: Capsule())
        }
        .padding(.trailing, 16)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(true)
    }
}
