import SwiftUI
import FirebaseFirestore
import CoreLocation
import UIKit
import AVFoundation
import AVKit
import Contacts
import SpriteKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

private actor GeocodeCountryCache {
    private var values: [String: String] = [:]

    func value(for key: String) -> String? {
        values[key]
    }

    func store(_ value: String, for key: String) {
        values[key] = value
    }
}

// MARK: - PERFORMANCE OPTIMIZATION STRATEGY
// 1. INSTANT INITIALIZATION: Bootstrap is fully synchronous - no async/await delays
// 2. DEFAULT COUNTRY: Start with US (index 0) immediately, geocode in background
// 3. LAZY PROFILE GENERATION: Profile posts are generated on-demand when viewed
// 4. BACKGROUND TASKS ONLY: Storage, username prefetch, geocoding all happen AFTER UI is ready
// 5. ZERO BLOCKING: All data generation is lightweight array construction (< 1ms)

struct FeedView: View {
    @Environment(\.layoutPreviewMode) private var layoutPreviewMode
    var homeChromeInactive: Bool = false

    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var cubeSkinStore = CubeSkinStore.shared
    @StateObject private var fallbackLocationProvider = LocationProvider()
    @StateObject private var poleModel = PolePositionModel()
    private var activeLocationProvider: LocationProvider { fallbackLocationProvider }

    @State private var posts: [FeedPost] = []
    @State private var isLoading = false
    @State private var didSeedIfEmpty = false
    @State private var didBootstrap = false
    @State private var isFeedReady = false  // Added as per instruction
    @State private var isVideoLoading = false  // Track video loading state for logo indicator
    @State private var showInitialLoadingScreen = true
    @State private var showFeedEntryLogo = true
    @State private var feedEntryLogoTask: Task<Void, Never>? = nil
    // Only true once the first post's media fires onMediaReady — gates hideInitialLoadingScreen
    @State private var firstMediaReady = false

    // Pagination
    private let pageSize = 5
    @State private var lastDocument: DocumentSnapshot?
    @State private var isLoadingMore = false
    @State private var reachedEnd = false

    // Current page
    @State private var currentIndex: Int = 0

    // Removed navigation state - now using tab-based navigation via notification

    // Username resolution cache (per-view state that consults the global actor)
    @State private var usernames: [String: String] = [:] // uid -> username
    @State private var usernameLoadsInProgress: Set<String> = []

    // Drag gesture and haptics
    @State private var dragTranslation: CGFloat = 0
    @State private var hapticGenerator = UIImpactFeedbackGenerator(style: .rigid)
    @State private var notifHaptics = UINotificationFeedbackGenerator()
    @State private var dragAxis: Axis? = nil
    private enum Axis { case horizontal, vertical }
    
    @State private var popPlayer: AVAudioPlayer? = nil

    @State private var showHeart: Bool = false
    @State private var likedPostIDs: Set<String> = []
    @State private var localLikeBoosts: [String: Int] = [:]
    
    // Instagram-style timeline view
    @State private var showTimelineView: Bool = false
    @State private var isFlippingTimeline: Bool = false
    @State private var showTVGuide: Bool = false
    @State private var tvGuideActivePlayer: AVPlayer? = nil
    @State private var breakingNewsConfettiTrigger: Int = 0
    @State private var showCommentCredits: Bool = false
    @State private var postComments: [String: [FeedCommentCredit]] = [:]
    @State private var isTVTransitionVisible: Bool = false
    @State private var tvTransitionOpacity: Double = 0.0
    @State private var tvTransitionChannelNumber: Int = 101
    @State private var tvTransitionChannelCategory: String = "Food"
    @State private var tvTransitionToken: Int = 0
    @State private var deliveryPost: FeedPost?

    // AI host bumper
    @ObservedObject private var bumper = BumperService.shared
    @State private var activeBumperPayload: BumperPayload? = nil
    @State private var presentedBumperPostIDs: Set<String> = []
    @State private var lastBumperPresentedAt: Date = .distantPast
    private let minimumBumperSpacing: TimeInterval = 45

    // Country paging (horizontal swipe)
    @State private var selectedCountryIndex: Int = 0
    private let countries: [(code: String, name: String, flag: String)] = [
        ("US","United States","🇺🇸"), ("CA","Canada","🇨🇦"), ("MX","Mexico","🇲🇽"), ("BR","Brazil","🇧🇷"), ("AR","Argentina","🇦🇷"), ("CL","Chile","🇨🇱"), ("GB","United Kingdom","🇬🇧"), ("IE","Ireland","🇮🇪"), ("FR","France","🇫🇷"), ("DE","Germany","🇩🇪"), ("ES","Spain","🇪🇸"), ("IT","Italy","🇮🇹"), ("PT","Portugal","🇵🇹"), ("NL","Netherlands","🇳🇱"), ("BE","Belgium","🇧🇪"), ("SE","Sweden","🇸🇪"), ("NO","Norway","🇳🇴"), ("FI","Finland","🇫🇮"), ("DK","Denmark","🇩🇰"), ("PL","Poland","🇵🇱"), ("CZ","Czechia","🇨🇿"), ("AT","Austria","🇦🇹"), ("CH","Switzerland","🇨🇭"), ("GR","Greece","🇬🇷"), ("TR","Türkiye","🇹🇷"), ("RU","Russia","🇷🇺"), ("UA","Ukraine","🇺🇦"), ("CN","China","🇨🇳"), ("JP","Japan","🇯🇵"), ("KR","South Korea","🇰🇷"), ("IN","India","🇮🇳"), ("PK","Pakistan","🇵🇰"), ("ID","Indonesia","🇮🇩"), ("AU","Australia","🇦🇺"), ("NZ","New Zealand","🇳🇿"), ("SA","Saudi Arabia","🇸🇦"), ("AE","UAE","🇦🇪"), ("EG","Egypt","🇪🇬"), ("ZA","South Africa","🇿🇦"), ("NG","Nigeria","🇳🇬"), ("KE","Kenya","🇰🇪"), ("MA","Morocco","🇲🇦"), ("TN","Tunisia","🇹🇳"), ("IL","Israel","🇮🇱"), ("IR","Iran","🇮🇷"), ("TH","Thailand","🇹🇭"), ("VN","Vietnam","🇻🇳"), ("PH","Philippines","🇵🇭"), ("MY","Malaysia","🇲🇾"), ("SG","Singapore","🇸🇬"), ("TW","Taiwan","🇹🇼"), ("HK","Hong Kong","🇭🇰")
    ]
    
    // Channel/Category paging (vertical swipe)
    @State private var selectedChannelIndex: Int = 0
    @State private var activeFeedChannelButton: FeedChannelButtonKind? = nil
    @State private var feedChannelButtonPressToken: Int = 0
    @AppStorage("poplur_feedChannelButtonsSpriteKit2D") private var useSpriteKitFeedChannelButtons: Bool = false
    private let channels: [(id: String, number: Int, name: String, emoji: String, iconAssetName: String)] = [
        ("food", 101, "Food", "🍔", "poplur_channel_101_food"),
        ("beauty", 103, "Beauty", "💄", "poplur_channel_103_beauty"),
        ("sports", 104, "Sports", "⚽", "poplur_channel_104_sports"),
        ("modelling", 105, "Modelling", "📸", "poplur_channel_105_modelling"),
        ("fashion", 106, "Fashion", "👗", "poplur_channel_106_fashion"),
        ("music", 107, "Music", "🎵", "poplur_channel_107_music"),
        ("tech", 108, "Tech", "💻", "poplur_channel_108_tech"),
        ("news", 109, "News", "📰", "poplur_channel_109_news"),
        ("french", 110, "French", "🇫🇷", "poplur_channel_110_french"),
        ("spanish", 111, "Spanish", "🇪🇸", "poplur_channel_111_spanish"),
        ("shopping", 112, "Shopping", "🛍️", "poplur_channel_112_shopping"),
        ("cartoon", 113, "Cartoon", "🎨", "poplur_channel_113_cartoon"),
        ("kids", 114, "Kids", "🧸", "poplur_channel_114_kids"),
        ("comedy", 115, "Comedy", "😂", "poplur_channel_115_comedy")
    ]

    private func countryIndex(for coordinate: CLLocationCoordinate2D?) -> Int {
        guard let coordinate else { return 0 }
        // Very lightweight mapping by rough longitude/latitude bands to pick a nearby country from our list.
        // This is a placeholder heuristic for demo purposes.
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        // Prefer a few common regions first (check Canada before USA to avoid defaulting to US near the border)
        if lat > 49 && lat < 84 && lon > -141 && lon < -52 { return countries.firstIndex { $0.code == "CA" } ?? 0 }
        if lat > 24 && lat < 49 && lon > -125 && lon < -66 { return countries.firstIndex { $0.code == "US" } ?? 0 }
        if lat > 42 && lat < 84 && lon > -10 && lon < 40 { return countries.firstIndex { $0.code == "FR" } ?? 0 }
        if lat > 35 && lat < 72 && lon > -10 && lon < 30 { return countries.firstIndex { $0.code == "DE" } ?? 0 }
        if lat > -44 && lat < -10 && lon > 112 && lon < 154 { return countries.firstIndex { $0.code == "AU" } ?? 0 }
        if lat > 8 && lat < 37 && lon > 68 && lon < 97 { return countries.firstIndex { $0.code == "IN" } ?? 0 }
        if lat > 3 && lat < 54 && lon > 73 && lon < 135 { return countries.firstIndex { $0.code == "CN" } ?? 0 }
        if lat > 24 && lat < 46 && lon > 123 && lon < 146 { return countries.firstIndex { $0.code == "JP" } ?? 0 }
        if lat > -35 && lat < 6 && lon > -74 && lon < -34 { return countries.firstIndex { $0.code == "BR" } ?? 0 }
        if lat > 49 && lat < 60 && lon > -141 && lon < -52 { return countries.firstIndex { $0.code == "CA" } ?? 0 }
        // Fallbacks by hemisphere
        if lon >= -30 && lon <= 60 { return countries.firstIndex { $0.code == "GB" } ?? 0 }
        if lon > 60 && lon < 120 { return countries.firstIndex { $0.code == "IN" } ?? 0 }
        if lon >= 120 { return countries.firstIndex { $0.code == "JP" } ?? 0 }
        return 0
    }

    // Equatable proxy for coordinate changes
    private var coordinateKey: String {
        if let c = activeLocationProvider.coordinate {
            return String(format: "%.6f,%.6f", c.latitude, c.longitude)
        } else {
            return "nil"
        }
    }
    
    // Simple cache for geocoding results to avoid redundant network calls
    private static let geocodeCache = GeocodeCountryCache()
    
    // Resolve ISO country code from coordinate using reverse geocoding (with caching)
    private func geocodeCountry(from coordinate: CLLocationCoordinate2D) async -> String? {
        // Cache key based on rounded coordinates (to ~1km precision)
        let cacheKey = String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude)
        
        // Check cache first
        if let cached = await Self.geocodeCache.value(for: cacheKey) {
            print("[Geocode] Using cached result for \(cacheKey): \(cached)")
            return cached
        }
        
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let pm = placemarks.first, let isoCode = pm.isoCountryCode {
                await Self.geocodeCache.store(isoCode, for: cacheKey)
                return isoCode
            }
        } catch {
            print("[Geocode] reverseGeocode failed: \(error)")
        }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                ZStack {
                    if showTimelineView {
                        FeedTwitterTimelineView(
                            posts: posts,
                            displayNameProvider: { post in displayName(for: post) },
                            onPostTapped: { index in
                                currentIndex = index
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showTimelineView = false
                                }
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            toggleTimelineFlip()
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(10)
                    } else {
                        feedContent(in: geo.size)
                            .opacity(1)
                            .zIndex(5)
                            .background(Color.black)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }


                }
                .animation(.spring(response: 0.48, dampingFraction: 0.82), value: showTimelineView)

                // TV static covers the black while the first frame buffers.
                // Removed instantly (no transition) once isReadyForDisplay fires.
                if showInitialLoadingScreen {
                    TVStaticLoopingView()
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .zIndex(50)
                        .transition(.identity)
                }

                if showFeedEntryLogo {
                    FeedEntryLogoPopView()
                        .allowsHitTesting(false)
                        .zIndex(100)
                        .transition(.opacity)
                }

                if showCommentCredits,
                   !showTimelineView,
                   !showTVGuide,
                   let currentPost = posts[safe: currentIndex] {
                    FeedCommentCreditsOverlay(
                        comments: commentsForCredits(for: currentPost),
                        displayName: displayName(for: currentPost)
                    )
                    .id("\(currentPost.id)-\(postComments[currentPost.id]?.count ?? 0)")
                    .zIndex(850_000)
                    .transition(.opacity)
                }

                if isTVTransitionVisible {
                    PoplurTransitionFlash(
                        channelNumber: tvTransitionChannelNumber,
                        channelCategory: tvTransitionChannelCategory
                    )
                        .id(tvTransitionToken)
                        .opacity(tvTransitionOpacity)
                        .zIndex(1_200_000)
                }

                if showTVGuide {
                    FeedTVGuideView(
                        channels: tvGuideChannels,
                        currentChannelID: currentChannel.id,
                        currentPostName: currentPostDisplayName,
                        activeFeedPlayer: tvGuideActivePlayer,
                        onDismiss: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                showTVGuide = false
                            }
                        },
                        onChannelSelected: { channel in
                            openTVGuideChannel(channel)
                        }
                    )
                    .zIndex(1_000_000)
                    .transition(.opacity)
                }

                FeedBreakingNewsConfettiOverlay(trigger: breakingNewsConfettiTrigger)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .zIndex(1_000_100)
            }
            .background(Color.black)
        }
        .task {
            if layoutPreviewMode {
                applyPreviewFeedData()
                return
            }
            // If the cover is already gone (returning to feed from another tab), nothing to do.
            guard showInitialLoadingScreen else { return }
            NotificationCenter.default.post(name: Notification.Name("FeedLaunchLoadingDidStart"), object: nil)
            if !didBootstrap {
                await runStrictBootstrap()
            }
            // Minimum cover display time — let the animation play for at least 1.5 s.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            firstMediaReady = true
            hideInitialLoadingScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: .LoadFeedNow)) { _ in
            Task {
                if didBootstrap {
                    await reload()
                } else {
                    await runStrictBootstrap()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ResetTabToTop)) { _ in
            currentIndex = 0
            publishCurrentPostMetrics(duration: 0.35)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FeedRefreshRequested"))) { _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .FeedAdvanceOnMediaFailure)) { _ in
            advanceToNextPost()
        }
        .onReceive(NotificationCenter.default.publisher(for: .FeedAdvanceToNextPost)) { _ in
            advanceToNextPost()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ProfileViewDismissed"))) { _ in
            // Restore feed radius when returning from profile
            if let post = posts[safe: currentIndex] {
                print("📱 [Feed] ProfileViewDismissed - restoring radius to \(post.radius)m")
                publishCurrentPostMetrics(duration: 0.6)
            } else if posts.isEmpty {
                print("📱 [Feed] ProfileViewDismissed - no posts, setting radius to 0")
                publishEmptyPostMetrics(duration: 0.3)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleTimelineView"))) { _ in
            toggleTimelineFlip()
        }
        .onReceive(NotificationCenter.default.publisher(for: .FeedOpenTVGuide)) { _ in
            guard !posts.isEmpty else { return }
            noteFeedInteraction()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                showTimelineView = false
                showTVGuide = true
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            NotificationCenter.default.post(name: .FeedTVGuideBecameVisible, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .PoplurAIGoToFeedChannel)) { notification in
            guard let query = notification.userInfo?["query"] as? String else { return }
            openPoplurAIChannel(query: query)
        }
        .onReceive(NotificationCenter.default.publisher(for: .FeedOpenNews)) { _ in
            guard !posts.isEmpty else { return }
            openNewsTimelineWithoutSpin()
        }
        .onReceive(NotificationCenter.default.publisher(for: .FeedLikeCurrentPost)) { _ in
            guard !showTimelineView else { return }
            likeCurrentPost()
        }
        .onReceive(NotificationCenter.default.publisher(for: .FeedOpenCurrentPostProfile)) { _ in
            openCurrentPostUserProfile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .FeedCommentSubmitted)) { notification in
            guard let text = notification.object as? String else { return }
            addCommentToCurrentPost(text)
        }
        .background(feedNotificationReceivers)
        .background {
            if let payload = activeBumperPayload {
                FeedBumperView(payload: payload) {
                    activeBumperPayload = nil
                }
            }
        }
        .sheet(item: $deliveryPost) { post in
            DeliveryFlowView(post: post, displayName: displayName(for: post))
        }
    }

    // MARK: - Notification receivers (split to help Swift type-checker)

    private var feedNotificationReceivers: some View {
        Color.clear
            .onChange(of: currentIndex) { _, newIndex in
                showCommentCredits = false
                guard newIndex >= 0, newIndex < posts.count else {
                    print("[Feed] currentIndex out of range: \(newIndex) posts=\(posts.count)")
                    return
                }
                let uid = posts[newIndex].userID
                maybeResolveUsername(for: uid)

                let post = posts[newIndex]
                print("📱 [Feed] Showing post at index \(newIndex), radius: \(post.radius)m")
                publishCurrentPostMetrics(duration: 0.6)

                presentBumper(for: post)
                prefetchUpcomingBumpers(from: newIndex)

                NotificationCenter.default.post(name: Notification.Name("FeedVideoDidAdvance"), object: nil)
            }
            .onAppear {
                handleFeedReceiversAppear()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if posts.isEmpty {
                    let newPosts = Self.generateDemoPostsForCountryAndChannel(
                        country: countries[selectedCountryIndex].code,
                        channel: channels[selectedChannelIndex].id,
                        start: 0,
                        count: pageSize
                    )
                    posts = newPosts
                    isFeedReady = !newPosts.isEmpty
                    hideInitialLoadingScreen()
                    if newPosts.first != nil {
                        publishCurrentPostMetrics(duration: 0.0)
                    }
                    let postsToStore = newPosts
                    Task.detached(priority: .utility) {
                        DemoPostStore.shared.store(postsToStore)
                    }
                }
            }
            .onChange(of: coordinateKey) {
                Task { @MainActor in
                    guard let coord = self.activeLocationProvider.coordinate else { return }
                    let finalIdx = self.countryIndex(for: coord)
                    guard finalIdx != self.selectedCountryIndex else { return }
                    self.selectedCountryIndex = finalIdx
                    await self.reloadForCountry()
                }
            }
            .onChange(of: selectedChannelIndex) { _, idx in
                let ch = channels[safe: idx] ?? channels[0]
                NotificationCenter.default.post(
                    name: .FeedChannelDidChange,
                    object: nil,
                    userInfo: ["id": ch.id, "name": ch.name, "emoji": ch.emoji]
                )
            }
            .onChange(of: showTVGuide) { _, visible in
                tvGuideActivePlayer = visible ? FeedAudioManager.shared.activePlayer : nil
                NotificationCenter.default.post(name: .MainTabChildRouteVisibilityChanged, object: visible)
                if !visible {
                    NotificationCenter.default.post(name: .FeedTVGuideBecameHidden, object: nil)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ActiveFeedPlayerDidChange)) { notification in
                guard showTVGuide else { return }
                tvGuideActivePlayer = notification.object as? AVPlayer
            }
            .onDisappear {
                feedEntryLogoTask?.cancel()
                feedEntryLogoTask = nil
                showFeedEntryLogo = false
                tvGuideActivePlayer = nil
                FeedAudioManager.shared.activePlayer?.pause()
                NotificationCenter.default.post(name: .MainTabChildRouteVisibilityChanged, object: false)
            }
    }

    private func handleFeedReceiversAppear() {
        guard !layoutPreviewMode else { return }
        publishSelectedChannel()
        showBriefFeedEntryLogo()
        triggerBreakingNewsArrival()
        hapticGenerator.prepare()
        notifHaptics.prepare()
        seedPostsForActiveSelectionIfNeeded()
        presentBumperForCurrentPostIfNeeded()

        if !posts.isEmpty && !isFeedReady {
            print("[Feed] onAppear - restoring feed ready state")
            isFeedReady = true
        }
        publishCurrentPostMetrics(duration: 0.35)

        // Resume playback when returning to feed tab
        FeedAudioManager.shared.activePlayer?.play()
    }

    private func publishSelectedChannel() {
        let ch = channels[safe: selectedChannelIndex] ?? channels[0]
        NotificationCenter.default.post(
            name: .FeedChannelDidChange,
            object: nil,
            userInfo: ["id": ch.id, "name": ch.name, "emoji": ch.emoji]
        )
    }

    private func seedPostsForActiveSelectionIfNeeded() {
        guard posts.isEmpty else { return }
        let newPosts = Self.generateDemoPostsForCountryAndChannel(
            country: countries[selectedCountryIndex].code,
            channel: channels[selectedChannelIndex].id,
            start: 0,
            count: pageSize
        )
        posts = newPosts
        isFeedReady = !newPosts.isEmpty
        hideInitialLoadingScreen()
        if newPosts.first != nil {
            publishCurrentPostMetrics(duration: 0.0)
        }
        storeDemoPosts(newPosts)
    }

    private func presentBumperForCurrentPostIfNeeded() {
        guard let post = posts[safe: currentIndex] else { return }
        presentBumper(for: post)
        prefetchUpcomingBumpers(from: currentIndex)
    }

    private func presentBumper(for post: FeedPost) {
        guard !showTimelineView, !showTVGuide else { return }
        guard activeBumperPayload == nil else { return }
        guard !presentedBumperPostIDs.contains(post.id) else { return }
        let now = Date()
        guard now.timeIntervalSince(lastBumperPresentedAt) >= minimumBumperSpacing else { return }
        presentedBumperPostIDs.insert(post.id)
        lastBumperPresentedAt = now

        let channel = channels[safe: selectedChannelIndex]
        let payload = bumper.activate(
            post,
            channelName: channel?.name ?? "General",
            channelID: channel?.id ?? ""
        )
        activeBumperPayload = payload
    }

    private func prefetchUpcomingBumpers(from index: Int) {
        guard bumper.isConfigured, activeBumperPayload == nil else { return }
        let channel = channels[safe: selectedChannelIndex]
        let channelName = channel?.name ?? "General"
        let channelID = channel?.id ?? ""
        for offset in 1...1 {
            if let next = posts[safe: index + offset] {
                bumper.prefetch(next, channelName: channelName, channelID: channelID)
            }
        }
    }

    private func storeDemoPosts(_ posts: [FeedPost]) {
        Task.detached(priority: .utility) {
            DemoPostStore.shared.store(posts)
        }
    }

    // MARK: - Strict bootstrap sequence
    @MainActor
    private func runStrictBootstrap() async {
        guard didBootstrap == false else { return }
        didBootstrap = true

        // INSTANT: Set default country immediately (US as safe default)
        selectedCountryIndex = 0  // US default
        let countryCode = countries[selectedCountryIndex].code
        let channelID = channels[selectedChannelIndex].id
        let pageSize = self.pageSize
        
        let newPosts = Self.generateDemoPostsForCountryAndChannel(
            country: countryCode,
            channel: channelID,
            start: 0,
            count: pageSize
        )

        // Update UI SYNCHRONOUSLY - no await needed
        posts = newPosts
        isFeedReady = !posts.isEmpty
        currentIndex = 0
        isVideoLoading = false
        poleModel.position = PolePosition(x: 0.5, y: 0.5)
        // Note: hideInitialLoadingScreen() is called by the .task after a minimum display time

        // Update radius bar immediately
        if newPosts.first != nil {
            publishCurrentPostMetrics(duration: 0.0)
        }
        
        // ALL background tasks happen AFTER UI is ready
        Task.detached(priority: .utility) {
            // Store posts
            DemoPostStore.shared.store(newPosts)
            
            // Prefetch usernames
            let uids = newPosts.map { $0.userID }
            await UsernameCache.shared.prefetch(uids: uids)
        }
        
        // Adjust by current location after first paint without leaving the main actor.
        Task { @MainActor in
            guard let coord = self.activeLocationProvider.coordinate else { return }
            let finalIdx = self.countryIndex(for: coord)
            guard finalIdx != self.selectedCountryIndex else { return }
            self.selectedCountryIndex = finalIdx
            await self.reload()
        }
    }

    // MARK: - Split content to ease type-checking

    @ViewBuilder
    private func feedContent(in size: CGSize) -> some View {
        ZStack {
            if posts.isEmpty {
                emptyFeedView(in: size)
                    .onAppear { }
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .local)
                            .onChanged { value in
                                if dragAxis == nil {
                                    noteFeedInteraction()
                                    dragAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                                    hapticGenerator.prepare()
                                    notifHaptics.prepare()
                                }
                                switch dragAxis {
                                case .horizontal:
                                    dragTranslation = value.translation.width
                                case .vertical:
                                    dragTranslation = value.translation.height
                                case .none:
                                    dragTranslation = 0
                                }
                            }
                            .onEnded { value in
                                let horizontalThreshold: CGFloat = 60
                                let verticalThreshold: CGFloat = 60
                                if let axis = dragAxis {
                                    switch axis {
                                    case .horizontal:
                                        if value.translation.width <= -horizontalThreshold {
                                            // swipe left -> next country
                                            flashTransition()
                                            selectedCountryIndex = (selectedCountryIndex + 1) % countries.count
                                            currentIndex = 0
                                            Task {
                                                await reloadForCountry()
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                                hapticGenerator.impactOccurred(intensity: 1.0)
                                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                                notifHaptics.notificationOccurred(.success)
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            }
                                            hapticGenerator.prepare()
                                            notifHaptics.prepare()
                                            playOneShotPop()
                                            maybeShowAd()
                                        } else if value.translation.width >= horizontalThreshold {
                                            // swipe right -> previous country
                                            flashTransition()
                                            selectedCountryIndex = (selectedCountryIndex - 1 + countries.count) % countries.count
                                            currentIndex = 0
                                            Task {
                                                await reloadForCountry()
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                                hapticGenerator.impactOccurred(intensity: 1.0)
                                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                                notifHaptics.notificationOccurred(.success)
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            }
                                            hapticGenerator.prepare()
                                            notifHaptics.prepare()
                                            playOneShotPop()
                                            maybeShowAd()
                                        }
                                    case .vertical:
                                        if value.translation.height <= -verticalThreshold {
                                            // swipe up -> next post
                                            pulseFeedChannelButton(.up)
                                            if !posts.isEmpty {
                                                flashTransition()
                                                currentIndex = min(currentIndex + 1, posts.count - 1)
                                                maybeLoadMoreIfNeeded(appearingIndex: currentIndex)
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                                hapticGenerator.impactOccurred(intensity: 1.0)
                                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                                notifHaptics.notificationOccurred(.success)
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            }
                                            hapticGenerator.prepare()
                                            notifHaptics.prepare()
                                            playOneShotPop()
                                            maybeShowAd()
                                        } else if value.translation.height >= verticalThreshold {
                                            // swipe down -> previous channel
                                            pulseFeedChannelButton(.down)
                                            let nextChannelIndex = (selectedChannelIndex - 1 + channels.count) % channels.count
                                            flashTransition(targetChannelIndex: nextChannelIndex)
                                            selectedChannelIndex = nextChannelIndex
                                            currentIndex = 0
                                            Task {
                                                await reloadForChannel()
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                                hapticGenerator.impactOccurred(intensity: 1.0)
                                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                                notifHaptics.notificationOccurred(.success)
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            }
                                            hapticGenerator.prepare()
                                            notifHaptics.prepare()
                                            playOneShotPop()
                                            maybeShowAd()
                                        }
                                    }
                                }
                                dragAxis = nil
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    dragTranslation = 0
                                }
                            }
                    )
            } else {
                populatedFeedView(in: size)
                    .onAppear { }
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .local)
                            .onChanged { value in
                                if dragAxis == nil {
                                    noteFeedInteraction()
                                    dragAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                                    hapticGenerator.prepare()
                                    notifHaptics.prepare()
                                }
                                switch dragAxis {
                                case .horizontal:
                                    dragTranslation = value.translation.width
                                case .vertical:
                                    dragTranslation = value.translation.height
                                case .none:
                                    dragTranslation = 0
                                }
                            }
                            .onEnded { value in
                                let horizontalThreshold: CGFloat = 60
                                let verticalThreshold: CGFloat = 60
                                if let axis = dragAxis {
                                    switch axis {
                                    case .horizontal:
                                        if value.translation.width <= -horizontalThreshold {
                                            // swipe left -> next country
                                            flashTransition()
                                            selectedCountryIndex = (selectedCountryIndex + 1) % countries.count
                                            currentIndex = 0
                                            Task {
                                                await reloadForCountry()
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                                hapticGenerator.impactOccurred(intensity: 1.0)
                                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                                notifHaptics.notificationOccurred(.success)
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            }
                                            hapticGenerator.prepare()
                                            notifHaptics.prepare()
                                            playOneShotPop()
                                            maybeLoadMoreIfNeeded(appearingIndex: currentIndex)
                                            maybeShowAd()
                                        } else if value.translation.width >= horizontalThreshold {
                                            // swipe right -> previous country
                                            flashTransition()
                                            selectedCountryIndex = (selectedCountryIndex - 1 + countries.count) % countries.count
                                            currentIndex = 0
                                            Task {
                                                await reloadForCountry()
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                                hapticGenerator.impactOccurred(intensity: 1.0)
                                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                                notifHaptics.notificationOccurred(.success)
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            }
                                            hapticGenerator.prepare()
                                            notifHaptics.prepare()
                                            playOneShotPop()
                                            maybeShowAd()
                                        }
                                    case .vertical:
                                        if value.translation.height <= -verticalThreshold {
                                            // swipe up -> next post
                                            pulseFeedChannelButton(.up)
                                            if !posts.isEmpty {
                                                flashTransition()
                                                currentIndex = min(currentIndex + 1, posts.count - 1)
                                                maybeLoadMoreIfNeeded(appearingIndex: currentIndex)
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                                hapticGenerator.impactOccurred(intensity: 1.0)
                                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                                notifHaptics.notificationOccurred(.success)
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            }
                                            hapticGenerator.prepare()
                                            notifHaptics.prepare()
                                            playOneShotPop()
                                            maybeShowAd()
                                        } else if value.translation.height >= verticalThreshold {
                                            // swipe down -> previous post
                                            pulseFeedChannelButton(.down)
                                            if !posts.isEmpty {
                                                flashTransition()
                                                currentIndex = max(currentIndex - 1, 0)
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                                hapticGenerator.impactOccurred(intensity: 1.0)
                                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                                notifHaptics.notificationOccurred(.success)
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            }
                                            hapticGenerator.prepare()
                                            notifHaptics.prepare()
                                            playOneShotPop()
                                            maybeShowAd()
                                        }
                                    }
                                }
                                dragAxis = nil
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    dragTranslation = 0
                                }
                            }
                    )
                    .onLongPressGesture(minimumDuration: 0.5) {
                        // Long press to show post location on map with user annotation
                        if let post = posts[safe: currentIndex] {
                            let coordinate = CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude)
                            print("📍 [FeedView] Long press - showing post location: \(coordinate.latitude), \(coordinate.longitude)")
                            if let city = post.cityName, let country = post.countryName {
                                print("   Location: \(city), \(country) \(post.countryFlag ?? "")")
                            }
                            print("   Radius: \(Int(post.radius))m")
                            
                            // Haptic feedback
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            
                            // Get username and profile image URL, then prepare notification
                            Task {
                                let username = await UsernameCache.shared.username(for: post.userID)
                                
                                // Get profile image URL if available
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
                                    print("⚠️ [FeedView] Failed to fetch profile image: \(error.localizedDescription)")
                                }
                                #endif
                                #endif
                                
                                // Prepare user info with coordinate as CLLocationCoordinate2D
                                var userInfo: [String: Any] = [
                                    "coordinate": coordinate,  // Use coordinate object
                                    "userID": post.userID,
                                    "username": username ?? displayName(for: post),
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
                                
                                print("📍 [FeedView] Posting ShowLocationOnMap with coordinate: \(coordinate.latitude), \(coordinate.longitude)")
                                print("   Username: \(username ?? displayName(for: post)), Profile URL: \(profileImageURL ?? "nil")")
                                
                                // ALSO store in MapStateManager for when MapView isn't loaded yet
                                print("📍 [FeedView] Setting pending post location in MapStateManager")
                                MapStateManager.shared.setPendingPostLocation(
                                    coordinate,
                                    userID: post.userID,
                                    username: username ?? displayName(for: post),
                                    profileImageURL: profileImageURL,
                                    radius: Double(post.radius),
                                    cityName: post.cityName,
                                    countryName: post.countryName,
                                    countryFlag: post.countryFlag
                                )
                                
                                await MainActor.run {
                                    // First, send location to map
                                    NotificationCenter.default.post(
                                        name: Notification.Name("ShowLocationOnMap"),
                                        object: nil,
                                        userInfo: userInfo
                                    )
                                }
                                
                                // Wait a moment for map to process location
                                try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
                                
                                await MainActor.run {
                                    // Then switch to map tab
                                    NotificationCenter.default.post(
                                        name: Notification.Name("SwitchToMapTab"),
                                        object: nil
                                    )
                                }
                            }
                        }
                    }
            }

            // Non-interactive heart animation
            if showHeart {
                Image(systemName: "heart.fill")
                    .poplurIconShader()
                    .font(.system(size: 120, weight: .bold))
                    .foregroundStyle(.red)
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
                    .zIndex(20)
            }

        }
    }

    private func emptyFeedView(in size: CGSize) -> some View {
        Color.black
            .frame(width: size.width, height: size.height)
    }

    private func populatedFeedView(in size: CGSize) -> some View {
        ZStack {
            if let post = posts[safe: currentIndex] {
                FeedFullscreenPageView(
                    post: post,
                    displayName: displayName(for: post),
                    channelNumber: currentChannelNumber,
                    channelCategory: currentChannel.name,
                    channelEmoji: currentChannel.emoji,
                    channelIconAssetName: currentChannel.iconAssetName,
                    isTVGuideVisible: showTVGuide,
                    onMediaReady: {
                        firstMediaReady = true
                        hideInitialLoadingScreen()
                    },
                    onCreditsVisibilityChanged: { visible in
                        guard posts[safe: currentIndex]?.id == post.id else { return }
                        setCommentCreditsVisible(visible)
                    },
                    onUserTapped: { uid in
                        print("👤 [FeedView] User tapped - userID: '\(uid)'")
                        guard !uid.hasPrefix("poplur_ad_") else {
                            print("📢 [FeedView] Poplur ad tapped - reserved for ad CTA routing")
                            return
                        }
                        guard !uid.isEmpty else {
                            print("⚠️ [FeedView] Cannot navigate to profile - userID is empty")
                            return
                        }
                        // Post notification to switch to profile tab with this userID
                        NotificationCenter.default.post(
                            name: .ShowUserProfile,
                            object: uid
                        )
                    }
                )
                .id(post.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .clipped()
                .background(Color.black)

                if isDeliveryEligible(post), !showTVGuide {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            DeliverToMeButton {
                                noteFeedInteraction()
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                deliveryPost = post
                            }
                            .padding(.trailing, 22)
                            .padding(.bottom, 214)
                        }
                    }
                    .zIndex(42)
                }
            } else {
                Color.black
            }
        }
    }
    

    private var tvGuideChannels: [FeedTVGuideChannel] {
        let fallbackNames = [
            "Mia", "Jay", "Alex Johnson", "Samira Khan", "Diego Morales",
            "Mina Park", "Noah Lee", "Ava Chen", "Kai Brooks", "Leo Vance",
            "Priya Sen", "Carlos R", "Yuki T", "Fatima Al"
        ]
        let programs = [
            "Live posts", "Street check-in", "Creator spotlight", "Radius live",
            "City pulse", "Trending now", "Late feed", "Local signal", "Fresh uploads"
        ]
        let channelCount = channels.count

        return channels.enumerated().map { index, channel in
            // Primary post (one per channel, in order)
            let primaryPost = posts[safe: index]
            let fallbackUser = fallbackNames[index % fallbackNames.count]
            let userID = primaryPost?.isPoplurAd == true ? "tv_\(channel.id)_user" : (primaryPost?.userID ?? "tv_\(channel.id)_user")
            let resolvedPrimary = primaryPost.map { displayName(for: $0) }
            let primaryName = primaryPost?.isPoplurAd == true
                ? "Poplur"
                : ((resolvedPrimary?.isEmpty == false && resolvedPrimary != "Sponsored") ? (resolvedPrimary ?? fallbackUser) : fallbackUser)

            // Additional names: round-robin through remaining posts
            var collectedNames: [String] = [primaryName]
            var round = 1
            while collectedNames.count < 5 {
                let postIndex = index + round * channelCount
                if let post = posts[safe: postIndex] {
                    let name = post.isPoplurAd ? "Poplur" : displayName(for: post)
                    if !name.isEmpty && name != "Sponsored" && !collectedNames.contains(name) {
                        collectedNames.append(name)
                    }
                } else {
                    let fb = fallbackNames[(index + round * 3) % fallbackNames.count]
                    if !collectedNames.contains(fb) { collectedNames.append(fb) }
                }
                round += 1
                if round > 6 { break }
            }

            let language = AITranslationCaptionProvider.sourceLanguage(for: channel.id)
            let program = language == .english
                ? programs[index % programs.count]
                : "\(language.displayName) language reel"

            return FeedTVGuideChannel(
                id: channel.id,
                number: channel.number,
                emoji: channel.emoji,
                category: channel.name,
                iconAssetName: channel.iconAssetName,
                userID: userID,
                username: primaryName,
                usernames: collectedNames,
                program: program,
                videoURL: primaryPost.flatMap { URL(string: $0.mediaURL) }
            )
        }
    }

    private var currentChannel: (id: String, number: Int, name: String, emoji: String, iconAssetName: String) {
        channels[safe: selectedChannelIndex] ?? channels[0]
    }

    private var currentChannelNumber: Int {
        currentChannel.number
    }

    private var currentPostDisplayName: String {
        guard let post = posts[safe: currentIndex] else { return "Live feed" }
        return displayName(for: post)
    }

    private func isDeliveryEligible(_ post: FeedPost) -> Bool {
        let userID = post.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !post.isPoplurAd
            && !post.isLiveStream
            && !userID.isEmpty
            && !userID.hasPrefix("poplur_ad_")
            && !userID.hasPrefix("sponsored_ad_")
    }

    private func toggleTimelineFlip() {
        guard !isFlippingTimeline else { return }
        noteFeedInteraction()
        showTVGuide = false
        playOneShotPop()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
        isFlippingTimeline = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                showTimelineView.toggle()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            isFlippingTimeline = false
        }
    }

    private func openNewsTimelineWithoutSpin() {
        noteFeedInteraction()
        showTVGuide = false
        guard !showTimelineView else { return }

        playOneShotPop()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showTimelineView = true
            isFlippingTimeline = false
        }
    }

    private func noteFeedInteraction() {
        NotificationCenter.default.post(name: .FeedUserInteraction, object: nil)
    }

    private func pulseFeedChannelButton(_ button: FeedChannelButtonKind) {
        feedChannelButtonPressToken += 1
        let token = feedChannelButtonPressToken
        activeFeedChannelButton = button

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            guard token == feedChannelButtonPressToken else { return }
            activeFeedChannelButton = nil
        }
    }

    private func changeFeedChannel(_ direction: FeedChannelButtonKind) {
        guard direction != .ch else { return }
        noteFeedInteraction()
        showCommentCredits = false
        pulseFeedChannelButton(direction)

        let step = direction == .up ? 1 : -1
        let nextChannelIndex = (selectedChannelIndex + step + channels.count) % channels.count
        flashTransition(targetChannelIndex: nextChannelIndex)
        selectedChannelIndex = nextChannelIndex
        currentIndex = 0

        Task { @MainActor in
            await reloadForChannel()
        }

        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.95)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        playOneShotPop()
    }

    private func openPoplurAIChannel(query: String) {
        let normalized = query
            .lowercased()
            .replacingOccurrences(of: "modeling", with: "modelling")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let targetIndex = channels.firstIndex(where: { channel in
            let channelName = channel.name.lowercased()
            return channel.id == normalized
                || channelName == normalized
                || "\(channel.number)" == normalized
                || normalized.contains(channel.id)
                || normalized.contains(channelName)
                || normalized.contains("\(channel.number)")
        }) else { return }

        noteFeedInteraction()
        showCommentCredits = false
        flashTransition(targetChannelIndex: targetIndex)
        selectedChannelIndex = targetIndex
        currentIndex = 0

        Task { @MainActor in
            await reloadForChannel()
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        playOneShotPop()
    }

    private func likeCurrentPost() {
        guard let post = posts[safe: currentIndex] else { return }
        noteFeedInteraction()

        if !likedPostIDs.contains(post.id) {
            likedPostIDs.insert(post.id)
            localLikeBoosts[post.id, default: 0] += 1
        }

        playOneShotPop()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.9)
        publishCurrentPostMetrics(duration: 0.18)

        withAnimation(.spring(response: 0.18, dampingFraction: 0.62)) {
            showHeart = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
            withAnimation(.easeOut(duration: 0.24)) {
                showHeart = false
            }
        }
    }

    private func addCommentToCurrentPost(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let post = posts[safe: currentIndex] else { return }
        noteFeedInteraction()
        postComments[post.id, default: []].append(
            FeedCommentCredit(username: "You", text: trimmed)
        )
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func commentsForCredits(for post: FeedPost) -> [FeedCommentCredit] {
        FeedCommentCredit.seedComments(for: post.id, displayName: displayName(for: post)) +
        postComments[post.id, default: []]
    }

    private func setCommentCreditsVisible(_ visible: Bool) {
        guard showCommentCredits != visible else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            showCommentCredits = visible
        }
    }

    /// Flashes the Poplur TV static tune card to mask post/channel/country changes.
    private func flashTransition(targetChannelIndex: Int? = nil) {
        let channelIndex = targetChannelIndex ?? selectedChannelIndex
        let targetChannel = channels[safe: channelIndex] ?? channels[0]
        tvTransitionChannelNumber = 101 + channelIndex
        tvTransitionChannelCategory = targetChannel.name
        tvTransitionToken += 1
        isTVTransitionVisible = true
        tvTransitionOpacity = 1.0

        let token = tvTransitionToken
        let fadeDuration: TimeInterval = 0.06
        // Fade out near the end of the stripe animation — abandon if a newer transition took over
        DispatchQueue.main.asyncAfter(deadline: .now() + kCommercialTransitionDuration - fadeDuration) {
            guard token == tvTransitionToken else { return }
            withAnimation(.easeOut(duration: fadeDuration)) {
                tvTransitionOpacity = 0.0
            }
        }
        // Hide after the full commercial duration
        DispatchQueue.main.asyncAfter(deadline: .now() + kCommercialTransitionDuration) {
            guard token == tvTransitionToken else { return }
            isTVTransitionVisible = false
        }
    }

    private func advanceToNextPost() {
        guard !posts.isEmpty else { return }
        showCommentCredits = false
        flashTransition()
        if currentIndex < max(0, posts.count - 1) {
            currentIndex += 1
            maybeLoadMoreIfNeeded(appearingIndex: currentIndex)
        } else {
            currentIndex = 0
            publishCurrentPostMetrics(duration: 0.3)
        }
    }

    private func openTVGuideChannel(_ channel: FeedTVGuideChannel) {
        noteFeedInteraction()
        if let index = channels.firstIndex(where: { $0.id == channel.id }) {
            flashTransition(targetChannelIndex: index)
            selectedChannelIndex = index
            Task { @MainActor in
                await reloadForChannel()
            }
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            showTVGuide = false
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @MainActor
    private func showBriefFeedEntryLogo() {
        feedEntryLogoTask?.cancel()
        showFeedEntryLogo = true
        feedEntryLogoTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                showFeedEntryLogo = false
            }
            feedEntryLogoTask = nil
        }
    }

    // MARK: - Username helpers

    @MainActor
    private func hideInitialLoadingScreen() {
        guard showInitialLoadingScreen else { return }
        guard firstMediaReady else { return }
        withAnimation(.easeOut(duration: 0.45)) {
            showInitialLoadingScreen = false
        }
        NotificationCenter.default.post(name: Notification.Name("FeedLaunchLoadingDidFinish"), object: nil)
    }

    private func displayName(for post: FeedPost) -> String {
        if post.isPoplurAd || post.userID.hasPrefix("poplur_ad_") || post.userID.hasPrefix("sponsored_ad_") {
            return "Poplur Ad"
        }
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

    @MainActor
    private func applyPreviewFeedData() {
        guard posts.isEmpty else { return }
        let previewPosts = [
            FeedPost(
                id: "preview-feed-0",
                latitude: 40.7128,
                longitude: -74.0060,
                mediaURL: "preview://feed/video-0.mp4",
                radius: 5_000,
                viewCount: 42,
                userID: "preview_creator_0",
                cityName: "New York",
                countryName: "United States",
                countryFlag: "🇺🇸"
            ),
            FeedPost(
                id: "preview-feed-1",
                latitude: 43.6532,
                longitude: -79.3832,
                mediaURL: "preview://feed/image-1.jpg",
                radius: 12_000,
                viewCount: 31,
                userID: "preview_creator_1",
                cityName: "Toronto",
                countryName: "Canada",
                countryFlag: "🇨🇦"
            )
        ]
        posts = previewPosts
        usernames = [
            "preview_creator_0": "PREVIEW CREATOR",
            "preview_creator_1": "CITY CREATOR"
        ]
        currentIndex = 0
        didBootstrap = true
        isFeedReady = true
        isLoading = false
        isVideoLoading = false
        reachedEnd = true
    }

    private func maybeResolveUsername(for uid: String) {
        // Guard against empty UIDs
        guard !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard !uid.hasPrefix("poplur_ad_") else {
            return
        }
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
        // OPTIMIZED: Don't block on username resolution - show feed immediately
        // Usernames will populate asynchronously in the background
        let currentPosts = posts
        let currentIdx = currentIndex
        Task {
            let uids = currentPosts.map { $0.userID }
            await UsernameCache.shared.prefetch(uids: uids)
            
            // Update display after prefetch (non-blocking)
            if let uid = currentPosts[safe: currentIdx]?.userID {
                let name = await UsernameCache.shared.username(for: uid)
                if let name {
                    await MainActor.run {
                        self.usernames[uid] = name
                    }
                }
            }
        }
    }

    private var currentCoordinate: CLLocationCoordinate2D? { activeLocationProvider.coordinate }

    private func openCurrentPostUserProfile() {
        guard !showTimelineView else { return }
        guard let post = posts[safe: currentIndex] else { return }
        let uid = post.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !post.isPoplurAd, !uid.hasPrefix("poplur_ad_"), !uid.hasPrefix("sponsored_ad_") else {
            print("📢 [FeedView] Current feed item is an ad - skipping profile navigation")
            return
        }
        guard !uid.isEmpty else {
            print("⚠️ [FeedView] Cannot open current post profile - userID is empty")
            return
        }
        noteFeedInteraction()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        NotificationCenter.default.post(name: .ShowUserProfile, object: uid)
    }

    private func triggerBreakingNewsArrival() {
        breakingNewsConfettiTrigger &+= 1
        playOneShotPop()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func publishCurrentPostMetrics(duration: Double = 0.6) {
        guard let post = posts[safe: currentIndex] else {
            publishEmptyPostMetrics(duration: duration)
            return
        }

        NotificationCenter.default.post(
            name: .currentPostRadiusDidChange,
            object: nil,
            userInfo: [
                "radius": post.radius,
                "duration": duration,
                "postCount": post.viewCount,
                "likesCount": likesCount(for: post)
            ]
        )
    }

    private func publishEmptyPostMetrics(duration: Double = 0.3) {
        NotificationCenter.default.post(
            name: .currentPostRadiusDidChange,
            object: nil,
            userInfo: [
                "radius": 0.0,
                "duration": duration,
                "postCount": 0,
                "likesCount": 0
            ]
        )
    }

    private func likesCount(for post: FeedPost) -> Int {
        let seed = post.id.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 97 }
        return max(0, post.viewCount * 3 + seed + (localLikeBoosts[post.id] ?? 0))
    }
    
    private func playOneShotPop() {
        guard PoplurEQSync.shared.shouldPlayTransientSound(minimumInterval: 0.14) else { return }
        PoplurEQSync.shared.configureAudioSession(for: .ambientPlayback)
        guard let url = Bundle.main.url(forResource: "pop", withExtension: "mp3")
            ?? Bundle.main.url(forResource: "pop", withExtension: "caf")
            ?? Bundle.main.url(forResource: "pop", withExtension: "wav") else {
            print("[PopSound] pop.(mp3|caf|wav) not found in bundle")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.volume = 0.40
            player.prepareToPlay()
            player.play()
            popPlayer = player
            // Auto release after it finishes (~0.5s typical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.popPlayer === player {
                    player.stop()
                    self.popPlayer = nil
                }
            }
        } catch {
            print("[PopSound] Failed to play: \(error)")
        }
    }
    
    private func presentInterstitialOrFallback() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else {
            print("[Ads] No active window to present interstitial")
            return
        }
        AdManager.shared.presentInterstitial(from: root)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        }
    }

    private func maybeShowAd() {
        let postID = posts[safe: currentIndex]?.id ?? "missing"
        let namespace = "\(countries[selectedCountryIndex].code)_\(channels[selectedChannelIndex].id)_\(postID)"
        guard FeedAdProbabilitySettings.shouldShowGoogleMobileAd(for: currentIndex, namespace: namespace) else { return }
        presentInterstitialOrFallback()
    }

    // MARK: - Data loading stubs (fill in with your real logic)

    @MainActor
    private func reload() async {
        // INSTANT: Generate posts synchronously (just array construction)
        let newPosts = Self.generateDemoPostsForCountryAndChannel(
            country: countries[selectedCountryIndex].code,
            channel: channels[selectedChannelIndex].id,
            start: 0,
            count: pageSize
        )

        // Update UI immediately (no await needed)
        isLoading = false
        reachedEnd = false
        lastDocument = nil
        posts = newPosts
        currentIndex = 0
        isFeedReady = !posts.isEmpty
        hideInitialLoadingScreen()
        
        // Update radius bar immediately
        if newPosts.first != nil {
            publishCurrentPostMetrics(duration: 0.3)
        } else {
            publishEmptyPostMetrics(duration: 0.3)
        }
        presentBumperForCurrentPostIfNeeded()
        
        // Background tasks only
        Task.detached(priority: .utility) {
            DemoPostStore.shared.store(newPosts)
            let uids = newPosts.map { $0.userID }
            await UsernameCache.shared.prefetch(uids: uids)
        }
    }

    @MainActor
    private func reloadForCountry() async {
        let newPosts = Self.generateDemoPostsForCountryAndChannel(
            country: countries[selectedCountryIndex].code,
            channel: channels[selectedChannelIndex].id,
            start: 0,
            count: pageSize
        )

        // Update UI immediately (no await needed)
        posts = newPosts
        isLoading = false
        isVideoLoading = false
        reachedEnd = newPosts.isEmpty
        isFeedReady = !newPosts.isEmpty
        currentIndex = 0
        hideInitialLoadingScreen()
        
        if newPosts.first != nil {
            publishCurrentPostMetrics(duration: 0.3)
        }
        presentBumperForCurrentPostIfNeeded()
        
        // Background only
        Task.detached(priority: .utility) {
            DemoPostStore.shared.store(newPosts)
        }
    }
    
    @MainActor
    private func reloadForChannel() async {
        let newPosts = Self.generateDemoPostsForCountryAndChannel(
            country: countries[selectedCountryIndex].code,
            channel: channels[selectedChannelIndex].id,
            start: 0,
            count: pageSize
        )

        // Update UI immediately (no await needed)
        posts = newPosts
        isLoading = false
        isVideoLoading = false
        reachedEnd = newPosts.isEmpty
        isFeedReady = !newPosts.isEmpty
        currentIndex = 0
        hideInitialLoadingScreen()
        
        if newPosts.first != nil {
            publishCurrentPostMetrics(duration: 0.3)
        }
        presentBumperForCurrentPostIfNeeded()
        
        // Background only
        Task.detached(priority: .utility) {
            DemoPostStore.shared.store(newPosts)
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

            let newPage = Self.generateDemoPostsForCountryAndChannel(
                country: countries[selectedCountryIndex].code,
                channel: channels[selectedChannelIndex].id,
                start: posts.count,
                count: pageSize
            )

            await MainActor.run {
                posts.append(contentsOf: newPage)
                isLoadingMore = false
                reachedEnd = newPage.isEmpty
            }
        }
    }

    // MARK: - Demo data generator (local fallback)
    // Videos with people speaking — required for closed-caption testing
    nonisolated private static let reliableDemoVideoURLs: [String] = [
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4",
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFuns.mp4",
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4",
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4",
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4",
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4"
    ]

    private struct PoplurAdCreative: Sendable {
        let id: String
        let channelID: String
        let mediaURL: String
        let headline: String
        let body: String
        let callToAction: String
        let creativeKind: String
        let latitude: Double
        let longitude: Double
        let cityName: String
        let countryName: String
        let countryFlag: String
        let radius: Double
        let viewCount: Int
        let driveFileID: String?
    }

    nonisolated private static func googleDriveMediaURL(fileID: String) -> String {
        // "&type=video" is not a real Google Drive parameter and previously made this an
        // invalid endpoint; AVPlayer would receive Drive's HTML page instead of video bytes
        // and silently fail. The file also must be shared as "Anyone with the link" — Drive
        // still serves an HTML sign-in/scan-warning page for private or very large files.
        "https://drive.google.com/uc?export=download&id=\(fileID)"
    }

    nonisolated private static let poplurChannelAdCreatives: [String: [PoplurAdCreative]] = [
        "food": [PoplurAdCreative(
            id: "food-drive-ad",
            channelID: "food",
            mediaURL: googleDriveMediaURL(fileID: "1cNOqd9w6gGpeoU7oMC1xf7iuUcv0l94E"),
            headline: "Poplur Food is serving nearby",
            body: "Food creators, cravings, and local spots are live inside the Poplur radius.",
            callToAction: "Watch Food",
            creativeKind: "Food channel ad",
            latitude: 35.6762,
            longitude: 139.6503,
            cityName: "Tokyo",
            countryName: "Japan",
            countryFlag: "🇯🇵",
            radius: 135_000,
            viewCount: 1_010,
            driveFileID: "1cNOqd9w6gGpeoU7oMC1xf7iuUcv0l94E"
        )],
        "sports": [PoplurAdCreative(
            id: "sports-drive-ad",
            channelID: "sports",
            mediaURL: googleDriveMediaURL(fileID: "1FmRd8-hKDd-pkOueGXjDuDS-SpGeIL27"),
            headline: "Sports energy is live",
            body: "Follow the plays, fans, and stadium moments moving through Poplur.",
            callToAction: "Watch Sports",
            creativeKind: "Sports channel ad",
            latitude: 40.8296,
            longitude: -73.9262,
            cityName: "New York",
            countryName: "USA",
            countryFlag: "🇺🇸",
            radius: 160_000,
            viewCount: 1_104,
            driveFileID: "1FmRd8-hKDd-pkOueGXjDuDS-SpGeIL27"
        )],
        "shopping": [PoplurAdCreative(
            id: "shopping-drive-ad",
            channelID: "shopping",
            mediaURL: googleDriveMediaURL(fileID: "1nKmjGcUTQW1gn1FVkFMWVwn9ErtH7XmM"),
            headline: "Shopping drops are nearby",
            body: "Sales, hauls, and local shopping moments are popping up on Poplur.",
            callToAction: "Watch Shopping",
            creativeKind: "Shopping channel ad",
            latitude: 43.6544,
            longitude: -79.3807,
            cityName: "Toronto",
            countryName: "Canada",
            countryFlag: "🇨🇦",
            radius: 125_000,
            viewCount: 980,
            driveFileID: "1nKmjGcUTQW1gn1FVkFMWVwn9ErtH7XmM"
        )],
        "music": [PoplurAdCreative(
            id: "music-drive-ad",
            channelID: "music",
            mediaURL: googleDriveMediaURL(fileID: "1tfukw5oiNk1VtqEy4wcgToHKNzTq22kT"),
            headline: "Music is moving through the city",
            body: "Studios, stages, and creator sounds are broadcasting through Poplur.",
            callToAction: "Watch Music",
            creativeKind: "Music channel ad",
            latitude: 34.0522,
            longitude: -118.2437,
            cityName: "Los Angeles",
            countryName: "USA",
            countryFlag: "🇺🇸",
            radius: 150_000,
            viewCount: 1_070,
            driveFileID: "1tfukw5oiNk1VtqEy4wcgToHKNzTq22kT"
        )],
        "cartoon": [PoplurAdCreative(
            id: "cartoon-drive-ad",
            channelID: "cartoon",
            mediaURL: googleDriveMediaURL(fileID: "1NyDZewxeHe6R-aiziY5yBVCnwdeFTfZS"),
            headline: "Cartoon worlds are live",
            body: "2D and 3D Poplur stories turn the feed into a bright animated channel.",
            callToAction: "Watch Cartoon",
            creativeKind: "Cartoon channel ad",
            latitude: 34.1381,
            longitude: -118.3534,
            cityName: "Burbank",
            countryName: "USA",
            countryFlag: "🇺🇸",
            radius: 118_000,
            viewCount: 875,
            driveFileID: "1NyDZewxeHe6R-aiziY5yBVCnwdeFTfZS"
        )],
        "kids": [PoplurAdCreative(
            id: "kids-drive-ad",
            channelID: "kids",
            mediaURL: googleDriveMediaURL(fileID: "1rx5BE095nIuA5lyZHictzB09-VsdiAIk"),
            headline: "Kids channel is playing",
            body: "Friendly Poplur moments for games, cartoons, learning, and family-safe fun.",
            callToAction: "Watch Kids",
            creativeKind: "Kids channel ad",
            latitude: 28.5384,
            longitude: -81.3789,
            cityName: "Orlando",
            countryName: "USA",
            countryFlag: "🇺🇸",
            radius: 110_000,
            viewCount: 820,
            driveFileID: "1rx5BE095nIuA5lyZHictzB09-VsdiAIk"
        )],
        "comedy": [PoplurAdCreative(
            id: "comedy-drive-ad",
            channelID: "comedy",
            mediaURL: googleDriveMediaURL(fileID: "1Byb1h62MEdDd4xnPb6Ao-_dQXK9T02sX"),
            headline: "Comedy is going live",
            body: "Sketches, reactions, and funny local moments are ready on Poplur.",
            callToAction: "Watch Comedy",
            creativeKind: "Comedy channel ad",
            latitude: 41.8781,
            longitude: -87.6298,
            cityName: "Chicago",
            countryName: "USA",
            countryFlag: "🇺🇸",
            radius: 120_000,
            viewCount: 925,
            driveFileID: "1Byb1h62MEdDd4xnPb6Ao-_dQXK9T02sX"
        )],
        "spanish": [
            PoplurAdCreative(
                id: "spanish-drive-ad-1",
                channelID: "spanish",
                mediaURL: googleDriveMediaURL(fileID: "17YgYn6c2i2kxrssF-6UrBO6X4h6nHIRd"),
                headline: "El canal en español está en vivo",
                body: "Creadores, música, y momentos locales en español están activos en Poplur.",
                callToAction: "Ver en Español",
                creativeKind: "Spanish channel ad",
                latitude: 40.4168,
                longitude: -3.7038,
                cityName: "Madrid",
                countryName: "Spain",
                countryFlag: "🇪🇸",
                radius: 130_000,
                viewCount: 940,
                driveFileID: "17YgYn6c2i2kxrssF-6UrBO6X4h6nHIRd"
            ),
            PoplurAdCreative(
                id: "spanish-drive-ad-2",
                channelID: "spanish",
                mediaURL: googleDriveMediaURL(fileID: "1q1lMCstW1QxxWmStwO8_YF2R5iImcl6O"),
                headline: "Contenido en español cerca de ti",
                body: "Descubre creadores y momentos en español dentro de tu radio de Poplur.",
                callToAction: "Ver en Español",
                creativeKind: "Spanish channel ad",
                latitude: 19.4326,
                longitude: -99.1332,
                cityName: "Mexico City",
                countryName: "Mexico",
                countryFlag: "🇲🇽",
                radius: 140_000,
                viewCount: 1_015,
                driveFileID: "1q1lMCstW1QxxWmStwO8_YF2R5iImcl6O"
            ),
            PoplurAdCreative(
                id: "spanish-drive-ad-3",
                channelID: "spanish",
                mediaURL: googleDriveMediaURL(fileID: "1Z_Neqsj5eoDdDWQD_-J1S-_PTuCPrWq9"),
                headline: "La energía latina está en vivo",
                body: "Sigue las tendencias y creadores del canal en español en Poplur.",
                callToAction: "Ver en Español",
                creativeKind: "Spanish channel ad",
                latitude: 4.7110,
                longitude: -74.0721,
                cityName: "Bogotá",
                countryName: "Colombia",
                countryFlag: "🇨🇴",
                radius: 120_000,
                viewCount: 865,
                driveFileID: "1Z_Neqsj5eoDdDWQD_-J1S-_PTuCPrWq9"
            )
        ],
        "french": [PoplurAdCreative(
            id: "french-drive-ad",
            channelID: "french",
            mediaURL: googleDriveMediaURL(fileID: "1s_o1GcEjIl25uw4rlRtvE_VhpSf_EJjz"),
            headline: "La chaîne française est en direct",
            body: "Créateurs, musique, et moments locaux en français sont en direct sur Poplur.",
            callToAction: "Regarder en Français",
            creativeKind: "French channel ad",
            latitude: 48.8566,
            longitude: 2.3522,
            cityName: "Paris",
            countryName: "France",
            countryFlag: "🇫🇷",
            radius: 130_000,
            viewCount: 955,
            driveFileID: "1s_o1GcEjIl25uw4rlRtvE_VhpSf_EJjz"
        )]
    ]

    nonisolated private static let poplurAdCreatives: [PoplurAdCreative] = [
        PoplurAdCreative(
            id: "nearby-reel",
            channelID: "sponsored",
            mediaURL: googleDriveMediaURL(fileID: "1cNOqd9w6gGpeoU7oMC1xf7iuUcv0l94E"),
            headline: "Real people are already nearby",
            body: "Human-first Poplur ad slot for finding pop-ups, food, and people around you.",
            callToAction: "Open the map",
            creativeKind: "Live human creative",
            latitude: 40.7128,
            longitude: -74.0060,
            cityName: "New York",
            countryName: "USA",
            countryFlag: "🇺🇸",
            radius: 125_000,
            viewCount: 840,
            driveFileID: "1cNOqd9w6gGpeoU7oMC1xf7iuUcv0l94E"
        ),
        PoplurAdCreative(
            id: "three-d-city-tour",
            channelID: "sponsored",
            mediaURL: googleDriveMediaURL(fileID: "1FmRd8-hKDd-pkOueGXjDuDS-SpGeIL27"),
            headline: "Your city is already talking",
            body: "3D human figures bring local radius discovery into a premium city ad slot.",
            callToAction: "Start a Poplur tour",
            creativeKind: "3D human creative",
            latitude: 43.6532,
            longitude: -79.3832,
            cityName: "Toronto",
            countryName: "Canada",
            countryFlag: "🇨🇦",
            radius: 95_000,
            viewCount: 730,
            driveFileID: "1FmRd8-hKDd-pkOueGXjDuDS-SpGeIL27"
        ),
        PoplurAdCreative(
            id: "radius-hero",
            channelID: "sponsored",
            mediaURL: googleDriveMediaURL(fileID: "1nKmjGcUTQW1gn1FVkFMWVwn9ErtH7XmM"),
            headline: "Post it where it matters",
            body: "Dimensional creator-led ad slot for radius sharing, local discovery, and city energy.",
            callToAction: "Share with your radius",
            creativeKind: "3D figure creative",
            latitude: 34.0522,
            longitude: -118.2437,
            cityName: "Los Angeles",
            countryName: "USA",
            countryFlag: "🇺🇸",
            radius: 150_000,
            viewCount: 910,
            driveFileID: "1nKmjGcUTQW1gn1FVkFMWVwn9ErtH7XmM"
        )
    ]

    nonisolated private static let reliableDemoImageIDs: [Int] = [
        10, 20, 28, 37, 42, 58, 64, 82, 96, 102, 103, 106, 119, 128, 133, 164, 175, 184, 190, 1025
    ]

    nonisolated private static var fallbackDemoVideoURL: String {
        reliableDemoVideoURLs[0]
    }

    nonisolated private static func stableMediaOffset(for namespace: String) -> Int {
        namespace.unicodeScalars.reduce(0) { partial, scalar in
            partial &+ Int(scalar.value)
        }
    }

    nonisolated private static func reliableDemoImageURL(for index: Int, namespace: String) -> String {
        let offset = stableMediaOffset(for: namespace)
        let imageID = reliableDemoImageIDs[abs(index + offset) % reliableDemoImageIDs.count]
        return "https://picsum.photos/id/\(imageID)/1080/1920"
    }

    nonisolated private static func poplurAdCreative(for index: Int, namespace: String, channel: String? = nil) -> PoplurAdCreative {
        if let channel, let creatives = poplurChannelAdCreatives[channel], !creatives.isEmpty {
            let offset = stableMediaOffset(for: namespace)
            return creatives[abs(index + offset) % creatives.count]
        }
        let offset = stableMediaOffset(for: namespace)
        return poplurAdCreatives[abs(index + offset) % poplurAdCreatives.count]
    }

    nonisolated private enum DemoMediaKind {
        case video
        case image
        case ad
    }

    nonisolated private static func demoMediaKind(for index: Int, namespace: String = "global") -> DemoMediaKind {
        if FeedAdProbabilitySettings.placement(for: index, namespace: namespace) == .poplurAd {
            return .ad
        }
        switch index % 4 {
        case 1, 3:
            return .video
        default:
            return .image
        }
    }

    nonisolated private static func balancedDemoMediaURL(for index: Int, namespace: String, channel: String? = nil) -> String {
        poplurAdCreative(for: index, namespace: namespace, channel: channel).mediaURL
    }

    nonisolated private static func languageDemoVideoURL(for index: Int, language: PoplurLanguage) -> String {
        let channel: String
        switch language {
        case .english: channel = "sports"
        case .french:  channel = "french"
        case .spanish: channel = "spanish"
        }
        return poplurAdCreative(for: index, namespace: language.rawValue, channel: channel).mediaURL
    }

    nonisolated private static func demoUserID(regular regularUserID: String, for index: Int, namespace: String = "global") -> String {
        demoMediaKind(for: index, namespace: namespace) == .ad ? "poplur_ad_\(index)" : regularUserID
    }

    nonisolated private static func generateDemoPosts(start: Int, count: Int) -> [FeedPost] {
        guard count > 0 else { return [] }
        let totalCap = 30 // stop after ~30 to simulate end of feed
        let end = min(start + count, totalCap)
        guard start < end else { return [] }

        var result: [FeedPost] = []
        for i in start..<end {
            let id = "demo_\(i)"
            let regularUserID = i % 3 == 0 ? "fake_user_\(i)" : String(format: "user_%06d", i)
            let adCreative = demoMediaKind(for: i, namespace: "global") == .ad ? poplurAdCreative(for: i, namespace: "global") : nil
            let userID = adCreative.map { "poplur_ad_\($0.id)" } ?? demoUserID(regular: regularUserID, for: i, namespace: "global")
            let mediaURL = balancedDemoMediaURL(for: i, namespace: "global")
            let latitude = adCreative?.latitude ?? (37.3349 + Double(i % 5) * 0.01)
            let longitude = adCreative?.longitude ?? (-122.0090 - Double(i % 7) * 0.01)
            let radius = [50, 100, 250, 500, 1000, 5000].randomElement() ?? 250

            let post = FeedPost(
                id: id,
                latitude: latitude,
                longitude: longitude,
                mediaURL: mediaURL,
                radius: adCreative?.radius ?? Double(radius),
                viewCount: adCreative?.viewCount ?? radius,
                userID: userID,
                cityName: adCreative?.cityName,
                countryName: adCreative?.countryName,
                countryFlag: adCreative?.countryFlag,
                isPoplurAd: adCreative != nil,
                adHeadline: adCreative?.headline,
                adBody: adCreative?.body,
                adCallToAction: adCreative?.callToAction,
                adCreativeKind: adCreative?.creativeKind,
                adStorageProvider: adCreative == nil ? nil : "stream_url",
                adDriveFileID: adCreative?.driveFileID
            )
            result.append(post)
        }
        return result
    }
    
    nonisolated private static func generateDemoPostsForCountryAndChannel(country: String, channel: String, start: Int, count: Int) -> [FeedPost] {
        guard count > 0 else { return [] }
        let totalCap = 30
        let end = min(start + count, totalCap)
        guard start < end else { return [] }
        var result: [FeedPost] = []
        
        // Global cities for diverse locations - EXPANDED FOR VARIETY
        let globalCities: [(name: String, lat: Double, lon: Double, country: String, flag: String)] = [
            // Asia
            ("Tokyo", 35.6762, 139.6503, "Japan", "🇯🇵"),
            ("Seoul", 37.5665, 126.9780, "South Korea", "🇰🇷"),
            ("Shanghai", 31.2304, 121.4737, "China", "🇨🇳"),
            ("Hong Kong", 22.3193, 114.1694, "Hong Kong", "🇭🇰"),
            ("Singapore", 1.3521, 103.8198, "Singapore", "🇸🇬"),
            ("Bangkok", 13.7563, 100.5018, "Thailand", "🇹🇭"),
            ("Mumbai", 19.0760, 72.8777, "India", "🇮🇳"),
            ("Dubai", 25.2048, 55.2708, "UAE", "🇦🇪"),
            ("Delhi", 28.6139, 77.2090, "India", "🇮🇳"),
            ("Osaka", 34.6937, 135.5023, "Japan", "🇯🇵"),
            
            // Europe
            ("London", 51.5074, -0.1278, "United Kingdom", "🇬🇧"),
            ("Paris", 48.8566, 2.3522, "France", "🇫🇷"),
            ("Rome", 41.9028, 12.4964, "Italy", "🇮🇹"),
            ("Barcelona", 41.3874, 2.1686, "Spain", "🇪🇸"),
            ("Amsterdam", 52.3676, 4.9041, "Netherlands", "🇳🇱"),
            ("Berlin", 52.5200, 13.4050, "Germany", "🇩🇪"),
            ("Prague", 50.0755, 14.4378, "Czech Republic", "🇨🇿"),
            ("Istanbul", 41.0082, 28.9784, "Turkey", "🇹🇷"),
            ("Madrid", 40.4168, -3.7038, "Spain", "🇪🇸"),
            ("Vienna", 48.2082, 16.3738, "Austria", "🇦🇹"),
            
            // North America
            ("New York", 40.7128, -74.0060, "USA", "🇺🇸"),
            ("San Francisco", 37.7749, -122.4194, "USA", "🇺🇸"),
            ("Los Angeles", 34.0522, -118.2437, "USA", "🇺🇸"),
            ("Chicago", 41.8781, -87.6298, "USA", "🇺🇸"),
            ("Miami", 25.7617, -80.1918, "USA", "🇺🇸"),
            ("Toronto", 43.6532, -79.3832, "Canada", "🇨🇦"),
            ("Vancouver", 49.2827, -123.1207, "Canada", "🇨🇦"),
            ("Mexico City", 19.4326, -99.1332, "Mexico", "🇲🇽"),
            ("Seattle", 47.6062, -122.3321, "USA", "🇺🇸"),
            ("Austin", 30.2672, -97.7431, "USA", "🇺🇸"),
            
            // South America
            ("São Paulo", -23.5505, -46.6333, "Brazil", "🇧🇷"),
            ("Rio de Janeiro", -22.9068, -43.1729, "Brazil", "🇧🇷"),
            ("Buenos Aires", -34.6037, -58.3816, "Argentina", "🇦🇷"),
            ("Lima", -12.0464, -77.0428, "Peru", "🇵🇪"),
            ("Bogotá", 4.7110, -74.0721, "Colombia", "🇨🇴"),
            
            // Oceania
            ("Sydney", -33.8688, 151.2093, "Australia", "🇦🇺"),
            ("Melbourne", -37.8136, 144.9631, "Australia", "🇦🇺"),
            ("Auckland", -36.8485, 174.7633, "New Zealand", "🇳🇿"),
            
            // Africa
            ("Cape Town", -33.9249, 18.4241, "South Africa", "🇿🇦"),
            ("Cairo", 30.0444, 31.2357, "Egypt", "🇪🇬"),
            ("Lagos", 6.5244, 3.3792, "Nigeria", "🇳🇬"),
            ("Nairobi", -1.2864, 36.8172, "Kenya", "🇰🇪"),
            ("Marrakech", 31.6295, -7.9811, "Morocco", "🇲🇦")
        ]
        
        // Create consistent userIDs per post index to ensure same user gets same posts
        var userIDForIndex: [Int: String] = [:]
        
        for i in start..<end {
            let id = "\(country.lowercased())_\(channel)_demo_\(i)"
            
            // Create a stable userID based on index (every 3 posts gets a unique user)
            let userIndex = i / 3  // This ensures posts 0,1,2 share user, 3,4,5 share user, etc.
            let userID: String
            if let existing = userIDForIndex[userIndex] {
                userID = existing
            } else {
                userID = "\(channel)_user_\(userIndex)"
                userIDForIndex[userIndex] = userID
            }
            let channelLanguage = AITranslationCaptionProvider.sourceLanguage(for: channel)
            let isLanguageChannel = channelLanguage != .english
            // For language channels, alternate: even indices are native-language videos,
            // odd indices are English videos that get auto-captioned into the channel language.
            let postSourceLanguage: PoplurLanguage = isLanguageChannel
                ? (i % 2 == 0 ? channelLanguage : .english)
                : .english
            let feedNamespace = "\(country)_\(channel)"
            let adCreative: PoplurAdCreative? = (!isLanguageChannel && demoMediaKind(for: i, namespace: feedNamespace) == .ad)
                ? poplurAdCreative(for: i, namespace: "\(country)_\(channel)", channel: channel)
                : nil
            let feedUserID = adCreative.map { "poplur_ad_\($0.id)" } ?? demoUserID(regular: userID, for: i, namespace: feedNamespace)

            let mediaURL: String = isLanguageChannel
                ? languageDemoVideoURL(for: i, language: postSourceLanguage)
                : balancedDemoMediaURL(for: i, namespace: feedNamespace, channel: channel)
            
            // ✅ USE GLOBAL CITIES for coordinates - posts now come from all over the world!
            let city = globalCities[i % globalCities.count]
            
            // Add slight variation to coordinates so posts aren't exactly on top of each other
            let latVariation = Double.random(in: -0.05...0.05)
            let lonVariation = Double.random(in: -0.05...0.05)
            let latitude = city.lat + latVariation
            let longitude = city.lon + lonVariation
            
            // ✅ EXPANDED RADIUS RANGE - from 100m to 20,000km (close to world radius!)
            // Distribution: More local posts, but some truly global ones
            let radiusOptions: [Double] = [
                100, 250, 500, 1_000,           // Local (neighborhood)
                2_500, 5_000, 10_000,           // City/region
                25_000, 50_000, 100_000,        // Country
                250_000, 500_000, 1_000_000,    // Continental
                2_500_000, 5_000_000, 10_000_000,  // Multi-continental
                15_000_000, 20_000_000          // Near-global (Earth's radius is ~6,371km, diameter ~12,742km)
            ]
            
            // Weight towards smaller radii but include variety
            let radius: Double
            let roll = Double.random(in: 0...1)
            if roll < 0.5 {
                // 50% chance: local to city-level (100m - 10km)
                radius = radiusOptions.prefix(7).randomElement() ?? 5_000
            } else if roll < 0.85 {
                // 35% chance: regional to country (25km - 1000km)
                radius = Array(radiusOptions[7...12]).randomElement() ?? 100_000
            } else {
                // 15% chance: continental to near-global (2.5M - 20M)
                radius = Array(radiusOptions[13...]).randomElement() ?? 5_000_000
            }
            
            // Store city info in post metadata for map display (we'll add this to FeedPost)
            let post = FeedPost(
                id: id,
                latitude: latitude,
                longitude: longitude,
                mediaURL: mediaURL,
                radius: adCreative?.radius ?? radius,
                viewCount: adCreative?.viewCount ?? Int(radius / 100), // Scale view count with radius
                userID: feedUserID,
                cityName: city.name,
                countryName: city.country,
                countryFlag: city.flag,
                sourceLanguageCode: postSourceLanguage.rawValue,
                isPoplurAd: adCreative != nil,
                adHeadline: adCreative?.headline,
                adBody: adCreative?.body,
                adCallToAction: adCreative?.callToAction,
                adCreativeKind: adCreative?.creativeKind,
                adStorageProvider: adCreative == nil ? nil : "stream_url",
                adDriveFileID: adCreative?.driveFileID
            )
            result.append(post)
        }
        
        // LAZY GENERATION: Profile posts will be generated on-demand when user profile is viewed
        // This keeps initial feed load INSTANT
        // NOTE: Profile posts can be generated later via a separate call when needed
        
        print("🌍 [FeedView] Generated \(result.count) GLOBAL feed posts from \(globalCities.count) cities!")
        print("   - Country: \(country), Channel: \(channel)")
        print("   - Radius range: 100m to 20,000km (near-global coverage)")
        
        // Log sample of generated posts
        if let firstPost = result.first {
            print("   - Sample post: \(firstPost.id)")
            print("     Location: \(firstPost.cityName ?? "Unknown"), \(firstPost.countryName ?? "Unknown") \(firstPost.countryFlag ?? "")")
            print("     Radius: \(Int(firstPost.radius))m")
            print("     userID: \(firstPost.userID)")
        }
        
        return result
    }
    
    nonisolated private static func generateDemoPostsForCountry(country: String, start: Int, count: Int) -> [FeedPost] {
        guard count > 0 else { return [] }
        let totalCap = 30
        let end = min(start + count, totalCap)
        guard start < end else { return [] }
        var result: [FeedPost] = []
        for i in start..<end {
            let id = "\(country.lowercased())_demo_\(i)"
            let regularUserID = i % 3 == 0 ? "fake_user_\(i)" : String(format: "user_%06d", i)
            let adCreative = demoMediaKind(for: i, namespace: country) == .ad ? poplurAdCreative(for: i, namespace: country) : nil
            let userID = adCreative.map { "poplur_ad_\($0.id)" } ?? demoUserID(regular: regularUserID, for: i, namespace: country)
            let mediaURL = balancedDemoMediaURL(for: i, namespace: country)
            // Shift coordinates slightly by country index to vary positions
            let baseLat = 37.3349 + Double(abs(country.hashValue % 20)) * 0.01
            let baseLon = -122.0090 - Double(abs(country.hashValue % 20)) * 0.01
            let latitude = adCreative?.latitude ?? (baseLat + Double(i % 5) * 0.01)
            let longitude = adCreative?.longitude ?? (baseLon - Double(i % 7) * 0.01)
            let radius = [50, 100, 250, 500, 1000, 5000].randomElement() ?? 250
            result.append(FeedPost(
                id: id,
                latitude: latitude,
                longitude: longitude,
                mediaURL: mediaURL,
                radius: adCreative?.radius ?? Double(radius),
                viewCount: adCreative?.viewCount ?? radius,
                userID: userID,
                cityName: adCreative?.cityName,
                countryName: adCreative?.countryName,
                countryFlag: adCreative?.countryFlag,
                isPoplurAd: adCreative != nil,
                adHeadline: adCreative?.headline,
                adBody: adCreative?.body,
                adCallToAction: adCreative?.callToAction,
                adCreativeKind: adCreative?.creativeKind,
                adStorageProvider: adCreative == nil ? nil : "stream_url",
                adDriveFileID: adCreative?.driveFileID
            ))
        }
        return result
    }
    
    // MARK: - On-demand profile post generation
    /// Generates additional posts for a user's profile (called lazily when profile is viewed)
    nonisolated static func generateProfilePosts(for userID: String, country: String, channel: String, count: Int = 10) {
        // Check if we already have enough posts for this user
        let existing = DemoPostStore.shared.posts(for: userID)
        guard existing.count < 5 else {
            print("📦 [ProfilePosts] User \(userID) already has \(existing.count) posts, skipping generation")
            return
        }
        
        let globalCities: [(name: String, lat: Double, lon: Double, country: String, flag: String)] = [
            ("Tokyo", 35.6762, 139.6503, "Japan", "🇯🇵"),
            ("London", 51.5074, -0.1278, "United Kingdom", "🇬🇧"),
            ("New York", 40.7128, -74.0060, "USA", "🇺🇸"),
            ("Paris", 48.8566, 2.3522, "France", "🇫🇷"),
            ("Sydney", -33.8688, 151.2093, "Australia", "🇦🇺"),
        ]
        
        var profilePosts: [FeedPost] = []
        for j in 0..<count {
            let additionalID = "\(country.lowercased())_\(channel)_\(userID)_profile_\(j)"
            let mediaURL = poplurAdCreative(for: j, namespace: "\(country)_\(channel)_profile", channel: channel).mediaURL
            
            let city = globalCities.randomElement() ?? globalCities[0]
            let latitude = city.lat + Double.random(in: -0.05...0.05)
            let longitude = city.lon + Double.random(in: -0.05...0.05)
            
            let radiusOptions: [Double] = [100, 500, 1_000, 5_000, 10_000, 50_000, 100_000, 500_000, 2_000_000, 10_000_000]
            let radius = radiusOptions.randomElement() ?? 5_000
            
            let additionalPost = FeedPost(
                id: additionalID,
                latitude: latitude,
                longitude: longitude,
                mediaURL: mediaURL,
                radius: radius,
                viewCount: Int(radius / 100),
                userID: userID,
                cityName: city.name,
                countryName: city.country,
                countryFlag: city.flag
            )
            
            profilePosts.append(additionalPost)
        }
        
        DemoPostStore.shared.store(profilePosts)
        print("📦 [ProfilePosts] Generated \(profilePosts.count) posts for user \(userID)")
    }
}

fileprivate struct FeedTVGuideChannel: Identifiable, Hashable {
    let id: String
    let number: Int
    let emoji: String
    let category: String
    let iconAssetName: String
    let userID: String
    let username: String
    let usernames: [String]
    let program: String
    var videoURL: URL? = nil
}

struct ChannelAssetIcon: View {
    let assetName: String?
    let fallbackEmoji: String
    let size: CGFloat
    let fallbackFontSize: CGFloat

    var body: some View {
        if let assetName, UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .poplurIconShader(intensity: 0.66)
                .frame(width: size, height: size)
        } else {
            Text(fallbackEmoji)
                .font(.system(size: fallbackFontSize))
                .poplurTextShader(intensity: 0.62)
        }
    }
}

private struct FeedTVGuideView: View {
    let channels: [FeedTVGuideChannel]
    let currentChannelID: String
    let currentPostName: String
    let activeFeedPlayer: AVPlayer?
    let onDismiss: () -> Void
    let onChannelSelected: (FeedTVGuideChannel) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("poplur_tvGuideFlipAnimation") private var useFlipAnimation: Bool = true
    @State private var isTabletMenuOpen = true
    @State private var previewedChannelID: String

    init(
        channels: [FeedTVGuideChannel],
        currentChannelID: String,
        currentPostName: String,
        activeFeedPlayer: AVPlayer?,
        onDismiss: @escaping () -> Void,
        onChannelSelected: @escaping (FeedTVGuideChannel) -> Void
    ) {
        self.channels = channels
        self.currentChannelID = currentChannelID
        self.currentPostName = currentPostName
        self.activeFeedPlayer = activeFeedPlayer
        self.onDismiss = onDismiss
        self.onChannelSelected = onChannelSelected
        _previewedChannelID = State(initialValue: currentChannelID)
    }

    private let guideGreen = Color(red: 0.31, green: 1.0, blue: 0.25)

    var body: some View {
        GeometryReader { proxy in
            let isTablet = horizontalSizeClass == .regular && proxy.size.width >= 700

            ZStack {
                Color.black.opacity(0.78)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    guideHeader(isTablet: isTablet)

                    if isTablet {
                        HStack(alignment: .top, spacing: 0) {
                            if isTabletMenuOpen {
                                tabletChannelRail
                                    .frame(width: 220)
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                            }
                            guideContent
                        }
                    } else {
                        guideContent
                    }
                }
                .padding(.top, proxy.safeAreaInsets.top)
                .padding(.bottom, proxy.safeAreaInsets.bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
        }
    }

    private var previewedChannel: FeedTVGuideChannel {
        channels.first { $0.id == previewedChannelID }
            ?? channels.first
            ?? FeedTVGuideChannel(id: "feed", number: 101, emoji: "▶", category: "Feed",
                                  iconAssetName: "poplur_channel_101_food",
                                  userID: "", username: currentPostName,
                                  usernames: [currentPostName], program: "Live posts")
    }

    // PiP in its own band above the list — never overlaps rows
    private var pipPreviewBand: some View {
        let pip = previewedChannel
        return HStack(spacing: 12) {
            GuidePipVideoPane(
                channel: pip,
                currentPostName: previewedChannelID == currentChannelID ? currentPostName : "",
                activeFeedPlayer: activeFeedPlayer,
                guideGreen: guideGreen
            )
            .frame(width: 62, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 3)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: previewedChannelID)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ChannelAssetIcon(assetName: pip.iconAssetName, fallbackEmoji: pip.emoji, size: 22, fallbackFontSize: 14)
                    Text("CH \(pip.number)")
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .foregroundStyle(guideGreen)
                        .poplurTextShader(intensity: 0.86)
                }
                Text(pip.category.uppercased())
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))
                    .poplurTextShader(intensity: 0.58)
                    .kerning(0.8)
                Text(pip.program)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
                    .poplurTextShader(intensity: 0.48)
                    .lineLimit(1)
            }

            Spacer()

            Text("LIVE")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.black)
                .poplurTextShader(intensity: 0.58)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(guideGreen, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.62))
        .overlay(alignment: .bottom) {
            Rectangle().fill(guideGreen.opacity(0.22)).frame(height: 1)
        }
    }

    // Dedicated PiP band + scrollable channel list
    private var guideContent: some View {
        VStack(spacing: 0) {
            pipPreviewBand
            columnHeader
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(channels) { channel in
                        FeedTVGuideRow(
                            channel: channel,
                            isSelected: channel.id == previewedChannelID,
                            guideGreen: guideGreen,
                            useFlipAnimation: useFlipAnimation
                        )
                        .onTapGesture(count: 2) { onChannelSelected(channel) }
                        .onTapGesture(count: 1) {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
                                previewedChannelID = channel.id
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .background(Color.black.opacity(0.36))
    }

    private var tabletChannelRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(channels) { channel in
                Button {
                    onChannelSelected(channel)
                } label: {
                    HStack(spacing: 10) {
                        ChannelAssetIcon(assetName: channel.iconAssetName, fallbackEmoji: channel.emoji, size: 34, fallbackFontSize: 22)
                        Text("\(channel.number)")
                            .font(.system(size: 18, weight: .black, design: .monospaced))
                            .foregroundStyle(guideGreen)
                            .poplurTextShader(intensity: 0.8)
                        Text(channel.category.uppercased())
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.white.opacity(channel.id == currentChannelID ? 1 : 0.62))
                            .poplurTextShader(intensity: channel.id == currentChannelID ? 0.78 : 0.56)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 52, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(channel.id == currentChannelID ? guideGreen.opacity(0.16) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .background(Color.black.opacity(0.46))
    }

    private func guideHeader(isTablet: Bool) -> some View {
        HStack {
            if isTablet {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        isTabletMenuOpen.toggle()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .poplurIconShader()
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("TV GUIDE")
                    .font(.system(size: isTablet ? 34 : 28, weight: .black, design: .monospaced))
                    .foregroundStyle(guideGreen)
                    .poplurTextShader(intensity: 0.92)
                Text("LIVE CHANNELS")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(guideGreen.opacity(0.72))
                    .poplurTextShader(intensity: 0.7)
                    .kerning(1.2)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .poplurIconShader()
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, isTablet ? 24 : 18)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(Color.black.opacity(0.86))
    }

    // CH=80, CATEGORY=90 (narrowed from 134), ON NOW=flex
    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("CH")
                .frame(width: 80, alignment: .leading)
            Text("CATEGORY")
                .frame(width: 90, alignment: .leading)
            Text("ON NOW")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12, weight: .black, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.58))
        .poplurTextShader(intensity: 0.54)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.07))
    }
}

// Continuous left-scrolling marquee for TV guide username rows
private struct TVGuideMarquee: View {
    let text: String
    let font: Font
    let color: Color

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animating = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { tw in
                            Color.clear
                                .onAppear {
                                    textWidth = tw.size.width
                                    containerWidth = geo.size.width
                                    triggerIfNeeded()
                                }
                                .onChange(of: text) { _, _ in
                                    textWidth = tw.size.width
                                    containerWidth = geo.size.width
                                    offset = 0
                                    animating = false
                                    triggerIfNeeded()
                                }
                        }
                    )
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .poplurTextShader(intensity: 0.7)
                    .fixedSize()
                    .offset(x: offset)
            }
            .clipped()
            .frame(width: geo.size.width, alignment: .leading)
        }
    }

    private func triggerIfNeeded() {
        guard !animating, textWidth > containerWidth else { return }
        animating = true
        let gap: CGFloat = 36
        let scroll = textWidth - containerWidth + gap
        let duration = Double(scroll) / 44.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.linear(duration: duration)) {
                offset = -scroll
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.2) {
                withAnimation(.none) { offset = 0 }
                animating = false
                triggerIfNeeded()
            }
        }
    }
}

private struct FeedTVGuideRow: View {
    let channel: FeedTVGuideChannel
    let isSelected: Bool
    let guideGreen: Color
    let useFlipAnimation: Bool

    // Marquee ticker: all usernames joined — scrolls left continuously
    private var tickerText: String {
        let names = channel.usernames.isEmpty ? [channel.username] : channel.usernames
        return names.joined(separator: "  ▶  ")
    }

    var body: some View {
        HStack(spacing: 0) {
            // CH column (80pt)
            HStack(spacing: 8) {
                ChannelAssetIcon(assetName: channel.iconAssetName, fallbackEmoji: channel.emoji, size: 34, fallbackFontSize: 22)
                Text("\(channel.number)")
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(isSelected ? guideGreen : .white)
                    .poplurTextShader(intensity: isSelected ? 0.86 : 0.68)
                    .monospacedDigit()
            }
            .frame(width: 80, alignment: .leading)

            // CATEGORY column (90pt)
            Text(channel.category.uppercased())
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(isSelected ? guideGreen : Color.white.opacity(0.72))
                .poplurTextShader(intensity: isSelected ? 0.8 : 0.58)
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            // ON NOW — scrolling marquee of all users in this channel
            TVGuideMarquee(
                text: tickerText,
                font: .system(size: 16, weight: .black, design: .monospaced),
                color: .white
            )

            // LIVE badge
            Text("LIVE")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(.black)
                .poplurTextShader(intensity: 0.52)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(guideGreen, in: Capsule())
                .padding(.leading, 8)
        }
        .padding(.horizontal, 20)
        .frame(height: 62)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var rowBackground: Color {
        isSelected
        ? Color(red: 0.09, green: 0.16, blue: 0.09)
        : channel.number.isMultiple(of: 2)
        ? Color(red: 0.07, green: 0.075, blue: 0.085)
        : Color(red: 0.045, green: 0.05, blue: 0.058)
    }
}

private struct GuidePipVideoPane: View {
    let channel: FeedTVGuideChannel
    let currentPostName: String
    let activeFeedPlayer: AVPlayer?
    let guideGreen: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            // Live video layer
            Color.black

            if activeFeedPlayer != nil || channel.videoURL != nil {
                TvPipPlayerView(player: activeFeedPlayer, fallbackURL: channel.videoURL)
                    .id(activeFeedPlayer.map { ObjectIdentifier($0).hashValue.description } ?? channel.videoURL?.absoluteString ?? "empty")
            }

            // Green border
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(guideGreen.opacity(0.80), lineWidth: 2)

            // Info scrim at bottom
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    ChannelAssetIcon(assetName: channel.iconAssetName, fallbackEmoji: channel.emoji, size: 22, fallbackFontSize: 13)
                    Text("CH \(channel.number)")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(guideGreen)
                        .poplurTextShader(intensity: 0.8)
                }

                Text(currentPostName.isEmpty ? channel.username : currentPostName)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.white)
                    .poplurTextShader(intensity: 0.68)
                    .lineLimit(1)

                Text("LIVE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(.black)
                    .poplurTextShader(intensity: 0.52)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(guideGreen, in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

// MARK: - Mini AVPlayer for TV Guide PiP

private struct TvPipPlayerView: UIViewRepresentable {
    let player: AVPlayer?
    let fallbackURL: URL?

    func makeUIView(context: Context) -> TvPipHostView {
        let view = TvPipHostView()
        view.configure(player: player, fallbackURL: fallbackURL)
        return view
    }

    func updateUIView(_ uiView: TvPipHostView, context: Context) {
        uiView.configure(player: player, fallbackURL: fallbackURL)
    }
}

final class TvPipHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var avPlayerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private weak var attachedPlayer: AVPlayer?
    private var fallbackPlayer: AVPlayer?
    private var currentURL: URL?
    private var loopToken: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        avPlayerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    func configure(player: AVPlayer?, fallbackURL: URL?) {
        if let player {
            guard attachedPlayer !== player || fallbackPlayer != nil else { return }
            tearDownFallback()
            attachedPlayer = player
            currentURL = nil
            avPlayerLayer.player = player
            if player.timeControlStatus != .playing {
                player.playImmediately(atRate: 1.0)
            }
            return
        }

        guard let fallbackURL else {
            tearDown()
            return
        }

        loadFallback(url: fallbackURL)
    }

    private func loadFallback(url: URL) {
        guard url != currentURL || attachedPlayer != nil else { return }
        currentURL = url
        tearDown()

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.isMuted = true
        p.allowsExternalPlayback = false
        fallbackPlayer = p
        attachedPlayer = nil
        avPlayerLayer.player = p
        p.play()

        loopToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak p] _ in
            p?.seek(to: .zero)
            p?.play()
        }
    }

    private func tearDownFallback() {
        if let t = loopToken { NotificationCenter.default.removeObserver(t); loopToken = nil }
        fallbackPlayer?.pause()
        fallbackPlayer = nil
    }

    private func tearDown() {
        tearDownFallback()
        avPlayerLayer.player = nil
        attachedPlayer = nil
        currentURL = nil
    }

    deinit { tearDown() }
}

private struct FeedBreakingNewsConfettiOverlay: UIViewRepresentable {
    let trigger: Int

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.backgroundColor = .clear
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.isUserInteractionEnabled = false

        let scene = FeedBreakingNewsConfettiScene(size: view.bounds.size)
        context.coordinator.scene = scene
        view.presentScene(scene)

        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if let scene = context.coordinator.scene, scene.size != uiView.bounds.size {
            scene.size = uiView.bounds.size
        }

        guard trigger != context.coordinator.lastTrigger else { return }
        context.coordinator.lastTrigger = trigger
        context.coordinator.scene?.burstFromTop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var scene: FeedBreakingNewsConfettiScene?
        var lastTrigger: Int = 0
    }
}

private struct FeedCommentCredit: Identifiable, Hashable {
    let id = UUID()
    let username: String
    let text: String

    static func seedComments(for postID: String, displayName: String) -> [FeedCommentCredit] {
        let samples = [
            FeedCommentCredit(username: "vi.xi.mmvi", text: "this is live right now"),
            FeedCommentCredit(username: "leurdavoir", text: "keep the camera there"),
            FeedCommentCredit(username: "monsekee", text: "the radius is going crazy"),
            FeedCommentCredit(username: "poplur", text: "watching \(displayName)")
        ]
        let offset = abs(postID.hashValue) % samples.count
        return Array(samples[offset...]) + Array(samples[..<offset])
    }
}

private struct FeedCommentCreditsOverlay: View {
    let comments: [FeedCommentCredit]
    let displayName: String

    @State private var isRolling = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.18),
                        .black.opacity(0.42),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 18) {
                    Text("Comments")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .poplurTextShader(intensity: 0.9)
                        .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 4)

                    Text(displayName)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.76))
                        .poplurTextShader(intensity: 0.68)
                        .textCase(.uppercase)

                    ForEach(comments) { comment in
                        VStack(spacing: 5) {
                            Text(comment.username)
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(.cyan)
                                .poplurTextShader(intensity: 0.8)
                                .shadow(color: .black.opacity(0.75), radius: 5, x: 0, y: 2)

                            Text(comment.text)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white)
                                .poplurTextShader(intensity: 0.78)
                                .fixedSize(horizontal: false, vertical: true)
                                .shadow(color: .black.opacity(0.78), radius: 7, x: 0, y: 3)
                        }
                        .frame(maxWidth: min(proxy.size.width - 52, 430))
                    }
                }
                .frame(width: min(proxy.size.width - 36, 460))
                .position(
                    x: proxy.size.width / 2,
                    y: isRolling ? -proxy.size.height * 0.22 : proxy.size.height + 190
                )
                .animation(.linear(duration: 7.2), value: isRolling)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            isRolling = false
            DispatchQueue.main.async {
                isRolling = true
            }
        }
    }
}

private final class FeedBreakingNewsConfettiScene: SKScene {
    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func burstFromTop() {
        guard size.width > 0, size.height > 0 else { return }

        let emitter = SKEmitterNode()
        emitter.particleTexture = SKTexture(image: Self.confettiTexture())
        emitter.position = CGPoint(x: size.width / 2, y: size.height + 12)
        emitter.particlePositionRange = CGVector(dx: size.width * 0.98, dy: 0)
        emitter.emissionAngle = -CGFloat.pi / 2
        emitter.emissionAngleRange = CGFloat.pi / 7
        emitter.particleBirthRate = 520
        emitter.numParticlesToEmit = 180
        emitter.particleLifetime = 4.0
        emitter.particleLifetimeRange = 1.1
        emitter.particleSpeed = 160
        emitter.particleSpeedRange = 90
        emitter.yAcceleration = -170
        emitter.xAcceleration = 0
        emitter.particleScale = 0.78
        emitter.particleScaleRange = 0.32
        emitter.particleScaleSpeed = -0.08
        emitter.particleRotationRange = CGFloat.pi * 2
        emitter.particleRotationSpeed = 5.5
        emitter.particleAlpha = 0.95
        emitter.particleAlphaRange = 0.12
        emitter.particleAlphaSpeed = -0.18
        emitter.particleBlendMode = .alpha
        emitter.particleColorBlendFactor = 1.0
        emitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [
                UIColor.systemYellow,
                UIColor.white,
                UIColor.systemRed,
                UIColor.systemBlue,
                UIColor.systemGreen,
                UIColor.systemPink
            ],
            times: [0.0, 0.18, 0.36, 0.54, 0.72, 1.0].map(NSNumber.init(value:))
        )

        addChild(emitter)
        emitter.run(.sequence([
            .wait(forDuration: 4.6),
            .removeFromParent()
        ]))
    }

    private static func confettiTexture() -> UIImage {
        let size = CGSize(width: 8, height: 15)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private struct FeedTimelineTransitionMotion: ViewModifier {
    let style: TransitionStylePreference
    let isFlipping: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .twoD:
            content
                .scaleEffect(isFlipping ? 0.96 : 1.0)
                .opacity(isFlipping ? 0.76 : 1.0)
        case .threeD:
            content
                .rotation3DEffect(
                    .degrees(isFlipping ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.72
                )
        }
    }
}

// A local host wrapper that injects PolePositionModel for use when presenting FeedView directly
struct FeedViewHost: View {
    @StateObject private var poleModel = PolePositionModel()
    var body: some View {
        FeedView()
            .environmentObject(poleModel)
    }
}

private struct FeedEntryLogoPopView: View {
    @State private var scale: CGFloat = 0.72
    @State private var opacity: Double = 0

    var body: some View {
        Image("logo")
            .resizable()
            .scaledToFit()
            .frame(width: 150, height: 150)
            .scaleEffect(scale)
            .opacity(opacity)
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
            .allowsHitTesting(false)
            .task {
                await MainActor.run {
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.55)) {
                        opacity = 1
                        scale = 1.22
                    }
                }
                try? await Task.sleep(nanoseconds: 180_000_000)
                await MainActor.run {
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
                        scale = 1.0
                    }
                }
            }
    }
}
