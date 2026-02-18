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
                    profileNavigationLink
                }
                .opacity(1)
                .zIndex(5)
                .background(Color.black)

                if isFeedReady == false {
                    LoadingOverlayView(isPresented: true, background: Color(red: 1.0, green: 0.2, blue: 0.4), logoName: "logo")
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
        .onChange(of: currentIndex) { newIndex in
            guard newIndex >= 0, newIndex < posts.count else {
                print("[Feed] currentIndex out of range: \(newIndex) posts=\(posts.count)")
                return
            }
            let uid = posts[newIndex].userID
            maybeResolveUsername(for: uid)
        }
        .onAppear {
            // Removed duplicate reload here as per instruction
            hapticGenerator.prepare()
            notifHaptics.prepare()
            if posts.isEmpty {
                Task { await reload() }
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
            print("[Feed] bootstrap start: showStatic=\(showStatic)")
        }
        playStaticSound()

        // Minimal on-screen time for the loading overlay (e.g., 1.2s)
        async let minOverlay: Void = { try? await Task.sleep(nanoseconds: 1_200_000_000) }()

        // Prepare essentials (pole, country) strictly in order
        await MainActor.run { poleModel.position = PolePosition(x: 0.5, y: 0.5) }
        if let coord = locationProvider.coordinate {
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
                if let current = posts[safe: currentIndex] {
                    VStack {
                        Spacer()
                        IsometricRadiusBar(radius: .constant(current.radius))
                            .frame(width: 60, height: 220)
                            .padding(.trailing, 12)
                    }
                    .padding(.bottom, 45)
                    .frame(width: size.width, height: size.height, alignment: .trailing)
                    .padding(.trailing, 0)
                    .allowsHitTesting(false)
                    .zIndex(15)
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
                        selectedUserID = uid
                        navigateToProfile = true
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .clipped()
                .background(Color.black)
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

        // In lieu of Firestore, generate a page of demo posts.

        let newPosts = Self.generateDemoPosts(start: 0, count: pageSize)

        let mixed = newPosts

        await MainActor.run {
            print("[Feed] reload posts loaded: \(mixed.count)")
            posts = mixed
            isLoading = false
            // If we couldn't load anything, mark as reached end to stop paginating.
            reachedEnd = mixed.isEmpty
            prefetchVisibleUsernames()
            isFeedReady = !posts.isEmpty
            print("[Feed] reload set ready=\(isFeedReady)")
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

        let mixed = newPosts

        await MainActor.run {
            print("[Feed] reloadForCountry posts loaded: \(mixed.count) country=\(countries[selectedCountryIndex].code)")
            posts = mixed
            isLoading = false
            reachedEnd = mixed.isEmpty
            prefetchVisibleUsernames()
            isFeedReady = !posts.isEmpty
            print("[Feed] reloadForCountry set ready=\(isFeedReady)")
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
            result.append(FeedPost(id: id, latitude: latitude, longitude: longitude, mediaURL: mediaURL, radius: Double(radius), viewCount: radius, userID: userID))
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
                let requiredKeys = ["playable"]
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
                let requiredKeys = ["playable"]
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
                .overlay(alignment: .topTrailing) {
                    topRightInfo(size: geo.size)
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
                Color.black
            }

            if !post.mediaURL.isEmpty {
                mediaURLBadge
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 12)
                    .zIndex(6)
            }

            /*
            topRightInfo(size: size)
                .zIndex(10)
            */
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
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .onAppear {
                        imagePhaseDebug = "empty"
                        print("[Feed] image phase: empty for URL: \(post.mediaURL)")
                    }
            case .success(let img):
                img
                    .resizable()
                    .aspectRatio(contentMode: .fit)  // changed from scaledToFill to aspectRatio fit
                    .frame(width: size.width, height: size.height)  // set explicit frame to size
                    .background(Color.black)
                    //.ignoresSafeArea() removed
                    //.clipped() removed
                    .onAppear {
                        imagePhaseDebug = "success"
                        print("[Feed] Using image: \(post.mediaURL)")
                    }
            case .failure:
                ZStack {
                    if UIImage(named: "placeholder") != nil {
                        Image("placeholder")
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea()
                            .clipped()
                    } else {
                        LinearGradient(colors: [.black, .gray.opacity(0.4), .black], startPoint: .top, endPoint: .bottom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea()
                            .clipped()
                    }
                }
                .background(Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    imagePhaseDebug = "failure"
                    print("[Feed] image phase: failure for URL: \(post.mediaURL)")
                }
            @unknown default:
                Color.black.onAppear { imagePhaseDebug = "unknown" }
            }
        }
        .id("image_\(post.id)_\(post.mediaURL)")
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

