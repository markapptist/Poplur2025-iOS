import SwiftUI
import FirebaseFirestore
import CoreLocation
import UIKit
import AVFoundation

struct FeedView: View {
    @Environment(\.locationProvider) private var injectedLocationProvider: LocationProvider?
    @StateObject private var fallbackLocationProvider = LocationProvider()
    private var locationProvider: LocationProvider { injectedLocationProvider ?? fallbackLocationProvider }

    @State private var posts: [FeedPost] = []
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
        // Prefer a few common regions first
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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                feedContent(in: geo.size)

                if showLaunchLogo {
                    Image("logo") // Ensure this asset exists in the asset catalog
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(220, geo.size.width * 0.5))
                        .opacity(launchLogoOpacity)
                        .scaleEffect(launchLogoScale)
                        .transition(.scale.combined(with: .opacity))
                        .onAppear {
                            // Subtle pop-in on first appear
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                launchLogoScale = 1.0
                                launchLogoOpacity = 1.0
                            }
                        }
                        .zIndex(9)
                }

                overlayChrome
                    .zIndex(10)
                profileNavigationLink
            }
            .background(Color.black)
        }
        .task {
            if selectedCountryIndex == 0 {
                // Initialize strictly from current location; if no coordinate yet, wait for onChange to update
                if let _ = locationProvider.coordinate {
                    let idx = countryIndex(for: locationProvider.coordinate)
                    selectedCountryIndex = idx
                }
            }
            showStatic = true
            playStaticSound()
            await reload()
            // brief static then fade
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run { withAnimation { showStatic = false } }
            stopStaticSound()
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.6)) {
                    launchLogoOpacity = 0
                    launchLogoScale = 1.05
                }
            }
            // Remove the logo overlay after the fade completes
            try? await Task.sleep(nanoseconds: 700_000_000)
            await MainActor.run { showLaunchLogo = false }
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
        }
        .onChange(of: showStatic) { visible in
            if visible {
                playStaticSound()
            } else {
                stopStaticSound()
            }
        }
        .onChange(of: coordinateKey) { _ in
            if posts.isEmpty {
                let idx = countryIndex(for: locationProvider.coordinate)
                if idx != selectedCountryIndex {
                    selectedCountryIndex = idx
                    Task { await reloadForCountry() }
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
            AsyncImage(url: URL(string: "https://picsum.photos/800/1400")) { phase in
                switch phase {
                case .empty:
                    Color.clear
                case .success(let img):
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                case .failure:
                    Color.black
                @unknown default:
                    Color.black
                }
            }
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

        await MainActor.run {
            posts = newPosts
            isLoading = false
            // If we couldn't load anything, mark as reached end to stop paginating.
            reachedEnd = newPosts.isEmpty
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
        await MainActor.run {
            posts = newPosts
            isLoading = false
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
            // Lower resolution image as per instruction
            let mediaURL = "https://picsum.photos/id/\(i % 100)/800/1400"
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
            let mediaURL = "https://picsum.photos/id/\(i % 100)/800/1400"
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

    private var coordinateText: String {
        String(format: "%.4f, %.4f", post.latitude, post.longitude)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Removed poster background AsyncImage block as per instruction

                if let url = URL(string: post.mediaURL) {
                    AsyncImage(url: url, transaction: Transaction(animation: .none)) { phase in
                        switch phase {
                        case .empty:
                            Color.black
                        case .success(let img):
                            img
                                .resizable()
                                .scaledToFill()
                                .frame(width: size.width, height: size.height)
                                .clipped()
                                .background(Color.black)
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

                VStack {
                    Spacer()
                    VerticalRadiusBar(
                        radius: Int(post.radius),
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
                .frame(width: size.width, height: size.height, alignment: .trailing)
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

