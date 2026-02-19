import SwiftUI
import SceneKit

public struct IsometricRadiusBar: View {
    @Binding public var radius: Double
    @State private var dragStartRadius: Double? = nil
    private var baseColor: Color

    public init(radius: Binding<Double>, baseColor: Color = .accentColor) {
        self._radius = radius
        self.baseColor = baseColor
    }

    public var body: some View {
        ZStack(alignment: .top) {
            RadiusBarSceneView(radius: $radius, baseColor: baseColor)
                .frame(width: 216, height: 720)
                .background(Color.clear)
                .allowsHitTesting(false)
                .offset(y: 120)

            // Small radius label
            Text("\(max(1, Int(radius) / 1000)) KM")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .padding(.top, 6)
        }
        .overlay(
            GeometryReader { proxy in
                Rectangle()
                    .foregroundColor(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(in: proxy.size))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Radius")
                    .accessibilityValue(Text(String(format: "%.0f", radius)))
                    .accessibilityAdjustableAction { direction in
                        let step: Double = 50
                        switch direction {
                        case .increment:
                            radius = min(radius + step, 10_000)
                        case .decrement:
                            radius = max(radius - step, 0)
                        @unknown default:
                            break
                        }
                    }
            }
        )
    }
}

private extension IsometricRadiusBar {
    func dragGesture(in size: CGSize) -> some Gesture {
        let height = max(1, size.height)
        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartRadius == nil {
                    dragStartRadius = radius
                }
                let start = dragStartRadius ?? radius
                let dy = Double(-(value.translation.height))
                let span: Double = 10_000 - 0
                let factor: Double = 0.5
                let delta = dy / Double(height) * span * factor
                let newValue = max(0, min(10_000, start + delta))
                radius = newValue
            }
            .onEnded { _ in
                dragStartRadius = nil
            }
    }
}

// MARK: - UIViewRepresentable SCNView (matches CubeTabView approach)

private struct RadiusBarSceneView: UIViewRepresentable {
    @Binding var radius: Double
    var baseColor: Color

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling4X
        scnView.isPlaying = true
        scnView.scene = makeScene()
        context.coordinator.view = scnView

        // Delay the initial height growth by ~2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            context.coordinator.markInitialAnimationRun()
            context.coordinator.updateHeight(from: radius, isInitial: true)
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.updateHeight(from: radius)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        // Camera (simple, like CubeTabView)
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.zFar = 100
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 5.0)
        scene.rootNode.addChildNode(cameraNode)

        // Lights (omni + ambient + subtle rim)
        let omni = SCNLight()
        omni.type = .omni
        omni.intensity = 900
        let omniNode = SCNNode()
        omniNode.light = omni
        omniNode.position = SCNVector3(4, 6, 8)
        scene.rootNode.addChildNode(omniNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 260
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 600
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(Float(20.0 * .pi / 180), Float(-160.0 * .pi / 180), 0)
        scene.rootNode.addChildNode(rimNode)

        // Radial shadow disk (floating cue)
        let shadowRadius: CGFloat = 0.8
        let shadow = SCNCylinder(radius: shadowRadius, height: 0.01)
        let shadowMat = SCNMaterial()
        shadowMat.lightingModel = .physicallyBased
        let size = CGSize(width: 256, height: 256)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let ctx = UIGraphicsGetCurrentContext()!
        let colors = [UIColor.black.withAlphaComponent(0.38).cgColor, UIColor.black.withAlphaComponent(0.0).cgColor] as CFArray
        let locations: [CGFloat] = [0.0, 1.0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations)!
        ctx.drawRadialGradient(gradient,
                               startCenter: CGPoint(x: size.width/2, y: size.height/2), startRadius: 0,
                               endCenter: CGPoint(x: size.width/2, y: size.height/2), endRadius: min(size.width, size.height)/2,
                               options: .drawsAfterEndLocation)
        let gradientImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        shadowMat.diffuse.contents = gradientImage
        shadow.materials = [shadowMat]
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.eulerAngles.x = -.pi / 2
        shadowNode.position = SCNVector3(0, -1.2, 0)
        scene.rootNode.addChildNode(shadowNode)

        // Bar (SCNBox) sized to show height with small width/length, start at height 0
        let box = SCNBox(width: 0.35, height: 0.0, length: 0.35, chamferRadius: 0.06)
        box.chamferSegmentCount = 3
        box.materials = perFaceMaterials(from: baseColor)
        let node = SCNNode(geometry: box)
        node.name = "bar"
        node.position = SCNVector3(0, 0.0, 0) // half initial height 0
        scene.rootNode.addChildNode(node)

        // Fixed 3D pose: show two faces + top (X ~ -10°, Y ~ 20°)
        node.eulerAngles = SCNVector3(-Float(10.0 * .pi / 180), Float(20.0 * .pi / 180), 0)

        // Gentle bob
        let up = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: 1.4)
        up.timingMode = .easeInEaseOut
        let down = up.reversed()
        let bob = SCNAction.repeatForever(SCNAction.sequence([up, down]))
        node.runAction(bob)

        return scene
    }

    private func perFaceMaterials(from color: Color) -> [SCNMaterial] {
        func uiColor(_ c: Color) -> UIColor {
            #if os(iOS)
            return UIColor(c)
            #else
            return UIColor.systemTeal
            #endif
        }
        func mat(_ color: UIColor, metal: CGFloat = 0.18, rough: CGFloat = 0.35) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.lightingModel = .physicallyBased
            m.multiply.contents = UIColor.systemIndigo
            if let normal = UIImage(named: "CubeNormalMap") {
                m.normal.contents = normal
                m.normal.intensity = 0.6
            }
            m.metalness.contents = metal
            m.roughness.contents = rough
            m.isDoubleSided = true
            return m
        }
        // Derive a few tints from the base color for subtle face variation
        let base = uiColor(color)
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        let front = UIColor(hue: hue, saturation: max(0, sat * 0.95), brightness: min(1, bri * 0.95), alpha: alpha)
        let right = UIColor(hue: hue, saturation: min(1, sat * 1.05), brightness: min(1, bri * 1.00), alpha: alpha)
        let back = UIColor(hue: hue, saturation: min(1, sat * 1.10), brightness: max(0, bri * 0.90), alpha: alpha)
        let left = UIColor(hue: hue, saturation: max(0, sat * 0.85), brightness: min(1, bri * 1.05), alpha: alpha)
        let top = UIColor(hue: hue, saturation: max(0, sat * 0.20), brightness: min(1, bri * 1.10), alpha: alpha)
        let bottom = UIColor(hue: hue, saturation: min(1, sat * 1.00), brightness: max(0, bri * 0.60), alpha: alpha)
        return [
            mat(front),
            mat(right),
            mat(back),
            mat(left),
            mat(top, metal: 0.08, rough: 0.25),
            mat(bottom, metal: 0.10, rough: 0.60)
        ]
    }

    class Coordinator {
        var parent: RadiusBarSceneView
        weak var view: SCNView?
        private(set) var didRunInitialAnimation = false

        init(_ parent: RadiusBarSceneView) { self.parent = parent }

        func markInitialAnimationRun() {
            didRunInitialAnimation = true
        }

        func updateHeight(from radius: Double) {
            updateHeight(from: radius, isInitial: false)
        }

        func updateHeight(from radius: Double, isInitial: Bool) {
            guard let scnView = view,
                  let bar = scnView.scene?.rootNode.childNode(withName: "bar", recursively: true),
                  let box = bar.geometry as? SCNBox else { return }
            let targetH = clampedHeight(radius)
            SCNTransaction.begin()
            let initialHeight = box.height
            // Slower animations overall; first animation is slower and delayed externally
            if isInitial {
                SCNTransaction.animationDuration = 1.2
            } else {
                SCNTransaction.animationDuration = didRunInitialAnimation ? 0.6 : 0.6
            }
            box.height = CGFloat(targetH)
            bar.position.y = Float(targetH / 2.0)
            SCNTransaction.commit()
        }

        private func clampedHeight(_ radius: Double) -> Double {
            let r = max(0, radius)
            let minR: Double = 50
            let maxR: Double = 10_000
            let minH: Double = 1.2
            let maxH: Double = 2.6
            let t = min(1.0, max(0.0, (r - minR) / (maxR - minR)))
            return minH + (maxH - minH) * t
        }
    }
}

// MARK: - Preview

private struct StatefulPreview: View {
    @State private var radius: Double = 2500
    var body: some View {
        IsometricRadiusBar(radius: $radius, baseColor: .accentColor)
            .padding()
            .background(Color(.systemBackground))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
    }
}

#Preview("IsometricRadiusBar") {
    StatefulPreview()
}

