import SwiftUI
import MapKit
import FirebaseAuth
import FirebaseFirestore
import CoreLocation

struct MapView: View {
    // Region will continuously follow user when coordinates update, unless a post is selected.
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var posts: [Post] = []
    @State private var annotations: [PostAnnotation] = []
    // Side bar shows the selected post's radius
    @State private var selectedPost: Post?

    // Tune this as needed for your product
    private let maxRadiusForBar: Int = 10_000

    // Location handling
    @StateObject private var locationManager = MapLocationManager()
    @State private var showLocationAlert = false
    @State private var locationAlertMessage = ""

    // Deterministic preload readiness
    @State private var didFetchPosts = false
    @State private var didGetFirstLocationOrAuth = false

    private var isReady: Bool {
        didFetchPosts && didGetFirstLocationOrAuth
    }

    // Brand color (sRGB) #FF2D96 for the side bar
    private let brandPink = Color(red: 1.0, green: 45.0/255.0, blue: 150.0/255.0)

    // MARK: - Post navigation helpers

    private var selectedIndex: Int? {
        guard let sel = selectedPost else { return nil }
        return posts.firstIndex(where: { $0.id == sel.id })
    }

    private func selectPost(at index: Int) {
        guard posts.indices.contains(index) else { return }
        let post = posts[index]
        selectedPost = post
        let coord = CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude)
        withAnimation(.easeInOut(duration: 0.25)) {
            region.center = coord
            // Keep same zoom level
        }
    }

    private func selectPreviousPost() {
        guard !posts.isEmpty else { return }
        let current = selectedIndex ?? 0
        let prev = (current - 1 + posts.count) % posts.count
        selectPost(at: prev)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func selectNextPost() {
        guard !posts.isEmpty else { return }
        let current = selectedIndex ?? -1
        let next = (current + 1) % posts.count
        selectPost(at: next)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Recenter to user

    private func recenterToUser() {
        guard let coord = locationManager.coordinate else { return }
        // Clear selection so auto-follow can resume if desired
        selectedPost = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            region.center = coord
            // Maintain same zoom span
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ZStack {
                    Map(
                        coordinateRegion: $region,
                        interactionModes: .all,
                        showsUserLocation: true,
                        annotationItems: annotations
                    ) { annotation in
                        MapAnnotation(coordinate: annotation.coordinate) {
                            Button {
                                // Select this post to update the side bar and stop auto-follow
                                selectedPost = annotation.post
                            } label: {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
                                    .shadow(radius: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .edgesIgnoringSafeArea(.all)

                    // Left/right transparent tap zones overlay
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { selectPreviousPost() }
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { selectNextPost() }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(true)
                    }

                    // Recenter button (top-left)
                    VStack {
                        HStack {
                            Button {
                                recenterToUser()
                            } label: {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .padding(.leading, 16)
                            .padding(.top, 16)
                            Spacer()
                        }
                        Spacer()
                    }
                    .allowsHitTesting(true)
                }

                if posts.isEmpty {
                    Text("No posts available.")
                        .foregroundColor(.gray)
                        .padding(.top, 8)
                }
            }

            // Right-pinned side bar showing the selected post's radius
            if let selected = selectedPost {
                VStack {
                    Spacer()
                    VerticalRadiusBar(
                        radius: selected.radius,
                        maxRadius: maxRadiusForBar,
                        width: 10,
                        maxHeight: 160,
                        color: brandPink, // brand pink
                        showsLabel: true,
                        labelFormat: { r in
                            if r >= 1000 {
                                return "\(r / 1000) km"
                            } else {
                                return "\(r) m"
                            }
                        }
                    )
                    .padding(.trailing, 12)
                    .padding(.bottom, 32) // keep above any bottom bars
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .allowsHitTesting(false) // bar is visual only; taps pass through to map
            }
        }
        .onAppear {
            // Start location updates
            locationManager.requestWhenInUse()
            // Load posts for the current user
            fetchPosts()
            // If authorization is already determined (even if denied), we can consider that part of readiness
            updateLocationReadinessFromAuthStatus(locationManager.authorizationStatus)
        }
        // Recenter on coordinate updates only if no post is selected (so navigation isn't overridden)
        .onReceive(locationManager.$coordinate.compactMap { $0 }) { coord in
            if selectedPost == nil {
                withAnimation(.easeInOut(duration: 0.2)) {
                    region.center = coord
                    region.span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                }
            }
            // First coordinate received -> mark location readiness
            if !didGetFirstLocationOrAuth {
                didGetFirstLocationOrAuth = true
            }
        }
        .onReceive(locationManager.$authorizationStatus) { status in
            switch status {
            case .denied, .restricted:
                locationAlertMessage = "Location access is disabled. Enable it in Settings to keep the map centered on your current location."
                showLocationAlert = true
            default:
                break
            }
            // If auth moved from notDetermined to any decided state but no location yet, we can still mark readiness
            updateLocationReadinessFromAuthStatus(status)
        }
        .alert("Location Access", isPresented: $showLocationAlert) {
            Button("OK", role: .cancel) { }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        } message: {
            Text(locationAlertMessage)
        }
        // Publish readiness to HomeView’s preloader
        .preference(key: MapReadyPreferenceKey.self, value: isReady)
    }

    private func updateLocationReadinessFromAuthStatus(_ status: CLAuthorizationStatus) {
        // Consider location portion "ready" once auth is decided (not .notDetermined),
        // even if denied/restricted, to avoid blocking preload forever.
        if status != .notDetermined && !didGetFirstLocationOrAuth {
            didGetFirstLocationOrAuth = true
        }
    }

    func fetchPosts() {
        // Fetch posts from Firestore and create annotations
        if let userId = Auth.auth().currentUser?.uid {
            let db = Firestore.firestore()
            db.collection("posts").whereField("userID", isEqualTo: userId).getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching posts: \(error.localizedDescription)")
                    // Mark fetch as done even on error to avoid blocking preload forever
                    if !didFetchPosts { didFetchPosts = true }
                    return
                }

                // Parse posts and create annotations
                self.posts = snapshot?.documents.compactMap { document -> Post? in
                    let data = document.data()
                    return Post(
                        id: document.documentID,
                        latitude: data["latitude"] as? Double ?? 0.0,
                        longitude: data["longitude"] as? Double ?? 0.0,
                        mediaURL: data["mediaURL"] as? String ?? "",
                        radius: data["radius"] as? Int ?? 0,
                        viewCount: data["viewCount"] as? Int ?? 0
                    )
                } ?? []

                // Create annotations for the posts
                self.annotations = self.posts.map { post in
                    PostAnnotation(post: post)
                }

                // If nothing selected yet, optionally select the first post
                if selectedPost == nil, let first = self.posts.first {
                    selectedPost = first
                }

                // Mark fetch portion as ready after first completion
                if !didFetchPosts { didFetchPosts = true }
            }
        } else {
            // No user -> treat as empty state but still mark fetch as complete
            self.posts = []
            self.annotations = []
            if !didFetchPosts { didFetchPosts = true }
        }
    }
}

// MARK: - Location Manager for MapView

final class MapLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // manager.distanceFilter = 20 // optional tuning
    }

    func requestWhenInUse() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            authorizationStatus = manager.authorizationStatus
        @unknown default:
            authorizationStatus = manager.authorizationStatus
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last?.coordinate
        // Keep updating to always follow the user
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error.localizedDescription)")
    }
}

// MARK: - Existing Models

struct PostAnnotation: Identifiable {
    var id = UUID() // Unique identifier for the annotation
    var post: Post

    var coordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude)
    }
}

struct Post: Identifiable {
    var id: String
    var latitude: Double
    var longitude: Double
    var mediaURL: String
    var radius: Int
    var viewCount: Int
}

struct MapView_Previews: PreviewProvider {
    static var previews: some View {
        MapView()
    }
}

// MARK: - Readiness PreferenceKey for MapView

struct MapReadyPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
