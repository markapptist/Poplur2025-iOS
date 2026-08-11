//
//  ConfettiSystem.swift
//  Confetti particle system for trending map pins
//

import Foundation
import SwiftUI
import SpriteKit
import MapKit

// MARK: - Confetti Particle System

/// Represents a trending pin that can emit confetti
struct TrendingPin: Identifiable, Equatable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    var radius: Double
    var previousRadius: Double
    var trendingScore: Double // 0.0 - 1.0, higher = more confetti
    
    /// Whether this pin is trending up (growing)
    var isTrendingUp: Bool {
        radius > previousRadius && trendingScore > 0.5
    }
    
    /// Confetti intensity based on growth rate
    var confettiIntensity: Double {
        guard radius > previousRadius else { return 0 }
        let safePrev = max(previousRadius, 1.0)
        let growthRate = (radius - previousRadius) / safePrev
        let value = min(max(growthRate * 2, 0), 1.0)
        return value.isFinite ? value : 0
    }
    
    static func == (lhs: TrendingPin, rhs: TrendingPin) -> Bool {
        return lhs.id == rhs.id
    }
}

/// SpriteKit scene for confetti particles
class ConfettiScene: SKScene {
    
    private var emitters: [UUID: SKEmitterNode] = [:]
    
    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Trigger confetti burst at a specific position
    func burst(at position: CGPoint, intensity: Double, color: UIColor = .systemYellow) {
        let emitter = createConfettiEmitter(color: color, intensity: intensity)
        emitter.position = position
        addChild(emitter)
        
        // Auto-remove after burst completes
        let duration = 2.0
        let wait = SKAction.wait(forDuration: duration)
        let remove = SKAction.removeFromParent()
        emitter.run(SKAction.sequence([wait, remove]))
    }
    
    /// Start continuous confetti emission at position (for sustained trending)
    func startEmitting(id: UUID, at position: CGPoint, intensity: Double, color: UIColor) {
        // Remove existing emitter if any
        stopEmitting(id: id)
        
        let emitter = createConfettiEmitter(color: color, intensity: intensity)
        emitter.position = position
        let safeIntensity = max(0, min(intensity.isFinite ? intensity : 0, 1))
        emitter.particleBirthRate = CGFloat(30 * safeIntensity) // Continuous emission
        addChild(emitter)
        emitters[id] = emitter
    }
    
    /// Stop continuous emission for a pin
    func stopEmitting(id: UUID) {
        if let emitter = emitters[id] {
            let fadeOut = SKAction.fadeOut(withDuration: 0.5)
            let remove = SKAction.removeFromParent()
            emitter.run(SKAction.sequence([fadeOut, remove]))
            emitters.removeValue(forKey: id)
        }
    }
    
    /// Create a confetti emitter node
    private func createConfettiEmitter(color: UIColor, intensity: Double) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        let safeIntensity = max(0, min(intensity.isFinite ? intensity : 0, 1))
        
        // Particle appearance
        emitter.particleTexture = SKTexture(image: createConfettiShape())
        emitter.particleBirthRate = CGFloat(100 * safeIntensity) // Burst rate
        emitter.numParticlesToEmit = Int(50 * safeIntensity) // Total particles in burst
        emitter.particleLifetime = 3.0
        emitter.particleLifetimeRange = 1.0
        
        // Explosion pattern
        emitter.emissionAngle = CGFloat.pi / 2 // Up
        emitter.emissionAngleRange = CGFloat.pi * 2 // All directions
        emitter.particleSpeed = 200 * safeIntensity
        emitter.particleSpeedRange = 100
        
        // Gravity effect
        emitter.yAcceleration = -200 // Fall down
        emitter.xAcceleration = 0
        
        // Size and scale
        emitter.particleScale = 0.3
        emitter.particleScaleRange = 0.2
        emitter.particleScaleSpeed = -0.1
        
        // Rotation
        emitter.particleRotation = 0
        emitter.particleRotationRange = CGFloat.pi * 2
        emitter.particleRotationSpeed = 4
        
        // Color variation
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1.0
        emitter.particleColorSequence = nil
        
        // Alpha fade
        emitter.particleAlpha = 0.9
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = -0.3
        
        // Blend mode
        emitter.particleBlendMode = .alpha
        
        return emitter
    }
    
    /// Create confetti particle shape
    private func createConfettiShape() -> UIImage {
        let size = CGSize(width: 10, height: 10)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Random shapes: square, circle, triangle
            let shape = Int.random(in: 0...2)
            
            let colors: [UIColor] = [
                .systemRed, .systemOrange, .systemYellow,
                .systemGreen, .systemBlue, .systemPurple,
                .systemPink, .systemTeal
            ]
            colors.randomElement()?.setFill()
            
            switch shape {
            case 0: // Square
                UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            case 1: // Circle
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            case 2: // Triangle
                let path = UIBezierPath()
                path.move(to: CGPoint(x: size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.close()
                path.fill()
            default:
                break
            }
        }
    }
}

/// UIKit wrapper for confetti scene
struct ConfettiOverlay: UIViewRepresentable {
    @Binding var trendingPins: [TrendingPin]
    
    let coordinateConverter: ((CLLocationCoordinate2D) -> CGPoint?)?
    
    func makeUIView(context: Context) -> SKView {
        let view = PoplurManagedSKView(performanceName: "Confetti2D")
        view.backgroundColor = .clear
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        
        let scene = ConfettiScene(size: view.bounds.size)
        context.coordinator.confettiScene = scene
        view.presentScene(scene)
        
        return view
    }
    
    func updateUIView(_ uiView: SKView, context: Context) {
        guard let scene = context.coordinator.confettiScene else { return }
        
        // Update scene size if needed
        if scene.size != uiView.bounds.size {
            scene.size = uiView.bounds.size
        }
        
        // Trigger confetti for trending pins
        for pin in trendingPins where pin.isTrendingUp {
            if let screenPosition = coordinateConverter?(pin.coordinate) {
                // Check if this is a new trending state
                if !context.coordinator.activePins.contains(pin.id) {
                    // Initial burst
                    scene.burst(at: screenPosition, intensity: pin.confettiIntensity)
                    context.coordinator.activePins.insert(pin.id)
                    
                    // Optional: Start continuous emission for very high trending
                    if pin.trendingScore > 0.8 {
                        scene.startEmitting(
                            id: pin.id,
                            at: screenPosition,
                            intensity: pin.confettiIntensity * 0.3, // Lighter continuous effect
                            color: .systemYellow
                        )
                    }
                }
            }
        }
        
        // Stop confetti for pins that are no longer trending
        let currentIds = Set(trendingPins.filter { $0.isTrendingUp }.map { $0.id })
        let stoppedIds = context.coordinator.activePins.subtracting(currentIds)
        for id in stoppedIds {
            scene.stopEmitting(id: id)
            context.coordinator.activePins.remove(id)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        weak var confettiScene: ConfettiScene?
        var activePins: Set<UUID> = []
    }
}

// MARK: - Pin Trending Tracker

/// Tracks pin growth and trending status over time
class PinTrendingTracker: ObservableObject {
    
    @Published var trendingPins: [TrendingPin] = []
    
    private var pinHistory: [UUID: [PinSnapshot]] = [:]
    private let historyWindow: TimeInterval = 60 // Track last 60 seconds
    
    struct PinSnapshot {
        let timestamp: Date
        let radius: Double
        let activityCount: Int // Number of posts/interactions
    }
    
    /// Update a pin's status and determine if it's trending
    func updatePin(id: UUID, coordinate: CLLocationCoordinate2D, radius: Double, activityCount: Int = 0) {
        let snapshot = PinSnapshot(timestamp: Date(), radius: radius, activityCount: activityCount)
        
        // Add to history
        if pinHistory[id] == nil {
            pinHistory[id] = []
        }
        pinHistory[id]?.append(snapshot)
        
        // Clean old history
        cleanOldHistory(for: id)
        
        // Calculate trending score
        let trendingScore = calculateTrendingScore(for: id)
        let previousRadius = getPreviousRadius(for: id)
        
        // Update or create trending pin
        if let index = trendingPins.firstIndex(where: { $0.id == id }) {
            trendingPins[index].coordinate = coordinate
            trendingPins[index].previousRadius = trendingPins[index].radius
            trendingPins[index].radius = radius
            trendingPins[index].trendingScore = trendingScore
        } else {
            let pin = TrendingPin(
                id: id,
                coordinate: coordinate,
                radius: radius,
                previousRadius: previousRadius,
                trendingScore: trendingScore
            )
            trendingPins.append(pin)
        }
    }
    
    /// Remove a pin from tracking
    func removePin(id: UUID) {
        trendingPins.removeAll { $0.id == id }
        pinHistory.removeValue(forKey: id)
    }

    /// Immediately mark a coordinate as trending so visual bursts can happen without waiting for history.
    func forceTrendingBurst(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, intensity: Double = 1.0) {
        let previousRadius = 80.0
        let radius = previousRadius * (1.0 + max(0.2, intensity))
        let pin = TrendingPin(
            id: id,
            coordinate: coordinate,
            radius: radius,
            previousRadius: previousRadius,
            trendingScore: intensity.clamped(to: 0.6...1.0)
        )
        trendingPins.append(pin)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            self?.removePin(id: id)
        }
    }
    
    /// Calculate trending score based on growth rate and velocity
    private func calculateTrendingScore(for id: UUID) -> Double {
        guard let history = pinHistory[id], history.count >= 2 else { return 0 }
        
        let recent = Array(history.suffix(5)) // Last 5 snapshots — Array gives 0-based indices, unlike ArraySlice
        
        // Calculate average growth rate
        var totalGrowth = 0.0
        for i in 1..<recent.count {
            let previous = recent[i - 1]
            let current = recent[i]
            let growth = (current.radius - previous.radius) / max(previous.radius, 1.0)
            totalGrowth += growth
        }
        
        let avgGrowth = totalGrowth / Double(recent.count - 1)
        
        // Calculate velocity (growth acceleration)
        var velocityScore = 0.0
        if recent.count >= 3 {
            let recentGrowth = (recent.last!.radius - recent[recent.count - 2].radius) / max(recent[recent.count - 2].radius, 1.0)
            let olderGrowth = (recent[recent.count - 2].radius - recent[recent.count - 3].radius) / max(recent[recent.count - 3].radius, 1.0)
            velocityScore = recentGrowth - olderGrowth
        }
        
        // Combine growth and velocity
        let score = (avgGrowth * 0.7 + velocityScore * 0.3).clamped(to: 0...1)
        
        return score
    }
    
    /// Get previous radius for comparison
    private func getPreviousRadius(for id: UUID) -> Double {
        guard let history = pinHistory[id], history.count >= 2 else {
            return pinHistory[id]?.first?.radius ?? 0
        }
        return history[history.count - 2].radius
    }
    
    /// Clean history older than the window
    private func cleanOldHistory(for id: UUID) {
        let cutoffDate = Date().addingTimeInterval(-historyWindow)
        pinHistory[id]?.removeAll { $0.timestamp < cutoffDate }
    }
    
    /// Clean all old history
    func cleanAllOldHistory() {
        let cutoffDate = Date().addingTimeInterval(-historyWindow)
        for (id, _) in pinHistory {
            pinHistory[id]?.removeAll { $0.timestamp < cutoffDate }
        }
    }
}

// MARK: - SwiftUI Confetti View

/// SwiftUI-friendly confetti animation
struct ConfettiAnimation: View {
    @State private var isAnimating = false
    @State private var particles: [ConfettiParticle] = []
    
    let intensity: Double
    let color: Color
    
    init(intensity: Double = 1.0, color: Color = .yellow) {
        self.intensity = intensity
        self.color = color
    }
    
    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .offset(x: particle.x, y: particle.y)
                    .opacity(particle.opacity)
                    .rotationEffect(.degrees(particle.rotation))
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        let count = Int(50 * intensity)
        particles = (0..<count).map { _ in
            ConfettiParticle(
                x: 0,
                y: 0,
                size: CGFloat.random(in: 4...12),
                color: randomColor(),
                opacity: 1.0,
                rotation: Double.random(in: 0...360)
            )
        }
        
        // Animate particles outward
        withAnimation(.easeOut(duration: 2.0)) {
            particles = particles.map { particle in
                var p = particle
                p.x = CGFloat.random(in: -150...150)
                p.y = CGFloat.random(in: (-200)...(-50))
                p.opacity = 0
                p.rotation += Double.random(in: 360...720)
                return p
            }
        }
        
        // Remove particles after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            particles.removeAll()
        }
    }
    
    private func randomColor() -> Color {
        let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
        return colors.randomElement() ?? color
    }
    
    struct ConfettiParticle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var color: Color
        var opacity: Double
        var rotation: Double
    }
}

// MARK: - Map Integration Helper

/// Helper functions for integrating confetti with your map view
/// Use these in your MapViewProduction or similar map components
struct ConfettiMapHelper {
    
    /// Create trending pins from your post data
    /// - Parameters:
    ///   - posts: Array of posts to analyze
    ///   - baseRadius: Base radius for pin calculation
    /// - Returns: Array of trending pins that should show confetti
    static func createTrendingPins<Post: Identifiable>(
        from posts: [Post],
        baseRadius: Double,
        getCoordinate: (Post) -> CLLocationCoordinate2D
    ) -> [TrendingPin] where Post.ID == UUID {
        let pins = posts.map { post in
            TrendingPin(
                id: post.id,
                coordinate: getCoordinate(post),
                radius: baseRadius * Double.random(in: 0.8...1.2),
                previousRadius: baseRadius * 0.9,
                trendingScore: Double.random(in: 0.6...0.95)
            )
        }
        return pins.filter { $0.isTrendingUp }
    }
}

// MARK: - Example Usage Extension (Optional)
// Uncomment and adapt this to your actual MapViewProduction implementation

/*
extension MapViewProduction {
    
    /// Setup confetti system for trending pins
    func setupConfettiSystem() {
        // This would be called in your MapView initialization
        // The confetti overlay would be added to your view hierarchy
    }
    
    /// Get trending pins from your posts
    func getTrendingPins() -> [TrendingPin] {
        // If you have access to posts and radiusMeters as internal/public properties:
        return ConfettiMapHelper.createTrendingPins(
            from: yourPosts,
            baseRadius: yourRadiusMeters
        ) { post in
            post.coordinate
        }
    }
}
*/

// MARK: - Helper Extension

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
