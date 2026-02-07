import SwiftUI
import FirebaseFirestore
import CoreLocation
import UIKit
import AVFoundation
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
                Color.orange.ignoresSafeArea() // TEMP: confirm FeedView is visible
                Group {
                    feedContent(in: geo.size)
                    // overlayChrome
                    // profileNavigationLink
                }
                .opacity(1) // TEMP: force visible for debugging (was: isFeedReady ? 1 : 0)
                .zIndex(5)
                .background(Color.black)

                if isFeedReady == false {
                    ZStack {
                        Color.pink.ignoresSafeArea()
                        Group {
                            if let _ = UIImage(named: "logo") {
                                Image("logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 200)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 80, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .transition(.opacity)
                    .zIndex(30)
                }
            }
            .background(Color.black)
        }
        .task {
            // Defer heavy bootstrap slightly to let first frame render
            if didBootstrap == false {
                didBootstrap = true
                // Small delay (~140ms)
                try? await Task.sleep(nanoseconds: 140_000_000)

                // Demo default pole position in the center; remove when wiring to real source
                poleModel.position = PolePosition(x: 0.5, y: 0.5)

                // Lightweight country selection; geocode if available, else heuristic
                if let coord = locationProvider.coordinate {
                    if let iso = await geocodeCountry(from: coord), let idx = countries.firstIndex(where: { $0.code == iso }) {
                        selectedCountryIndex = idx
                    } else {
                        selectedCountryIndex = countryIndex(for: coord)
                    }
                }

                // Brief TV static intro and initial load
                showStatic = true
                playStaticSound()
                await reload()
                // Content is now ready; flip readiness, then fade static in sync
                await MainActor.run {
                    isFeedReady = true
                    print("[Debug] isFeedReady set to:", isFeedReady)
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
                await MainActor.run { withAnimation { showStatic = false } }
                stopStaticSound()
                await MainActor.run { showStatic = false }

                // Fade out launch logo without blocking UI
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.5)) {
                        launchLogoOpacity = 0
                        launchLogoScale = 1.05
                    }
                }
                // Remove the logo overlay after the fade completes
                try? await Task.sleep(nanoseconds: 550_000_000)
                await MainActor.run { showLaunchLogo = false }

                if posts.isEmpty, !didSeedIfEmpty {
                    didSeedIfEmpty = true
                    await seedAndReload()
                }

                // Defensive: if still empty, try one more reload
                if posts.isEmpty {
                    await reload()
                }

                await MainActor.run {
                    currentIndex = 0
                }

                prefetchVisibleUsernames()

                await MainActor.run {
                    print("[Feed] Bootstrap complete — posts: \(posts.count)")
                    NotificationCenter.default.post(name: Notification.Name("FeedReady"), object: nil)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .LoadFeedNow)) { _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ResetTabToTop)) { _ in
            currentIndex = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FeedRefreshRequested"))) { _ in
            print("[Feed] Refresh requested — reloading feed")
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
                print("[Feed] onAppear fallback — posts empty, triggering reload()")
                Task { await reload() }
            }
        }
        .onChange(of: showStatic) { visible in
            if visible {
                print("[Debug] showStatic changed to:", visible)
                playStaticSound()
            } else {
                print("[Debug] showStatic changed to:", visible)
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

    // MARK: - Split content to ease type-checking

    @ViewBuilder
    private func feedContent(in size: CGSize) -> some View {
        ZStack {
            if posts.isEmpty {
                emptyFeedView(in: size)
                    .onAppear { print("[Feed] showing emptyFeedView") }
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
                    .onAppear { print("[Feed] showing populatedFeedView") }
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
                            print("Liked post: \(post.id)")
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
            Color.gray
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
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
            Color.blue // TEMP: confirm populated feed ZStack is visible
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
//                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragTranslation) // Removed as per instruction
                .onTapGesture(count: 2) {
                    if var post = posts[safe: currentIndex] {
                        // Like action (log for now)
                        print("Liked post: \(post.id)")
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
    }

    private func maybeShowAd(probability: Double = 0.12) {
        let roll = Double.random(in: 0...1)
        guard roll <= probability else { return }
        presentInterstitialOrFallback()
    }

    // MARK: - Data loading stubs (fill in with your real logic)

    private func reload() async {
        print("[Feed] reload() start")
        // Reset pagination state and load the first page.
        await MainActor.run {
            isLoading = true
            reachedEnd = false
            lastDocument = nil
            posts.removeAll()
            currentIndex = 0
            print("[Feed] reload() reset state")
        }

        // Simulate network delay for UX parity.
        try? await Task.sleep(nanoseconds: 250_000_000)

        // In lieu of Firestore, generate a page of demo posts.
        let newPosts = Self.generateDemoPosts(start: 0, count: pageSize)
        print("[Feed] reload() generated newPosts: \(newPosts.count)")

        await MainActor.run {
            posts = newPosts
            isLoading = false
            // If we couldn't load anything, mark as reached end to stop paginating.
            reachedEnd = newPosts.isEmpty
            prefetchVisibleUsernames()
            print("[Debug] posts after reload:", posts.count)
            print("[Feed] reload() end — posts: \(posts.count)")
        }
    }

    private func reloadForCountry() async {
        print("[Feed] reloadForCountry() start — country: \(countries[selectedCountryIndex].code)")
        await MainActor.run {
            isLoading = true
            reachedEnd = false
            lastDocument = nil
            posts.removeAll()
            currentIndex = 0
            print("[Feed] reloadForCountry() reset state")
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        let newPosts = Self.generateDemoPostsForCountry(country: countries[selectedCountryIndex].code, start: 0, count: pageSize)
        print("[Feed] reloadForCountry() generated newPosts: \(newPosts.count)")
        await MainActor.run {
            posts = newPosts
            isLoading = false
            reachedEnd = newPosts.isEmpty
            prefetchVisibleUsernames()
            print("[Feed] reloadForCountry() end — posts: \(posts.count)")
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
            let newPage = Self.generateDemoPostsForCountry(country: countries[selectedCountryIndex].code, start: start, count: pageSize)

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
}

private struct FeedFullscreenPageView: View {
    let post: FeedPost
    let displayName: String
    var onUserTapped: (String) -> Void

    @State private var imagePhaseDebug: String = ""

    private var coordinateText: String {
        String(format: "%.4f, %.4f", post.latitude, post.longitude)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.green
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .zIndex(0)

                // Removed poster background AsyncImage block as per instruction

                if let url = URL(string: post.mediaURL) {
                    AsyncImage(url: url, transaction: Transaction(animation: .none)) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                Color.black
                                ProgressView().tint(.white).scaleEffect(1.4)
                            }
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
                            ZStack {
                                Color.red  // TEMP: make failure very visible
                                Image(systemName: "photo")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .onAppear { imagePhaseDebug = "failure" }
                        @unknown default:
                            Color.black.onAppear { imagePhaseDebug = "unknown" }
                        }
                    }
                    .id("image_\(post.id)_\(post.mediaURL)")
                    .onAppear { print("[Debug] mediaURL:", post.mediaURL) }
                } else {
                    Color.black
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("id: \(post.id)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text("url: \(post.mediaURL.prefix(36))…")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                    Text("phase: \(imagePhaseDebug)")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                .padding(.leading, 16)
                .padding(.top, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .zIndex(11)

                Text(String(format: "size: %.0f x %.0f", size.width, size.height))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .padding(8)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(16)
                    .zIndex(20)
                
                Text("POST: \(post.id)  PHASE: \(imagePhaseDebug)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding()
                    .background(Color.black.opacity(0.4), in: Capsule())
                    .padding(.top, 70)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .zIndex(12)

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

