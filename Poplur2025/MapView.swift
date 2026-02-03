import SwiftUI
import MapKit
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import UserNotifications

struct MapView: View {
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    ))
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var loadError: String?

    // Location
    @State private var locationManager = CLLocationManager()
    @State private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    @State private var locationDelegateProxy: LocationDelegateProxy? = nil

    // Selection state for right-side radius bar
    @State private var selectedPostID: String?
    @State private var presentedCluster: PostCluster? = nil
    @State private var selectedRadius: Int = 0

    // Notification banner state
    @State private var banner: BannerData? = nil
    @State private var bannerOffset: CGFloat = -120
    @State private var bannerTimer: Timer? = nil

    struct BannerData: Identifiable, Equatable {
        let id = UUID()
        enum Kind { case suggestion, growth }
        let kind: Kind
        let title: String
        let message: String
        let action: (() -> Void)?

        static func == (lhs: BannerData, rhs: BannerData) -> Bool {
            // Compare by stable identity only; closures are not equatable
            return lhs.id == rhs.id
        }
    }

    // Simple AI suggestion stub – replace with your real AI
    private func aiSuggestedCoordinate(from posts: [Post]) -> CLLocationCoordinate2D? {
        // Example heuristic: suggest near the centroid of existing posts, slightly offset
        guard !posts.isEmpty else { return nil }
        let avgLat = posts.map { $0.latitude }.reduce(0, +) / Double(posts.count)
        let avgLon = posts.map { $0.longitude }.reduce(0, +) / Double(posts.count)
        // Offset a bit so it doesn't overlap exactly
        return CLLocationCoordinate2D(latitude: avgLat + 0.01, longitude: avgLon + 0.01)
    }

    // Detect a post whose viewCount has recently increased
    private func detectGrowingPost(old: [Post], new: [Post]) -> Post? {
        let oldMap = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0.viewCount) })
        // Find the post with the biggest positive delta
        var best: (post: Post, delta: Int)?
        for p in new {
            let delta = p.viewCount - (oldMap[p.id] ?? 0)
            if delta > 0 {
                if let current = best {
                    if delta > current.delta { best = (p, delta) }
                } else {
                    best = (p, delta)
                }
            }
        }
        return best?.post
    }

    private func showBanner(_ data: BannerData, autoHideAfter seconds: TimeInterval = 3.0) {
        banner = data
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            bannerOffset = 0
        }
        bannerTimer?.invalidate()
        bannerTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            hideBanner()
        }
    }

    private func hideBanner() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            bannerOffset = -120
        }
        // Clear after the animation to avoid tapable area lingering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            banner = nil
        }
    }

    // MARK: - Local Notifications
    private func requestNotificationAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
    }

    private static let notificationPostIDKey = "postID"
    private static let suggestionLatKey = "suggestionLat"
    private static let suggestionLonKey = "suggestionLon"
    private static let suggestionMessageKey = "suggestionMessage"

    // Call this from App/Scene delegate when a notification for a growing post is tapped
    static func postFocusRequest(postID: String) {
        NotificationCenter.default.post(name: .FocusPostFromNotification, object: nil, userInfo: [notificationPostIDKey: postID])
    }
    // Call this from App/Scene delegate when a suggestion notification is tapped
    static func suggestionFocusRequest(latitude: Double, longitude: Double, message: String) {
        NotificationCenter.default.post(name: .FocusSuggestionFromNotification, object: nil, userInfo: [
            suggestionLatKey: latitude,
            suggestionLonKey: longitude,
            suggestionMessageKey: message
        ])
    }

    private func scheduleGrowthNotification(for post: Post, delta: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Your post is expanding"
        content.body = "Radius is growing by \(delta)m near (\(String(format: "%.3f", post.latitude)), \(String(format: "%.3f", post.longitude)))"
        content.sound = .default
        content.userInfo = [MapView.notificationPostIDKey: post.id]
        content.categoryIdentifier = "GROWTH_CATEGORY"
        content.threadIdentifier = "growth_\(post.id)"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "growth_\(post.id)_\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    private func scheduleSuggestionNotification(title: String, message: String, coordinate: CLLocationCoordinate2D) {
        let content = UNMutableNotificationContent()
        // No separate title; show only the suggestion message
        content.title = ""
        content.body = message
        content.sound = .default
        content.userInfo = [
            MapView.suggestionLatKey: coordinate.latitude,
            MapView.suggestionLonKey: coordinate.longitude,
            MapView.suggestionMessageKey: message
        ]
        content.categoryIdentifier = "SUGGESTION_CATEGORY"
        content.threadIdentifier = "suggestion_\(UUID().uuidString)"
        // Randomize fire time slightly to avoid predictability
        let interval = TimeInterval.random(in: 3...10)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: "suggestion_\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // Constants for the side bar look
    private let sideBarMaxRadius = 10_000
    private let sideBarWidth: CGFloat = 10
    private let sideBarMaxHeight: CGFloat = 140
    private let sideBarColor: Color = .pink

    // Default region for reset
    private let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )

    // Group posts that share the exact same coordinate
    struct PostCluster: Identifiable, Equatable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let posts: [Post]
        var representative: Post { posts.first! }
        var count: Int { posts.count }
        var maxRadius: Int { posts.map { $0.radius }.max() ?? 0 }
        static func == (lhs: PostCluster, rhs: PostCluster) -> Bool { lhs.id == rhs.id }
    }

    private var clusteredPosts: [PostCluster] {
        // Quantize coordinates to ~10m grid (approx 0.0001 degrees ~ 11m latitude)
        let quant: Double = 0.0001
        func quantize(_ value: Double) -> Double { (value / quant).rounded() * quant }

        var dict: [String: [Post]] = [:]
        for p in posts {
            let qLat = quantize(p.latitude)
            let qLon = quantize(p.longitude)
            let key = "\(qLat),\(qLon)"
            dict[key, default: []].append(p)
        }
        return dict.map { (key, arr) in
            // Use the average coordinate of the cluster for stability
            let avgLat = arr.map { $0.latitude }.reduce(0, +) / Double(arr.count)
            let avgLon = arr.map { $0.longitude }.reduce(0, +) / Double(arr.count)
            let coord = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
            return PostCluster(id: key, coordinate: coord, posts: arr)
        }
    }

    var body: some View {
        ZStack {
            Map(position: $position) {
                ForEach(clusteredPosts) { cluster in
                    // Draw a halo sized to the largest radius in the cluster
                    MapCircle(center: cluster.coordinate, radius: CLLocationDistance(cluster.maxRadius))
                        .foregroundStyle(.blue.opacity(0.20))
                        .stroke(.blue.opacity(0.5), lineWidth: 2)

                    // Pin annotation with optional count badge
                    Annotation("", coordinate: cluster.coordinate) {
                        Button {
                            if cluster.count > 1 {
                                presentedCluster = cluster
                            } else {
                                onSelect(post: cluster.representative)
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 28, height: 28)
                                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                                Circle()
                                    .fill(sideBarColor.opacity(0.9))
                                    .frame(width: 20, height: 20)
                                if cluster.count > 1 {
                                    Text("\(cluster.count)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.85), in: Capsule())
                                        .overlay(
                                            Capsule().stroke(Color.white.opacity(0.9), lineWidth: 0.5)
                                        )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                    }
                }
            }
            .ignoresSafeArea(edges: .top)

            // Drop-down banner overlay
            VStack(spacing: 0) {
                if let banner {
                    BannerView(data: banner, color: sideBarColor) {
                        // Tap action
                        banner.action?()
                        hideBanner()
                    } closeAction: {
                        hideBanner()
                    }
                    .offset(y: bannerOffset)
                    .zIndex(2)
                }
                Spacer(minLength: 0)
            }
            .allowsHitTesting(true)

            VStack {
                HStack {
                    if isLoading {
                        ProgressView().tint(.gray)
                    }
                    if let err = loadError {
                        Text(err).font(.footnote).foregroundColor(.red)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                Spacer()
            }

            // Current location button (top-right)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        Task { await centerOnUserLocation() }
                    } label: {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(10)
                            .background(Color.white, in: Circle())
                            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .padding(.top, 8)
                }
                Spacer()
            }
            .allowsHitTesting(true)

            VStack {
                Spacer()
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: sideBarWidth / 2, style: .continuous)
                        .fill(Color.gray.opacity(0.18))
                        .frame(width: sideBarWidth, height: sideBarMaxHeight)

                    VerticalRadiusBar(
                        radius: selectedRadius,
                        maxRadius: sideBarMaxRadius,
                        width: sideBarWidth,
                        maxHeight: sideBarMaxHeight,
                        color: sideBarColor,
                        showsLabel: true,
                        labelFormat: { r in
                            r >= 1000 ? "\(r / 1000) km" : "\(r) m"
                        }
                    )
                    .frame(width: sideBarWidth, height: sideBarMaxHeight, alignment: .bottom)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedRadius)
                }
                .padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .allowsHitTesting(false)
        }
        .sheet(item: $presentedCluster) { cluster in
            ClusterPostsSheet(cluster: cluster) { post in
                // When a post is selected from the sheet, center and select it
                presentedCluster = nil
                onSelect(post: post)
            }
            .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
        }
        .task {
            requestNotificationAuthorizationIfNeeded()
            await loadRecentPosts()
            // Randomly schedule a suggestion notification sometime soon (does not show immediately on open)
            Task {
                let delay = Double.random(in: 30...120) // 30s to 2 minutes after opening
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await MainActor.run {
                    // Use example suggestions
                    let examples: [(String, String, CLLocationCoordinate2D)] = [
                        ("", "Post an image about Chinese food in Chinatown Market", CLLocationCoordinate2D(latitude: 40.715, longitude: -74.009)),
                        ("", "Post an image about Lamborghini in Italy", CLLocationCoordinate2D(latitude: 44.4949, longitude: 11.3426))
                    ]
                    if let pick = examples.randomElement() {
                        scheduleSuggestionNotification(title: pick.0, message: pick.1, coordinate: pick.2)
                    }
                }
            }
        }
        .onChange(of: posts) { oldValue, newValue in
            // Removed immediate AI suggestion banner and immediate suggestion notification scheduling to avoid showing on open

            // Growth detection (views rising or radius increasing)
            // Compute deltas for both viewCount and radius
            let oldByID = Dictionary(uniqueKeysWithValues: oldValue.map { ($0.id, $0) })
            var bestGrowth: (post: Post, viewDelta: Int, radiusDelta: Int)?
            for p in newValue {
                let old = oldByID[p.id]
                let vDelta = p.viewCount - (old?.viewCount ?? 0)
                let rDelta = p.radius - (old?.radius ?? p.radius)
                if vDelta > 0 || rDelta > 0 {
                    if let current = bestGrowth {
                        let score = vDelta * 2 + rDelta // simple scoring to pick the most significant growth
                        let currentScore = current.viewDelta * 2 + current.radiusDelta
                        if score > currentScore { bestGrowth = (p, vDelta, rDelta) }
                    } else {
                        bestGrowth = (p, vDelta, rDelta)
                    }
                }
            }
            if let growth = bestGrowth {
                let title = growth.radiusDelta > 0 ? "Post radius increased" : "Post is gaining traction"
                let message: String
                if growth.radiusDelta > 0 {
                    message = "+\(growth.radiusDelta)m radius near your post. Tap to zoom."
                } else {
                    message = "+\(growth.viewDelta) views near your post. Tap to zoom."
                }
                // In-app banner
                showBanner(BannerData(kind: .growth, title: title, message: message, action: { [post = growth.post] in
                    onSelect(post: post)
                }))
                // Local notification for radius increase
                if growth.radiusDelta > 0 {
                    scheduleGrowthNotification(for: growth.post, delta: growth.radiusDelta)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .LoadMapNow)) { _ in
            Task { await loadRecentPosts() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ResetTabToTop)) { _ in
            // Reset to default region and clear selection
            withAnimation(.easeInOut(duration: 0.25)) {
                position = .region(defaultRegion)
                selectedPostID = nil
                selectedRadius = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .FocusPostFromNotification)) { note in
            if let id = note.userInfo?[MapView.notificationPostIDKey] as? String,
               let post = posts.first(where: { $0.id == id }) {
                onSelect(post: post)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .FocusSuggestionFromNotification)) { note in
            let userInfo = note.userInfo ?? [:]
            if let lat = userInfo[MapView.suggestionLatKey] as? Double,
               let lon = userInfo[MapView.suggestionLonKey] as? Double {
                let message = (userInfo[MapView.suggestionMessageKey] as? String) ?? "Suggested place to post"
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                withAnimation(.easeInOut(duration: 0.35)) {
                    position = .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)))
                }
                showBanner(BannerData(kind: .suggestion, title: "", message: message, action: { [coord] in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        position = .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)))
                    }
                }))
            }
        }
    }

    @MainActor
    private func onSelect(post: Post) {
        selectedPostID = post.id
        selectedRadius = min(max(0, post.radius), sideBarMaxRadius)
        withAnimation(.easeInOut(duration: 0.35)) {
            position = .region(MKCoordinateRegion(center: post.coordinate,
                                                  span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)))
        }
    }

    private func loadRecentPosts() async {
        let started = await MainActor.run { () -> Bool in
            if isLoading { return false }
            isLoading = true
            loadError = nil
            return true
        }
        guard started else { return }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let fetched = try await fetchMyMapPosts()
            await MainActor.run {
                posts = fetched
                if let firstCluster = clusteredPosts.first {
                    let first = firstCluster.representative
                    selectedPostID = first.id
                    selectedRadius = min(max(0, first.radius), sideBarMaxRadius)
                    position = .region(MKCoordinateRegion(center: first.coordinate,
                                                          span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)))
                }
            }
        } catch {
            await MainActor.run {
                loadError = "Map load failed: \(error.localizedDescription)"
            }
        }
    }

    private func fetchMyMapPosts(maxCount: Int = 10) async throws -> [Post] {
        try await withCheckedThrowingContinuation { cont in
            guard let uid = Auth.auth().currentUser?.uid else {
                cont.resume(returning: [])
                return
            }
            let db = Firestore.firestore()

            // Helper to map a snapshot to [Post]
            func mapSnapshot(_ snap: QuerySnapshot?, defaultUserID: String) -> [Post] {
                guard let snap else { return [] }
                var result: [Post] = []
                result.reserveCapacity(snap.documents.count)
                for doc in snap.documents {
                    let data = doc.data()
                    guard let lat = (data["latitude"] as? Double) ?? (data["latitude"] as? NSNumber)?.doubleValue,
                          let lon = (data["longitude"] as? Double) ?? (data["longitude"] as? NSNumber)?.doubleValue,
                          let mediaURL = data["mediaURL"] as? String
                    else { continue }
                    let radius = (data["radius"] as? Int) ?? (data["radius"] as? NSNumber)?.intValue ?? 5000
                    let viewCount = (data["viewCount"] as? Int) ?? (data["viewCount"] as? NSNumber)?.intValue ?? 0
                    let userID = data["userID"] as? String ?? defaultUserID
                    result.append(Post(id: doc.documentID, latitude: lat, longitude: lon, mediaURL: mediaURL, radius: radius, viewCount: viewCount, userID: userID))
                }
                return result
            }

            // First attempt: ordered query by createdAt (most recent first)
            db.collection("posts")
                .whereField("userID", isEqualTo: uid)
                .order(by: "createdAt", descending: true)
                .limit(to: maxCount)
                .getDocuments { snap, err in
                    if let err {
                        print("[Map] Ordered query failed (will fallback without order): \(err.localizedDescription)")
                        // Fallback: same filter, no order
                        db.collection("posts")
                            .whereField("userID", isEqualTo: uid)
                            .limit(to: maxCount)
                            .getDocuments { fallbackSnap, fallbackErr in
                                if let fallbackErr {
                                    cont.resume(throwing: fallbackErr)
                                    return
                                }
                                let mapped = mapSnapshot(fallbackSnap, defaultUserID: uid)
                                cont.resume(returning: mapped)
                            }
                        return
                    }
                    let mapped = mapSnapshot(snap, defaultUserID: uid)
                    cont.resume(returning: mapped)
                }
        }
    }

    @MainActor
    private func requestLocationAuthorizationIfNeeded() {
        let status = CLLocationManager.authorizationStatus()
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private func currentLocation() async -> CLLocation? {
        await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                // Ensure we keep a strong reference to the proxy
                if locationDelegateProxy == nil {
                    locationDelegateProxy = LocationDelegateProxy { loc in
                        cont.resume(returning: loc)
                        locationContinuation = nil
                    }
                } else {
                    locationDelegateProxy?.handler = { loc in
                        cont.resume(returning: loc)
                        locationContinuation = nil
                    }
                }

                locationContinuation = cont
                locationManager.delegate = locationDelegateProxy
                locationManager.desiredAccuracy = kCLLocationAccuracyBest
                locationManager.requestLocation()
            }
        }
    }

    @MainActor
    private func centerOnUserLocation() async {
        requestLocationAuthorizationIfNeeded()
        let loc = await currentLocation()
        guard let loc else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            position = .region(MKCoordinateRegion(center: loc.coordinate,
                                                  span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))
        }
    }
}

extension Notification.Name {
    static let LoadMapNow = Notification.Name("LoadMapNow")
    static let FocusPostFromNotification = Notification.Name("FocusPostFromNotification")
    static let FocusSuggestionFromNotification = Notification.Name("FocusSuggestionFromNotification")
}
private final class LocationDelegateProxy: NSObject, CLLocationManagerDelegate {
    var handler: (CLLocation?) -> Void
    init(handler: @escaping (CLLocation?) -> Void) { self.handler = handler }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        handler(locations.last)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Map] Location error: \(error)")
        handler(nil)
    }
}

private extension Post {
    // Use existing id if available; otherwise synthesize from coordinates and radius
    var _id: String {
        if let existing = (self as AnyObject) as? Identifiable { return (existing as! any Identifiable).id as? String ?? id }
        return id
    }
}

struct ClusterPostsSheet: View {
    let cluster: MapView.PostCluster
    let onSelect: (Post) -> Void
    var body: some View {
        NavigationStack {
            List(cluster.posts, id: \.id) { post in
                Button {
                    onSelect(post)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.pink)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Radius: \(post.radius) m")
                                .font(.subheadline).bold()
                            Text("Lat: \(post.latitude), Lon: \(post.longitude)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("\(cluster.count) post\(cluster.count == 1 ? "" : "s") here")
        }
    }
}

struct BannerView: View {
    let data: MapView.BannerData
    let color: Color
    let tapAction: () -> Void
    let closeAction: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background((data.kind == .suggestion ? Color.pink : color).opacity(0.95), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    if !data.title.isEmpty {
                        Text(data.title.uppercased())
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(.white)
                    }
                    Text(data.message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.95))
                }
                Spacer()
                Button(action: closeAction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill((data.kind == .suggestion ? Color.pink : color).gradient.opacity(0.92))
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 6)
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .onTapGesture(perform: tapAction)
        }
    }

    private var iconName: String {
        switch data.kind {
        case .suggestion: return "lightbulb.max.fill"
        case .growth: return "chart.line.uptrend.xyaxis"
        }
    }
}

/*
 To deep-link from a tapped notification to the map and focus the post, forward the notification response like:
 
 // In your App/Scene delegate UNUserNotificationCenterDelegate method:
 // func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
 //     let userInfo = response.notification.request.content.userInfo
 //     if let postID = userInfo[MapView.notificationPostIDKey] as? String {
 //         MapView.postFocusRequest(postID: postID)
 //     }
 //     completionHandler()
 // }
 
 // If the notification is a suggestion with coordinates:
 // if let lat = userInfo[MapView.suggestionLatKey] as? Double,
 //    let lon = userInfo[MapView.suggestionLonKey] as? Double {
 //     let msg = (userInfo[MapView.suggestionMessageKey] as? String) ?? "Suggested place to post"
 //     MapView.suggestionFocusRequest(latitude: lat, longitude: lon, message: msg)
 // }
*/
