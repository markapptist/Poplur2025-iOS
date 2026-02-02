import SwiftUI
import MapKit
import FirebaseFirestore
import CoreLocation

struct MapView: View {
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var loadError: String?

    // Location
    @State private var locationManager = CLLocationManager()
    @State private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    @State private var locationDelegateProxy: LocationDelegateProxy? = nil

    // Selection state for right-side radius bar
    @State private var selectedPostID: String?
    @State private var selectedRadius: Int = 0

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

    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, annotationItems: posts) { post in
                MapAnnotation(coordinate: post.coordinate) {
                    Button {
                        onSelect(post: post)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 28, height: 28)
                                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                            Circle()
                                .fill(sideBarColor.opacity(0.9))
                                .frame(width: 20, height: 20)
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                }
            }
            .ignoresSafeArea(edges: .top)

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
        .task { await loadRecentPosts() }
        .onReceive(NotificationCenter.default.publisher(for: .LoadMapNow)) { _ in
            Task { await loadRecentPosts() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ResetTabToTop)) { _ in
            // Reset to default region and clear selection
            withAnimation(.easeInOut(duration: 0.25)) {
                region = defaultRegion
                selectedPostID = nil
                selectedRadius = 0
            }
        }
    }

    @MainActor
    private func onSelect(post: Post) {
        selectedPostID = post.id
        selectedRadius = min(max(0, post.radius), sideBarMaxRadius)
        withAnimation(.easeInOut(duration: 0.35)) {
            region.center = post.coordinate
            region.span = MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
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
            let fetched = try await fetchRecentPosts()
            await MainActor.run {
                posts = fetched
                if let first = fetched.first {
                    selectedPostID = first.id
                    selectedRadius = min(max(0, first.radius), sideBarMaxRadius)
                    region.center = first.coordinate
                    region.span = MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
                }
            }
        } catch {
            await MainActor.run {
                loadError = "Map load failed: \(error.localizedDescription)"
            }
        }
    }

    private func fetchRecentPosts() async throws -> [Post] {
        try await withCheckedThrowingContinuation { cont in
            let db = Firestore.firestore()
            db.collection("posts")
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
                .getDocuments { snap, err in
                    if let err { cont.resume(throwing: err); return }
                    guard let snap else { cont.resume(returning: []); return }
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
                        let userID = data["userID"] as? String ?? "unknown"
                        result.append(Post(id: doc.documentID, latitude: lat, longitude: lon, mediaURL: mediaURL, radius: radius, viewCount: viewCount, userID: userID))
                    }
                    cont.resume(returning: result)
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
            region.center = loc.coordinate
            region.span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        }
    }
}

extension Notification.Name {
    static let LoadMapNow = Notification.Name("LoadMapNow")
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

