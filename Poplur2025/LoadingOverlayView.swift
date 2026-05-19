import SwiftUI
import SpriteKit

/// Lightweight logo sprite for quick video loading states in the feed
/// Shows a large animated logo in the center of the screen occasionally (not every transition)
/// Note: Logo appears only every N transitions to avoid visual fatigue
struct VideoLoadingIndicator: View {
    @Binding var isLoading: Bool
    var logoName: String? = "logo"
    var showEveryNTransitions: Int = 4 // Show logo every 4th transition by default
    
    @State private var scene: CompactLogoScene?
    @State private var transitionCount: Int = 0
    @State private var shouldShowLogo: Bool = false
    
    var body: some View {
        // Only show occasionally (every N transitions)
        Group {
            if isLoading && shouldShowLogo, let scene = scene {
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onChange(of: isLoading) { newValue in
            if newValue {
                // Increment counter on each loading event
                transitionCount += 1
                
                // Only show logo every N transitions
                shouldShowLogo = (transitionCount % showEveryNTransitions == 0)
                
                if shouldShowLogo {
                    // Create scene only when needed
                    let newScene = CompactLogoScene(size: CGSize(width: 300, height: 300))
                    newScene.scaleMode = .aspectFit
                    newScene.backgroundColor = .clear
                    newScene.logoName = logoName
                    scene = newScene
                    print("[VideoLoadingIndicator] Showing logo (transition #\(transitionCount))")
                } else {
                    print("[VideoLoadingIndicator] Skipping logo display (transition #\(transitionCount))")
                }
            } else {
                // Clean up scene when done
                scene = nil
                shouldShowLogo = false
            }
        }
    }
}

/// Radius trend indicator showing if radius increased or decreased
struct RadiusTrendIndicator: View {
    enum Trend {
        case up, down, neutral
        
        var color: Color {
            switch self {
            case .up: return .green
            case .down: return .red
            case .neutral: return .gray
            }
        }
        
        var symbol: String {
            switch self {
            case .up: return "arrow.up"
            case .down: return "arrow.down"
            case .neutral: return "minus"
            }
        }
    }
    
    let trend: Trend
    let radiusDelta: Double // Change in meters
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: trend.symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(trend.color)
            
            if abs(radiusDelta) > 0 {
                Text(formatDelta(radiusDelta))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(trend.color.opacity(0.9))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
    
    private func formatDelta(_ delta: Double) -> String {
        let absDelta = abs(delta)
        if absDelta >= 1000 {
            return String(format: "%.1fkm", absDelta / 1000)
        } else {
            return String(format: "%.0fm", absDelta)
        }
    }
}

/// Compact SpriteKit scene for video loading indicator
final class CompactLogoScene: SKScene {
    var logoName: String? = nil
    private var logoNode: SKSpriteNode?
    private var glowNode: SKEffectNode?
    
    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        view.backgroundColor = .clear
        buildIfNeeded()
        runAnimation()
    }
    
    private func buildIfNeeded() {
        if logoNode != nil { return }
        let texture: SKTexture
        
        // Try to load the logo image from assets
        if let name = logoName, let logoImage = UIImage(named: name) {
            print("[CompactLogoScene] ✅ Successfully loaded logo image: \(name)")
            texture = SKTexture(image: logoImage)
        } else {
            print("[CompactLogoScene] ⚠️ Failed to load logo '\(logoName ?? "nil")' - using fallback sparkles")
            // Fallback to a system-like sparkles image
            let size = CGSize(width: 200, height: 200)
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            let cfg = UIImage.SymbolConfiguration(pointSize: 120, weight: .bold)
            let img = UIImage(systemName: "sparkles", withConfiguration: cfg)?.withTintColor(.white, renderingMode: .alwaysOriginal)
            img?.draw(in: CGRect(origin: .zero, size: size))
            let rendered = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
            UIGraphicsEndImageContext()
            texture = SKTexture(image: rendered)
        }
        
        // Create glow effect container
        let effectNode = SKEffectNode()
        effectNode.shouldEnableEffects = true
        effectNode.shouldRasterize = false
        
        // Create the logo sprite - TWICE AS LARGE (160pt instead of 80pt)
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: 160, height: 160)
        node.position = .zero // Position relative to effect node
        node.zPosition = 10
        
        // Add glow filter for glowing effect
        let blur = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 15.0])
        effectNode.filter = blur
        effectNode.addChild(node)
        
        // Position effect node at center
        effectNode.position = CGPoint(x: size.width/2, y: size.height/2)
        addChild(effectNode)
        
        // Also add a non-glowing version on top for clarity
        let clearNode = SKSpriteNode(texture: texture)
        clearNode.size = CGSize(width: 160, height: 160)
        clearNode.position = CGPoint(x: size.width/2, y: size.height/2)
        clearNode.zPosition = 20
        addChild(clearNode)
        
        logoNode = clearNode
        glowNode = effectNode
        
        print("[CompactLogoScene] Logo node created with size: \(node.size), texture size: \(texture.size())")
    }
    
    private func runAnimation() {
        guard let node = logoNode, let glow = glowNode else { return }
        
        // Remove any existing actions (including any potential rotation)
        node.removeAllActions()
        glow.removeAllActions()
        
        // Ensure no rotation is set
        node.zRotation = 0
        glow.zRotation = 0
        
        // Position logo at center (stays centered, no movement)
        node.position = CGPoint(x: size.width/2, y: size.height/2)
        glow.position = CGPoint(x: size.width/2, y: size.height/2)
        
        // Start invisible and small
        node.alpha = 0
        node.setScale(0.0)
        glow.alpha = 0
        glow.setScale(0.0)
        
        // Smooth fade in
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        fadeIn.timingMode = .easeInEaseOut
        
        // POP animation: Scale from 0 to 1.15 (gentle overshoot) then settle to 1.0
        let scaleUp = SKAction.scale(to: 1.15, duration: 0.4)
        scaleUp.timingMode = .easeOut
        
        let scaleSettle = SKAction.scale(to: 1.0, duration: 0.3)
        scaleSettle.timingMode = .easeInEaseOut
        
        let popSequence = SKAction.sequence([scaleUp, scaleSettle])
        
        // Initial POP animation (fade in + scale) - NO ROTATION
        let initial = SKAction.group([fadeIn, popSequence])
        
        // Continuous gentle pulse while loading (very subtle breathing)
        let pulseUp = SKAction.scale(to: 1.03, duration: 1.2)
        pulseUp.timingMode = .easeInEaseOut
        let pulseDown = SKAction.scale(to: 1.0, duration: 1.2)
        pulseDown.timingMode = .easeInEaseOut
        let pulse = SKAction.sequence([pulseUp, pulseDown])
        
        // Glow pulse (subtle glow intensity change)
        let glowFadeIn = SKAction.fadeAlpha(to: 0.75, duration: 0.5)
        glowFadeIn.timingMode = .easeInEaseOut
        let glowStrong = SKAction.fadeAlpha(to: 0.9, duration: 1.2)
        glowStrong.timingMode = .easeInEaseOut
        let glowWeak = SKAction.fadeAlpha(to: 0.6, duration: 1.2)
        glowWeak.timingMode = .easeInEaseOut
        let glowPulse = SKAction.sequence([glowStrong, glowWeak])
        
        // Run animations - NO ROTATION AT ALL
        node.run(initial) {
            node.run(SKAction.repeatForever(pulse), withKey: "pulse")
        }
        
        glow.run(SKAction.group([glowFadeIn, popSequence])) {
            glow.run(SKAction.repeatForever(glowPulse), withKey: "glowPulse")
        }
    }
}

// MARK: - Deprecated Full-Screen Loading Overlay (kept for reference, remove after migration)

/// ⚠️ DEPRECATED: This full-screen loading overlay causes performance issues.
/// Use VideoLoadingIndicator instead for feed video loading states.
@available(*, deprecated, message: "Use VideoLoadingIndicator for feed loading instead")
struct LoadingOverlayView: View {
    let isPresented: Bool
    var background: Color = .pink
    var logoName: String? = "logo"

    var body: some View {
        // Minimal implementation to avoid breaking existing code
        // This should be removed from all call sites
        EmptyView()
    }
}

// MARK: - Preview

#Preview("Video Loading Indicator") {
    struct PreviewHost: View {
        @State private var isLoading: Bool = false
        
        var body: some View {
            ZStack {
                // Simulated feed background
                LinearGradient(
                    colors: [.purple, .blue, .teal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Video loading indicator
                VideoLoadingIndicator(isLoading: $isLoading, logoName: "logo")
                
                // Controls
                VStack {
                    Spacer()
                    
                    Button(action: {
                        isLoading.toggle()
                    }) {
                        Text(isLoading ? "Hide Indicator" : "Show Indicator")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    return PreviewHost()
}

#Preview("Auto Toggle") {
    struct AutoPreviewHost: View {
        @State private var isLoading: Bool = false
        @State private var transitionNumber: Int = 0
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Show every 3rd transition in preview for faster demonstration
                VideoLoadingIndicator(
                    isLoading: $isLoading, 
                    logoName: "logo",
                    showEveryNTransitions: 3
                )
                
                VStack {
                    Text("Transition #\(transitionNumber)")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                    
                    Text(isLoading ? "Loading..." : "Ready")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Logo shows every 3rd transition")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 8)
                }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    transitionNumber += 1
                    isLoading = true
                    
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    isLoading = false
                }
            }
        }
    }
    
    return AutoPreviewHost()
}
#Preview("Radius Trend Indicators") {
    VStack(spacing: 20) {
        Text("Radius Trend Indicators")
            .font(.title2)
            .fontWeight(.bold)
        
        VStack(spacing: 16) {
            RadiusTrendIndicator(trend: .up, radiusDelta: 5000)
            RadiusTrendIndicator(trend: .up, radiusDelta: 250)
            RadiusTrendIndicator(trend: .down, radiusDelta: -3500)
            RadiusTrendIndicator(trend: .down, radiusDelta: -150)
            RadiusTrendIndicator(trend: .neutral, radiusDelta: 0)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
        LinearGradient(
            colors: [.purple, .blue, .teal],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}

