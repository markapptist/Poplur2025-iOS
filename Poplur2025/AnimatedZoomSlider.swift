import SwiftUI
import SpriteKit
import AVFoundation

/// Animated SpriteKit-based zoom slider with notches and smooth interactions
struct AnimatedZoomSlider: UIViewRepresentable {
    @Binding var zoomLevel: Double // 10m to 40,000,000m
    let onZoomChange: (Double) -> Void
    
    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.allowsTransparency = true
        
        let scene = ZoomSliderScene(size: CGSize(width: 60, height: 400))
        scene.scaleMode = .fill
        scene.backgroundColor = .clear
        scene.anchorPoint = CGPoint(x: 0, y: 0)
        scene.zoomLevel = zoomLevel
        scene.onZoomChange = onZoomChange
        scene.coordinator = context.coordinator
        
        view.presentScene(scene)
        context.coordinator.scene = scene
        
        return view
    }
    
    func updateUIView(_ uiView: SKView, context: Context) {
        if let scene = context.coordinator.scene {
            scene.updateZoomLevel(zoomLevel, animated: false)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        weak var scene: ZoomSliderScene?
    }
}

// MARK: - SpriteKit Scene

class ZoomSliderScene: SKScene {
    var zoomLevel: Double = 100 {  // Start at 100m (close zoom - near top of slider)
        didSet {
            // Only update if scene is properly initialized
            if knobNode != nil {
                updateZoomLevel(zoomLevel, animated: true)
            }
        }
    }
    var onZoomChange: ((Double) -> Void)?
    weak var coordinator: AnimatedZoomSlider.Coordinator?
    
    private var trackNode: SKShapeNode!
    private var knobNode: SKShapeNode!
    private var notchNodes: [SKShapeNode] = []
    private var labelNodes: [SKLabelNode] = []
    private var isDragging = false
    private var dragStartY: CGFloat = 0
    private var dragStartZoom: Double = 0
    
    // Haptic feedback
    private var impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private var lastNotchIndex: Int = -1
    
    // Audio feedback
    private var audioPlayer: AVAudioPlayer?
    
    // Zoom range
    private let minZoom: Double = 10 // 10m (very close - bottom of slider with new inversion)
    private let maxZoom: Double = 40_000_000 // 40,000km (very far - top of slider with new inversion)
    
    // Visual constants
    private let trackWidth: CGFloat = 8
    private let trackHeight: CGFloat = 320
    private let knobRadius: CGFloat = 18
    private let knobWidth: CGFloat = 44
    private let knobHeight: CGFloat = 28
    private let notchCount = 10
    
    override func didMove(to view: SKView) {
        super.didMove(to: view)
        setupSlider()
        setupAudio()
    }
    
    private func setupAudio() {
        // Load the pop sound (system sound or custom)
        // Using a system sound for now - you can replace with custom audio file
        guard let soundURL = Bundle.main.url(forResource: "pop", withExtension: "mp3") ?? 
                             Bundle.main.url(forResource: "pop", withExtension: "wav") else {
            print("⚠️ [ZoomSlider] Pop sound file not found, using haptic only")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = 0.3 // Subtle volume
        } catch {
            print("⚠️ [ZoomSlider] Could not load audio: \(error.localizedDescription)")
        }
    }
    
    private func playPopSound() {
        audioPlayer?.currentTime = 0
        audioPlayer?.play()
    }
    
    private func setupSlider() {
        // With anchor point at (0,0), center of scene is at (width/2, height/2)
        let centerX = size.width / 2
        let centerY = size.height / 2
        
        print("🔧 [ZoomSlider] setupSlider - centerX: \(centerX), centerY: \(centerY), initialZoom: \(zoomLevel)m")
        
        // Track - minimal vertical line
        let trackPath = UIBezierPath(roundedRect: CGRect(x: -2, y: -trackHeight/2, width: 4, height: trackHeight), cornerRadius: 2)
        trackNode = SKShapeNode(path: trackPath.cgPath)
        trackNode.fillColor = UIColor(white: 0.3, alpha: 0.4)
        trackNode.strokeColor = .clear
        trackNode.position = CGPoint(x: centerX, y: centerY)
        trackNode.zPosition = 50
        addChild(trackNode)
        
        // Knob - simple cube-like design matching CubeTabView aesthetic
        let knobPath = UIBezierPath(roundedRect: CGRect(x: -knobWidth/2, y: -knobHeight/2, width: knobWidth, height: knobHeight), cornerRadius: 4)
        knobNode = SKShapeNode(path: knobPath.cgPath)
        
        knobNode.fillColor = UIColor.white
        knobNode.strokeColor = UIColor.white.withAlphaComponent(0.9)
        knobNode.lineWidth = 1
        knobNode.position = CGPoint(x: centerX, y: centerY)
        knobNode.zPosition = 100
        
        addChild(knobNode)
        
        print("🔧 [ZoomSlider] setupSlider complete - knob created at \(knobNode.position)")
        
        // Initial position
        updateZoomLevel(zoomLevel, animated: false)
        
        print("🔧 [ZoomSlider] setupSlider - after updateZoomLevel, knob position: \(knobNode.position)")
    }
    
    private func zoomValueForProgress(_ progress: Double) -> Double {
        // Exponential mapping from progress to zoom value
        let minLog = log10(minZoom)
        let maxLog = log10(maxZoom)
        let logValue = minLog + progress * (maxLog - minLog)
        return pow(10.0, logValue)
    }
    
    private func progressForZoomValue(_ zoom: Double) -> Double {
        // Inverse exponential mapping - INVERTED for intuitive behavior
        // 0 progress (close/zoomed in) = BOTTOM of slider
        // 1 progress (far/zoomed out) = TOP of slider
        let minLog = log10(minZoom)
        let maxLog = log10(maxZoom)
        let currentLog = log10(zoom.clamped(to: minZoom...maxZoom))
        let normalProgress = (currentLog - minLog) / (maxLog - minLog)
        return 1.0 - normalProgress // Invert the progress
    }
    
    private func formatZoomLabel(_ zoom: Double) -> String {
        if zoom >= 1_000_000 {
            return String(format: "%.0fkm", zoom / 1000)
        } else if zoom >= 1000 {
            return String(format: "%.1fkm", zoom / 1000)
        } else {
            return String(format: "%.0fm", zoom)
        }
    }
    
    func updateZoomLevel(_ zoom: Double, animated: Bool) {
        guard let knob = knobNode else {
            print("⚠️ [ZoomSlider] updateZoomLevel called but knob not ready, zoom: \(zoom)m")
            return
        }
        
        let centerY = size.height / 2
        let progress = progressForZoomValue(zoom)
        // With inverted progress: 0 = bottom (zoomed in), 1 = top (zoomed out)
        let targetY = -trackHeight/2 + CGFloat(progress) * trackHeight
        let finalY = centerY + targetY
        
        print("🔧 [ZoomSlider] updateZoomLevel: zoom=\(Int(zoom))m, progress=\(String(format: "%.3f", progress)), finalY=\(finalY)")
        
        if animated && !isDragging {
            let moveAction = SKAction.moveTo(y: finalY, duration: 0.3)
            moveAction.timingMode = .easeInEaseOut
            knob.run(moveAction)
        } else {
            knob.position.y = finalY
        }
        
        // Check if we're near a zone for haptic feedback
        if isDragging {
            checkForNotchHaptics(targetY: targetY, knob: knob)
        }
    }
    
    /// Check if knob crossed a notch and trigger haptic feedback
    private func checkForNotchHaptics(targetY: CGFloat, knob: SKShapeNode) {
        // Simplified - trigger feedback every 50 points of movement
        let currentZone = Int(targetY / 50)
        
        if currentZone != lastNotchIndex {
            lastNotchIndex = currentZone
            
            // Trigger haptic feedback
            impactFeedback.impactOccurred(intensity: 0.5)
            
            // Play pop sound
            playPopSound()
            
            // Subtle scale animation on knob
            let scaleUp = SKAction.scale(to: 1.1, duration: 0.1)
            let scaleDown = SKAction.scale(to: 1.0, duration: 0.1)
            knob.run(SKAction.sequence([scaleUp, scaleDown]))
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        guard let knob = knobNode else { return }
        
        // Check if touch is on knob
        if knob.contains(location) {
            isDragging = true
            dragStartY = location.y
            dragStartZoom = zoomLevel
            lastNotchIndex = -1
            
            impactFeedback.prepare()
            
            // Scale up animation
            let scaleAction = SKAction.scale(to: 1.2, duration: 0.2)
            scaleAction.timingMode = .easeOut
            knob.run(scaleAction)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDragging, let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        let deltaY = dragStartY - location.y
        let progress = Double(deltaY) / Double(trackHeight)
        
        // Calculate new zoom exponentially
        let currentProgress = progressForZoomValue(dragStartZoom)
        let newProgress = (currentProgress + progress).clamped(to: 0...1)
        let newZoom = zoomValueForProgress(newProgress)
        
        // Update - with safety check
        guard !newZoom.isNaN && !newZoom.isInfinite else { return }
        
        // Update zoom level without triggering didSet to avoid potential issues
        updateZoomLevel(newZoom, animated: false)
        onZoomChange?(newZoom)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isDragging {
            isDragging = false
            lastNotchIndex = -1
            
            // Scale back animation
            let scaleAction = SKAction.scale(to: 1.0, duration: 0.2)
            scaleAction.timingMode = .easeInEaseOut
            knobNode?.run(scaleAction)
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}

// Helper extension
private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
