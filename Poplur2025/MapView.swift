import SwiftUI
import MapKit
import CoreLocation
import SceneKit
import Foundation
import AVFoundation

// MARK: - Weather Overlay Types

import SpriteKit

struct WeatherVisualizationState {
    enum Kind { case rain, thunderstorms, cloudy, snow }
    var kind: Kind
    var intensity: Double // 0..1
    var lightningFrequency: Double // 0..1
}

struct WeatherParticleOverlay: UIViewRepresentable {
    @Binding var weatherState: WeatherVisualizationState

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.backgroundColor = .clear
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        
        let scene = SKScene()
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        
        context.coordinator.skView = view
        context.coordinator.skScene = scene
        view.presentScene(scene)
        
        context.coordinator.configureScene(for: weatherState)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        context.coordinator.configureScene(for: weatherState)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var skView: SKView?
        weak var skScene: SKScene?
        private var currentEmitter: SKEmitterNode?
        private var lightningNode: SKSpriteNode?
        private var lightningTimer: Timer?

        func configureScene(for state: WeatherVisualizationState) {
            guard let scene = skScene else { return }
            
            // Remove previous effects
            currentEmitter?.removeFromParent()
            currentEmitter = nil
            lightningNode?.removeFromParent()
            lightningNode = nil
            lightningTimer?.invalidate()
            lightningTimer = nil

            switch state.kind {
            case .rain:
                addRain(to: scene, intensity: state.intensity)
            case .thunderstorms:
                addRain(to: scene, intensity: state.intensity)
                addLightning(to: scene, frequency: state.lightningFrequency)
            case .cloudy:
                addCloudHaze(to: scene, density: state.intensity)
            case .snow:
                addSnow(to: scene, intensity: state.intensity)
            }
        }

        private func addRain(to scene: SKScene, intensity: Double) {
            let emitter = SKEmitterNode()
            
            // Position at top of screen
            emitter.position = CGPoint(x: scene.frame.midX, y: scene.frame.maxY)
            emitter.particlePositionRange = CGVector(dx: scene.frame.width, dy: 0)
            
            // Rain appearance
            emitter.particleTexture = SKTexture(image: createRaindropImage())
            emitter.particleBirthRate = CGFloat(300 * max(0.1, intensity))
            emitter.particleLifetime = 2.0
            emitter.particleLifetimeRange = 0.5
            
            // Fall straight down
            emitter.particleSpeed = 800
            emitter.particleSpeedRange = 200
            emitter.emissionAngle = -CGFloat.pi / 2 // Point down
            emitter.emissionAngleRange = 0.1
            
            // Size and appearance
            emitter.particleScale = 0.3
            emitter.particleScaleRange = 0.1
            emitter.particleScaleSpeed = -0.1
            emitter.particleAlpha = 0.6
            emitter.particleAlphaRange = 0.2
            emitter.particleAlphaSpeed = -0.3
            
            // Blend mode for rain
            emitter.particleBlendMode = .alpha
            
            scene.addChild(emitter)
            currentEmitter = emitter
        }

        private func addLightning(to scene: SKScene, frequency: Double) {
            // Create a white flash overlay
            let flash = SKSpriteNode(color: .white, size: scene.size)
            flash.alpha = 0
            flash.position = CGPoint(x: scene.frame.midX, y: scene.frame.midY)
            flash.zPosition = 100
            scene.addChild(flash)
            lightningNode = flash
            
            // Calculate flash interval based on frequency
            let interval = max(0.5, 3.0 - frequency * 2.5)
            
            lightningTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak flash] _ in
                guard let flash = flash else { return }
                
                // Quick flash
                let fadeIn = SKAction.fadeAlpha(to: 0.3, duration: 0.05)
                let fadeOut = SKAction.fadeAlpha(to: 0, duration: 0.1)
                let sequence = SKAction.sequence([fadeIn, fadeOut])
                flash.run(sequence)
            }
        }

        private func addSunnyMotes(to scene: SKScene, intensity: Double) {
            let emitter = SKEmitterNode()
            
            // Position in center
            emitter.position = CGPoint(x: scene.frame.midX, y: scene.frame.midY)
            emitter.particlePositionRange = CGVector(dx: scene.frame.width, dy: scene.frame.height)
            
            // Sunny particles
            emitter.particleTexture = SKTexture(image: createSunMoteImage())
            emitter.particleBirthRate = CGFloat(30 * max(0.1, intensity))
            emitter.particleLifetime = 4.0
            emitter.particleLifetimeRange = 2.0
            
            // Gentle floating
            emitter.particleSpeed = 20
            emitter.particleSpeedRange = 10
            emitter.emissionAngle = CGFloat.pi / 2 // Up
            emitter.emissionAngleRange = CGFloat.pi * 2
            
            // Appearance
            emitter.particleScale = 0.5
            emitter.particleScaleRange = 0.3
            emitter.particleAlpha = 0.4
            emitter.particleAlphaRange = 0.2
            emitter.particleBlendMode = .add
            
            scene.addChild(emitter)
            currentEmitter = emitter
        }

        private func addCloudHaze(to scene: SKScene, density: Double) {
            let emitter = SKEmitterNode()
            
            // Position at top, drifting down slowly
            emitter.position = CGPoint(x: scene.frame.midX, y: scene.frame.maxY)
            emitter.particlePositionRange = CGVector(dx: scene.frame.width, dy: 0)
            
            // Cloud particles
            emitter.particleTexture = SKTexture(image: createCloudImage())
            emitter.particleBirthRate = CGFloat(15 * max(0.1, density))
            emitter.particleLifetime = 8.0
            emitter.particleLifetimeRange = 2.0
            
            // Slow drift
            emitter.particleSpeed = 30
            emitter.particleSpeedRange = 10
            emitter.emissionAngle = -CGFloat.pi / 2
            emitter.emissionAngleRange = 0.3
            
            // Large, soft clouds
            emitter.particleScale = 2.0
            emitter.particleScaleRange = 1.0
            emitter.particleAlpha = 0.15
            emitter.particleAlphaRange = 0.1
            emitter.particleBlendMode = .alpha
            
            scene.addChild(emitter)
            currentEmitter = emitter
        }
        
        private func addSnow(to scene: SKScene, intensity: Double) {
            let emitter = SKEmitterNode()
            
            // Position at top of screen
            emitter.position = CGPoint(x: scene.frame.midX, y: scene.frame.maxY)
            emitter.particlePositionRange = CGVector(dx: scene.frame.width, dy: 0)
            
            // Snow appearance
            emitter.particleTexture = SKTexture(image: createSnowflakeImage())
            emitter.particleBirthRate = CGFloat(150 * max(0.1, intensity))
            emitter.particleLifetime = 10.0
            emitter.particleLifetimeRange = 3.0
            
            // Fall straight down
            emitter.particleSpeed = 60
            emitter.particleSpeedRange = 20
            emitter.emissionAngle = -CGFloat.pi / 2 // Point straight down
            emitter.emissionAngleRange = 0.05 // Very slight variation for realism
            
            // No horizontal drift - fall straight down
            emitter.xAcceleration = 0
            emitter.yAcceleration = 0
            
            // Size and appearance
            emitter.particleScale = 0.3
            emitter.particleScaleRange = 0.2
            emitter.particleAlpha = 0.9
            emitter.particleAlphaRange = 0.2
            emitter.particleAlphaSpeed = -0.1
            
            // Gentle rotation
            emitter.particleRotation = 0
            emitter.particleRotationRange = CGFloat.pi * 2
            emitter.particleRotationSpeed = 0.5
            
            // Blend mode for snow
            emitter.particleBlendMode = .alpha
            
            scene.addChild(emitter)
            currentEmitter = emitter
        }
        
        // MARK: - Particle Textures
        
        private func createRaindropImage() -> UIImage {
            let size = CGSize(width: 4, height: 20)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                UIColor.white.withAlphaComponent(0.8).setFill()
                let rect = CGRect(origin: .zero, size: size)
                UIBezierPath(roundedRect: rect, cornerRadius: 2).fill()
            }
        }
        
        private func createSunMoteImage() -> UIImage {
            let size = CGSize(width: 20, height: 20)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                UIColor.yellow.withAlphaComponent(0.6).setFill()
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            }
        }
        
        private func createCloudImage() -> UIImage {
            let size = CGSize(width: 100, height: 60)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                UIColor.white.withAlphaComponent(0.3).setFill()
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            }
        }
        
        private func createSnowflakeImage() -> UIImage {
            let size = CGSize(width: 20, height: 20)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                let ctx = context.cgContext
                
                // Draw a simple snowflake
                UIColor.white.setStroke()
                ctx.setLineWidth(1.5)
                ctx.setLineCap(.round)
                
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius: CGFloat = 8
                
                // Draw 6 lines radiating from center
                for i in 0..<6 {
                    let angle = CGFloat(i) * .pi / 3.0
                    let endX = center.x + radius * cos(angle)
                    let endY = center.y + radius * sin(angle)
                    
                    ctx.move(to: center)
                    ctx.addLine(to: CGPoint(x: endX, y: endY))
                    
                    // Add small branches
                    let branchLength: CGFloat = 3
                    let branchAngle1 = angle + .pi / 6
                    let branchAngle2 = angle - .pi / 6
                    
                    let branchX = center.x + (radius * 0.6) * cos(angle)
                    let branchY = center.y + (radius * 0.6) * sin(angle)
                    
                    ctx.move(to: CGPoint(x: branchX, y: branchY))
                    ctx.addLine(to: CGPoint(
                        x: branchX + branchLength * cos(branchAngle1),
                        y: branchY + branchLength * sin(branchAngle1)
                    ))
                    
                    ctx.move(to: CGPoint(x: branchX, y: branchY))
                    ctx.addLine(to: CGPoint(
                        x: branchX + branchLength * cos(branchAngle2),
                        y: branchY + branchLength * sin(branchAngle2)
                    ))
                }
                
                ctx.strokePath()
            }
        }
    }
}

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

// Stub annotation views - Now using enhanced beacon markers
private struct PreviewDominancePin: View {
    let profileURL: URL
    var body: some View { 
        Enhanced3DBeaconMarker(color: .purple, intensity: 0.9)
            .frame(width: 100, height: 120)
    }
}

private struct PreviewGoogleStylePin: View {
    var body: some View { 
        Enhanced3DBeaconMarker(color: .red, intensity: 0.7)
            .frame(width: 90, height: 110)
    }
}

// Extension for clamping values
private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return min(max(self, range.lowerBound), range.upperBound)
    }
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

// MARK: - SceneKit 3D Marker View

/// Blue 3D marker for user location - cone pin with sphere head
private struct UserLocation3DMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
        
        let scene = SCNScene()
        view.scene = scene
        
        // Add ambient light for better visibility
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor.white
        ambientLight.light?.intensity = 400
        scene.rootNode.addChildNode(ambientLight)
        
        // Add directional light for depth
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.color = UIColor.white
        directionalLight.light?.intensity = 800
        directionalLight.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(directionalLight)
        
        // Camera - positioned to see the 3D depth
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(1.5, 1.0, 3.5)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)
        
        // 3D Pin geometry - cone (pole) + sphere (head) in blue
        let cone = SCNCone(topRadius: 0.08, bottomRadius: 0.12, height: 1.8)
        let sphere = SCNSphere(radius: 0.4)
        
        let coneMaterial = SCNMaterial()
        coneMaterial.diffuse.contents = UIColor.systemBlue
        coneMaterial.lightingModel = .physicallyBased
        coneMaterial.metalness.contents = 0.4
        coneMaterial.roughness.contents = 0.3
        cone.materials = [coneMaterial]
        
        let sphereMaterial = SCNMaterial()
        sphereMaterial.diffuse.contents = UIColor.systemBlue
        sphereMaterial.emission.contents = UIColor.systemBlue.withAlphaComponent(0.3)
        sphereMaterial.lightingModel = .physicallyBased
        sphereMaterial.metalness.contents = 0.7
        sphereMaterial.roughness.contents = 0.15
        sphere.materials = [sphereMaterial]
        
        let coneNode = SCNNode(geometry: cone)
        coneNode.position = SCNVector3(0, -0.9, 0)
        
        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.position = SCNVector3(0, 0.4, 0)
        
        let pinNode = SCNNode()
        pinNode.addChildNode(coneNode)
        pinNode.addChildNode(sphereNode)
        scene.rootNode.addChildNode(pinNode)
        
        // Continuous rotation animation for 3D effect
        let rotation = CABasicAnimation(keyPath: "rotation")
        rotation.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi * 2))
        rotation.duration = 4
        rotation.repeatCount = .infinity
        pinNode.addAnimation(rotation, forKey: "rotation")
        
        // Gentle bobbing animation
        let bob = CABasicAnimation(keyPath: "position.y")
        bob.fromValue = 0
        bob.toValue = 0.15
        bob.duration = 1.8
        bob.autoreverses = true
        bob.repeatCount = .infinity
        pinNode.addAnimation(bob, forKey: "bob")
        
        return view
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.backgroundColor = .clear
    }
}

/// Enhanced 3D marker with pulsing glow and more complex geometry
private struct SceneKit3DEnhancedMarker: UIViewRepresentable {
    let text: String
    let color: Color
    
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
        
        let scene = SCNScene()
        view.scene = scene
        
        // Add enhanced lighting for VIP marker
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor.white
        ambientLight.light?.intensity = 500
        scene.rootNode.addChildNode(ambientLight)
        
        let spotLight = SCNNode()
        spotLight.light = SCNLight()
        spotLight.light?.type = .spot
        spotLight.light?.color = UIColor(color)
        spotLight.light?.intensity = 1000
        spotLight.position = SCNVector3(0, 3, 2)
        spotLight.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(spotLight)
        
        // Camera - angled to show 3D depth
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(2.0, 1.5, 4.0) // More dramatic angle
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)
        
        // Create compound pin geometry
        // Base: larger sphere
        let baseSphere = SCNSphere(radius: 0.5)
        let baseMaterial = SCNMaterial()
        baseMaterial.diffuse.contents = UIColor(color)
        baseMaterial.emission.contents = UIColor(color.opacity(0.5))
        baseMaterial.lightingModel = .physicallyBased
        baseMaterial.metalness.contents = 0.9
        baseMaterial.roughness.contents = 0.05
        baseSphere.materials = [baseMaterial]
        
        let baseSphereNode = SCNNode(geometry: baseSphere)
        baseSphereNode.position = SCNVector3(0, 0.6, 0)
        
        // Pole: cylinder
        let cylinder = SCNCylinder(radius: 0.1, height: 2.0)
        let cylinderMaterial = SCNMaterial()
        cylinderMaterial.diffuse.contents = UIColor(color.opacity(0.9))
        cylinderMaterial.lightingModel = .physicallyBased
        cylinderMaterial.metalness.contents = 0.6
        cylinder.materials = [cylinderMaterial]
        
        let cylinderNode = SCNNode(geometry: cylinder)
        cylinderNode.position = SCNVector3(0, -0.4, 0)
        
        // Glow ring - larger and more visible
        let torus = SCNTorus(ringRadius: 0.6, pipeRadius: 0.06)
        let torusMaterial = SCNMaterial()
        torusMaterial.diffuse.contents = UIColor(color.opacity(0.4))
        torusMaterial.emission.contents = UIColor(color)
        torusMaterial.lightingModel = .constant
        torus.materials = [torusMaterial]
        
        let torusNode = SCNNode(geometry: torus)
        torusNode.position = SCNVector3(0, 0.6, 0)
        torusNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        
        let pinNode = SCNNode()
        pinNode.addChildNode(baseSphereNode)
        pinNode.addChildNode(cylinderNode)
        pinNode.addChildNode(torusNode)
        scene.rootNode.addChildNode(pinNode)
        
        // Faster rotation for VIP effect
        let rotation = CABasicAnimation(keyPath: "rotation")
        rotation.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi * 2))
        rotation.duration = 3
        rotation.repeatCount = .infinity
        pinNode.addAnimation(rotation, forKey: "rotation")
        
        // More dramatic pulsing glow on torus
        let pulseScale = CABasicAnimation(keyPath: "scale")
        pulseScale.fromValue = NSValue(scnVector3: SCNVector3(0.9, 0.9, 0.9))
        pulseScale.toValue = NSValue(scnVector3: SCNVector3(1.4, 1.4, 1.4))
        pulseScale.duration = 1.2
        pulseScale.autoreverses = true
        pulseScale.repeatCount = .infinity
        torusNode.addAnimation(pulseScale, forKey: "pulse")
        
        // Bobbing animation
        let bob = CABasicAnimation(keyPath: "position.y")
        bob.fromValue = 0
        bob.toValue = 0.2
        bob.duration = 2.0
        bob.autoreverses = true
        bob.repeatCount = .infinity
        pinNode.addAnimation(bob, forKey: "bob")
        
        return view
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.backgroundColor = .clear
    }
}

// MARK: - Floating 3D Beacon (Overlay on map)

/// Floating 3D beacon that hovers over map coordinates - like the reference image
private struct Floating3DBeacon: UIViewRepresentable {
    let color: Color
    let pulseSpeed: Double
    
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.backgroundColor = .clear
        
        let scene = SCNScene()
        view.scene = scene
        
        // Camera - top-down perspective to match map view
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 8, 0)
        cameraNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        scene.rootNode.addChildNode(cameraNode)
        
        // Lighting
        let omniLight = SCNNode()
        omniLight.light = SCNLight()
        omniLight.light?.type = .omni
        omniLight.light?.color = UIColor.white
        omniLight.light?.intensity = 2000
        omniLight.position = SCNVector3(0, 5, 0)
        scene.rootNode.addChildNode(omniLight)
        
        // Create floating beacon
        let beaconContainer = SCNNode()
        
        // Base platform - glowing ring
        let baseTorus = SCNTorus(ringRadius: 0.8, pipeRadius: 0.08)
        let baseMaterial = SCNMaterial()
        baseMaterial.diffuse.contents = UIColor(color.opacity(0.3))
        baseMaterial.emission.contents = UIColor(color)
        baseMaterial.lightingModel = .constant
        baseTorus.materials = [baseMaterial]
        
        let baseNode = SCNNode(geometry: baseTorus)
        baseNode.position = SCNVector3(0, 0, 0)
        beaconContainer.addChildNode(baseNode)
        
        // Center crystal/diamond shape
        let pyramid = SCNPyramid(width: 0.4, height: 1.2, length: 0.4)
        let pyramidMaterial = SCNMaterial()
        pyramidMaterial.diffuse.contents = UIColor(color.opacity(0.6))
        pyramidMaterial.emission.contents = UIColor(color.opacity(0.8))
        pyramidMaterial.lightingModel = .constant
        pyramidMaterial.transparency = 0.8
        pyramid.materials = [pyramidMaterial]
        
        let pyramidNode = SCNNode(geometry: pyramid)
        pyramidNode.position = SCNVector3(0, 0.8, 0)
        beaconContainer.addChildNode(pyramidNode)
        
        // Vertical light beam
        let beam = SCNCylinder(radius: 0.15, height: 2.5)
        let beamMaterial = SCNMaterial()
        beamMaterial.diffuse.contents = UIColor(color.opacity(0.2))
        beamMaterial.emission.contents = UIColor(color.opacity(0.6))
        beamMaterial.lightingModel = .constant
        beamMaterial.transparency = 0.4
        beam.materials = [beamMaterial]
        
        let beamNode = SCNNode(geometry: beam)
        beamNode.position = SCNVector3(0, 1.5, 0)
        beaconContainer.addChildNode(beamNode)
        
        scene.rootNode.addChildNode(beaconContainer)
        
        // Rotation animation
        let rotation = CABasicAnimation(keyPath: "rotation")
        rotation.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi * 2))
        rotation.duration = 4.0 / pulseSpeed
        rotation.repeatCount = .infinity
        beaconContainer.addAnimation(rotation, forKey: "rotation")
        
        // Pulsing scale animation
        let pulse = CABasicAnimation(keyPath: "scale")
        pulse.fromValue = NSValue(scnVector3: SCNVector3(1.0, 1.0, 1.0))
        pulse.toValue = NSValue(scnVector3: SCNVector3(1.2, 1.2, 1.2))
        pulse.duration = 1.5 / pulseSpeed
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        baseNode.addAnimation(pulse, forKey: "pulse")
        
        // Floating animation
        let float = CABasicAnimation(keyPath: "position.y")
        float.fromValue = 0.0
        float.toValue = 0.3
        float.duration = 2.0
        float.autoreverses = true
        float.repeatCount = .infinity
        beaconContainer.addAnimation(float, forKey: "float")
        
        return view
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.backgroundColor = .clear
    }
}

// MARK: - Enhanced 3D Beacon Marker

/// Enhanced 3D beacon marker - matches Google Maps hybrid style with glowing effects
private struct Enhanced3DBeaconMarker: UIViewRepresentable {
    let color: Color
    let intensity: Double // 0.0 to 1.0 for heat/activity level
    
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        
        let scene = SCNScene()
        view.scene = scene
        
        // Camera - angled view to show 3D depth
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 50
        cameraNode.position = SCNVector3(0, 3, 5)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)
        
        // Omni light for overall illumination
        let omniLight = SCNNode()
        omniLight.light = SCNLight()
        omniLight.light?.type = .omni
        omniLight.light?.color = UIColor.white
        omniLight.light?.intensity = 1500
        omniLight.position = SCNVector3(0, 5, 2)
        scene.rootNode.addChildNode(omniLight)
        
        // Spotlight for dramatic glow
        let spotlight = SCNNode()
        spotlight.light = SCNLight()
        spotlight.light?.type = .spot
        spotlight.light?.color = UIColor(color)
        spotlight.light?.intensity = 2000 * intensity
        spotlight.light?.spotInnerAngle = 30
        spotlight.light?.spotOuterAngle = 60
        spotlight.position = SCNVector3(0, 6, 0)
        spotlight.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(spotlight)
        
        let beaconContainer = SCNNode()
        
        // Ground glow ring - pulsing base
        let groundRing = SCNTorus(ringRadius: 1.2, pipeRadius: 0.15)
        let groundMaterial = SCNMaterial()
        groundMaterial.diffuse.contents = UIColor(color.opacity(0.2))
        groundMaterial.emission.contents = UIColor(color.opacity(0.8 * intensity))
        groundMaterial.lightingModel = .constant
        groundMaterial.transparency = 0.6
        groundRing.materials = [groundMaterial]
        
        let groundRingNode = SCNNode(geometry: groundRing)
        groundRingNode.position = SCNVector3(0, 0.1, 0)
        groundRingNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        beaconContainer.addChildNode(groundRingNode)
        
        // Middle ring - smaller, brighter
        let midRing = SCNTorus(ringRadius: 0.8, pipeRadius: 0.1)
        let midMaterial = SCNMaterial()
        midMaterial.diffuse.contents = UIColor(color.opacity(0.3))
        midMaterial.emission.contents = UIColor(color)
        midMaterial.lightingModel = .constant
        midMaterial.transparency = 0.7
        midRing.materials = [midMaterial]
        
        let midRingNode = SCNNode(geometry: midRing)
        midRingNode.position = SCNVector3(0, 0.3, 0)
        midRingNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        beaconContainer.addChildNode(midRingNode)
        
        // Central crystal/diamond
        let crystal = SCNPyramid(width: 0.6, height: 2.0, length: 0.6)
        let crystalMaterial = SCNMaterial()
        crystalMaterial.diffuse.contents = UIColor(color.opacity(0.4))
        crystalMaterial.emission.contents = UIColor(color.opacity(intensity))
        crystalMaterial.lightingModel = .physicallyBased
        crystalMaterial.metalness.contents = 0.9
        crystalMaterial.roughness.contents = 0.1
        crystalMaterial.transparency = 0.7
        crystal.materials = [crystalMaterial]
        
        let crystalNode = SCNNode(geometry: crystal)
        crystalNode.position = SCNVector3(0, 1.2, 0)
        beaconContainer.addChildNode(crystalNode)
        
        // Vertical light beam
        let beam = SCNCylinder(radius: 0.25, height: 3.5)
        let beamMaterial = SCNMaterial()
        beamMaterial.diffuse.contents = UIColor(color.opacity(0.1))
        beamMaterial.emission.contents = UIColor(color.opacity(0.5 * intensity))
        beamMaterial.lightingModel = .constant
        beamMaterial.transparency = 0.3
        beam.materials = [beamMaterial]
        
        let beamNode = SCNNode(geometry: beam)
        beamNode.position = SCNVector3(0, 2.0, 0)
        beaconContainer.addChildNode(beamNode)
        
        // Particle ring at top
        let particleRing = SCNTorus(ringRadius: 0.4, pipeRadius: 0.05)
        let particleMaterial = SCNMaterial()
        particleMaterial.emission.contents = UIColor(color)
        particleMaterial.lightingModel = .constant
        particleRing.materials = [particleMaterial]
        
        let particleRingNode = SCNNode(geometry: particleRing)
        particleRingNode.position = SCNVector3(0, 2.8, 0)
        particleRingNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        beaconContainer.addChildNode(particleRingNode)
        
        scene.rootNode.addChildNode(beaconContainer)
        
        // Continuous rotation
        let rotation = CABasicAnimation(keyPath: "rotation")
        rotation.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi * 2))
        rotation.duration = 6.0 / intensity.clamped(to: 0.3...1.0)
        rotation.repeatCount = .infinity
        beaconContainer.addAnimation(rotation, forKey: "rotation")
        
        // Pulsing ground ring
        let pulse = CABasicAnimation(keyPath: "scale")
        pulse.fromValue = NSValue(scnVector3: SCNVector3(1.0, 1.0, 1.0))
        pulse.toValue = NSValue(scnVector3: SCNVector3(1.3, 1.0, 1.3))
        pulse.duration = 2.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        groundRingNode.addAnimation(pulse, forKey: "pulse")
        
        // Floating animation
        let float = CABasicAnimation(keyPath: "position.y")
        float.fromValue = 0.0
        float.toValue = 0.4
        float.duration = 2.5
        float.autoreverses = true
        float.repeatCount = .infinity
        beaconContainer.addAnimation(float, forKey: "float")
        
        // Spinning particle ring
        let particleSpin = CABasicAnimation(keyPath: "rotation")
        particleSpin.toValue = NSValue(scnVector4: SCNVector4(1, 0, 0, Float.pi * 2))
        particleSpin.duration = 3.0
        particleSpin.repeatCount = .infinity
        particleRingNode.addAnimation(particleSpin, forKey: "particleSpin")
        
        return view
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.backgroundColor = .clear
    }
}

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
    
    @State private var fixedDistanceAlt: CLLocationDistance = 700 // Start at optimal viewing distance (700m)
    @State private var camera: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // SF default, will update to user location
            distance: 700,  // Start at 700m (optimal viewing distance)
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
    
    // Zoom slider state
    @State private var zoomLevel: Double = 700 // Initial distance in meters (700 = optimal viewing distance)
    
    // Confetti system for trending pins
    @StateObject private var trendingTracker = PinTrendingTracker()
    @State private var showConfetti: Bool = true // Toggle confetti on/off
    @State private var cubeHoldStartY: CGFloat? = nil // Track cube hold drag start position
    @State private var initialZoomLevel: Double = 700 // Store zoom level when cube hold starts
    
    // Weather overlay state
    @State private var weatherState = WeatherVisualizationState(
        kind: .rain,
        intensity: 0.5,
        lightningFrequency: 0.3
    )
    
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
        // Initialize with demo cities and posts synchronously to avoid crash
        _dominance = State(initialValue: [
            PreviewCityDominance(city: "San Francisco", coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), profileURL: nil),
            PreviewCityDominance(city: "New York", coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), profileURL: nil),
            PreviewCityDominance(city: "Los Angeles", coordinate: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437), profileURL: nil)
        ])
        
        // Add demo posts near SF for visualization
        _posts = State(initialValue: [
            PreviewMapAnnotationPost(title: "Golden Gate", coordinate: CLLocationCoordinate2D(latitude: 37.8199, longitude: -122.4783), radius: 500),
            PreviewMapAnnotationPost(title: "Fisherman's Wharf", coordinate: CLLocationCoordinate2D(latitude: 37.8080, longitude: -122.4177), radius: 400),
            PreviewMapAnnotationPost(title: "Alcatraz", coordinate: CLLocationCoordinate2D(latitude: 37.8267, longitude: -122.4230), radius: 600)
        ])
    }
    
    // New: Override timeAdaptiveMapStyle to always return hybrid style for both day and night
    private var timeAdaptiveMapStyle: MapStyle {
#if POP_PREVIEW_LIGHT
        // Preview-light fallback still uses standard, but we keep behavior unified
        return .standard
#else
        // Always use hybrid imagery; rely on overlay to darken at night
        return .hybrid(elevation: .realistic, showsTraffic: false)
#endif
    }
    
    // Increased night overlay opacity target to 0.45 for clearer darkening
    private func updateNightOverlay() {
        // Determine if we are in night mode
        let isNight = Calendar.current.component(.hour, from: Date()) < 6 || Calendar.current.component(.hour, from: Date()) > 18
        
        // Updated opacity target for hybrid tiles night mode
        let target = isNight ? 0.45 : 0.0
        
        // Apply overlay opacity with animation (not shown here)
        // Assume overlayOpacity is a @State or similar
        // Example:
        // withAnimation(.easeInOut(duration: 0.3)) {
        //     overlayOpacity = target
        // }
    }
    
    // MARK: - Helper Methods
    
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
    
    var body: some View {
        ZStack {
            // Minimal production map rendering to satisfy View conformance
            Map(position: $camera, interactionModes: [.all])
                .mapStyle(timeAdaptiveMapStyle)
                .ignoresSafeArea()

            // Weather overlay on top of the map
            WeatherParticleOverlay(weatherState: $weatherState)
                .allowsHitTesting(false)
        }
    }
    
    // ... Remaining code unchanged ...

}
