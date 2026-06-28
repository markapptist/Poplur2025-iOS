import SwiftUI
import MapKit
import CoreLocation
import SceneKit
import Foundation
import AVFoundation
import AudioToolbox
import WebKit

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
    enum Kind: Equatable { case rain, thunderstorms, cloudy, snow }
    var kind: Kind
    var intensity: Double // 0..1
    var lightningFrequency: Double // 0..1
    var temperatureFahrenheit: Int
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

// MARK: - Poplur Map Radio

// Thin wrapper so the map radio host can call ElevenLabsService with the same interface as before.
private final class PoplurHumanVoiceSpeechService {
    static let shared = PoplurHumanVoiceSpeechService()

    func speechData(for script: String) async throws -> Data {
        let text = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ElevenLabsService.ElevenLabsError.badResponse }
        return try await ElevenLabsService.shared.audioData(for: text, voice: .english)
    }
}

@MainActor
final class PoplurMapRadioHost: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = PoplurMapRadioHost()

    @Published private(set) var isLive = false
    @Published private(set) var currentScript = "Poplur Radio is ready."

    private let synth = AVSpeechSynthesizer()
    private var generatedVoicePlayer: AVAudioPlayer?
    private var generatedVoiceTask: Task<Void, Never>?
    private var speechToken = UUID()
    private var onSpeechFinished: (() -> Void)?
    private var prewarmTask: Task<Void, Never>?

    override init() {
        super.init()
        synth.delegate = self
    }

    // Pre-fetches TTS audio for the generic "your area" opening script so it is
    // cached in PoplurHumanVoiceSpeechService before the map tab is first opened.
    func prewarm() async {
        guard prewarmTask == nil else { return }
        let genericScript = "Welcome to Poplur Radio, live and direct from your area. The music scene here is absolutely on fire. Stay with us."
        prewarmTask = Task {
            _ = try? await PoplurHumanVoiceSpeechService.shared.speechData(for: genericScript)
        }
        await prewarmTask?.value
    }

    func speak(_ script: String, onFinished: (() -> Void)? = nil) {
        stop(notifyFinished: false)
        synth.stopSpeaking(at: .immediate)
        currentScript = script
        onSpeechFinished = onFinished

        isLive = true
        let token = UUID()
        speechToken = token

        generatedVoiceTask = Task { [weak self] in
            do {
                let data = try await PoplurHumanVoiceSpeechService.shared.speechData(for: script)
                try Task.checkCancellation()
                try await MainActor.run {
                    guard let self, self.speechToken == token else { return }
                    try self.playGeneratedVoice(data, token: token)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.speechToken == token else { return }
                    self.speakWithSystemVoice(script, token: token)
                }
            }
        }
    }

    private static func preferredRadioVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let britishVoices = voices.filter { $0.language == "en-GB" }
        let preferredNames = ["serena", "daniel", "martha", "arthur", "kate"]
        if let named = britishVoices.first(where: { voice in
            preferredNames.contains { voice.name.lowercased().contains($0) }
        }) {
            return named
        }
        if let premium = britishVoices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = britishVoices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        if let anyPremium = voices.first(where: { $0.language.hasPrefix("en") && $0.quality == .premium }) {
            return anyPremium
        }
        if let anyEnhanced = voices.first(where: { $0.language.hasPrefix("en") && $0.quality == .enhanced }) {
            return anyEnhanced
        }
        return AVSpeechSynthesisVoice(language: "en-GB")
    }

    func stop() {
        stop(notifyFinished: false)
    }

    private func stop(notifyFinished: Bool) {
        speechToken = UUID()
        generatedVoiceTask?.cancel()
        generatedVoiceTask = nil
        generatedVoicePlayer?.stop()
        generatedVoicePlayer?.delegate = nil
        generatedVoicePlayer = nil
        synth.stopSpeaking(at: .immediate)
        isLive = false
        let completion = onSpeechFinished
        onSpeechFinished = nil
        if notifyFinished {
            completion?()
        }
    }

    private func playGeneratedVoice(_ data: Data, token: UUID) throws {
        guard speechToken == token else { return }
        try configureVoiceSession()
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.volume = 1.0
        player.prepareToPlay()
        generatedVoicePlayer = player
        if !player.play() {
            throw URLError(.cannotOpenFile)
        }
    }

    private func speakWithSystemVoice(_ script: String, token: UUID) {
        guard speechToken == token else { return }
        try? configureVoiceSession()

        let utterance = AVSpeechUtterance(string: script)
        utterance.voice = Self.preferredRadioVoice()
        utterance.rate = 0.49
        utterance.pitchMultiplier = 0.98
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.04
        utterance.postUtteranceDelay = 0.12

        synth.speak(utterance)
    }

    private func configureVoiceSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try session.setActive(true, options: [])
    }

    private func finishSpeech() {
        generatedVoiceTask?.cancel()
        generatedVoiceTask = nil
        generatedVoicePlayer?.delegate = nil
        generatedVoicePlayer = nil
        isLive = false
        let completion = onSpeechFinished
        onSpeechFinished = nil
        completion?()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.finishSpeech()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.generatedVoiceTask == nil,
                  self.generatedVoicePlayer == nil,
                  !self.synth.isSpeaking else { return }
            self.isLive = false
            self.onSpeechFinished = nil
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.finishSpeech()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.finishSpeech()
        }
    }
}

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

private enum LiveTourMomentKind {
    case sports
    case shopping
}

private struct PoplurLiveTourMoment {
    let id: String
    let kind: LiveTourMomentKind
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let bearing: CLLocationDirection
    let radiusMeters: Double
    let distance: CLLocationDistance
    let category: TrendCategory
}

private struct SportsVenue {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let bearing: CLLocationDirection
}

private struct ShoppingSaleVenue {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let sale: String
    let bearing: CLLocationDirection
}

private struct TrendPopObject: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let channelId: String
    let objectId: String
    let scale: CGFloat
    let delay: Double
    let seed: Int
}

private enum PoplurRadioTopic: String, CaseIterable, Identifiable {
    case malls
    case universities
    case restaurants
    case stadiums
    case airports
    case concerts
    case downtown
    case themeParks
    case casinos
    case hotels

    var id: String { rawValue }

    var title: String {
        switch self {
        case .malls: return "Malls"
        case .universities: return "Universities"
        case .restaurants: return "Restaurants"
        case .stadiums: return "Stadiums"
        case .airports: return "Airports"
        case .concerts: return "Concert Venues"
        case .downtown: return "Downtown Districts"
        case .themeParks: return "Theme Parks"
        case .casinos: return "Casinos"
        case .hotels: return "Hotels & Resorts"
        }
    }

    var shortTitle: String {
        switch self {
        case .universities: return "Colleges"
        case .restaurants: return "Food"
        case .stadiums: return "Arenas"
        case .themeParks: return "Parks"
        case .hotels: return "Hotels"
        default: return title
        }
    }

    var symbolName: String {
        switch self {
        case .malls: return "bag.fill"
        case .universities: return "graduationcap.fill"
        case .restaurants: return "fork.knife"
        case .stadiums: return "sportscourt.fill"
        case .airports: return "airplane"
        case .concerts: return "music.mic"
        case .downtown: return "building.2.fill"
        case .themeParks: return "sparkles"
        case .casinos: return "suit.diamond.fill"
        case .hotels: return "bed.double.fill"
        }
    }

    var trendCategory: TrendCategory {
        switch self {
        case .malls, .universities:
            return .clothes
        case .restaurants:
            return .food
        case .stadiums:
            return .sports
        case .concerts:
            return .music
        case .casinos:
            return .nightlife
        case .airports, .downtown, .themeParks, .hotels:
            return .travel
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .malls, .restaurants, .stadiums, .concerts, .downtown:
            return true
        case .universities, .airports, .themeParks, .casinos, .hotels:
            return false
        }
    }
}

private struct PoplurTourFocus {
    let topic: PoplurRadioTopic
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let bearing: CLLocationDirection
    let radiusMeters: Double
    let distance: CLLocationDistance
    let category: TrendCategory
    let liveMoment: PoplurLiveTourMoment?
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

    var lightTint: Color {
        switch self {
        case .clothes: return Color(red: 1.0, green: 0.55, blue: 0.85)
        case .sports: return Color(red: 0.63, green: 1.0, blue: 0.69)
        case .food: return Color(red: 1.0, green: 0.88, blue: 0.46)
        case .nightlife: return Color(red: 0.80, green: 0.65, blue: 1.0)
        case .music: return Color(red: 0.58, green: 0.96, blue: 1.0)
        case .travel: return Color(red: 1.0, green: 0.62, blue: 0.56)
        }
    }

    var darkTint: Color {
        switch self {
        case .clothes: return Color(red: 0.50, green: 0.11, blue: 0.38)
        case .sports: return Color(red: 0.11, green: 0.50, blue: 0.22)
        case .food: return Color(red: 0.61, green: 0.35, blue: 0.07)
        case .nightlife: return Color(red: 0.32, green: 0.18, blue: 0.62)
        case .music: return Color(red: 0.04, green: 0.36, blue: 0.62)
        case .travel: return Color(red: 0.62, green: 0.12, blue: 0.10)
        }
    }
}

private let tourStopDwellSeconds: UInt64 = 30
private let tourTopicDwellSeconds: UInt64 = 14
private let trendPopStartDelaySeconds: UInt64 = 1
private let trendPopCountMin = 10
private let trendPopCountRange = 6
private let musicLookupTimeout: TimeInterval = 5
private let musicTopTrackChoices = 5

private enum PoplurAudioMix {
    static let musicFullVolume: Float = 0.92
    static let voiceDuckVolume: Float = 0.10
    static let rainDuckMultiplier: Float = 0.32
    static let rainFadeDuration: TimeInterval = 1.35
    static let rainVoiceDuckDuration: TimeInterval = 0.55
    static let musicFadeDuration: TimeInterval = 1.8
    static let musicDuckDuration: TimeInterval = 0.45
    static let musicUnduckDuration: TimeInterval = 1.25
}

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

private let PoplurSportsVenueCatalog: [String: [SportsVenue]] = [
    "New York": [
        SportsVenue(name: "Madison Square Garden", coordinate: CLLocationCoordinate2D(latitude: 40.7505, longitude: -73.9934), bearing: -18),
        SportsVenue(name: "Barclays Center", coordinate: CLLocationCoordinate2D(latitude: 40.6826, longitude: -73.9754), bearing: 18),
        SportsVenue(name: "Yankee Stadium", coordinate: CLLocationCoordinate2D(latitude: 40.8296, longitude: -73.9262), bearing: -24),
        SportsVenue(name: "Citi Field", coordinate: CLLocationCoordinate2D(latitude: 40.7571, longitude: -73.8458), bearing: 24),
        SportsVenue(name: "MetLife Stadium", coordinate: CLLocationCoordinate2D(latitude: 40.8135, longitude: -74.0745), bearing: -12)
    ],
    "Los Angeles": [
        SportsVenue(name: "Crypto.com Arena", coordinate: CLLocationCoordinate2D(latitude: 34.0430, longitude: -118.2673), bearing: 20),
        SportsVenue(name: "Dodger Stadium", coordinate: CLLocationCoordinate2D(latitude: 34.0739, longitude: -118.2400), bearing: 28),
        SportsVenue(name: "SoFi Stadium", coordinate: CLLocationCoordinate2D(latitude: 33.9535, longitude: -118.3392), bearing: -26),
        SportsVenue(name: "BMO Stadium", coordinate: CLLocationCoordinate2D(latitude: 34.0128, longitude: -118.2845), bearing: 16)
    ],
    "Chicago": [
        SportsVenue(name: "United Center", coordinate: CLLocationCoordinate2D(latitude: 41.8807, longitude: -87.6742), bearing: -18),
        SportsVenue(name: "Wrigley Field", coordinate: CLLocationCoordinate2D(latitude: 41.9484, longitude: -87.6553), bearing: 24),
        SportsVenue(name: "Soldier Field", coordinate: CLLocationCoordinate2D(latitude: 41.8623, longitude: -87.6167), bearing: 12),
        SportsVenue(name: "Guaranteed Rate Field", coordinate: CLLocationCoordinate2D(latitude: 41.8300, longitude: -87.6339), bearing: -22)
    ],
    "Toronto": [
        SportsVenue(name: "Scotiabank Arena", coordinate: CLLocationCoordinate2D(latitude: 43.6435, longitude: -79.3791), bearing: 24),
        SportsVenue(name: "Rogers Centre", coordinate: CLLocationCoordinate2D(latitude: 43.6414, longitude: -79.3894), bearing: -20),
        SportsVenue(name: "BMO Field", coordinate: CLLocationCoordinate2D(latitude: 43.6332, longitude: -79.4186), bearing: 30)
    ],
    "London": [
        SportsVenue(name: "Wembley Stadium", coordinate: CLLocationCoordinate2D(latitude: 51.5560, longitude: -0.2796), bearing: -26),
        SportsVenue(name: "Emirates Stadium", coordinate: CLLocationCoordinate2D(latitude: 51.5549, longitude: -0.1084), bearing: 18),
        SportsVenue(name: "Tottenham Hotspur Stadium", coordinate: CLLocationCoordinate2D(latitude: 51.6043, longitude: -0.0662), bearing: 22),
        SportsVenue(name: "Stamford Bridge", coordinate: CLLocationCoordinate2D(latitude: 51.4817, longitude: -0.1910), bearing: -18)
    ],
    "Tokyo": [
        SportsVenue(name: "Tokyo Dome", coordinate: CLLocationCoordinate2D(latitude: 35.7056, longitude: 139.7519), bearing: 34),
        SportsVenue(name: "Japan National Stadium", coordinate: CLLocationCoordinate2D(latitude: 35.6780, longitude: 139.7147), bearing: -24)
    ],
    "Sydney": [
        SportsVenue(name: "Accor Stadium", coordinate: CLLocationCoordinate2D(latitude: -33.8472, longitude: 151.0634), bearing: -28),
        SportsVenue(name: "Sydney Cricket Ground", coordinate: CLLocationCoordinate2D(latitude: -33.8915, longitude: 151.2248), bearing: 22)
    ],
    "Miami": [
        SportsVenue(name: "Kaseya Center", coordinate: CLLocationCoordinate2D(latitude: 25.7814, longitude: -80.1870), bearing: 28),
        SportsVenue(name: "Hard Rock Stadium", coordinate: CLLocationCoordinate2D(latitude: 25.9580, longitude: -80.2389), bearing: -24),
        SportsVenue(name: "loanDepot park", coordinate: CLLocationCoordinate2D(latitude: 25.7781, longitude: -80.2197), bearing: 18)
    ],
    "Paris": [
        SportsVenue(name: "Parc des Princes", coordinate: CLLocationCoordinate2D(latitude: 48.8414, longitude: 2.2530), bearing: 24),
        SportsVenue(name: "Stade de France", coordinate: CLLocationCoordinate2D(latitude: 48.9245, longitude: 2.3601), bearing: -20),
        SportsVenue(name: "Accor Arena", coordinate: CLLocationCoordinate2D(latitude: 48.8386, longitude: 2.3786), bearing: 18)
    ]
]

private let PoplurShoppingSaleCatalog: [String: [ShoppingSaleVenue]] = [
    "New York": [
        ShoppingSaleVenue(name: "Westfield World Trade Center", coordinate: CLLocationCoordinate2D(latitude: 40.7116, longitude: -74.0113), sale: "Nike, Sephora, and Apple accessories are flagged for 20-40% off limited-time in-store drops.", bearing: -18),
        ShoppingSaleVenue(name: "The Shops at Columbus Circle", coordinate: CLLocationCoordinate2D(latitude: 40.7686, longitude: -73.9830), sale: "Designer apparel and sneaker shops are running end-of-week clearance, up to 35% off select items.", bearing: 22)
    ],
    "Los Angeles": [
        ShoppingSaleVenue(name: "Westfield Century City", coordinate: CLLocationCoordinate2D(latitude: 34.0587, longitude: -118.4198), sale: "Fashion and beauty stores are showing 25-50% off summer edits and bonus loyalty points.", bearing: 26),
        ShoppingSaleVenue(name: "The Grove", coordinate: CLLocationCoordinate2D(latitude: 34.0720, longitude: -118.3570), sale: "Pop-up retail signal: shoes, denim, and fragrance bundles marked down through tonight.", bearing: -20)
    ],
    "Chicago": [
        ShoppingSaleVenue(name: "Water Tower Place", coordinate: CLLocationCoordinate2D(latitude: 41.8976, longitude: -87.6235), sale: "Mall-wide sale signal: apparel, bags, and cosmetics are 20-45% off select collections.", bearing: -18)
    ],
    "Toronto": [
        ShoppingSaleVenue(name: "CF Toronto Eaton Centre", coordinate: CLLocationCoordinate2D(latitude: 43.6544, longitude: -79.3807), sale: "Sneakers, beauty, and tech accessories are marked 20-40% off at participating stores.", bearing: 24),
        ShoppingSaleVenue(name: "Yorkdale Shopping Centre", coordinate: CLLocationCoordinate2D(latitude: 43.7255, longitude: -79.4522), sale: "Luxury and streetwear sale signal: select seasonal items up to 30% off today.", bearing: -24)
    ],
    "London": [
        ShoppingSaleVenue(name: "Westfield London", coordinate: CLLocationCoordinate2D(latitude: 51.5073, longitude: -0.2219), sale: "Fashion, trainer, and beauty stores are running 25-50% off flash offers until close.", bearing: -28),
        ShoppingSaleVenue(name: "Westfield Stratford City", coordinate: CLLocationCoordinate2D(latitude: 51.5433, longitude: -0.0067), sale: "Shopping signal: electronics accessories and streetwear bundles marked down today.", bearing: 18)
    ],
    "Tokyo": [
        ShoppingSaleVenue(name: "Shibuya Scramble Square", coordinate: CLLocationCoordinate2D(latitude: 35.6585, longitude: 139.7020), sale: "Department floors are showing limited-time fashion, skincare, and lifestyle markdowns.", bearing: 34)
    ],
    "Paris": [
        ShoppingSaleVenue(name: "Westfield Forum des Halles", coordinate: CLLocationCoordinate2D(latitude: 48.8626, longitude: 2.3470), sale: "Beauty, sneakers, and casualwear sale signal: select collections 20-40% off today.", bearing: 18),
        ShoppingSaleVenue(name: "Galeries Lafayette Haussmann", coordinate: CLLocationCoordinate2D(latitude: 48.8738, longitude: 2.3321), sale: "Designer and fragrance counters are flagged for limited in-store offers.", bearing: -22)
    ],
    "Sydney": [
        ShoppingSaleVenue(name: "Westfield Sydney", coordinate: CLLocationCoordinate2D(latitude: -33.8705, longitude: 151.2089), sale: "Fashion and beauty retailers are running 20-40% off selected seasonal edits.", bearing: -26)
    ],
    "Singapore": [
        ShoppingSaleVenue(name: "ION Orchard", coordinate: CLLocationCoordinate2D(latitude: 1.3040, longitude: 103.8319), sale: "Orchard Road retail signal: beauty, luxury, and sneaker offers running through close.", bearing: 22)
    ],
    "Dubai": [
        ShoppingSaleVenue(name: "The Dubai Mall", coordinate: CLLocationCoordinate2D(latitude: 25.1972, longitude: 55.2796), sale: "Mall-wide shopping signal: fashion, fragrance, and electronics offers up to 50% off.", bearing: 18)
    ]
]

private func countryFlagEmoji(_ countryCode: String) -> String {
    let scalars = countryCode.uppercased().unicodeScalars
    guard scalars.count == 2, scalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return "" }
    return String(String.UnicodeScalarView(scalars.compactMap {
        UnicodeScalar(127397 + $0.value)
    }))
}

private func normalizedStorefront(_ countryCode: String?) -> String? {
    guard let countryCode else { return nil }
    let trimmed = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed.count == 2 ? trimmed : nil
}

private func activeCityTitle(_ stop: PoplurTourStop) -> String {
    "\(stop.cityName) \(countryFlagEmoji(stop.storefront))"
}

private struct ESPNSportsFeed {
    let leagueName: String
    let url: URL
}

private let PoplurSportsScoreboardFeeds: [ESPNSportsFeed] = [
    ESPNSportsFeed(leagueName: "NBA", url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard")!),
    ESPNSportsFeed(leagueName: "NHL", url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard")!),
    ESPNSportsFeed(leagueName: "MLB", url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard")!),
    ESPNSportsFeed(leagueName: "NFL", url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard")!),
    ESPNSportsFeed(leagueName: "MLS", url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/usa.1/scoreboard")!),
    ESPNSportsFeed(leagueName: "Premier League", url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/scoreboard")!)
]

private struct ESPNScoreboardResponse: Decodable {
    let events: [ESPNEvent]?
}

private struct ESPNEvent: Decodable {
    let id: String?
    let name: String?
    let shortName: String?
    let status: ESPNStatus?
    let competitions: [ESPNCompetition]?
}

private struct ESPNStatus: Decodable {
    let type: ESPNStatusType?
    let displayClock: String?
}

private struct ESPNStatusType: Decodable {
    let state: String?
    let detail: String?
    let shortDetail: String?
    let completed: Bool?
}

private struct ESPNCompetition: Decodable {
    let venue: ESPNVenue?
    let competitors: [ESPNCompetitor]?
}

private struct ESPNVenue: Decodable {
    let fullName: String?
    let address: ESPNVenueAddress?
}

private struct ESPNVenueAddress: Decodable {
    let city: String?
    let state: String?
    let country: String?
}

private struct ESPNCompetitor: Decodable {
    let homeAway: String?
    let score: String?
    let team: ESPNTeam?
}

private struct ESPNTeam: Decodable {
    let displayName: String?
    let shortDisplayName: String?
    let abbreviation: String?
    let location: String?
}

private enum PoplurLiveTourMomentResolver {
    static func moment(for stop: PoplurTourStop) async -> PoplurLiveTourMoment? {
        if let sportsMoment = await liveSportsMoment(for: stop) {
            return sportsMoment
        }
        return shoppingSaleMoment(for: stop)
    }

    static func liveSportsMoment(for stop: PoplurTourStop) async -> PoplurLiveTourMoment? {
        guard PoplurSportsVenueCatalog[stop.cityName]?.isEmpty == false else { return nil }

        for feed in PoplurSportsScoreboardFeeds {
            guard let scoreboard = try? await fetchScoreboard(from: feed.url) else { continue }
            for event in scoreboard.events ?? [] {
                guard event.isLiveGame,
                      let competition = event.competitions?.first,
                      let venue = matchingVenue(for: stop, event: event, competition: competition)
                else { continue }

                let score = scoreLine(for: competition)
                let statusText = event.status?.type?.shortDetail
                    ?? event.status?.type?.detail
                    ?? event.status?.displayClock
                    ?? "Live"
                let matchup = event.shortName ?? event.name ?? feed.leagueName
                let subtitle = "LIVE \(feed.leagueName): \(score) - \(statusText). Tuning into \(stop.cityName) game radio."

                return PoplurLiveTourMoment(
                    id: "sports-\(feed.leagueName)-\(event.id ?? matchup)-\(venue.name)",
                    kind: .sports,
                    title: venue.name,
                    subtitle: subtitle,
                    coordinate: venue.coordinate,
                    bearing: venue.bearing,
                    radiusMeters: min(max(stop.radiusMeters * 0.45, 35_000), 75_000),
                    distance: max(520, min(stop.distance, 820)),
                    category: .sports
                )
            }
        }

        return nil
    }

    private static func fetchScoreboard(from url: URL) async throws -> ESPNScoreboardResponse {
        var request = URLRequest(url: url, timeoutInterval: 4.5)
        request.setValue("Poplur2025-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(ESPNScoreboardResponse.self, from: data)
    }

    private static func matchingVenue(for stop: PoplurTourStop, event: ESPNEvent, competition: ESPNCompetition) -> SportsVenue? {
        let knownVenues = PoplurSportsVenueCatalog[stop.cityName] ?? []
        let venueName = competition.venue?.fullName ?? ""
        let normalizedVenueName = normalizedTourText(venueName)

        if let exactVenue = knownVenues.first(where: { venue in
            let knownName = normalizedTourText(venue.name)
            return !knownName.isEmpty && (normalizedVenueName.contains(knownName) || knownName.contains(normalizedVenueName))
        }) {
            return exactVenue
        }

        let venueCity = normalizedTourText(competition.venue?.address?.city ?? "")
        let stopCity = normalizedTourText(stop.cityName)
        if !venueCity.isEmpty, venueCity == stopCity || venueCity.contains(stopCity) || stopCity.contains(venueCity) {
            return knownVenues.first
        }

        let searchableTeams = (competition.competitors ?? [])
            .flatMap { [$0.team?.location, $0.team?.displayName, $0.team?.shortDisplayName] }
            .compactMap { $0 }
            .joined(separator: " ")
        let eventText = normalizedTourText("\(event.name ?? "") \(event.shortName ?? "") \(searchableTeams)")
        guard eventText.contains(stopCity) else { return nil }
        return knownVenues.first
    }

    private static func scoreLine(for competition: ESPNCompetition) -> String {
        let competitors = competition.competitors ?? []
        let away = competitors.first { $0.homeAway?.lowercased() == "away" } ?? competitors.first
        let home = competitors.first { $0.homeAway?.lowercased() == "home" } ?? competitors.dropFirst().first

        func label(_ competitor: ESPNCompetitor?) -> String {
            competitor?.team?.abbreviation
                ?? competitor?.team?.shortDisplayName
                ?? competitor?.team?.displayName
                ?? "TEAM"
        }

        func score(_ competitor: ESPNCompetitor?) -> String {
            let trimmed = competitor?.score?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "0" : trimmed
        }

        return "\(label(away)) \(score(away)) - \(label(home)) \(score(home))"
    }

    static func shoppingSaleMoment(for stop: PoplurTourStop) -> PoplurLiveTourMoment? {
        guard let venues = PoplurShoppingSaleCatalog[stop.cityName], !venues.isEmpty else { return nil }
        let saleBucket = Int(Date().timeIntervalSince1970 / 10_800)
        let index = stableTourSeed(parts: stop.cityName, "shopping", "\(saleBucket)") % venues.count
        let venue = venues[index]
        return PoplurLiveTourMoment(
            id: "shopping-\(stop.cityName)-\(venue.name)-\(saleBucket)",
            kind: .shopping,
            title: venue.name,
            subtitle: "SALE: \(venue.sale)",
            coordinate: venue.coordinate,
            bearing: venue.bearing,
            radiusMeters: min(max(stop.radiusMeters * 0.32, 22_000), 58_000),
            distance: max(520, min(stop.distance, 760)),
            category: .clothes
        )
    }
}

private extension ESPNEvent {
    var isLiveGame: Bool {
        let state = status?.type?.state?.lowercased() ?? ""
        guard state == "in" else { return false }
        return status?.type?.completed != true
    }
}

private func normalizedTourText(_ text: String) -> String {
    text
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

private func spoofAiTourInsight(for stop: PoplurTourStop) -> AiTourInsight {
    let now = Int(Date().timeIntervalSince1970 * 1000)
    let sportsCities: Set<String> = ["New York", "Los Angeles", "Chicago", "Toronto", "London", "Tokyo", "Sydney", "Miami"]
    if sportsCities.contains(stop.cityName), stableTourSeed(parts: stop.cityName, "\(now)") % 3 == 0 {
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

private func stableTourSeed(parts: String...) -> Int {
    var value: UInt64 = 14_695_981_039_346_656_037
    for part in parts {
        for byte in part.utf8 {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
    }
    return Int(value % 1_000_000)
}

private func trendChannelObject(category: TrendCategory, seed: Int) -> (channelId: String, objectId: String) {
    let channelId: String
    let options: [String]

    switch category {
    case .food:
        channelId = "food"
        options = ["banana", "cake", "fruit"]
    case .sports:
        channelId = "sports"
        options = ["ball", "trophy", "dumbbell"]
    case .clothes:
        channelId = "fashion"
        options = ["dress", "shoe", "bag"]
    case .nightlife:
        channelId = "music"
        options = ["sparkle", "spotlight", "microphone"]
    case .music:
        channelId = "music"
        options = ["microphone", "note", "speaker"]
    case .travel:
        channelId = "news"
        options = ["globe", "eiffel", "camera"]
    }

    return (channelId, options[abs(seed) % options.count])
}

private func buildTrendPopObjects(stop: PoplurTourStop, insight: AiTourInsight) -> [TrendPopObject] {
    let seed = stableTourSeed(parts: stop.cityName, insight.id, insight.category.rawValue)
    let count = trendPopCountMin + seed % trendPopCountRange
    let lngScale = 0.0048
    let latScale = 0.0036

    return (0..<count).map { index in
        let angle = 2.0 * Double.pi * Double(index) / Double(count) + Double(seed % 360) * Double.pi / 180.0
        let radius = 0.36 + Double((index * 29 + seed) % 100) / 145.0
        let objectSeed = (seed + index * 97) % 1_000_000
        let channelObject = trendChannelObject(category: insight.category, seed: objectSeed)
        return TrendPopObject(
            coordinate: CLLocationCoordinate2D(
                latitude: stop.coordinate.latitude + sin(angle) * latScale * radius,
                longitude: stop.coordinate.longitude + cos(angle) * lngScale * radius
            ),
            channelId: channelObject.channelId,
            objectId: channelObject.objectId,
            scale: 0.9 + CGFloat((index * 17 + seed) % 28) / 100.0,
            delay: Double(index) * 0.26,
            seed: objectSeed
        )
    }
}

private func buildTrendPopObjects(center: CLLocationCoordinate2D, cityName: String, insight: AiTourInsight) -> [TrendPopObject] {
    let seed = stableTourSeed(parts: cityName, insight.id, insight.category.rawValue)
    let count = 12 + seed % 7
    let lngScale = 0.0032
    let latScale = 0.0025

    return (0..<count).map { index in
        let angle = 2.0 * Double.pi * Double(index) / Double(count) + Double(seed % 180) * Double.pi / 180.0
        let radius = 0.34 + Double((index * 31 + seed) % 120) / 145.0
        let objectSeed = (seed + index * 83) % 1_000_000
        let channelObject = trendChannelObject(category: insight.category, seed: objectSeed)
        return TrendPopObject(
            coordinate: CLLocationCoordinate2D(
                latitude: center.latitude + sin(angle) * latScale * radius,
                longitude: center.longitude + cos(angle) * lngScale * radius
            ),
            channelId: channelObject.channelId,
            objectId: channelObject.objectId,
            scale: 0.92 + CGFloat((index * 13 + seed) % 30) / 100.0,
            delay: Double(index) * 0.1,
            seed: objectSeed
        )
    }
}

private func makeLocalTrendInsight(for cityName: String) -> AiTourInsight {
    let now = Int(Date().timeIntervalSince1970 / 900)
    let options: [AiTourInsight] = [
        AiTourInsight(id: "\(cityName)-food-\(now)", subtitle: "Trending nearby: food spots, cafe runs, and table shots.", category: .food),
        AiTourInsight(id: "\(cityName)-clothes-\(now)", subtitle: "Trending nearby: fit checks, sneakers, and streetwear drops.", category: .clothes),
        AiTourInsight(id: "\(cityName)-sports-\(now)", subtitle: "Trending nearby: sports clips, pickup games, and fan reactions.", category: .sports),
        AiTourInsight(id: "\(cityName)-music-\(now)", subtitle: "Trending nearby: music posts, car audio, and live moments.", category: .music),
        AiTourInsight(id: "\(cityName)-travel-\(now)", subtitle: "Trending nearby: neighborhood views, landmarks, and arrival shots.", category: .travel)
    ]
    let index = stableTourSeed(parts: cityName, "\(now)") % options.count
    return options[index]
}

@MainActor
private final class RainAmbientAudioService: ObservableObject {
    private var player: AVAudioPlayer?
    private var targetVolume: Float = 0
    private var isDuckedForVoice = false

    func update(for weatherState: WeatherVisualizationState) {
        switch weatherState.kind {
        case .rain, .thunderstorms:
            play(volume: rainVolume(for: weatherState))
        case .cloudy, .snow:
            stop()
        }
    }

    func play(volume: Float) {
        targetVolume = volume
        let mixedVolume = outputVolume(for: volume)
        if let player, player.isPlaying {
            player.setVolume(mixedVolume, fadeDuration: PoplurAudioMix.rainFadeDuration)
            return
        }
        do {
            let url = try rainLoopURL()
            try configureAudioSession()
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            if !player.play() {
                print("[RainAmbientAudio] AVAudioPlayer refused to start")
            }
            player.setVolume(mixedVolume, fadeDuration: PoplurAudioMix.rainFadeDuration)
            self.player = player
        } catch {
            print("[RainAmbientAudio] Failed to start rain audio: \(error)")
        }
    }

    func setVoiceDucked(_ ducked: Bool) {
        isDuckedForVoice = ducked
        player?.setVolume(
            outputVolume(for: targetVolume),
            fadeDuration: ducked ? PoplurAudioMix.rainVoiceDuckDuration : PoplurAudioMix.rainFadeDuration
        )
    }

    private func rainVolume(for state: WeatherVisualizationState) -> Float {
        let clampedIntensity = max(0, min(1, state.intensity))
        let baseVolume = state.kind == .thunderstorms ? 0.18 : 0.14
        return Float(min(0.28, baseVolume + clampedIntensity * 0.08))
    }

    private func outputVolume(for volume: Float) -> Float {
        isDuckedForVoice ? volume * PoplurAudioMix.rainDuckMultiplier : volume
    }

    func stop() {
        targetVolume = 0
        let stoppingPlayer = player
        stoppingPlayer?.fadeOutAndStop(duration: 0.65)
        player = nil
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true, options: [])
    }

    private func rainLoopURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poplur-rain-ambient-v4-background.wav")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let sampleRate = 22_050
        let durationSeconds = 3
        let sampleCount = sampleRate * durationSeconds
        var data = Data()

        func appendUInt16(_ value: UInt16) {
            var littleEndian = value.littleEndian
            data.append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
        }

        func appendUInt32(_ value: UInt32) {
            var littleEndian = value.littleEndian
            data.append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
        }

        data.append("RIFF".data(using: .ascii)!)
        appendUInt32(UInt32(36 + sampleCount * 2))
        data.append("WAVEfmt ".data(using: .ascii)!)
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        data.append("data".data(using: .ascii)!)
        appendUInt32(UInt32(sampleCount * 2))

        var seed: UInt64 = 0xD00D_CA7E
        var lowPass = 0.0
        var darkerPass = 0.0
        for index in 0..<sampleCount {
            seed = 6364136223846793005 &* seed &+ 1
            let raw = Double((seed >> 33) & 0x7fff_ffff) / Double(Int32.max)
            let white = raw * 2.0 - 1.0
            lowPass = lowPass * 0.94 + white * 0.06
            darkerPass = darkerPass * 0.985 + lowPass * 0.015
            let softenedHighs = white * 0.035
            let body = darkerPass * 0.86 + lowPass * 0.28
            let shimmer = sin(Double(index) * 0.006) * 0.018
            let sample = max(-1.0, min(1.0, body + softenedHighs + shimmer))
            var pcm = Int16(sample * Double(Int16.max) * 0.22).littleEndian
            data.append(Data(bytes: &pcm, count: MemoryLayout<Int16>.size))
        }

        try data.write(to: url, options: .atomic)
        return url
    }
}

private extension AVAudioPlayer {
    func fadeOutAndStop(duration: TimeInterval = 0.35) {
        setVolume(0, fadeDuration: duration)
        let player = self
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
            player.stop()
        }
    }
}

@MainActor
private final class CityTourMusicPlayerService: ObservableObject {
    @Published private(set) var currentTrackTitle: String?
    private let previewOnly: Bool
    private var player: AVPlayer?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playerEndObserver: NSObjectProtocol?
    private var playbackFallbackTask: Task<Void, Never>?
    private var activeTracks: [CityMusicTrack] = []
    private var activeTrackIndex = 0
    private var chartTrackCache: [String: [CityMusicTrack]] = [:]
    private var radioTrackCache: [String: [CityMusicTrack]] = [:]
    private var sportsRadioTrackCache: [String: [CityMusicTrack]] = [:]
    private var loadTask: Task<Void, Never>?
    private var volumeFadeTask: Task<Void, Never>?
    private var lastPlayerVolume: Float = PoplurAudioMix.musicFullVolume
    private var activeStopID: String?
    private var preparingStopID: String?
    private var isPreparingPlayback = false
    private var interruptionObserver: NSObjectProtocol?

    var isPlaybackActive: Bool {
        if isPreparingPlayback { return true }
        guard let player else { return false }
        return player.timeControlStatus == .playing || player.rate != 0
    }

    init(previewOnly: Bool = false) {
        self.previewOnly = previewOnly
        guard !previewOnly else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioSessionInterruption(notification)
            }
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    func play(for stop: PoplurTourStop, insight: AiTourInsight?, preferPreviewTracks: Bool = false, fadeIn: Bool = true) {
        guard !previewOnly else { return }
        let stopID = stop.id
        guard activeStopID != stopID || !isPlaybackActive else { return }
        guard preparingStopID != stopID else { return }

        configureCallFriendlyAudioSession()
        loadTask?.cancel()
        playbackFallbackTask?.cancel()
        isPreparingPlayback = true
        preparingStopID = stopID
        activeStopID = stopID
        loadTask = Task { [weak self] in
            guard let self else { return }
            let tracks = await self.resolveTrackQueue(for: stop, insight: insight, preferPreviewTracks: preferPreviewTracks)
            guard !Task.isCancelled, !tracks.isEmpty else { return }
            await MainActor.run {
                guard self.preparingStopID == stopID else { return }
                self.isPreparingPlayback = false
                self.preparingStopID = nil
                self.startPlayback(tracks: tracks, index: 0, fadeIn: fadeIn)
            }
        }
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        volumeFadeTask?.cancel()
        volumeFadeTask = nil
        playbackFallbackTask?.cancel()
        playbackFallbackTask = nil
        activeStopID = nil
        preparingStopID = nil
        isPreparingPlayback = false
        clearPlaybackObservers()
        activeTracks = []
        activeTrackIndex = 0
        player?.pause()
        player = nil
        currentTrackTitle = nil
    }

    func duckForRadio() {
        lastPlayerVolume = 0.10
        fadePlayerVolume(to: PoplurAudioMix.voiceDuckVolume, duration: PoplurAudioMix.musicDuckDuration)
    }

    func unduckAfterRadio() {
        lastPlayerVolume = PoplurAudioMix.musicFullVolume
        // AVSpeechSynthesizer can interrupt AVPlayer even with .mixWithOthers; the interruption
        // handler only resumes if shouldResume is set (often absent for TTS). Force-resume here.
        if let p = player, p.rate == 0, p.currentItem?.status == .readyToPlay {
            p.play()
        }
        fadePlayerVolume(to: PoplurAudioMix.musicFullVolume, duration: PoplurAudioMix.musicUnduckDuration)
    }

    private func startPlayback(tracks: [CityMusicTrack], index: Int, fadeIn: Bool = true) {
        guard tracks.indices.contains(index) else { return }
        let track = tracks[index]
        guard let url = URL(string: track.assetURI) else {
            startPlayback(tracks: tracks, index: index + 1, fadeIn: fadeIn)
            return
        }

        playbackFallbackTask?.cancel()
        volumeFadeTask?.cancel()
        clearPlaybackObservers()
        // Silence the old player before releasing it to prevent an audible pop/click
        let previousPlayer = player
        previousPlayer?.volume = 0
        previousPlayer?.pause()

        activeTracks = tracks
        activeTrackIndex = index

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.volume = fadeIn ? 0 : lastPlayerVolume
        newPlayer.isMuted = false
        // Keep default stalling behaviour (true) so streaming URLs buffer properly
        player = newPlayer
        currentTrackTitle = track.artistSeed

        playerItemStatusObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] observedItem, _ in
            Task { @MainActor in
                guard
                    let self,
                    let item,
                    self.player?.currentItem === item
                else { return }

                switch observedItem.status {
                case .readyToPlay:
                    self.player?.play()
                    self.fadePlayerVolume(to: self.lastPlayerVolume, duration: fadeIn ? PoplurAudioMix.musicFadeDuration : 0.2)
                case .failed:
                    print("[MapTourAudio] Failed to play \(track.assetURI): \(observedItem.error?.localizedDescription ?? "unknown error")")
                    self.playNextTrack(fadeIn: fadeIn)
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        playerEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.playNextTrack(loopAtEnd: false, fadeIn: true)
            }
        }

        newPlayer.play()
        playbackFallbackTask = Task { [weak self, weak item] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard
                    let self,
                    let item,
                    self.player?.currentItem === item,
                    item.status != .readyToPlay || self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
                else { return }
                print("[MapTourAudio] Playback did not become audible quickly; trying next source")
                self.playNextTrack(fadeIn: fadeIn)
            }
        }
    }

    private func playNextTrack(loopAtEnd: Bool = false, fadeIn: Bool = true) {
        let nextIndex = activeTrackIndex + 1
        if activeTracks.indices.contains(nextIndex) {
            startPlayback(tracks: activeTracks, index: nextIndex, fadeIn: fadeIn)
        } else if loopAtEnd, !activeTracks.isEmpty {
            startPlayback(tracks: activeTracks, index: 0, fadeIn: fadeIn)
        } else {
            clearPlaybackObservers()
            player?.pause()
            player = nil
            currentTrackTitle = nil
            activeTracks = []
            activeTrackIndex = 0
            activeStopID = nil
        }
    }

    private func fadePlayerVolume(to targetVolume: Float, duration: TimeInterval) {
        guard let player else { return }
        volumeFadeTask?.cancel()
        let startVolume = player.volume
        let steps = max(1, Int(duration * 30))
        volumeFadeTask = Task { [weak self, weak player] in
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let progress = Float(step) / Float(steps)
                await MainActor.run {
                    guard let self, let player, self.player === player else { return }
                    player.volume = startVolume + (targetVolume - startVolume) * progress
                }
                try? await Task.sleep(nanoseconds: UInt64((duration / Double(steps)) * 1_000_000_000))
            }
        }
    }

    private func clearPlaybackObservers() {
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        if let playerEndObserver {
            NotificationCenter.default.removeObserver(playerEndObserver)
            self.playerEndObserver = nil
        }
    }

    private func configureCallFriendlyAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            print("[MapTourAudio] Call-friendly audio session setup failed: \(error)")
        }
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            player?.pause()
        case .ended:
            configureCallFriendlyAudioSession()
            if let rawOptions = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                if options.contains(.shouldResume) {
                    player?.play()
                }
            }
        @unknown default:
            break
        }
    }

    private func resolveTrackQueue(for stop: PoplurTourStop, insight: AiTourInsight?, preferPreviewTracks: Bool) async -> [CityMusicTrack] {
        async let chartTracks = cachedChartTracks(for: stop)
        async let radioTracks = cachedRadioTracks(for: stop)
        async let sportsTracks = cachedSportsTracks(for: stop)

        let resolvedChartTracks = await chartTracks
        let resolvedRadioTracks = await radioTracks
        let resolvedSportsTracks = await sportsTracks

        var tracks: [CityMusicTrack] = []
        if insight?.category == .sports {
            tracks.append(contentsOf: resolvedSportsTracks)
        }
        if preferPreviewTracks {
            tracks.append(contentsOf: resolvedChartTracks)
            tracks.append(contentsOf: resolvedRadioTracks)
        } else {
            tracks.append(contentsOf: resolvedRadioTracks)
            tracks.append(contentsOf: resolvedChartTracks)
        }
        if let fallback = FallbackCityMusicTracks[stop.cityName] {
            tracks.append(fallback)
        }
        tracks.append(DefaultFallbackCityMusicTrack)
        return tracks.uniquedByAssetURI()
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
        guard streamURL.lowercased().hasPrefix("https://"), !name.isEmpty else { return nil }
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
        let activeFrame = ((frame % 3) + 3) % 3
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                ArcShape(startAngle: .degrees(-54), endAngle: .degrees(54))
                    .stroke(index == activeFrame ? Color.white : tint.opacity(0.75), style: StrokeStyle(lineWidth: CGFloat(5 + index * 2), lineCap: .round))
                    .frame(width: CGFloat(30 + index * 22), height: CGFloat(42 + index * 24))
                    .opacity(index == activeFrame ? 1 : 0.55)
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
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            return path
        }

        let radius = min(rect.width, rect.height) / 2
        guard radius.isFinite, radius > 0 else {
            return path
        }

        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
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
    @State private var startDate = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(startDate) - object.delay)
            let popPhase = min(max(elapsed / 0.42, 0), 1)
            let seedOffset = Double(object.seed * 157)
            let bobPhase = (timeline.date.timeIntervalSinceReferenceDate * 1000 + seedOffset) / 520.0
            let popScale = overshootScale(popPhase) * object.scale * (1 + CGFloat(object.seed % 7) * 0.01)
            let bob = CGFloat(sin(bobPhase) * 3.0)

            ZStack {
                TrendObjectConfetti(seed: object.seed, elapsed: elapsed)
                ChannelObjectSceneView(channelId: object.channelId, objectId: object.objectId)
                    .frame(width: 92, height: 92)
                    .scaleEffect(popScale)
                    .offset(y: bob)
                    .opacity(popPhase <= 0 ? 0 : 1)
                    .shadow(color: category.tint.opacity(0.50), radius: 14, x: 0, y: 0)
            }
            .frame(width: 132, height: 132)
        }
        .onAppear { startDate = Date() }
        .accessibilityHidden(true)
    }

    private func overshootScale(_ phase: Double) -> CGFloat {
        guard phase > 0 else { return 0 }
        guard phase < 1 else { return 1 }
        let eased = 1 - pow(1 - phase, 3)
        return CGFloat(eased + sin(phase * .pi) * 0.18)
    }
}

private struct TrendObjectConfetti: View {
    let seed: Int
    let elapsed: TimeInterval

    private let duration: TimeInterval = 0.74

    var body: some View {
        let phase = min(max(elapsed / duration, 0), 1)
        ZStack {
            ForEach(0..<14, id: \.self) { index in
                let angle = Double(seed) * 0.017 + Double(index) * 0.92
                let distance = (34.0 + Double(index % 5) * 11.0) * phase
                let x = cos(angle) * distance
                let y = -34.0 + sin(angle) * distance + phase * phase * 44.0

                RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                    .fill(confettiColor(index).opacity(phase < 1 ? 1 - phase : 0))
                    .frame(width: 8, height: 14)
                    .rotationEffect(.degrees(Double(index) * 31 + phase * 220))
                    .offset(x: x, y: y)
            }
        }
        .opacity(elapsed < duration ? 1 : 0)
    }

    private func confettiColor(_ index: Int) -> Color {
        switch abs(seed + index) % 6 {
        case 0: return Color(red: 1.0, green: 0.29, blue: 0.68)
        case 1: return Color(red: 1.0, green: 0.83, blue: 0.27)
        case 2: return Color(red: 0.35, green: 0.92, blue: 1.0)
        case 3: return Color(red: 0.44, green: 1.0, blue: 0.56)
        case 4: return Color(red: 0.67, green: 0.46, blue: 1.0)
        default: return .white
        }
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
        .overlay {
            if showPlacesList {
                Color.black.opacity(0.58)
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        PlacesListView(places: tourPlaces) { place in
                            showPlacesList = false
                            NotificationCenter.default.post(name: .preview_stopDominanceTour, object: nil)
                            NotificationCenter.default.post(
                                name: Notification.Name("JumpToPlace"),
                                object: nil,
                                userInfo: ["coordinate": place.coordinate]
                            )
                        }
                        .frame(maxHeight: 520)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                    }
                    .transition(.opacity)
                    .zIndex(50)
            }

            if showAddressSearch {
                Color.black.opacity(0.58)
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
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
                        .frame(maxHeight: 520)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                    }
                    .transition(.opacity)
                    .zIndex(51)
            }
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

/// Back button for sub-screens pushed inside the cube-hold NavigationStack.
/// Hides the system nav bar and shows a single ← chevron that calls dismiss().
private struct CubeMenuBackButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct MapRadioSearchChecklistView: View {
    @Binding var query: String
    @Binding var results: [MKMapItem]
    @Binding var isSearching: Bool
    @Binding var selectedTopics: Set<PoplurRadioTopic>
    let isTouring: Bool
    let radioScript: String
    let onClose: () -> Void
    let onSelectSearchResult: (MKMapItem) -> Void
    let onToggleTour: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Search Menu")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                    Text("Choose what Poplur Radio should cover.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                TextField("Search city, mall, campus, arena...", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.words)
                    .onSubmit(performSearch)

                Button(action: performSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .black))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.borderedProminent)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }

            if isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Searching")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else if !results.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(results.prefix(5), id: \.self) { item in
                            Button {
                                onSelectSearchResult(item)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundStyle(.indigo)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "Unknown place")
                                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                                            .foregroundStyle(.primary)
                                        if let title = item.placemark.title {
                                            Text(title)
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 168)
            }

            Divider()

            Text("Poplur Radio Checklist")
                .font(.system(size: 16, weight: .black, design: .rounded))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(PoplurRadioTopic.allCases) { topic in
                    Button {
                        toggle(topic)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selectedTopics.contains(topic) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(selectedTopics.contains(topic) ? topic.trendCategory.tint : .secondary)
                            Image(systemName: topic.symbolName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(topic.trendCategory.tint)
                            Text(topic.title)
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(Color.black.opacity(selectedTopics.contains(topic) ? 0.075 : 0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(radioScript)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Button(action: onToggleTour) {
                Label(isTouring ? "Stop Tour" : "Start Tour", systemImage: isTouring ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)
        }
        .padding(16)
    }

    private func toggle(_ topic: PoplurRadioTopic) {
        if selectedTopics.contains(topic) {
            selectedTopics.remove(topic)
        } else {
            selectedTopics.insert(topic)
        }
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        results = []

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        MKLocalSearch(request: request).start { response, _ in
            results = response?.mapItems ?? []
            isSearching = false
        }
    }
}

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
private struct CubeHoldSearchOverlay_UNUSED: View {
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
    @Environment(\.layoutPreviewMode) private var layoutPreviewMode

    @StateObject private var locationManager = LocationProvider()
    @StateObject private var flowManager = CaptureFlowManager.shared
    @StateObject private var mapState = MapStateManager.shared
    @StateObject private var musicPlayer: CityTourMusicPlayerService
    @ObservedObject private var mapRadioHost = PoplurMapRadioHost.shared

    @AppStorage("poplur_use2DMap") private var use2DMap: Bool = false
    private var activePitch: CGFloat { use2DMap ? 0 : fixedPitchAlt }

    @State private var fixedDistanceAlt: CLLocationDistance = 700 // Start at optimal viewing distance (700m)
    @State private var camera: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // SF default, will update to user location
            distance: 700,  // Start at 700m (optimal viewing distance)
            heading: 0,
            pitch: 60
        )
    )
    
    @State private var currentCity: String = "Current Location"
    @State private var aiRecommendation: String = "Finding what is trending where you are..."
    @State private var showPlacesList: Bool = false
    @State private var showAddressSearch: Bool = false
    @StateObject private var mapCubeMenuWheel = CubeMenuWheelController()
    @State private var searchQuery: String = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching: Bool = false
    @State private var selectedRadioTopics: Set<PoplurRadioTopic> = Set(PoplurRadioTopic.allCases.filter(\.defaultEnabled))
    @State private var clickedCoordinate: CLLocationCoordinate2D? = nil  // Track clicked coordinate
    @State private var showPostPrompt: Bool = false  // Show "Post Here?" prompt
    @State private var isPoplurAIPostMode: Bool = false
    @State private var isInitialMapLaunchPreparing: Bool
    @State private var isInitialMapLaunchActive: Bool = false
    @State private var mapLaunchTask: Task<Void, Never>? = nil
    
    @State private var posts: [MapAnnotationPost] = []
    @State private var dominance: [CityDominance] = []
    @State private var radiusMeters: Double = 5_000
    
    @State private var currentTourIndex: Int = Int.random(in: 0..<PoplurTourStops.count)
    @State private var tourZoomOutDistance: CLLocationDistance = 25_000_000 // Distance for zoom out
    @State private var isZoomedOut: Bool = false
    @State private var hasSetInitialLocation: Bool = false  // Track if we've set initial location
    @State private var activeTourStop: PoplurTourStop? = nil
    @State private var activeTourInsight: AiTourInsight? = nil
    @State private var activeTourMoment: PoplurLiveTourMoment? = nil
    @State private var localTrendInsight: AiTourInsight? = nil
    @State private var trendPopObjects: [TrendPopObject] = []
    @State private var musicWaveFrame: Int = 0
    @State private var showTourNowPlayingText: Bool = true
    @State private var currentLocationMusicStopID: String? = nil
    @State private var locationContextTask: Task<Void, Never>? = nil
    @State private var liveUserCoordinate: CLLocationCoordinate2D? = nil
    @State private var lastUserCenterRequestAt: Date = .distantPast
    @State private var lastContextRefreshLocation: CLLocation? = nil
    @State private var isCameraTransitionInProgress: Bool = false

    private let mapZoomSliderHeight: CGFloat = 400
    private let mapLeftOverlayPadding: CGFloat = 28
    
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
    @State private var showIndoorMap: Bool = false
    @State private var indoorVenues: [MappedinVenue] = []
    @State private var selectedVenueSlug: String? = nil
    
    // Weather overlay state
    @State private var weatherState = WeatherVisualizationState(
        kind: .rain,
        intensity: 0.5,
        lightningFrequency: 0.3,
        temperatureFahrenheit: 72
    )
    @StateObject private var rainAmbientAudio = RainAmbientAudioService()
    
    // Available in both Debug and Release for tour functionality
    let tourPlaces: [(name: String, coordinate: CLLocationCoordinate2D, description: String)] = PoplurTourStops.map {
        ($0.cityName, $0.coordinate, $0.description)
    }
    
    init(layoutPreviewOnly: Bool = false) {
        _musicPlayer = StateObject(wrappedValue: CityTourMusicPlayerService(previewOnly: layoutPreviewOnly))
        _isInitialMapLaunchPreparing = State(initialValue: !layoutPreviewOnly && !MapStateManager.shared.hasRunFirstLaunchSequence)

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
                    pitch: activePitch
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
                    pitch: activePitch
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
        let targetDistance = fixedDistanceAlt
        print("   Current camera: \(currentCoord.latitude), \(currentCoord.longitude)")
        print("   Zoom out distance: \(tourZoomOutDistance)m")
        isCameraTransitionInProgress = true
        
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
                        distance: targetDistance,
                        heading: 0,
                        pitch: activePitch
                    )
                )
            }
            fixedDistanceAlt = targetDistance
            zoomLevel = targetDistance
            
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
            
            isCameraTransitionInProgress = false
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
                    pitch: activePitch
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

    private var mapRadioScript: String {
        let visiblePosts = filteredPosts()
        let cityName = [
            activeTourStop?.cityName,
            shownPostCityName,
            currentCity
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "your map"

        let insight = activeTourInsight ?? localTrendInsight
        let insightLine = insight?.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let momentLine = activeTourMoment.map { "\($0.title). \($0.subtitle)" }
        let headlinePost = visiblePosts.max { $0.radius < $1.radius }
        let radiusLine = headlinePost.map { "\($0.title) has the widest signal right now at \(mapRadioRadiusLabel($0.radius))." }
        let activityLine = visiblePosts.isEmpty
            ? "No public posts are inside your current filter yet, so we are watching for the first spark."
            : "We are tracking \(visiblePosts.count) visible \(visiblePosts.count == 1 ? "post" : "posts") around this map."
        let topics = selectedRadioTopics.isEmpty ? Set(PoplurRadioTopic.allCases.filter(\.defaultEnabled)) : selectedRadioTopics
        let topicLine = "On this tour, I am watching \(topics.map(\.shortTitle).sorted().joined(separator: ", "))."

        var lines = [
            "You are listening to Poplur Radio. I am Nova, riding with you over \(cityName).",
            topicLine,
            cleanMapRadioLine(momentLine ?? insightLine ?? aiRecommendation),
            activityLine
        ]

        if let radiusLine {
            lines.append(radiusLine)
        } else {
            lines.append("Your active radius is \(mapRadioRadiusLabel(radiusMeters)).")
        }

        lines.append("Keep the map open. If something useful pops off, I will take you there and talk you through it.")

        return lines
            .map(cleanMapRadioLine)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func mapRadioRadiusLabel(_ meters: Double) -> String {
        if meters >= 1_000 {
            let kilometers = meters / 1_000
            if kilometers >= 10 {
                return "\(Int(kilometers.rounded())) kilometers"
            }
            return String(format: "%.1f kilometers", kilometers)
        }
        return "\(Int(meters.rounded())) meters"
    }

    private func cleanMapRadioLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "📍", with: "")
            .replacingOccurrences(of: "🗺️", with: "")
            .replacingOccurrences(of: "✅", with: "")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func noteInteraction() {
        // Delegate to state manager
        mapState.noteUserInteraction()
    }

    private func clearTourEffects(stopAudio: Bool = true) {
        activeTourStop = nil
        activeTourInsight = nil
        activeTourMoment = nil
        trendPopObjects = []
        showTourNowPlayingText = true
        if stopAudio {
            musicPlayer.stop()
        }
    }
    
    private func startTour() {
        currentTourIndex = Int.random(in: 0..<PoplurTourStops.count)
        mapState.startTour()
    }
    
    private func stopTour() {
        mapState.stopTour()
        clearTourEffects()
    }

    private func beginPoplurAIMapPost(location: String?) {
        mapState.stopTour()
        clearTourEffects()
        mapCubeMenuWheel.endHold(activateSelected: false)
        isPostPlacementMode = false
        isPoplurAIPostMode = true
        showPostPrompt = false
        clickedCoordinate = nil
        postPlacementCoordinate = nil

        let trimmedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedLocation.isEmpty {
            currentCity = "Select Post Location"
            aiRecommendation = "Tap the map where you want to post, then choose Post Here"
        } else {
            currentCity = "Post to \(trimmedLocation)"
            aiRecommendation = "Pick a search result or tap the map, then choose Post Here"
            searchQuery = trimmedLocation
            searchResults = []
            showAddressSearch = true
        }
    }

    private func selectPoplurAIMapPostCoordinate(_ coordinate: CLLocationCoordinate2D) {
        isPoplurAIPostMode = true
        clickedCoordinate = coordinate
        showPostPrompt = true
        currentCity = "Location Selected"
        aiRecommendation = String(
            format: "%.4f, %.4f - choose Post Here to open the camera",
            coordinate.latitude,
            coordinate.longitude
        )
    }
    
    private func centerOnUserLocation() {
        // Respect lockToPost window
        if let until = lockToPostUntil, until > Date() {
            print("⛔️ [MapView] centerOnUserLocation ignored during lockToPost window")
            return
        }
        
        guard let userCoordinate = locationManager.location?.coordinate else { return }
        let now = Date()
        guard now.timeIntervalSince(lastUserCenterRequestAt) > 1.2 else {
            print("⏭️ [MapView] centerOnUserLocation ignored - duplicate request")
            return
        }
        lastUserCenterRequestAt = now

        if let currentCoordinate = camera.camera?.centerCoordinate,
           CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
            .distance(from: CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)) < 35 {
            print("⏭️ [MapView] centerOnUserLocation skipped - already centered")
            refreshLocalContext(for: CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude))
            return
        }
        
        // Stop any active operations and return to browsing
        mapState.cancelCurrentOperation()
        clearTourEffects()
        
        withAnimation(.easeInOut(duration: 0.55)) {
            camera = .camera(
                MapCamera(
                    centerCoordinate: userCoordinate,
                    distance: fixedDistanceAlt,
                    heading: camera.camera?.heading ?? 0,
                    pitch: activePitch
                )
            )
        }

        refreshLocalContext(for: CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude))
    }
    
    private func uploadPostToSelectedLocation() {
        guard let coordinate = postPlacementCoordinate else {
            print("[MapView] No coordinate selected for post placement")
            return
        }
        
        print("[MapView] Confirmed legacy post placement coordinate: \(coordinate.latitude), \(coordinate.longitude)")

        flowManager.startCameraToMapFlow(image: pendingPostImage, videoURL: pendingPostVideoURL)
        flowManager.confirmLocation(coordinate)

        NotificationCenter.default.post(
            name: .showPostCaptureEditor,
            object: nil,
            userInfo: [
                "image": pendingPostImage as Any,
                "videoURL": pendingPostVideoURL as Any,
                "latitude": coordinate.latitude,
                "longitude": coordinate.longitude
            ]
        )
        
        // Exit post placement mode
        isPostPlacementMode = false
        pendingPostImage = nil
        pendingPostVideoURL = nil
        postPlacementCoordinate = nil
        
        if let location = locationManager.location {
            refreshLocalContext(for: location)
        } else {
            aiRecommendation = "Choose a filter, trim if needed, then pick a channel"
        }
    }

    private func refreshLocalContext(for location: CLLocation) {
        locationContextTask?.cancel()
        locationContextTask = Task { @MainActor in
            let coordinate = location.coordinate
            let fallbackStop = nearestTourStop(to: coordinate)
            let fallbackName = fallbackStop?.cityName ?? "Current Location"
            let fallbackCountryCode = fallbackStop?.storefront
            let fallbackFlag = fallbackCountryCode.map(countryFlagEmoji) ?? ""
            applyLocalContext(cityName: fallbackName, countryFlag: fallbackFlag, countryCode: fallbackCountryCode, coordinate: coordinate)

            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                guard !Task.isCancelled, let placemark = placemarks.first else { return }

                let cityName = placemark.locality
                    ?? placemark.subAdministrativeArea
                    ?? placemark.administrativeArea
                    ?? fallbackName
                let countryCode = placemark.isoCountryCode ?? fallbackCountryCode
                let countryFlag = countryCode.map(countryFlagEmoji) ?? fallbackFlag
                applyLocalContext(cityName: cityName, countryFlag: countryFlag, countryCode: countryCode, coordinate: coordinate)
            } catch {
                print("[MapView] Reverse geocode failed: \(error)")
            }
        }
    }

    private func applyLocalContext(cityName: String, countryFlag: String, countryCode: String?, coordinate: CLLocationCoordinate2D) {
        guard !isInitialMapLaunchActive,
              !mapState.isInTourMode,
              !(flowManager.currentFlow?.isCameraFirst ?? false),
              !isPostPlacementMode else { return }

        let trimmedCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleCity = trimmedCity.isEmpty ? "Current Location" : trimmedCity
        currentCity = countryFlag.isEmpty ? titleCity : "\(titleCity) \(countryFlag)"

        let insight = makeLocalTrendInsight(for: titleCity)
        localTrendInsight = insight
        aiRecommendation = insight.subtitle
        trendPopObjects = buildTrendPopObjects(center: coordinate, cityName: titleCity, insight: insight)
        emitLocalTrendConfetti(center: coordinate, objects: trendPopObjects)
        playCurrentLocationMusicIfNeeded(cityName: titleCity, countryCode: countryCode, coordinate: coordinate, insight: insight)
    }

    private func playCurrentLocationMusicIfNeeded(cityName: String, countryCode: String?, coordinate: CLLocationCoordinate2D, insight: AiTourInsight?) {
        guard !mapState.isInTourMode else { return }
        let fallbackStorefront = nearestTourStop(to: coordinate)?.storefront
        let storefront = normalizedStorefront(countryCode) ?? fallbackStorefront ?? Locale.current.region?.identifier.lowercased() ?? "us"
        let stop = PoplurTourStop(
            cityName: cityName,
            storefront: storefront,
            coordinate: coordinate,
            bearing: camera.camera?.heading ?? 0,
            radiusMeters: radiusMeters,
            distance: max(850, fixedDistanceAlt),
            description: "Current location"
        )
        guard currentLocationMusicStopID != stop.id else { return }
        currentLocationMusicStopID = stop.id
        musicPlayer.play(for: stop, insight: insight, preferPreviewTracks: true)
    }

    private func ensureCurrentLocationMusicAfterLaunch(delayNanoseconds: UInt64 = 1_200_000_000) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !isInitialMapLaunchActive, !musicPlayer.isPlaybackActive else { return }
            guard !mapState.isInTourMode, !(flowManager.currentFlow?.isCameraFirst ?? false), !isPostPlacementMode else { return }
            guard lockToPostUntil == nil || lockToPostUntil! <= Date() else { return }

            if let location = locationManager.location {
                liveUserCoordinate = location.coordinate
                refreshLocalContext(for: location)
            } else {
                locationManager.request()
            }
        }
    }

    private func emitLocalTrendConfetti(center: CLLocationCoordinate2D, objects: [TrendPopObject]) {
        showConfetti = true
        trendingTracker.forceTrendingBurst(coordinate: center, intensity: 1.0)
        for object in objects.prefix(7) {
            trendingTracker.forceTrendingBurst(coordinate: object.coordinate, intensity: 0.85)
        }
    }

    private func nearestTourCityName(to coordinate: CLLocationCoordinate2D) -> String? {
        nearestTourStop(to: coordinate)?.cityName
    }

    private func nearestTourCountryFlag(to coordinate: CLLocationCoordinate2D) -> String {
        guard let stop = nearestTourStop(to: coordinate) else { return "" }
        return countryFlagEmoji(stop.storefront)
    }

    private func nearestTourStop(to coordinate: CLLocationCoordinate2D) -> PoplurTourStop? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return PoplurTourStops.min { lhs, rhs in
            let lhsLocation = CLLocation(latitude: lhs.coordinate.latitude, longitude: lhs.coordinate.longitude)
            let rhsLocation = CLLocation(latitude: rhs.coordinate.latitude, longitude: rhs.coordinate.longitude)
            return lhsLocation.distance(from: location) < rhsLocation.distance(from: location)
        }
    }

    private func enabledRadioTopics() -> [PoplurRadioTopic] {
        let topics = selectedRadioTopics.isEmpty ? Set(PoplurRadioTopic.allCases.filter(\.defaultEnabled)) : selectedRadioTopics
        return PoplurRadioTopic.allCases.filter { topics.contains($0) }
    }

    private func landmarkFocus(for stop: PoplurTourStop) -> PoplurTourFocus {
        PoplurTourFocus(
            topic: .downtown,
            title: activeCityTitle(stop),
            subtitle: "Starting at the main landmark: \(stop.description). I will use your checklist to decide where we go next.",
            coordinate: stop.coordinate,
            bearing: stop.bearing,
            radiusMeters: stop.radiusMeters,
            distance: stop.distance,
            category: .travel,
            liveMoment: nil
        )
    }

    private func tourFocuses(for stop: PoplurTourStop, topics: [PoplurRadioTopic]) async -> [PoplurTourFocus] {
        var focuses: [PoplurTourFocus] = []
        for topic in topics {
            if let focus = await tourFocus(for: topic, in: stop) {
                focuses.append(focus)
            }
        }
        return focuses
    }

    private func tourFocus(for topic: PoplurRadioTopic, in stop: PoplurTourStop) async -> PoplurTourFocus? {
        switch topic {
        case .malls:
            guard let moment = PoplurLiveTourMomentResolver.shoppingSaleMoment(for: stop) else { return nil }
            return focus(from: moment, topic: topic)
        case .stadiums:
            if let moment = await PoplurLiveTourMomentResolver.liveSportsMoment(for: stop) {
                return focus(from: moment, topic: topic)
            }
            guard let venue = PoplurSportsVenueCatalog[stop.cityName]?.first else { return nil }
            return PoplurTourFocus(
                topic: topic,
                title: venue.name,
                subtitle: "Checking the arena signal. Fan clips, game-day fits, and local sports chatter are usually strongest around here.",
                coordinate: venue.coordinate,
                bearing: venue.bearing,
                radiusMeters: min(max(stop.radiusMeters * 0.45, 35_000), 75_000),
                distance: max(520, min(stop.distance, 820)),
                category: .sports,
                liveMoment: nil
            )
        case .casinos:
            guard ["Las Vegas", "Singapore", "Dubai"].contains(stop.cityName) else { return nil }
            return syntheticFocus(topic, stop: stop, placeName: casinoName(for: stop), subtitle: "Casino and resort energy is active here: arrivals, nightlife, food, and big-room moments are the things to watch.")
        case .themeParks:
            guard ["Los Angeles", "Tokyo", "Paris", "Singapore", "Dubai"].contains(stop.cityName) else { return nil }
            return syntheticFocus(topic, stop: stop, placeName: themeParkName(for: stop), subtitle: "Theme park traffic is worth watching: ride waits, character moments, food drops, and crowd surges can move fast.")
        case .restaurants:
            return syntheticFocus(topic, stop: stop, placeName: "\(stop.cityName) food district", subtitle: "Restaurant and food court posts are heating up. I am watching for specials, packed rooms, and late plates.")
        case .universities:
            return syntheticFocus(topic, stop: stop, placeName: "\(stop.cityName) campus zone", subtitle: "Campus energy is on the checklist: student events, study spots, sports clips, and cafe traffic.")
        case .airports:
            return syntheticFocus(topic, stop: stop, placeName: "\(stop.cityName) airport corridor", subtitle: "Airport signal is on: arrivals, delays, travel posts, and terminal food are all fair game.")
        case .concerts:
            return syntheticFocus(topic, stop: stop, placeName: "\(stop.cityName) live music district", subtitle: "Concert venue watch is active. If doors open or crowds build, Poplur Radio will call it out.")
        case .downtown:
            return syntheticFocus(topic, stop: stop, placeName: "\(stop.cityName) downtown", subtitle: "Downtown district check: street clips, public squares, traffic, shopping, and nightlife all overlap here.")
        case .hotels:
            return syntheticFocus(topic, stop: stop, placeName: "\(stop.cityName) hotel row", subtitle: "Hotel and resort watch is on: arrivals, rooftop scenes, lobbies, pool decks, and weekend energy.")
        }
    }

    private func focus(from moment: PoplurLiveTourMoment, topic: PoplurRadioTopic) -> PoplurTourFocus {
        PoplurTourFocus(
            topic: topic,
            title: moment.title,
            subtitle: moment.subtitle,
            coordinate: moment.coordinate,
            bearing: moment.bearing,
            radiusMeters: moment.radiusMeters,
            distance: moment.distance,
            category: moment.category,
            liveMoment: moment
        )
    }

    private func syntheticFocus(_ topic: PoplurRadioTopic, stop: PoplurTourStop, placeName: String, subtitle: String) -> PoplurTourFocus {
        let coordinate = offsetCoordinate(from: stop.coordinate, topic: topic, cityName: stop.cityName)
        return PoplurTourFocus(
            topic: topic,
            title: placeName,
            subtitle: subtitle,
            coordinate: coordinate,
            bearing: stop.bearing + CLLocationDirection((stableTourSeed(parts: stop.cityName, topic.rawValue) % 70) - 35),
            radiusMeters: min(max(stop.radiusMeters * 0.36, 24_000), 68_000),
            distance: max(560, min(stop.distance, 840)),
            category: topic.trendCategory,
            liveMoment: nil
        )
    }

    private func offsetCoordinate(from coordinate: CLLocationCoordinate2D, topic: PoplurRadioTopic, cityName: String) -> CLLocationCoordinate2D {
        let seed = stableTourSeed(parts: cityName, topic.rawValue)
        let angle = Double(seed % 360) * .pi / 180
        let distanceDegrees = 0.018 + Double(seed % 11) * 0.002
        let latitude = coordinate.latitude + sin(angle) * distanceDegrees
        let longitudeScale = max(0.35, cos(coordinate.latitude * .pi / 180))
        let longitude = coordinate.longitude + cos(angle) * distanceDegrees / longitudeScale
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func casinoName(for stop: PoplurTourStop) -> String {
        switch stop.cityName {
        case "Las Vegas": return "Las Vegas Strip casinos"
        case "Singapore": return "Marina Bay casino district"
        case "Dubai": return "Dubai resort nightlife"
        default: return "\(stop.cityName) casino district"
        }
    }

    private func themeParkName(for stop: PoplurTourStop) -> String {
        switch stop.cityName {
        case "Los Angeles": return "Anaheim theme park corridor"
        case "Tokyo": return "Tokyo Disney Resort area"
        case "Paris": return "Disneyland Paris corridor"
        case "Singapore": return "Sentosa theme park district"
        case "Dubai": return "Dubai Parks corridor"
        default: return "\(stop.cityName) theme park district"
        }
    }

    private func runTourSubtitleLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                if mapState.isInTourMode, activeTourInsight != nil {
                    withAnimation(.easeInOut(duration: 0.38)) {
                        showTourNowPlayingText.toggle()
                    }
                } else if !showTourNowPlayingText {
                    showTourNowPlayingText = true
                }
            }
        }
    }
    
    private func runExtendedTourStop(_ stop: PoplurTourStop) async {
        guard mapState.isInTourMode else { return }
        let globeCoordinate = CLLocationCoordinate2D(latitude: 18.0, longitude: -98.0)
        let topics = await MainActor.run { enabledRadioTopics() }

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

        let topicFocuses = await tourFocuses(for: stop, topics: topics)
        let itinerary = [landmarkFocus(for: stop)] + topicFocuses

        for (index, focus) in itinerary.enumerated() {
            guard mapState.isInTourMode, !Task.isCancelled else { return }
            await runTourFocus(focus, cityStop: stop, index: index, total: itinerary.count)
            let dwell = index == 0 ? tourTopicDwellSeconds + 4 : tourTopicDwellSeconds
            try? await Task.sleep(nanoseconds: dwell * 1_000_000_000)
        }
    }

    private func runTourFocus(_ focus: PoplurTourFocus, cityStop: PoplurTourStop, index: Int, total: Int) async {
        let focusStop = PoplurTourStop(
            cityName: cityStop.cityName,
            storefront: cityStop.storefront,
            coordinate: focus.coordinate,
            bearing: focus.bearing,
            radiusMeters: focus.radiusMeters,
            distance: focus.distance,
            description: focus.title
        )
        let insight = AiTourInsight(
            id: focus.liveMoment?.id ?? "\(cityStop.cityName)-\(focus.topic.rawValue)-\(index)",
            subtitle: focus.subtitle,
            category: focus.category
        )

        await MainActor.run {
            activeTourStop = focusStop
            activeTourInsight = insight
            activeTourMoment = focus.liveMoment
            currentCity = index == 0 ? activeCityTitle(cityStop) : focus.title
            aiRecommendation = focus.subtitle
            showTourNowPlayingText = false
            musicPlayer.play(for: cityStop, insight: insight)
            mapRadioHost.speak(radioScript(for: focus, cityStop: cityStop, index: index, total: total))

            withAnimation(.easeInOut(duration: index == 0 ? 4.2 : 2.4)) {
                camera = .camera(
                    MapCamera(
                        centerCoordinate: focus.coordinate,
                        distance: focus.distance,
                        heading: focus.bearing,
                        pitch: activePitch
                    )
                )
                fixedDistanceAlt = focus.distance
                zoomLevel = focus.distance
                radiusMeters = focus.radiusMeters
            }

            NotificationCenter.default.post(
                name: .MapSuggestedRadius,
                object: nil,
                userInfo: ["radius": focus.radiusMeters]
            )
        }

        try? await Task.sleep(nanoseconds: trendPopStartDelaySeconds * 1_000_000_000 + 350_000_000)
        guard mapState.isInTourMode, !Task.isCancelled else { return }

        await MainActor.run {
            AudioServicesPlaySystemSound(1104)
            trendPopObjects = buildTrendPopObjects(stop: focusStop, insight: insight)
        }
    }

    private func radioScript(for focus: PoplurTourFocus, cityStop: PoplurTourStop, index: Int, total: Int) -> String {
        if index == 0 {
            let watched = enabledRadioTopics().map(\.shortTitle).joined(separator: ", ")
            return cleanMapRadioLine("Poplur Radio is live in \(cityStop.cityName). We are starting at the main landmark, \(cityStop.description). Your checklist is set to \(watched). If this city has those spots, I will pan us there next.")
        }

        let opener = "Next stop, \(focus.title)."
        let context = focus.liveMoment == nil
            ? focus.subtitle
            : "There is something happening here right now. \(focus.subtitle)"
        let progress = "Stop \(index + 1) of \(total)."
        return cleanMapRadioLine("\(opener) \(context) \(progress)")
    }
    
    // MARK: - Computed Properties
    
    private var cameraBinding: Binding<MapCameraPosition> {
        Binding(
            get: { camera },
            set: { newValue in
                // Allow free camera movement - user can pan/zoom anywhere
                camera = newValue

                // Only sync zoom when it changes meaningfully (>1%). Panning
                // doesn't change distance so this stays silent during drags.
                if !isCameraTransitionInProgress,
                   let distance = newValue.camera?.distance,
                   abs(distance - fixedDistanceAlt) > fixedDistanceAlt * 0.01 {
                    zoomLevel = distance
                    fixedDistanceAlt = distance
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
                noteInteraction()
            }
    }
    
    @ViewBuilder
    private var mapView: some View {
        MapReader { proxy in
            ZStack {
                Map(
                    position: cameraBinding,
                    interactionModes: use2DMap ? [.pan, .rotate, .zoom] : [.pan, .rotate, .pitch, .zoom]
                ) {
                // Show user annotation with 3D blue pin when location is available
                if let userCoord = liveUserCoordinate ?? locationManager.location?.coordinate {
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

                if let insight = activeTourInsight ?? (mapState.isInTourMode ? nil : localTrendInsight) {
                    ForEach(trendPopObjects) { object in
                        Annotation("", coordinate: object.coordinate) {
                            TrendPopMarker(object: object, category: insight.category)
                        }
                    }
                }

                ForEach(indoorVenues) { venue in
                    Annotation("", coordinate: venue.coordinate) {
                        Button {
                            selectedVenueSlug = venue.slug
                            showIndoorMap = true
                        } label: {
                            MappedinVenue3DButton(venue: venue)
                        }
                        .accessibilityLabel("Look inside \(venue.name)")
                    }
                }
                }
#if POP_PREVIEW_LIGHT
                .mapStyle(.standard)
#else
                .mapStyle(use2DMap ? .standard : .hybrid(elevation: .realistic, showsTraffic: false))
#endif
                .onTapGesture { location in
                // Handle map tap based on current flow
                if let coordinate = proxy.convert(location, from: .local) {
                    print("🗺️ [MapView] Map tapped at screen: \(location), converted to: \(coordinate.latitude), \(coordinate.longitude)")
                    
                    if isPoplurAIPostMode {
                        selectPoplurAIMapPostCoordinate(coordinate)
                        noteInteraction()
                    } else if let flow = flowManager.currentFlow, flow.isCameraFirst {
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
                        // Store clicked coordinate and show prompt
                        clickedCoordinate = coordinate
                        showPostPrompt = true

                        currentCity = "Location Selected"
                        aiRecommendation = String(format: "📍 %.4f°, %.4f° — Want to post here?",
                                                 coordinate.latitude,
                                                 coordinate.longitude)
                        print("✅ [MapView] Set clickedCoordinate: \(coordinate.latitude), \(coordinate.longitude)")
                        print("   showPostPrompt: \(showPostPrompt)")
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
                        } else if mapState.isInTourMode, activeTourInsight != nil {
                            if showTourNowPlayingText {
                                let trackText = musicPlayer.currentTrackTitle?
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                return "Now playing - \((trackText?.isEmpty == false) ? trackText! : "Finding local station...")"
                            } else {
                                return aiRecommendation
                            }
                        } else {
                            return aiRecommendation
                        }
                    }()
                    
                    Text(titleText)
                        .font(.headline)
                        .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.9)], startPoint: .leading, endPoint: .trailing))
                        .shadow(color: .black.opacity(0.55), radius: 4, x: 0, y: 1)
                    Text(recommendationText)
                        .font(.subheadline)
                        .foregroundStyle(LinearGradient(colors: [.white.opacity(0.92), .white.opacity(0.78)], startPoint: .leading, endPoint: .trailing))
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.55), radius: 4, x: 0, y: 1)
                        .id(recommendationText)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                        .animation(.easeInOut(duration: 0.38), value: recommendationText)
                }
                Spacer()
                
                // Dismiss button when showing post prompt or in camera->map flow
                if showPostPrompt || (flowManager.currentFlow?.isCameraFirst ?? false) {
                    Button(action: {
                        // Cancel the flow
                        if flowManager.currentFlow?.isCameraFirst ?? false {
                            flowManager.cancelFlow()
                        }
                        isPoplurAIPostMode = false
                        showPostPrompt = false
                        clickedCoordinate = nil
                        if let location = locationManager.location {
                            refreshLocalContext(for: location)
                        }
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
            
            // Post Here button - shows when coordinate is clicked OR in post placement mode
            if showPostPrompt, let coordinate = clickedCoordinate {
                Button(action: {
                    // Check which flow we're in
                    if let flow = flowManager.currentFlow, flow.isCameraFirst {
                        // Camera-first flow: confirm location, then continue to filters/channel selection.
                        print("📸 [MapView] Confirmed Camera -> Map location: \(coordinate.latitude), \(coordinate.longitude)")
                        flowManager.confirmLocation(coordinate)

                        NotificationCenter.default.post(
                            name: .showPostCaptureEditor,
                            object: nil,
                            userInfo: [
                                "image": flowManager.capturedImage as Any,
                                "videoURL": flowManager.capturedVideoURL as Any,
                                "latitude": coordinate.latitude,
                                "longitude": coordinate.longitude
                            ]
                        )
                        
                        // Reset UI
                        isPoplurAIPostMode = false
                        showPostPrompt = false
                        clickedCoordinate = nil
                        aiRecommendation = "Choose a filter, trim if needed, then pick a channel"
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
                        isPoplurAIPostMode = false
                        showPostPrompt = false
                        clickedCoordinate = nil
                        if let location = locationManager.location {
                            refreshLocalContext(for: location)
                        }
                    }
                }) {
                    HStack {
                        if let flow = flowManager.currentFlow, flow.isCameraFirst {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Confirm Location")
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
                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
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
                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(AnyTransition.move(edge: .top).combined(with: .opacity))
            }
            
            Spacer()
        }
    }

    @ViewBuilder
    private var mapZoomSliderOverlay: some View {
        GeometryReader { proxy in
            VStack {
                Spacer()
                HStack {
                    AnimatedZoomSlider(zoomLevel: $zoomLevel) { newZoom in
                        updateMapZoom(to: newZoom)
                    }
                    .frame(width: 60, height: mapZoomSliderHeight)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)

                    Spacer()
                }
                .padding(.leading, proxy.safeAreaInsets.leading + mapLeftOverlayPadding)
                .padding(.bottom, proxy.safeAreaInsets.bottom + 120)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .zIndex(1000)
    }

    private func updateMapZoom(to newZoom: Double) {
        guard let currentCoord = camera.camera?.centerCoordinate else { return }
        let heading = camera.camera?.heading ?? 0
        let clampedZoom = newZoom.clamped(to: 10...40_000_000)

        withAnimation(.easeOut(duration: 0.2)) {
            camera = .camera(
                MapCamera(
                    centerCoordinate: currentCoord,
                    distance: clampedZoom,
                    heading: heading,
                    pitch: activePitch
                )
            )
        }

        fixedDistanceAlt = clampedZoom
    }
    
    @ViewBuilder
    private var weatherBadgeOverlay: some View {
        GeometryReader { proxy in
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    weatherBadge
                        .frame(width: 112, alignment: .center)
                }
                .padding(.trailing, proxy.safeAreaInsets.trailing + 12)
                .padding(.bottom, proxy.safeAreaInsets.bottom + 248)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .allowsHitTesting(false)
        .zIndex(1001)
    }

    @ViewBuilder
    private var mapSearchButtonOverlay: some View {
        GeometryReader { proxy in
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        showAddressSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search locations")
                    .frame(width: 112, alignment: .center)
                }
                .padding(.trailing, proxy.safeAreaInsets.trailing + 12)
                .padding(.bottom, proxy.safeAreaInsets.bottom + 152)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .zIndex(1002)
    }

    @ViewBuilder
    private var weatherBadge: some View {
        VStack(spacing: 4) {
            weatherIcon(for: weatherState.kind)
                .font(.system(size: 32))
                .foregroundStyle(.white)

            Text(weatherName(for: weatherState.kind))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text("\(weatherState.temperatureFahrenheit)°")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }
    
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
                weatherState.temperatureFahrenheit = Int(max(18, min(42, 58 - latitude * 0.45)))
            } else if latitude > 30 {
                // Temperate - rain
                weatherState.kind = .rain
                weatherState.intensity = 0.5
                weatherState.temperatureFahrenheit = Int(max(45, min(78, 82 - abs(latitude - 35) * 1.25)))
            } else {
                // Tropical - thunderstorms
                weatherState.kind = .thunderstorms
                weatherState.intensity = 0.7
                weatherState.lightningFrequency = 0.4
                weatherState.temperatureFahrenheit = Int(max(72, min(92, 90 - abs(latitude) * 0.25)))
            }
            
            print("🌦 Weather updated for location: \(latitude), \(centerCoord.longitude)")
            print("   Weather: \(weatherName(for: weatherState.kind))")
            rainAmbientAudio.update(for: weatherState)
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
    
    @ViewBuilder
    private var mapContentLayer: some View {
        ZStack {
            // Main Map Layer - Same settings as interactive preview
            if layoutPreviewMode {
                mapLayoutSkeleton
            } else {
                mapView
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .simultaneousGesture(dragGesture)
                    .opacity(shouldObscureMapForInitialLaunch ? 0.001 : 1)
                    .allowsHitTesting(!shouldObscureMapForInitialLaunch)

                if shouldObscureMapForInitialLaunch {
                    mapLaunchCurtain
                        .transition(.opacity)
                        .zIndex(2_000)
                }
            }

            if !shouldObscureMapForInitialLaunch {
            // Top navigation buttons
            navigationButtons
            
            // AI Recommendation Overlay
            aiRecommendationOverlay

            mapZoomSliderOverlay

            weatherBadgeOverlay

            mapSearchButtonOverlay

            Button {
                selectedVenueSlug = indoorVenues.first?.slug ?? MappedinVenueSearch.demoSlug
                showIndoorMap = true
            } label: {
                Label("View Inside", systemImage: "building.2.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 20)
            .padding(.bottom, 200)
            .zIndex(1004)
            }
        }
        .animation(.easeOut(duration: 0.28), value: shouldObscureMapForInitialLaunch)
    }

    private var shouldObscureMapForInitialLaunch: Bool {
        isInitialMapLaunchPreparing
            && mapState.pendingPostLocation == nil
            && shownPostCoordinate == nil
            && !layoutPreviewMode
    }

    private var mapLaunchCurtain: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.04, blue: 0.05),
                    Color(red: 0.08, green: 0.12, blue: 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Canvas { context, size in
                var path = Path()
                for x in stride(from: CGFloat(0), through: size.width, by: 28) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: CGFloat(0), through: size.height, by: 28) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(.white.opacity(0.055)), lineWidth: 0.5)
            }

            VStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                Text(currentCity)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                Text(aiRecommendation)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
        }
        .ignoresSafeArea()
    }

    private var mapLayoutSkeleton: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.10),
                    Color(red: 0.14, green: 0.18, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Canvas { context, size in
                var path = Path()
                for x in stride(from: CGFloat(0), through: size.width, by: 24) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: CGFloat(0), through: size.height, by: 24) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(.white.opacity(0.08)), lineWidth: 0.5)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(currentCity)
                    .font(.headline)
                Text(aiRecommendation)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.28), in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
            .positioned(tab: .map, control: .title)

            AnimatedZoomSlider(zoomLevel: $zoomLevel) { newZoom in
                zoomLevel = newZoom
            }
            .frame(width: 60, height: 400)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
            .positioned(tab: .map, control: .secondaryAction)

            Button {} label: {
                Label("Post Here", systemImage: "camera.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.indigo, in: Capsule())
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
            .positioned(tab: .map, control: .primaryAction)
        }
    }
    
    var body: some View {
        mapContentLayer
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                #if DEBUG
                if showPlacesList {
                    mapOverlayPanel {
                        placesListSheet
                    }
                    .zIndex(50)
                }
                #endif

                if showAddressSearch {
                    mapOverlayPanel {
                        locationSearchSheet
                    }
                    .zIndex(51)
                }

                if mapCubeMenuWheel.isOnScreen {
                    CubeMenuWheelOverlay(controller: mapCubeMenuWheel)
                        .zIndex(52)
                }
            }
            .onAppear {
                guard !layoutPreviewMode else { return }
                handleOnAppear()
            }
            .onDisappear {
                mapLaunchTask?.cancel()
                mapLaunchTask = nil
                if !mapState.hasRunFirstLaunchSequence {
                    isInitialMapLaunchPreparing = true
                }
                isInitialMapLaunchActive = false
                isCameraTransitionInProgress = false
                mapRadioHost.stop()
                musicPlayer.stop()
                currentLocationMusicStopID = nil
                rainAmbientAudio.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: .StopMapAudio)) { _ in
                mapRadioHost.stop()
                musicPlayer.stop()
                currentLocationMusicStopID = nil
                rainAmbientAudio.stop()
            }
            .onChange(of: locationManager.location) { _, newLocation in
                guard !layoutPreviewMode else { return }
                handleLocationChange(newLocation)
            }
            .onChange(of: weatherState.kind) { _, _ in
                guard !layoutPreviewMode else { return }
                rainAmbientAudio.update(for: weatherState)
            }
            .onChange(of: weatherState.intensity) { _, _ in
                guard !layoutPreviewMode else { return }
                rainAmbientAudio.update(for: weatherState)
            }
            .onChange(of: mapCubeMenuWheel.isOnScreen) { _, isOnScreen in
                guard !layoutPreviewMode else { return }
                if !isOnScreen {
                    searchQuery = ""
                    searchResults = []
                }
            }
            .onChange(of: use2DMap) { _, is2D in
                guard !layoutPreviewMode else { return }
                guard let coord = camera.camera?.centerCoordinate else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    camera = .camera(MapCamera(
                        centerCoordinate: coord,
                        distance: fixedDistanceAlt,
                        heading: camera.camera?.heading ?? 0,
                        pitch: is2D ? 0 : fixedPitchAlt
                    ))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .CubeGlobalTap)) { _ in
                guard !layoutPreviewMode else { return }
                if mapCubeMenuWheel.isOnScreen {
                    mapCubeMenuWheel.endHold(activateSelected: false)
                    return
                }
                if let until = lockToPostUntil, until > Date() {
                    print("⛔️ [MapView] CubeGlobalTap centering ignored during lockToPost window")
                    return
                }
                if let until = suppressUserCenteringUntil, until > Date() {
                    print("⛔️ [MapView] CubeGlobalTap centering ignored during suppression window")
                    return
                }
                showPostPrompt = false
                clickedCoordinate = nil
                centerOnUserLocation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldBegan)) { _ in
                guard !layoutPreviewMode else { return }
                mapState.stopTour()
                showAddressSearch = false
                mapCubeMenuWheel.beginHold(items: mapCubeMenuItems)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CameraCubeHoldMoved"))) { _ in
                guard !layoutPreviewMode else { return }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldEnded)) { _ in
                guard !layoutPreviewMode else { return }
                mapCubeMenuWheel.endHold(activateSelected: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToMapTab"))) { _ in
                guard !layoutPreviewMode else { return }
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
                                    pitch: activePitch
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
                guard !layoutPreviewMode else { return }
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
            .onReceive(NotificationCenter.default.publisher(for: .PoplurAIStartMapPost)) { notification in
                guard !layoutPreviewMode else { return }
                beginPoplurAIMapPost(location: notification.userInfo?["location"] as? String)
            }
            .onReceive(NotificationCenter.default.publisher(for: .PoplurAISetTourActive)) { notification in
                guard !layoutPreviewMode else { return }
                let shouldStart = (notification.userInfo?["active"] as? Bool) ?? true
                if shouldStart {
                    if !mapState.isInTourMode {
                        startTour()
                    }
                } else if mapState.isInTourMode {
                    stopTour()
                } else {
                    mapState.stopTour()
                    clearTourEffects()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowLocationOnMap"))) { notification in
                guard !layoutPreviewMode else { return }
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
                                pitch: activePitch
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
                guard !layoutPreviewMode else { return }
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
                guard !layoutPreviewMode else { return }
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
                guard !layoutPreviewMode else { return }
                // Handle when a capture completes in camera tab
                guard let userInfo = notification.userInfo else { return }
                
                // Check if we're in Map -> Camera flow
                if let flow = flowManager.currentFlow, flow.isMapFirst, 
                   let coordinate = flow.preselectedCoordinate {
                    // Map-first fallback path: continue to filters/channel selection.
                    print("📍 [MapView] Capture complete in Map -> Camera flow, opening editor")
                    
                    let image = userInfo["image"] as? UIImage
                    let videoURL = userInfo["videoURL"] as? URL
                    
                    // Store the captured media in flow manager
                    flowManager.capturedImage = image
                    flowManager.capturedVideoURL = videoURL
                    flowManager.confirmLocation(coordinate)
                    
                    NotificationCenter.default.post(
                        name: .showPostCaptureEditor,
                        object: nil,
                        userInfo: [
                            "image": image as Any,
                            "videoURL": videoURL as Any,
                            "latitude": coordinate.latitude,
                            "longitude": coordinate.longitude
                        ]
                    )
                    
                    currentCity = "Edit Post"
                    aiRecommendation = "Choose a filter, trim if needed, then pick a channel"
                }
            }
            .task {
                guard !layoutPreviewMode else { return }
                await runTourLoop()
            }
            .task {
                guard !layoutPreviewMode else { return }
                await runTourSubtitleLoop()
            }
            .onChange(of: mapRadioHost.isLive) { _, isLive in
                guard !layoutPreviewMode else { return }
                if isLive {
                    rainAmbientAudio.setVoiceDucked(true)
                    musicPlayer.duckForRadio()
                } else {
                    rainAmbientAudio.setVoiceDucked(false)
                    musicPlayer.unduckAfterRadio()
                }
            }
            .sheet(isPresented: $showIndoorMap, onDismiss: { selectedVenueSlug = nil }) {
                indoorMapSheet
            }
            .onChange(of: fixedDistanceAlt) { _, newDist in
                if newDist >= 800 {
                    indoorVenues = []
                    return
                }
                guard let center = camera.camera?.centerCoordinate ?? locationManager.location?.coordinate else { return }
                let lat = center.latitude
                let lng = center.longitude
                Task {
                    let venues = await MappedinVenueSearch.nearbyVenues(lat: lat, lng: lng)
                    await MainActor.run { indoorVenues = venues }
                }
            }
    }

    @ViewBuilder
    private func mapOverlayPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Color.black.opacity(0.58)
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                content()
                    .frame(maxHeight: 520)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
            }
            .transition(.opacity)
    }
    
    #if DEBUG
    // MARK: - Sheet Views
    
    @ViewBuilder
    private var placesListSheet: some View {
        PlacesListView(places: tourPlaces) { place in
            showPlacesList = false
            panTo(place.coordinate)
        }
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
    }
    #endif

    @ViewBuilder
    private var locationSearchSheet: some View {
        AddressSearchView(
            query: $searchQuery,
            results: $searchResults,
            isSearching: $isSearching
        ) { item in
            showAddressSearch = false
            if let coord = item.placemark.location?.coordinate {
                if isPoplurAIPostMode {
                    selectPoplurAIMapPostCoordinate(coord)
                    panTo(coord)
                    return
                }
                if isPostPlacementMode {
                    postPlacementCoordinate = coord
                    panTo(coord)
                } else {
                    let name = item.name ?? "Selected Location"
                    navigateWithTourTransition(to: coord, cityName: name)
                }
            }
        }
    }

    @ViewBuilder
    private var indoorMapSheet: some View {
        NavigationStack {
            IndoorMapContainer(
                coordinate: locationManager.location?.coordinate,
                presetSlug: selectedVenueSlug
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Indoor Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showIndoorMap = false }
                }
            }
        }
    }

    // MARK: - Hold Menu

    private var mapCubeMenuItems: [CubeSubmenuItem] {
        [
            CubeSubmenuItem(id: "search", title: "Search", systemImage: "magnifyingglass", tint: .white) {
                showAddressSearch = true
            },
            CubeSubmenuItem(id: "location", title: "Location", systemImage: "location.fill", tint: .white) {
                centerOnUserLocation()
            },
            CubeSubmenuItem(id: "post", title: "Post Here", systemImage: "camera.fill", tint: .white) {
                isPostPlacementMode = true
            },
            CubeSubmenuItem(id: "multi-post", title: "Post Multiple", systemImage: "square.stack.fill", tint: .white) {
                isPostPlacementMode = true
            },
            CubeSubmenuItem(id: "tour", title: mapState.isInTourMode ? "Stop Tour" : "Start Tour", systemImage: "map.fill", tint: .white) {
                if mapState.isInTourMode { stopTour() } else { startTour() }
            }
        ]
    }

    // MARK: - First Launch Sequence

    private func generateLaunchRadioScript(cityName: String, insight: AiTourInsight?) -> String {
        let city = cityName.isEmpty ? "your area" : cityName
        let category = insight?.category ?? .music
        let hourSeed = Int(Date().timeIntervalSince1970 / 3600)

        let scripts: [TrendCategory: [String]] = [
            .food: [
                "You're tuned in to Poplur Radio, coming at you live from \(city). The food scene is absolutely buzzing right now — cafes packed, late plates flying, and the table shots everywhere. Brilliant spot to be. Stay with us.",
                "Poplur Radio, live from \(city). Food posts are trending hard around here today — from morning brunches to evening specials. Smashing vibes. Here comes the music."
            ],
            .clothes: [
                "This is Poplur Radio, broadcasting live from \(city). The streets are looking proper smart today — fit checks, fresh drops, sneakers on point. Cracking energy. Let's get into it.",
                "Poplur Radio, live in \(city). Fashion is at the forefront today — streetwear, new fits, and all the style you'd expect. Absolutely brilliant. Stay tuned."
            ],
            .sports: [
                "Poplur Radio is live from \(city). Sports energy is running high around here — games, fans, pickup clips, and all the reactions. Top stuff. Here come the sounds.",
                "You're with Poplur Radio, live in \(city). The sporting buzz here is undeniable — clips, fan moments, proper electric atmosphere. Brilliant. Let's keep it moving."
            ],
            .music: [
                "Welcome to Poplur Radio, live and direct from \(city). The music scene here is absolutely on fire — live moments, studio sessions, car audio turned all the way up. Lovely stuff. Here we go.",
                "Poplur Radio, coming to you live from \(city). Music is taking over the area right now — concerts, performers, the works. Absolutely mint. Let's ride with it."
            ],
            .travel: [
                "Poplur Radio, broadcasting live from \(city). People are out exploring and what they're capturing is stunning — landmarks, neighbourhood gems, arrival moments. Proper lovely. Here's your soundtrack.",
                "This is Poplur Radio, live from \(city). The exploration energy around here is brilliant — views, street life, all of it. What a spot. Let's get into the music."
            ],
            .nightlife: [
                "Poplur Radio is live from \(city). The nightlife around here is something else — rooftops, clubs, all the after-dark action you could want. Proper buzzing. Music's up next.",
                "You're with Poplur Radio, live in \(city). Nightlife is absolutely trending right now. The city doesn't sleep, and neither do we. Cracking vibes. Here we go."
            ]
        ]

        let options = scripts[category] ?? scripts[.music]!
        let seed = stableTourSeed(parts: city, "\(hourSeed)")
        return options[seed % options.count]
    }

    @MainActor
    private func runFirstLaunchSequence(at coordinate: CLLocationCoordinate2D, cityName: String, insight: AiTourInsight?, countryCode: String?) async {
        var didCompleteLaunch = false
        defer {
            if !didCompleteLaunch, Task.isCancelled, !mapState.hasRunFirstLaunchSequence {
                isInitialMapLaunchPreparing = true
            }
            isInitialMapLaunchActive = false
            isCameraTransitionInProgress = false
            rainAmbientAudio.setVoiceDucked(false)
        }

        fixedDistanceAlt = 700
        zoomLevel = 700
        radiusMeters = 5_000
        showConfetti = false
        isCameraTransitionInProgress = true

        camera = .camera(MapCamera(
            centerCoordinate: coordinate,
            distance: 10_000,
            heading: 0,
            pitch: 0
        ))

        try? await Task.sleep(nanoseconds: 260_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.28)) {
            isInitialMapLaunchPreparing = false
        }

        try? await Task.sleep(nanoseconds: 240_000_000)
        guard !Task.isCancelled else { return }

        currentCity = cityName
        let launchInsight = insight ?? makeLocalTrendInsight(for: cityName)
        localTrendInsight = launchInsight
        aiRecommendation = launchInsight.subtitle
        trendPopObjects = buildTrendPopObjects(center: coordinate, cityName: cityName, insight: launchInsight)

        withAnimation(.easeInOut(duration: 2.2)) {
            camera = .camera(MapCamera(
                centerCoordinate: coordinate,
                distance: fixedDistanceAlt,
                heading: 0,
                pitch: activePitch
            ))
        }

        try? await Task.sleep(nanoseconds: 2_500_000_000)
        guard !Task.isCancelled else { return }

        emitLocalTrendConfetti(center: coordinate, objects: trendPopObjects)

        try? await Task.sleep(nanoseconds: 700_000_000)
        guard !Task.isCancelled else { return }

        await fetchWeatherForCurrentLocation()
        rainAmbientAudio.setVoiceDucked(true)

        let script = generateLaunchRadioScript(cityName: cityName, insight: launchInsight)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            mapRadioHost.speak(script) {
                continuation.resume()
            }
        }
        rainAmbientAudio.setVoiceDucked(false)

        try? await Task.sleep(nanoseconds: 650_000_000)
        guard !Task.isCancelled, !mapState.isInTourMode else { return }

        let storefront = normalizedStorefront(countryCode)
            ?? nearestTourStop(to: coordinate)?.storefront
            ?? Locale.current.region?.identifier.lowercased()
            ?? "us"
        let stop = PoplurTourStop(
            cityName: cityName,
            storefront: storefront,
            coordinate: coordinate,
            bearing: 0,
            radiusMeters: radiusMeters,
            distance: max(850, fixedDistanceAlt),
            description: "Current location"
        )
        currentLocationMusicStopID = stop.id
        musicPlayer.play(for: stop, insight: launchInsight, preferPreviewTracks: true, fadeIn: true)

        didCompleteLaunch = true
        mapState.hasRunFirstLaunchSequence = true
    }

    // MARK: - Event Handlers

    private func handleOnAppear() {
        if mapState.hasRunFirstLaunchSequence {
            rainAmbientAudio.update(for: weatherState)
        }

        if let location = locationManager.location {
            liveUserCoordinate = location.coordinate
        }

        // Pending post navigation takes priority over everything
        if let pendingCoordinate = mapState.pendingPostLocation {
            suppressUserCenteringUntil = Date().addingTimeInterval(15)
            lockToPostUntil = Date().addingTimeInterval(15)
            hasSetInitialLocation = true
            mapState.showPostLocation(pendingCoordinate)

            let latStr = String(format: "%.4f", pendingCoordinate.latitude)
            let lonStr = String(format: "%.4f", pendingCoordinate.longitude)
            var cityComponents: [String] = []
            if let username = mapState.pendingPostUsername { cityComponents.append(username) }
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
            withAnimation(.none) {
                camera = .camera(MapCamera(
                    centerCoordinate: pendingCoordinate,
                    distance: fixedDistanceAlt,
                    heading: 0,
                    pitch: activePitch
                ))
            }
            navigateWithTourTransition(to: pendingCoordinate, cityName: "Post Location")
            mapState.clearPendingPostLocation()
            return
        }

        if let until = lockToPostUntil, until > Date() {
            print("⛔️ [MapView] handleOnAppear ignored during lockToPost window")
            return
        }
        if case .showingPostLocation = mapState.mode {
            print("⛔️ [MapView] handleOnAppear ignored - showing post location")
            return
        }

        locationManager.request()

        if !mapState.hasRunFirstLaunchSequence {
            guard !isInitialMapLaunchActive else { return }
            mapLaunchTask?.cancel()
            isInitialMapLaunchPreparing = true
            isInitialMapLaunchActive = true
            hasSetInitialLocation = true
            currentCity = "Current Location"
            aiRecommendation = "Finding what is trending where you are..."
            locationContextTask?.cancel()

            mapLaunchTask = Task { @MainActor in
                // Wait briefly for the real location before revealing the map, so the
                // first visible camera is already aimed at the correct place.
                var attempts = 0
                while locationManager.location == nil && attempts < 35 {
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    attempts += 1
                }

                let location = locationManager.location
                let coordinate = location?.coordinate
                    ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
                liveUserCoordinate = coordinate

                var cityName = "Your Location"
                var countryCode: String? = nil
                if let location {
                    let geocoder = CLGeocoder()
                    if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
                       let placemark = placemarks.first {
                        cityName = placemark.locality
                            ?? placemark.subAdministrativeArea
                            ?? placemark.administrativeArea
                            ?? "Your Location"
                        countryCode = placemark.isoCountryCode
                    }
                } else if let nearest = nearestTourStop(to: coordinate) {
                    cityName = nearest.cityName
                    countryCode = nearest.storefront
                }

                let insight = makeLocalTrendInsight(for: cityName)
                await runFirstLaunchSequence(at: coordinate, cityName: cityName, insight: insight, countryCode: countryCode)
                mapLaunchTask = nil
            }
        } else {
            Task { await fetchWeatherForCurrentLocation() }
            // Returning to map tab: restore context and resume music without re-running the intro
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !mapState.isInTourMode, !(flowManager.currentFlow?.isCameraFirst ?? false), !isPostPlacementMode else { return }
                guard lockToPostUntil == nil || lockToPostUntil! <= Date() else { return }
                if let location = locationManager.location {
                    liveUserCoordinate = location.coordinate
                    refreshLocalContext(for: location)
                }
            }
            ensureCurrentLocationMusicAfterLaunch(delayNanoseconds: 2_800_000_000)
        }
    }

    private func handleLocationChange(_ newLocation: CLLocation?) {
        if let newLocation {
            liveUserCoordinate = newLocation.coordinate
            if isInitialMapLaunchActive {
                print("⏭️ [MapView] handleLocationChange deferred during initial launch")
                return
            }
            // Only refresh context after the launch sequence has fully run.
            // Guard against the 10m distanceFilter firing too often — only re-trigger
            // pops/music/radio when the user has moved at least 5km from the last refresh.
            if mapState.hasRunFirstLaunchSequence &&
               (currentLocationMusicStopID == nil || !musicPlayer.isPlaybackActive) {
                let shouldRefresh = lastContextRefreshLocation.map {
                    newLocation.distance(from: $0) > 5_000
                } ?? true
                if shouldRefresh {
                    lastContextRefreshLocation = newLocation
                    refreshLocalContext(for: newLocation)
                }
            }
        }

        if let until = lockToPostUntil, until > Date() {
            print("⛔️ [MapView] handleLocationChange ignored during lockToPost window")
            return
        }

        // Only update camera once per view lifetime; launch sequence handles the first visit
        guard !hasSetInitialLocation, let newLocation else {
            if hasSetInitialLocation {
                print("⏭️ [MapView] handleLocationChange skipped - initial location already set")
            }
            return
        }

        hasSetInitialLocation = true
        print("📍 [MapView] handleLocationChange - centering on user (returning visit)")

        camera = .camera(MapCamera(
            centerCoordinate: newLocation.coordinate,
            distance: fixedDistanceAlt,
            heading: 0,
            pitch: activePitch
        ))

        if mapState.hasRunFirstLaunchSequence {
            lastContextRefreshLocation = newLocation
            refreshLocalContext(for: newLocation)
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
private struct MapTabLayoutPreview: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.13, blue: 0.12),
                    Color(red: 0.16, green: 0.20, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Canvas { context, size in
                let gridColor = Color.white.opacity(0.10)
                for x in stride(from: 0, through: size.width, by: 42) {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + 70, y: size.height))
                    context.stroke(path, with: .color(gridColor), lineWidth: 1)
                }
                for y in stride(from: 0, through: size.height, by: 42) {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y - 54))
                    context.stroke(path, with: .color(gridColor), lineWidth: 1)
                }
            }
            .ignoresSafeArea()

            ForEach(0..<9, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: CGFloat(20 + (index % 3) * 7), height: CGFloat(20 + (index % 3) * 7))
                    .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
                    .position(
                        x: [74, 148, 246, 326, 110, 286, 210, 52, 344][index],
                        y: [154, 238, 184, 312, 428, 500, 620, 694, 724][index]
                    )
            }

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Toronto")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Now playing - local radio")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.70))
                    }
                    Spacer()
                    Button {} label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.14), in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)

                Spacer()

                HStack {
                    Button {} label: {
                        Image(systemName: "minus")
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                    Button {} label: {
                        Image(systemName: "plus")
                            .frame(width: 44, height: 44)
                    }
                }
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .backgroundStyle(.white.opacity(0.14))
                .buttonStyle(.bordered)
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }
        }
    }
}

#endif

// MARK: - Mappedin Indoor Maps

private struct IndoorMapContainer: View {
    let coordinate: CLLocationCoordinate2D?
    var presetSlug: String? = nil

    @State private var venueURL: URL? = nil
    @State private var isSearching = true

    var body: some View {
        Group {
            if let url = venueURL {
                MappedInWebView(url: url)
            } else if isSearching {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Searching for nearby venues…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "building.2.slash")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                    Text("No indoor map available\nfor this location")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if let slug = presetSlug {
                venueURL = URL(string: "https://app.mappedin.com/map/\(slug)")
            } else if let coord = coordinate {
                let slug = await MappedinVenueSearch.nearestVenue(lat: coord.latitude, lng: coord.longitude)
                venueURL = slug.flatMap { URL(string: "https://app.mappedin.com/map/\($0)") }
            } else {
                venueURL = URL(string: "https://app.mappedin.com/map/\(MappedinVenueSearch.demoSlug)")
            }
            isSearching = false
        }
    }
}

private struct MappedInWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url { uiView.load(URLRequest(url: url)) }
    }
}

struct MappedinVenue: Identifiable {
    let slug: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    var id: String { slug }
    var mapURL: URL { URL(string: "https://app.mappedin.com/map/\(slug)")! }
}

private struct MappedinVenue3DButton: View {
    let venue: MappedinVenue

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 13, weight: .bold))
            Text("3D")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
            Text("Inside")
                .font(.system(size: 8, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.indigo.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }
}

private enum MappedinVenueSearch {
    // Sign up at developer.mappedin.com and replace these with your own credentials.
    static let clientId = "5eab30aa91b055001a68e996"
    static let clientSecret = "RJyRXKcryCMy4erZqqCbuB1NpgM2G7NMEAD75cFhotP"
    static let demoSlug = "mappedin-demo-mall"

    /// Returns the slug of the nearest Mappedin-indexed venue, or nil if none is nearby.
    static func nearestVenue(lat: Double, lng: Double) async -> String? {
        await nearbyVenues(lat: lat, lng: lng).first?.slug
    }

    /// Returns all Mappedin-indexed venues near the given coordinate.
    static func nearbyVenues(lat: Double, lng: Double) async -> [MappedinVenue] {
        guard var comps = URLComponents(string: "https://api.mappedin.com/1/venue") else { return [] }
        comps.queryItems = [
            .init(name: "venue", value: "nearby"),
            .init(name: "lat", value: String(lat)),
            .init(name: "lng", value: String(lng))
        ]
        guard let url = comps.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 6)
        let token = Data("\(clientId):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let arr = json["data"] as? [[String: Any]] {
                return arr.compactMap { venue -> MappedinVenue? in
                    guard let slug = venue["slug"] as? String, !slug.isEmpty else { return nil }
                    let name = venue["name"] as? String ?? slug
                    // Coordinates may be at top level or nested under "location"
                    let vLat: Double
                    let vLng: Double
                    if let loc = venue["location"] as? [String: Any],
                       let la = loc["lat"] as? Double,
                       let lo = (loc["lon"] as? Double) ?? (loc["lng"] as? Double) {
                        vLat = la; vLng = lo
                    } else if let la = venue["lat"] as? Double,
                              let lo = (venue["lon"] as? Double) ?? (venue["lng"] as? Double) {
                        vLat = la; vLng = lo
                    } else {
                        vLat = lat; vLng = lng
                    }
                    return MappedinVenue(slug: slug, name: name,
                                        coordinate: CLLocationCoordinate2D(latitude: vLat, longitude: vLng))
                }
            }
        } catch {}
        return []
    }
}
