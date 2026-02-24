import SwiftUI
import SceneKit

extension Notification.Name {
    static let currentPostRadiusDidChange = Notification.Name("CurrentPostRadiusDidChange")
    static let showCapturedPreviewRequested = Notification.Name("ShowCapturedPreviewRequested")
}

extension Notification.Name {
    static let capturePreviewDidDismiss = Notification.Name("CapturePreviewDidDismiss")
}

public struct IsometricRadiusBar: View {
    @Binding public var radius: Double
    @State private var dragStartRadius: Double? = nil
    @State private var usesImperial: Bool = Locale.current.usesMetricSystem == false
    @State private var holdTimer: CADisplayLink? = nil
    private var earthRadiusMeters: Double { usesImperial ? 3958.8 * 1609.34 : 6371.0 * 1000.0 }
    private var earthRadiusCapMeters: Double { earthRadiusMeters }
    private var baseColor: Color
    private var pitchDegrees: Double
    private var yawDegrees: Double
    private var growthSpeed: Double
    private var maxSceneHeight: Double
    private var uiScale: CGFloat
    private var maxRuntimeRadius: Double

    public init(radius: Binding<Double>, baseColor: Color = .indigo, pitchDegrees: Double = 10.0, yawDegrees: Double = 20.0, growthSpeed: Double = 1.5, maxSceneHeight: Double = 2.4, uiScale: CGFloat = 1.5, maxRuntimeRadius: Double? = nil) {
        self._radius = radius
        self.baseColor = baseColor
        self.pitchDegrees = pitchDegrees
        self.yawDegrees = yawDegrees
        self.growthSpeed = growthSpeed
        self.maxSceneHeight = maxSceneHeight
        self.uiScale = uiScale
        self.maxRuntimeRadius = maxRuntimeRadius ?? (Locale.current.usesMetricSystem ? 6_371_000.0 : 3_958.8 * 1609.34)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            RadiusBarSceneView(radius: $radius, baseColor: baseColor, pitchDegrees: pitchDegrees, yawDegrees: yawDegrees, maxSceneHeight: maxSceneHeight)
                .frame(width: 220, height: 960)
                .background(Color.clear)
                .allowsHitTesting(false)
        }
        .scaleEffect(uiScale, anchor: .bottomTrailing)
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
        .onReceive(NotificationCenter.default.publisher(for: .currentPostRadiusDidChange)) { note in
            if let r = note.userInfo?["radius"] as? Double {
                self.radius = min(max(0, r), self.maxRuntimeRadius)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldBegan)) { _ in
            startAutoIncrease()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldEnded)) { _ in
            stopAutoIncrease()
            // Notify that we should show the captured preview output
            NotificationCenter.default.post(name: .showCapturedPreviewRequested, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .capturePreviewDidDismiss)) { _ in
            // Reset radius to zero so the bar returns to minimal height
            self.radius = 0
        }
    }
}

private extension IsometricRadiusBar {
    func dragGesture(in size: CGSize) -> some Gesture {
        let height = max(1, size.height)
        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Ignore manual drag while recording hold is active
                if holdTimer != nil { return }
                if dragStartRadius == nil {
                    dragStartRadius = radius
                }
                let start = dragStartRadius ?? radius
                let dy = Double(-(value.translation.height))
                let span: Double = earthRadiusCapMeters
                let factor: Double = 0.5
                let delta = dy / Double(height) * span * factor
                let newValue = max(0, min(min(earthRadiusCapMeters, self.maxRuntimeRadius), start + delta))
                radius = newValue
            }
            .onEnded { _ in
                if holdTimer != nil { return }
                dragStartRadius = nil
            }
    }

    func startAutoIncrease() {
        stopAutoIncrease()
        let link = CADisplayLink(target: DisplayLinkProxy { dt in
            // Increase radius toward earth radius while held
            let incrementPerSecond: Double = (earthRadiusMeters / 10.0) * max(0.1, self.growthSpeed) // base 10s to full; scale by growthSpeed
            self.radius = min(self.radius + incrementPerSecond * dt, min(earthRadiusCapMeters, self.maxRuntimeRadius))
        }, selector: #selector(DisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        holdTimer = link
    }

    func stopAutoIncrease() {
        holdTimer?.invalidate()
        holdTimer = nil
    }
}

// MARK: - UIViewRepresentable SCNView (matches CubeTabView approach)

private struct RadiusBarSceneView: UIViewRepresentable {
    @Binding var radius: Double
    var baseColor: Color
    var pitchDegrees: Double
    var yawDegrees: Double
    var maxSceneHeight: Double

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

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.updateHeight(from: radius)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        // Camera (orthographic for straight vertical bar)
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 4.8 // zoom in (smaller scale = closer look in ortho)
        camera.zNear = 0.01
        camera.zFar = 100
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 3.0, 3.4)
        cameraNode.eulerAngles = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        // Target node for the camera to look at (visual center)
        let barTarget = SCNNode()
        barTarget.name = "barTarget"
        barTarget.position = SCNVector3(0, 1.2, 0) // raise the target (visual center) so the bar appears higher in frame
        scene.rootNode.addChildNode(barTarget)

        // Bar (SCNBox) sized to show height with small width/length, start at a tiny height so it's visible
        let box = SCNBox(width: 0.42, height: 0.05, length: 0.42, chamferRadius: 0.06)
        box.chamferSegmentCount = 3
        box.materials = perFaceMaterials(from: baseColor)
        let node = SCNNode(geometry: box)
        node.name = "bar"
        node.position = SCNVector3(0, 1.0, 0) // lowered slightly to avoid cutoff
        node.pivot = SCNMatrix4Identity // rotate around center to keep it visually centered
        barTarget.addChildNode(node)

        // Remove lookAt constraint and bobbing
        // node.eulerAngles will be used for fixed pitch/yaw for subtle 3D effect
        node.eulerAngles = SCNVector3(Float(6.0 * .pi / 180), Float(-10.0 * .pi / 180), 0)

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

        // Removed radial shadow disk and cachedShadowImage as per instructions

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

    private func makeTickLabel(text: String) -> SCNNode {
        let textGeom = SCNText(string: text, extrusionDepth: 0.1)
        textGeom.font = UIFont.systemFont(ofSize: 1.6, weight: .semibold)
        let m = SCNMaterial()
        m.diffuse.contents = UIColor.white.withAlphaComponent(0.8)
        textGeom.materials = [m]
        let node = SCNNode(geometry: textGeom)
        let (minB, maxB) = textGeom.boundingBox
        let cx = (minB.x + maxB.x) / 2.0
        let cy = (minB.y + maxB.y) / 2.0
        node.pivot = SCNMatrix4MakeTranslation(cx, cy, 0)
        node.scale = SCNVector3(0.02, 0.02, 0.02)
        node.constraints = [SCNBillboardConstraint()]
        return node
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
            // Start at zero height so animation grows upward
            let minH: CGFloat = 0.0
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
            // Hard cap to ensure we never exceed the visible scene height
            let hardMaxH: Double = parent.maxSceneHeight
            let appliedH = min(targetH, hardMaxH)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            box.height = CGFloat(appliedH)
            bar.position.y = Float(appliedH / 2.0)
            CATransaction.commit()
        }

        private func clampedHeight(_ radius: Double) -> Double {
            let r = max(0, radius)
            // Earth radius in meters based on locale (imperial uses miles)
            let usesImperial = Locale.current.usesMetricSystem == false
            let earthMeters: Double = usesImperial ? 3958.8 * 1609.34 : 6371.0 * 1000.0
            let minH: Double = 0.0
            let maxH: Double = parent.maxSceneHeight
            let t = min(1.0, max(0.0, r / earthMeters))
            let result = minH + (maxH - minH) * t
            return min(result, maxH)
        }
    }
}

// MARK: - DisplayLinkProxy

private class DisplayLinkProxy {
    private var lastTimestamp: CFTimeInterval?
    private let handler: (Double) -> Void
    init(_ handler: @escaping (Double) -> Void) { self.handler = handler }
    @objc func tick(_ link: CADisplayLink) {
        let ts = link.timestamp
        let dt: Double
        if let last = lastTimestamp { dt = ts - last } else { dt = link.duration }
        lastTimestamp = ts
        handler(max(0, dt))
    }
}

// MARK: - Preview

#Preview("Radius Bar Properties") {
    RadiusBarOnlyPreview()
}

private struct RadiusBarOnlyPreview: View {
    @State private var radius: Double = 2500
    @State private var barWidth: CGFloat = 98
    @State private var barHeight: CGFloat = 390
    @State private var tilt: Double = -8
    @State private var uiScale: CGFloat = 1.5
    @State private var maxSceneHeight: Double = 1.8
    @State private var growth: Double = 1.5
    @State private var baseColor: Color = .indigo

    var body: some View {
        VStack(spacing: 12) {
            // Controls
            VStack(alignment: .leading, spacing: 10) {
                Text("Radius Bar Controls").font(.headline)
                HStack {
                    Text("Radius \(Int(radius))m").monospacedDigit()
                    Slider(value: $radius, in: 0...3_323_000)
                }
                HStack {
                    Text("Width \(Int(barWidth))")
                    Slider(value: $barWidth, in: 64...160)
                }
                HStack {
                    Text("Height \(Int(barHeight))")
                    Slider(value: $barHeight, in: 260...520)
                }
                HStack {
                    Text("Tilt \(Int(tilt))°")
                    Slider(value: $tilt, in: -25...0, step: 1)
                }
                HStack {
                    Text("UI Scale \(String(format: "%.2f", uiScale))")
                    Slider(value: $uiScale, in: 0.8...2.0)
                }
                HStack {
                    Text("Max Scene H \(String(format: "%.1f", maxSceneHeight))")
                    Slider(value: $maxSceneHeight, in: 0.8...3.0)
                }
                HStack {
                    Text("Growth \(String(format: "%.2f", growth))")
                    Slider(value: $growth, in: 0.5...3.0)
                }
                ColorPicker("Base Color", selection: $baseColor)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Bar under test
            ZStack {
                Color(UIColor.systemBackground)
                IsometricRadiusBar(radius: $radius, baseColor: baseColor, growthSpeed: growth, maxSceneHeight: maxSceneHeight, uiScale: uiScale, maxRuntimeRadius: 3_323_000.0)
                    .frame(width: barWidth, height: barHeight)
                    .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 6)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
    }
}
