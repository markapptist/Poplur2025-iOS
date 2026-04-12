import SwiftUI
import MapKit
import CoreLocation
import FirebaseFirestore
import FirebaseAuth
import FirebaseCore
import SceneKit

private let fixedPitchAlt: CGFloat = 60 // Changed to 60 degrees for 3D perspective

struct MapView_PreviewAlt: View {
    @StateObject private var locationManager = LocationManager()

    @State private var fixedDistanceAlt: CLLocationDistance = 3_000 // Closer for preview to see buildings
    @State private var camera: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 40.748339, longitude: -73.985912),
            distance: 3_000,
            heading: 52,
            pitch: 60
        )
    )

    @State private var posts: [MapAnnotationPost] = []
    @State private var selectedIndex: Int?
    @State private var radiusMeters: Double = 5_000

    @State private var dominance: [CityDominance] = []
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
    
    init() {
        // Initialize with demo cities synchronously to avoid preview crash
        _dominance = State(initialValue: [
            CityDominance(city: "San Francisco", coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), profileURL: nil),
            CityDominance(city: "New York", coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), profileURL: nil)
        ])
    }

    var aiMessage: String {
        """
        This is an alternate preview of MapView with suffixed constants and alternative view components to avoid conflicts.
        """
    }

    @ViewBuilder
    func mapContent() -> some View {
        VStack {
            Text(aiMessage).padding()
            Spacer()
        }
    }

    var mapLayer: AnyView {
        // Use full interaction modes in previews too
        let modes: MapInteractionModes = [.pan, .rotate, .pitch, .zoom]

        return AnyView(
            Map(
                position: Binding(
                    get: { camera },
                    set: { camera = lockCamera($0) }
                ),
                interactionModes: modes
            ) {
                // Only show user annotation when not in preview and location available
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
                    Annotation(post.title, coordinate: post.coordinate) {
                        GoogleStylePinAlt()
                    }

                    MapCircle(center: post.coordinate, radius: post.radius)
                        .foregroundStyle(Color.white.opacity(0.08))
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                }

                ForEach(dominance) { dom in
                    Annotation(dom.city, coordinate: dom.coordinate) {
                        if let url = dom.profileURL {
                            DominancePin(profileURL: url)
                        }
                    }
                }
            }
            .mapStyle(.hybrid(elevation: .realistic, showsTraffic: false))
        )
    }

    private func lockCamera(_ pos: MapCameraPosition) -> MapCameraPosition {
        // Don't lock camera in preview mode - allow full 3D exploration
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return pos
        }
        #endif
        
        return pos.camera.map {
            .camera(
                MapCamera(
                    centerCoordinate: $0.centerCoordinate,
                    distance: fixedDistanceAlt,
                    heading: $0.heading,
                    pitch: fixedPitchAlt
                )
            )
        } ?? pos
    }

    private func panTo(_ coordinate: CLLocationCoordinate2D) {
        let heading = camera.camera?.heading ?? 0
        withAnimation(.easeInOut(duration: 0.8)) {
            camera = .camera(
                MapCamera(
                    centerCoordinate: coordinate,
                    distance: fixedDistanceAlt,
                    heading: heading,
                    pitch: fixedPitchAlt
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

    private func filteredPosts() -> [MapAnnotationPost] {
        guard let userLoc = locationManager.location else { return posts }
        return posts.filter {
            MKMapPoint(userLoc.coordinate).distance(to: MKMapPoint($0.coordinate)) <= radiusMeters
        }
    }

    private func fetchPosts() {
        // Skip Firebase network calls when running SwiftUI previews
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            posts = [
                MapAnnotationPost(
                    title: "Preview A",
                    coordinate: CLLocationCoordinate2D(latitude: 40.748339, longitude: -73.985912),
                    radius: 5000
                ),
                MapAnnotationPost(
                    title: "Preview B",
                    coordinate: CLLocationCoordinate2D(latitude: 40.758896, longitude: -73.985130),
                    radius: 3000
                )
            ]
            return
        }
        #endif

        Firestore.firestore().collection("posts").getDocuments { snap, _ in
            let mapped: [MapAnnotationPost] = snap?.documents.compactMap { doc -> MapAnnotationPost? in
                let d = doc.data()
                guard let lat = d["latitude"] as? CLLocationDegrees,
                      let lon = d["longitude"] as? CLLocationDegrees else { return nil }
                return MapAnnotationPost(
                    title: d["title"] as? String ?? "Post",
                    coordinate: .init(latitude: lat, longitude: lon),
                    radius: (d["radius"] as? Double) ?? 5_000
                )
            } ?? []
            posts = mapped
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
                            pitch: (max(tourZoomOutDistance, 12_000) >= 20_000_000 ? 0 : fixedPitchAlt)
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
                            pitch: (max(tourZoomOutDistance, 12_000) >= 20_000_000 ? 0 : fixedPitchAlt)
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
                            distance: fixedDistanceAlt,
                            heading: camera.camera?.heading ?? 0,
                            pitch: fixedPitchAlt
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
                FavoritesListViewAlt(
                    onSelect: { coord in panTo(coord) },
                    currentCenter: camera.camera?.centerCoordinate,
                    userLocation: locationManager.location?.coordinate
                )
                .presentationDetents([.medium, .large])
            }
            // Search sheet
            .sheet(isPresented: $showSearch) {
                SearchViewAlt(query: $searchQuery, results: $searchResults) { item in
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
            locationManager.requestAuthorizationIfNeeded()
            // Normalize camera to fixed pitch/distance so tiles render immediately
            if let current = camera.camera {
                camera = .camera(
                    MapCamera(
                        centerCoordinate: current.centerCoordinate,
                        distance: fixedDistanceAlt,
                        heading: current.heading,
                        pitch: fixedPitchAlt
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
            // Center only once when we get the first location fix
            if let _ = locationManager.location {
                locationManager.centerOnUser(&camera)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .CenterMapOnUser)) { _ in
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
                        pitch: (max(tourZoomOutDistance, 12_000) >= 20_000_000 ? 0 : fixedPitchAlt)
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
                            pitch: (max(tourZoomOutDistance, 12_000) >= 20_000_000 ? 0 : fixedPitchAlt)
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
                            distance: fixedDistanceAlt,
                            heading: camera.camera?.heading ?? 0,
                            pitch: fixedPitchAlt
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
        .onReceive(NotificationCenter.default.publisher(for: .setBuildingZoomDistance)) { note in
            if let value = note.userInfo?["distance"] as? Double {
                fixedDistanceAlt = max(500, min(10_000, value))
                // If we're currently at a close zoom level, update the camera to the new distance
                if let currentDistance = camera.camera?.distance, currentDistance < 15_000 {
                    if let coord = camera.camera?.centerCoordinate {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            camera = .camera(
                                MapCamera(
                                    centerCoordinate: coord,
                                    distance: fixedDistanceAlt,
                                    heading: camera.camera?.heading ?? 0,
                                    pitch: fixedPitchAlt
                                )
                            )
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("JumpToPlace"))) { note in
            stopDominanceTour()
            if let coord = note.userInfo?["coordinate"] as? CLLocationCoordinate2D {
                // Zoom out first
                withAnimation(.easeInOut(duration: 1.5)) {
                    let currentCenter = camera.camera?.centerCoordinate ?? coord
                    camera = .camera(
                        MapCamera(
                            centerCoordinate: currentCenter,
                            distance: 5_000_000,
                            heading: 0,
                            pitch: fixedPitchAlt
                        )
                    )
                }
                
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    
                    // Fly to destination
                    withAnimation(.easeInOut(duration: 2.0)) {
                        camera = .camera(
                            MapCamera(
                                centerCoordinate: coord,
                                distance: 5_000_000,
                                heading: 0,
                                pitch: fixedPitchAlt
                            )
                        )
                    }
                    
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    
                    // Zoom in
                    withAnimation(.easeInOut(duration: 1.5)) {
                        camera = .camera(
                            MapCamera(
                                centerCoordinate: coord,
                                distance: fixedDistanceAlt,
                                heading: camera.camera?.heading ?? 0,
                                pitch: fixedPitchAlt
                            )
                        )
                    }
                    
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    noteInteraction()
                }
            }
        }
    }
}

private struct FavoritesListViewAlt: View {
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

private struct SearchViewAlt: View {
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

private struct DominancePinAlt: View {
    let profileURL: URL
    var body: some View {
        DominancePin(profileURL: profileURL)
    }
}

private struct GoogleStylePinAlt: View {
    var body: some View {
        GoogleStylePin()
    }
}

// MARK: - Interactive Tour Preview with Controls

private struct MapTourPreviewWithControls: View {
    @State private var tourSpeed: Double = 1.0 // Matches tourSpeedMultiplier default
    @State private var zoomOutDistance: Double = 25_000_000 // Matches tourZoomOutDistance default
    @State private var buildingZoomDistance: Double = 3_000 // Matches fixedDistanceAlt default
    @State private var currentCity: String = "New York"
    @State private var aiRecommendation: String = "Explore the vibrant streets of Manhattan and discover world-class dining."
    @State private var recommendationTask: Task<Void, Never>?
    @State private var isLoading: Bool = true
    @State private var showPlacesList: Bool = false
    @State private var showAddressSearch: Bool = false
    @State private var searchQuery: String = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching: Bool = false
    
    let tourPlaces: [(name: String, coordinate: CLLocationCoordinate2D, description: String)] = [
        ("New York", CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), "The city that never sleeps"),
        ("San Francisco", CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), "The Golden Gate City"),
        ("Los Angeles", CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437), "City of Angels"),
        ("Chicago", CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298), "The Windy City"),
        ("Miami", CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918), "Magic City"),
        ("Seattle", CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321), "Emerald City"),
        ("Boston", CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589), "Beantown"),
        ("Austin", CLLocationCoordinate2D(latitude: 30.2672, longitude: -97.7431), "Live Music Capital")
    ]
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading Map Preview...")
                    .onAppear {
                        // Small delay to ensure everything initializes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isLoading = false
                        }
                    }
            } else {
                MapView_PreviewAlt()
            }
            
            // Top navigation buttons
            VStack {
                HStack {
                    // Hamburger menu button
                    Button(action: { showPlacesList.toggle() }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    
                    Spacer()
                    
                    // Address search button
                    Button(action: { showAddressSearch.toggle() }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding([.top, .horizontal])
                
                Spacer()
            }
            
            // AI Recommendation Overlay
            VStack {
                Spacer().frame(height: 60) // Space for top buttons
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentCity)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(aiRecommendation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal)
                
                Spacer()
                
                // Tour Controls
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tour Speed")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(String(format: "%.1f", tourSpeed))x")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                        Slider(value: $tourSpeed, in: 0.1...5.0, step: 0.1)
                            .onChange(of: tourSpeed) { _, newValue in
                                NotificationCenter.default.post(
                                    name: .setTourSpeedMultiplier,
                                    object: nil,
                                    userInfo: ["multiplier": newValue]
                                )
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Zoom Out Distance")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(zoomOutDistance / 1_000_000))M km")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                        Slider(value: $zoomOutDistance, in: 1_000_000...200_000_000, step: 1_000_000)
                            .onChange(of: zoomOutDistance) { _, newValue in
                                NotificationCenter.default.post(
                                    name: .setTourZoomOutDistance,
                                    object: nil,
                                    userInfo: ["zoomOutDistance": newValue]
                                )
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Building Zoom")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(buildingZoomDistance)) m")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                        Slider(value: $buildingZoomDistance, in: 500...10_000, step: 100)
                            .onChange(of: buildingZoomDistance) { _, newValue in
                                NotificationCenter.default.post(
                                    name: .setBuildingZoomDistance,
                                    object: nil,
                                    userInfo: ["distance": newValue]
                                )
                            }
                    }
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            NotificationCenter.default.post(name: .stopDominanceTour, object: nil)
                        }) {
                            Label("Stop", systemImage: "stop.fill")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            NotificationCenter.default.post(name: .startDominanceTour, object: nil)
                        }) {
                            Label("Start", systemImage: "play.fill")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding()
            }
        }
        .sheet(isPresented: $showPlacesList) {
            PlacesListView(places: tourPlaces) { place in
                showPlacesList = false
                NotificationCenter.default.post(name: .stopDominanceTour, object: nil)
                NotificationCenter.default.post(
                    name: Notification.Name("JumpToPlace"),
                    object: nil,
                    userInfo: ["coordinate": place.coordinate]
                )
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAddressSearch) {
            AddressSearchView(
                query: $searchQuery,
                results: $searchResults,
                isSearching: $isSearching
            ) { item in
                showAddressSearch = false
                if let coord = item.placemark.location?.coordinate {
                    NotificationCenter.default.post(name: .stopDominanceTour, object: nil)
                    NotificationCenter.default.post(
                        name: Notification.Name("JumpToPlace"),
                        object: nil,
                        userInfo: ["coordinate": coord]
                    )
                }
            }
            .presentationDetents([.medium, .large])
        }
        .task {
            // Start tour after brief delay
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            NotificationCenter.default.post(name: .startDominanceTour, object: nil)
            
            // Cycle AI recommendations
            let cities = [
                ("San Francisco", "Discover the Golden Gate Bridge and innovative tech culture of the Bay Area."),
                ("New York", "Explore the vibrant streets of Manhattan and discover world-class dining."),
                ("San Francisco", "Visit Alcatraz Island and enjoy fresh seafood at Fisherman's Wharf."),
                ("New York", "Experience Broadway shows and explore the iconic Central Park.")
            ]
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if let randomCity = cities.randomElement() {
                    await MainActor.run {
                        currentCity = randomCity.0
                        aiRecommendation = randomCity.1
                    }
                }
            }
        }
    }
}

// MARK: - Places List View

private struct PlacesListView: View {
    let places: [(name: String, coordinate: CLLocationCoordinate2D, description: String)]
    let onSelect: ((name: String, coordinate: CLLocationCoordinate2D, description: String)) -> Void
    
    var body: some View {
        NavigationStack {
            List(places.indices, id: \.self) { index in
                Button(action: {
                    onSelect(places[index])
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(places[index].name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(places[index].description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Tour Places")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Address Search View

private struct AddressSearchView: View {
    @Binding var query: String
    @Binding var results: [MKMapItem]
    @Binding var isSearching: Bool
    let onSelect: (MKMapItem) -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("Search for a place or address", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            performSearch()
                        }
                    
                    if isSearching {
                        ProgressView()
                            .padding(.leading, 4)
                    }
                    
                    Button("Search") {
                        performSearch()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
                
                if results.isEmpty && !query.isEmpty && !isSearching {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No results found")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "map")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Search for any address or place")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results, id: \.self) { item in
                        Button(action: {
                            onSelect(item)
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name ?? "Unknown")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if let title = item.placemark.title {
                                    Text(title)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search Address")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func performSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        results = []
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            self.results = response?.mapItems ?? []
            self.isSearching = false
        }
    }
}

// MARK: - SceneKit Rotating Earth Globe Preview

private struct RotatingEarthGlobePreview: View {
    @State private var rotationAngle: Double = 0
    @State private var showGlobeInfo: Bool = true
    
    var body: some View {
        ZStack {
            // SceneKit Earth view
            SceneKitEarthView(rotationAngle: $rotationAngle)
                .ignoresSafeArea()
            
            // Info overlay
            if showGlobeInfo {
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Earth")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                            Text("Radius: 6,371 km")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Rotation: 1,670 km/h at equator")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(action: { showGlobeInfo.toggle() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding()
                    
                    Spacer()
                }
            }
            
            // Rotation controls
            VStack {
                Spacer()
                HStack(spacing: 16) {
                    Button(action: {
                        // Toggle rotation speed
                        NotificationCenter.default.post(
                            name: Notification.Name("ToggleGlobeRotation"),
                            object: nil
                        )
                    }) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.8))
                            .shadow(radius: 4)
                    }
                    
                    Button(action: {
                        // Reset view
                        withAnimation(.spring(response: 1.0, dampingFraction: 0.7)) {
                            rotationAngle = 0
                        }
                    }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.8))
                            .shadow(radius: 4)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - SceneKit Earth View

private struct SceneKitEarthView: UIViewRepresentable {
    @Binding var rotationAngle: Double
    
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.backgroundColor = .black
        
        // Create scene
        let scene = SCNScene()
        sceneView.scene = scene
        
        // Create Earth sphere
        let earthRadius: CGFloat = 2.0
        let earthGeometry = SCNSphere(radius: earthRadius)
        
        // Apply Earth texture (using a simple material for now)
        let earthMaterial = SCNMaterial()
        earthMaterial.diffuse.contents = UIColor.blue
        earthMaterial.specular.contents = UIColor.white
        earthMaterial.shininess = 0.1
        
        // For a realistic Earth, you would load an Earth texture:
        // earthMaterial.diffuse.contents = UIImage(named: "earth_texture")
        
        earthGeometry.materials = [earthMaterial]
        
        // Create Earth node
        let earthNode = SCNNode(geometry: earthGeometry)
        earthNode.name = "earth"
        scene.rootNode.addChildNode(earthNode)
        
        // Add atmospheric glow
        let glowGeometry = SCNSphere(radius: earthRadius * 1.05)
        let glowMaterial = SCNMaterial()
        glowMaterial.diffuse.contents = UIColor.cyan.withAlphaComponent(0.3)
        glowMaterial.isDoubleSided = true
        glowGeometry.materials = [glowMaterial]
        let glowNode = SCNNode(geometry: glowGeometry)
        earthNode.addChildNode(glowNode)
        
        // Add camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 6)
        scene.rootNode.addChildNode(cameraNode)
        
        // Add rotation animation
        let rotation = CABasicAnimation(keyPath: "rotation")
        rotation.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi * 2))
        rotation.duration = 30 // One full rotation every 30 seconds
        rotation.repeatCount = .infinity
        earthNode.addAnimation(rotation, forKey: "rotation")
        
        return sceneView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update rotation if needed
        if let earthNode = uiView.scene?.rootNode.childNode(withName: "earth", recursively: false) {
            earthNode.eulerAngles.y = Float(rotationAngle)
        }
    }
}

#Preview("Interactive Tour with Controls") {
    MapTourPreviewWithControls()
        .onAppear {
            print("🗺️ Tour preview loaded")
        }
}

#Preview("Rotating Earth Globe") {
    RotatingEarthGlobePreview()
        .onAppear {
            print("🌍 Globe preview loaded")
        }
}

