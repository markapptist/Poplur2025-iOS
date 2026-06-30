import SwiftUI
import UIKit
import SceneKit

/// SceneKit view that loads a native MarkHead asset and animates the Jaw bone when speaking.
/// MarkHead.scn is the required runtime asset. The FBX/DAE files are source assets only.
struct MarkHeadView: UIViewRepresentable {
    @Binding var isSpeaking: Bool

    static var hasBundledModel: Bool {
        requiredModelURL != nil
    }

    private static var requiredModelURL: URL? {
        Bundle.main.url(forResource: "MarkHead", withExtension: "scn")
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.allowsCameraControl = false
        v.antialiasingMode = .multisampling4X
        v.autoenablesDefaultLighting = false
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
            guard let modelURL = MarkHeadView.requiredModelURL else {
                assertionFailure("[MarkHeadView] Required MarkHead.scn is missing. No fallback head will be shown.")
                return
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let scene = try? SCNScene(url: modelURL, options: [
                    SCNSceneSource.LoadingOption.convertUnitsToMeters: true,
                    SCNSceneSource.LoadingOption.convertToYUp: true
                ]) else {
                    assertionFailure("[MarkHeadView] Failed to load required model: \(modelURL.lastPathComponent)")
                    return
                }
                DispatchQueue.main.async { self?.configure(scene, in: view) }
            }
        }

        private func configure(_ scene: SCNScene, in view: SCNView) {
            // Auto-fit: scale so the largest extent = 0.28m
            let (minBB, maxBB) = scene.rootNode.boundingBox
            let extX = Float(maxBB.x - minBB.x)
            let extY = Float(maxBB.y - minBB.y)
            let extZ = Float(maxBB.z - minBB.z)
            let maxExt = Swift.max(extX, Swift.max(extY, extZ))
            let s: Float = maxExt > 0 ? 0.28 / maxExt : 1.0
            let cx = Float((minBB.x + maxBB.x) / 2)
            let cy = Float((minBB.y + maxBB.y) / 2)
            let cz = Float((minBB.z + maxBB.z) / 2)

            // Wrap model nodes in a pivot for animation control
            let p = SCNNode(); p.name = "MarkPivot"
            p.scale = SCNVector3(s, s, s)
            let fittedX = -cx * s
            let fittedY = (-cy * s) + 0.02
            let fittedZ = -cz * s
            p.position = SCNVector3(fittedX, fittedY, fittedZ)
            scene.rootNode.childNodes.forEach { node in
                node.removeFromParentNode(); p.addChildNode(node)
            }
            scene.rootNode.addChildNode(p)
            pivot = p

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
            cam.camera?.fieldOfView = 38
            cam.position = SCNVector3(0, 0.04, 0.5)
            scene.rootNode.addChildNode(cam)
            view.pointOfView = cam

            // Idle animations: gentle float + sway on the pivot
            let floatUp = SCNAction.moveBy(x: 0, y: 0.007, z: 0, duration: 1.6)
            let floatDn = SCNAction.moveBy(x: 0, y: -0.007, z: 0, duration: 1.6)
            floatUp.timingMode = .easeInEaseOut; floatDn.timingMode = .easeInEaseOut
            p.runAction(.repeatForever(.sequence([floatUp, floatDn])))

            let swayL = SCNAction.rotateBy(x: 0, y: 0.07, z: 0, duration: 2.4)
            let swayR = SCNAction.rotateBy(x: 0, y: -0.07, z: 0, duration: 2.4)
            swayL.timingMode = .easeInEaseOut; swayR.timingMode = .easeInEaseOut
            p.runAction(.repeatForever(.sequence([swayL, swayR])))

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
