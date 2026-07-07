import SwiftUI
import SpriteKit

// MARK: - SwiftUI host for the native SpriteKit PoplurFPS game

struct FPSSpriteKitView: UIViewRepresentable {
    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.backgroundColor = .black
        #if DEBUG
        view.showsFPS = false
        view.showsNodeCount = false
        #endif

        let scene = FPSGameScene(size: CGSize(width: FPSK.screenW, height: FPSK.screenH))
        scene.scaleMode = .aspectFit
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {}
}
