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
    static let setTourZoomOutDistance = Notification.Name("SetTourZoomOutDistance")
    static let CenterMapOnUser = Notification.Name("CenterMapOnUser")
}

// MARK: - Constants (LOCKED CAMERA VALUES)
private let fixedDistance: CLLocationDistance = 1600   // 🔒 zoom / height
private let fixedPitch: CGFloat = 52                   // 🔒 pitch

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
    
    @State private var tourZoomOutDistance: CLLocationDistance = 25_000_000 // far enough to see the planet
    @State private var showFavorites: Bool = false
    @State private var showSearch: Bool = false
    @State private var searchQuery: String = ""
    @State private var searchResults: [MKMapItem] = []

    @State private var idleTask: Task<Void, Never>? = nil
    @State private var lastInteractionAt: Date = Date()

    var body: some View {
        ZStack {
            mapLayer
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in noteInteraction() })
                .simultaneousGesture(TapGesture().onEnded { noteInteraction() })
            
            // Top-left Search button
            VStack {
                HStack {
                    Button(action: { showSearch.toggle() }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    Button(action: { showFavorites.toggle() }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding([.top, .horizontal])
                Spacer()
            }
            
            // Favorites sheet
            .sheet(isPresented: $showFavorites) {
                FavoritesListView(
                    onSelect: { coord in panTo(coord) },
                    currentCenter: camera.camera?.centerCoordinate,
                    userLocation: locationManager.location?.coordinate
                )
                .presentationDetents([.medium, .large])
            }
            // Search sheet
            .sheet(isPresented: $showSearch) {
                SearchView(query: $searchQuery, results: $searchResults) { item in
                    if let coord = item.placemark.location?.coordinate {
                        panTo(coord)
                    }
                }
                .presentationDetents([.medium, .large])
            }
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
                camera = .camera(
                    MapCamera(
                        centerCoordinate: currentCenter,
                        distance: max(tourZoomOutDistance, 12_000),
                        heading: 0,
                        pitch: (max(tourZoomOutDistance, 12_000) >= 20_000_000 ? 0 : fixedPitch)
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
                            distance: max(tourZoomOutDistance, 12_000),
                            heading: 0,
                            pitch: (max(tourZoomOutDistance, 12_000) >= 20_000_000 ? 0 : fixedPitch)
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
        .onReceive(NotificationCenter.default.publisher(for: .setTourZoomOutDistance)) { note in
            if let value = note.userInfo?["zoomOutDistance"] as? Double {
                tourZoomOutDistance = max(1_000_000, min(1_000_000_000, value))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowFullGlobe"))) { note in
            let dist = (note.userInfo?["distance"] as? Double) ?? 200_000_000.0
            withAnimation(.easeInOut(duration: 1.2)) {
                camera = .camera(
                    MapCamera(
                        centerCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                        distance: dist,
                        heading: 0,
                        pitch: 0
                    )
                )
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
                    .foregroundStyle(Color.white.opacity(0.08))
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
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
            : .hybrid(elevation: .flat)
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
                withAnimation(.easeInOut(duration: 2.0 / max(0.1, tourSpeedMultiplier))) {
                    let currentCenter = camera.camera?.centerCoordinate ?? dom.coordinate
                    camera = .camera(
                        MapCamera(
                            centerCoordinate: currentCenter,
                            distance: max(tourZoomOutDistance, 12_000),
                            heading: (max(tourZoomOutDistance, 12_000) >= 10_000_000 ? 0 : (camera.camera?.heading ?? 0)),
                            pitch: (max(tourZoomOutDistance, 12_000) >= 20_000_000 ? 0 : fixedPitch)
                        )
                    )
                }
                // Let the map settle
                try? await Task.sleep(nanoseconds: UInt64(1_200_000_000.0 / max(0.1, tourSpeedMultiplier)))

                // Fly to target city at zoomed-out distance
                withAnimation(.easeInOut(duration: 3.0 / max(0.1, tourSpeedMultiplier))) {
                    camera = .camera(
                        MapCamera(
                            centerCoordinate: dom.coordinate,
                            distance: max(tourZoomOutDistance, 12_000),
                            heading: (max(tourZoomOutDistance, 12_000) >= 10_000_000 ? 0 : (camera.camera?.heading ?? 0)),
                            pitch: (max(tourZoomOutDistance, 12_000) >= 20_000_000 ? 0 : fixedPitch)
                        )
                    )
                }
                // Allow tiles to begin loading
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000.0 / max(0.1, tourSpeedMultiplier)))

                // Zoom back in slowly to fixed distance at target
                withAnimation(.easeInOut(duration: 2.0 / max(0.1, tourSpeedMultiplier))) {
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
                try? await Task.sleep(nanoseconds: UInt64(15_000_000_000.0 / max(0.1, tourSpeedMultiplier)))

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

private struct FavoritesListView: View {
    let onSelect: (CLLocationCoordinate2D) -> Void
    var currentCenter: CLLocationCoordinate2D?
    var userLocation: CLLocationCoordinate2D?

    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var favorites: [(id: String, name: String, coordinate: CLLocationCoordinate2D, rank: Int?)] = []
    @State private var addingName: String = ""
    @State private var addError: String? = nil

    private var userFavoritesCollection: CollectionReference? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return Firestore.firestore().collection("users").document(uid).collection("favorites")
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading favorites…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Retry") { fetchFavorites() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("Add Favorite") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Name (e.g. Home, Office)", text: $addingName)
                                    .textFieldStyle(.roundedBorder)
                                if let addError { Text(addError).font(.footnote).foregroundStyle(.red) }
                                HStack {
                                    Button {
                                        if let coord = userLocation { addFavorite(name: addingNameOrFallback("My Location"), coordinate: coord) }
                                    } label: {
                                        Label("Add Current Location", systemImage: "location.fill")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(userLocation == nil)
                                    Button {
                                        if let coord = currentCenter { addFavorite(name: addingNameOrFallback("Map Center"), coordinate: coord) }
                                    } label: {
                                        Label("Add Current View Center", systemImage: "viewfinder")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(currentCenter == nil)
                                }
                            }
                        }

                        Section("Your Favorites") {
                            if favorites.isEmpty {
                                Text("No favorites yet. Use the buttons above to add one.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(favorites, id: \.id) { fav in
                                    Button(action: { onSelect(fav.coordinate) }) {
                                        HStack {
                                            Image(systemName: "mappin.and.ellipse")
                                            VStack(alignment: .leading) {
                                                Text(fav.name)
                                                if let rank = fav.rank { Text("Rank: \(rank)").font(.caption).foregroundStyle(.secondary) }
                                            }
                                        }
                                    }
                                }
                                .onDelete(perform: deleteFavorites)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Favorites")
            .task { fetchFavorites() }
            .refreshable { fetchFavorites() }
        }
    }

    private func fetchFavorites() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            self.isLoading = false
            self.errorMessage = "Favorites are disabled in previews."
            self.favorites = []
            return
        }
        #endif

        guard let col = userFavoritesCollection else {
            self.errorMessage = "You must be signed in to view favorites."
            self.isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        col.order(by: "rank", descending: false).limit(to: 10).getDocuments { snap, err in
            if let err = err {
                // Fall back to ordering by name if rank missing
                (col.order(by: "name").limit(to: 10)).getDocuments { snap2, err2 in
                    self.handleSnapshot(snap2, err: err2)
                }
            } else {
                self.handleSnapshot(snap, err: nil)
            }
        }
    }

    private func handleSnapshot(_ snap: QuerySnapshot?, err: Error?) {
        if let err = err {
            self.errorMessage = "Failed to load favorites: \(err.localizedDescription)"
            self.favorites = []
            self.isLoading = false
            return
        }
        let items: [(String, String, CLLocationCoordinate2D, Int?)] = snap?.documents.compactMap { doc in
            let d = doc.data()
            guard let name = d["name"] as? String,
                  let lat = d["latitude"] as? CLLocationDegrees,
                  let lon = d["longitude"] as? CLLocationDegrees else { return nil }
            let rank = d["rank"] as? Int
            return (doc.documentID, name, CLLocationCoordinate2D(latitude: lat, longitude: lon), rank)
        } ?? []
        self.favorites = items.map { (id, name, coord, rank) in (id: id, name: name, coordinate: coord, rank: rank) }
        self.isLoading = false
    }

    private func addingNameOrFallback(_ fallback: String) -> String {
        let trimmed = addingName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        guard let col = userFavoritesCollection else { return }
        addError = nil
        let data: [String: Any] = [
            "name": name,
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "createdAt": FieldValue.serverTimestamp()
        ]
        col.addDocument(data: data) { err in
            if let err = err {
                self.addError = "Failed to add favorite: \(err.localizedDescription)"
            } else {
                self.addingName = ""
                fetchFavorites()
            }
        }
    }

    private func deleteFavorites(at offsets: IndexSet) {
        guard let col = userFavoritesCollection else { return }
        let idsToDelete = offsets.map { favorites[$0].id }
        for id in idsToDelete {
            col.document(id).delete { _ in }
        }
        favorites.remove(atOffsets: offsets)
    }
}

private struct SearchView: View {
    @Binding var query: String
    @Binding var results: [MKMapItem]
    let onSelect: (MKMapItem) -> Void

    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("Search for a place or address", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                    if isSearching { ProgressView().padding(.leading, 4) }
                    Button("Go") { performSearch() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                List(results, id: \.self) { item in
                    Button(action: { onSelect(item) }) {
                        VStack(alignment: .leading) {
                            Text(item.name ?? "Result")
                                .font(.headline)
                            Text(item.placemark.title ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Search")
        }
    }

    private func performSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            self.results = response?.mapItems ?? []
            self.isSearching = false
        }
    }
}

#if DEBUG
private struct MapViewPreviewHost: View {
    @State private var previewMode: Int = 1
    @State private var previewSpeed: Double = 1.0
    @State private var previewZoomOut: Double = 25_000_000

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if previewMode == 0 {
                    MapView()
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
            }

            GeometryReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Preview Mode", selection: $previewMode) {
                            Text("MapKit").tag(0)
                            Text("SceneKit").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        if previewMode == 1 {
                            SpaceGlobeView()
                                .frame(height: 300)
                                .cornerRadius(12)
                                .padding(.horizontal)
                        }

                        Text("Tour Controls").font(.headline).padding(.horizontal)
                        HStack(spacing: 10) {
                            Button("Start Tour") {
                                NotificationCenter.default.post(name: .startDominanceTour, object: nil)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Stop Tour") {
                                NotificationCenter.default.post(name: .stopDominanceTour, object: nil)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Speed Multiplier")
                            Slider(value: $previewSpeed, in: 0.1...3.0)
                                .onChange(of: previewSpeed) { newVal in
                                    NotificationCenter.default.post(name: .setTourSpeedMultiplier, object: nil, userInfo: ["multiplier": newVal])
                                    NotificationCenter.default.post(name: .startDominanceTour, object: nil)
                                }
                            Text(String(format: "%.2fx", previewSpeed)).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Zoom-out Distance")
                            Slider(value: $previewZoomOut, in: 1_000_000...1_000_000_000)
                                .onChange(of: previewZoomOut) { newVal in
                                    NotificationCenter.default.post(name: .setTourZoomOutDistance, object: nil, userInfo: ["zoomOutDistance": newVal])
                                    NotificationCenter.default.post(name: .startDominanceTour, object: nil)
                                }
                            Text("\(Int(previewZoomOut / 1000)) km").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        // Simulate zoom from globe (space) into MapKit
                        HStack(spacing: 10) {
                            Button("Show Globe First") { previewMode = 1 }
                                .buttonStyle(.bordered)
                            Button("Zoom In to MapKit") { withAnimation { previewMode = 0 } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal)

                        /*
                        Button("Show Globe") {
                            NotificationCenter.default.post(name: Notification.Name("ShowFullGlobe"), object: nil, userInfo: ["distance": 200_000_000.0])
                        }
                        .buttonStyle(.borderedProminent)
                        */

                        Button("Show Max Globe") {
                            NotificationCenter.default.post(name: Notification.Name("ShowFullGlobe"), object: nil, userInfo: ["distance": 1_000_000_000.0])
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        
                        Button("Show Space View") {
                            NotificationCenter.default.post(name: Notification.Name("ShowFullGlobe"), object: nil, userInfo: ["distance": 3_000_000_000.0])
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)

                        Button("Fit Globe") {
                            let size = proxy.size
                            let fitDistance = max(size.width, size.height) * 12000.0
                            NotificationCenter.default.post(name: Notification.Name("ShowFullGlobe"), object: nil, userInfo: ["distance": fitDistance])
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)

                        Text("Note: Buttons post notifications used by MapView to drive the tour.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

private struct SpaceGlobeView: UIViewRepresentable {
    // Simple heuristic: daytime between 6am and 6pm local time
    private var isDaytime: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return (6...17).contains(hour)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()

        // Scene setup
        let scene = SCNScene()

        // Earth sphere
        let sphere = SCNSphere(radius: 1.0)
        sphere.segmentCount = 128

        // Materials: use images named "earth_day" and "earth_night" from assets
        let material = SCNMaterial()
        material.diffuse.contents = UIImage(named: isDaytime ? "earth_day" : "earth_night") ?? UIColor.systemGray
        material.locksAmbientWithDiffuse = true
        material.isDoubleSided = false
        sphere.firstMaterial = material

        let sphereNode = SCNNode(geometry: sphere)
        scene.rootNode.addChildNode(sphereNode)

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 3)
        scene.rootNode.addChildNode(cameraNode)

        // Ambient light
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 500
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        // Directional light to give some shading
        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.intensity = 800
        let directionalNode = SCNNode()
        directionalNode.light = directionalLight
        directionalNode.eulerAngles = SCNVector3(-CGFloat.pi/4, CGFloat.pi/4, 0)
        scene.rootNode.addChildNode(directionalNode)

        // Slow constant rotation on Y axis
        let duration: TimeInterval = 60 // one full rotation per minute
        let rotateAction = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: duration))
        sphereNode.runAction(rotateAction)

        scnView.scene = scene
        scnView.backgroundColor = UIColor.black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update the texture if day/night boundary has changed while preview is live
        let desiredImageName = isDaytime ? "earth_day" : "earth_night"
        if let sphere = (uiView.scene?.rootNode.childNodes.first { $0.geometry is SCNSphere })?.geometry as? SCNSphere,
           let mat = sphere.firstMaterial {
            if let currentImage = mat.diffuse.contents as? UIImage,
               let desiredImage = UIImage(named: desiredImageName),
               currentImage !== desiredImage {
                mat.diffuse.contents = desiredImage
            } else if mat.diffuse.contents is UIColor, let desiredImage = UIImage(named: desiredImageName) {
                mat.diffuse.contents = desiredImage
            }
        }
    }
}
#endif

#Preview("Map Tour Preview") {
    MapViewPreviewHost()
}
