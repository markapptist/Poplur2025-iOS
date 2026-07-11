import SwiftUI
import SpriteKit

// MARK: - SwiftUI host for the native SpriteKit PoplurFPS game

struct FPSSpriteKitView: UIViewRepresentable {
    /// Invoked when the player picks QUIT in the in-game pause menu.
    var onQuit: (() -> Void)? = nil

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.backgroundColor = .black
        #if DEBUG
        view.showsFPS = false
        view.showsNodeCount = false
        #endif

        // Fill the view and adapt to rotation; the scene lays out its game "CRT"
        // band + controls per orientation each frame.
        let initial = UIScreen.main.bounds.size
        let scene = FPSGameScene(size: initial == .zero ? CGSize(width: FPSK.screenW, height: FPSK.screenH) : initial)
        scene.scaleMode = .resizeFill
        scene.onQuit = onQuit
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {}
}
