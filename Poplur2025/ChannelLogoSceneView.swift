import SwiftUI
import SceneKit
import UIKit

struct ChannelObjectSceneView: UIViewRepresentable {
    let channelId: String
    let objectId: String

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.isJitteringEnabled = true
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.isUserInteractionEnabled = false

        let scene = SCNScene()
        view.scene = scene

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 40
        cameraNode.position = SCNVector3(0, 0, 3.35)
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 420
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 980
        key.position = SCNVector3(-1.4, 1.9, 2.4)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 320
        fill.eulerAngles = SCNVector3(-0.6, 0.7, 0.1)
        scene.rootNode.addChildNode(fill)

        let objectNode = makeObjectNode()
        objectNode.scale = SCNVector3(0.01, 0.01, 0.01)
        scene.rootNode.addChildNode(objectNode)

        let pop = SCNAction.sequence([
            SCNAction.scale(to: 1.14, duration: 0.18),
            SCNAction.scale(to: 0.94, duration: 0.10),
            SCNAction.scale(to: 1.0, duration: 0.08)
        ])
        let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 3.4))
        objectNode.runAction(pop) {
            objectNode.runAction(spin)
        }

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    private func makeObjectNode() -> SCNNode {
        switch objectId {
        case "banana", "croissant", "guitar", "shoe":
            return capsuleObject(color: objectColor(), radius: 0.17, height: 1.45, zRotation: .pi / 2, xRotation: 0.18)
        case "dumbbell":
            return dumbbellObject()
        case "cake":
            return stackedCylinderObject(base: UIColor(red: 1.0, green: 0.42, blue: 0.66, alpha: 1), top: UIColor(red: 1.0, green: 0.86, blue: 0.92, alpha: 1))
        case "lipstick", "microphone":
            return cylinderObject(color: objectColor(), radius: 0.32, height: 1.35)
        case "ball", "fruit", "globe", "sun", "sparkle", "star":
            return sphereObject(color: objectColor(), radius: 0.68)
        case "trophy", "dress", "eiffel", "fan", "spotlight":
            return coneObject(color: objectColor(), topRadius: 0.14, bottomRadius: 0.68, height: 1.35)
        case "compact", "laptop", "newspaper", "note", "beret":
            return boxObject(color: objectColor(), width: 1.34, height: 0.18, length: 0.92, chamfer: 0.08)
        case "camera", "speaker", "chip", "controller", "bag":
            return boxObject(color: objectColor(), width: 1.18, height: 0.86, length: 0.72, chamfer: 0.10)
        default:
            return sphereObject(color: channelFallbackColor(), radius: 0.68)
        }
    }

    private func sphereObject(color: UIColor, radius: CGFloat) -> SCNNode {
        let geometry = SCNSphere(radius: radius)
        geometry.segmentCount = 48
        geometry.materials = [material(color)]
        return SCNNode(geometry: geometry)
    }

    private func cylinderObject(color: UIColor, radius: CGFloat, height: CGFloat) -> SCNNode {
        let geometry = SCNCylinder(radius: radius, height: height)
        geometry.radialSegmentCount = 48
        geometry.materials = [material(color)]
        let node = SCNNode(geometry: geometry)
        node.eulerAngles.z = .pi / 2
        return node
    }

    private func stackedCylinderObject(base: UIColor, top: UIColor) -> SCNNode {
        let root = SCNNode()
        let cake = SCNCylinder(radius: 0.58, height: 0.56)
        cake.radialSegmentCount = 48
        cake.materials = [material(base)]
        let cakeNode = SCNNode(geometry: cake)
        cakeNode.position.y = -0.12
        root.addChildNode(cakeNode)

        let frosting = SCNCylinder(radius: 0.5, height: 0.20)
        frosting.radialSegmentCount = 48
        frosting.materials = [material(top)]
        let frostingNode = SCNNode(geometry: frosting)
        frostingNode.position.y = 0.28
        root.addChildNode(frostingNode)
        return root
    }

    private func capsuleObject(color: UIColor, radius: CGFloat, height: CGFloat, zRotation: Float, xRotation: Float = 0) -> SCNNode {
        let geometry = SCNCapsule(capRadius: radius, height: height)
        geometry.radialSegmentCount = 32
        geometry.materials = [material(color)]
        let node = SCNNode(geometry: geometry)
        node.eulerAngles = SCNVector3(xRotation, 0, zRotation)
        return node
    }

    private func dumbbellObject() -> SCNNode {
        let root = SCNNode()
        root.addChildNode(capsuleObject(color: objectColor(), radius: 0.10, height: 1.35, zRotation: .pi / 2))
        [-0.56, 0.56].forEach { x in
            let weight = SCNCylinder(radius: 0.25, height: 0.28)
            weight.radialSegmentCount = 32
            weight.materials = [material(UIColor(red: 0.40, green: 1.0, blue: 0.48, alpha: 1))]
            let node = SCNNode(geometry: weight)
            node.position.x = Float(x)
            node.eulerAngles.z = .pi / 2
            root.addChildNode(node)
        }
        return root
    }

    private func coneObject(color: UIColor, topRadius: CGFloat, bottomRadius: CGFloat, height: CGFloat) -> SCNNode {
        let geometry = SCNCone(topRadius: topRadius, bottomRadius: bottomRadius, height: height)
        geometry.radialSegmentCount = 48
        geometry.materials = [material(color)]
        return SCNNode(geometry: geometry)
    }

    private func boxObject(color: UIColor, width: CGFloat, height: CGFloat, length: CGFloat, chamfer: CGFloat) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: chamfer)
        geometry.materials = [material(color)]
        let node = SCNNode(geometry: geometry)
        node.eulerAngles.x = -0.18
        return node
    }

    private func material(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .lambert
        return material
    }

    private func objectColor() -> UIColor {
        switch objectId {
        case "banana": return UIColor(red: 1.0, green: 0.82, blue: 0.12, alpha: 1)
        case "cake": return UIColor(red: 1.0, green: 0.46, blue: 0.70, alpha: 1)
        case "fruit": return UIColor(red: 1.0, green: 0.24, blue: 0.12, alpha: 1)
        case "lipstick": return UIColor(red: 1.0, green: 0.08, blue: 0.34, alpha: 1)
        case "compact": return UIColor(red: 1.0, green: 0.72, blue: 0.90, alpha: 1)
        case "ball": return UIColor(red: 0.12, green: 0.70, blue: 1.0, alpha: 1)
        case "trophy": return UIColor(red: 1.0, green: 0.74, blue: 0.16, alpha: 1)
        case "dumbbell": return UIColor(red: 0.38, green: 1.0, blue: 0.48, alpha: 1)
        case "camera": return UIColor(red: 0.52, green: 0.62, blue: 0.95, alpha: 1)
        case "spotlight": return UIColor(red: 1.0, green: 0.86, blue: 0.26, alpha: 1)
        case "dress": return UIColor(red: 0.72, green: 0.34, blue: 1.0, alpha: 1)
        case "shoe": return UIColor(red: 1.0, green: 0.52, blue: 0.18, alpha: 1)
        case "bag": return UIColor(red: 1.0, green: 0.28, blue: 0.72, alpha: 1)
        case "microphone": return UIColor(red: 0.18, green: 0.88, blue: 1.0, alpha: 1)
        case "note": return UIColor(red: 0.48, green: 1.0, blue: 1.0, alpha: 1)
        case "speaker": return UIColor(red: 0.40, green: 0.48, blue: 1.0, alpha: 1)
        case "laptop": return UIColor(red: 0.16, green: 0.55, blue: 1.0, alpha: 1)
        case "chip": return UIColor(red: 0.20, green: 1.0, blue: 0.75, alpha: 1)
        case "controller": return UIColor(red: 0.52, green: 0.40, blue: 1.0, alpha: 1)
        case "newspaper": return UIColor(red: 0.90, green: 0.92, blue: 0.96, alpha: 1)
        case "globe": return UIColor(red: 0.22, green: 0.62, blue: 1.0, alpha: 1)
        case "eiffel": return UIColor(red: 0.22, green: 0.36, blue: 1.0, alpha: 1)
        case "croissant": return UIColor(red: 1.0, green: 0.66, blue: 0.24, alpha: 1)
        case "beret": return UIColor(red: 0.10, green: 0.16, blue: 0.82, alpha: 1)
        case "guitar": return UIColor(red: 0.94, green: 0.45, blue: 0.15, alpha: 1)
        case "sun": return UIColor(red: 1.0, green: 0.82, blue: 0.18, alpha: 1)
        case "fan": return UIColor(red: 1.0, green: 0.22, blue: 0.30, alpha: 1)
        default: return channelFallbackColor()
        }
    }

    private func channelFallbackColor() -> UIColor {
        switch channelId.lowercased() {
        case "food": return UIColor(red: 1.0, green: 0.46, blue: 0.08, alpha: 1)
        case "beauty": return UIColor(red: 1.0, green: 0.18, blue: 0.55, alpha: 1)
        case "sports", "fitness": return UIColor(red: 0.12, green: 0.36, blue: 1.0, alpha: 1)
        case "modelling": return UIColor(red: 1.0, green: 0.78, blue: 0.12, alpha: 1)
        case "fashion": return UIColor(red: 0.62, green: 0.10, blue: 0.96, alpha: 1)
        case "music": return UIColor(red: 0.0, green: 0.82, blue: 0.96, alpha: 1)
        case "tech": return UIColor(red: 0.16, green: 0.52, blue: 1.0, alpha: 1)
        case "news": return UIColor(red: 0.88, green: 0.10, blue: 0.10, alpha: 1)
        case "french": return UIColor(red: 0.06, green: 0.22, blue: 0.84, alpha: 1)
        case "spanish": return UIColor(red: 0.88, green: 0.66, blue: 0.0, alpha: 1)
        default: return .white
        }
    }
}
