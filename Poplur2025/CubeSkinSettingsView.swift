import SwiftUI
import SceneKit

struct CubeSkinSettingsView: View {
    @StateObject private var store = CubeSkinStore.shared
    @State private var selection: CubeSkin = CubeSkinStore.shared.current

    var body: some View {
        VStack(spacing: 16) {
            Text("Cube Skins").font(.title).bold()
            Text("Choose a skin and preview it below. Tap Apply to use it across the app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Picker of available skins
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CubeSkin.allCases) { skin in
                        Button {
                            selection = skin
                        } label: {
                            VStack(spacing: 8) {
                                SkinThumbnailView(skin: skin)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(skin.displayName)
                                    .font(.caption)
                                    .foregroundStyle(skin == selection ? .primary : .secondary)
                            }
                            .padding(8)
                            .background(skin == selection ? Color.accentColor.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            // SceneKit preview
            CubeSkinPreviewSceneView(skin: selection)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8, y: 4)
                .padding(.horizontal)

            HStack {
                Spacer()
                Button("Apply") {
                    store.apply(selection)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
        }
        .onAppear { selection = store.current }
    }
}

private struct SkinThumbnailView: View {
    let skin: CubeSkin
    var body: some View {
        let img = UIImage(named: skin.diffuseAssetName) ?? skin.makeTexture()
        Image(uiImage: img).resizable().scaledToFill()
    }
}

private struct CubeSkinPreviewSceneView: UIViewRepresentable {
    let skin: CubeSkin

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.scene = makeScene()
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let cube = uiView.scene?.rootNode.childNode(withName: "cube", recursively: false),
              let box = cube.geometry as? SCNBox else { return }
        let skinTexture = skinImage(for: skin)
        for m in box.materials { m.diffuse.contents = skinTexture }
        uiView.isPlaying = true
    }

    private func skinImage(for skin: CubeSkin) -> UIImage {
        UIImage(named: skin.diffuseAssetName) ?? skin.makeTexture()
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        let cam = SCNCamera()
        cam.fieldOfView = 45
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 0, 4.5)
        scene.rootNode.addChildNode(camNode)

        let dir = SCNLight()
        dir.type = .directional
        dir.intensity = 600
        let dirNode = SCNNode()
        dirNode.light = dir
        dirNode.eulerAngles = SCNVector3(-Float.pi/4, Float.pi/4, 0)
        scene.rootNode.addChildNode(dirNode)

        let omni = SCNLight()
        omni.type = .omni
        omni.intensity = 300
        let omniNode = SCNNode()
        omniNode.light = omni
        omniNode.position = SCNVector3(2, 2, 2)
        scene.rootNode.addChildNode(omniNode)

        let box = SCNBox(width: 1.3, height: 1.3, length: 1.3, chamferRadius: 0.25)
        box.chamferSegmentCount = 8
        let node = SCNNode(geometry: box)
        node.name = "cube"
        scene.rootNode.addChildNode(node)

        let skinTexture = skinImage(for: skin)
        let materials: [SCNMaterial] = (0..<6).map { _ in
            let m = SCNMaterial()
            m.diffuse.contents = skinTexture
            m.multiply.contents = UIColor.white
            m.emission.intensity = 0.8
            m.lightingModel = .physicallyBased
            m.metalness.contents = 0.0
            m.roughness.contents = 1.0
            return m
        }
        box.materials = materials

        // Slow spin for preview
        let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 12.0))
        spin.timingMode = .linear
        node.runAction(spin)

        return scene
    }
}

#Preview("Cube Skins") {
    CubeSkinSettingsView()
}
