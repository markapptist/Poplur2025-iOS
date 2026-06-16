import SwiftUI
import FirebaseFirestore
import CoreLocation
import UIKit
import AVFoundation
import AVKit
import Contacts
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif


// MARK: - PERFORMANCE OPTIMIZATION STRATEGY
// 1. INSTANT INITIALIZATION: Bootstrap is fully synchronous - no async/await delays
// 2. DEFAULT COUNTRY: Start with US (index 0) immediately, geocode in background
// 3. LAZY PROFILE GENERATION: Profile posts are generated on-demand when viewed
// 4. BACKGROUND TASKS ONLY: Storage, username prefetch, geocoding all happen AFTER UI is ready
// 5. ZERO BLOCKING: All data generation is lightweight array construction (< 1ms)

struct FeedView: View {
    @Environment(\.layoutPreviewMode) private var layoutPreviewMode

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
    
    // Instagram-style timeline view
    @State private var showTimelineView: Bool = false
    @State private var isFlippingTimeline: Bool = false
    @State private var showTVGuide: Bool = false
    
    // Comment section overlay
    @State private var showCommentSection: Bool = false

    // Country paging (horizontal swipe)
    @State private var selectedCountryIndex: Int = 0
    private let countries: [(code: String, name: String, flag: String)] = [
        ("US","United States","🇺🇸"), ("CA","Canada","🇨🇦"), ("MX","Mexico","🇲🇽"), ("BR","Brazil","🇧🇷"), ("AR","Argentina","🇦🇷"), ("CL","Chile","🇨🇱"), ("GB","United Kingdom","🇬🇧"), ("IE","Ireland","🇮🇪"), ("FR","France","🇫🇷"), ("DE","Germany","🇩🇪"), ("ES","Spain","🇪🇸"), ("IT","Italy","🇮🇹"), ("PT","Portugal","🇵🇹"), ("NL","Netherlands","🇳🇱"), ("BE","Belgium","🇧🇪"), ("SE","Sweden","🇸🇪"), ("NO","Norway","🇳🇴"), ("FI","Finland","🇫🇮"), ("DK","Denmark","🇩🇰"), ("PL","Poland","🇵🇱"), ("CZ","Czechia","🇨🇿"), ("AT","Austria","🇦🇹"), ("CH","Switzerland","🇨🇭"), ("GR","Greece","🇬🇷"), ("TR","Türkiye","🇹🇷"), ("RU","Russia","🇷🇺"), ("UA","Ukraine","🇺🇦"), ("CN","China","🇨🇳"), ("JP","Japan","🇯🇵"), ("KR","South Korea","🇰🇷"), ("IN","India","🇮🇳"), ("PK","Pakistan","🇵🇰"), ("ID","Indonesia","🇮🇩"), ("AU","Australia","🇦🇺"), ("NZ","New Zealand","🇳🇿"), ("SA","Saudi Arabia","🇸🇦"), ("AE","UAE","🇦🇪"), ("EG","Egypt","🇪🇬"), ("ZA","South Africa","🇿🇦"), ("NG","Nigeria","🇳🇬"), ("KE","Kenya","🇰🇪"), ("MA","Morocco","🇲🇦"), ("TN","Tunisia","🇹🇳"), ("IL","Israel","🇮🇱"), ("IR","Iran","🇮🇷"), ("TH","Thailand","🇹🇭"), ("VN","Vietnam","🇻🇳"), ("PH","Philippines","🇵🇭"), ("MY","Malaysia","🇲🇾"), ("SG","Singapore","🇸🇬"), ("TW","Taiwan","🇹🇼"), ("HK","Hong Kong","🇭🇰")
    ]
    
    // Channel/Category paging (vertical swipe)
    @State private var selectedChannelIndex: Int = 0
    private let channels: [(id: String, name: String, emoji: String)] = [
        ("food", "Food", "🍔"),
        ("fitness", "Fitness", "💪"),
        ("beauty", "Beauty", "💄"),
        ("sports", "Sports", "⚽"),
        ("modelling", "Modelling", "📸"),
        ("fashion", "Fashion", "👗"),
        ("music", "Music", "🎵"),
        ("tech", "Tech", "💻"),
        ("news", "News", "📰")
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
    private static var geocodeCache: [String: String] = [:]
    private static let geocodeCacheLock = NSLock()
    
    // Resolve ISO country code from coordinate using reverse geocoding (with caching)
    private func geocodeCountry(from coordinate: CLLocationCoordinate2D) async -> String? {
        // Cache key based on rounded coordinates (to ~1km precision)
        let cacheKey = String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude)
        
        // Check cache first
        Self.geocodeCacheLock.lock()
        let cached = Self.geocodeCache[cacheKey]
        Self.geocodeCacheLock.unlock()
        
        if let cached {
            print("[Geocode] Using cached result for \(cacheKey): \(cached)")
            return cached
        }
        
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let pm = placemarks.first, let isoCode = pm.isoCountryCode {
                // Store in cache
                Self.geocodeCacheLock.lock()
                Self.geocodeCache[cacheKey] = isoCode
                Self.geocodeCacheLock.unlock()
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
                .rotation3DEffect(.degrees(isFlippingTimeline ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.72)
                .animation(.spring(response: 0.48, dampingFraction: 0.82), value: showTimelineView)
                .animation(.easeInOut(duration: 0.24), value: isFlippingTimeline)

                if showInitialLoadingScreen {
                    FeedLaunchLoadingScreen()
                        .zIndex(100)
                        .transition(.opacity)
                }

                // Comment section overlay
                if showCommentSection, let currentPost = posts[safe: currentIndex] {
                    CommentSectionView(
                        postID: currentPost.id,
                        onDismiss: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showCommentSection = false
                            }
                        }
                    )
                    .zIndex(999999) // Extremely high z-index to ensure it's in front of absolutely everything
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if showTVGuide {
                    FeedTVGuideView(
                        channels: tvGuideChannels,
                        currentChannelID: currentChannel.id,
                        currentPostName: currentPostDisplayName,
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
            }
            .background(Color.black)
        }
        .task {
            if layoutPreviewMode {
                applyPreviewFeedData()
                return
            }
            if showInitialLoadingScreen {
                NotificationCenter.default.post(name: Notification.Name("FeedLaunchLoadingDidStart"), object: nil)
            }
            if !posts.isEmpty {
                hideInitialLoadingScreen()
                return
            }
            guard didBootstrap == false else {
                hideInitialLoadingScreen()
                return
            }
            await runStrictBootstrap()
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
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FeedRefreshRequested"))) { _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FeedAdvanceOnMediaFailure"))) { _ in
            // Advance to next post on media failure
            if !posts.isEmpty {
                if currentIndex < max(0, posts.count - 1) {
                    currentIndex += 1
                } else {
                    currentIndex = 0
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ProfileViewDismissed"))) { _ in
            // Restore feed radius when returning from profile
            if let post = posts[safe: currentIndex] {
                print("📱 [Feed] ProfileViewDismissed - restoring radius to \(post.radius)m")
                RadiusBarAnimator.showPostRadius(post.radius, duration: 0.6)
            } else if posts.isEmpty {
                print("📱 [Feed] ProfileViewDismissed - no posts, setting radius to 0")
                RadiusBarAnimator.showPostRadius(0, duration: 0.3)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleTimelineView"))) { _ in
            toggleTimelineFlip()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cubeHoldBegan)) { _ in
            guard !posts.isEmpty else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                showTVGuide = true
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CubeTapped"))) { _ in
            // Tap cube to show comment section (only when NOT in timeline view)
            guard !posts.isEmpty, !showTimelineView else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showCommentSection = true
            }
            // Haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        .onChange(of: currentIndex) { _, newIndex in
            guard newIndex >= 0, newIndex < posts.count else {
                print("[Feed] currentIndex out of range: \(newIndex) posts=\(posts.count)")
                return
            }
            let uid = posts[newIndex].userID
            maybeResolveUsername(for: uid)

            // Animate the radius bar to match the current post's radius
            let post = posts[newIndex]
            print("📱 [Feed] Showing post at index \(newIndex), radius: \(post.radius)m")
            RadiusBarAnimator.showPostRadius(post.radius, duration: 0.6)
        }
        .onAppear {
            guard !layoutPreviewMode else { return }
            // Removed duplicate reload here as per instruction
            hapticGenerator.prepare()
            notifHaptics.prepare()
            
            // Quick synchronous check - only reload if truly empty
            if posts.isEmpty {
                // Synchronous reload for instant response
                let newPosts = Self.generateDemoPostsForCountryAndChannel(
                    country: countries[selectedCountryIndex].code,
                    channel: channels[selectedChannelIndex].id,
                    start: 0,
                    count: pageSize
                )
                posts = newPosts
                isFeedReady = !newPosts.isEmpty
                hideInitialLoadingScreen()
                
                if let firstPost = newPosts.first {
                    RadiusBarAnimator.showPostRadius(firstPost.radius, duration: 0.0)
                }
                
                // Background storage only
                Task.detached(priority: .utility) {
                    DemoPostStore.shared.store(newPosts)
                }
            }
            
            // Ensure feed is ready when returning from navigation
            if !posts.isEmpty && !isFeedReady {
                print("[Feed] onAppear - restoring feed ready state")
                isFeedReady = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // INSTANT: Only reload if truly empty - avoid unnecessary async overhead
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
                
                if let firstPost = newPosts.first {
                    RadiusBarAnimator.showPostRadius(firstPost.radius, duration: 0.0)
                }
                
                Task.detached(priority: .utility) {
                    DemoPostStore.shared.store(newPosts)
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
        .onChange(of: showTVGuide) { _, visible in
            NotificationCenter.default.post(name: .MainTabChildRouteVisibilityChanged, object: visible)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .MainTabChildRouteVisibilityChanged, object: false)
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
        hideInitialLoadingScreen()
        
        // Update radius bar immediately
        if let firstPost = newPosts.first {
            RadiusBarAnimator.showPostRadius(firstPost.radius, duration: 0.0)
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
                                            if !posts.isEmpty {
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
                                            selectedChannelIndex = (selectedChannelIndex - 1 + channels.count) % channels.count
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
                    .onTapGesture(count: 2) {
                        toggleTimelineFlip()
                    }
            } else {
                populatedFeedView(in: size)
                    .onAppear { }
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .local)
                            .onChanged { value in
                                if dragAxis == nil {
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
                                            if !posts.isEmpty {
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
                                            if !posts.isEmpty {
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
                    .onTapGesture(count: 2) {
                        toggleTimelineFlip()
                    }
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

            // Wrap overlays in a separate ZStack with allowsHitTesting(false) to avoid gesture conflicts and ensure no offset
            ZStack {
                if showHeart {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 120, weight: .bold))
                        .foregroundStyle(.red)
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(20)
                }
                overlayChrome
                    .allowsHitTesting(false)
                    .zIndex(25)
            }
            .allowsHitTesting(false)
            .padding(.top, 0)
        }
    }

    private func emptyFeedView(in size: CGSize) -> some View {
        ZStack {
            Color.black
                .frame(width: size.width, height: size.height)

            ProgressView()
                .tint(.white)
        }
        .frame(width: size.width, height: size.height)
        .onTapGesture(count: 2) {
            toggleTimelineFlip()
        }
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
                    isTVGuideVisible: showTVGuide,
                    onMediaReady: {
                        hideInitialLoadingScreen()
                    },
                    onUserTapped: { uid in
                        print("👤 [FeedView] User tapped - userID: '\(uid)'")
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
            } else {
                Color.black
            }
        }
    }
    
    private var overlayChrome: some View {
        // REMOVED: Grid icon button and all other chrome elements
        // Overlay is now completely clean - only post info labels remain
        EmptyView()
    }

    private var tvGuideChannels: [FeedTVGuideChannel] {
        let usernames = [
            "Mia", "Jay", "Alex Johnson", "Samira Khan", "Diego Morales",
            "Mina Park", "Noah Lee", "Ava Chen", "Kai Brooks"
        ]
        let programs = [
            "Live posts", "Street check-in", "Creator spotlight", "Radius live",
            "City pulse", "Trending now", "Late feed", "Local signal", "Fresh uploads"
        ]

        return channels.enumerated().map { index, channel in
            let post = posts[safe: index]
            let fallbackUser = usernames[index % usernames.count]
            let userID = post?.userID.hasPrefix("sponsored_ad_") == true ? "tv_\(channel.id)_user" : (post?.userID ?? "tv_\(channel.id)_user")
            let resolvedName = post.map { displayName(for: $0) }
            let username = (resolvedName?.isEmpty == false && resolvedName != "Sponsored") ? (resolvedName ?? fallbackUser) : fallbackUser

            return FeedTVGuideChannel(
                id: channel.id,
                number: 101 + index,
                emoji: channel.emoji,
                category: channel.name,
                userID: userID,
                username: username,
                program: programs[index % programs.count]
            )
        }
    }

    private var currentChannel: (id: String, name: String, emoji: String) {
        channels[safe: selectedChannelIndex] ?? channels[0]
    }

    private var currentChannelNumber: Int {
        101 + selectedChannelIndex
    }

    private var currentPostDisplayName: String {
        guard let post = posts[safe: currentIndex] else { return "Live feed" }
        return displayName(for: post)
    }

    private func toggleTimelineFlip() {
        guard !isFlippingTimeline else { return }
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

    private func openTVGuideChannel(_ channel: FeedTVGuideChannel) {
        if let index = channels.firstIndex(where: { $0.id == channel.id }) {
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

    // MARK: - Username helpers

    @MainActor
    private func hideInitialLoadingScreen() {
        guard showInitialLoadingScreen else { return }
        withAnimation(.easeOut(duration: 0.45)) {
            showInitialLoadingScreen = false
        }
        NotificationCenter.default.post(name: Notification.Name("FeedLaunchLoadingDidFinish"), object: nil)
    }

    private func displayName(for post: FeedPost) -> String {
        if post.userID.hasPrefix("sponsored_ad_") {
            return "Sponsored"
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
    
    private func playOneShotPop() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Use ambient to avoid errors and allow mixing
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[PopSound] Audio session config failed: \(error)")
        }
        guard let url = Bundle.main.url(forResource: "pop", withExtension: "mp3") ?? Bundle.main.url(forResource: "pop", withExtension: "wav") else {
            print("[PopSound] pop.(mp3|wav) not found in bundle")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.volume = 0.9
            player.prepareToPlay()
            player.play()
            popPlayer = player
            // Auto release after it finishes (~0.5s typical)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak popPlayer] in
                self.popPlayer?.stop()
                self.popPlayer = nil
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

    private func maybeShowAd(probability: Double = 0.18) {
        let roll = Double.random(in: 0...1)
        guard roll <= probability else { return }
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
        if let firstPost = newPosts.first {
            RadiusBarAnimator.showPostRadius(firstPost.radius, duration: 0.3)
        } else {
            RadiusBarAnimator.showPostRadius(0, duration: 0.3)
        }
        
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
        
        if let firstPost = newPosts.first {
            RadiusBarAnimator.showPostRadius(firstPost.radius, duration: 0.3)
        }
        
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
        
        if let firstPost = newPosts.first {
            RadiusBarAnimator.showPostRadius(firstPost.radius, duration: 0.3)
        }
        
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
    nonisolated private static let reliableDemoVideoURLs: [String] = [
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8",
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/gear1/prog_index.m3u8",
        "https://media.w3.org/2010/05/sintel/trailer.mp4",
        "https://media.w3.org/2010/05/bunny/trailer.mp4",
        "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4",
        "https://download.samplelib.com/mp4/sample-10s.mp4",
        "https://download.samplelib.com/mp4/sample-15s.mp4"
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

    nonisolated private enum DemoMediaKind {
        case video
        case image
        case ad
    }

    nonisolated private static func demoMediaKind(for index: Int) -> DemoMediaKind {
        switch index % 5 {
        case 1, 4:
            return .video
        case 2:
            return .ad
        default:
            return .image
        }
    }

    nonisolated private static func balancedDemoMediaURL(for index: Int, namespace: String) -> String {
        switch demoMediaKind(for: index) {
        case .video:
            return reliableDemoVideoURLs[index % reliableDemoVideoURLs.count]
        case .image:
            return reliableDemoImageURL(for: index, namespace: namespace)
        case .ad:
            return reliableDemoImageURL(for: index + 97, namespace: "\(namespace)_sponsored")
        }
    }

    nonisolated private static func demoUserID(regular regularUserID: String, for index: Int) -> String {
        demoMediaKind(for: index) == .ad ? "sponsored_ad_\(index)" : regularUserID
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
            let userID = demoUserID(regular: regularUserID, for: i)
            let mediaURL = balancedDemoMediaURL(for: i, namespace: "global")
            let latitude = 37.3349 + Double(i % 5) * 0.01
            let longitude = -122.0090 - Double(i % 7) * 0.01
            let radius = [50, 100, 250, 500, 1000, 5000].randomElement() ?? 250

            let post = FeedPost(
                id: id,
                latitude: latitude,
                longitude: longitude,
                mediaURL: mediaURL,
                radius: Double(radius),
                viewCount: radius,
                userID: userID,
                cityName: nil,
                countryName: nil,
                countryFlag: nil
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
            let feedUserID = demoUserID(regular: userID, for: i)
            
            let mediaURL = balancedDemoMediaURL(for: i, namespace: "\(country)_\(channel)")
            
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
                radius: radius,
                viewCount: Int(radius / 100), // Scale view count with radius
                userID: feedUserID,
                cityName: city.name,
                countryName: city.country,
                countryFlag: city.flag
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
            let userID = demoUserID(regular: regularUserID, for: i)
            let mediaURL = balancedDemoMediaURL(for: i, namespace: country)
            // Shift coordinates slightly by country index to vary positions
            let baseLat = 37.3349 + Double(abs(country.hashValue % 20)) * 0.01
            let baseLon = -122.0090 - Double(abs(country.hashValue % 20)) * 0.01
            let latitude = baseLat + Double(i % 5) * 0.01
            let longitude = baseLon - Double(i % 7) * 0.01
            let radius = [50, 100, 250, 500, 1000, 5000].randomElement() ?? 250
            result.append(FeedPost(
                id: id,
                latitude: latitude,
                longitude: longitude,
                mediaURL: mediaURL,
                radius: Double(radius),
                viewCount: radius,
                userID: userID,
                cityName: nil,
                countryName: nil,
                countryFlag: nil
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
            let mediaURL: String
            if j % 5 == 4 {
                mediaURL = reliableDemoImageURL(for: j, namespace: "\(country)_\(channel)_profile")
            } else {
                mediaURL = reliableDemoVideoURLs.randomElement() ?? fallbackDemoVideoURL
            }
            
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
    let userID: String
    let username: String
    let program: String
}

private struct FeedTVGuideView: View {
    let channels: [FeedTVGuideChannel]
    let currentChannelID: String
    let currentPostName: String
    let onDismiss: () -> Void
    let onChannelSelected: (FeedTVGuideChannel) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isTabletMenuOpen = true

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

                            guideList

                            GuidePipPane(
                                channel: selectedChannel,
                                currentPostName: currentPostName,
                                guideGreen: guideGreen
                            )
                            .frame(width: 320)
                            .padding(.horizontal, 18)
                            .padding(.top, 18)
                        }
                    } else {
                        GuidePipPane(
                            channel: selectedChannel,
                            currentPostName: currentPostName,
                            guideGreen: guideGreen
                        )
                        .frame(height: 138)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)

                        guideList
                    }
                }
                .padding(.top, proxy.safeAreaInsets.top)
                .padding(.bottom, proxy.safeAreaInsets.bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
        }
    }

    private var selectedChannel: FeedTVGuideChannel {
        channels.first { $0.id == currentChannelID } ?? channels.first ?? FeedTVGuideChannel(
            id: "feed",
            number: 101,
            emoji: "▶",
            category: "Feed",
            userID: "",
            username: currentPostName,
            program: "Live posts"
        )
    }

    private var guideList: some View {
        VStack(spacing: 0) {
            columnHeader

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(channels) { channel in
                        Button {
                            onChannelSelected(channel)
                        } label: {
                            FeedTVGuideRow(
                                channel: channel,
                                isSelected: channel.id == currentChannelID,
                                guideGreen: guideGreen
                            )
                        }
                        .buttonStyle(.plain)
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
                        Text(channel.emoji)
                            .font(.system(size: 22))

                        Text("\(channel.number)")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(guideGreen)

                        Text(channel.category.uppercased())
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.white.opacity(channel.id == currentChannelID ? 1 : 0.62))
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
        VStack(spacing: 0) {
            HStack {
                if isTablet {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            isTabletMenuOpen.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("TV GUIDE")
                        .font(.system(size: isTablet ? 34 : 28, weight: .black))
                        .foregroundStyle(.white)
                    Text("LIVE CHANNELS")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(guideGreen)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
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
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("CH")
                .frame(width: 96, alignment: .leading)
            Text("CATEGORY")
                .frame(width: 134, alignment: .leading)
            Text("ON NOW")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12, weight: .black, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.58))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.07))
    }
}

private struct FeedTVGuideRow: View {
    let channel: FeedTVGuideChannel
    let isSelected: Bool
    let guideGreen: Color

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(channel.emoji)
                    .font(.system(size: 26))
                Text("\(channel.number)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(guideGreen)
            }
            .frame(width: 96, alignment: .leading)

            Text(channel.category.uppercased())
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Color.white.opacity(0.86))
                .lineLimit(1)
                .frame(width: 134, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.username)
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(channel.program)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("LIVE")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(guideGreen, in: Capsule())
        }
        .padding(.horizontal, 20)
        .frame(height: 78)
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

private struct GuidePipPane: View {
    let channel: FeedTVGuideChannel
    let currentPostName: String
    let guideGreen: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(guideGreen.opacity(0.72), lineWidth: 2)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(channel.emoji)
                        Text("CH \(channel.number)")
                            .foregroundStyle(guideGreen)
                    }
                    .font(.system(size: 18, weight: .black, design: .rounded))

                    Text(currentPostName.isEmpty ? channel.username : currentPostName)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(channel.category.uppercased())
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.68))
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("LIVE AUDIO")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(guideGreen, in: Capsule())
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

private struct FeedLaunchLoadingScreen: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .scaleEffect(pulse ? 1.04 : 0.96)
                .opacity(pulse ? 1.0 : 0.86)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: pulse
                )
        }
        .onAppear {
            pulse = true
        }
        .allowsHitTesting(false)
    }
}
