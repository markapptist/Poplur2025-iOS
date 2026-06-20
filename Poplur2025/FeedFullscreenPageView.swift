//
//  FeedFullscreenPageView.swift
//  Fullscreen Feed Page with Video/Image Support
//

import SwiftUI
import Foundation
import AVFoundation
import AVKit
import CoreLocation
import FirebaseFirestore
import UIKit

// MARK: - Fullscreen Feed Page View

struct FeedFullscreenPageView: View {
    let post: FeedPost
    let displayName: String
    let channelNumber: Int
    let channelCategory: String
    let channelEmoji: String
    let channelIconAssetName: String?
    let isTVGuideVisible: Bool
    var onMediaReady: () -> Void = {}
    var onCreditsVisibilityChanged: (Bool) -> Void = { _ in }
    var onUserTapped: (String) -> Void

    @State private var imagePhaseDebug: String = ""
    @State private var debugPlayerTimeControl: AVPlayer.TimeControlStatus = .waitingToPlayAtSpecifiedRate
    @State private var debugItemStatus: AVPlayerItem.Status = .unknown
    @State private var didReportMediaReady = false
    @State private var imageLifecycleTask: Task<Void, Never>? = nil

    // Added for playback stuck detection and UI overlay
    @State private var forceVideoPlaceholder: Bool = false
    @State private var playbackStuck: Bool = false

    // Auto-cycles the username ↔ channel-number display like a TV ticker
    @State private var showChannelMode: Bool = false
    @ObservedObject private var settings = SettingsStore.shared
    private var displayAsChannel: Bool { showChannelMode || isTVGuideVisible }

    private var coordinateText: String {
        String(format: "%.4f, %.4f", post.latitude, post.longitude)
    }

    private var directVideoURL: URL? {
        guard localAssetName == nil else { return nil }
        guard let url = URL(string: post.mediaURL) else { return nil }
        let lower = url.absoluteString.lowercased()

        // Avoid playing Apple devstreaming fragments directly
        if lower.contains("devstreaming-cdn.apple.com"),
           lower.contains("filesequence"),
           lower.hasSuffix(".mp4") {
            return nil
        }

        // Strong video hints: explicit video extensions or HLS playlists
        let videoExtensions = [".mp4", ".mov", ".m4v", ".m3u8"]
        if videoExtensions.contains(where: { lower.hasSuffix($0) }) {
            return url
        }

        // Query and path hints that often indicate video
        let videoHints = ["/prog_index.m3u8", "video.mp4", "format=mp4", "format=hls", "type=video", "contentType=video", "mime=video"]
        if videoHints.contains(where: { lower.contains($0) }) {
            return url
        }

        // Image extensions that clearly indicate image
        let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".heic", ".webp"]
        if imageExtensions.contains(where: { lower.hasSuffix($0) }) {
            return nil
        }

        if lower.contains("picsum.photos") {
            return nil
        }

        // Ambiguous: prefer video to avoid treating recorded videos as photos
        return url
    }

    private enum MediaType { case video, image, unknown }
    private var mediaType: MediaType {
        if localAssetName != nil { return .image }
        if directVideoURL != nil { return .video }
        guard let url = URL(string: post.mediaURL) else { return .unknown }
        let lower = url.absoluteString.lowercased()
        let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".heic", ".webp"]
        if imageExtensions.contains(where: { lower.hasSuffix($0) }) { return .image }
        if lower.contains("picsum.photos") { return .image }
        return .unknown
    }

    private var localAssetName: String? {
        Self.localAssetName(from: post.mediaURL)
    }

    private static func localAssetName(from mediaURL: String) -> String? {
        let prefix = "asset://"
        guard mediaURL.hasPrefix(prefix) else { return nil }
        let name = String(mediaURL.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    // Replaced custom PlayerLayer with AVKit.VideoPlayer for reliability
    struct VideoPlayerContainer: View {
        let url: URL
        let mediaKey: String
        @Binding var hudTimeControl: AVPlayer.TimeControlStatus
        @Binding var hudItemStatus: AVPlayerItem.Status
        @Binding var playbackStuck: Bool
        let onReadyToDisplay: () -> Void
        let onCreditsVisibilityChanged: (Bool) -> Void
        @State private var player: AVPlayer? = nil
        @State private var itemObservation: NSKeyValueObservation? = nil

        @State private var timeObserver: Any? = nil
        @State private var endObserver: Any? = nil
        
        @State private var pauseObserver: Any? = nil

        @State private var itemFailed: Bool = false
        @State private var isReadyToDisplay: Bool = false
        @State private var creditsVisible: Bool = false

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
                        NotificationCenter.default.post(name: .FeedAdvanceOnMediaFailure, object: nil)
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
                self.setCreditsVisible(false)
                NotificationCenter.default.post(name: .FeedAdvanceToNextPost, object: nil)
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
                let duration = p.currentItem?.duration.seconds ?? 0
                guard duration.isFinite, duration > 2.0, time.seconds.isFinite else { return }
                let remaining = duration - time.seconds
                let leadTime = min(4.2, max(2.0, duration * 0.22))
                self.setCreditsVisible(remaining <= leadTime && remaining > 0.12)
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
            setCreditsVisible(false)
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

        private func setCreditsVisible(_ visible: Bool) {
            guard creditsVisible != visible else { return }
            creditsVisible = visible
            onCreditsVisibilityChanged(visible)
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
                .onChange(of: post.mediaURL) { _, _ in
                    // Reset readiness so freshly recorded media triggers playback/display
                    didReportMediaReady = false
                    cancelImageLifecycle()
                }
                .onDisappear {
                    cancelImageLifecycle()
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task(id: post.id) {
            // Continuously cycle username ↔ channel number like a TV ticker
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.5))
                guard !Task.isCancelled else { break }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    showChannelMode.toggle()
                }
            }
        }
    }

    @ViewBuilder
    private func contentView(size: CGSize) -> some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .zIndex(0)

            // Compute primary media view with reduced builder complexity
            let mediaView: AnyView = {
                switch mediaType {
                case .video:
                    if let videoURL = directVideoURL {
                        return AnyView(
                            videoContent(size: size, videoURL: videoURL)
                                .id("video_\(post.id)_\(videoURL.absoluteString)")
                        )
                    } else {
                        return AnyView(
                            unavailableMediaView(isVideo: true)
                                .onAppear { reportMediaReady() }
                        )
                    }
                case .image:
                    if let assetName = localAssetName {
                        return AnyView(
                            localAssetImageContent(size: size, assetName: assetName)
                                .id("asset_\(post.id)_\(assetName)")
                        )
                    } else if let url = URL(string: post.mediaURL) {
                        return AnyView(
                            imageContent(size: size, url: url)
                                .id("image_\(post.id)_\(url.absoluteString)")
                        )
                    } else {
                        return AnyView(
                            unavailableMediaView(isVideo: false)
                                .onAppear { reportMediaReady() }
                        )
                    }
                case .unknown:
                    if let videoURL = directVideoURL {
                        return AnyView(
                            videoContent(size: size, videoURL: videoURL)
                                .id("video_\(post.id)_\(videoURL.absoluteString)")
                        )
                    } else if let assetName = localAssetName {
                        return AnyView(
                            localAssetImageContent(size: size, assetName: assetName)
                                .id("asset_\(post.id)_\(assetName)")
                        )
                    } else if let url = URL(string: post.mediaURL) {
                        return AnyView(
                            imageContent(size: size, url: url)
                                .id("image_\(post.id)_\(url.absoluteString)")
                        )
                    } else {
                        return AnyView(
                            unavailableMediaView(isVideo: false)
                                .onAppear { reportMediaReady() }
                        )
                    }
                }
            }()

            mediaView

            // Username overlay in top-right corner
            topRightInfo(size: size)
                .zIndex(10)

            if shouldShowCaptions {
                aiCaptionOverlay(size: size)
                    .zIndex(12)
            }

            if post.isPoplurAd {
                poplurAdInfo
                    .zIndex(11)
            }
        }
    }

    private struct VideoLoadingPlaceholder: View {
        let mediaKey: String

        var body: some View {
            Color.black
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
            onReadyToDisplay: reportMediaReady,
            onCreditsVisibilityChanged: onCreditsVisibilityChanged
        )
            .id(videoURL.absoluteString)
            .frame(width: size.width, height: size.height)
            .background(Color.black)
    }

    @ViewBuilder
    private func imageContent(size: CGSize, url: URL) -> some View {
        FullBleedRemoteImage(url: url, size: size, onReady: reportMediaReady)
            .id("image_\(post.id)_\(url.absoluteString)")
    }

    @ViewBuilder
    private func localAssetImageContent(size: CGSize, assetName: String) -> some View {
        if let image = UIImage(named: assetName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .onAppear { reportMediaReady() }
        } else {
            unavailableMediaView(isVideo: false)
                .onAppear { reportMediaReady() }
        }
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
        scheduleImageLifecycleIfNeeded()
    }

    private func scheduleImageLifecycleIfNeeded() {
        guard mediaType != .video else {
            cancelImageLifecycle()
            return
        }
        imageLifecycleTask?.cancel()
        onCreditsVisibilityChanged(false)
        imageLifecycleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_300_000_000)
            guard !Task.isCancelled else { return }
            onCreditsVisibilityChanged(true)

            try? await Task.sleep(nanoseconds: 3_700_000_000)
            guard !Task.isCancelled else { return }
            onCreditsVisibilityChanged(false)
            NotificationCenter.default.post(name: .FeedAdvanceToNextPost, object: post.id)
        }
    }

    private func cancelImageLifecycle() {
        imageLifecycleTask?.cancel()
        imageLifecycleTask = nil
        onCreditsVisibilityChanged(false)
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

    private var shouldShowCaptions: Bool {
        settings.closedCaptionsEnabled && !post.isPoplurAd && mediaType == .video
    }

    private func aiCaptionOverlay(size: CGSize) -> some View {
        VStack(spacing: 6) {
            Text(AITranslationCaptionProvider.caption(
                for: post,
                channelCategory: channelCategory,
                preferredLanguage: settings.preferredLanguage
            ))
            .font(.system(size: min(size.width * 0.045, 19), weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: .black.opacity(0.85), radius: 4, x: 0, y: 2)

            Text(AITranslationCaptionProvider.translationBadge(
                for: post,
                preferredLanguage: settings.preferredLanguage
            ))
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: min(size.width - 40, 520))
        .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 126)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: settings.preferredLanguage)
        .animation(.easeInOut(duration: 0.2), value: settings.closedCaptionsEnabled)
    }

    private func topRightInfo(size: CGSize) -> some View {
        HStack(spacing: 12) {
            // Left side: Flag + Channel emoji
            HStack(spacing: 8) {
                if let flag = post.countryFlag {
                    Text(flag)
                        .font(.system(size: 32))
                }
                if post.isPoplurAd {
                    Text("AD")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                } else {
                    ChannelAssetIcon(assetName: channelIconAssetName, fallbackEmoji: channelEmoji, size: 38, fallbackFontSize: 32)
                }
            }
            
            // Right side: Username and coordinates
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .leading) {
                    Button(action: { onUserTapped(post.userID) }) {
                        Text(post.isPoplurAd ? "Poplur Ad" : (displayName.isEmpty ? "User" : displayName))
                            .font(.system(size: 20, weight: .bold, design: .default))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .opacity(displayAsChannel ? 0 : 1)
                    .offset(y: displayAsChannel ? -10 : 0)

                    Text("CH \(channelNumber)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.31, green: 1.0, blue: 0.25))
                        .opacity(displayAsChannel ? 1 : 0)
                        .offset(y: displayAsChannel ? 0 : 10)
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: displayAsChannel)

                ZStack(alignment: .leading) {
                    Text(post.isPoplurAd ? (post.adCreativeKind?.uppercased() ?? "AI CREATIVE") : String(format: "%.4f, %.4f", post.latitude, post.longitude))
                        .font(.system(size: 16, weight: .regular, design: .default))
                        .foregroundColor(.white.opacity(0.9))
                        .opacity(displayAsChannel ? 0 : 1)
                        .offset(y: displayAsChannel ? -8 : 0)

                    Text(channelCategory.uppercased())
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 0.31, green: 1.0, blue: 0.25))
                        .opacity(displayAsChannel ? 1 : 0)
                        .offset(y: displayAsChannel ? 0 : 8)
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.82).delay(0.03), value: displayAsChannel)
            }
            .frame(minWidth: 150, alignment: .leading)
            
            Spacer()
        }
        .padding(.leading, 16)
        .padding(.top, 60)  // ✅ Increased from 40 to 60 to push label down
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(true)
    }

    private var poplurAdInfo: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("POPLUR AD")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .tracking(0)

            Text(post.adHeadline ?? "See what is happening nearby")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            if let body = post.adBody, !body.isEmpty {
                Text(body)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(3)
            }

            Text(post.adCallToAction ?? "Open Poplur")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 17)
                .padding(.vertical, 9)
                .background(Color.white, in: Capsule())
                .padding(.top, 3)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 138)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.62)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.62), radius: 12, x: 0, y: 5)
        .allowsHitTesting(false)
    }
    
}

private struct FullBleedRemoteImage: View {
    let url: URL
    let size: CGSize
    let onReady: () -> Void

    @State private var loadState: FullBleedImageLoadState = .loading

    var body: some View {
        ZStack {
            Color.black

            switch loadState {
            case .loading:
                EmptyView()
            case .loaded(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .transition(.opacity)
            case .failed:
                Image(systemName: "photo")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: url.absoluteString) {
            await loadImage()
        }
    }

    private func loadImage() async {
        await MainActor.run { loadState = .loading }

        do {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                let (remoteData, _) = try await URLSession.shared.data(from: url)
                data = remoteData
            }

            guard !Task.isCancelled else { return }
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }

            if image.hasLikelyBlackBars {
                await MainActor.run {
                    loadState = .failed
                    onReady()
                    NotificationCenter.default.post(
                        name: .FeedAdvanceOnMediaFailure,
                        object: nil
                    )
                }
                return
            }

            await MainActor.run {
                withAnimation(.easeIn(duration: 0.35)) {
                    loadState = .loaded(image)
                }
                onReady()
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                loadState = .failed
                onReady()
            }
        }
    }
}

private enum FullBleedImageLoadState {
    case loading
    case loaded(UIImage)
    case failed
}

private extension UIImage {
    var hasLikelyBlackBars: Bool {
        guard let cgImage else { return false }

        let sampleWidth = min(max(cgImage.width, 1), 96)
        let sampleHeight = min(max(cgImage.height, 1), 96)
        guard sampleWidth >= 24, sampleHeight >= 24 else { return false }

        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let didDrawSample = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: sampleWidth,
                    height: sampleHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else {
                return false
            }

            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
            return true
        }

        guard didDrawSample else { return false }

        let stripHeight = max(2, Int(Double(sampleHeight) * 0.07))
        let stripWidth = max(2, Int(Double(sampleWidth) * 0.07))
        let centerX = (sampleWidth / 4)..<max(sampleWidth / 4 + 1, sampleWidth * 3 / 4)
        let centerY = (sampleHeight / 4)..<max(sampleHeight / 4 + 1, sampleHeight * 3 / 4)

        func darkRatio(xRange: Range<Int>, yRange: Range<Int>) -> Double {
            var darkPixels = 0
            var countedPixels = 0

            for y in yRange {
                for x in xRange {
                    let index = y * bytesPerRow + x * bytesPerPixel
                    let red = Int(pixels[index])
                    let green = Int(pixels[index + 1])
                    let blue = Int(pixels[index + 2])
                    let alpha = Int(pixels[index + 3])
                    guard alpha > 32 else { continue }

                    countedPixels += 1
                    let brightness = (red + green + blue) / 3
                    if brightness < 28 {
                        darkPixels += 1
                    }
                }
            }

            guard countedPixels > 0 else { return 0 }
            return Double(darkPixels) / Double(countedPixels)
        }

        let top = darkRatio(xRange: 0..<sampleWidth, yRange: 0..<stripHeight)
        let bottom = darkRatio(xRange: 0..<sampleWidth, yRange: (sampleHeight - stripHeight)..<sampleHeight)
        let left = darkRatio(xRange: 0..<stripWidth, yRange: 0..<sampleHeight)
        let right = darkRatio(xRange: (sampleWidth - stripWidth)..<sampleWidth, yRange: 0..<sampleHeight)
        let center = darkRatio(xRange: centerX, yRange: centerY)

        let hasLetterbox = top > 0.96 && bottom > 0.96
        let hasPillarbox = left > 0.96 && right > 0.96
        return (hasLetterbox || hasPillarbox) && center < 0.75
    }
}
