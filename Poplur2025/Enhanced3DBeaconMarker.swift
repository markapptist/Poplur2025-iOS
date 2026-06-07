import SwiftUI
import SceneKit

struct Enhanced3DBeaconMarker: UIViewRepresentable {
    let color: Color
    let intensity: Double

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = false
        scnView.backgroundColor = .clear
        scnView.autoenablesDefaultLighting = false
        
        let scene = SCNScene()
        scnView.scene = scene
        
        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 10)
        scene.rootNode.addChildNode(cameraNode)
        
        // Beacon base (a cylinder)
        let beaconGeometry = SCNCylinder(radius: 0.5, height: 1.0)
        let beaconMaterial = SCNMaterial()
        beaconMaterial.diffuse.contents = UIColor(color)
        beaconGeometry.materials = [beaconMaterial]
        
        let beaconNode = SCNNode(geometry: beaconGeometry)
        scene.rootNode.addChildNode(beaconNode)
        
        // Light for glowing effect (omni light)
        let lightNode = SCNNode()
        let omniLight = SCNLight()
        omniLight.type = .omni
        omniLight.color = UIColor(color).withAlphaComponent(CGFloat(min(max(intensity, 0), 1)))
        lightNode.light = omniLight
        lightNode.position = SCNVector3(0, 0, 5)
        scene.rootNode.addChildNode(lightNode)
        
        // Animation - pulsate intensity
        let pulseUp = CABasicAnimation(keyPath: "intensity")
        pulseUp.fromValue = intensity * 0.5
        pulseUp.toValue = intensity
        pulseUp.duration = 1.0
        pulseUp.autoreverses = true
        pulseUp.repeatCount = .infinity
        omniLight.addAnimation(pulseUp, forKey: "pulseIntensity")
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let scene = uiView.scene, let lightNode = scene.rootNode.childNodes.first(where: { $0.light != nil }), let light = lightNode.light else {
            return
        }
        let uiColor = UIColor(color)
        light.color = uiColor.withAlphaComponent(CGFloat(min(max(intensity, 0), 1)))
        
        if let beaconNode = scene.rootNode.childNodes.first(where: { $0.geometry is SCNCylinder }),
           let material = beaconNode.geometry?.materials.first {
            material.diffuse.contents = uiColor
        }
    }
}
