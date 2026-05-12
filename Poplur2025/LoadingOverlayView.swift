import SwiftUI
import SpriteKit

/// Lightweight logo sprite for quick video loading states in the feed
/// Shows a small animated logo in the center of the screen during transitions
struct VideoLoadingIndicator: View {
    @Binding var isLoading: Bool
    var logoName: String? = "logo"
    
    var body: some View {
        ZStack {
            if isLoading {
                // Small centered logo sprite
                SpriteView(scene: makeLogoScene(), options: [.allowsTransparency])
                    .frame(width: 100, height: 100)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isLoading)
    }
    
    private func makeLogoScene() -> SKScene {
        let scene = CompactLogoScene(size: CGSize(width: 100, height: 100))
        scene.scaleMode = .aspectFit
        scene.backgroundColor = .clear
        scene.logoName = logoName
        return scene
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

