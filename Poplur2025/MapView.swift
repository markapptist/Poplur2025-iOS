import SwiftUI
import MapKit
import CoreLocation
import SceneKit
import Foundation
import AVFoundation
import AudioToolbox

// MARK: - Required Dependencies
/*
 This file requires the following project files to compile:
 - MapViewStubs.swift (MapAnnotationPost, CityDominance, DominancePin types)
 - LocationProvider.swift (LocationProvider class)
 - CaptureFlowManager.swift (CaptureFlowManager.shared)
 - MapStateManager.swift (MapStateManager.shared)
 - AnimatedZoomSlider.swift (AnimatedZoomSlider view)
 - ConfettiSystem.swift (ConfettiOverlay, PinTrendingTracker)
 - Notifications+Names.swift (Notification.Name extensions)
 
 ARCHIVE-FRIENDLY CONFIGURATION:
 This file is configured to compile cleanly in both DEBUG and RELEASE builds.
 
 DEBUG-only features (excluded from production/archive builds):
 - WeatherParticleOverlay: SpriteKit-based weather visualization
 - Weather controls overlay: Debug UI for toggling weather/confetti
 - Weather state updates and fetch methods
 - Interactive tour preview controls
 
 All core map functionality is available in both DEBUG and RELEASE builds.
 */

// MARK: - Weather Overlay Types

import SpriteKit

struct WeatherVisualizationState {
    enum Kind { case rain, thunderstorms, cloudy, snow }
    var kind: Kind
    var intensity: Double // 0..1
    var lightningFrequency: Double // 0..1
}

#if DEBUG
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
#endif // End WeatherParticleOverlay DEBUG block

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

// Notification names used in this file (available in all builds)
extension Notification.Name {
    static let preview_CenterMapOnUser = Notification.Name("Preview_CenterMapOnUser")
    static let preview_startDominanceTour = Notification.Name("Preview_startDominanceTour")
    static let preview_stopDominanceTour = Notification.Name("Preview_stopDominanceTour")
    static let preview_setTourSpeedMultiplier = Notification.Name("Preview_setTourSpeedMultiplier")
    static let preview_setTourZoomOutDistance = Notification.Name("Preview_setTourZoomOutDistance")
    static let preview_setBuildingZoomDistance = Notification.Name("Preview_SetBuildingZoomDistance")
}

#endif // End #if DEBUG block

// Extension for clamping values (available everywhere, not just DEBUG)
extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Enhanced 3D Beacon Marker (Available in all builds)

/// Enhanced 3D beacon marker - matches Google Maps hybrid style with glowing effects
struct Enhanced3DBeaconMarker: UIViewRepresentable {
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

#if DEBUG
private let IS_PREVIEW: Bool = (ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1")
#else
private let IS_PREVIEW: Bool = false
#endif

private let fixedPitchAlt: CGFloat = 60 // Changed to 60 degrees for 3D perspective

// MARK: - Android Map Feature Parity Models

private struct PoplurTourStop: Identifiable {
    var id: String { cityName }
    let cityName: String
    let storefront: String
    let coordinate: CLLocationCoordinate2D
    let bearing: CLLocationDirection
    let radiusMeters: Double
    let distance: CLLocationDistance
    let description: String
}

private struct CityMusicTrack: Hashable {
    let assetURI: String
    let artistSeed: String
}

private struct AiTourInsight: Identifiable, Equatable {
    let id: String
    let subtitle: String
    let category: TrendCategory
}

private struct TrendPopObject: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let emoji: String
    let scale: CGFloat
    let delay: Double
    let seed: Int
}

private enum TrendCategory: String, CaseIterable {
    case clothes
    case sports
    case food
    case nightlife
    case music
    case travel

    var symbolName: String {
        switch self {
        case .clothes: return "tshirt.fill"
        case .sports: return "basketball.fill"
        case .food: return "fork.knife.circle.fill"
        case .nightlife: return "sparkles"
        case .music: return "music.note"
        case .travel: return "airplane"
        }
    }

    var tint: Color {
        switch self {
        case .clothes: return Color(red: 1.0, green: 0.28, blue: 0.71)
        case .sports: return Color(red: 0.38, green: 0.92, blue: 0.48)
        case .food: return Color(red: 1.0, green: 0.72, blue: 0.22)
        case .nightlife: return Color(red: 0.62, green: 0.42, blue: 1.0)
        case .music: return Color(red: 0.32, green: 0.88, blue: 1.0)
        case .travel: return Color(red: 1.0, green: 0.39, blue: 0.35)
        }
    }

    var emojis: [String] {
        switch self {
        case .clothes: return ["👕", "👟", "🧢", "🕶️", "👜"]
        case .sports: return ["🏀", "⚽", "🏈", "⚾", "🏆"]
        case .food: return ["🍔", "🍕", "🍜", "🍣", "☕"]
        case .nightlife: return ["🪩", "🍸", "🎉", "🌃", "✨"]
        case .music: return ["🎤", "🎧", "🎸", "🎹", "🎵"]
        case .travel: return ["✈️", "🗽", "🏙️", "📍", "🌍"]
        }
    }
}

private let tourStopDwellSeconds: UInt64 = 30
private let trendPopStartDelaySeconds: UInt64 = 1
private let trendPopCountMin = 10
private let trendPopCountRange = 6
private let musicLookupTimeout: TimeInterval = 5
private let musicTopTrackChoices = 5

private let PoplurTourStops: [PoplurTourStop] = [
    PoplurTourStop(cityName: "Paris", storefront: "fr", coordinate: CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945), bearing: 28, radiusMeters: 105_000, distance: 900, description: "Eiffel Tower energy"),
    PoplurTourStop(cityName: "New York", storefront: "us", coordinate: CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857), bearing: -24, radiusMeters: 132_000, distance: 780, description: "Skyline and street posts"),
    PoplurTourStop(cityName: "Los Angeles", storefront: "us", coordinate: CLLocationCoordinate2D(latitude: 34.1016, longitude: -118.3267), bearing: 22, radiusMeters: 150_000, distance: 850, description: "Studios, murals, and sunset hills"),
    PoplurTourStop(cityName: "Chicago", storefront: "us", coordinate: CLLocationCoordinate2D(latitude: 41.8819, longitude: -87.6233), bearing: -18, radiusMeters: 120_000, distance: 820, description: "Riverwalk and late plates"),
    PoplurTourStop(cityName: "Miami", storefront: "us", coordinate: CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918), bearing: 36, radiusMeters: 95_000, distance: 850, description: "Ocean, nightlife, and art deco"),
    PoplurTourStop(cityName: "Las Vegas", storefront: "us", coordinate: CLLocationCoordinate2D(latitude: 36.1147, longitude: -115.1728), bearing: -34, radiusMeters: 115_000, distance: 850, description: "Neon strip moments"),
    PoplurTourStop(cityName: "New Orleans", storefront: "us", coordinate: CLLocationCoordinate2D(latitude: 29.9584, longitude: -90.0659), bearing: 30, radiusMeters: 90_000, distance: 900, description: "Jazz streets and food posts"),
    PoplurTourStop(cityName: "San Francisco", storefront: "us", coordinate: CLLocationCoordinate2D(latitude: 37.8199, longitude: -122.4783), bearing: 18, radiusMeters: 110_000, distance: 850, description: "Golden Gate viewpoints"),
    PoplurTourStop(cityName: "Seattle", storefront: "us", coordinate: CLLocationCoordinate2D(latitude: 47.6205, longitude: -122.3493), bearing: -28, radiusMeters: 105_000, distance: 900, description: "Coffee, mist, and skyline"),
    PoplurTourStop(cityName: "Washington DC", storefront: "us", coordinate: CLLocationCoordinate2D(latitude: 38.8977, longitude: -77.0365), bearing: 20, radiusMeters: 80_000, distance: 920, description: "Monuments and museum days"),
    PoplurTourStop(cityName: "Toronto", storefront: "ca", coordinate: CLLocationCoordinate2D(latitude: 43.6426, longitude: -79.3871), bearing: 24, radiusMeters: 84_000, distance: 850, description: "CN Tower and city sound"),
    PoplurTourStop(cityName: "Vancouver", storefront: "ca", coordinate: CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1119), bearing: -22, radiusMeters: 95_000, distance: 900, description: "Mountains and glass towers"),
    PoplurTourStop(cityName: "Montreal", storefront: "ca", coordinate: CLLocationCoordinate2D(latitude: 45.5017, longitude: -73.5673), bearing: 30, radiusMeters: 88_000, distance: 900, description: "Old city and festival posts"),
    PoplurTourStop(cityName: "Calgary", storefront: "ca", coordinate: CLLocationCoordinate2D(latitude: 51.0447, longitude: -114.0719), bearing: -18, radiusMeters: 100_000, distance: 950, description: "Prairie skyline"),
    PoplurTourStop(cityName: "Mexico City", storefront: "mx", coordinate: CLLocationCoordinate2D(latitude: 19.4326, longitude: -99.1332), bearing: 26, radiusMeters: 130_000, distance: 850, description: "Plazas, plates, and murals"),
    PoplurTourStop(cityName: "Rio de Janeiro", storefront: "br", coordinate: CLLocationCoordinate2D(latitude: -22.9519, longitude: -43.2105), bearing: -24, radiusMeters: 130_000, distance: 900, description: "Beach and mountain views"),
    PoplurTourStop(cityName: "Sao Paulo", storefront: "br", coordinate: CLLocationCoordinate2D(latitude: -23.5505, longitude: -46.6333), bearing: 34, radiusMeters: 150_000, distance: 850, description: "Megacity culture"),
    PoplurTourStop(cityName: "Tokyo", storefront: "jp", coordinate: CLLocationCoordinate2D(latitude: 35.6586, longitude: 139.7454), bearing: 34, radiusMeters: 148_000, distance: 780, description: "Crossings and tower lights"),
    PoplurTourStop(cityName: "Seoul", storefront: "kr", coordinate: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780), bearing: -20, radiusMeters: 105_000, distance: 850, description: "Street style and food alleys"),
    PoplurTourStop(cityName: "Singapore", storefront: "sg", coordinate: CLLocationCoordinate2D(latitude: 1.2834, longitude: 103.8518), bearing: 22, radiusMeters: 70_000, distance: 850, description: "Marina skyline"),
    PoplurTourStop(cityName: "Bangkok", storefront: "th", coordinate: CLLocationCoordinate2D(latitude: 13.7563, longitude: 100.5018), bearing: -30, radiusMeters: 100_000, distance: 900, description: "Markets and night lights"),
    PoplurTourStop(cityName: "Jakarta", storefront: "id", coordinate: CLLocationCoordinate2D(latitude: -6.1754, longitude: 106.8272), bearing: 28, radiusMeters: 135_000, distance: 900, description: "Urban heat and food posts"),
    PoplurTourStop(cityName: "Manila", storefront: "ph", coordinate: CLLocationCoordinate2D(latitude: 14.5995, longitude: 120.9842), bearing: -26, radiusMeters: 110_000, distance: 900, description: "Bay and street scenes"),
    PoplurTourStop(cityName: "London", storefront: "gb", coordinate: CLLocationCoordinate2D(latitude: 51.5007, longitude: -0.1246), bearing: -32, radiusMeters: 118_000, distance: 820, description: "Landmarks and radio"),
    PoplurTourStop(cityName: "Dubai", storefront: "ae", coordinate: CLLocationCoordinate2D(latitude: 25.1972, longitude: 55.2744), bearing: 18, radiusMeters: 96_000, distance: 900, description: "Towers and desert glow"),
    PoplurTourStop(cityName: "Doha", storefront: "qa", coordinate: CLLocationCoordinate2D(latitude: 25.2854, longitude: 51.5310), bearing: -24, radiusMeters: 80_000, distance: 950, description: "Corniche views"),
    PoplurTourStop(cityName: "Riyadh", storefront: "sa", coordinate: CLLocationCoordinate2D(latitude: 24.7136, longitude: 46.6753), bearing: 30, radiusMeters: 115_000, distance: 900, description: "Boulevard nights"),
    PoplurTourStop(cityName: "Istanbul", storefront: "tr", coordinate: CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784), bearing: -28, radiusMeters: 125_000, distance: 850, description: "Two-continent views"),
    PoplurTourStop(cityName: "Petra", storefront: "jo", coordinate: CLLocationCoordinate2D(latitude: 30.3285, longitude: 35.4444), bearing: 20, radiusMeters: 65_000, distance: 1_050, description: "Ancient landmark posts"),
    PoplurTourStop(cityName: "Mumbai", storefront: "in", coordinate: CLLocationCoordinate2D(latitude: 19.0760, longitude: 72.8777), bearing: 26, radiusMeters: 145_000, distance: 850, description: "Bollywood and sea links"),
    PoplurTourStop(cityName: "Delhi", storefront: "in", coordinate: CLLocationCoordinate2D(latitude: 28.6129, longitude: 77.2295), bearing: -24, radiusMeters: 155_000, distance: 850, description: "Markets and monuments"),
    PoplurTourStop(cityName: "Jaipur", storefront: "in", coordinate: CLLocationCoordinate2D(latitude: 26.9239, longitude: 75.8235), bearing: 34, radiusMeters: 95_000, distance: 950, description: "Pink city travel posts"),
    PoplurTourStop(cityName: "Bengaluru", storefront: "in", coordinate: CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946), bearing: -18, radiusMeters: 120_000, distance: 900, description: "Tech and cafe scenes"),
    PoplurTourStop(cityName: "Cairo", storefront: "eg", coordinate: CLLocationCoordinate2D(latitude: 29.9792, longitude: 31.1342), bearing: 26, radiusMeters: 120_000, distance: 1_050, description: "Pyramids and city haze"),
    PoplurTourStop(cityName: "Lagos", storefront: "ng", coordinate: CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792), bearing: -20, radiusMeters: 165_000, distance: 900, description: "Afrobeats and city life"),
    PoplurTourStop(cityName: "Nairobi", storefront: "ke", coordinate: CLLocationCoordinate2D(latitude: -1.2921, longitude: 36.8219), bearing: 30, radiusMeters: 115_000, distance: 950, description: "Skyline and safari edges"),
    PoplurTourStop(cityName: "Cape Town", storefront: "za", coordinate: CLLocationCoordinate2D(latitude: -33.9249, longitude: 18.4241), bearing: -26, radiusMeters: 105_000, distance: 950, description: "Table Mountain views"),
    PoplurTourStop(cityName: "Marrakech", storefront: "ma", coordinate: CLLocationCoordinate2D(latitude: 31.6295, longitude: -7.9811), bearing: 22, radiusMeters: 85_000, distance: 950, description: "Market color and courtyards"),
    PoplurTourStop(cityName: "Accra", storefront: "gh", coordinate: CLLocationCoordinate2D(latitude: 5.6037, longitude: -0.1869), bearing: -28, radiusMeters: 95_000, distance: 950, description: "Coastal culture"),
    PoplurTourStop(cityName: "Sydney", storefront: "au", coordinate: CLLocationCoordinate2D(latitude: -33.8568, longitude: 151.2153), bearing: -28, radiusMeters: 110_000, distance: 900, description: "Harbor icons")
]

private let FallbackCityMusicTracks: [String: CityMusicTrack] = [
    "Paris": CityMusicTrack(assetURI: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3", artistSeed: "Aya Nakamura, Daft Punk, DJ Snake"),
    "New York": CityMusicTrack(assetURI: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3", artistSeed: "Jay-Z, Cardi B, A$AP Rocky"),
    "Tokyo": CityMusicTrack(assetURI: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3", artistSeed: "YOASOBI, Hikaru Utada, Ryuichi Sakamoto"),
    "London": CityMusicTrack(assetURI: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3", artistSeed: "Dua Lipa, Stormzy, Adele"),
    "Dubai": CityMusicTrack(assetURI: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3", artistSeed: "Balqees, Hussain Al Jassmi, Wegz"),
    "Toronto": CityMusicTrack(assetURI: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3", artistSeed: "Drake, The Weeknd, PARTYNEXTDOOR"),
    "Sydney": CityMusicTrack(assetURI: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3", artistSeed: "The Kid LAROI, Sia, Flume")
]

private let DefaultFallbackCityMusicTrack = CityMusicTrack(
    assetURI: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
    artistSeed: "Global pop and rap mix"
)

private let FallbackCityRadioTracks: [String: [CityMusicTrack]] = [
    "New York": [
        CityMusicTrack(assetURI: "https://playerservices.streamtheworld.com/api/livestream-redirect/WNYCFM.mp3", artistSeed: "WNYC live radio"),
        CityMusicTrack(assetURI: "https://playerservices.streamtheworld.com/api/livestream-redirect/WQXRFM.mp3", artistSeed: "WQXR live radio")
    ],
    "Los Angeles": [CityMusicTrack(assetURI: "https://playerservices.streamtheworld.com/api/livestream-redirect/KUSCMP256.mp3", artistSeed: "KUSC live radio")],
    "Chicago": [CityMusicTrack(assetURI: "https://playerservices.streamtheworld.com/api/livestream-redirect/WBEZFM.mp3", artistSeed: "WBEZ live radio")],
    "London": [
        CityMusicTrack(assetURI: "https://stream.live.vc.bbcmedia.co.uk/bbc_radio_fourfm", artistSeed: "BBC Radio 4 live"),
        CityMusicTrack(assetURI: "https://stream.live.vc.bbcmedia.co.uk/bbc_radio_one", artistSeed: "BBC Radio 1 live")
    ],
    "Paris": [CityMusicTrack(assetURI: "https://icecast.radiofrance.fr/fip-midfi.mp3", artistSeed: "FIP live radio")],
    "Toronto": [CityMusicTrack(assetURI: "https://playerservices.streamtheworld.com/api/livestream-redirect/CBC_R1_TOR_H.mp3", artistSeed: "CBC Radio One Toronto")],
    "Sydney": [CityMusicTrack(assetURI: "https://live-radio01.mediahubaustralia.com/2TJW/mp3/", artistSeed: "triple j Sydney live")]
]

private let FallbackCitySportsRadioTracks: [String: [CityMusicTrack]] = [
    "New York": [CityMusicTrack(assetURI: "https://playerservices.streamtheworld.com/api/livestream-redirect/WFANAM.mp3", artistSeed: "WFAN Sports Radio New York")],
    "Los Angeles": [CityMusicTrack(assetURI: "https://playerservices.streamtheworld.com/api/livestream-redirect/KSPNAMAAC.aac", artistSeed: "ESPN LA live sports radio")],
    "Chicago": [CityMusicTrack(assetURI: "https://playerservices.streamtheworld.com/api/livestream-redirect/WSCRAM.mp3", artistSeed: "670 The Score Chicago")],
    "Toronto": [CityMusicTrack(assetURI: "https://playerservices.streamtheworld.com/api/livestream-redirect/CHUMAM.mp3", artistSeed: "TSN 1050 Toronto")],
    "London": [CityMusicTrack(assetURI: "https://radio.talksport.com/stream", artistSeed: "talkSPORT London")]
]

private func countryFlagEmoji(_ countryCode: String) -> String {
    let scalars = countryCode.uppercased().unicodeScalars
    guard scalars.count == 2, scalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return "" }
    return String(String.UnicodeScalarView(scalars.compactMap {
        UnicodeScalar(127397 + $0.value)
    }))
}

private func activeCityTitle(_ stop: PoplurTourStop) -> String {
    "\(stop.cityName) \(countryFlagEmoji(stop.storefront))"
}

private func spoofAiTourInsight(for stop: PoplurTourStop) -> AiTourInsight {
    let now = Int(Date().timeIntervalSince1970 * 1000)
    let sportsCities: Set<String> = ["New York", "Los Angeles", "Chicago", "Toronto", "London", "Tokyo", "Sydney", "Miami"]
    if sportsCities.contains(stop.cityName), abs(stop.cityName.hashValue + now) % 3 == 0 {
        return AiTourInsight(
            id: "\(stop.cityName)-sports-\(now)",
            subtitle: "AI: sports posts are surging here. Tuning into a live local sports radio station.",
            category: .sports
        )
    }

    let options: [AiTourInsight] = [
        AiTourInsight(id: "\(stop.cityName)-clothes-\(now)", subtitle: "AI: most posts nearby are fit checks, sneakers, and streetwear drops.", category: .clothes),
        AiTourInsight(id: "\(stop.cityName)-food-\(now)", subtitle: "AI: food posts are spiking here: late plates, cafes, and table shots.", category: .food),
        AiTourInsight(id: "\(stop.cityName)-nightlife-\(now)", subtitle: "AI: nightlife is trending now: clubs, rooftops, and after-dark clips.", category: .nightlife),
        AiTourInsight(id: "\(stop.cityName)-music-\(now)", subtitle: "AI: music posts are leading here: concerts, street performers, and studio clips.", category: .music),
        AiTourInsight(id: "\(stop.cityName)-travel-\(now)", subtitle: "AI: travel posts are highest here: landmarks, views, and arrival moments.", category: .travel)
    ]
    return options.randomElement() ?? options[0]
}

private func buildTrendPopObjects(stop: PoplurTourStop, insight: AiTourInsight) -> [TrendPopObject] {
    let seed = abs(stop.cityName.hashValue ^ insight.id.hashValue ^ insight.category.rawValue.hashValue)
    let count = trendPopCountMin + seed % trendPopCountRange
    let lngScale = 0.0048
    let latScale = 0.0036

    return (0..<count).map { index in
        let angle = 2.0 * Double.pi * Double(index) / Double(count) + Double(seed % 360) * Double.pi / 180.0
        let radius = 0.36 + Double((index * 29 + seed) % 100) / 145.0
        let emojiChoices = insight.category.emojis
        return TrendPopObject(
            coordinate: CLLocationCoordinate2D(
                latitude: stop.coordinate.latitude + sin(angle) * latScale * radius,
                longitude: stop.coordinate.longitude + cos(angle) * lngScale * radius
            ),
            emoji: emojiChoices[abs(seed + index) % emojiChoices.count],
            scale: 0.9 + CGFloat((index * 17 + seed) % 28) / 100.0,
            delay: Double(index) * 0.26,
            seed: seed + index * 97
        )
    }
}

@MainActor
private final class CityTourMusicPlayerService: ObservableObject {
    @Published private(set) var currentTrackTitle: String?
    private var player: AVPlayer?
    private var chartTrackCache: [String: [CityMusicTrack]] = [:]
    private var radioTrackCache: [String: [CityMusicTrack]] = [:]
    private var sportsRadioTrackCache: [String: [CityMusicTrack]] = [:]
    private var loadTask: Task<Void, Never>?

    func play(for stop: PoplurTourStop, insight: AiTourInsight?) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            let track = await self.resolveTrack(for: stop, insight: insight)
            guard !Task.isCancelled, let url = URL(string: track.assetURI) else { return }
            await MainActor.run {
                let item = AVPlayerItem(url: url)
                self.player = AVPlayer(playerItem: item)
                self.player?.volume = 0.72
                self.player?.play()
                self.currentTrackTitle = track.artistSeed
            }
        }
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        player?.pause()
        player = nil
        currentTrackTitle = nil
    }

    private func resolveTrack(for stop: PoplurTourStop, insight: AiTourInsight?) async -> CityMusicTrack {
        async let chartTracks = cachedChartTracks(for: stop)
        async let radioTracks = cachedRadioTracks(for: stop)
        async let sportsTracks = cachedSportsTracks(for: stop)

        let resolvedChartTracks = await chartTracks
        let resolvedRadioTracks = await radioTracks
        let resolvedSportsTracks = await sportsTracks

        if insight?.category == .sports, let track = resolvedSportsTracks.randomElement() {
            return track
        }
        if Bool.random(), let track = resolvedRadioTracks.randomElement() {
            return track
        }
        return resolvedChartTracks.randomElement()
            ?? FallbackCityMusicTracks[stop.cityName]
            ?? DefaultFallbackCityMusicTrack
    }

    private func cachedChartTracks(for stop: PoplurTourStop) async -> [CityMusicTrack] {
        if let cached = chartTrackCache[stop.cityName] { return cached }
        let tracks = (try? await resolveTopCountryMusicTracks(stop: stop))
            ?? [FallbackCityMusicTracks[stop.cityName] ?? DefaultFallbackCityMusicTrack]
        chartTrackCache[stop.cityName] = tracks
        return tracks
    }

    private func cachedRadioTracks(for stop: PoplurTourStop) async -> [CityMusicTrack] {
        if let cached = radioTrackCache[stop.cityName] { return cached }
        let tracks = (try? await resolveTopCityRadioTracks(stop: stop)) ?? FallbackCityRadioTracks[stop.cityName] ?? []
        radioTrackCache[stop.cityName] = tracks
        return tracks
    }

    private func cachedSportsTracks(for stop: PoplurTourStop) async -> [CityMusicTrack] {
        if let cached = sportsRadioTrackCache[stop.cityName] { return cached }
        let tracks = (try? await resolveTopCitySportsRadioTracks(stop: stop)) ?? FallbackCitySportsRadioTracks[stop.cityName] ?? []
        sportsRadioTrackCache[stop.cityName] = tracks
        return tracks
    }
}

private func fetchText(from url: URL, userAgent: String? = nil) async throws -> String {
    var request = URLRequest(url: url, timeoutInterval: musicLookupTimeout)
    if let userAgent {
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    }
    let (data, _) = try await URLSession.shared.data(for: request)
    return String(decoding: data, as: UTF8.self)
}

private func resolveTopCountryMusicTracks(stop: PoplurTourStop) async throws -> [CityMusicTrack] {
    let chartURL = URL(string: "https://rss.applemarketingtools.com/api/v2/\(stop.storefront)/music/most-played/50/songs.json")!
    let chartResponse = try await fetchText(from: chartURL)
    guard
        let data = chartResponse.data(using: .utf8),
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let feed = root["feed"] as? [String: Any],
        let results = feed["results"] as? [[String: Any]]
    else { throw URLError(.cannotParseResponse) }

    var tracks: [CityMusicTrack] = []
    for item in results.prefix(24) {
        let title = item["name"] as? String ?? ""
        let artist = item["artistName"] as? String ?? ""
        if let previewURL = try? await lookupITunesPreviewURL(title: title, artist: artist, storefront: stop.storefront) {
            tracks.append(CityMusicTrack(assetURI: previewURL, artistSeed: "\(artist) - \(title)"))
            if tracks.count == musicTopTrackChoices { return tracks }
        }
    }

    if tracks.isEmpty { throw URLError(.resourceUnavailable) }
    return tracks
}

private func resolveTopCityRadioTracks(stop: PoplurTourStop) async throws -> [CityMusicTrack] {
    let city = stop.cityName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stop.cityName
    let country = stop.storefront.uppercased()
    let url = URL(string: "https://de1.api.radio-browser.info/json/stations/search?name=\(city)&countrycode=\(country)&hidebroken=true&order=clickcount&reverse=true&limit=24")!
    return try await queryRadioTracks(url: url, suffix: "live radio")
}

private func resolveTopCitySportsRadioTracks(stop: PoplurTourStop) async throws -> [CityMusicTrack] {
    let city = stop.cityName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stop.cityName
    let country = stop.storefront.uppercased()
    let cityURL = URL(string: "https://de1.api.radio-browser.info/json/stations/search?name=\(city)&tag=sports&countrycode=\(country)&hidebroken=true&order=clickcount&reverse=true&limit=36")!
    let countryURL = URL(string: "https://de1.api.radio-browser.info/json/stations/search?name=&tag=sports&countrycode=\(country)&hidebroken=true&order=clickcount&reverse=true&limit=36")!
    let cityTracks = (try? await queryRadioTracks(url: cityURL, suffix: "live sports radio", sportsOnly: true)) ?? []
    let countryTracks = cityTracks.count < musicTopTrackChoices
        ? ((try? await queryRadioTracks(url: countryURL, suffix: "live sports radio", sportsOnly: true)) ?? [])
        : []
    let tracks = Array((cityTracks + countryTracks).uniquedByAssetURI().prefix(musicTopTrackChoices))
    if tracks.isEmpty { throw URLError(.resourceUnavailable) }
    return tracks
}

private func queryRadioTracks(url: URL, suffix: String, sportsOnly: Bool = false) async throws -> [CityMusicTrack] {
    let response = try await fetchText(from: url, userAgent: "Poplur2025-iOS/1.0")
    guard
        let data = response.data(using: .utf8),
        let stations = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { throw URLError(.cannotParseResponse) }

    let sportsSignals = ["sports", "sport", "espn", "fox sports", "tsn", "sportsnet", "talksport", "score", "fan"]
    let tracks = stations.compactMap { station -> CityMusicTrack? in
        let streamURL = (station["url_resolved"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? station["url"] as? String ?? ""
        let name = station["name"] as? String ?? "Live radio"
        let tags = station["tags"] as? String ?? ""
        guard streamURL.lowercased().hasPrefix("http"), !name.isEmpty else { return nil }
        if sportsOnly {
            let searchable = "\(name) \(tags)".lowercased()
            guard sportsSignals.contains(where: { searchable.contains($0) }) else { return nil }
        }
        return CityMusicTrack(assetURI: streamURL, artistSeed: "\(name) \(suffix)")
    }

    let unique = Array(tracks.uniquedByAssetURI().prefix(musicTopTrackChoices))
    if unique.isEmpty { throw URLError(.resourceUnavailable) }
    return unique
}

private func lookupITunesPreviewURL(title: String, artist: String, storefront: String) async throws -> String? {
    let term = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
    let country = storefront.uppercased()
    let url = URL(string: "https://itunes.apple.com/search?term=\(term)&country=\(country)&media=music&entity=song&limit=5")!
    let response = try await fetchText(from: url)
    guard
        let data = response.data(using: .utf8),
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let results = root["results"] as? [[String: Any]]
    else { return nil }
    return results.compactMap { $0["previewUrl"] as? String }.first { !$0.isEmpty }
}

private extension Array where Element == CityMusicTrack {
    func uniquedByAssetURI() -> [CityMusicTrack] {
        var seen = Set<String>()
        return filter { seen.insert($0.assetURI).inserted }
    }
}

private struct MusicWaveMarker: View {
    let frame: Int
    let tint: Color

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                ArcShape(startAngle: .degrees(-54), endAngle: .degrees(54))
                    .stroke(index == frame % 3 ? Color.white : tint.opacity(0.75), style: StrokeStyle(lineWidth: CGFloat(5 + index * 2), lineCap: .round))
                    .frame(width: CGFloat(30 + index * 22), height: CGFloat(42 + index * 24))
                    .opacity(index == frame % 3 ? 1 : 0.55)
                    .shadow(color: tint.opacity(0.75), radius: 8)
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
    }
}

private struct ArcShape: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.minX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

private struct TrendPopMarker: View {
    let object: TrendPopObject
    let category: TrendCategory
    @State private var isVisible = false

    var body: some View {
        Text(object.emoji)
            .font(.system(size: 30))
            .frame(width: 54, height: 54)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(category.tint.opacity(0.9), lineWidth: 2))
                    .shadow(color: category.tint.opacity(0.85), radius: 12)
            )
            .scaleEffect((isVisible ? object.scale : 0.05) * (1 + CGFloat((object.seed % 7)) * 0.01))
            .opacity(isVisible ? 1 : 0)
            .animation(.spring(response: 0.42, dampingFraction: 0.54).delay(object.delay), value: isVisible)
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
    }
}

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

#if DEBUG
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

// TEMPORARILY DISABLED FOR ARCHIVE TESTING
#if false && !POP_PREVIEW_LIGHT && (!DEBUG || !IS_PREVIEW)
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

#endif // End of DEBUG preview views

// MARK: - Cube Hold Search Overlay (Available in all builds)

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
    @StateObject private var musicPlayer = CityTourMusicPlayerService()
    
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
    
    @State private var posts: [MapAnnotationPost] = []
    @State private var dominance: [CityDominance] = []
    @State private var radiusMeters: Double = 5_000
    
    @State private var currentTourIndex: Int = 0
    @State private var tourZoomOutDistance: CLLocationDistance = 25_000_000 // Distance for zoom out
    @State private var isZoomedOut: Bool = false
    @State private var hasSetInitialLocation: Bool = false  // Track if we've set initial location
    @State private var activeTourStop: PoplurTourStop? = nil
    @State private var activeTourInsight: AiTourInsight? = nil
    @State private var trendPopObjects: [TrendPopObject] = []
    @State private var musicWaveFrame: Int = 0
    
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
    
    // Weather overlay state (DEBUG ONLY)
    #if DEBUG
    @State private var weatherState = WeatherVisualizationState(
        kind: .rain,
        intensity: 0.5,
        lightningFrequency: 0.3
    )
    #endif
    
    // Available in both Debug and Release for tour functionality
    let tourPlaces: [(name: String, coordinate: CLLocationCoordinate2D, description: String)] = PoplurTourStops.map {
        ($0.cityName, $0.coordinate, $0.description)
    }
    
    init() {
        // Initialize with demo cities and posts synchronously to avoid crash
        _dominance = State(initialValue: [
            CityDominance(city: "San Francisco", coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), profileURL: nil),
            CityDominance(city: "New York", coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), profileURL: nil),
            CityDominance(city: "Los Angeles", coordinate: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437), profileURL: nil)
        ])
        
        // Add demo posts near SF for visualization
        _posts = State(initialValue: [
            MapAnnotationPost(title: "Golden Gate", coordinate: CLLocationCoordinate2D(latitude: 37.8199, longitude: -122.4783), radius: 500),
            MapAnnotationPost(title: "Fisherman's Wharf", coordinate: CLLocationCoordinate2D(latitude: 37.8080, longitude: -122.4177), radius: 400),
            MapAnnotationPost(title: "Alcatraz", coordinate: CLLocationCoordinate2D(latitude: 37.8267, longitude: -122.4230), radius: 600)
        ])
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
        clearTourEffects()
        
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
    
    private func filteredPosts() -> [MapAnnotationPost] {
        guard let userLoc = locationManager.location else { return posts }
        return posts.filter {
            MKMapPoint(userLoc.coordinate).distance(to: MKMapPoint($0.coordinate)) <= radiusMeters
        }
    }
    
    private func noteInteraction() {
        // Delegate to state manager
        mapState.noteUserInteraction()
    }

    private func clearTourEffects(stopAudio: Bool = true) {
        activeTourStop = nil
        activeTourInsight = nil
        trendPopObjects = []
        if stopAudio {
            musicPlayer.stop()
        }
    }
    
    private func startTour() {
        mapState.startTour()
    }
    
    private func stopTour() {
        mapState.stopTour()
        clearTourEffects()
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
        clearTourEffects()
        
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
    
    private func runExtendedTourStop(_ stop: PoplurTourStop) async {
        guard mapState.isInTourMode else { return }
        let globeCoordinate = CLLocationCoordinate2D(latitude: 18.0, longitude: -98.0)

        await MainActor.run {
            clearTourEffects()
            currentCity = "World"
            aiRecommendation = "Scanning global hotspots..."
            NotificationCenter.default.post(name: .MapSuggestedRadius, object: nil, userInfo: ["radius": 0.0])
            withAnimation(.easeInOut(duration: 2.6)) {
                radiusMeters = 0
                camera = .camera(
                    MapCamera(
                        centerCoordinate: globeCoordinate,
                        distance: tourZoomOutDistance,
                        heading: 0,
                        pitch: 0
                    )
                )
            }
        }

        try? await Task.sleep(nanoseconds: 3_300_000_000)
        guard mapState.isInTourMode, !Task.isCancelled else { return }

        let insight = spoofAiTourInsight(for: stop)
        await MainActor.run {
            activeTourStop = stop
            activeTourInsight = insight
            currentCity = activeCityTitle(stop)
            aiRecommendation = insight.subtitle
            musicPlayer.play(for: stop, insight: insight)

            #if DEBUG
            Task {
                await fetchWeatherForCurrentLocation()
            }
            #endif

            withAnimation(.easeInOut(duration: 4.2)) {
                camera = .camera(
                    MapCamera(
                        centerCoordinate: stop.coordinate,
                        distance: stop.distance,
                        heading: stop.bearing,
                        pitch: fixedPitchAlt
                    )
                )
                fixedDistanceAlt = stop.distance
                zoomLevel = stop.distance
                radiusMeters = stop.radiusMeters
            }

            NotificationCenter.default.post(
                name: .MapSuggestedRadius,
                object: nil,
                userInfo: ["radius": stop.radiusMeters]
            )
        }

        try? await Task.sleep(nanoseconds: trendPopStartDelaySeconds * 1_000_000_000 + 350_000_000)
        guard mapState.isInTourMode, !Task.isCancelled else { return }

        await MainActor.run {
            AudioServicesPlaySystemSound(1104)
            trendPopObjects = buildTrendPopObjects(stop: stop, insight: insight)
            #if DEBUG
            simulateTrendingBurst()
            #endif
        }

        try? await Task.sleep(nanoseconds: tourStopDwellSeconds * 1_000_000_000)
    }
    
    // MARK: - Computed Properties
    
    private var cameraBinding: Binding<MapCameraPosition> {
        Binding(
            get: { camera },
            set: { newValue in
                // Always sync zoom level with camera distance
                if let distance = newValue.camera?.distance {
                    // Update zoom level to match camera distance
                    // Remove threshold to ensure smooth tracking
                    zoomLevel = distance
                    fixedDistanceAlt = distance
                }
                
                // Allow free camera movement - user can pan/zoom anywhere
                camera = newValue
                
                // Fetch weather when camera moves significantly (DEBUG ONLY)
                #if DEBUG
                if let newCoord = newValue.camera?.centerCoordinate,
                   let oldCoord = self.camera.camera?.centerCoordinate {
                    let distance = MKMapPoint(newCoord).distance(to: MKMapPoint(oldCoord))
                    // Only fetch if moved more than 50km
                    if distance > 50_000 {
                        Task {
                            await fetchWeatherForCurrentLocation()
                        }
                    }
                }
                #endif
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
            ZStack {
                Map(
                    position: cameraBinding,
                    interactionModes: [.pan, .rotate, .pitch, .zoom]
                ) {
                // Show user annotation with 3D blue pin when location is available
                if let userCoord = locationManager.location?.coordinate {
                    Annotation("", coordinate: userCoord) {
                        Enhanced3DBeaconMarker(color: Color.blue, intensity: 0.9)
                            .frame(width: 100, height: 120)
                    }
                }
                
                // Show marker when user clicks a coordinate
                if showPostPrompt, let coord = clickedCoordinate {
                    Annotation("Selected Location", coordinate: coord) {
                        ZStack {
                            // Outer glow ring
                            Circle()
                                .fill(Color.indigo.opacity(0.2))
                                .frame(width: 80, height: 80)
                            
                            // Inner circle
                            Circle()
                                .fill(Color.indigo.opacity(0.5))
                                .frame(width: 60, height: 60)
                            
                            // Icon
                            if flowManager.currentFlow?.isCameraFirst ?? false {
                                // Camera -> Map: Show upload/checkmark icon
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white, .indigo)
                                    .shadow(color: .black.opacity(0.3), radius: 2)
                            } else {
                                // Map -> Camera: Show camera icon
                                Image(systemName: "camera.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white, .indigo)
                                    .shadow(color: .black.opacity(0.3), radius: 2)
                            }
                        }
                        .animation(.easeInOut(duration: 0.3), value: showPostPrompt)
                    }
                }
                
                // Show placement marker when in post placement mode
                if isPostPlacementMode, let coord = postPlacementCoordinate {
                    Annotation("", coordinate: coord) {
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
                    // Show radius circle if available
                    if let radius = shownPostRadius {
                        MapCircle(center: coord, radius: radius)
                            .foregroundStyle(Color.purple.opacity(0.15))
                            .stroke(Color.purple.opacity(0.5), lineWidth: 2)
                    }
                    
                    // Show detailed pin annotation - no background, text only
                    Annotation("", coordinate: coord) {
                        // Pin marker only - no information card
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
                
                ForEach(filteredPosts()) { post in
                    Annotation("", coordinate: post.coordinate) {
                        // Use different colors for variety
                        let colors: [Color] = [.orange, .blue, .green, .yellow, .pink]
                        let colorIndex = abs(post.title.hashValue) % colors.count
                        Enhanced3DBeaconMarker(color: colors[colorIndex], intensity: 0.6)
                            .frame(width: 80, height: 100)
                    }
                    
                    // Glowing circle with vibrant colors
                    MapCircle(center: post.coordinate, radius: post.radius)
                        .foregroundStyle(Color.orange.opacity(0.15))
                        .stroke(Color.orange.opacity(0.6), lineWidth: 2)
                }
                
                ForEach(dominance) { dom in
                    Annotation("", coordinate: dom.coordinate) {
                        if let url = dom.profileURL {
                            DominancePin(profileURL: url)
                        } else {
                            // High-intensity purple beacons for dominance locations
                            Enhanced3DBeaconMarker(color: .purple, intensity: 1.0)
                                .frame(width: 110, height: 130)
                        }
                    }
                }

                if let stop = activeTourStop {
                    Annotation("", coordinate: stop.coordinate) {
                        MusicWaveMarker(frame: musicWaveFrame, tint: activeTourInsight?.category.tint ?? .cyan)
                            .offset(x: 38, y: -72)
                    }
                }

                if let insight = activeTourInsight {
                    ForEach(trendPopObjects) { object in
                        Annotation("", coordinate: object.coordinate) {
                            TrendPopMarker(object: object, category: insight.category)
                        }
                    }
                }
                }
#if POP_PREVIEW_LIGHT
                .mapStyle(.standard)
#else
                .mapStyle(.hybrid(elevation: .realistic, showsTraffic: false))
#endif
                .onTapGesture { location in
                // Handle map tap based on current flow
                if let coordinate = proxy.convert(location, from: .local) {
                    print("🗺️ [MapView] Map tapped at screen: \(location), converted to: \(coordinate.latitude), \(coordinate.longitude)")
                    
                    if let flow = flowManager.currentFlow, flow.isCameraFirst {
                        // Flow 2: Camera -> Map - User already captured, now selecting location
                        clickedCoordinate = coordinate
                        showPostPrompt = true
                        
                        currentCity = "Location Selected"
                        aiRecommendation = String(format: "📍 %.4f°, %.4f° — Post your capture here?", 
                                                 coordinate.latitude, 
                                                 coordinate.longitude)
                        print("[MapView] Camera -> Map flow: Selected coordinate \(coordinate.latitude), \(coordinate.longitude)")
                    } else {
                        // Flow 1: Map -> Camera OR normal browsing
                        if showCubeHoldSearch {
                            showCubeHoldSearch = false
                        } else {
                            // Store clicked coordinate and show prompt
                            clickedCoordinate = coordinate
                            showPostPrompt = true
                            
                            // Update AI text to show coordinate
                            currentCity = "Location Selected"
                            aiRecommendation = String(format: "📍 %.4f°, %.4f° — Want to post here?", 
                                                     coordinate.latitude, 
                                                     coordinate.longitude)
                            print("✅ [MapView] Set clickedCoordinate: \(coordinate.latitude), \(coordinate.longitude)")
                            print("   showPostPrompt: \(showPostPrompt)")
                        }
                        noteInteraction()
                    }
                } else {
                    print("❌ [MapView] Failed to convert screen location to coordinate")
                }
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        // Long press on map - no action (removed)
                        noteInteraction()
                    }
            )
                
            // Weather particle overlay (DEBUG ONLY)
            #if DEBUG
            WeatherParticleOverlay(weatherState: $weatherState)
                .allowsHitTesting(false) // Let touches pass through to map
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
            
            // Confetti overlay for trending pins
            if showConfetti {
                GeometryReader { geometry in
                    ConfettiOverlay(
                        trendingPins: $trendingTracker.trendingPins,
                        coordinateConverter: { coordinate -> CGPoint? in
                            // Convert map coordinate to screen point
                            // Note: MapReader doesn't provide direct coordinate->point conversion
                            // We need to implement this based on current camera position
                            guard let camera = camera.camera else { return nil }
                            
                            // Use MKMapView's conversion (approximation for demo)
                            // In production, you'd want a more precise conversion
                            let centerCoord = camera.centerCoordinate
                            let latDelta = coordinate.latitude - centerCoord.latitude
                            let lonDelta = coordinate.longitude - centerCoord.longitude
                            
                            // Rough pixel conversion (will vary with zoom)
                            let pixelsPerDegree = geometry.size.width / 0.5 // Approximate
                            let x = geometry.size.width / 2 + CGFloat(lonDelta) * pixelsPerDegree
                            let y = geometry.size.height / 2 - CGFloat(latDelta) * pixelsPerDegree
                            
                            // Check if point is within bounds
                            guard x >= 0, x <= geometry.size.width,
                                  y >= 0, y <= geometry.size.height else {
                                return nil
                            }
                            
                            return CGPoint(x: x, y: y)
                        }
                    )
                    .allowsHitTesting(false) // Let touches pass through
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            
            // 3D SceneKit Overlay Layer - Floating beacons over map
            // Note: This layer is separate from the Map to avoid gesture conflicts
            // Commented out due to coordinate conversion issues - can be re-enabled after fixing
            /*
            GeometryReader { geometry in
                MapReader { beaconProxy in
                    ForEach(dominance) { dom in
                        if let screenPoint = beaconProxy.convert(dom.coordinate, from: .global) {
                            Floating3DBeacon(color: .purple, pulseSpeed: 2.0)
                                .frame(width: 120, height: 200)
                                .position(screenPoint)
                        }
                    }
                    
                    // Show 3D beacon for post location
                    if let coord = shownPostCoordinate,
                       let screenPoint = beaconProxy.convert(coord, from: .global) {
                        Floating3DBeacon(color: .purple, pulseSpeed: 1.5)
                            .frame(width: 150, height: 220)
                            .position(screenPoint)
                    }
                    
                    // Show 3D beacons for filtered posts
                    ForEach(filteredPosts()) { post in
                        if let screenPoint = beaconProxy.convert(post.coordinate, from: .global) {
                            Floating3DBeacon(color: .red, pulseSpeed: 2.5)
                                .frame(width: 100, height: 180)
                                .position(screenPoint)
                        }
                    }
                }
            }
            .allowsHitTesting(false) // Let touches pass through to map
            */
        } // End ZStack
        } // End MapReader
    }
    
    // MARK: - Body Components (broken down to help compiler)
    
    @ViewBuilder
    private var navigationButtons: some View {
        VStack {
            Spacer()
        }
    }
    
    @ViewBuilder
    private var aiRecommendationOverlay: some View {
        VStack {
            Spacer().frame(height: 24)
            
            // AI Text at top - no background
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
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    Text(recommendationText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
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
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Animated Zoom Slider - positioned on left side
            HStack {
                AnimatedZoomSlider(zoomLevel: $zoomLevel) { newZoom in
                    // Update camera when slider changes - zoom from CURRENT camera position
                    // This allows zooming in/out from anywhere on the map
                    guard let currentCoord = camera.camera?.centerCoordinate else { return }
                    let heading = camera.camera?.heading ?? 0
                    
                    let clampedZoom = newZoom.clamped(to: 10...40_000_000)
                    
                    // Smoothly animate zoom change
                    withAnimation(.easeOut(duration: 0.2)) {
                        camera = .camera(
                            MapCamera(
                                centerCoordinate: currentCoord, // Keep current view position
                                distance: clampedZoom,
                                heading: heading,
                                pitch: fixedPitchAlt
                            )
                        )
                    }
                    
                    fixedDistanceAlt = clampedZoom
                }
                .frame(width: 60, height: 400)
                .padding(.leading, 12)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
                
                Spacer()
            }
            .padding(.bottom, 120) // Positioned above bottom UI
            .zIndex(1000) // Ensure slider appears above map
            
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
                .transition(AnyTransition.move(edge: .top).combined(with: .opacity))
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
                .transition(AnyTransition.move(edge: .top).combined(with: .opacity))
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
                .transition(AnyTransition.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showCubeHoldSearch)
            }
            
            Spacer()
        }
    }
    
    #if DEBUG
    @ViewBuilder
    private var weatherControlsOverlay: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                VStack(spacing: 12) {
                    // Current weather display
                    VStack(spacing: 4) {
                        weatherIcon(for: weatherState.kind)
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                        
                        Text(weatherName(for: weatherState.kind))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    
                    Divider()
                        .frame(width: 30)
                        .background(.white.opacity(0.3))
                    
                    // Confetti toggle
                    Button(action: {
                        showConfetti.toggle()
                    }) {
                        Image(systemName: showConfetti ? "party.popper.fill" : "party.popper")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial.opacity(0.6), in: Circle())
                            .shadow(color: .black.opacity(0.3), radius: 2)
                    }
                    
                    // Simulate trending button
                    Button(action: {
                        simulateTrendingBurst()
                    }) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial.opacity(0.6), in: Circle())
                            .shadow(color: .black.opacity(0.3), radius: 2)
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 200)
            }
        }
    }
    #endif
    
    #if DEBUG
    /// Get icon for weather type
    private func weatherIcon(for kind: WeatherVisualizationState.Kind) -> Image {
        switch kind {
        case .rain:
            return Image(systemName: "cloud.rain.fill")
        case .thunderstorms:
            return Image(systemName: "cloud.bolt.rain.fill")
        case .cloudy:
            return Image(systemName: "cloud.fill")
        case .snow:
            return Image(systemName: "snowflake")
        }
    }
    
    /// Get name for weather type
    private func weatherName(for kind: WeatherVisualizationState.Kind) -> String {
        switch kind {
        case .rain:
            return "Rain"
        case .thunderstorms:
            return "Storms"
        case .cloudy:
            return "Cloudy"
        case .snow:
            return "Snow"
        }
    }
    
    /// Fetch weather for current map center
    private func fetchWeatherForCurrentLocation() async {
        guard let centerCoord = camera.camera?.centerCoordinate else { return }
        
        // In production, you would call a real weather API here
        // For now, we'll simulate based on location
        await MainActor.run {
            // Simple mock based on latitude/season
            let latitude = centerCoord.latitude
            
            if latitude > 45 {
                // Northern regions - snow
                weatherState.kind = .snow
                weatherState.intensity = 0.6
            } else if latitude > 30 {
                // Temperate - rain
                weatherState.kind = .rain
                weatherState.intensity = 0.5
            } else {
                // Tropical - thunderstorms
                weatherState.kind = .thunderstorms
                weatherState.intensity = 0.7
                weatherState.lightningFrequency = 0.4
            }
            
            print("🌦 Weather updated for location: \(latitude), \(centerCoord.longitude)")
            print("   Weather: \(weatherName(for: weatherState.kind))")
        }
    }
    
    /// Simulate a trending burst for demo purposes
    private func simulateTrendingBurst() {
        guard let randomPost = posts.randomElement() else { return }
        
        // Dramatically increase radius to trigger confetti
        let newRadius = randomPost.radius * 1.5
        
        if let index = posts.firstIndex(where: { $0.id == randomPost.id }) {
            // Update post with new radius
            posts[index] = MapAnnotationPost(
                title: randomPost.title,
                coordinate: randomPost.coordinate,
                radius: newRadius
            )
            
            // Force trending update
            trendingTracker.updatePin(
                id: posts[index].id,
                coordinate: posts[index].coordinate,
                radius: newRadius,
                activityCount: 100 // High activity = high trending score
            )
            
            print("🎉 Simulated trending burst for \(randomPost.title) - radius: \(Int(randomPost.radius))m → \(Int(newRadius))m")
        }
    }
    #endif // End DEBUG weather methods
    
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
            
            // AI Recommendation Overlay (now includes zoom slider above it)
            aiRecommendationOverlay
            
            // Weather controls (DEBUG ONLY - removed in production builds)
            #if DEBUG
            weatherControlsOverlay
            #endif
        }
    }
    
    var body: some View {
        mapContentLayer
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPlacesList) {
                #if DEBUG
                placesListSheet
                #endif
            }
            .sheet(isPresented: $showAddressSearch) {
                #if DEBUG
                addressSearchSheet
                #endif
            }
            .onAppear {
                handleOnAppear()
            }
            .onDisappear {
                musicPlayer.stop()
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
            .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldBegan)) { notification in
                // Long press cube shows favorites/search overlay
                print("[MapView] Cube hold began - showing favorites overlay")
                showCubeHoldSearch = true
                mapState.stopTour()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CameraCubeHoldMoved"))) { notification in
                // No action during drag - slider handles zoom now
            }
            .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldEnded)) { _ in
                // No action on end - menu stays open
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
    
    #if DEBUG
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
    #endif
    
    // MARK: - Event Handlers
    
    private func handleOnAppear() {
        print("👀 [MapView] handleOnAppear called")
        print("   lockToPostUntil: \(lockToPostUntil?.description ?? "nil")")
        print("   mapState.mode: \(mapState.mode)")
        print("   pendingPostLocation: \(mapState.pendingPostLocation?.latitude ?? 0), \(mapState.pendingPostLocation?.longitude ?? 0)")
        
        // Fetch initial weather (DEBUG ONLY)
        #if DEBUG
        Task {
            await fetchWeatherForCurrentLocation()
        }
        #endif
        
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
        
        var waveTask: Task<Void, Never>?
        waveTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180_000_000)
                musicWaveFrame = (musicWaveFrame + 1) % 4
            }
        }
        defer { waveTask?.cancel() }

        // Extended tour loop - mirrors Android's globe scan, fly-in, music/radio, and pop burst.
        while !Task.isCancelled {
            if mapState.isInTourMode {
                let stop = PoplurTourStops[currentTourIndex % PoplurTourStops.count]
                await runExtendedTourStop(stop)
                await MainActor.run {
                    currentTourIndex = (currentTourIndex + 1) % PoplurTourStops.count
                }
            } else {
                await MainActor.run {
                    clearTourEffects()
                    isZoomedOut = false
                }
                // If tour is not active, wait a bit before checking again
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            // Update trending pins periodically
            await updateTrendingPins()
        }
    }
    
    /// Update trending pin tracking (called periodically)
    private func updateTrendingPins() async {
        await MainActor.run {
            // Update all visible posts as trending pins
            for post in filteredPosts() {
                trendingTracker.updatePin(
                    id: post.id,
                    coordinate: post.coordinate,
                    radius: post.radius,
                    activityCount: Int.random(in: 1...10) // Replace with real activity count
                )
            }
            
            // Simulate radius growth for demo (remove in production)
            // In production, this would come from your real-time database
            if posts.count > 0, Bool.random() && Double.random(in: 0...1) > 0.7 {
                let randomPost = posts.randomElement()!
                let newRadius = min(randomPost.radius * Double.random(in: 1.1...1.3), 10000)
                
                // Update the post radius (this triggers confetti if growing significantly)
                if let index = posts.firstIndex(where: { $0.id == randomPost.id }) {
                    posts[index] = MapAnnotationPost(
                        title: randomPost.title,
                        coordinate: randomPost.coordinate,
                        radius: newRadius
                    )
                    
                    // Update trending tracker
                    trendingTracker.updatePin(
                        id: posts[index].id,
                        coordinate: posts[index].coordinate,
                        radius: newRadius,
                        activityCount: Int.random(in: 1...10)
                    )
                }
            }
            
            // Clean old tracking data
            trendingTracker.cleanAllOldHistory()
        }
    }
}

// MARK: - Previews

#if DEBUG
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
