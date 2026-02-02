import SwiftUI
import FirebaseFirestore
import AVKit
import CoreMedia
import CoreLocation
import UIKit

struct FeedView: View {
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var didSeedIfEmpty = false

    // Pagination
    private let pageSize = 5
    @State private var lastDocument: DocumentSnapshot?
    @State private var isLoadingMore = false
    @State private var reachedEnd = false

    // Current page
    @State private var currentIndex: Int = 0

    // Navigation to profile
    @State private var selectedUserID: String? = nil
    @State private var navigateToProfile = false

    // Username resolution cache (per-view state that consults the global actor)
    @State private var usernames: [String: String] = [:] // uid -> username
    @State private var usernameLoadsInProgress: Set<String> = []

    // Video preloading cache
    @State private var preloadedAssets: [String: AVURLAsset] = [:] // mediaURL string -> asset
    @State private var readyItems: Set<String> = [] // URLs that reached .readyToPlay

    // Fallback demo video to ensure we always have something to play
    private let fallbackFastVideoURL = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")

    // Gate: only render the current page at first, then widen to neighbors after first user scroll
    @State private var hasUserScrolledOnce = false

    // Debounce fast index changes to avoid rapid player start/stop thrash
    @State private var debouncedIndex: Int = 0

    @State private var impactHaptics = UIImpactFeedbackGenerator(style: .rigid)

    // Global mute toggle with persistence
    @AppStorage("FeedGlobalMute") private var isGloballyMuted: Bool = false
    @State private var lastHapticIndex: Int? = nil

    @Environment(\.scenePhase) private var scenePhase
    @State private var emptyStatePlayer: AVPlayer? = nil

    // Computed: current post
    private var currentPost: Post? {
        posts[safe: debouncedIndex]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                feedContent(in: geo.size)
                overlayChrome
                    .zIndex(10)
                profileNavigationLink
            }
            .background(Color.black)
        }
        .task {
            await reload()
            if posts.isEmpty, !didSeedIfEmpty {
                didSeedIfEmpty = true
                await seedAndReload()
            } else {
                prefetchVisibleUsernames()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .LoadFeedNow)) { _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ResetTabToTop)) { _ in
            currentIndex = 0
        }
        .onChange(of: currentIndex) { newIndex in
            // Debounce rapid changes to avoid player thrash
            let target = newIndex
            Task {
                try? await Task.sleep(nanoseconds: 80_000_000) // 80ms debounce
                await MainActor.run {
                    guard debouncedIndex != target else { return }
                    debouncedIndex = target
                    if lastHapticIndex != target {
                        lastHapticIndex = target
                        let notif = UINotificationFeedbackGenerator()
                        notif.notificationOccurred(.success)
                        impactHaptics.prepare()
                        impactHaptics.impactOccurred(intensity: 1.0)
                    }
                }
            }

            if let uid = posts[safe: newIndex]?.userID {
                maybeResolveUsername(for: uid)
            }
            if !hasUserScrolledOnce, !posts.isEmpty {
                hasUserScrolledOnce = true
            }
        }
        .onAppear {
            debouncedIndex = currentIndex
            impactHaptics.prepare()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RecordTabDidAppear"))) { _ in
            print("[Feed] Record tab appeared — pausing feed playback")
            Task { @MainActor in
                debouncedIndex = -1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RecordTabDidDisappear"))) { _ in
            print("[Feed] Record tab disappeared — optionally resume feed playback")
            Task { @MainActor in
                debouncedIndex = currentIndex
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FeedTabDidAppear"))) { _ in
            print("[Feed] Feed tab appeared — resuming feed playback")
            Task { @MainActor in
                debouncedIndex = currentIndex
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FeedTabDidDisappear"))) { _ in
            print("[Feed] Feed tab disappeared — pausing feed playback")
            Task { @MainActor in
                debouncedIndex = -1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FeedRefreshRequested"))) { _ in
            print("[Feed] Refresh requested — reloading feed")
            Task { await reload() }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                Task { @MainActor in
                    debouncedIndex = currentIndex
                    impactHaptics.prepare()
                    impactHaptics.impactOccurred(intensity: 1.0)
                }
            case .inactive, .background:
                Task { @MainActor in
                    debouncedIndex = -1
                }
            @unknown default:
                break
            }
        }
        .onAppear {
            print("[Feed] Appeared — refreshing feed to avoid repeated content")
            Task { await reload() }
        }
        .onDisappear {
            Task { @MainActor in
                debouncedIndex = -1
            }
        }
    }

    // MARK: - Split content to ease type-checking

    @ViewBuilder
    private func feedContent(in size: CGSize) -> some View {
        if posts.isEmpty {
            emptyFeedView(in: size)
                .ignoresSafeArea()
        } else {
            populatedFeedView(in: size)
                .ignoresSafeArea()
        }
    }

    private func emptyFeedView(in size: CGSize) -> some View {
        VerticalPager(currentIndex: .constant(0), pageCount: 1) {
            ZStack {
                if let url = fallbackFastVideoURL {
                    FillVideoPlayer(url: url, play: true, muted: isGloballyMuted)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    Color.black
                }
            }
            .frame(width: size.width, height: size.height)
            .background(Color.black)
        }
    }

    private func populatedFeedView(in size: CGSize) -> some View {
        VerticalPager(currentIndex: $currentIndex, pageCount: posts.count) {
            if let idx = pagesToDisplay.first, let post = posts[safe: idx] {
                let isActive: Bool = (debouncedIndex == idx)
                let shouldPlay: Bool = isActive
                let isMuted: Bool = isGloballyMuted || !isActive || debouncedIndex == -1
                let resolvedName: String = displayName(for: post)
                let isReady = readyItems.contains(post.mediaURL)
                let asset = preloadedAssets[post.mediaURL]

                FeedFullscreenPage(
                    post: post,
                    displayName: resolvedName,
                    onUserTapped: { userId in
                        selectedUserID = userId
                        navigateToProfile = true
                    },
                    isVideoReady: isReady,
                    preloadedAsset: asset,
                    shouldPlay: shouldPlay,
                    isMuted: isMuted
                )
                .id(post.id)
                .onAppear {
                    if isVideoURL(post.mediaURL) {
                        preloadVideoIfNeeded(for: post.mediaURL)
                    }
                    if let next = posts[safe: idx + 1], isVideoURL(next.mediaURL) {
                        preloadVideoIfNeeded(for: next.mediaURL)
                    }
                    maybeLoadMoreIfNeeded(appearingIndex: idx)
                    maybeResolveUsername(for: post.userID)

                    // Strong haptic on page activation (once per index)
                    if lastHapticIndex != idx {
                        lastHapticIndex = idx
                        let notif = UINotificationFeedbackGenerator()
                        notif.notificationOccurred(.success)
                        impactHaptics.prepare()
                        impactHaptics.impactOccurred(intensity: 1.0)
                    }
                }
            } else {
                Color.black
            }
        }
    }

    private var profileNavigationLink: some View {
        NavigationLink(
            isActive: $navigateToProfile,
            destination: {
                if let userId = selectedUserID {
                    AnyView(ProfileView(userID: userId))
                } else {
                    AnyView(Text("No user selected"))
                }
            },
            label: {
                EmptyView()
            }
        )
        .hidden()
    }

    private var pagesToDisplay: [Int] {
        guard !posts.isEmpty else { return [] }
        return [debouncedIndex].filter { $0 >= 0 && $0 < posts.count }
    }

    private var overlayChrome: some View {
        ZStack {
            VStack {
                HStack {
                    if isLoading || isLoadingMore {
                        ProgressView().tint(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .allowsHitTesting(false)

            VStack {
                Spacer()
                if isLoadingMore {
                    ProgressView()
                        .tint(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.4), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .padding(.trailing, 16)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .allowsHitTesting(false)

            VStack {
                Spacer()
                VStack(spacing: 14) {
                    Button {
                        if !posts.isEmpty {
                            currentIndex = max(0, currentIndex - 1)
                        }
                    } label: {
                        Circle().fill(Color.green).frame(width: 56, height: 56)
                            .overlay(Image(systemName: "arrow.up").foregroundColor(.white))
                    }
                    .buttonStyle(.plain)

                    Button {
                        print("Heart tapped for post: \(currentPost?.id ?? "nil")")
                    } label: {
                        Circle().fill(Color.pink).frame(width: 44, height: 44)
                            .overlay(Image(systemName: "heart.fill").foregroundColor(.white))
                    }
                    .buttonStyle(.plain)

                    Button {
                        if !posts.isEmpty {
                            currentIndex = min(posts.count - 1, currentIndex + 1)
                        }
                    } label: {
                        Circle().fill(Color.blue).frame(width: 56, height: 56)
                            .overlay(Image(systemName: "arrow.down").foregroundColor(.white))
                    }
                    .buttonStyle(.plain)

                    Button {
                        isGloballyMuted.toggle()
                    } label: {
                        Circle().fill(Color.white.opacity(0.2)).frame(width: 44, height: 44)
                            .overlay(Image(systemName: isGloballyMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").foregroundColor(.white))
                    }
                    .buttonStyle(.plain)

                    Button {
                        print("[Haptics] Test button tapped")
                        let notif = UINotificationFeedbackGenerator()
                        notif.prepare()
                        notif.notificationOccurred(.warning)
                        impactHaptics.prepare()
                        impactHaptics.impactOccurred(intensity: 1.0)
                    } label: {
                        RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.2)).frame(width: 120, height: 36)
                            .overlay(Text("Haptic Test").foregroundColor(.white).font(.system(size: 14, weight: .semibold)))
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .allowsHitTesting(true)
                .padding(.leading, 16)
                .padding(.bottom, 160)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .ignoresSafeArea()
    }

    // MARK: - Username helpers

    private func displayName(for post: Post) -> String {
        if let name = usernames[post.userID], !name.isEmpty {
            return name
        }
        // Fallback: a readable form of userID
        if post.userID.hasPrefix("fake_") || post.userID.hasPrefix("na_user_") || post.userID.hasPrefix("world_user_") {
            return post.userID.replacingOccurrences(of: "_", with: " ").uppercased()
        }
        // Shorten generic uid
        let short = post.userID.prefix(6)
        return "User \(short)"
    }

    private func maybeResolveUsername(for uid: String) {
        // Avoid duplicate fetches per-view
        if usernames[uid] != nil || usernameLoadsInProgress.contains(uid) { return }
        usernameLoadsInProgress.insert(uid)
        Task {
            let name = await UsernameCache.shared.username(for: uid)
            await MainActor.run {
                if let name, !name.isEmpty {
                    usernames[uid] = name
                }
                usernameLoadsInProgress.remove(uid)
            }
        }
    }

    private func prefetchVisibleUsernames() {
        for idx in pagesToDisplay {
            if let uid = posts[safe: idx]?.userID {
                maybeResolveUsername(for: uid)
            }
        }
    }

    // MARK: - Helpers for video readiness

    private func isVideoURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.contains("video")
    }

    private func preloadVideoIfNeeded(for urlString: String) {
        guard preloadedAssets[urlString] == nil, let url = URL(string: urlString) else { return }
        let asset = AVURLAsset(url: url)

        Task {
            do {
                async let playable: Bool = asset.load(.isPlayable)
                async let duration: CMTime = asset.load(.duration)
                let (isPlayable, dur) = try await (playable, duration)
                // Ensure we have a finite, non-zero duration for better readiness
                if isPlayable, dur.isNumeric, dur.seconds > 0.1 {
                    await MainActor.run {
                        preloadedAssets[urlString] = asset
                        readyItems.insert(urlString)
                    }
                }
            } catch {
                return
            }
        }
    }

    // MARK: - Data loading stubs (fill in with your real logic)

    private func reload() async {
        // Reset pagination state and load the first page.
        await MainActor.run {
            isLoading = true
            reachedEnd = false
            lastDocument = nil
            posts.removeAll()
            currentIndex = 0
            debouncedIndex = 0
        }

        // Simulate network delay for UX parity.
        try? await Task.sleep(nanoseconds: 250_000_000)

        // In lieu of Firestore, generate a page of demo posts.
        let newPosts = Self.generateDemoPosts(start: 0, count: pageSize)

        await MainActor.run {
            posts = newPosts
            isLoading = false
            // If we couldn't load anything, mark as reached end to stop paginating.
            reachedEnd = newPosts.isEmpty
            prefetchVisibleUsernames()
        }
    }

    private func seedAndReload() async {
        // For now, we simply create a few local demo posts and then call reload.
        // In a real app, you would write seed data to Firestore and then fetch.
        await MainActor.run {
            // No-op for local mode; `reload()` will generate demo posts.
        }
        await reload()
    }

    private func maybeLoadMoreIfNeeded(appearingIndex idx: Int) {
        // Trigger pagination when the user is within 1 item of the end.
        guard !isLoadingMore, !reachedEnd else { return }
        let thresholdIndex = max(0, posts.count - 3)
        guard idx >= thresholdIndex else { return }

        isLoadingMore = true
        Task {
            // Simulate network delay
            try? await Task.sleep(nanoseconds: 250_000_000)

            let start = posts.count
            let newPage = Self.generateDemoPosts(start: start, count: pageSize)

            await MainActor.run {
                posts.append(contentsOf: newPage)
                isLoadingMore = false
                reachedEnd = newPage.isEmpty
            }
        }
    }

    // MARK: - Demo data generator (local fallback)
    private static func generateDemoPosts(start: Int, count: Int) -> [Post] {
        guard count > 0 else { return [] }
        let totalCap = 30 // stop after ~30 to simulate end of feed
        let end = min(start + count, totalCap)
        guard start < end else { return [] }

        var result: [Post] = []
        for i in start..<end {
            let id = "demo_\(i)"
            let userID = i % 3 == 0 ? "fake_user_\(i)" : String(format: "user_%06d", i)
            let mediaURL: String
            let posterURL: String?
            if userID.hasPrefix("fake_user_") {
                mediaURL = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
                posterURL = "https://picsum.photos/id/\(i % 100)/800/1400"
            } else {
                mediaURL = "https://picsum.photos/id/\(i % 100)/1200/2000"
                posterURL = nil
            }
            let latitude = 37.3349 + Double(i % 5) * 0.01
            let longitude = -122.0090 - Double(i % 7) * 0.01
            let radius = [50, 100, 250, 500, 1000, 5000].randomElement() ?? 250

            // Construct a Post. This assumes your Post initializer or memberwise init.
            // If your Post is a struct with public memberwise init, this will compile.
            let post = Post(
                id: id,
                latitude: latitude,
                longitude: longitude,
                mediaURL: mediaURL,
                radius: radius,
                viewCount: radius,
                userID: userID,
                posterURL: posterURL
            )
            result.append(post)
        }
        return result
    }

}

private struct FeedFullscreenPage: View {
    let post: Post
    let displayName: String
    var onUserTapped: (String) -> Void

    let isVideoReady: Bool?
    let preloadedAsset: AVURLAsset?

    let shouldPlay: Bool
    let isMuted: Bool

    private var isVideo: Bool {
        let lower = post.mediaURL.lowercased()
        return lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.contains("video")
    }

    private var coordinateText: String {
        String(format: "%.4f, %.4f", post.latitude, post.longitude)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let poster = post.posterURL, let posterURL = URL(string: poster) {
                    AsyncImage(url: posterURL, transaction: Transaction(animation: .none)) { phase in
                        switch phase {
                        case .empty:
                            Color.black
                        case .success(let img):
                            img
                                .resizable()
                                .scaledToFill()
                                .clipped()
                        case .failure:
                            Color.black
                        @unknown default:
                            Color.black
                        }
                    }
                } else {
                    Color.black
                }

                Group {
                    // Render video as full-screen when media is a video; otherwise show image
                    if let url = URL(string: post.mediaURL) {
                        if post.mediaURL.lowercased().hasSuffix(".mp4") || post.mediaURL.lowercased().hasSuffix(".mov") || post.mediaURL.lowercased().contains("video") {
                            if (isVideoReady ?? false), let asset = preloadedAsset {
                                FillVideoPlayerAsset(asset: asset, play: shouldPlay, muted: isMuted)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            } else {
                                FillVideoPlayer(url: url, play: shouldPlay, muted: isMuted)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }
                        } else {
                            AsyncImage(url: url, transaction: Transaction(animation: .none)) { phase in
                                switch phase {
                                case .empty:
                                    ZStack { Color.black; ProgressView().tint(.white) }
                                case .success(let img):
                                    img
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: geo.size.width, height: geo.size.height)
                                        .clipped()
                                case .failure:
                                    ZStack {
                                        Color.black
                                        Image(systemName: "photo")
                                            .font(.system(size: 40, weight: .bold))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                @unknown default:
                                    Color.black
                                }
                            }
                            .id("image_\(post.id)_\(post.mediaURL)")
                        }
                    } else {
                        Color.black
                    }
                }
                .animation(.linear(duration: 0.15), value: isVideoReady ?? false)

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

                    Text(coordinateText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55), in: Capsule())
                }
                .padding(.trailing, 16)
                .padding(.top, geo.safeAreaInsets.top + 40)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
                .zIndex(10)

                VStack {
                    Spacer()
                    VerticalRadiusBar(
                        radius: post.radius,
                        maxRadius: 10_000,
                        width: 10,
                        maxHeight: 220,
                        color: .pink,
                        showsLabel: true,
                        labelFormat: { r in
                            r >= 1000 ? "\(r / 1000) km" : "\(r) m"
                        }
                    )
                    .frame(width: 10, height: 220, alignment: .bottom)
                    .padding(.trailing, 12)
                }
                .padding(.bottom, 45)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .trailing)
                .zIndex(10)
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color.black)
        }
        .ignoresSafeArea()
        .background(Color.black)
    }
}

private struct FillVideoPlayer: UIViewRepresentable {
    let url: URL
    var play: Bool
    var muted: Bool

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.configure(url: url, play: play, muted: muted)
        return v
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.configure(url: url, play: play, muted: muted)
    }
}

private struct FillVideoPlayerAsset: UIViewRepresentable {
    let asset: AVURLAsset
    var play: Bool
    var muted: Bool

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.configure(asset: asset, play: play, muted: muted)
        return v
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.configure(asset: asset, play: play, muted: muted)
    }
}

private final class PlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var endObserver: Any?
    private var currentAssetURL: URL?

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player?.pause()
        player = nil
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspectFill
        }
    }

    func configure(url: URL, play: Bool, muted: Bool) {
        if (player?.currentItem?.asset as? AVURLAsset)?.url != url {
            player = AVPlayer(url: url)
            player?.actionAtItemEnd = .none
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { [weak self] _ in
                self?.player?.seek(to: .zero)
                if play { self?.player?.play() }
            }
        }
        player?.isMuted = muted
        if play { player?.play() } else { player?.pause() }
    }

    func configure(asset: AVURLAsset, play: Bool, muted: Bool) {
        let url = asset.url
        if currentAssetURL != url {
            currentAssetURL = url
            let newItem = AVPlayerItem(asset: asset)
            if player == nil {
                player = AVPlayer(playerItem: newItem)
                player?.actionAtItemEnd = .none
            } else {
                player?.replaceCurrentItem(with: newItem)
            }
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: newItem, queue: .main) { [weak self] _ in
                self?.player?.seek(to: .zero)
                if play { self?.player?.play() }
            }
        }
        player?.isMuted = muted
        if play { player?.play() } else { player?.pause() }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

