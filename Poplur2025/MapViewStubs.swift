import SwiftUI
import MapKit
import CoreLocation
import Foundation

let fixedDistance: CLLocationDistance = 12_000
let fixedPitch: CGFloat = 0

struct MapAnnotationPost: Identifiable {
    let id = UUID()
    let title: String
    let coordinate: CLLocationCoordinate2D
    let radius: CLLocationDistance
}

struct CityDominance: Identifiable {
    let id = UUID()
    let city: String
    let coordinate: CLLocationCoordinate2D
    let profileURL: URL?
}

func demoDominanceCities() -> [CityDominance] {
    return [
        CityDominance(city: "San Francisco", coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), profileURL: nil),
        CityDominance(city: "New York", coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), profileURL: nil)
    ]
}

struct GoogleStylePin: View {
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }
}

struct DominancePin: View {
    var profileURL: URL?
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.blue)
            .frame(width: 14, height: 14)
    }
}

struct RecommendationOverlay: View {
    @Binding var message: String?
    var body: some View {
        VStack {
            if let message {
                Text(message)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
        }
        .padding()
    }
}

struct FavoritesListView: View {
    var onSelect: (CLLocationCoordinate2D) -> Void
    var currentCenter: CLLocationCoordinate2D?
    var userLocation: CLLocationCoordinate2D?
    var body: some View {
        List {
            if let userLocation {
                Button("User Location") { onSelect(userLocation) }
            }
            if let currentCenter {
                Button("Map Center") { onSelect(currentCenter) }
            }
            Button("San Francisco") {
                onSelect(CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
            }
            Button("New York") {
                onSelect(CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060))
            }
        }
    }
}

struct SearchView: View {
    @Binding var query: String
    @Binding var results: [MKMapItem]
    var onSelect: (MKMapItem) -> Void

    var body: some View {
        VStack {
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding()
            List(results, id: \.self) { item in
                Button(item.name ?? "Result") {
                    onSelect(item)
                }
            }
            Spacer()
        }
        .onChange(of: query) { _, newValue in
            Task {
                await SearchView.performSearch(text: newValue, results: $results)
            }
        }
    }

    static func performSearch(text: String, results: Binding<[MKMapItem]>) async {
        guard !text.isEmpty else {
            await MainActor.run { results.wrappedValue = [] }
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        let search = MKLocalSearch(request: request)
        let response = try? await search.start()
        await MainActor.run {
            results.wrappedValue = response?.mapItems ?? []
        }
    }
}

// MARK: - Notification names used for routing and preloading
extension Notification.Name {
    // LoadFeedNow, LoadMapNow, LoadProfileNow, ShowUserProfile, CenterMapOnUser moved to Notifications+Names.swift
    static let startDominanceTour = Notification.Name("startDominanceTour")
    static let stopDominanceTour = Notification.Name("stopDominanceTour")
    static let setTourSpeedMultiplier = Notification.Name("setTourSpeedMultiplier")
    static let setTourZoomOutDistance = Notification.Name("setTourZoomOutDistance")
    static let setBuildingZoomDistance = Notification.Name("setBuildingZoomDistance")
    static let PreviewRetryRender = Notification.Name("PreviewRetryRender")
}

// MARK: - MapView implementation
struct MapView: View {
    var coordinate: CLLocationCoordinate2D
    
    @StateObject private var locationManager = LocationManager()
    @State private var camera: MapCameraPosition
    @State private var posts: [MapAnnotationPost] = []
    @State private var selectedIndex: Int?
    @State private var radiusMeters: Double = 5_000
    @State private var dominance: [CityDominance] = demoDominanceCities()
    @State private var tourTask: Task<Void, Never>? = nil
    @State private var tourActive: Bool = false
    @State private var tourIndex: Int = 0
    @State private var tourSpeedMultiplier: Double = 1.0
    @State private var tourZoomOutDistance: CLLocationDistance = 25_000_000
    @State private var showFavorites: Bool = false
    @State private var showSearch: Bool = false
    @State private var searchQuery: String = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var idleTask: Task<Void, Never>? = nil
    @State private var lastInteractionAt: Date = Date()
    
    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        _camera = State(initialValue: .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: fixedDistance,
                heading: 52,
                pitch: fixedPitch
            )
        ))
    }
    
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
    
    private func filteredPosts() -> [MapAnnotationPost] {
        guard let userLoc = locationManager.location else { return posts }
        return posts.filter {
            MKMapPoint(userLoc.coordinate).distance(to: MKMapPoint($0.coordinate)) <= radiusMeters
        }
    }
    
    private func noteInteraction() {
        lastInteractionAt = Date()
        stopDominanceTour()
        scheduleIdleCheck()
    }
    
    private func scheduleIdleCheck() {
        idleTask?.cancel()
        idleTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let elapsed = Date().timeIntervalSince(lastInteractionAt)
                if elapsed >= 15.0 {
                    startDominanceTour()
                    break
                }
            }
        }
    }
    
    private func startDominanceTour() {
        tourTask?.cancel()
        tourActive = true
        tourTask = Task { @MainActor in
            while !Task.isCancelled, tourActive, !dominance.isEmpty {
                let dom = dominance[tourIndex % dominance.count]
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
                try? await Task.sleep(nanoseconds: UInt64(1_200_000_000.0 / max(0.1, tourSpeedMultiplier)))
                
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
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000.0 / max(0.1, tourSpeedMultiplier)))
                
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
    
    @MapContentBuilder
    private var mapContent: some MapContent {
        if locationManager.location != nil {
            UserAnnotation {
                Label("You", systemImage: "location.fill")
            }
        }
        
        ForEach(filteredPosts()) { post in
            Annotation(post.title, coordinate: post.coordinate) {
                GoogleStylePin()
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
    
    var body: some View {
        ZStack {
            Map(
                position: Binding(
                    get: { camera },
                    set: { camera = lockCamera($0) }
                ),
                interactionModes: [.pan, .rotate]
            ) {
                mapContent
            }
            .mapStyle(.hybrid(elevation: .realistic, showsTraffic: false))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in noteInteraction() })
            .simultaneousGesture(TapGesture().onEnded { noteInteraction() })
            
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
            .sheet(isPresented: $showFavorites) {
                FavoritesListView(
                    onSelect: { coord in panTo(coord) },
                    currentCenter: camera.camera?.centerCoordinate,
                    userLocation: locationManager.location?.coordinate
                )
                .presentationDetents([.medium, .large])
            }
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
            locationManager.requestAuthorizationIfNeeded()
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
            scheduleIdleCheck()
        }
        .onDisappear {
            stopDominanceTour()
            idleTask?.cancel()
            idleTask = nil
        }
        .onChange(of: locationManager.location) { _, _ in
            if locationManager.location != nil {
                locationManager.centerOnUser(&camera)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .CenterMapOnUser)) { _ in
            stopDominanceTour()
            guard let userCoord = locationManager.location?.coordinate else {
                locationManager.centerOnUser(&camera)
                noteInteraction()
                return
            }
            
            // Break down complex expressions
            let currentCenter = camera.camera?.centerCoordinate ?? userCoord
            let zoomDistance = max(tourZoomOutDistance, 12_000)
            let shouldResetPitch = zoomDistance >= 20_000_000
            let initialPitch: CGFloat = shouldResetPitch ? 0 : fixedPitch
            
            withAnimation(.easeInOut(duration: 2.0 * tourSpeedMultiplier)) {
                camera = .camera(
                    MapCamera(
                        centerCoordinate: currentCenter,
                        distance: zoomDistance,
                        heading: 0,
                        pitch: initialPitch
                    )
                )
            }
            
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(1_200_000_000.0 * tourSpeedMultiplier))
                
                let zoomDist = max(tourZoomOutDistance, 12_000)
                let resetPitch = zoomDist >= 20_000_000
                let pitch: CGFloat = resetPitch ? 0 : fixedPitch
                
                withAnimation(.easeInOut(duration: 3.0 * tourSpeedMultiplier)) {
                    camera = .camera(
                        MapCamera(
                            centerCoordinate: userCoord,
                            distance: zoomDist,
                            heading: 0,
                            pitch: pitch
                        )
                    )
                }
                
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000.0 * tourSpeedMultiplier))
                
                let currentHeading = camera.camera?.heading ?? 0
                
                withAnimation(.easeInOut(duration: 2.0 * tourSpeedMultiplier)) {
                    camera = .camera(
                        MapCamera(
                            centerCoordinate: userCoord,
                            distance: fixedDistance,
                            heading: currentHeading,
                            pitch: fixedPitch
                        )
                    )
                }
                
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
        .task {
            await NotificationCenter.default.publisher(for: .LoadMapNow)
                .first()
                .values
                .first { _ in true }
        }
    }
}

// Minimal MapView stub to allow extensions to compile
#if USE_MAPVIEW_STUB
// If you need a stub MapView for previews or to unblock compilation, enable the
// `USE_MAPVIEW_STUB` Swift flag in your target's build settings.
// This avoids conflicting with a real MapView defined elsewhere.

struct MapViewStub: View {
    @State var posts: [MapAnnotationPost] = []
    @State var camera: MapKit.MapCameraPosition = .automatic
    @State var lastInteractionAt: Date? = nil
    @State var tourActive: Bool = false
    @State var tourTask: Task<Void, Never>? = nil
    @State var idleTask: Task<Void, Never>? = nil

    var body: some View {
        Text("MapView placeholder")
    }
}
// Provide a typealias so call sites using `MapView` continue to compile when the stub is enabled.
@available(*, deprecated, message: "Stub typealias active only when USE_MAPVIEW_STUB is defined")
typealias MapView = MapViewStub
#endif

// Note: We use MapKit's built-in MapCamera and MapCameraPosition types
// No custom definitions needed - MapKit provides these

#if USE_MAPVIEW_STUB
fileprivate extension MapViewStub {
    func lockCamera(_ position: MapKit.MapCameraPosition) -> MapKit.MapCameraPosition {
        // Lock zoom by clamping distance if a camera exists
        switch position {
        case .camera(let cam):
            let clamped = MapKit.MapCamera(
                centerCoordinate: cam.centerCoordinate,
                distance: fixedDistance,
                heading: cam.heading,
                pitch: cam.pitch
            )
            return .camera(clamped)
        default:
            return position
        }
    }
}
#endif

#if USE_MAPVIEW_STUB
fileprivate extension MapViewStub {
    func filteredPosts() -> [MapAnnotationPost] {
        posts
    }
}
#endif

#if USE_MAPVIEW_STUB
fileprivate extension MapViewStub {
    func fetchPosts() {
        // minimal demo posts
        posts = [
            MapAnnotationPost(title: "Post A", coordinate: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437), radius: 500),
            MapAnnotationPost(title: "Post B", coordinate: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278), radius: 500)
        ]
    }
}
#endif

#if USE_MAPVIEW_STUB
fileprivate extension MapViewStub {
    func panTo(_ coord: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 1.0)) {
            camera = .camera(MapKit.MapCamera(centerCoordinate: coord, distance: fixedDistance, heading: 0, pitch: fixedPitch))
        }
    }
}
#endif

#if USE_MAPVIEW_STUB
fileprivate extension MapViewStub {
    func noteInteraction() {
        lastInteractionAt = Date()
    }
}
#endif

#if USE_MAPVIEW_STUB
fileprivate extension MapViewStub {
    func startDominanceTour() {
        tourActive = true
    }
}
#endif

#if USE_MAPVIEW_STUB
fileprivate extension MapViewStub {
    func stopDominanceTour() {
        tourActive = false
        tourTask?.cancel()
        tourTask = nil
    }
}
#endif

#if USE_MAPVIEW_STUB
fileprivate extension MapViewStub {
    func scheduleIdleCheck() {
        idleTask?.cancel()
        idleTask = Task {
            @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                // no-op for now
            }
        }
    }
}
#endif

enum MockAIRecommender {
    static func recommendation(for coord: CLLocationCoordinate2D) -> String {
        "Explore nearby places at (\(String(format: "%.3f", coord.latitude)), \(String(format: "%.3f", coord.longitude)))"
    }
}

#if USE_MAPVIEW_STUB
#Preview {
    MapViewStub()
}
#endif
