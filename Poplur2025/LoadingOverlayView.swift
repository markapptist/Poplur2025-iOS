import SwiftUI
import SpriteKit

/// Lightweight logo sprite for quick video loading states in the feed
/// Shows a small animated logo in the center of the screen during transitions
struct VideoLoadingIndicator: View {
    @Binding var isLoading: Bool
    var logoName: String? = "logo"
    
    var body: some View {
        // Disabled globally - no loading spinner shown
        EmptyView()
    }
    
    private func makeLogoScene() -> SKScene {
        let scene = CompactLogoScene(size: CGSize(width: 100, height: 100))
        scene.scaleMode = .aspectFit
        scene.backgroundColor = .clear
        scene.logoName = logoName
        return scene
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
            let size = CGSize(width: 100, height: 100)
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            let cfg = UIImage.SymbolConfiguration(pointSize: 60, weight: .bold)
            let img = UIImage(systemName: "sparkles", withConfiguration: cfg)?.withTintColor(.white, renderingMode: .alwaysOriginal)
            img?.draw(in: CGRect(origin: .zero, size: size))
            let rendered = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
            UIGraphicsEndImageContext()
            texture = SKTexture(image: rendered)
        }
        
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: 80, height: 80)
        node.position = CGPoint(x: size.width/2, y: size.height/2)
        node.zPosition = 10
        logoNode = node
        addChild(node)
        
        print("[CompactLogoScene] Logo node created with size: \(node.size), texture size: \(texture.size())")
    }
    
    private func runAnimation() {
        guard let node = logoNode else { return }
        node.removeAllActions()
        
        // Start from above the screen
        node.position.y = size.height + 50
        
        // Animate down to center
        let moveDown = SKAction.moveTo(y: size.height/2, duration: 0.3)
        moveDown.timingMode = .easeOut
        
        // Gentle pulse while loading
        let scaleUp = SKAction.scale(to: 1.1, duration: 0.5)
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.5)
        let pulse = SKAction.sequence([scaleUp, scaleDown])
        pulse.timingMode = .easeInEaseOut
        
        // Fade in
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.2)
        
        // Initial drop + fade
        let initial = SKAction.group([moveDown, fadeIn])
        
        // Run initial animation then loop pulse
        node.run(initial) {
            node.run(SKAction.repeatForever(pulse), withKey: "pulse")
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
        @State private var isLoading: Bool = true
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VideoLoadingIndicator(isLoading: $isLoading, logoName: "logo")
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    isLoading.toggle()
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

