import SwiftUI
import MapKit
import FirebaseFirestore
import FirebaseAuth
import SceneKit
import CoreLocation
import UserNotifications
#if canImport(GoogleMaps3D)
import GoogleMaps3D
#endif

enum GoogleMaps3DConfig {
    static let apiKey: String = "AIzaSyDgMYA1YisgbpEGyl0Nj8VGoorbqmfAkG0"
}

extension Notification.Name {
    static let startDominanceTour = Notification.Name("StartDominanceTour")
    static let stopDominanceTour = Notification.Name("StopDominanceTour")
    static let setTourSpeedMultiplier = Notification.Name("SetTourSpeedMultiplier")
}

// MARK: - Constants (LOCKED CAMERA VALUES)
private let fixedDistance: CLLocationDistance = 1039   // 🔒 zoom / height
private let fixedPitch: CGFloat = 68                   // 🔒 pitch

// MARK: - Models
private struct MapAnnotationPost: Identifiable, Hashable {
    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
    let radius: Double

    static func == (lhs: MapAnnotationPost, rhs: MapAnnotationPost) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - City Dominance (Fake demo data)
private struct CityDominance: Identifiable {
    let id = UUID()
    let city: String
    let coordinate: CLLocationCoordinate2D
    let username: String
    let profileURL: URL
}

private func demoDominanceCities() -> [CityDominance] {
    // Simple pool of fake usernames and profile images
    let names: [String] = [
        "FAKE USER 1", "FAKE USER 2", "FAKE USER 3", "FAKE USER 4", "FAKE USER 5",
        "FAKE USER 6", "FAKE USER 7", "FAKE USER 8", "FAKE USER 9", "FAKE USER 10"
    ]
    func randomFaceURL() -> URL {
        // Use picsum as placeholder faces; stable seed by city name could be added
        let id = Int.random(in: 1...10_000)
        return URL(string: "https://picsum.photos/seed/\(id)/200/200")!
    }

    let cities: [(String, CLLocationDegrees, CLLocationDegrees)] = [
        ("New York", 40.7128, -74.0060),
        ("Los Angeles", 34.0522, -118.2437),
        ("Chicago", 41.8781, -87.6298),
        ("London", 51.5074, -0.1278),
        ("Paris", 48.8566, 2.3522),
        ("Berlin", 52.5200, 13.4050),
        ("Tokyo", 35.6762, 139.6503),
        ("Seoul", 37.5665, 126.9780),
        ("Shanghai", 31.2304, 121.4737),
        ("Hong Kong", 22.3193, 114.1694),
        ("Sydney", -33.8688, 151.2093),
        ("Melbourne", -37.8136, 144.9631),
        ("Toronto", 43.6532, -79.3832),
        ("Vancouver", 49.2827, -123.1207),
        ("Mexico City", 19.4326, -99.1332),
        ("São Paulo", -23.5558, -46.6396),
        ("Buenos Aires", -34.6037, -58.3816),
        ("Johannesburg", -26.2041, 28.0473),
        ("Cairo", 30.0444, 31.2357),
        ("Dubai", 25.2048, 55.2708),
        ("Istanbul", 41.0082, 28.9784),
        ("Moscow", 55.7558, 37.6173),
        ("Rome", 41.9028, 12.4964),
        ("Madrid", 40.4168, -3.7038)
    ]

    var result: [CityDominance] = []
    result.reserveCapacity(cities.count)
    for (name, lat, lon) in cities {
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let username = names.randomElement() ?? "USER"
        let profile = randomFaceURL()
        result.append(CityDominance(city: name, coordinate: coord, username: username, profileURL: profile))
    }
    return result
}

// MARK: - Location Manager
private final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var location: CLLocation?
    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func requestAuthorizationIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func centerOnUser(_ camera: inout MapCameraPosition) {
        guard let loc = location else { return }
        camera = .camera(
            MapCamera(
                centerCoordinate: loc.coordinate,
                distance: fixedDistance,
                heading: 0,
                pitch: fixedPitch
            )
        )
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }
}

// MARK: - Google Style Pin
private struct GoogleStylePin: View {
    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(.white, lineWidth: 2))

            Triangle()
                .fill(.red)
                .frame(width: 10, height: 12)
                .offset(y: -1)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Dominance Pin
private struct DominancePin: View {
    let profileURL: URL
    var body: some View {
        AsyncImage(url: profileURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            default:
                Circle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
        }
    }
}

// MARK: - Map View
struct MapView: View {
    @StateObject private var locationManager = LocationManager()
    // @Environment(\.isometricBarSettings) private var barSettings
    // @Environment(\.isometricRadiusBarDistance) private var isometricRadiusBarDistance

    @State private var camera: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 40.748339, longitude: -73.985912),
            distance: fixedDistance,
            heading: 52,
            pitch: fixedPitch
        )
    )

    @State private var posts: [MapAnnotationPost] = []
    @State private var selectedIndex: Int?
    @State private var radiusMeters: Double = 5_000

    @State private var dominance: [CityDominance] = demoDominanceCities()
    @State private var tourTask: Task<Void, Never>? = nil
    @State private var tourActive: Bool = false
    @State private var tourIndex: Int = 0
    @State private var tourSpeedMultiplier: Double = 1.0

    @State private var idleTask: Task<Void, Never>? = nil
    @State private var lastInteractionAt: Date = Date()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            mapLayer
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in noteInteraction() })
                .simultaneousGesture(TapGesture().onEnded { noteInteraction() })
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
#if DEBUG
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                locationManager.requestAuthorizationIfNeeded()
            }
#else
            locationManager.requestAuthorizationIfNeeded()
#endif
            // Normalize camera to fixed pitch/distance so tiles render immediately
            if let current = camera.camera {
                camera = .camera(
                    MapCamera(
                        centerCoordinate: current.centerCoordinate,
                        distance: fixedDistance,
                        heading: current.heading,
                        pitch: fixedPitch
                    )
                )
            }
            fetchPosts()
            scheduleIdleCheck()
        }
        .onDisappear {
            stopDominanceTour()
            idleTask?.cancel()
            idleTask = nil
        }
        .onChange(of: locationManager.location) { _, _ in
#if DEBUG
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
#endif
            // Center only once when we get the first location fix
            if let _ = locationManager.location {
                locationManager.centerOnUser(&camera)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .CenterMapOnUser)) { _ in
#if DEBUG
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
#endif
            stopDominanceTour()
            // Get user coordinate if available
            guard let userCoord = locationManager.location?.coordinate else {
                // Fallback to instant center if we don't have a fix yet
                locationManager.centerOnUser(&camera)
                noteInteraction()
                return
            }

            // 1) Zoom out from current position
            withAnimation(.easeInOut(duration: 2.0 * tourSpeedMultiplier)) {
                let currentCenter = camera.camera?.centerCoordinate ?? userCoord
                let currentHeading = camera.camera?.heading ?? 0
                camera = .camera(
                    MapCamera(
                        centerCoordinate: currentCenter,
                        distance: max(fixedDistance * 6, 6000),
                        heading: currentHeading,
                        pitch: fixedPitch
                    )
                )
            }

            Task { @MainActor in
                // Small pause
                try? await Task.sleep(nanoseconds: UInt64(1_200_000_000.0 * tourSpeedMultiplier))
                // 2) Fly to user at zoomed-out distance
                withAnimation(.easeInOut(duration: 3.0 * tourSpeedMultiplier)) {
                    camera = .camera(
                        MapCamera(
                            centerCoordinate: userCoord,
                            distance: max(fixedDistance * 6, 6000),
                            heading: camera.camera?.heading ?? 0,
                            pitch: fixedPitch
                        )
                    )
                }
                // Small pause
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000.0 * tourSpeedMultiplier))
                // 3) Zoom back in
                withAnimation(.easeInOut(duration: 2.0 * tourSpeedMultiplier)) {
                    camera = .camera(
                        MapCamera(
                            centerCoordinate: userCoord,
                            distance: fixedDistance,
                            heading: camera.camera?.heading ?? 0,
                            pitch: fixedPitch
                        )
                    )
                }
                // Dwell briefly after landing on user
                try? await Task.sleep(nanoseconds: UInt64(3_000_000_000.0 * tourSpeedMultiplier))
                noteInteraction()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startDominanceTour)) { _ in
            startDominanceTour()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopDominanceTour)) { _ in
            stopDominanceTour()
        }
        .onReceive(NotificationCenter.default.publisher(for: .setTourSpeedMultiplier)) { note in
            if let value = note.userInfo?["multiplier"] as? Double {
                tourSpeedMultiplier = max(0.1, min(5.0, value))
            }
        }
    }

    // MARK: - Map Layer (LOCKED ZOOM)
    private var mapLayer: some View {
        // Choose interaction modes at runtime (previews vs app)
        let modes: MapInteractionModes = {
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                return [.pan]
            }
            #endif
            return [.pan, .rotate]
        }()

        return Map(
            position: Binding(
                get: { camera },
                set: { camera = lockCamera($0) }
            ),
            interactionModes: modes
        ) {
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                if locationManager.location != nil {
                    UserAnnotation {
                        Label("You", systemImage: "location.fill")
                    }
                }
            }
            #else
            if locationManager.location != nil {
                UserAnnotation {
                    Label("You", systemImage: "location.fill")
                }
            }
            #endif

            ForEach(filteredPosts()) { post in
                Annotation(coordinate: post.coordinate) {
                    GoogleStylePin()
                } label: {
                    Text(post.title)
                }

                MapCircle(center: post.coordinate, radius: post.radius)
                    .foregroundStyle(.blue.opacity(0.15))
                    .stroke(.blue.opacity(0.6), lineWidth: 1)
            }
            
            ForEach(dominance) { dom in
                Annotation(coordinate: dom.coordinate) {
                    DominancePin(profileURL: dom.profileURL)
                } label: {
                    Text(dom.city)
                }
            }
        }
        .mapStyle(
            (ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1")
            ? .standard
            : .hybrid(elevation: .realistic)
        )
    }

    // MARK: - Camera Lock
    private func lockCamera(_ pos: MapCameraPosition) -> MapCameraPosition {
        pos.camera.map {
            .camera(
                MapCamera(
                    centerCoordinate: $0.centerCoordinate,
                    distance: fixedDistance,
                    heading: $0.heading,
                    pitch: fixedPitch
                )
            )
        } ?? pos
    }


    // MARK: - Navigation
    private func panTo(_ coordinate: CLLocationCoordinate2D) {
        let heading = camera.camera?.heading ?? 0
        withAnimation(.easeInOut(duration: 0.8)) {
            camera = .camera(
                MapCamera(
                    centerCoordinate: coordinate,
                    distance: fixedDistance,
                    heading: heading,
                    pitch: fixedPitch
                )
            )
        }
    }

    private func cyclePost(direction: Int) {
        let items = filteredPosts()
        guard !items.isEmpty else { return }

        if let idx = selectedIndex {
            selectedIndex = (idx + direction + items.count) % items.count
        } else {
            selectedIndex = 0
        }

        if let idx = selectedIndex {
            panTo(items[idx].coordinate)
        }
    }

    // MARK: - Data
    private func filteredPosts() -> [MapAnnotationPost] {
        guard let userLoc = locationManager.location else { return posts }
        return posts.filter {
            MKMapPoint(userLoc.coordinate).distance(to: MKMapPoint($0.coordinate)) <= radiusMeters
        }
    }

    private func fetchPosts() {
        // Skip Firebase network calls when running SwiftUI previews
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            posts = [
                MapAnnotationPost(
                    id: "1",
                    title: "Preview A",
                    coordinate: CLLocationCoordinate2D(latitude: 40.748339, longitude: -73.985912),
                    radius: 5000
                ),
                MapAnnotationPost(
                    id: "2",
                    title: "Preview B",
                    coordinate: CLLocationCoordinate2D(latitude: 40.758896, longitude: -73.985130),
                    radius: 3000
                )
            ]
            return
        }
        Firestore.firestore().collection("posts").getDocuments { snap, _ in
            posts = snap?.documents.compactMap { doc in
                let d = doc.data()
                guard let lat = d["latitude"] as? CLLocationDegrees,
                      let lon = d["longitude"] as? CLLocationDegrees else { return nil }

                return MapAnnotationPost(
                    id: doc.documentID,
                    title: d["title"] as? String ?? "Post",
                    coordinate: .init(latitude: lat, longitude: lon),
                    radius: (d["radius"] as? Double) ?? 5_000
                )
            } ?? []
        }
    }

    private func startDominanceTour() {
        tourTask?.cancel()
        tourActive = true
        tourTask = Task { @MainActor in
            while !Task.isCancelled, tourActive, !dominance.isEmpty {
                let dom = dominance[tourIndex % dominance.count]
                // Zoom out significantly and prepare to move towards the destination
                withAnimation(.easeInOut(duration: 2.0 * tourSpeedMultiplier)) {
                    let currentCenter = camera.camera?.centerCoordinate ?? dom.coordinate
                    let currentHeading = camera.camera?.heading ?? 0
                    camera = .camera(
                        MapCamera(
                            centerCoordinate: currentCenter,
                            distance: max(fixedDistance * 10, 12000),
                            heading: currentHeading,
                            pitch: fixedPitch
                        )
                    )
                }
                // Let the map settle
                try? await Task.sleep(nanoseconds: UInt64(1_200_000_000.0 * tourSpeedMultiplier))

                // Fly to target city at zoomed-out distance
                withAnimation(.easeInOut(duration: 3.0 * tourSpeedMultiplier)) {
                    camera = .camera(
                        MapCamera(
                            centerCoordinate: dom.coordinate,
                            distance: max(fixedDistance * 10, 12000),
                            heading: camera.camera?.heading ?? 0,
                            pitch: fixedPitch
                        )
                    )
                }
                // Allow tiles to begin loading
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000.0 * tourSpeedMultiplier))

                // Zoom back in slowly to fixed distance at target
                withAnimation(.easeInOut(duration: 2.0 * tourSpeedMultiplier)) {
                    camera = .camera(
                        MapCamera(
                            centerCoordinate: dom.coordinate,
                            distance: fixedDistance,
                            heading: camera.camera?.heading ?? 0,
                            pitch: fixedPitch
                        )
                    )
                }

                // Dwell longer at the destination to allow tiles/labels to fully render
                try? await Task.sleep(nanoseconds: UInt64(15_000_000_000.0 * tourSpeedMultiplier))

                tourIndex = (tourIndex + 1) % dominance.count
            }
        }
    }

    private func stopDominanceTour() {
        tourActive = false
        tourTask?.cancel()
        tourTask = nil
    }
    
    private func scheduleIdleCheck() {
        idleTask?.cancel()
        idleTask = Task { @MainActor in
            // let start = Date()
            // Wait until 15 seconds after the most recent interaction time
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // check every 1s
                let elapsed = Date().timeIntervalSince(lastInteractionAt)
                if elapsed >= 15.0 {
                    startDominanceTour()
                    break
                }
            }
        }
    }

    private func noteInteraction() {
        lastInteractionAt = Date()
        stopDominanceTour()
        scheduleIdleCheck()
    }
}

#if DEBUG
private struct MapViewPreviewHost: View {
    @State private var camera: MapCameraPosition? = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 40.748339, longitude: -73.985912),
            distance: 1039,
            heading: 52,
            pitch: 68
        )
    )

    var body: some View {
        Map(
            position: Binding(
                get: { camera ?? .automatic },
                set: { camera = $0 }
            ),
            interactionModes: [.pan]
        ) {
            Annotation(coordinate: CLLocationCoordinate2D(latitude: 40.748339, longitude: -73.985912)) {
                Circle().fill(Color.red).frame(width: 12, height: 12)
            } label: {
                Text("Preview")
            }
        }
        .mapStyle(.standard)
    }
}
#endif

#Preview("Map Tour Preview") {
    #if DEBUG
    MapViewPreviewHost()
    #else
    MapView()
    #endif
}

