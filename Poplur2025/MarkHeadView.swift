import SwiftUI
import UIKit
import SceneKit

/// SceneKit view that loads the required MarkHead scene from the asset catalog.
/// The model references a `temp.fbm` texture folder, so the data asset and its texture images
/// are staged together in Caches before SceneKit opens the model URL.
struct MarkHeadView: UIViewRepresentable {
    @Binding var isSpeaking: Bool

    static var hasBundledModel: Bool {
        requiredModelURL != nil
    }

    private static let sceneAssetName = "MarkHeadScene"
    private static let assetCatalogFolder = "MarkHead"
    private static let textureAssetName = "Meshy_AI_Mark_character_head_3_0630045036_image-to-3d-texture"
    private static let runtimeFolderName = "MarkHeadRuntime.v4"
    private static let colorTextureFilename = "Image_0.jpg"
    private static let emissionTextureFilename = "Image_3.jpg"

    private static let requiredModelURL: URL? = {
        do {
            return try stageRequiredModel()
        } catch {
            print("[MarkHeadView] Failed to stage required MarkHead model: \(error.localizedDescription)")
            return nil
        }
    }()

    private static func stageRequiredModel() throws -> URL {
        if let modelAsset = dataAsset(named: sceneAssetName) {
            return try stageModelData(modelAsset.data)
        }

        guard let bundledModelURL = Bundle.main.url(forResource: "MarkHead", withExtension: "scn") else {
            throw MarkHeadLoadError.missingRequiredModel
        }
        return try stageModelData(Data(contentsOf: bundledModelURL))
    }

    private static func stageModelData(_ modelData: Data) throws -> URL {
        let fileManager = FileManager.default
        let root = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent(runtimeFolderName, isDirectory: true)
        let textureDirectory = root.appendingPathComponent("temp.fbm", isDirectory: true)

        try fileManager.createDirectory(at: textureDirectory, withIntermediateDirectories: true)

        let modelURL = root.appendingPathComponent("MarkHead.scn")
        try write(modelData, to: modelURL)

        let textures: [(asset: String, filename: String, quality: CGFloat)] = [
            ("\(textureAssetName)e", colorTextureFilename, 0.96),
            ("\(textureAssetName)_emission", emissionTextureFilename, 0.96)
        ]

        for texture in textures {
            let destinationURL = textureDirectory.appendingPathComponent(texture.filename)
            if let image = imageAsset(named: texture.asset),
               let data = image.jpegData(compressionQuality: texture.quality) {
                try write(data, to: destinationURL)
            } else if let bundledTextureURL = bundledTextureURL(filename: texture.filename) {
                try write(Data(contentsOf: bundledTextureURL), to: destinationURL)
            } else {
                throw MarkHeadLoadError.missingTextureAsset(texture.asset)
            }
        }

        return modelURL
    }

    private static func dataAsset(named name: String) -> NSDataAsset? {
        let candidates = [
            name,
            "\(assetCatalogFolder)/\(name)"
        ]
        for candidate in candidates {
            if let asset = NSDataAsset(name: candidate) {
                return asset
            }
        }
        return nil
    }

    private static func imageAsset(named name: String) -> UIImage? {
        let candidates = [
            name,
            "\(assetCatalogFolder)/\(name)"
        ]
        for candidate in candidates {
            if let image = UIImage(named: candidate, in: .main, compatibleWith: nil) {
                return image
            }
        }
        return nil
    }

    private static func bundledTextureURL(filename: String) -> URL? {
        let resourceName = (filename as NSString).deletingPathExtension
        let resourceExtension = (filename as NSString).pathExtension
        return Bundle.main.url(forResource: resourceName, withExtension: resourceExtension)
    }

    private static func stagedTextureURL(filename: String) -> URL? {
        requiredModelURL?
            .deletingLastPathComponent()
            .appendingPathComponent("temp.fbm", isDirectory: true)
            .appendingPathComponent(filename)
    }

    private static func write(_ data: Data, to url: URL) throws {
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
           size.intValue == data.count {
            return
        }
        try data.write(to: url, options: .atomic)
    }

    private enum MarkHeadLoadError: LocalizedError {
        case missingRequiredModel
        case missingTextureAsset(String)

        var errorDescription: String? {
            switch self {
            case .missingRequiredModel:
                return "Missing MarkHeadScene data asset and bundled MarkHead.scn resource."
            case .missingTextureAsset(let name):
                return "Missing MarkHead texture image asset named \(name)."
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.isOpaque = false
        v.backgroundColor = .clear
        v.allowsCameraControl = false
        v.antialiasingMode = .multisampling4X
        v.autoenablesDefaultLighting = false
        v.isPlaying = true
        v.rendersContinuously = true
        v.scene = SCNScene()
        context.coordinator.load(into: v)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        if isSpeaking {
            context.coordinator.startSpeaking()
        } else {
            context.coordinator.stopSpeaking()
        }
    }

    // MARK: - Coordinator

    final class Coordinator {
        private weak var scnView: SCNView?
        private var pivot: SCNNode?
        private var jawNode: SCNNode?
        private var mouthTimer: Timer?
        private var mouthOpen = false
        private var isLoaded = false
        private var pendingSpeaking = false

        func load(into view: SCNView) {
            scnView = view
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak view] in
                guard let self = self, let view = view else { return }
                let maybeScene = self.loadScene()
                DispatchQueue.main.async {
                    if let scene = maybeScene {
                        self.configure(scene, in: view)
                    } else {
                        print("[MarkHeadView] MarkHead model could not be loaded. No alternate head will be shown.")
                        view.scene = SCNScene()
                        self.isLoaded = false
                        self.pendingSpeaking = false
                    }
                }
            }
        }

        private func loadScene() -> SCNScene? {
            guard let url = MarkHeadView.requiredModelURL else { return nil }
            do {
                return try SCNScene(url: url, options: sceneLoadingOptions(for: url))
            } catch {
                print("[MarkHeadView] SceneKit failed to load staged MarkHead scene: \(error.localizedDescription)")
                return nil
            }
        }

        private func sceneLoadingOptions(for url: URL) -> [SCNSceneSource.LoadingOption: Any] {
            var assetDirectories: [URL] = [url.deletingLastPathComponent()]
            if let resourceURL = Bundle.main.resourceURL {
                assetDirectories.append(resourceURL)
            }
            return [
                .convertUnitsToMeters: true,
                .convertToYUp: true,
                .assetDirectoryURLs: assetDirectories
            ]
        }

        private func configure(_ importedScene: SCNScene, in view: SCNView) {
            let scene = SCNScene()
            scene.background.contents = UIColor.clear

            let modelRoot = SCNNode()
            importedScene.rootNode.childNodes.forEach { node in
                node.removeFromParentNode()
                modelRoot.addChildNode(node)
            }

            let bounds = Coordinator.recursiveBounds(in: modelRoot) ?? modelRoot.boundingBox
            let (minBB, maxBB) = bounds
            let extX = Float(maxBB.x - minBB.x)
            let extY = Float(maxBB.y - minBB.y)
            let extZ = Float(maxBB.z - minBB.z)
            let maxExt = Swift.max(extX, Swift.max(extY, extZ))
            let s: Float = maxExt > 0 ? 1.22 / maxExt : 1.0
            let cx = Float((minBB.x + maxBB.x) / 2)
            let cy = Float((minBB.y + maxBB.y) / 2)
            let cz = Float((minBB.z + maxBB.z) / 2)

            modelRoot.name = "MarkPivot"
            Coordinator.applyRequiredTexture(to: modelRoot)
            modelRoot.scale = SCNVector3(s, s, s)
            modelRoot.position = SCNVector3(
                -cx * s,
                (-cy * s) + 0.04,
                -cz * s
            )
            scene.rootNode.addChildNode(modelRoot)
            pivot = modelRoot

            // Find jaw bone — try exact names, then partial match
            jawNode = Coordinator.findJaw(in: scene.rootNode)

            // Lighting
            let amb = SCNNode(); amb.light = SCNLight()
            amb.light?.type = .ambient; amb.light?.intensity = 450
            scene.rootNode.addChildNode(amb)

            let key = SCNNode(); key.light = SCNLight()
            key.light?.type = .directional; key.light?.intensity = 1000
            key.eulerAngles = SCNVector3(-0.4, 0.4, 0)
            scene.rootNode.addChildNode(key)

            let rim = SCNNode(); rim.light = SCNLight()
            rim.light?.type = .directional; rim.light?.intensity = 300
            rim.light?.color = UIColor(red: 0.55, green: 0.70, blue: 1.0, alpha: 1)
            rim.eulerAngles = SCNVector3(0.15, Float.pi - 0.35, 0)
            scene.rootNode.addChildNode(rim)

            // Camera: framed to show head region
            let cam = SCNNode(); cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 32
            cam.position = SCNVector3(0, 0.04, 2.45)
            scene.rootNode.addChildNode(cam)
            view.pointOfView = cam

            // Idle animations: gentle float + sway on the pivot
            let floatUp = SCNAction.moveBy(x: 0, y: 0.007, z: 0, duration: 1.6)
            let floatDn = SCNAction.moveBy(x: 0, y: -0.007, z: 0, duration: 1.6)
            floatUp.timingMode = .easeInEaseOut; floatDn.timingMode = .easeInEaseOut
            modelRoot.runAction(.repeatForever(.sequence([floatUp, floatDn])))

            let swayL = SCNAction.rotateBy(x: 0, y: 0.07, z: 0, duration: 2.4)
            let swayR = SCNAction.rotateBy(x: 0, y: -0.07, z: 0, duration: 2.4)
            swayL.timingMode = .easeInEaseOut; swayR.timingMode = .easeInEaseOut
            modelRoot.runAction(.repeatForever(.sequence([swayL, swayR])))

            view.scene = scene
            isLoaded = true
            if pendingSpeaking { startSpeaking() }
        }

        private static func findJaw(in root: SCNNode) -> SCNNode? {
            for name in ["Jaw", "jaw", "JAW", "Head_Jaw", "jaw_M", "Jaw_M"] {
                if let n = root.childNode(withName: name, recursively: true) { return n }
            }
            return root.childNodes(passingTest: { n, _ in
                guard let nm = n.name?.lowercased() else { return false }
                return nm.contains("jaw") || nm.contains("mandible")
            }).first
        }

        private static func applyRequiredTexture(to root: SCNNode) {
            guard let colorURL = MarkHeadView.stagedTextureURL(filename: MarkHeadView.colorTextureFilename),
                  let colorImage = UIImage(contentsOfFile: colorURL.path) else {
                return
            }

            func visit(_ node: SCNNode) {
                node.geometry?.materials.forEach { material in
                    material.diffuse.contents = colorImage
                    material.normal.contents = nil
                    material.emission.contents = UIColor.clear
                    material.metalness.contents = 0
                    material.roughness.contents = 0.58
                    material.lightingModel = .physicallyBased
                    material.isDoubleSided = true
                }
                node.childNodes.forEach(visit)
            }

            visit(root)
        }

        private static func recursiveBounds(in root: SCNNode) -> (SCNVector3, SCNVector3)? {
            var found = false
            var minV = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
            var maxV = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)

            func include(_ point: SCNVector3) {
                found = true
                minV.x = Swift.min(minV.x, point.x)
                minV.y = Swift.min(minV.y, point.y)
                minV.z = Swift.min(minV.z, point.z)
                maxV.x = Swift.max(maxV.x, point.x)
                maxV.y = Swift.max(maxV.y, point.y)
                maxV.z = Swift.max(maxV.z, point.z)
            }

            func visit(_ node: SCNNode) {
                if node.geometry != nil {
                    let (minBB, maxBB) = node.boundingBox
                    let corners = [
                        SCNVector3(minBB.x, minBB.y, minBB.z),
                        SCNVector3(minBB.x, minBB.y, maxBB.z),
                        SCNVector3(minBB.x, maxBB.y, minBB.z),
                        SCNVector3(minBB.x, maxBB.y, maxBB.z),
                        SCNVector3(maxBB.x, minBB.y, minBB.z),
                        SCNVector3(maxBB.x, minBB.y, maxBB.z),
                        SCNVector3(maxBB.x, maxBB.y, minBB.z),
                        SCNVector3(maxBB.x, maxBB.y, maxBB.z)
                    ]
                    for corner in corners {
                        include(node.convertPosition(corner, to: root))
                    }
                }
                node.childNodes.forEach(visit)
            }

            visit(root)
            return found ? (minV, maxV) : nil
        }

        func startSpeaking() {
            guard isLoaded else { pendingSpeaking = true; return }
            pendingSpeaking = false
            mouthTimer?.invalidate()
            mouthOpen = false
            mouthTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.mouthOpen.toggle()
                self.setMouth(open: self.mouthOpen)
            }
        }

        func stopSpeaking() {
            pendingSpeaking = false
            mouthTimer?.invalidate(); mouthTimer = nil
            setMouth(open: false)
        }

        private func setMouth(open: Bool) {
            guard let jaw = jawNode else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.08
            jaw.eulerAngles.x = open ? 0.08 : 0
            SCNTransaction.commit()
        }

        deinit { mouthTimer?.invalidate() }
    }
}
