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

// MapView listens for:
// - SetCameraCoordinate: ["latitude": Double, "longitude": Double] to navigate to a post's location

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
    func request() {} // Compatibility with LocationProvider
    func requestAuthorizationIfNeeded() {}
    
    /// Returns a MapCameraPosition centered on the user's current location
    func getCenteredCamera() -> MapCameraPosition? {
        guard let coord = location?.coordinate else { return nil }
        return .camera(MapCamera(centerCoordinate: coord, distance: 300, heading: 0, pitch: 60))
    }
    
    /// Centers the map camera on the user's current location (mutating version)
    func centerOnUser(_ camera: Binding<MapCameraPosition>) {
        guard let coord = location?.coordinate else { return }
        camera.wrappedValue = .camera(MapCamera(centerCoordinate: coord, distance: 300, heading: 0, pitch: 60))
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

// MARK: - Cube Hold Search Overlay

/// Search overlay that appears when cube is held down - similar styling to AI text window
private struct CubeHoldSearchOverlay: View {
    @Binding var query: String
    @Binding var results: [MKMapItem]
    @Binding var isSearching: Bool
    @FocusState private var isSearchFieldFocused: Bool
    
    let tourPlaces: [(name: String, coordinate: CLLocationCoordinate2D, description: String)]
    let onSelectPlace: ((name: String, coordinate: CLLocationCoordinate2D, description: String)) -> Void
    let onSelectMapItem: (MKMapItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                
                TextField("Search for a location", text: $query)
                    .textFieldStyle(.plain)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .font(.subheadline)
                    .focused($isSearchFieldFocused)
                    .onChange(of: query) { _, newValue in
                        // Trigger autocomplete search as user types
                        if !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                            performSearch()
                        } else {
                            results = []
                        }
                    }
                    .onSubmit {
                        performSearch()
                    }
                
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !query.isEmpty {
                    Button(action: {
                        query = ""
                        results = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(10)
            .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            // Show search results if searching, otherwise show favorites
            if !query.isEmpty && !results.isEmpty {
                // Search results with autocomplete
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(results.prefix(8), id: \.self) { item in
                            Button(action: {
                                onSelectMapItem(item)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "Unknown")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                        if let subtitle = item.placemark.title {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            
                            if item != results.prefix(8).last {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            } else if query.isEmpty {
                // Favorites list - show top 10 tour places
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Favorites")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                        
                        ForEach(tourPlaces.prefix(10).indices, id: \.self) { index in
                            let place = tourPlaces[index]
                            Button(action: {
                                onSelectPlace(place)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(place.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                        Text(place.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            
                            if index < min(9, tourPlaces.count - 1) {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            } else if !query.isEmpty && !isSearching {
                // No results found
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No results found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 4)
        .padding(.horizontal)
        .padding(.top, 8)
        .onAppear {
            // Auto-focus search field when menu appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }
        }
    }
    
    private func performSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        
        isSearching = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        
        // Enable autocomplete by searching for partial matches
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            self.results = response?.mapItems ?? []
            self.isSearching = false
        }
    }
}

// MARK: - Production MapView (Clean - No Debug Controls)

/// The main MapView used in the app - shows map with AI recommendations and navigation
struct MapViewProduction: View {
    @StateObject private var locationManager = LocationProvider()
    @StateObject private var flowManager = CaptureFlowManager.shared
    @StateObject private var mapState = MapStateManager.shared
    
    @State private var fixedDistanceAlt: CLLocationDistance = 300 // Closer zoom to avoid building obstruction
    @State private var camera: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // SF default, will update to user location
            distance: 300,
            heading: 0,
            pitch: 60
        )
    )
    
    @State private var currentCity: String = "Your Location"
    @State private var aiRecommendation: String = "Explore what's happening around you right now!"
    @State private var showPlacesList: Bool = false
    @State private var showAddressSearch: Bool = false
    @State private var showCubeHoldSearch: Bool = false  // NEW: For long-press search
    @State private var searchQuery: String = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching: Bool = false
    @State private var clickedCoordinate: CLLocationCoordinate2D? = nil  // Track clicked coordinate
    @State private var showPostPrompt: Bool = false  // Show "Post Here?" prompt
    
    @State private var posts: [PreviewMapAnnotationPost] = []
    @State private var dominance: [PreviewCityDominance] = []
    @State private var radiusMeters: Double = 5_000
    
    @State private var currentTourIndex: Int = 0
    @State private var tourZoomOutDistance: CLLocationDistance = 25_000_000 // Distance for zoom out
    @State private var isZoomedOut: Bool = false
    @State private var hasSetInitialLocation: Bool = false  // Track if we've set initial location
    
    @State private var longPressLocation: CGPoint? = nil  // Track long press location
    @State private var selectedCoordinate: CLLocationCoordinate2D? = nil  // Track selected coordinate for long-press
    
    // Post placement mode - when user needs to select location for captured media
    @State private var isPostPlacementMode: Bool = false
    @State private var pendingPostImage: UIImage? = nil
    @State private var pendingPostVideoURL: URL? = nil
    @State private var postPlacementCoordinate: CLLocationCoordinate2D? = nil
    
    @State private var suppressUserCenteringUntil: Date? = nil
    
    @State private var lockToPostUntil: Date? = nil // Added state for hard lock on post
    
    // Shown post location (for displaying pin and radius)
    @State private var shownPostCoordinate: CLLocationCoordinate2D? = nil
    @State private var shownPostRadius: Double? = nil
    @State private var shownPostUsername: String? = nil
    @State private var shownPostCityName: String? = nil
    @State private var shownPostCountryName: String? = nil
    @State private var shownPostCountryFlag: String? = nil
    
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
    
    /// Navigate to a location using tour-style transitions (zoom out, move, zoom in)
    private func navigateWithTourTransition(to coordinate: CLLocationCoordinate2D, cityName: String = "Selected Location", postRadius: Double? = nil) {
        print("🎯 [navigateWithTourTransition] Starting transition")
        print("   Target: \(coordinate.latitude), \(coordinate.longitude)")
        print("   City: \(cityName)")
        print("   Post radius: \(postRadius ?? 0)m")
        print("   shownPostCoordinate: \(String(describing: shownPostCoordinate))")
        print("   CURRENT currentCity: '\(currentCity)'")
        print("   CURRENT aiRecommendation: '\(aiRecommendation)'")
        
        // Stop any active tour
        mapState.stopTour()
        
        // Only update UI text if we're NOT showing a post location
        // (showing post location sets comprehensive text that shouldn't be overridden)
        if shownPostCoordinate == nil {
            print("   ⚠️ shownPostCoordinate is nil - UPDATING UI text")
            currentCity = cityName
            aiRecommendation = "Explore what's happening here!"
        } else {
            print("   ✅ shownPostCoordinate is SET - PRESERVING existing UI text")
            print("      Keeping currentCity: '\(currentCity)'")
            print("      Keeping aiRecommendation: '\(aiRecommendation)'")
        }
        
        let currentCoord = camera.camera?.centerCoordinate ?? coordinate
        print("   Current camera: \(currentCoord.latitude), \(currentCoord.longitude)")
        print("   Zoom out distance: \(tourZoomOutDistance)m")
        
        // Step 1: Zoom out from current location (FASTER - 0.8s instead of 1.5s)
        print("🔍 [Step 1] Zooming out from current location (0.8s)")
        withAnimation(.easeInOut(duration: 0.8)) {
            camera = .camera(
                MapCamera(
                    centerCoordinate: currentCoord,
                    distance: tourZoomOutDistance,
                    heading: 0,
                    pitch: 0
                )
            )
        }
        
        // Step 2: Pan to new location while zoomed out (FASTER - 1.5s instead of 3.0s)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            
            print("➡️ [Step 2] Panning to target location (1.5s)")
            withAnimation(.easeInOut(duration: 1.5)) {
                camera = .camera(
                    MapCamera(
                        centerCoordinate: coordinate,
                        distance: tourZoomOutDistance,
                        heading: 0,
                        pitch: 0
                    )
                )
            }
            
            // Step 3: Zoom in to new location (FASTER - 1.2s instead of 2.0s)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            print("🔎 [Step 3] Zooming in to target location (1.2s)")
            withAnimation(.easeInOut(duration: 1.2)) {
                camera = .camera(
                    MapCamera(
                        centerCoordinate: coordinate,
                        distance: fixedDistanceAlt,
                        heading: 0,
                        pitch: fixedPitchAlt
                    )
                )
            }
            
            // Update radius display if post radius is provided
            if let radius = postRadius {
                try? await Task.sleep(nanoseconds: 300_000_000) // Small delay for smooth transition
                
                print("📏 [Step 4] Updating radius display to \(Int(radius))m")
                withAnimation(.easeInOut(duration: 0.8)) {
                    radiusMeters = radius
                }
                
                // Notify HomeView to update the radius bar
                NotificationCenter.default.post(
                    name: .MapSuggestedRadius,
                    object: nil,
                    userInfo: ["radius": radius]
                )
            }
            
            print("✅ [navigateWithTourTransition] Animation sequence complete")
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
        // Delegate to state manager
        mapState.noteUserInteraction()
    }
    
    private func startTour() {
        mapState.startTour()
    }
    
    private func stopTour() {
        mapState.stopTour()
    }
    
    private func centerOnUserLocation() {
        // Respect lockToPost window
        if let until = lockToPostUntil, until > Date() {
            print("⛔️ [MapView] centerOnUserLocation ignored during lockToPost window")
            return
        }
        
        guard let userCoordinate = locationManager.location?.coordinate else { return }
        
        // Stop any active operations and return to browsing
        mapState.cancelCurrentOperation()
        
        // Update city and recommendation
        currentCity = "Your Location"
        aiRecommendation = "Explore what's happening around you right now!"
        
        // Use tour-style transition to go back to current location
        navigateWithTourTransition(to: userCoordinate, cityName: "Your Location")
    }
    
    private func uploadPostToSelectedLocation() {
        guard let coordinate = postPlacementCoordinate else {
            print("[MapView] No coordinate selected for post placement")
            return
        }
        
        print("[MapView] Uploading post to coordinate: \(coordinate.latitude), \(coordinate.longitude)")
        
        // Post notification to upload the pending media to this location
        var userInfo: [String: Any] = [
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude
        ]
        
        if let image = pendingPostImage {
            userInfo["image"] = image
        }
        
        if let videoURL = pendingPostVideoURL {
            userInfo["videoURL"] = videoURL
        }
        
        NotificationCenter.default.post(
            name: Notification.Name("UploadPostToCoordinate"),
            object: nil,
            userInfo: userInfo
        )
        
        // Exit post placement mode
        isPostPlacementMode = false
        pendingPostImage = nil
        pendingPostVideoURL = nil
        postPlacementCoordinate = nil
        
        // Return to normal map state
        currentCity = "Your Location"
        aiRecommendation = "Explore what's happening around you right now!"
    }
    
    private func tourToNextPlace() {
        guard mapState.isInTourMode, !tourPlaces.isEmpty else { return }
        
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
    
    // MARK: - Computed Properties
    
    private var cameraBinding: Binding<MapCameraPosition> {
        Binding(
            get: { camera },
            set: { newValue in
                // Don't lock camera when navigating from feed posts or in selection modes
                // Only lock during tour mode
                if mapState.isInTourMode {
                    camera = lockCamera(newValue)
                } else {
                    // Allow free camera movement
                    camera = newValue
                }
            }
        )
    }
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in noteInteraction() }
    }
    
    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded { 
                // If menu is open, close it on map tap
                if showCubeHoldSearch {
                    showCubeHoldSearch = false
                }
                noteInteraction() 
            }
    }
    
    @ViewBuilder
    private var mapView: some View {
        MapReader { proxy in
            Map(
                position: cameraBinding,
                interactionModes: [.pan, .rotate, .pitch, .zoom]
            ) {
                let _ = print("🗺️ [MapView] Map body re-evaluating, shownPostCoordinate: \(String(describing: shownPostCoordinate))")
                // Show user annotation when location is available
                if locationManager.location != nil {
                    UserAnnotation {
                        Label("You", systemImage: "location.fill")
                    }
                }
                
                // Show marker when user clicks a coordinate
                if showPostPrompt, let coord = clickedCoordinate {
                    Annotation("Selected Location", coordinate: coord) {
                        ZStack {
                            Circle()
                                .fill(Color.indigo.opacity(0.3))
                                .frame(width: 50, height: 50)
                            
                            // Show different icon based on flow
                            if flowManager.currentFlow?.isCameraFirst ?? false {
                                // Camera -> Map: Show upload/checkmark icon
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.indigo, .white)
                            } else {
                                // Map -> Camera: Show camera icon
                                Image(systemName: "camera.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.indigo, .white)
                            }
                        }
                    }
                }
                
                // Show placement marker when in post placement mode
                if isPostPlacementMode, let coord = postPlacementCoordinate {
                    Annotation("Post Location", coordinate: coord) {
                        ZStack {
                            Circle()
                                .fill(Color.indigo.opacity(0.3))
                                .frame(width: 50, height: 50)
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.indigo, .white)
                        }
                    }
                }
                
                // Show pin for post location being viewed
                if let coord = shownPostCoordinate {
                    // Debug: Log that we're rendering the annotation
                    let _ = print("🗺️ [MapView] Rendering post annotation at: \(coord.latitude), \(coord.longitude)")
                    let _ = print("   Radius: \(shownPostRadius ?? 0)m")
                    let _ = print("   Username: \(shownPostUsername ?? "nil")")
                    
                    // Show radius circle if available
                    if let radius = shownPostRadius {
                        MapCircle(center: coord, radius: radius)
                            .foregroundStyle(Color.purple.opacity(0.15))
                            .stroke(Color.purple.opacity(0.5), lineWidth: 2)
                    }
                    
                    // Build comprehensive annotation label showing all key info
                    let annotationLabel: String = {
                        var components: [String] = []
                        
                        // Username
                        if let username = shownPostUsername {
                            components.append(username)
                        }
                        
                        // Coordinates
                        let coordText = String(format: "%.4f, %.4f", coord.latitude, coord.longitude)
                        components.append(coordText)
                        
                        // Location (flag + city)
                        if let cityName = shownPostCityName {
                            let flag = shownPostCountryFlag ?? ""
                            let cityText = flag.isEmpty ? cityName : "\(flag) \(cityName)"
                            components.append(cityText)
                        }
                        
                        return components.joined(separator: " • ")
                    }()
                    
                    // Show detailed pin annotation with comprehensive label
                    Annotation(annotationLabel, coordinate: coord) {
                        VStack(spacing: 8) {
                            // Information card above the pin
                            VStack(spacing: 8) {
                                // Username
                                if let username = shownPostUsername {
                                    Text(username)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                }
                                
                                // Coordinates
                                Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                
                                // City and country
                                if let cityName = shownPostCityName, let countryName = shownPostCountryName {
                                    HStack(spacing: 6) {
                                        if let flag = shownPostCountryFlag {
                                            Text(flag)
                                                .font(.system(size: 18))
                                        }
                                        Text("\(cityName), \(countryName)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                // Radius
                                if let radius = shownPostRadius {
                                    let radiusText = radius >= 1000 
                                        ? String(format: "%.1f km", radius / 1000) 
                                        : String(format: "%.0f m", radius)
                                    HStack(spacing: 4) {
                                        Image(systemName: "circle.dotted")
                                            .font(.system(size: 12))
                                        Text("Radius: \(radiusText)")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundStyle(.purple)
                                }
                                
                                // Back to Feed button
                                Button {
                                    print("📱 [MapView] Back to Feed tapped - clearing post location")
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        shownPostCoordinate = nil
                                        shownPostRadius = nil
                                        shownPostUsername = nil
                                        shownPostCityName = nil
                                        shownPostCountryName = nil
                                        shownPostCountryFlag = nil
                                    }
                                    
                                    // Return to browsing mode
                                    mapState.cancelCurrentOperation()
                                    
                                    // Switch back to feed tab
                                    NotificationCenter.default.post(
                                        name: Notification.Name("SwitchToFeedTab"),
                                        object: nil
                                    )
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.left")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("Back to Feed")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.purple, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            .onAppear {
                                print("📋 [MapView] Annotation card rendered with:")
                                print("   Username: \(shownPostUsername ?? "nil")")
                                print("   Coordinates: \(coord.latitude), \(coord.longitude)")
                                print("   City: \(shownPostCityName ?? "nil")")
                                print("   Country: \(shownPostCountryName ?? "nil")")
                                print("   Flag: \(shownPostCountryFlag ?? "nil")")
                                print("   Radius: \(shownPostRadius ?? 0)")
                            }
                            
                            // Pin marker
                            ZStack {
                                Circle()
                                    .fill(Color.purple.opacity(0.3))
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.purple, .white)
                                    .shadow(radius: 3)
                            }
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
            .gesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { event in
                        let screenCoordinate = event.location
                        // Handle map tap based on current flow
                        if let flow = flowManager.currentFlow, flow.isCameraFirst {
                            // Flow 2: Camera -> Map - User already captured, now selecting location
                            if let coordinate = proxy.convert(screenCoordinate, from: .local) {
                                clickedCoordinate = coordinate
                                showPostPrompt = true
                                
                                currentCity = "Location Selected"
                                aiRecommendation = String(format: "📍 %.4f°, %.4f° — Post your capture here?", 
                                                         coordinate.latitude, 
                                                         coordinate.longitude)
                                print("[MapView] Camera -> Map flow: Selected coordinate \(coordinate.latitude), \(coordinate.longitude)")
                            }
                        } else {
                            // Flow 1: Map -> Camera OR normal browsing
                            if showCubeHoldSearch {
                                showCubeHoldSearch = false
                            } else if let coordinate = proxy.convert(screenCoordinate, from: .local) {
                                // Store clicked coordinate and show prompt
                                clickedCoordinate = coordinate
                                showPostPrompt = true
                                
                                // Update AI text to show coordinate
                                currentCity = "Location Selected"
                                aiRecommendation = String(format: "📍 %.4f°, %.4f° — Want to post here?", 
                                                         coordinate.latitude, 
                                                         coordinate.longitude)
                                print("[MapView] Normal tap: Showing post prompt at \(coordinate.latitude), \(coordinate.longitude)")
                            }
                            noteInteraction()
                        }
                    }
            )
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: SpatialTapGesture(coordinateSpace: .local))
                    .onEnded { value in
                        // Only handle long press when NOT in post placement mode
                        guard !isPostPlacementMode else { return }
                        
                        switch value {
                        case .second(_, let tap?):
                            let screenCoordinate = tap.location
                            // Convert screen coordinate to map coordinate and open camera at that location
                            if let coordinate = proxy.convert(screenCoordinate, from: .local) {
                                print("[MapView] Long press at coordinate: \(coordinate.latitude), \(coordinate.longitude)")
                                
                                // Post notification to switch to camera tab and set the coordinate
                                NotificationCenter.default.post(
                                    name: Notification.Name("OpenCameraAtCoordinate"),
                                    object: nil,
                                    userInfo: [
                                        "coordinate": coordinate,
                                        "latitude": coordinate.latitude,
                                        "longitude": coordinate.longitude
                                    ]
                                )
                            }
                        default:
                            break
                        }
                    }
            )
        }
    }
    
    // MARK: - Body Components (broken down to help compiler)
    
    @ViewBuilder
    private var navigationButtons: some View {
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
    }
    
    @ViewBuilder
    private var aiRecommendationOverlay: some View {
        VStack {
            Spacer().frame(height: 24)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Update title based on flow
                    let titleText: String = {
                        if let flow = flowManager.currentFlow, flow.isCameraFirst {
                            return "Select Post Location"
                        } else if isPostPlacementMode {
                            return "Select Post Location"
                        } else {
                            return currentCity
                        }
                    }()
                    
                    let recommendationText: String = {
                        if let flow = flowManager.currentFlow, flow.isCameraFirst {
                            return "Tap where you want to post your capture"
                        } else if isPostPlacementMode {
                            return "Tap on the map to choose where to place your post"
                        } else {
                            return aiRecommendation
                        }
                    }()
                    
                    Text(titleText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(recommendationText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                
                // Dismiss button when showing post prompt or in camera->map flow
                if showPostPrompt || (flowManager.currentFlow?.isCameraFirst ?? false) {
                    Button(action: {
                        // Cancel the flow
                        if flowManager.currentFlow?.isCameraFirst ?? false {
                            flowManager.cancelFlow()
                        }
                        showPostPrompt = false
                        clickedCoordinate = nil
                        currentCity = "Your Location"
                        aiRecommendation = "Explore what's happening around you right now!"
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, -4)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(radius: 4)
            .padding(.horizontal)
            
            // Post Here button - shows when coordinate is clicked OR in post placement mode
            if showPostPrompt, let coordinate = clickedCoordinate {
                Button(action: {
                    // Check which flow we're in
                    if let flow = flowManager.currentFlow, flow.isCameraFirst {
                        // Flow 2: Camera -> Map -> Complete upload
                        print("📸 [MapView] Completing Camera -> Map flow, uploading to: \(coordinate.latitude), \(coordinate.longitude)")
                        flowManager.completeFlow(finalCoordinate: coordinate)
                        
                        // Reset UI
                        showPostPrompt = false
                        clickedCoordinate = nil
                        currentCity = "Your Location"
                        aiRecommendation = "Post uploaded successfully!"
                        
                        // Return to feed or profile after a delay
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            NotificationCenter.default.post(name: Notification.Name("SwitchToFeedTab"), object: nil)
                        }
                    } else {
                        // Flow 1: Map -> Camera -> Open camera at this location
                        print("📍 [MapView] Starting Map -> Camera flow at: \(coordinate.latitude), \(coordinate.longitude)")
                        flowManager.startMapToCameraFlow(coordinate: coordinate)
                        
                        // Open camera at this location
                        NotificationCenter.default.post(
                            name: Notification.Name("OpenCameraAtCoordinate"),
                            object: nil,
                            userInfo: [
                                "coordinate": coordinate,
                                "latitude": coordinate.latitude,
                                "longitude": coordinate.longitude
                            ]
                        )
                        
                        // Reset prompt
                        showPostPrompt = false
                        clickedCoordinate = nil
                        currentCity = "Your Location"
                        aiRecommendation = "Explore what's happening around you right now!"
                    }
                }) {
                    HStack {
                        if let flow = flowManager.currentFlow, flow.isCameraFirst {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Confirm & Post")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Post Here")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.indigo, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if isPostPlacementMode, let _ = postPlacementCoordinate {
                // Original post placement button
                Button(action: {
                    // Upload post to selected location
                    uploadPostToSelectedLocation()
                }) {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Post Here")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.indigo, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Cube Hold Search Overlay - appears below AI text
            if showCubeHoldSearch {
                CubeHoldSearchOverlay(
                    query: $searchQuery,
                    results: $searchResults,
                    isSearching: $isSearching,
                    tourPlaces: tourPlaces,
                    onSelectPlace: { place in
                        showCubeHoldSearch = false
                        
                        // If in post placement mode, set coordinate
                        if isPostPlacementMode {
                            postPlacementCoordinate = place.coordinate
                            panTo(place.coordinate)
                        } else {
                            navigateWithTourTransition(to: place.coordinate, cityName: place.name)
                        }
                    },
                    onSelectMapItem: { item in
                        showCubeHoldSearch = false
                        if let coord = item.placemark.location?.coordinate {
                            // If in post placement mode, set coordinate
                            if isPostPlacementMode {
                                postPlacementCoordinate = coord
                                panTo(coord)
                            } else {
                                let name = item.name ?? "Selected Location"
                                navigateWithTourTransition(to: coord, cityName: name)
                            }
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showCubeHoldSearch)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var mapContentLayer: some View {
        ZStack {
            // Main Map Layer - Same settings as interactive preview
            mapView
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .simultaneousGesture(dragGesture)
            
            // Top navigation buttons
            navigationButtons
            
            // AI Recommendation Overlay
            aiRecommendationOverlay
        }
    }
    
    var body: some View {
        mapContentLayer
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPlacesList) {
                placesListSheet
            }
            .sheet(isPresented: $showAddressSearch) {
                addressSearchSheet
            }
            .onAppear {
                handleOnAppear()
            }
            .onChange(of: locationManager.location) { _, newLocation in
                handleLocationChange(newLocation)
            }
            .onChange(of: showCubeHoldSearch) { _, isShowing in
                // Pause tour when menu is showing
                if isShowing {
                    mapState.stopTour()
                } else {
                    // Clear search when menu closes
                    searchQuery = ""
                    searchResults = []
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .CubeGlobalTap)) { _ in
                // If menu is open, close it on tap; otherwise center on location
                if showCubeHoldSearch {
                    showCubeHoldSearch = false
                } else {
                    // Respect lock/suppression windows after jumping to a post location
                    if let until = lockToPostUntil, until > Date() {
                        print("⛔️ [MapView] CubeGlobalTap centering ignored during lockToPost window")
                        return
                    }
                    if let until = suppressUserCenteringUntil, until > Date() {
                        print("⛔️ [MapView] CubeGlobalTap centering ignored during suppression window")
                        return
                    }
                    // Clear post prompt when centering on user
                    showPostPrompt = false
                    clickedCoordinate = nil
                    centerOnUserLocation()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldBegan)) { _ in
                // Toggle menu - if already open, keep it open
                // Pause tour when menu opens
                showCubeHoldSearch = true
                mapState.stopTour()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldEnded)) { _ in
                // Don't auto-close on release - let user keep menu open
                // Menu will close when:
                // 1. User taps elsewhere (CubeGlobalTap)
                // 2. User selects a location
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToMapTab"))) { _ in
                print("🔔 [MapView] SwitchToMapTab notification received!")
                print("   ❌❌❌ CRITICAL: pendingPostLocation is nil!")
                print("   ❌❌❌ This means FeedView long-press handler DID NOT RUN!")
                print("   ❌❌❌ Check FeedView.swift - the .onLongPressGesture is NOT firing!")
                print("   mapState.pendingPostLocation: \(String(describing: mapState.pendingPostLocation))")
                print("   mapState.pendingPostUsername: \(mapState.pendingPostUsername ?? "nil")")
                print("   mapState.pendingPostRadius: \(mapState.pendingPostRadius ?? 0)")
                
                // Add assertion to make this VERY visible
                if mapState.pendingPostLocation == nil {
                    print("")
                    print("════════════════════════════════════════════════════════════")
                    print("⛔️ DIAGNOSIS: FEEDVIEW LONG-PRESS GESTURE IS NOT WORKING ⛔️")
                    print("════════════════════════════════════════════════════════════")
                    print("Expected flow:")
                    print("1. User long-presses post in FeedView")
                    print("2. FeedView calls MapStateManager.setPendingPostLocation(...)")
                    print("3. FeedView posts ShowLocationOnMap notification")
                    print("4. FeedView posts SwitchToMapTab notification")
                    print("")
                    print("What's happening:")
                    print("❌ Steps 2-3 are SKIPPED - gesture not firing!")
                    print("✅ Only step 4 happens - tab switches with no data")
                    print("")
                    print("Fix: Check FeedView.swift for gesture conflicts!")
                    print("════════════════════════════════════════════════════════════")
                    print("")
                }
                
                // CHECK FOR PENDING POST LOCATION FIRST!
                if let pendingCoordinate = mapState.pendingPostLocation {
                    print("✨ [MapView] Found pending post location in SwitchToMapTab - navigating to it!")
                    
                    // Set locks FIRST with longer duration
                    suppressUserCenteringUntil = Date().addingTimeInterval(15)
                    lockToPostUntil = Date().addingTimeInterval(15)
                    hasSetInitialLocation = true
                    
                    print("🔒 [MapView] Set 15-second locks for pending navigation")
                    
                    // CRITICAL: Set shownPostCoordinate IMMEDIATELY
                    shownPostCoordinate = pendingCoordinate
                    shownPostRadius = mapState.pendingPostRadius
                    shownPostUsername = mapState.pendingPostUsername
                    shownPostCityName = mapState.pendingPostCityName
                    shownPostCountryName = mapState.pendingPostCountryName
                    shownPostCountryFlag = mapState.pendingPostCountryFlag
                    
                    print("💾 [MapView] Set shownPostCoordinate from pending:")
                    print("   Coordinate: \(pendingCoordinate.latitude), \(pendingCoordinate.longitude)")
                    print("   Username: \(shownPostUsername ?? "nil")")
                    print("   Radius: \(shownPostRadius ?? 0)m")
                    print("   City: \(shownPostCityName ?? "nil")")
                    print("   Country: \(shownPostCountryName ?? "nil")")
                    
                    // Stop tour and enter showing post location mode
                    mapState.stopTour()
                    mapState.showPostLocation(pendingCoordinate)
                    
                    // Update UI with comprehensive location info
                    let latStr = String(format: "%.4f", pendingCoordinate.latitude)
                    let lonStr = String(format: "%.4f", pendingCoordinate.longitude)
                    
                    var cityComponents: [String] = []
                    if let username = mapState.pendingPostUsername {
                        cityComponents.append(username)
                    }
                    cityComponents.append("\(latStr), \(lonStr)")
                    if let flag = mapState.pendingPostCountryFlag, let city = mapState.pendingPostCityName {
                        cityComponents.append("\(flag) \(city)")
                    } else if let city = mapState.pendingPostCityName {
                        cityComponents.append(city)
                    }
                    
                    currentCity = cityComponents.joined(separator: " • ")
                    
                    if let radius = mapState.pendingPostRadius {
                        let radiusText = radius >= 1000 
                            ? String(format: "%.1f km", radius / 1000) 
                            : String(format: "%.0f m", radius)
                        aiRecommendation = "Post radius: \(radiusText)"
                    } else {
                        aiRecommendation = "Viewing post location"
                    }
                    
                    print("✅ [MapView] Set UI text:")
                    print("   currentCity: '\(currentCity)'")
                    print("   aiRecommendation: '\(aiRecommendation)'")
                    
                    // Small delay to ensure SwiftUI processes the state changes
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        
                        print("📸 [MapView] Now snapping camera to coordinate")
                        
                        // Snap to coordinate immediately
                        withAnimation(.none) {
                            camera = .camera(
                                MapCamera(
                                    centerCoordinate: pendingCoordinate,
                                    distance: fixedDistanceAlt,
                                    heading: 0,
                                    pitch: fixedPitchAlt
                                )
                            )
                        }
                        
                        print("🎬 [MapView] Starting tour-style transition")
                        
                        // Start tour-style transition with post radius
                        navigateWithTourTransition(to: pendingCoordinate, cityName: "Post Location", postRadius: mapState.pendingPostRadius)
                        
                        // Clear pending location AFTER navigation starts
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        mapState.clearPendingPostLocation()
                    }
                    
                    return // Exit early - don't set shorter locks below
                }
                
                print("ℹ️ [MapView] No pending post location - normal tab switch")
                
                // Normal tab switch behavior (no pending location)
                // When switching to map, DON'T override existing locks if they're already set
                // This allows ShowLocationOnMap to set longer locks that won't be overridden
                mapState.stopTour()
                hasSetInitialLocation = true // prevent onAppear/location from snapping back
                
                let now = Date()
                
                // Only set suppression if not already set or if existing one has expired
                if let existingUntil = suppressUserCenteringUntil, existingUntil > now {
                    let remaining = existingUntil.timeIntervalSince(now)
                    print("🗺️ [MapView] SwitchToMapTab: keeping existing suppression window (expires in \(String(format: "%.1f", remaining))s)")
                } else {
                    suppressUserCenteringUntil = now.addingTimeInterval(10)
                    print("🗺️ [MapView] SwitchToMapTab: setting new suppression window (10s)")
                }
                
                // Only set lock if not already set or if existing one has expired
                if let existingUntil = lockToPostUntil, existingUntil > now {
                    let remaining = existingUntil.timeIntervalSince(now)
                    print("🗺️ [MapView] SwitchToMapTab: keeping existing lock window (expires in \(String(format: "%.1f", remaining))s)")
                } else {
                    lockToPostUntil = now.addingTimeInterval(10)
                    print("🗺️ [MapView] SwitchToMapTab: setting new lock window (10s)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .CenterMapOnUser)) { _ in
                // Respect suppression/lock windows after jumping to a post location
                if let until = lockToPostUntil, until > Date() {
                    print("⛔️ [MapView] CenterMapOnUser ignored during lockToPost window")
                    return
                }
                if let until = suppressUserCenteringUntil, until > Date() {
                    print("⛔️ [MapView] CenterMapOnUser ignored during suppression window")
                    return
                }
                centerOnUserLocation()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowLocationOnMap"))) { notification in
                print("🔔 [MapView] ShowLocationOnMap notification received!")
                print("   ⚠️ THIS NOTIFICATION SHOULD HAVE POST DATA!")
                
                // Show a specific coordinate on the map (from long-press on post)
                guard let userInfo = notification.userInfo else {
                    print("❌ [MapView] ShowLocationOnMap: Missing userInfo")
                    return
                }

                var target: CLLocationCoordinate2D? = nil
                var sourceKeyUsed: String = "(none)"
                if let tc = userInfo["targetCoordinate"] as? CLLocationCoordinate2D {
                    target = tc
                    sourceKeyUsed = "targetCoordinate (CLLocationCoordinate2D)"
                } else if let coord = userInfo["coordinate"] as? CLLocationCoordinate2D {
                    target = coord
                    sourceKeyUsed = "coordinate (CLLocationCoordinate2D)"
                } else if let lat = userInfo["latitude"] as? Double, let lon = userInfo["longitude"] as? Double {
                    target = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    sourceKeyUsed = "latitude/longitude (Double)"
                }

                guard let coordinate = target else {
                    print("❌ [MapView] ShowLocationOnMap: No usable coordinate (targetCoordinate/coordinate or latitude/longitude)")
                    return
                }
                
                // ✅ Extract radius, username, and location information
                let postRadius = userInfo["radius"] as? Double
                let postUsername = userInfo["username"] as? String
                let cityName = userInfo["cityName"] as? String
                let countryName = userInfo["countryName"] as? String
                let countryFlag = userInfo["countryFlag"] as? String

                print("✅ [MapView] ShowLocationOnMap: Using key -> \(sourceKeyUsed)")
                print("📍 [MapView] Received ShowLocationOnMap notification")
                print("   Target coordinate: \(coordinate.latitude), \(coordinate.longitude)")
                if let radius = postRadius {
                    print("   Radius: \(Int(radius))m")
                }
                if let username = postUsername {
                    print("   Username: \(username)")
                }
                if let city = cityName, let country = countryName {
                    print("   Location: \(countryFlag ?? "") \(city), \(country)")
                }
                print("   Current camera: \(camera.camera?.centerCoordinate.latitude ?? 0), \(camera.camera?.centerCoordinate.longitude ?? 0)")
                print("   Tour active: \(mapState.isInTourMode)")

                // ALSO store in MapStateManager for when tab switches
                print("💾 [MapView] ALSO storing in MapStateManager.pending for tab switch")
                mapState.setPendingPostLocation(
                    coordinate,
                    userID: nil,
                    username: postUsername,
                    profileImageURL: nil,
                    radius: postRadius,
                    cityName: cityName,
                    countryName: countryName,
                    countryFlag: countryFlag
                )

                // FIRST: Set locks BEFORE doing anything else
                // This ensures no other operation can interfere
                suppressUserCenteringUntil = Date().addingTimeInterval(15)
                lockToPostUntil = Date().addingTimeInterval(15)
                hasSetInitialLocation = true
                
                print("🔒 [MapView] Set 15-second lock/suppression windows IMMEDIATELY")
                print("   Lock expires at: \(lockToPostUntil!)")
                print("   Suppression expires at: \(suppressUserCenteringUntil!)")

                // Stop any active tour or operation
                mapState.stopTour()

                // CRITICAL: Set shownPostCoordinate FIRST before doing anything else
                // This ensures navigateWithTourTransition knows we're showing a post location
                shownPostCoordinate = coordinate
                shownPostRadius = postRadius
                shownPostUsername = postUsername
                shownPostCityName = cityName
                shownPostCountryName = countryName
                shownPostCountryFlag = countryFlag
                
                print("💾 [MapView] Stored post location state IN MapView:")
                print("   shownPostCoordinate: \(String(describing: shownPostCoordinate))")
                print("   shownPostRadius: \(String(describing: shownPostRadius))")
                print("   shownPostUsername: \(String(describing: shownPostUsername))")
                print("   shownPostCityName: \(String(describing: shownPostCityName))")
                print("   shownPostCountryName: \(String(describing: shownPostCountryName))")
                print("   shownPostCountryFlag: \(String(describing: shownPostCountryFlag))")
                
                // Force view update by touching a dummy state variable
                // This ensures SwiftUI re-evaluates the Map body
                self.radiusMeters = self.radiusMeters

                // Enter "showing post location" mode - this prevents auto-centering on user
                mapState.showPostLocation(coordinate)

                // Format coordinates
                let latStr = String(format: "%.4f", coordinate.latitude)
                let lonStr = String(format: "%.4f", coordinate.longitude)
                
                // Build currentCity with all available info
                var cityComponents: [String] = []
                if let username = postUsername {
                    cityComponents.append(username)
                }
                cityComponents.append("\(latStr), \(lonStr)")
                if let flag = countryFlag, let city = cityName {
                    cityComponents.append("\(flag) \(city)")
                } else if let city = cityName {
                    cityComponents.append(city)
                }
                
                currentCity = cityComponents.joined(separator: " • ")
                
                // Build aiRecommendation with radius info if available
                if let radius = postRadius {
                    let radiusText = radius >= 1000 
                        ? String(format: "%.1f km", radius / 1000) 
                        : String(format: "%.0f m", radius)
                    aiRecommendation = "Post radius: \(radiusText)"
                } else {
                    aiRecommendation = "Viewing post location"
                }
                
                print("✅ [MapView] Set comprehensive UI text:")
                print("   currentCity: '\(currentCity)'")
                print("   aiRecommendation: '\(aiRecommendation)'")

                // DON'T snap camera or call navigateWithTourTransition yet
                // Instead, use a small delay to ensure SwiftUI has processed the state changes
                print("⏱️ [MapView] Waiting 100ms for SwiftUI to process state changes...")
                
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                    
                    print("🎬 [MapView] Now starting navigation animation")
                    print("   Current shownPostCoordinate: \(String(describing: shownPostCoordinate))")
                    print("   Current currentCity: '\(currentCity)'")
                    
                    // Immediately snap camera to target
                    withAnimation(.none) {
                        camera = .camera(
                            MapCamera(
                                centerCoordinate: coordinate,
                                distance: fixedDistanceAlt,
                                heading: 0,
                                pitch: fixedPitchAlt
                            )
                        )
                    }
                    
                    print("📸 [MapView] Camera snapped to target coordinate")

                    // Use the tour-style transition for smooth navigation with radius
                    // This should NOT override the UI text because shownPostCoordinate is now set
                    navigateWithTourTransition(to: coordinate, cityName: "Post Location", postRadius: postRadius)
                    
                    print("✅ [MapView] Navigation transition started")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SetCameraCoordinate"))) { notification in
                guard let userInfo = notification.userInfo,
                      let lat = userInfo["latitude"] as? Double,
                      let lon = userInfo["longitude"] as? Double else {
                    print("❌ [MapView] SetCameraCoordinate: Missing latitude/longitude in userInfo")
                    return
                }
                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                print("📍 [MapView] Received SetCameraCoordinate: \(lat), \(lon)")

                // Stop any active tour or operation
                mapState.stopTour()

                // Enter showing post location mode
                mapState.showPostLocation(coordinate)

                // Update UI and navigate
                self.currentCity = "Post Location"
                self.aiRecommendation = "📍 Navigating to post location..."
                self.navigateWithTourTransition(to: coordinate, cityName: "Post Location")

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 7_000_000_000)
                    self.aiRecommendation = "📍 This is where the post was created!"
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenMapToSelectPostLocation"))) { notification in
                // Enter post placement mode when user wants to select location for captured media
                guard let userInfo = notification.userInfo else { return }
                
                let image = userInfo["image"] as? UIImage
                let videoURL = userInfo["videoURL"] as? URL
                
                // Start Camera -> Map flow
                flowManager.startCameraToMapFlow(image: image, videoURL: videoURL)
                
                // Show UI prompts
                currentCity = "Select Post Location"
                aiRecommendation = "Tap where you want to post your capture"
                
                print("[MapView] Entered Camera -> Map flow mode")
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CaptureComplete"))) { notification in
                // Handle when a capture completes in camera tab
                guard let userInfo = notification.userInfo else { return }
                
                // Check if we're in Map -> Camera flow
                if let flow = flowManager.currentFlow, flow.isMapFirst, 
                   let coordinate = flow.preselectedCoordinate {
                    // Flow 1: Map -> Camera -> Auto-post to preselected coordinate
                    print("📍 [MapView] Capture complete in Map -> Camera flow, uploading to preselected coordinate")
                    
                    let image = userInfo["image"] as? UIImage
                    let videoURL = userInfo["videoURL"] as? URL
                    
                    // Store the captured media in flow manager
                    flowManager.capturedImage = image
                    flowManager.capturedVideoURL = videoURL
                    
                    // Complete the flow automatically
                    flowManager.completeFlow(finalCoordinate: coordinate)
                    
                    // Show success message
                    currentCity = "Post Uploaded"
                    aiRecommendation = "Your post has been shared at the selected location!"
                }
            }
            .task {
                await runTourLoop()
            }
    }
    
    // MARK: - Sheet Views
    
    @ViewBuilder
    private var placesListSheet: some View {
        PlacesListView(places: tourPlaces) { place in
            showPlacesList = false
            panTo(place.coordinate)
        }
        .presentationDetents([.medium, .large])
    }
    
    @ViewBuilder
    private var addressSearchSheet: some View {
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
    
    // MARK: - Event Handlers
    
    private func handleOnAppear() {
        print("👀 [MapView] handleOnAppear called")
        print("   lockToPostUntil: \(lockToPostUntil?.description ?? "nil")")
        print("   mapState.mode: \(mapState.mode)")
        print("   pendingPostLocation: \(mapState.pendingPostLocation?.latitude ?? 0), \(mapState.pendingPostLocation?.longitude ?? 0)")
        
        // Check if there's a pending post location to navigate to
        if let pendingCoordinate = mapState.pendingPostLocation {
            print("✨ [MapView] Found pending post location - navigating to it!")
            
            // Set locks FIRST
            suppressUserCenteringUntil = Date().addingTimeInterval(15)
            lockToPostUntil = Date().addingTimeInterval(15)
            hasSetInitialLocation = true
            
            print("🔒 [MapView] Set 15-second locks for pending navigation")
            
            // Enter showing post location mode
            mapState.showPostLocation(pendingCoordinate)
            
            // Update UI with comprehensive location info
            let latStr = String(format: "%.4f", pendingCoordinate.latitude)
            let lonStr = String(format: "%.4f", pendingCoordinate.longitude)
            
            var cityComponents: [String] = []
            if let username = mapState.pendingPostUsername {
                cityComponents.append(username)
            }
            cityComponents.append("\(latStr), \(lonStr)")
            if let flag = mapState.pendingPostCountryFlag, let city = mapState.pendingPostCityName {
                cityComponents.append("\(flag) \(city)")
            } else if let city = mapState.pendingPostCityName {
                cityComponents.append(city)
            }
            
            currentCity = cityComponents.joined(separator: " • ")
            
            if let radius = mapState.pendingPostRadius {
                let radiusText = radius >= 1000 
                    ? String(format: "%.1f km", radius / 1000) 
                    : String(format: "%.0f m", radius)
                aiRecommendation = "Post radius: \(radiusText)"
            } else {
                aiRecommendation = "Viewing post location"
            }
            
            // Snap to coordinate immediately
            withAnimation(.none) {
                camera = .camera(
                    MapCamera(
                        centerCoordinate: pendingCoordinate,
                        distance: fixedDistanceAlt,
                        heading: 0,
                        pitch: fixedPitchAlt
                    )
                )
            }
            
            print("📸 [MapView] Camera snapped to pending coordinate")
            
            // Start tour-style transition
            navigateWithTourTransition(to: pendingCoordinate, cityName: "Post Location")
            
            // Clear pending location
            mapState.clearPendingPostLocation()
            
            return
        }
        
        // Respect the lock - don't reset camera when navigating to a post location
        if let until = lockToPostUntil, until > Date() {
            let remaining = until.timeIntervalSince(Date())
            print("⛔️ [MapView] handleOnAppear ignored during lockToPost window (remaining: \(String(format: "%.1f", remaining))s)")
            return
        }
        
        // Also don't reset if we're showing a post location (even if lock has expired)
        if case .showingPostLocation = mapState.mode {
            print("⛔️ [MapView] handleOnAppear ignored - currently showing post location")
            return
        }
        
        print("✅ [MapView] handleOnAppear proceeding - no locks active")
        
        locationManager.request()
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
    
    private func handleLocationChange(_ newLocation: CLLocation?) {
        // If we're locked to a post, ignore location changes entirely
        if let until = lockToPostUntil, until > Date() {
            let remaining = until.timeIntervalSince(Date())
            print("⛔️ [MapView] handleLocationChange ignored during lockToPost window (remaining: \(String(format: "%.1f", remaining))s)")
            return
        }
        
        // Only update camera on first location - don't interfere with tour
        guard !hasSetInitialLocation, let _ = newLocation else { 
            if hasSetInitialLocation {
                print("⏭️ [MapView] handleLocationChange skipped - initial location already set")
            }
            return 
        }
        
        print("📍 [MapView] handleLocationChange - setting initial location")
        hasSetInitialLocation = true
        
        if let newCameraPosition = locationManager.getCenteredCamera() {
            print("   Moving camera to user location: \(newLocation?.coordinate.latitude ?? 0), \(newLocation?.coordinate.longitude ?? 0)")
            camera = newCameraPosition
        }
    }
    
    private func runTourLoop() async {
        // Note initial user interaction - this starts the idle timer internally
        await MainActor.run {
            mapState.noteUserInteraction()
        }
        
        // Tour loop - alternates between zoom out (3s) and zoom in (12s at location)
        while !Task.isCancelled {
            if mapState.isInTourMode {
                // Initialize tour if just started
                if currentTourIndex == 0 && !isZoomedOut {
                    currentTourIndex = 0
                    isZoomedOut = false
                    // Brief delay before first transition
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                
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
                // If tour is not active, wait a bit before checking again
                try? await Task.sleep(nanoseconds: 1_000_000_000)
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




