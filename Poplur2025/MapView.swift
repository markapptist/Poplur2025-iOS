import SwiftUI
import MapKit
import CoreLocation
import SceneKit

/*
 ═══════════════════════════════════════════════════════════════════════════════
 MapView.swift - Production Map Implementation
 ═══════════════════════════════════════════════════════════════════════════════
 
 PRIMARY MAP VIEW (DO NOT REPLACE):
 • MapViewProduction - The ONLY map view used in the production app
   - Hybrid map style with realistic 3D elevation  
   - AI recommendations overlay
   - Navigation controls (places list, address search)
   - Optimized 60° pitch camera at 700m distance
   - Used in HomeView.swift mapTabContent
 
 PREVIEW/DEVELOPMENT VIEWS:
 • MapTourPreviewWithControls - Interactive preview with debug controls
   - Used for testing and tuning map behavior
   - Includes speed/zoom/distance sliders for development
 
 REMOVED VIEWS:
 • MapView_PreviewAlt - Removed (duplicate/unused)
 • MapView (basic) - Replaced by MapViewProduction
 
 ═══════════════════════════════════════════════════════════════════════════════
*/

/*
 POP_PREVIEW_LIGHT compile-time flag enables a lighter preview mode that excludes heavy dependencies
 like FirebaseFirestore and SceneKit. Use it to speed up SwiftUI previews in complex projects.
*/

#if !POP_PREVIEW_LIGHT
#if canImport(FirebaseFirestore)
#if !DEBUG || !IS_PREVIEW
import FirebaseFirestore
#endif
#endif
#endif

#if DEBUG
// Preview-safe fallbacks for missing app types so this file builds in isolation
import Combine

// Minimal stubs used only for previews if not defined elsewhere
#if !canImport(AppKit) && !canImport(UIKit)
// no-op
#endif

// Stub PreviewLocationManager if the real one isn't available to previews
private class PreviewLocationManager: NSObject, ObservableObject {
    @Published var location: CLLocation? = CLLocation(latitude: 40.748339, longitude: -73.985912)
    func requestAuthorizationIfNeeded() {}
    func centerOnUser(_ camera: inout MapCameraPosition) {
        if let coord = location?.coordinate {
            camera = .camera(MapCamera(centerCoordinate: coord, distance: 700, heading: 0, pitch: 60))
        }
    }
}

// Stub models used by annotations
private struct PreviewMapAnnotationPost: Identifiable, Hashable, Equatable {
    let id = UUID()
    var title: String
    var coordinate: CLLocationCoordinate2D
    var radius: CLLocationDistance

    static func == (lhs: PreviewMapAnnotationPost, rhs: PreviewMapAnnotationPost) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct PreviewCityDominance: Identifiable, Hashable, Equatable {
    let id = UUID()
    var city: String
    var coordinate: CLLocationCoordinate2D
    var profileURL: URL?

    static func == (lhs: PreviewCityDominance, rhs: PreviewCityDominance) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// Stub annotation views
private struct PreviewDominancePin: View {
    let profileURL: URL
    var body: some View { Image(systemName: "person.crop.circle").padding(4).background(.ultraThinMaterial, in: Circle()) }
}

private struct PreviewGoogleStylePin: View {
    var body: some View { Image(systemName: "mappin.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.red, .white) }
}

// Notification names used in this file
private extension Notification.Name {
    static let preview_CenterMapOnUser = Notification.Name("Preview_CenterMapOnUser")
    static let preview_startDominanceTour = Notification.Name("Preview_startDominanceTour")
    static let preview_stopDominanceTour = Notification.Name("Preview_stopDominanceTour")
    static let preview_setTourSpeedMultiplier = Notification.Name("Preview_setTourSpeedMultiplier")
    static let preview_setTourZoomOutDistance = Notification.Name("Preview_setTourZoomOutDistance")
    static let preview_setBuildingZoomDistance = Notification.Name("Preview_SetBuildingZoomDistance")
}
#endif

#if DEBUG
private let IS_PREVIEW: Bool = (ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1")
#else
private let IS_PREVIEW: Bool = false
#endif

private let fixedPitchAlt: CGFloat = 60 // Changed to 60 degrees for 3D perspective

#if DEBUG
private extension PreviewLocationManager {
    static func stubForPreviewInstance() -> PreviewLocationManager {
        // Return a plain instance without triggering authorization in previews
        return PreviewLocationManager()
    }
}

#endif

// REMOVED: MapView_PreviewAlt - Not used in production. Use MapViewProduction instead.
// REMOVED: Helper views (FavoritesListViewAlt, SearchViewAlt, etc.) - No longer needed since MapView_PreviewAlt was removed.

// MARK: - Interactive Tour Preview with Controls

private struct MapTourPreviewWithControls: View {
    @State private var tourSpeed: Double = 1.0 // Matches tourSpeedMultiplier default
    @State private var zoomOutDistance: Double = 25_000_000 // Matches tourZoomOutDistance default
    @State private var buildingZoomDistance: Double = 700 // Matches fixedDistanceAlt default (updated)
    @State private var currentCity: String = "New York"
    @State private var aiRecommendation: String = "People nearby are posting street food finds and skyline shots — share your take!"
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
            MapViewProduction()
                .allowsHitTesting(true)
            
            // Removed SceneKitRotatingBarView overlay as per instructions

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
                .padding(.top, 20)
                .padding(.horizontal, 12)
                
                Spacer()
            }
            
            // AI Recommendation Overlay
            VStack {
                Spacer().frame(height: 24)
                
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
                .padding(.top, -4)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(radius: 4)
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
                                #if DEBUG
                                guard !IS_PREVIEW else { return }
                                #endif
                                NotificationCenter.default.post(
                                    name: .preview_setTourSpeedMultiplier,
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
                            Text("\(Int(zoomOutDistance / 1_000_000)) Mm")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                        Slider(value: $zoomOutDistance, in: 1_000_000...200_000_000, step: 1_000_000)
                            .onChange(of: zoomOutDistance) { _, newValue in
                                #if DEBUG
                                guard !IS_PREVIEW else { return }
                                #endif
                                NotificationCenter.default.post(
                                    name: .preview_setTourZoomOutDistance,
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
                        Slider(value: $buildingZoomDistance, in: 100...20_000, step: 100) // Adjusted range to match new clamp
                            .onChange(of: buildingZoomDistance) { _, newValue in
                                NotificationCenter.default.post(
                                    name: .preview_setBuildingZoomDistance,
                                    object: nil,
                                    userInfo: ["distance": newValue]
                                )
                            }
                    }
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            NotificationCenter.default.post(name: .preview_stopDominanceTour, object: nil)
                        }) {
                            Label("Stop", systemImage: "stop.fill")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            NotificationCenter.default.post(name: .preview_startDominanceTour, object: nil)
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
                NotificationCenter.default.post(name: .preview_stopDominanceTour, object: nil)
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
                    NotificationCenter.default.post(name: .preview_stopDominanceTour, object: nil)
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
#if POP_PREVIEW_LIGHT
            return
#endif
            #if DEBUG
            if IS_PREVIEW { return }
            #endif

            // Start tour after brief delay
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            NotificationCenter.default.post(name: .preview_startDominanceTour, object: nil)
            
            // Cycle AI recommendations
            let cities = [
                ("San Francisco", "Trending posts: Golden Gate views and coffee spots — snap a photo from your vantage point."),
                ("New York", "People nearby are posting street food finds and skyline shots — share your take!"),
                ("Los Angeles", "Popular now: murals and sunset beaches — post your favorite scene."),
                ("Chicago", "Hot right now: riverwalk reflections and deep-dish moments — add yours."),
                ("Miami", "Trending: pastel art deco and ocean vibes — capture and post your view."),
                ("Seattle", "Popular nearby: cozy cafes and skyline-in-the-mist — share your snapshot."),
                ("Boston", "Trending posts: cobblestone corners and harbor light — what do you see?"),
                ("Austin", "Now popular: live music clips and neon nights — post a moment from your spot.")
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

// MARK: - SceneKit Rotating Bar View (replaces Earth globe)

#if !POP_PREVIEW_LIGHT && (!DEBUG || !IS_PREVIEW)
private struct SceneKitRotatingBarView: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear

        let scene = SCNScene()
        view.scene = scene

        // Camera
        let cameraNode = SCNNode()
        let cam = SCNCamera()
        cam.zFar = 100
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, 0, 6)
        scene.rootNode.addChildNode(cameraNode)

        // Bar geometry
        let barWidth: CGFloat = 4.0
        let barHeight: CGFloat = 0.4
        let barLength: CGFloat = 0.1
        let box = SCNBox(width: barWidth, height: barHeight, length: barLength, chamferRadius: 0.06)
        let mat = SCNMaterial()
        mat.isDoubleSided = true
        mat.diffuse.contents = Self.textImage(from: text)
        mat.emission.contents = UIColor(white: 1.0, alpha: 0.08)
        mat.lightingModel = .physicallyBased
        box.materials = [mat]

        let barNode = SCNNode(geometry: box)
        scene.rootNode.addChildNode(barNode)

        // Rotation
        let rotation = CABasicAnimation(keyPath: "rotation")
        rotation.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi * 2))
        rotation.duration = 12
        rotation.repeatCount = .infinity
        barNode.addAnimation(rotation, forKey: "rotation")

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update material texture when text changes
        if let node = uiView.scene?.rootNode.childNodes.first(where: { $0.geometry is SCNBox }),
           let box = node.geometry as? SCNBox,
           let mat = box.materials.first {
            mat.diffuse.contents = Self.textImage(from: text)
        }
        uiView.backgroundColor = .clear
    }

    private static func textImage(from text: String) -> UIImage {
        // Render a single-line label into an image with transparent background
        let padding: CGFloat = 16
        let font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let canvas = CGSize(width: max(16, size.width + padding * 2), height: max(24, size.height + padding))
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { ctx in
            // Optional subtle backdrop for contrast
            let rect = CGRect(origin: .zero, size: canvas)
            UIColor(white: 0.0, alpha: 0.15).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
            // Draw text centered
            let textRect = CGRect(x: (canvas.width - size.width)/2, y: (canvas.height - size.height)/2, width: size.width, height: size.height)
            (text as NSString).draw(in: textRect, withAttributes: attributes)
        }
    }
}
#endif

// MARK: - Rotating Earth Globe Preview replaced with Rotating Bar and AI text

private struct RotatingEarthGlobePreview: View {
    @State private var rotationAngle: Double = 0
    @State private var showGlobeInfo: Bool = true
    @State private var aiText: String = "Explore the vibrant streets of Manhattan and discover world-class dining."

    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()

            if showGlobeInfo {
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI Suggestion")
                                .font(.title2).fontWeight(.bold)
                            Text(aiText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button(action: { showGlobeInfo.toggle() }) {
                            Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding()
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Production MapView (Clean - No Debug Controls)

/// The main MapView used in the app - shows map with AI recommendations and navigation
struct MapViewProduction: View {
    #if DEBUG
    @StateObject private var locationManager = IS_PREVIEW ? PreviewLocationManager.stubForPreviewInstance() : PreviewLocationManager()
    #else
    @StateObject private var locationManager = PreviewLocationManager()
    #endif
    
    @State private var fixedDistanceAlt: CLLocationDistance = 700 // Same as interactive preview
    @State private var camera: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 40.748339, longitude: -73.985912),
            distance: 700,
            heading: 52,
            pitch: 60
        )
    )
    
    @State private var currentCity: String = "New York"
    @State private var aiRecommendation: String = "People nearby are posting street food finds and skyline shots — share your take!"
    @State private var showPlacesList: Bool = false
    @State private var showAddressSearch: Bool = false
    @State private var searchQuery: String = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching: Bool = false
    
    @State private var posts: [PreviewMapAnnotationPost] = []
    @State private var dominance: [PreviewCityDominance] = []
    @State private var radiusMeters: Double = 5_000
    
    @State private var lastInteractionAt: Date = Date()
    @State private var isTourActive: Bool = false
    @State private var currentTourIndex: Int = 0
    @State private var tourZoomOutDistance: CLLocationDistance = 25_000_000 // Distance for zoom out
    @State private var isZoomedOut: Bool = false
    
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
    
    init() {
        // Initialize with demo cities synchronously to avoid crash
        _dominance = State(initialValue: [
            PreviewCityDominance(city: "San Francisco", coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), profileURL: nil),
            PreviewCityDominance(city: "New York", coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), profileURL: nil)
        ])
    }
    
    private func lockCamera(_ pos: MapCameraPosition) -> MapCameraPosition {
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
    
    private func zoomOut(to coordinate: CLLocationCoordinate2D) {
        let heading = camera.camera?.heading ?? 0
        withAnimation(.easeInOut(duration: 2.5)) {
            camera = .camera(
                MapCamera(
                    centerCoordinate: coordinate,
                    distance: tourZoomOutDistance,
                    heading: heading,
                    pitch: 0 // Flat view when zoomed out
                )
            )
        }
    }
    
    private func zoomIn(to coordinate: CLLocationCoordinate2D) {
        let heading = camera.camera?.heading ?? 0
        withAnimation(.easeInOut(duration: 2.5)) {
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
    
    private func filteredPosts() -> [PreviewMapAnnotationPost] {
        guard let userLoc = locationManager.location else { return posts }
        return posts.filter {
            MKMapPoint(userLoc.coordinate).distance(to: MKMapPoint($0.coordinate)) <= radiusMeters
        }
    }
    
    private func noteInteraction() {
        lastInteractionAt = Date()
        // Stop tour when user interacts with map
        isTourActive = false
    }
    
    private func startTour() {
        guard !isTourActive else { return }
        isTourActive = true
        currentTourIndex = 0
    }
    
    private func stopTour() {
        isTourActive = false
    }
    
    private func centerOnUserLocation() {
        guard let userCoordinate = locationManager.location?.coordinate else { return }
        
        // Stop any active tour
        isTourActive = false
        isZoomedOut = false
        
        // Update city and recommendation based on location (default to current city name)
        currentCity = "Your Location"
        aiRecommendation = "Explore what's happening around you right now!"
        
        // Animate to user's location
        let heading = camera.camera?.heading ?? 0
        withAnimation(.easeInOut(duration: 1.2)) {
            camera = .camera(
                MapCamera(
                    centerCoordinate: userCoordinate,
                    distance: fixedDistanceAlt,
                    heading: heading,
                    pitch: fixedPitchAlt
                )
            )
        }
    }
    
    private func tourToNextPlace() {
        guard isTourActive, !tourPlaces.isEmpty else { return }
        
        let place = tourPlaces[currentTourIndex]
        
        // Update AI recommendation for current city
        let cityRecommendations: [String: String] = [
            "San Francisco": "Trending posts: Golden Gate views and coffee spots — snap a photo from your vantage point.",
            "New York": "People nearby are posting street food finds and skyline shots — share your take!",
            "Los Angeles": "Popular now: murals and sunset beaches — post your favorite scene.",
            "Chicago": "Hot right now: riverwalk reflections and deep-dish moments — add yours.",
            "Miami": "Trending: pastel art deco and ocean vibes — capture and post your view.",
            "Seattle": "Popular nearby: cozy cafes and skyline-in-the-mist — share your snapshot.",
            "Boston": "Trending posts: cobblestone corners and harbor light — what do you see?",
            "Austin": "Now popular: live music clips and neon nights — post a moment from your spot."
        ]
        
        // Zoom out first, then zoom back in at the new location
        if !isZoomedOut {
            // Zoom out from current location - reset radius to 0
            if let currentCoord = camera.camera?.centerCoordinate {
                // Reset radius bar when zooming out
                print("[MapTour] Zooming out - resetting radius to 0")
                NotificationCenter.default.post(
                    name: .MapSuggestedRadius,
                    object: nil,
                    userInfo: ["radius": 0.0]
                )
                withAnimation(.easeInOut(duration: 1.5)) {
                    radiusMeters = 0
                }
                
                zoomOut(to: currentCoord)
                isZoomedOut = true
            }
        } else {
            // Update city and recommendation BEFORE zooming in
            currentCity = place.name
            aiRecommendation = cityRecommendations[place.name] ?? "Explore what's happening here!"
            
            // Zoom in to the new place
            zoomIn(to: place.coordinate)
            isZoomedOut = false
            
            // Update radius to a random value between 2km and 15km AFTER starting zoom
            // This creates the effect of the bar rising as we zoom into the city
            let newRadius = Double.random(in: 2_000...15_000)
            
            // Delay slightly to sync with zoom-in animation
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                
                print("[MapTour] Zooming into \(place.name) - setting radius to \(Int(newRadius))m")
                
                // Animate radius bar up
                withAnimation(.easeInOut(duration: 2.0)) {
                    radiusMeters = newRadius
                }
                
                // Notify HomeView to animate the radius bar
                NotificationCenter.default.post(
                    name: .MapSuggestedRadius,
                    object: nil,
                    userInfo: ["radius": newRadius]
                )
            }
            
            // Move to next place
            currentTourIndex = (currentTourIndex + 1) % tourPlaces.count
        }
    }
    
    var body: some View {
        ZStack {
            // Main Map Layer - Same settings as interactive preview
            Map(
                position: Binding(
                    get: { camera },
                    set: { camera = lockCamera($0) }
                ),
                interactionModes: [.pan, .rotate, .pitch, .zoom]
            ) {
                // Only show user annotation when not in preview and location available
                if !IS_PREVIEW {
                    if locationManager.location != nil {
                        UserAnnotation {
                            Label("You", systemImage: "location.fill")
                        }
                    }
                }
                
                ForEach(filteredPosts()) { post in
                    Annotation(post.title, coordinate: post.coordinate) {
                        PreviewGoogleStylePin()
                    }
                    
                    MapCircle(center: post.coordinate, radius: post.radius)
                        .foregroundStyle(Color.white.opacity(0.08))
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                }
                
                ForEach(dominance) { dom in
                    Annotation(dom.city, coordinate: dom.coordinate) {
                        if let url = dom.profileURL {
                            PreviewDominancePin(profileURL: url)
                        } else {
                            PreviewGoogleStylePin()
                        }
                    }
                }
            }
#if POP_PREVIEW_LIGHT
            .mapStyle(.standard)
#else
            .mapStyle(.hybrid(elevation: .realistic, showsTraffic: false))
#endif
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in noteInteraction() })
            .simultaneousGesture(TapGesture().onEnded { noteInteraction() })
            
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
                .padding(.top, 20)
                .padding(.horizontal, 12)
                
                Spacer()
            }
            
            // AI Recommendation Overlay
            VStack {
                Spacer().frame(height: 24)
                
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
                .padding(.top, -4)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(radius: 4)
                .padding(.horizontal)
                
                Spacer()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPlacesList) {
            PlacesListView(places: tourPlaces) { place in
                showPlacesList = false
                panTo(place.coordinate)
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
                    panTo(coord)
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            #if DEBUG
            if IS_PREVIEW {
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
                return
            }
            #endif
            
            locationManager.requestAuthorizationIfNeeded()
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
        }
        .onChange(of: locationManager.location) { _, _ in
            if !IS_PREVIEW, let _ = locationManager.location {
                locationManager.centerOnUser(&camera)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .CubeGlobalTap)) { _ in
            // When cube is tapped while on map tab, center on user location
            centerOnUserLocation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .CenterMapOnUser)) { _ in
            // Also respond to the standard center map notification
            centerOnUserLocation()
        }
        .task {
            // Start tour after 5 seconds
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            startTour()
            
            // Tour loop - alternates between zoom out (3s) and zoom in (12s at location)
            while !Task.isCancelled {
                if isTourActive {
                    tourToNextPlace()
                    
                    // Wait for animation duration based on zoom state
                    if isZoomedOut {
                        // Just zoomed out, wait 3 seconds before zooming in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                    } else {
                        // Just zoomed in, wait 12 seconds at this location before next transition
                        try? await Task.sleep(nanoseconds: 12_000_000_000)
                    }
                } else {
                    // If tour is stopped, wait a bit before checking again
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
// Full preview - WITH controls and globe
#Preview("Interactive Tour with Controls") {
    MapTourPreviewWithControls()
        .onAppear {
            print("🗺️ Tour preview loaded")
        }
}

#Preview("Production MapView") {
    MapViewProduction()
        .onAppear {
            print("🗺️ Production MapView loaded")
        }
}

#Preview("Rotating Earth Globe") {
    RotatingEarthGlobePreview()
        .onAppear {
            print("🌍 Globe preview loaded")
        }
}
#endif
