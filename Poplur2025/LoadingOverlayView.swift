import SwiftUI
import SpriteKit

struct LoadingOverlayView: View {
    // Controls visibility from parent
    let isPresented: Bool
    // Optional brand color; defaults to pink to match previous design
    var background: Color = .pink
    // Optional logo image name
    var logoName: String? = "logo"

    var body: some View {
        ZStack {
            if isPresented {
                GeometryReader { geo in
                    ZStack {
                        background
                            .ignoresSafeArea()
                            .transition(.opacity)

                        // SpriteKit-based logo animation filling the screen
                        SpriteView(scene: makeLogoScene(size: geo.size, logoName: logoName))
                            .background(Color.clear)
                            .ignoresSafeArea()
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.35), value: isPresented)
        /*
        // Previous SwiftUI animation implementation for reference:
        ZStack {
            if isPresented {
                background
                    .ignoresSafeArea()
                    .transition(.opacity)
                Group {
                    if let name = logoName, UIImage(named: name) != nil {
                        Image(name)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 80, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.35), value: isPresented)
        */
    }

    private func makeLogoScene(size: CGSize, logoName: String?) -> SKScene {
        let scene = LogoScene(size: size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        scene.logoName = logoName
        return scene
    }
}

final class LogoScene: SKScene {
    var logoName: String? = nil
    private var logoNode: SKSpriteNode?
    var animationSpeedFactor: CGFloat = 1.0 { didSet { updateSpeeds() } }
    var shouldLoop: Bool = true { didSet { restartIfNeeded() } }

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
        if let name = logoName, UIImage(named: name) != nil {
            texture = SKTexture(imageNamed: name)
        } else {
            // Fallback to a system-like sparkles image by drawing a SF Symbol into a texture
            let size = CGSize(width: 256, height: 256)
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            let cfg = UIImage.SymbolConfiguration(pointSize: 180, weight: .bold)
            let img = UIImage(systemName: "sparkles", withConfiguration: cfg)?.withTintColor(.white, renderingMode: .alwaysOriginal)
            img?.draw(in: CGRect(origin: .zero, size: size))
            let rendered = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
            UIGraphicsEndImageContext()
            texture = SKTexture(image: rendered)
        }
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: 200, height: 200)
        node.position = CGPoint(x: size.width/2, y: size.height/2)
        node.zPosition = 10
        logoNode = node
        addChild(node)
    }

    private func runAnimation() {
        guard let node = logoNode else { return }
        node.removeAllActions()
        let scaleUp = SKAction.scale(to: 1.15, duration: 0.6)
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.6)
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.3)
        let pulse = SKAction.sequence([scaleUp, scaleDown])
        pulse.timingMode = .easeInEaseOut
        let group = SKAction.group([pulse, fadeIn])
        group.speed = CGFloat(animationSpeedFactor)
        if shouldLoop {
            node.run(SKAction.repeatForever(group), withKey: "loop")
        } else {
            node.run(group, withKey: "once")
        }
    }

    private func updateSpeeds() {
        guard let node = logoNode else { return }
        node.speed = CGFloat(animationSpeedFactor)
        // Also update action speed where supported by re-running
        if node.action(forKey: "loop") != nil || node.action(forKey: "once") != nil {
            runAnimation()
        }
    }

    private func restartIfNeeded() {
        runAnimation()
    }
}

/*
#Preview {
    LoadingOverlayView(isPresented: true)
}
*/

#Preview("LoadingOverlay SpriteKit") {
    struct PreviewHost: View {
        @State private var presented: Bool = true
        @State private var loop: Bool = true
        @State private var speed: CGFloat = 1.0
        @State private var bg: Color = .pink
        @State private var logo: String? = "logo"

        var body: some View {
            VStack(spacing: 12) {
                // Controls
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Presented", isOn: $presented)
                    Toggle("Loop", isOn: $loop)
                    HStack { Text(String(format: "Speed x%.2f", speed)); Slider(value: $speed, in: 0.2...3.0) }
                    ColorPicker("Background", selection: $bg)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                ZStack {
                    LoadingOverlaySpriteContainer(isPresented: presented, background: bg, logoName: logo, loop: loop, speed: speed)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 6)
                }
            }
            .padding()
        }
    }

    // A small wrapper that allows us to pass loop/speed into the SpriteKit scene
    struct LoadingOverlaySpriteContainer: View {
        let isPresented: Bool
        var background: Color
        var logoName: String?
        var loop: Bool
        var speed: CGFloat

        var body: some View {
            ZStack {
                if isPresented {
                    background.ignoresSafeArea()
                    SpriteView(scene: configuredScene())
                        .ignoresSafeArea()
                }
            }
        }

        private func configuredScene() -> SKScene {
            let scene = LogoScene(size: CGSize(width: 600, height: 600))
            scene.scaleMode = .resizeFill
            scene.backgroundColor = .clear
            scene.logoName = logoName
            scene.shouldLoop = loop
            scene.animationSpeedFactor = speed
            return scene
        }
    }

    return PreviewHost()
}
