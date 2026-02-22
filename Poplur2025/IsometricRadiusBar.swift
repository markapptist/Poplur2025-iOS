import SwiftUI
import SceneKit

public struct IsometricRadiusBar: View {
    @Binding public var radius: Double
    @State private var dragStartRadius: Double? = nil
    private var baseColor: Color
    private var pitchDegrees: Double
    private var yawDegrees: Double

    public init(radius: Binding<Double>, baseColor: Color = .indigo, pitchDegrees: Double = 10.0, yawDegrees: Double = 20.0) {
        self._radius = radius
        self.baseColor = baseColor
        self.pitchDegrees = pitchDegrees
        self.yawDegrees = yawDegrees
    }

    public var body: some View {
        ZStack(alignment: .top) {
            RadiusBarSceneView(radius: $radius, baseColor: baseColor, pitchDegrees: pitchDegrees, yawDegrees: yawDegrees)
                .frame(width: 160, height: 520)
                .background(Color.clear)
                .allowsHitTesting(false)
                .offset(y: 80)
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
    var pitchDegrees: Double
    var yawDegrees: Double

    private static let cachedShadowImage: UIImage = {
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
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }()

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .none
        scnView.isPlaying = true
        scnView.preferredFramesPerSecond = 30
        scnView.scene = makeScene()
        context.coordinator.view = scnView

        context.coordinator.prepareInitialState()

        // Delay the initial height growth by ~0.6 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
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
        camera.zNear = 0.01
        camera.zFar = 100
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 3.6, 3.5)
        // Orientation will be driven by look-at constraint
        cameraNode.eulerAngles = SCNVector3Zero
        scene.rootNode.addChildNode(cameraNode)

        // Target node for the camera to look at (visual center)
        let barTarget = SCNNode()
        barTarget.name = "barTarget"
        barTarget.position = SCNVector3(0, 1.5, 0) // raise the target (visual center) so the bar appears higher in frame
        scene.rootNode.addChildNode(barTarget)

        // Bar (SCNBox) sized to show height with small width/length, start at a tiny height so it's visible
        let box = SCNBox(width: 0.35, height: 0.05, length: 0.35, chamferRadius: 0.06)
        box.chamferSegmentCount = 3
        box.materials = perFaceMaterials(from: baseColor)
        let node = SCNNode(geometry: box)
        node.name = "bar"
        node.position = SCNVector3(0, 2.0, 0) // raised higher to appear more centered with current camera angle
        node.pivot = SCNMatrix4Identity // rotate around center to keep it visually centered
        barTarget.addChildNode(node)

        // Attach camera look-at constraint to the target so the bar can be offset within the frame
        let lookAt = SCNLookAtConstraint(target: barTarget)
        lookAt.isGimbalLockEnabled = true
        cameraNode.constraints = [lookAt]

        // Fixed 3D pose: show two faces + top with manual pitch/yaw (restored)
        node.eulerAngles = SCNVector3(Float(pitchDegrees * .pi / 10), -Float(yawDegrees * .pi / -65), 0)

        // Gentle bob
        let up = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: 1.4)
        up.timingMode = .easeInEaseOut
        let down = up.reversed()
        let bob = SCNAction.repeatForever(SCNAction.sequence([up, down]))
        node.runAction(bob)

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
        shadowMat.diffuse.contents = RadiusBarSceneView.cachedShadowImage
        shadow.materials = [shadowMat]
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.eulerAngles.x = -.pi / 2
        shadowNode.position = SCNVector3(0, -0.35, 0)
        scene.rootNode.addChildNode(shadowNode)

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

    private func makeBarLabelNode(text: String) -> SCNNode {
        // Use SCNText for crisp vector text with a small plane background to mimic a capsule
        let textGeom = SCNText(string: text, extrusionDepth: 0.2)
        textGeom.font = UIFont.systemFont(ofSize: 3.0, weight: .heavy)
        textGeom.flatness = 0.2
        let textMat = SCNMaterial()
        textMat.diffuse.contents = UIColor.white
        textMat.lightingModel = .physicallyBased
        textGeom.materials = [textMat]

        // Center the text by using its bounding box
        let textNode = SCNNode(geometry: textGeom)
        let (minB, maxB) = textGeom.boundingBox
        let centerX = (minB.x + maxB.x) / 2.0
        let centerY = (minB.y + maxB.y) / 2.0
        textNode.pivot = SCNMatrix4MakeTranslation(centerX, centerY, 0)
        textNode.scale = SCNVector3(0.02, 0.02, 0.02) // scale down to scene units

        // Background plane behind the text to simulate a capsule tag
        let padding: CGFloat = 0.6
        let width = CGFloat(maxB.x - minB.x) * 0.02 + padding
        let height = CGFloat(maxB.y - minB.y) * 0.02 + padding * 0.6
        let bgPlane = SCNPlane(width: width, height: height)
        let bgMat = SCNMaterial()
        bgMat.diffuse.contents = UIColor.black.withAlphaComponent(0.55)
        bgMat.isDoubleSided = true
        bgPlane.cornerRadius = height / 2.0
        bgPlane.materials = [bgMat]
        let bgNode = SCNNode(geometry: bgPlane)

        let container = SCNNode()
        container.addChildNode(bgNode)
        container.addChildNode(textNode)
        // Slightly offset text towards viewer to avoid z-fighting
        textNode.position = SCNVector3(0, 0, 0.01)

        // Move bg and text up so that container's origin is at the bottom edge of the label
        let planeHeightScene = Float(height)
        bgNode.position = SCNVector3(0, planeHeightScene / 2.0, 0)
        textNode.position.y += planeHeightScene / 2.0

        // Pivot at bottom-center so y=0 is the bottom of the label
        container.pivot = SCNMatrix4MakeTranslation(0, 0, 0)

        // Make the label always face the camera
        container.constraints = [SCNBillboardConstraint()]
        return container
    }

    class Coordinator {
        var parent: RadiusBarSceneView
        weak var view: SCNView?
        private(set) var didRunInitialAnimation = false

        init(_ parent: RadiusBarSceneView) { self.parent = parent }

        func prepareInitialState() {
            guard let scnView = view,
                  let root = scnView.scene?.rootNode,
                  let bar = root.childNode(withName: "bar", recursively: true),
                  let box = bar.geometry as? SCNBox else { return }
            // Set to minimal height and position at bottom so animation grows upward
            let minH: CGFloat = 1.2
            box.height = minH
            bar.position.y = Float(minH / 2.0)
        }

        func markInitialAnimationRun() {
            didRunInitialAnimation = true
        }

        func updateHeight(from radius: Double) {
            updateHeight(from: radius, isInitial: false)
        }

        func updateHeight(from radius: Double, isInitial: Bool) {
            guard let scnView = view,
                  let root = scnView.scene?.rootNode,
                  let bar = root.childNode(withName: "bar", recursively: true),
                  let box = bar.geometry as? SCNBox else { return }

            let targetH = clampedHeight(radius)

            SCNTransaction.begin()
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if isInitial {
                SCNTransaction.animationDuration = 1.2
            } else {
                SCNTransaction.animationDuration = didRunInitialAnimation ? 0.6 : 0.6
            }

            // Update geometry height and bar position
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
        IsometricRadiusBar(radius: $radius, baseColor: .accentColor, pitchDegrees: 10, yawDegrees: 20)
            .padding()
            .background(Color(.systemBackground))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
    }
}

#Preview("IsometricRadiusBar") {
    StatefulPreview()
}

