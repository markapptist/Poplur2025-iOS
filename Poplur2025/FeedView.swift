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

// MARK: - Environment key for LocationProvider

private struct LocationProviderKey: EnvironmentKey {
    static let defaultValue: LocationProvider? = nil
}

extension EnvironmentValues {
    var locationProvider: LocationProvider? {
        get { self[LocationProviderKey.self] }
        set { self[LocationProviderKey.self] = newValue }
    }
}

// MARK: - Shared pole position model and overlay

// Normalized pole position within the view's content area (0...1 in both axes)
struct PolePosition {
    var x: CGFloat
    var y: CGFloat
}

// Observable model so multiple views (Map, Feed, Camera) can render the pole identically
final class PolePositionModel: ObservableObject {
    @Published var position: PolePosition = .init(x: 0.5, y: 0.5)
}

// A lightweight overlay that renders a pole at the normalized position
private struct PoleOverlay: View {
    @EnvironmentObject var poleModel: PolePositionModel

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // Clamp normalized values to [0,1] to avoid accidental overflow
            let nx = min(max(poleModel.position.x, 0), 1)
            let ny = min(max(poleModel.position.y, 0), 1)
            let x = nx * size.width
            let y = ny * size.height

            // Match Map view: blue accuracy halo + white ring center (no filled dot)
            // Since we don't have a map projection in Feed, we use a visual heuristic to size the halo.
            // The halo scales with the shorter screen dimension to suggest radius without geographic accuracy.
            let haloSize = min(size.width, size.height) * 0.25 // tweak as desired for feel

            ZStack {
                // Accuracy halo (visual approximation of MapCircle)
                Circle()
                    .fill(Color.blue.opacity(0.20))
                    .frame(width: haloSize, height: haloSize)
                    .overlay(
                        Circle().stroke(Color.blue.opacity(0.5), lineWidth: 2)
                    )

                // Center marker: white ring only (no center fill)
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 20, height: 20)
            }
            .position(x: x, y: y)
            .accessibilityLabel("Pole indicator")
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Demo Post Store (shared in-memory database for demo users)

/// Singleton that stores all generated demo posts so they can be queried by userID
final class DemoPostStore {
    static let shared = DemoPostStore()
    private init() {}
    
    private var posts: [FeedPost] = []
    
    func store(_ posts: [FeedPost]) {
        // Add new posts, avoiding duplicates by ID
        var addedCount = 0
        for post in posts {
            if !self.posts.contains(where: { $0.id == post.id }) {
                self.posts.append(post)
                addedCount += 1
            }
        }
        print("📦 [DemoPostStore] Stored \(addedCount) new posts (total: \(self.posts.count))")
    }
    
    func posts(for userID: String) -> [FeedPost] {
        let userPosts = posts.filter { $0.userID == userID }
        print("👤 [DemoPostStore] Found \(userPosts.count) posts for userID: \(userID)")
        return userPosts
    }
    
    func allPosts() -> [FeedPost] {
        print("📚 [DemoPostStore] Total posts: \(posts.count)")
        return posts
    }
    
    // Add method to get all unique users
    func allUsers() -> Set<String> {
        let users = Set(posts.map { $0.userID })
        print("👥 [DemoPostStore] Total unique users: \(users.count)")
        return users
    }
}

// MARK: - FeedPost Model
// Note: FeedPost is defined in FeedFullscreenPage.swift to avoid duplication

struct FeedView: View {
    @StateObject private var fallbackLocationProvider = LocationProvider()
    @StateObject private var poleModel = PolePositionModel()
    private var activeLocationProvider: LocationProvider { fallbackLocationProvider }

    @State private var posts: [FeedPost] = []
    @State private var isLoading = false
    @State private var didSeedIfEmpty = false
    @State private var didBootstrap = false
    @State private var isFeedReady = false  // Added as per instruction
    @State private var isVideoLoading = false  // Track video loading state for logo indicator

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
    
    // TV static overlay state
    @State private var showStatic: Bool = false
    @State private var staticPlayer: AVAudioPlayer? = nil
    @State private var popPlayer: AVAudioPlayer? = nil

    @State private var showHeart: Bool = false

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

    @State private var showLaunchLogo: Bool = true
    @State private var launchLogoOpacity: Double = 1.0
    @State private var launchLogoScale: CGFloat = 0.9

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
    
    // Resolve ISO country code from coordinate using reverse geocoding
    private func geocodeCountry(from coordinate: CLLocationCoordinate2D) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let pm = placemarks.first, let isoCode = pm.isoCountryCode {
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
                feedContent(in: geo.size)
                    .opacity(1)
                    .zIndex(5)
                    .background(Color.black)

                // Video loading indicator - shown during transitions (visible on all tabs)
                VideoLoadingIndicator(isLoading: $isVideoLoading, logoName: "logo")
                    .zIndex(30)
                    .transition(.opacity)
            }
            .background(Color.black)
        }
        .task {
            if didBootstrap == false {
                didBootstrap = true
                // Strict, sequential bootstrap to guarantee loading overlay timing and content readiness
                await runStrictBootstrap()
                print("[Feed] after bootstrap posts=\(posts.count) ready=\(isFeedReady)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .LoadFeedNow)) { _ in
            Task { await reload() }
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
        .onChange(of: currentIndex) { newIndex in
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
            // Removed duplicate reload here as per instruction
            hapticGenerator.prepare()
            notifHaptics.prepare()
            if posts.isEmpty {
                Task { await reload() }
            }
            
            // Ensure feed is ready when returning from navigation
            if !posts.isEmpty && !isFeedReady {
                print("[Feed] onAppear - restoring feed ready state")
                isFeedReady = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { @MainActor in
                // Force a strict refresh to recover from any overlay/black screen state
                isFeedReady = false
                print("[Feed] didBecomeActive: resetting, showStatic=true")
                showStatic = true
                stopStaticSound()
                playStaticSound()

                posts.removeAll()
                currentIndex = 0
                await reload()
                print("[Feed] didBecomeActive: reload complete posts=\(posts.count)")
                if posts.isEmpty {
                    await seedAndReload()
                    print("[Feed] didBecomeActive: seedAndReload done posts=\(posts.count)")
                }
                if posts.isEmpty {
                    await reload()
                    print("[Feed] didBecomeActive: second reload posts=\(posts.count)")
                }

                showStatic = false
                stopStaticSound()
                print("[Feed] didBecomeActive: static stopped")
                isFeedReady = !posts.isEmpty
                print("[Feed] didBecomeActive: ready=\(isFeedReady)")
            }
        }
        .onChange(of: showStatic) { visible in
            if visible {
                playStaticSound()
            } else {
                stopStaticSound()
            }
        }
        .onChange(of: coordinateKey) { _ in
            Task {
                if let coord = activeLocationProvider.coordinate {
                    if let iso = await geocodeCountry(from: coord), let idx = countries.firstIndex(where: { $0.code == iso }) {
                        if idx != selectedCountryIndex {
                            await MainActor.run { selectedCountryIndex = idx }
                            await MainActor.run { showStatic = true }
                            playStaticSound()
                            await reloadForCountry()
                            try? await Task.sleep(nanoseconds: 120_000_000)
                            await MainActor.run { withAnimation { showStatic = false } }
                            stopStaticSound()
                        }
                    } else {
                        let idx = countryIndex(for: coord)
                        if idx != selectedCountryIndex {
                            await MainActor.run { selectedCountryIndex = idx }
                            await MainActor.run { showStatic = true }
                            playStaticSound()
                            await reloadForCountry()
                            try? await Task.sleep(nanoseconds: 120_000_000)
                            await MainActor.run { withAnimation { showStatic = false } }
                            stopStaticSound()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Strict bootstrap sequence
    private func runStrictBootstrap() async {
        // Ensure loading overlay is visible immediately
        await MainActor.run {
            isFeedReady = false
            isVideoLoading = true  // Show video loading indicator
            showStatic = true
            print("[Feed] bootstrap start: showStatic=\(showStatic)")
        }
        playStaticSound()

        // Minimal on-screen time for the loading overlay (e.g., 1.2s)
        async let minOverlay: Void = { try? await Task.sleep(nanoseconds: 1_200_000_000) }()

        // Prepare essentials (pole, country) strictly in order
        await MainActor.run { poleModel.position = PolePosition(x: 0.5, y: 0.5) }
        if let coord = activeLocationProvider.coordinate {
            if let iso = await geocodeCountry(from: coord), let idx = countries.firstIndex(where: { $0.code == iso }) {
                await MainActor.run { selectedCountryIndex = idx }
            } else {
                let idx = countryIndex(for: coord)
                await MainActor.run { selectedCountryIndex = idx }
            }
        }

        // Load posts strictly and wait until we have content
        await reload()
        // If still empty, try seed and reload once
        if posts.isEmpty {
            await seedAndReload()
        }
        // Defensive: one more reload if still empty
        if posts.isEmpty {
            await reload()
        }

        // Wait for the minimum overlay time
        _ = await minOverlay

        // Small settle time to help first frame render
        try? await Task.sleep(nanoseconds: 120_000_000)

        // Hide static, stop sound, and reveal content in a tightly-controlled order
        await MainActor.run {
            print("[Feed] bootstrap hiding static")
            withAnimation { showStatic = false }
            isVideoLoading = false  // Hide video loading indicator
        }
        stopStaticSound()
        print("[Feed] bootstrap stopped static sound")

        // Ensure we have at least one post before revealing
        await MainActor.run {
            isFeedReady = !posts.isEmpty
            print("[Feed] bootstrap ready=\(isFeedReady) posts=\(posts.count)")
            currentIndex = 0
        }

        // Notify observers that feed is ready
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("FeedReady"), object: nil)
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
                                            showStatic = true
                                            playOneShotPop()
                                            playStaticSound()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                                withAnimation { showStatic = false }
                                                stopStaticSound()
                                            }
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
                                            showStatic = true
                                            playOneShotPop()
                                            playStaticSound()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                                withAnimation { showStatic = false }
                                                stopStaticSound()
                                            }
                                            maybeShowAd()
                                        }
                                    case .vertical:
                                        if value.translation.height <= -verticalThreshold {
                                            // swipe up -> next channel
                                            selectedChannelIndex = (selectedChannelIndex + 1) % channels.count
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
                                            showStatic = true
                                            playOneShotPop()
                                            playStaticSound()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                                withAnimation { showStatic = false }
                                                stopStaticSound()
                                            }
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
                                            showStatic = true
                                            playOneShotPop()
                                            playStaticSound()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                                withAnimation { showStatic = false }
                                                stopStaticSound()
                                            }
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
                        // On empty feed double-tap just fire haptics for consistency
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                            hapticGenerator.impactOccurred(intensity: 1.0)
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            notifHaptics.notificationOccurred(.success)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        playOneShotPop()
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { showHeart = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.easeOut(duration: 0.15)) { showHeart = false }
                        }
                        hapticGenerator.prepare()
                        notifHaptics.prepare()
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
                                            showStatic = true
                                            playOneShotPop()
                                            playStaticSound()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                                withAnimation { showStatic = false }
                                                stopStaticSound()
                                            }
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
                                            showStatic = true
                                            playOneShotPop()
                                            playStaticSound()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                                withAnimation { showStatic = false }
                                                stopStaticSound()
                                            }
                                            maybeShowAd()
                                        }
                                    case .vertical:
                                        if value.translation.height <= -verticalThreshold {
                                            // swipe up -> next channel
                                            selectedChannelIndex = (selectedChannelIndex + 1) % channels.count
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
                                            showStatic = true
                                            playOneShotPop()
                                            playStaticSound()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                                withAnimation { showStatic = false }
                                                stopStaticSound()
                                            }
                                            maybeLoadMoreIfNeeded(appearingIndex: currentIndex)
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
                                            showStatic = true
                                            playOneShotPop()
                                            playStaticSound()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                                withAnimation { showStatic = false }
                                                stopStaticSound()
                                            }
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
                        if let post = posts[safe: currentIndex] {
                            // Like action (log for now)
                            // Increase radius by 5000 meters, clamp to max 10000
                            let newRadius = min(10_000, post.radius + 5000)
                            let updated = FeedPost(
                                id: post.id,
                                latitude: post.latitude,
                                longitude: post.longitude,
                                mediaURL: post.mediaURL,
                                radius: newRadius,
                                viewCount: post.viewCount,
                                userID: post.userID,
                                cityName: post.cityName,
                                countryName: post.countryName,
                                countryFlag: post.countryFlag
                            )
                            posts[currentIndex] = updated
                            // Haptic feedback for like
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                hapticGenerator.impactOccurred(intensity: 1.0)
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                notifHaptics.notificationOccurred(.success)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                            playOneShotPop()
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { showHeart = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                withAnimation(.easeOut(duration: 0.15)) { showHeart = false }
                            }
                            hapticGenerator.prepare()
                            notifHaptics.prepare()
                        }
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
        }
        .frame(width: size.width, height: size.height)
        .onTapGesture(count: 2) {
            // On empty feed double-tap just fire haptics for consistency
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                hapticGenerator.impactOccurred(intensity: 1.0)
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                notifHaptics.notificationOccurred(.success)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            playOneShotPop()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { showHeart = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.15)) { showHeart = false }
            }
            hapticGenerator.prepare()
            notifHaptics.prepare()
        }
    }

    private func populatedFeedView(in size: CGSize) -> some View {
        ZStack {
            if let post = posts[safe: currentIndex] {
                FeedFullscreenPageView(
                    post: post,
                    displayName: displayName(for: post),
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .clipped()
                .background(Color.black)
                
                // Post info overlay
                VStack {
                    HStack(spacing: 12) {
                        // Country flag and channel emoji
                        HStack(spacing: 6) {
                            Text(countries[selectedCountryIndex].flag)
                                .font(.system(size: 32))
                            
                            Text(channels[selectedChannelIndex].emoji)
                                .font(.system(size: 32))
                        }
                        
                        // User info and coordinates
                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                print("👤 [FeedView] User info tapped - userID: '\(post.userID)'")
                                guard !post.userID.isEmpty else {
                                    print("⚠️ [FeedView] Cannot navigate to profile - userID is empty")
                                    return
                                }
                                // Post notification to switch to profile tab with this userID
                                NotificationCenter.default.post(
                                    name: .ShowUserProfile,
                                    object: post.userID
                                )
                            } label: {
                                Text(displayName(for: post))
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            
                            Text(String(format: "%.4f, %.4f", post.latitude, post.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(radius: 4)
                    .padding(.horizontal)
                    .padding(.top, 60)
                    
                    Spacer()
                }
                .allowsHitTesting(true)
            } else {
                Color.black
            }
        }
    }
    
    @ViewBuilder
    private func tvStaticOverlay(in size: CGSize) -> some View {
        StaticView(size: size, isVisible: showStatic)
            .allowsHitTesting(false)
    }

    private var overlayChrome: some View {
        GeometryReader { geo in
            ZStack {
                VStack {
                    // REMOVED: Debug label showing posts count and ready state
                    
                    // REMOVED: Country flag and channel emoji badges (now shown in post info overlay)
                    /*
                    HStack(spacing: 8) {
                        // Country flag (horizontal swipe)
                        Text(countries[selectedCountryIndex].flag)
                            .font(.system(size: 28))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        
                        // Channel emoji (vertical swipe)
                        Text(channels[selectedChannelIndex].emoji)
                            .font(.system(size: 28))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        
                        Spacer()
                    }
                    .padding(.leading, 12)
                    .padding(.top, geo.safeAreaInsets.top + 8)
                    */
                    
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, geo.safeAreaInsets.top)
                .allowsHitTesting(false)
                .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Username helpers

    private func displayName(for post: FeedPost) -> String {
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
        // Prefetch username only for currentIndex since we show one post at a time
        if let uid = posts[safe: currentIndex]?.userID {
            maybeResolveUsername(for: uid)
        }
        
        // Also prefetch next and previous posts for smooth navigation
        if let nextUID = posts[safe: currentIndex + 1]?.userID {
            maybeResolveUsername(for: nextUID)
        }
        if currentIndex > 0, let prevUID = posts[safe: currentIndex - 1]?.userID {
            maybeResolveUsername(for: prevUID)
        }
        
        // Background prefetch ALL usernames for loaded posts
        Task {
            let allUIDs = posts.map { $0.userID }
            await UsernameCache.shared.prefetch(uids: allUIDs)
            
            // Refresh display after prefetch completes
            await MainActor.run {
                // Trigger a state update to refresh displayed names
                if let uid = posts[safe: currentIndex]?.userID {
                    Task {
                        let name = await UsernameCache.shared.username(for: uid)
                        if let name {
                            usernames[uid] = name
                        }
                    }
                }
            }
        }
    }

    private var currentCoordinate: CLLocationCoordinate2D? { activeLocationProvider.coordinate }
    
    private func configureAudioSessionForStatic() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Use ambient so it mixes and avoids activation failures on silent/route-less cases
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[StaticSound] Audio session config failed (safe): \(error)")
        }
    }

    private func playStaticSound() {
        configureAudioSessionForStatic()
        // allow restarting even if a previous player exists but is not playing
        if staticPlayer?.isPlaying == true { return }
        guard let url = Bundle.main.url(forResource: "pop", withExtension: "mp3") ?? Bundle.main.url(forResource: "pop", withExtension: "wav") else {
            print("[StaticSound] pop.(mp3|wav) not found in bundle")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1 // loop while visible
            player.volume = 0.8
            player.prepareToPlay()
            player.play()
            staticPlayer = player
        } catch {
            print("[StaticSound] Failed to play: \(error)")
        }
    }

    private func stopStaticSound() {
        staticPlayer?.stop()
        staticPlayer = nil
        // Deactivate ambient audio session to avoid conflicts with playback
        DispatchQueue.main.async {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                print("[StaticSound] Failed to deactivate session: \(error)")
            }
        }
    }
    
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

    private func maybeShowAd(probability: Double = 0.03) {
        let roll = Double.random(in: 0...1)
        guard roll <= probability else { return }
        presentInterstitialOrFallback()
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
        }

        // Simulate network delay for UX parity.
        try? await Task.sleep(nanoseconds: 250_000_000)

        // Use the country and channel-aware generator for consistency
        let newPosts = Self.generateDemoPostsForCountryAndChannel(
            country: countries[selectedCountryIndex].code,
            channel: channels[selectedChannelIndex].id,
            start: 0,
            count: pageSize
        )

        let mixed = newPosts

        await MainActor.run {
            print("📡 [Feed] reload completed:")
            print("   - Posts loaded: \(mixed.count)")
            print("   - Country: \(countries[selectedCountryIndex].code)")
            print("   - Channel: \(channels[selectedChannelIndex].id)")
            
            // Log first post details for debugging
            if let firstPost = mixed.first {
                print("   - First post ID: \(firstPost.id)")
                print("   - First post mediaURL: \(firstPost.mediaURL)")
                print("   - First post userID: \(firstPost.userID)")
            }
            
            posts = mixed
            isLoading = false
            // If we couldn't load anything, mark as reached end to stop paginating.
            reachedEnd = mixed.isEmpty
            prefetchVisibleUsernames()
            isFeedReady = !posts.isEmpty
            print("   - Feed ready: \(isFeedReady)")
            
            // Store demo posts in shared store
            DemoPostStore.shared.store(mixed)
            print("   - Stored \(mixed.count) posts in DemoPostStore")
            
            // Trigger radius bar update for the first post
            if !posts.isEmpty {
                let firstPost = posts[0]
                print("📱 [Feed] Initial load - showing first post radius: \(firstPost.radius)m")
                RadiusBarAnimator.showPostRadius(firstPost.radius, duration: 0.8)
            } else {
                // No posts - set radius to 0
                print("📱 [Feed] No posts - setting radius to 0")
                RadiusBarAnimator.showPostRadius(0, duration: 0.3)
            }
        }
    }

    private func reloadForCountry() async {
        await MainActor.run {
            isLoading = true
            isVideoLoading = true  // Show loading indicator during transition
            reachedEnd = false
            lastDocument = nil
            posts.removeAll()
            currentIndex = 0
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        let newPosts = Self.generateDemoPostsForCountryAndChannel(
            country: countries[selectedCountryIndex].code,
            channel: channels[selectedChannelIndex].id,
            start: 0,
            count: pageSize
        )

        let mixed = newPosts

        await MainActor.run {
            print("[Feed] reloadForCountry posts loaded: \(mixed.count) country=\(countries[selectedCountryIndex].code) channel=\(channels[selectedChannelIndex].id)")
            posts = mixed
            isLoading = false
            isVideoLoading = false  // Hide loading indicator
            reachedEnd = mixed.isEmpty
            prefetchVisibleUsernames()
            isFeedReady = !posts.isEmpty
            print("[Feed] reloadForCountry set ready=\(isFeedReady)")
            
            // Store demo posts in shared store
            DemoPostStore.shared.store(mixed)
            
            // Trigger radius bar update for the first post
            if !posts.isEmpty {
                let firstPost = posts[0]
                print("📱 [Feed] Country reload - showing first post radius: \(firstPost.radius)m")
                RadiusBarAnimator.showPostRadius(firstPost.radius, duration: 0.8)
            }
        }
    }
    
    private func reloadForChannel() async {
        await MainActor.run {
            isLoading = true
            isVideoLoading = true  // Show loading indicator during transition
            reachedEnd = false
            lastDocument = nil
            posts.removeAll()
            currentIndex = 0
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        let newPosts = Self.generateDemoPostsForCountryAndChannel(
            country: countries[selectedCountryIndex].code,
            channel: channels[selectedChannelIndex].id,
            start: 0,
            count: pageSize
        )

        let mixed = newPosts

        await MainActor.run {
            print("[Feed] reloadForChannel posts loaded: \(mixed.count) country=\(countries[selectedCountryIndex].code) channel=\(channels[selectedChannelIndex].id)")
            posts = mixed
            isLoading = false
            isVideoLoading = false  // Hide loading indicator
            reachedEnd = mixed.isEmpty
            prefetchVisibleUsernames()
            isFeedReady = !posts.isEmpty
            print("[Feed] reloadForChannel set ready=\(isFeedReady)")
            
            // Store demo posts in shared store
            DemoPostStore.shared.store(mixed)
            
            // Trigger radius bar update for the first post
            if !posts.isEmpty {
                let firstPost = posts[0]
                print("📱 [Feed] Channel reload - showing first post radius: \(firstPost.radius)m")
                RadiusBarAnimator.showPostRadius(firstPost.radius, duration: 0.8)
            }
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
    private static func generateDemoPosts(start: Int, count: Int) -> [FeedPost] {
        guard count > 0 else { return [] }
        let totalCap = 30 // stop after ~30 to simulate end of feed
        let end = min(start + count, totalCap)
        guard start < end else { return [] }

        var result: [FeedPost] = []
        for i in start..<end {
            let id = "demo_\(i)"
            let userID = i % 3 == 0 ? "fake_user_\(i)" : String(format: "user_%06d", i)
            // Force the first post to be a guaranteed playable HLS stream
            let hlsSample = "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8"
            let sampleVideos: [String] = [
                // Reliable HLS (landscape)
                "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8",
                "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/gear1/prog_index.m3u8",
                // HLS variants
                "https://devstreaming-cdn.apple.com/videos/wwdc/2020/10653/4/7EEB4C51-2E7F-4B6C-BE1D-2E94C7D10C61/hls_vod_mvp.m3u8",
                "https://devstreaming-cdn.apple.com/videos/wwdc/2019/502dvxw8o5g9v9b/502/hls_vod_mvp.m3u8",
                // Small MP4s (landscape)
                "https://filesamples.com/samples/video/mp4/sample_640x360.mp4",
                "https://filesamples.com/samples/video/mp4/sample_960x400_ocean_with_audio.mp4",
                "https://sample-videos.com/video321/mp4/720/big_buck_bunny_720p_1mb.mp4",
                // Additional MP4s
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                // Extra diversity (different encodes/aspects)
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4"
            ]
            let mediaURL: String
            if i < 2 {
                // Force images early so the first page shows a mix
                let w = [640, 720, 800, 1080].randomElement() ?? 800
                let h = [960, 1280, 1400, 1440, 1920].randomElement() ?? 1400
                mediaURL = "https://picsum.photos/\(w)/\(h)?random=\(Int.random(in: 1...10_000))"
            } else if i % 2 == 0 {
                // Even index -> image
                let w = [640, 720, 800, 1080].randomElement() ?? 800
                let h = [960, 1280, 1400, 1440, 1920].randomElement() ?? 1400
                mediaURL = "https://picsum.photos/\(w)/\(h)?random=\(Int.random(in: 1...10_000))"
            } else {
                // Odd index -> random video from sampleVideos
                mediaURL = sampleVideos.randomElement() ?? hlsSample
            }
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
    
    private static func generateDemoPostsForCountryAndChannel(country: String, channel: String, start: Int, count: Int) -> [FeedPost] {
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
            
            // Force the first post to be a guaranteed playable HLS stream
            let hlsSample = "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8"
            let sampleVideos: [String] = [
                // Reliable HLS (landscape)
                "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8",
                "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/gear1/prog_index.m3u8",
                // HLS variants
                "https://devstreaming-cdn.apple.com/videos/wwdc/2020/10653/4/7EEB4C51-2E7F-4B6C-BE1D-2E94C7D10C61/hls_vod_mvp.m3u8",
                "https://devstreaming-cdn.apple.com/videos/wwdc/2019/502dvxw8o5g9v9b/502/hls_vod_mvp.m3u8",
                // Small MP4s (landscape)
                "https://filesamples.com/samples/video/mp4/sample_640x360.mp4",
                "https://filesamples.com/samples/video/mp4/sample_960x400_ocean_with_audio.mp4",
                "https://sample-videos.com/video321/mp4/720/big_buck_bunny_720p_1mb.mp4",
                // Additional MP4s
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                // Extra diversity (different encodes/aspects)
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4"
            ]
            let mediaURL: String
            if i < 2 {
                // Force images early so the first page shows a mix
                let w = [640, 720, 800, 1080].randomElement() ?? 800
                let h = [960, 1280, 1400, 1440, 1920].randomElement() ?? 1400
                mediaURL = "https://picsum.photos/\(w)/\(h)?random=\(Int.random(in: 1...10_000))"
            } else if i % 2 == 0 {
                // Even index -> image
                let w = [640, 720, 800, 1080].randomElement() ?? 800
                let h = [960, 1280, 1400, 1440, 1920].randomElement() ?? 1400
                mediaURL = "https://picsum.photos/\(w)/\(h)?random=\(Int.random(in: 1...10_000))"
            } else {
                // Odd index -> random video from sampleVideos
                mediaURL = sampleVideos.randomElement() ?? hlsSample
            }
            
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
                userID: userID,
                cityName: city.name,
                countryName: city.country,
                countryFlag: city.flag
            )
            result.append(post)
        }
        
        // CRITICAL: Pre-generate additional posts for each unique user so they have a full profile
        // This ensures when you click on a user, they have multiple posts in their profile
        var postsPerUser: [String: [FeedPost]] = [:]
        for post in result {
            postsPerUser[post.userID, default: []].append(post)
        }
        
        // Generate 5-10 additional posts per user for their profile
        for (userID, existingPosts) in postsPerUser {
            let additionalCount = Int.random(in: 5...10)
            for j in 0..<additionalCount {
                let additionalID = "\(country.lowercased())_\(channel)_\(userID)_profile_\(j)"
                let mediaURL: String
                if j % 2 == 0 {
                    let w = [640, 720, 800, 1080].randomElement() ?? 800
                    let h = [960, 1280, 1400, 1440, 1920].randomElement() ?? 1400
                    mediaURL = "https://picsum.photos/\(w)/\(h)?random=\(Int.random(in: 1...10_000))"
                } else {
                    let sampleVideos = [
                        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8",
                        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
                        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
                    ]
                    mediaURL = sampleVideos.randomElement() ?? "https://picsum.photos/800/1400"
                }
                
                // Use random global city for variety
                let city = globalCities.randomElement() ?? globalCities[0]
                let latitude = city.lat + Double.random(in: -0.05...0.05)
                let longitude = city.lon + Double.random(in: -0.05...0.05)
                
                // Varied radius for profile posts too
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
                
                // Store in DemoPostStore immediately so it's available for profile queries
                DemoPostStore.shared.store([additionalPost])
            }
        }
        
        print("🌍 [FeedView] Generated \(result.count) GLOBAL feed posts from \(globalCities.count) cities!")
        print("   - Country: \(country), Channel: \(channel)")
        print("   - User IDs: \(postsPerUser.keys.sorted())")
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
    
    private static func generateDemoPostsForCountry(country: String, start: Int, count: Int) -> [FeedPost] {
        guard count > 0 else { return [] }
        let totalCap = 30
        let end = min(start + count, totalCap)
        guard start < end else { return [] }
        var result: [FeedPost] = []
        for i in start..<end {
            let id = "\(country.lowercased())_demo_\(i)"
            let userID = i % 3 == 0 ? "fake_user_\(i)" : String(format: "user_%06d", i)
            // Force the first post to be a guaranteed playable HLS stream
            let hlsSample = "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8"
            let sampleVideos: [String] = [
                // Reliable HLS (landscape)
                "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8",
                "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/gear1/prog_index.m3u8",
                // HLS variants
                "https://devstreaming-cdn.apple.com/videos/wwdc/2020/10653/4/7EEB4C51-2E7F-4B6C-BE1D-2E94C7D10C61/hls_vod_mvp.m3u8",
                "https://devstreaming-cdn.apple.com/videos/wwdc/2019/502dvxw8o5g9v9b/502/hls_vod_mvp.m3u8",
                // Small MP4s (landscape)
                "https://filesamples.com/samples/video/mp4/sample_640x360.mp4",
                "https://filesamples.com/samples/video/mp4/sample_960x400_ocean_with_audio.mp4",
                "https://sample-videos.com/video321/mp4/720/big_buck_bunny_720p_1mb.mp4",
                // Additional MP4s
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                // Extra diversity (different encodes/aspects)
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4"
            ]
            let mediaURL: String
            if i < 2 {
                // Force images early so the first page shows a mix
                let w = [640, 720, 800, 1080].randomElement() ?? 800
                let h = [960, 1280, 1400, 1440, 1920].randomElement() ?? 1400
                mediaURL = "https://picsum.photos/\(w)/\(h)?random=\(Int.random(in: 1...10_000))"
            } else if i % 2 == 0 {
                // Even index -> image
                let w = [640, 720, 800, 1080].randomElement() ?? 800
                let h = [960, 1280, 1400, 1440, 1920].randomElement() ?? 1400
                mediaURL = "https://picsum.photos/\(w)/\(h)?random=\(Int.random(in: 1...10_000))"
            } else {
                // Odd index -> random video from sampleVideos
                mediaURL = sampleVideos.randomElement() ?? hlsSample
            }
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
}

// Removed YouTube API and YouTubeService definitions as per instruction

private struct FeedFullscreenPageView: View {
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
    private struct VideoPlayerContainer: View {
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
            /*
            .onAppear {
                // Observe global pause to stop fullscreen playback immediately
                self.pauseObserver = NotificationCenter.default.addObserver(forName: Notification.Name("PauseGlobalFeedAudio"), object: nil, queue: .main) { _ in
                    self.playbackStuck = false
                    if let obs = timeObserver, let p = player { p.removeTimeObserver(obs) }
                    timeObserver = nil
                    player?.pause()
                    (player as? AVQueuePlayer)?.removeAllItems()
                }
            }
            */
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

    private struct PlayerLayerView: UIViewRepresentable {
        let player: AVPlayer?

        func makeUIView(context: Context) -> PlayerHostingView {
            let view = PlayerHostingView()
            view.backgroundColor = .black
            view.translatesAutoresizingMaskIntoConstraints = false
            view.playerLayer.videoGravity = .resizeAspect  // Changed to .resizeAspect
            view.player = player
            return view
        }

        func updateUIView(_ uiView: PlayerHostingView, context: Context) {
            uiView.player = player
            uiView.playerLayer.videoGravity = .resizeAspect  // Changed to .resizeAspect
            uiView.setNeedsLayout()
            uiView.layoutIfNeeded()
        }
    }

    private final class PlayerHostingView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
            playerLayer.videoGravity = .resizeAspect  // Changed to .resizeAspect
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
                //.ignoresSafeArea() // removed as per instructions
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
                                "coordinate": coordinate,  // Use coordinate object
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
        
        // Debug logging
        let _ = print("🎬 [FeedFullscreenPageView] Rendering post \(post.id)")
        let _ = print("   mediaURL: \(post.mediaURL)")
        let _ = print("   isVideo: \(isVideo)")
        let _ = print("   directVideoURL: \(directVideoURL?.absoluteString ?? "nil")")
        
        ZStack {
            Color.black
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .zIndex(0)

            if isVideo, let videoURL = directVideoURL {
                videoContent(size: size, videoURL: videoURL)
                    .onAppear {
                        print("🎥 [FeedFullscreenPageView] Showing video: \(videoURL.absoluteString)")
                    }
            } else if let url = URL(string: post.mediaURL) {
                imageContent(size: size, url: url)
                    .onAppear {
                        print("🖼️ [FeedFullscreenPageView] Showing image: \(url.absoluteString)")
                    }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Invalid media URL")
                        .foregroundColor(.white.opacity(0.7))
                    Text(post.mediaURL)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .onAppear {
                    print("⚠️ [FeedFullscreenPageView] Invalid URL for post \(post.id): \(post.mediaURL)")
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
                .onAppear {
                    imagePhaseDebug = "empty"
                    print("📸 [Feed] Loading image: \(url.absoluteString)")
                }
            case .success(let img):
                img
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .onAppear {
                        imagePhaseDebug = "success"
                        print("✅ [Feed] Image loaded successfully: \(url.absoluteString)")
                    }
            case .failure(let error):
                ZStack {
                    Color.black
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.yellow)
                        Text("Image failed to load")
                            .foregroundColor(.white)
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .onAppear {
                    imagePhaseDebug = "failure"
                    print("❌ [Feed] Image load failed: \(url.absoluteString), error: \(error.localizedDescription)")
                }
            @unknown default:
                Color.black
                    .onAppear {
                        imagePhaseDebug = "unknown"
                        print("⚠️ [Feed] Unknown image phase for: \(url.absoluteString)")
                    }
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

private struct StaticView: View {
    let size: CGSize
    let isVisible: Bool

    @State private var jitterX: CGFloat = 0
    @State private var scanlinePhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Color bands (retro vertical stripes)
            colorBands
                .offset(x: jitterX)
                .animation(.linear(duration: 0.12), value: jitterX)

            // Scanlines
            scanlines
                .blendMode(.overlay)
                .opacity(0.35)
                .offset(y: scanlinePhase)
                .animation(.linear(duration: 0.06).repeatForever(autoreverses: false), value: scanlinePhase)

            // Grain (simple white/black noise shimmer)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.black.opacity(0.08),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(0.5)
                .blendMode(.softLight)
        }
        .frame(width: size.width, height: size.height)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.16), value: isVisible)
        .onAppear {
            // Initialize animation phases
            jitterX = CGFloat.random(in: -6...6)
            scanlinePhase = .random(in: -4...4)
            // Kick small jitter updates when visible
            if isVisible {
                withAnimation(.linear(duration: 0.12)) {
                    jitterX = CGFloat.random(in: -6...6)
                }
            }
        }
        .onChange(of: isVisible) { visible in
            if visible {
                jitterX = CGFloat.random(in: -6...6)
                scanlinePhase = .random(in: -4...4)
            }
        }
    }

    private var colorBands: some View {
        HStack(spacing: 0) {
            Color.red
            Color.green
            Color.blue
            Color.cyan
            Color.pink
            Color.yellow
            Color.red
            Color.green
        }
        .frame(width: size.width, height: size.height)
        .mask(
            LinearGradient(
                colors: [
                    .white.opacity(0.9), .white.opacity(0.7), .white.opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .saturation(1.2)
        .contrast(1.2)
        .opacity(0.9)
    }

    private var scanlines: some View {
        // Repeating thin dark lines
        let lineHeight: CGFloat = 2
        let spacing: CGFloat = 4
        return Stripes(lineWidth: lineHeight, spacing: spacing)
            .fill(Color.black.opacity(0.35))
            .frame(width: size.width, height: size.height)
    }
}

// Utility shape for repeating horizontal stripes
private struct Stripes: Shape {
    let lineWidth: CGFloat
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        var y: CGFloat = rect.minY
        while y < rect.maxY {
            p.addRect(CGRect(x: rect.minX, y: y, width: rect.width, height: lineWidth))
            y += lineWidth + spacing
        }
        return p
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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

#Preview("FeedView with environment") {
    FeedViewHost()
}

#Preview("FeedView (basic)") {
    FeedViewHost()
}

#Preview("FeedView iPhone 15 Pro") {
    FeedViewHost()
        .previewDevice("iPhone 15 Pro")
}
