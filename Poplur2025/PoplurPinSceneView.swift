import SwiftUI
import SceneKit
import UIKit

/// Loads + normalizes the bundled Poplur pin model (`poplur_pin.glb`).
enum PoplurPinModel {
    static func makeNode() -> SCNNode? {
        guard let url = RuntimeGLBLoader.bundledURL(
            named: "poplur_pin",
            candidateSubdirectories: ["PopularObjects", "Models", ""]
        ), let scene = RuntimeGLBLoader.loadScene(from: url, label: "poplur_pin") else {
            return nil
        }
        let content = SCNNode()
        scene.rootNode.childNodes.forEach { content.addChildNode($0.clone()) }
        guard !content.childNodes.isEmpty else { return nil }
        RuntimeGLBLoader.normalize(content, targetExtent: 1.7)
        return content
    }

    static var isAvailable: Bool {
        RuntimeGLBLoader.bundledURL(
            named: "poplur_pin",
            candidateSubdirectories: ["PopularObjects", "Models", ""]
        ) != nil
    }
}

/// Renders the (heavy) 3D pin model **once** to a transparent image and caches it, so every
/// map pin can draw a cheap `Image` instead of its own live SCNView. At pin size this is
/// visually identical to a live 3D view but costs a fraction of the memory/GPU.
@MainActor
enum PoplurPinRenderer {
    private static var cachedImage: UIImage?
    private static var isRendering = false
    private static var waiters: [(UIImage?) -> Void] = []

    /// Async: hands back the pre-rendered pin image (rendering it on first call, then cached).
    static func image(_ completion: @escaping (UIImage?) -> Void) {
        if let cachedImage {
            completion(cachedImage)
            return
        }
        waiters.append(completion)
        guard !isRendering else { return }
        isRendering = true
        // Defer a tick so the map can appear before the one-time decode/render hitch.
        DispatchQueue.main.async {
            let image = render()
            cachedImage = image
            isRendering = false
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0(image) }
        }
    }

    private static func render() -> UIImage? {
        guard let pin = PoplurPinModel.makeNode() else { return nil }

        let size = CGSize(width: 260, height: 340)
        let scnView = SCNView(frame: CGRect(origin: .zero, size: size))
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        scene.background.contents = nil
        scnView.scene = scene

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 34
        cameraNode.position = SCNVector3(0, 0, 3.6)
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 540
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 1000
        key.position = SCNVector3(-1.4, 2.0, 2.6)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 340
        fill.eulerAngles = SCNVector3(-0.6, 0.7, 0.1)
        scene.rootNode.addChildNode(fill)

        scene.rootNode.addChildNode(pin)

        // snapshot() forces a GPU render and preserves alpha (clear background).
        return scnView.snapshot()
    }
}

/// Map annotation that shows the 3D Poplur pin (as a cached rendered image, with a subtle
/// bob). Falls back to the flat beacon marker until the image is ready / if it can't render.
struct PoplurPinAnnotationView: View {
    let fallbackColor: Color
    var skin: CubeSkin = .standard

    @State private var image: UIImage?
    @State private var bobbing = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .offset(y: bobbing ? -3 : 3)
                    .shadow(color: .black.opacity(0.28), radius: 5, x: 0, y: 4)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                            bobbing = true
                        }
                    }
            } else {
                Enhanced3DBeaconMarker(color: fallbackColor, intensity: 0.6, skin: skin, role: .post)
            }
        }
        .onAppear {
            if image == nil {
                PoplurPinRenderer.image { rendered in
                    if let rendered { image = rendered }
                }
            }
        }
    }
}
