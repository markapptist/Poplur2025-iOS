import SwiftUI
import SceneKit

struct UserLocation3DMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        let scene = SCNScene()

        // Create a simple sphere to represent the user location
        let sphere = SCNSphere(radius: 0.1)
        sphere.firstMaterial?.diffuse.contents = UIColor.systemBlue

        let sphereNode = SCNNode(geometry: sphere)
        scene.rootNode.addChildNode(sphereNode)

        sceneView.scene = scene
        sceneView.allowsCameraControl = true
        sceneView.backgroundColor = UIColor.clear

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

struct SceneKit3DEnhancedMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        let scene = SCNScene()

        // Add a box with a glowing effect
        let box = SCNBox(width: 0.2, height: 0.2, length: 0.2, chamferRadius: 0.05)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemGreen
        material.emission.contents = UIColor.green
        box.firstMaterial = material

        let boxNode = SCNNode(geometry: box)
        scene.rootNode.addChildNode(boxNode)

        sceneView.scene = scene
        sceneView.allowsCameraControl = true
        sceneView.backgroundColor = UIColor.clear

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

struct Floating3DBeacon: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        let scene = SCNScene()

        // Create a floating beacon with a cylinder and a light
        let cylinder = SCNCylinder(radius: 0.05, height: 0.3)
        cylinder.firstMaterial?.diffuse.contents = UIColor.systemRed

        let cylinderNode = SCNNode(geometry: cylinder)
        scene.rootNode.addChildNode(cylinderNode)

        // Add a light source above the cylinder
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor.red
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position = SCNVector3(0, 0.3, 0)
        scene.rootNode.addChildNode(lightNode)

        // Animate the beacon to float up and down
        let floatUp = SCNAction.moveBy(x: 0, y: 0.1, z: 0, duration: 1)
        let floatDown = SCNAction.moveBy(x: 0, y: -0.1, z: 0, duration: 1)
        let floatSequence = SCNAction.sequence([floatUp, floatDown])
        let floatLoop = SCNAction.repeatForever(floatSequence)
        cylinderNode.runAction(floatLoop)

        sceneView.scene = scene
        sceneView.allowsCameraControl = true
        sceneView.backgroundColor = UIColor.clear

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
