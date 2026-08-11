import SwiftUI
import SceneKit

/// 3D SceneKit-based zoom slider matching the cube tab view aesthetic
struct MapZoomSlider3D: View {
    @Binding var zoomLevel: Double
    @Binding var isDragging: Bool
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onChange: (Double) -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            // Zoom in button (top)
            Button(action: onZoomIn) {
                SceneKitButton(icon: "plus")
            }
            .buttonStyle(.plain)
            
            // 3D Slider track
            SceneKitSliderTrack(
                zoomLevel: $zoomLevel,
                isDragging: $isDragging,
                onChange: onChange
            )
            .frame(width: 32, height: 100)
            
            // Zoom out button (bottom)
            Button(action: onZoomOut) {
                SceneKitButton(icon: "minus")
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - SceneKit Button

private struct SceneKitButton: View {
    let icon: String
    
    var body: some View {
        ZStack {
            // 3D button using SceneKit
            SceneKitButtonView(icon: icon)
                .frame(width: 32, height: 24)
        }
    }
}

private struct SceneKitButtonView: UIViewRepresentable {
    let icon: String
    
    func makeUIView(context: Context) -> SCNView {
        let view = PoplurManagedSCNView(performanceName: "MapZoomSlider3D")
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        
        let scene = SCNScene()
        view.scene = scene
        
        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(cameraNode)
        
        // Light
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.intensity = 1000
        lightNode.position = SCNVector3(0, 2, 2)
        scene.rootNode.addChildNode(lightNode)
        
        // 3D Button - rounded box
        let box = SCNBox(width: 1.4, height: 0.8, length: 0.3, chamferRadius: 0.1)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.lightingModel = .physicallyBased
        material.metalness.contents = 0.1
        material.roughness.contents = 0.3
        box.materials = [material]
        
        let boxNode = SCNNode(geometry: box)
        scene.rootNode.addChildNode(boxNode)
        
        // Icon text
        let textGeometry = SCNText(string: icon == "plus" ? "+" : "−", extrusionDepth: 0.05)
        textGeometry.font = UIFont.systemFont(ofSize: 0.6, weight: .bold)
        textGeometry.flatness = 0.01
        
        let textMaterial = SCNMaterial()
        textMaterial.diffuse.contents = UIColor.black
        textGeometry.materials = [textMaterial]
        
        let textNode = SCNNode(geometry: textGeometry)
        let (min, max) = textNode.boundingBox
        let textWidth = max.x - min.x
        let textHeight = max.y - min.y
        textNode.position = SCNVector3(-textWidth / 2, -textHeight / 2, 0.2)
        boxNode.addChildNode(textNode)
        
        // Subtle rotation for depth
        boxNode.eulerAngles = SCNVector3(-Float.pi / 12, Float.pi / 24, 0)
        
        return view
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.backgroundColor = .clear
    }
}

// MARK: - SceneKit Slider Track

private struct SceneKitSliderTrack: UIViewRepresentable {
    @Binding var zoomLevel: Double
    @Binding var isDragging: Bool
    let onChange: (Double) -> Void
    
    func makeUIView(context: Context) -> SliderContainerView {
        let container = SliderContainerView()
        
        let scnView = PoplurManagedSCNView(performanceName: "MapZoomButton3D")
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        
        let scene = SCNScene()
        scnView.scene = scene
        
        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)
        
        // Light
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.intensity = 1200
        lightNode.position = SCNVector3(0, 2, 2)
        scene.rootNode.addChildNode(lightNode)
        
        // Track - dark metallic rail
        let track = SCNCylinder(radius: 0.12, height: 4.0)
        let trackMaterial = SCNMaterial()
        trackMaterial.diffuse.contents = UIColor(white: 0.2, alpha: 1.0)
        trackMaterial.lightingModel = .physicallyBased
        trackMaterial.metalness.contents = 0.8
        trackMaterial.roughness.contents = 0.4
        track.materials = [trackMaterial]
        
        let trackNode = SCNNode(geometry: track)
        trackNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        scene.rootNode.addChildNode(trackNode)
        
        // Knob - 3D cubic knob with depth
        let knobSize: CGFloat = 0.5
        let knob = SCNBox(width: knobSize, height: knobSize, length: 0.35, chamferRadius: 0.08)
        
        // Multi-material for cube faces
        let materials = (0..<6).map { _ in
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor.white
            mat.lightingModel = .physicallyBased
            mat.metalness.contents = 0.3
            mat.roughness.contents = 0.2
            return mat
        }
        knob.materials = materials
        
        let knobNode = SCNNode(geometry: knob)
        knobNode.name = "knob"
        scene.rootNode.addChildNode(knobNode)
        
        // Add accent lines on knob for grip
        let lineHeight: CGFloat = 0.05
        let lineDepth: CGFloat = 0.02
        let lineSpacing: CGFloat = 0.15
        for i in -1...1 {
            let line = SCNBox(width: knobSize * 0.6, height: lineHeight, length: lineDepth, chamferRadius: 0.01)
            let lineMat = SCNMaterial()
            lineMat.diffuse.contents = UIColor(white: 0.3, alpha: 1.0)
            line.materials = [lineMat]
            
            let lineNode = SCNNode(geometry: line)
            lineNode.position = SCNVector3(0, CGFloat(i) * lineSpacing, 0.2)
            knobNode.addChildNode(lineNode)
        }
        
        // Subtle rotation for 3D effect
        knobNode.eulerAngles = SCNVector3(-Float.pi / 16, Float.pi / 20, 0)
        
        container.sceneView = scnView
        container.addSubview(scnView)
        scnView.frame = container.bounds
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // Update knob position based on initial zoom
        updateKnobPosition(in: scnView.scene!, zoomLevel: zoomLevel)
        
        return container
    }
    
    func updateUIView(_ container: SliderContainerView, context: Context) {
        guard let scnView = container.sceneView,
              let scene = scnView.scene else { return }
        
        scnView.backgroundColor = .clear
        
        // Update knob position if not dragging
        if !isDragging {
            updateKnobPosition(in: scene, zoomLevel: zoomLevel)
        }
        
        // Setup gesture if not already set
        if container.gestureRecognizers?.isEmpty ?? true {
            let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
            container.addGestureRecognizer(panGesture)
        }
        
        context.coordinator.parent = self
        context.coordinator.container = container
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func updateKnobPosition(in scene: SCNScene, zoomLevel: Double) {
        guard let knobNode = scene.rootNode.childNode(withName: "knob", recursively: false) else { return }
        
        let normalized = normalizedZoom(zoomLevel)
        let trackLength: Float = 4.0
        let yPosition = -trackLength / 2 + Float(normalized) * trackLength
        
        knobNode.position = SCNVector3(0, yPosition, 0)
    }
    
    private func normalizedZoom(_ zoomLevel: Double) -> Double {
        let minLog = log10(10.0)
        let maxLog = log10(40_000_000.0)
        let currentLog = log10(zoomLevel.clamped(to: 10...40_000_000))
        return (currentLog - minLog) / (maxLog - minLog)
    }
    
    class Coordinator: NSObject {
        var parent: SceneKitSliderTrack
        weak var container: SliderContainerView?
        
        init(_ parent: SceneKitSliderTrack) {
            self.parent = parent
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let container = container,
                  let scnView = container.sceneView,
                  let scene = scnView.scene,
                  let knobNode = scene.rootNode.childNode(withName: "knob", recursively: false) else { return }
            
            let trackLength: Float = 4.0
            let containerHeight = container.bounds.height
            
            switch gesture.state {
            case .began:
                parent.isDragging = true
                
            case .changed:
                let translation = gesture.translation(in: container)
                // Invert Y because UIKit coordinates are inverted
                let normalizedDrag = Double(-translation.y / containerHeight).clamped(to: 0...1)
                
                // Update knob position
                let yPosition = -trackLength / 2 + Float(normalizedDrag) * trackLength
                knobNode.position = SCNVector3(0, yPosition, 0)
                
                // Convert to zoom level
                let minLog = log10(10.0)
                let maxLog = log10(40_000_000.0)
                let logValue = minLog + normalizedDrag * (maxLog - minLog)
                let newZoom = pow(10.0, logValue)
                
                parent.zoomLevel = newZoom
                parent.onChange(newZoom)
                
            case .ended, .cancelled:
                parent.isDragging = false
                
            default:
                break
            }
        }
    }
}

// MARK: - Container View

private class SliderContainerView: UIView {
    weak var sceneView: SCNView?
}

// MARK: - Helper Extension

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
