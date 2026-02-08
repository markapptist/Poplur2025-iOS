import SwiftUI
import FirebaseFirestore
import CoreLocation
import UIKit
import AVFoundation
import Contacts
import WebKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

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

struct FeedView: View {
    @Environment(\.locationProvider) private var injectedLocationProvider: LocationProvider?
    @StateObject private var fallbackLocationProvider = LocationProvider()
    @StateObject private var poleModel = PolePositionModel()
    private var locationProvider: LocationProvider { injectedLocationProvider ?? fallbackLocationProvider }

    @State private var posts: [FeedPost] = []
    @State private var isLoading = false
    @State private var didSeedIfEmpty = false
    @State private var didBootstrap = false
    @State private var isFeedReady = false  // Added as per instruction

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

    // YouTube content pool
    @State private var youtubeVideoIDs: [String] = []
    private var youtubeService = YouTubeService(apiKey: YouTubeAPI.apiKey)
    
    // Country paging
    @State private var selectedCountryIndex: Int = 0
    private let countries: [(code: String, name: String, flag: String)] = [
        ("US","United States","🇺🇸"), ("CA","Canada","🇨🇦"), ("MX","Mexico","🇲🇽"), ("BR","Brazil","🇧🇷"), ("AR","Argentina","🇦🇷"), ("CL","Chile","🇨🇱"), ("GB","United Kingdom","🇬🇧"), ("IE","Ireland","🇮🇪"), ("FR","France","🇫🇷"), ("DE","Germany","🇩🇪"), ("ES","Spain","🇪🇸"), ("IT","Italy","🇮🇹"), ("PT","Portugal","🇵🇹"), ("NL","Netherlands","🇳🇱"), ("BE","Belgium","🇧🇪"), ("SE","Sweden","🇸🇪"), ("NO","Norway","🇳🇴"), ("FI","Finland","🇫🇮"), ("DK","Denmark","🇩🇰"), ("PL","Poland","🇵🇱"), ("CZ","Czechia","🇨🇿"), ("AT","Austria","🇦🇹"), ("CH","Switzerland","🇨🇭"), ("GR","Greece","🇬🇷"), ("TR","Türkiye","🇹🇷"), ("RU","Russia","🇷🇺"), ("UA","Ukraine","🇺🇦"), ("CN","China","🇨🇳"), ("JP","Japan","🇯🇵"), ("KR","South Korea","🇰🇷"), ("IN","India","🇮🇳"), ("PK","Pakistan","🇵🇰"), ("ID","Indonesia","🇮🇩"), ("AU","Australia","🇦🇺"), ("NZ","New Zealand","🇳🇿"), ("SA","Saudi Arabia","🇸🇦"), ("AE","UAE","🇦🇪"), ("EG","Egypt","🇪🇬"), ("ZA","South Africa","🇿🇦"), ("NG","Nigeria","🇳🇬"), ("KE","Kenya","🇰🇪"), ("MA","Morocco","🇲🇦"), ("TN","Tunisia","🇹🇳"), ("IL","Israel","🇮🇱"), ("IR","Iran","🇮🇷"), ("TH","Thailand","🇹🇭"), ("VN","Vietnam","🇻🇳"), ("PH","Philippines","🇵🇭"), ("MY","Malaysia","🇲🇾"), ("SG","Singapore","🇸🇬"), ("TW","Taiwan","🇹🇼"), ("HK","Hong Kong","🇭🇰")
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
        if let c = locationProvider.coordinate {
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
                Group {
                    feedContent(in: geo.size)
                    // overlayChrome
                    // profileNavigationLink
                }
                .opacity(isFeedReady ? 1 : 0) // replaced from .opacity(1)
                .zIndex(5)
                .background(Color.black)

                if isFeedReady == false {
                    LoadingOverlayView(isPresented: true, background: .pink, logoName: "logo")
                        .zIndex(30)
                        .transition(.opacity)
                }
            }
            .background(Color.black)
        }
        .task {
            if didBootstrap == false {
                didBootstrap = true
                // Strict, sequential bootstrap to guarantee loading overlay timing and content readiness
                await runStrictBootstrap()
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
        .onChange(of: currentIndex) { newIndex in
            if let uid = posts[safe: newIndex]?.userID {
                maybeResolveUsername(for: uid)
            }
        }
        .onAppear {
            // Removed duplicate reload here as per instruction
            hapticGenerator.prepare()
            notifHaptics.prepare()
            try? AVAudioSession.sharedInstance().setActive(false)
            if posts.isEmpty {
                Task { await reload() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { @MainActor in
                // Force a strict refresh to recover from any overlay/black screen state
                isFeedReady = false
                showStatic = true
                stopStaticSound()
                playStaticSound()

                posts.removeAll()
                currentIndex = 0
                await reload()
                if posts.isEmpty {
                    await seedAndReload()
                }
                if posts.isEmpty {
                    await reload()
                }

                showStatic = false
                stopStaticSound()
                isFeedReady = !posts.isEmpty
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
                if let coord = locationProvider.coordinate {
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
            showStatic = true
        }
        playStaticSound()

        // Minimal on-screen time for the loading overlay (e.g., 1.2s)
        async let minOverlay: Void = { try? await Task.sleep(nanoseconds: 1_200_000_000) }()

        // Prepare essentials (pole, country, youtube pool) strictly in order
        await MainActor.run { poleModel.position = PolePosition(x: 0.5, y: 0.5) }
        if let coord = locationProvider.coordinate {
            if let iso = await geocodeCountry(from: coord), let idx = countries.firstIndex(where: { $0.code == iso }) {
                await MainActor.run { selectedCountryIndex = idx }
            } else {
                let idx = countryIndex(for: coord)
                await MainActor.run { selectedCountryIndex = idx }
            }
        }

        await loadYouTubePool()

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
            withAnimation { showStatic = false }
        }
        stopStaticSound()

        // Ensure we have at least one post before revealing
        await MainActor.run {
            isFeedReady = !posts.isEmpty
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
                                            // swipe up -> next (wrap to 0 from last)
                                            if posts.isEmpty == false {
                                                if currentIndex < max(0, posts.count - 1) {
                                                    currentIndex += 1
                                                } else {
                                                    currentIndex = 0
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
                                        } else if value.translation.height >= verticalThreshold {
                                            // swipe down -> previous (wrap to last from 0)
                                            if posts.isEmpty == false {
                                                if currentIndex > 0 {
                                                    currentIndex -= 1
                                                } else {
                                                    currentIndex = max(0, posts.count - 1)
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
                                            // swipe up -> next (wrap to 0 from last)
                                            if posts.isEmpty == false {
                                                if currentIndex < max(0, posts.count - 1) {
                                                    currentIndex += 1
                                                } else {
                                                    currentIndex = 0
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
                                            }
                                        } else if value.translation.height >= verticalThreshold {
                                            // swipe down -> previous (wrap to last from 0)
                                            if posts.isEmpty == false {
                                                if currentIndex > 0 {
                                                    currentIndex -= 1
                                                } else {
                                                    currentIndex = max(0, posts.count - 1)
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
                                }
                                dragAxis = nil
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    dragTranslation = 0
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        if var post = posts[safe: currentIndex] {
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
                                userID: post.userID
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
            }
            tvStaticOverlay(in: size)
            if showHeart {
                Image(systemName: "heart.fill")
                    .font(.system(size: 120, weight: .bold))
                    .foregroundStyle(.red)
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(20)
            }
        }
    }

    private func emptyFeedView(in size: CGSize) -> some View {
        ZStack {
            Color.black
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
                    onUserTapped: { userId in
                        selectedUserID = userId
                        navigateToProfile = true
                    }
                )
                .offset(x: dragAxis == .horizontal ? dragTranslation * 0.25 : 0)
                .offset(y: dragAxis == .vertical ? dragTranslation * 0.25 : 0)
                // Removed animation as per instruction
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

    // Removed pagesToDisplay property since no pager is used anymore

    private var overlayChrome: some View {
        GeometryReader { geo in
            ZStack {
                VStack {
                    HStack {
                        let readyText = isFeedReady ? "yes" : "no"
                        Text("posts: \(posts.count) ready: \(readyText)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    HStack {
                        Text(countries[selectedCountryIndex].flag)
                            .font(.system(size: 28))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        Spacer()
                    }
                    .padding(.leading, 12)
                    .padding(.top, geo.safeAreaInsets.top + 8)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
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
    }

    private var currentCoordinate: CLLocationCoordinate2D? { locationProvider.coordinate }
    
    private func configureAudioSessionForStatic() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("[StaticSound] Audio session config failed: \(error)")
        }
    }

    private func playStaticSound() {
        configureAudioSessionForStatic()
        guard staticPlayer == nil || staticPlayer?.isPlaying == false else { return }
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
    }
    
    private func playOneShotPop() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
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
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let root = window.rootViewController else { return }
        AdManager.shared.presentInterstitial(from: root)
        // After ad presentation, ensure we recover UI state when app becomes active again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        }
    }

    private func maybeShowAd(probability: Double = 0.12) {
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

        // In lieu of Firestore, generate a page of demo posts.
        let newPosts = Self.generateDemoPosts(start: 0, count: pageSize)

        var mixed = newPosts
        if youtubeVideoIDs.isEmpty == false {
            for i in mixed.indices {
                if true { // replaced from `if Double.random(in: 0...1) < 0.95 {`
                    if let vid = youtubeVideoIDs.randomElement() {
                        mixed[i] = FeedPost(
                            id: mixed[i].id,
                            latitude: mixed[i].latitude,
                            longitude: mixed[i].longitude,
                            mediaURL: "https://www.youtube.com/watch?v=\(vid)",
                            radius: mixed[i].radius,
                            viewCount: mixed[i].viewCount,
                            userID: mixed[i].userID
                        )
                    }
                }
            }
        }

        await MainActor.run {
            posts = mixed
            isLoading = false
            // If we couldn't load anything, mark as reached end to stop paginating.
            reachedEnd = mixed.isEmpty
            prefetchVisibleUsernames()
        }
    }

    private func reloadForCountry() async {
        await MainActor.run {
            isLoading = true
            reachedEnd = false
            lastDocument = nil
            posts.removeAll()
            currentIndex = 0
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        let newPosts = Self.generateDemoPostsForCountry(country: countries[selectedCountryIndex].code, start: 0, count: pageSize)

        var mixed = newPosts
        if youtubeVideoIDs.isEmpty == false {
            for i in mixed.indices {
                if true { // replaced from `if Double.random(in: 0...1) < 0.95 {`
                    if let vid = youtubeVideoIDs.randomElement() {
                        mixed[i] = FeedPost(
                            id: mixed[i].id,
                            latitude: mixed[i].latitude,
                            longitude: mixed[i].longitude,
                            mediaURL: "https://www.youtube.com/watch?v=\(vid)",
                            radius: mixed[i].radius,
                            viewCount: mixed[i].viewCount,
                            userID: mixed[i].userID
                        )
                    }
                }
            }
        }

        await MainActor.run {
            posts = mixed
            isLoading = false
            reachedEnd = mixed.isEmpty
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

            var newPage = Self.generateDemoPostsForCountry(country: countries[selectedCountryIndex].code, start: posts.count, count: pageSize)
            if youtubeVideoIDs.isEmpty == false {
                for i in newPage.indices {
                    if true { // replaced from `if Double.random(in: 0...1) < 0.95 {`
                        if let vid = youtubeVideoIDs.randomElement() {
                            newPage[i] = FeedPost(
                                id: newPage[i].id,
                                latitude: newPage[i].latitude,
                                longitude: newPage[i].longitude,
                                mediaURL: "https://www.youtube.com/watch?v=\(vid)",
                                radius: newPage[i].radius,
                                viewCount: newPage[i].viewCount,
                                userID: newPage[i].userID
                            )
                        }
                    }
                }
            }

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
            // Lower resolution image as per instruction, replaced with guaranteed placeholder
            let mediaURL = "https://picsum.photos/800/1400"
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
                userID: userID
            )
            result.append(post)
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
            // Guaranteed placeholder mediaURL to avoid 404s
            let mediaURL = "https://picsum.photos/800/1400"
            // Shift coordinates slightly by country index to vary positions
            let baseLat = 37.3349 + Double(abs(country.hashValue % 20)) * 0.01
            let baseLon = -122.0090 - Double(abs(country.hashValue % 20)) * 0.01
            let latitude = baseLat + Double(i % 5) * 0.01
            let longitude = baseLon - Double(i % 7) * 0.01
            let radius = [50, 100, 250, 500, 1000, 5000].randomElement() ?? 250
            result.append(FeedPost(id: id, latitude: latitude, longitude: longitude, mediaURL: mediaURL, radius: Double(radius), viewCount: radius, userID: userID))
        }
        return result
    }

    // MARK: - YouTube Pool Loader

    private func loadYouTubePool() async {
        guard YouTubeAPI.apiKey.isEmpty == false else { return }
        let channels = YouTubeAPI.topChannelIDs
        guard channels.isEmpty == false else { return }
        // Fetch up to 10 videos per channel and flatten
        await withTaskGroup(of: [YouTubeService.Video].self) { group in
            for ch in channels {
                group.addTask { await youtubeService.fetchRecentVideos(forChannel: ch, maxResults: 10) }
            }
            var collected: Set<String> = []
            for await vids in group {
                for v in vids { collected.insert(v.id) }
            }
            await MainActor.run {
                self.youtubeVideoIDs = Array(collected)
            }
        }
    }
}

// YouTube API configuration and lightweight fetcher
private struct YouTubeAPI {
    // TODO: Replace with your own API key as needed
    static let apiKey: String = "AIzaSyDgMYA1YisgbpEGyl0Nj8VGoorbqmfAkG0"

    // A configurable list of top creator channel IDs. These are examples; replace as desired.
    // MrBeast, Marques Brownlee (MKBHD), Kurzgesagt – In a Nutshell, TED, Veritasium
    static let topChannelIDs: [String] = [
        "UCX6OQ3DkcsbYNE6H8uQQuVA", // MrBeast
        "UCBJycsmduvYEL83R_U4JriQ", // MKBHD
        "UCsXVk37bltHxD1rDPwtNM8Q", // Kurzgesagt
        "UCAuUUnT6oDeKwE6v1NGQxug", // TED
        "UCHnyfMqiRRG1u-2MsSQLbXA"  // Veritasium
    ]
}

private final class YouTubeService {
    struct Video: Hashable { let id: String }

    private let apiKey: String

    init(apiKey: String) { self.apiKey = apiKey }

    // Fetch latest video IDs for a channel by querying the Search API (order=date)
    func fetchRecentVideos(forChannel channelID: String, maxResults: Int = 10) async -> [Video] {
        guard apiKey.isEmpty == false else { return [] }
        var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        comps.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "channelId", value: channelID),
            URLQueryItem(name: "part", value: "id"),
            URLQueryItem(name: "order", value: "date"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: String(max(1, min(50, maxResults))))
        ]
        guard let url = comps.url else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return [] }
            let vids: [Video] = items.compactMap { item in
                guard let id = item["id"] as? [String: Any], let videoId = id["videoId"] as? String else { return nil }
                return Video(id: videoId)
            }
            return vids
        } catch {
            print("[YouTubeService] fetchRecentVideos failed for channel \(channelID): \(error)")
            return []
        }
    }
}

private struct FeedFullscreenPageView: View {
    let post: FeedPost
    let displayName: String
    var onUserTapped: (String) -> Void

    @State private var imagePhaseDebug: String = ""
    
    @State private var ytTitle: String = ""
    @State private var ytAuthor: String = ""

    private var coordinateText: String {
        String(format: "%.4f, %.4f", post.latitude, post.longitude)
    }

    private var youtubeVideoID: String? {
        // Extract YouTube video ID if mediaURL is a YouTube link
        guard let url = URL(string: post.mediaURL) else { return nil }
        if url.host?.contains("youtube.com") == true {
            if let query = url.query {
                let components = URLComponents(string: "https://dummy.com?\(query)")
                if let v = components?.queryItems?.first(where: { $0.name == "v" })?.value {
                    return v
                }
            }
        } else if url.host?.contains("youtu.be") == true {
            return url.lastPathComponent
        }
        return nil
    }
    
    private func fetchYouTubeMetadataIfNeeded() {
        guard ytTitle.isEmpty, ytAuthor.isEmpty, let videoID = youtubeVideoID else { return }
        let apiKey = YouTubeAPI.apiKey
        guard apiKey.isEmpty == false else { return }
        let urlString = "https://www.googleapis.com/youtube/v3/videos?part=snippet&id=\(videoID)&key=\(apiKey)"
        guard let url = URL(string: urlString) else { return }
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]],
                  let first = items.first,
                  let snippet = first["snippet"] as? [String: Any]
            else { return }
            let title = (snippet["title"] as? String) ?? ""
            let channel = (snippet["channelTitle"] as? String) ?? ""
            DispatchQueue.main.async {
                self.ytTitle = title
                self.ytAuthor = channel
            }
        }
        task.resume()
    }

    // Inline YouTube player using WKWebView
    private struct YouTubePlayerView: UIViewRepresentable {
        let videoID: String

        func makeUIView(context: Context) -> WKWebView {
            let config = WKWebViewConfiguration()
            config.allowsInlineMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = []
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.scrollView.isScrollEnabled = false
            webView.isOpaque = false
            webView.backgroundColor = .black
            return webView
        }

        func updateUIView(_ webView: WKWebView, context: Context) {
            let html = """
            <html><head><meta name='viewport' content='initial-scale=1, maximum-scale=1, user-scalable=no'>
            <style>html,body{margin:0;padding:0;background:#000;height:100%;}</style>
            </head><body>
            <iframe id='player' type='text/html' width='100%' height='100%'
                src='https://www.youtube.com/embed/\(videoID)?autoplay=1&mute=1&playsinline=1&controls=0&modestbranding=1&rel=0&showinfo=0&enablejsapi=1'
                frameborder='0' allow='accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share; fullscreen'
                allowfullscreen>
            </iframe>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .zIndex(0)

                if let vid = youtubeVideoID {
                    YouTubePlayerView(videoID: vid)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .background(Color.black)
                        .onAppear { imagePhaseDebug = "youtube"; fetchYouTubeMetadataIfNeeded() }
                } else if let url = URL(string: post.mediaURL) {
                    AsyncImage(url: url, transaction: Transaction(animation: .none)) { phase in
                        switch phase {
                        case .empty:
                            Color.black
                                .onAppear { imagePhaseDebug = "empty" }
                        case .success(let img):
                            img
                                .resizable()
                                .scaledToFill()
                                .frame(width: size.width, height: size.height)
                                .clipped()
                                .background(Color.black)
                                .onAppear { imagePhaseDebug = "success" }
                        case .failure:
                            Color.black
                                .onAppear { imagePhaseDebug = "failure" }
                        @unknown default:
                            Color.black.onAppear { imagePhaseDebug = "unknown" }
                        }
                    }
                    .id("image_\(post.id)_\(post.mediaURL)")
                    .onAppear {
                        fetchYouTubeMetadataIfNeeded()
                    }
                } else {
                    Color.black
                }
                
                if !ytTitle.isEmpty || !ytAuthor.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if !ytTitle.isEmpty {
                            Text(ytTitle)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(2)
                        }
                        if !ytAuthor.isEmpty {
                            Text(ytAuthor)
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(16)
                    .zIndex(5)
                }

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
                .frame(width: size.width, height: size.height, alignment: .topTrailing)
                .zIndex(10)

                // Removed debug VStack with id, url, and phase

                // Removed Text with size info

                VStack {
                    Spacer()
                    IsometricRadiusBar(radius: .constant(post.radius))
                        .frame(width: 60, height: 220)
                        .padding(.trailing, 12)
                }
                .padding(.bottom, 45)
                .frame(width: size.width, height: size.height, alignment: .trailing)
                .zIndex(10)
            }
            .background(Color.black)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
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

// Optional environment key to allow graceful fallback when not provided by ancestor
private struct LocationProviderKey: EnvironmentKey {
    static let defaultValue: LocationProvider? = nil
}

private extension EnvironmentValues {
    var locationProvider: LocationProvider? {
        get { self[LocationProviderKey.self] }
        set { self[LocationProviderKey.self] = newValue }
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

