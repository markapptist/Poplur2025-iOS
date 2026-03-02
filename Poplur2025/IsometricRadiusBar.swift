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
    public var baseColor: Color
    public var tintColor: Color = .indigo
    private var pitchDegrees: Double
    private var yawDegrees: Double
    private var growthSpeed: Double
    private var maxSceneHeight: Double
    private var uiScale: CGFloat
    private var maxRuntimeRadius: Double

    public var useNormalMap: Bool = true
    public var lightingModel: SCNMaterial.LightingModel = .physicallyBased

    public init(radius: Binding<Double>, baseColor: Color = .indigo, tintColor: Color = .indigo, pitchDegrees: Double = 10.0, yawDegrees: Double = 20.0, growthSpeed: Double = 1.5, maxSceneHeight: Double = 2.4, uiScale: CGFloat = 1.5, maxRuntimeRadius: Double? = nil) {
        self._radius = radius
        self.baseColor = baseColor
        self.tintColor = tintColor
        self.pitchDegrees = pitchDegrees
        self.yawDegrees = yawDegrees
        self.growthSpeed = growthSpeed
        self.maxSceneHeight = maxSceneHeight
        self.uiScale = uiScale
        self.maxRuntimeRadius = maxRuntimeRadius ?? (Locale.current.usesMetricSystem ? 6_371_000.0 : 3_958.8 * 1609.34)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            RadiusBarSceneView(
                radius: $radius,
                baseColor: baseColor,
                tintColor: tintColor,
                pitchDegrees: pitchDegrees,
                yawDegrees: yawDegrees,
                maxSceneHeight: maxSceneHeight,
                useNormalMap: useNormalMap,
                lightingModel: lightingModel
            )
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
    var tintColor: Color
    var pitchDegrees: Double
    var yawDegrees: Double
    var maxSceneHeight: Double

    var useNormalMap: Bool
    var lightingModel: SCNMaterial.LightingModel

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
        context.coordinator.updateMaterials(baseColor: baseColor, tintColor: tintColor, useNormalMap: useNormalMap, lightingModel: lightingModel)
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
        barTarget.position = SCNVector3(0, 0.3, 0) // lower the target (visual center) so the bar appears lower in frame
        scene.rootNode.addChildNode(barTarget)

        // Bar (SCNBox) sized to show height with small width/length, start at a tiny height so it's visible
        let box = SCNBox(width: 0.42, height: CGFloat(maxSceneHeight), length: 0.42, chamferRadius: 0.06)
        box.chamferSegmentCount = 3
        box.materials = perFaceMaterials(from: baseColor)
        let node = SCNNode(geometry: box)
        node.name = "bar"
        // Set pivot to bottom-center so scaling grows upward
        if let box = node.geometry as? SCNBox {
            let minY: Float = -Float(box.height) / 2.0
            node.pivot = SCNMatrix4MakeTranslation(0, minY, 0)
            // Position so that when scale.y == 1, the bar base sits at y=0 relative to barTarget
            node.position = SCNVector3(0, Float(box.height) / 2.0, 0)
        }
        // Start collapsed in Y
        node.scale = SCNVector3(1, 0.0001, 1)
        // Fixed subtle 3D effect
        node.eulerAngles = SCNVector3(Float(6.0 * .pi / 180), Float(-10.0 * .pi / 180), 0)
        barTarget.addChildNode(node)

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

        // Add a small spinning Earth globe near the bar
        let globeRadius: CGFloat = 0.28
        let globe = SCNSphere(radius: globeRadius)
        let globeMat = SCNMaterial()
        if let earthImage = UIImage(named: "EarthDiffuse") {
            globeMat.diffuse.contents = earthImage
        } else {
            globeMat.diffuse.contents = UIColor.systemBlue
        }
        // Slight specular for a nicer look
        globeMat.metalness.contents = 0.05
        globeMat.roughness.contents = 0.35
        globe.materials = [globeMat]
        let globeNode = SCNNode(geometry: globe)
        // Position globe slightly to the right of the bar and lower so it sits visually near the base
        globeNode.position = SCNVector3(0.9, 0.45, 0)
        // Give a subtle tilt like Earth's axial tilt
        globeNode.eulerAngles.x = Float(-23.5 * .pi / 180)
        barTarget.addChildNode(globeNode)

        // Continuous spin animation around Y
        let spin = CABasicAnimation(keyPath: "rotation")
        spin.fromValue = NSValue(scnVector4: SCNVector4(0, 1, 0, 0))
        spin.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, Float(2 * Double.pi)))
        spin.duration = 12.0
        spin.repeatCount = .infinity
        globeNode.addAnimation(spin, forKey: "earthSpin")

        if let barNode = scene.rootNode.childNode(withName: "bar", recursively: true) {
            // Bouncy, elastic keyframe animation for scale.y
            let keyAnim = CAKeyframeAnimation(keyPath: "scale.y")
            keyAnim.values = [0.0001, 1.15, 0.92, 1.05, 0.99, 1.0]
            keyAnim.keyTimes = [0.0, 0.55, 0.7, 0.85, 0.95, 1.0] as [NSNumber]
            keyAnim.duration = 4.0
            keyAnim.autoreverses = true
            keyAnim.repeatCount = .infinity
            keyAnim.calculationMode = .cubic
            keyAnim.isRemovedOnCompletion = false
            // Slight ease-in at the start
            keyAnim.timingFunctions = [
                CAMediaTimingFunction(name: .easeIn),
                CAMediaTimingFunction(name: .default),
                CAMediaTimingFunction(name: .default),
                CAMediaTimingFunction(name: .default),
                CAMediaTimingFunction(name: .easeOut)
            ]
            barNode.addAnimation(keyAnim, forKey: "growYLoop")
        }

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
            m.lightingModel = lightingModel
            m.multiply.contents = uiColor(self.tintColor)
            if useNormalMap, let normal = UIImage(named: "CubeNormalMap") {
                m.normal.contents = normal
                m.normal.intensity = 0.6
            } else {
                m.normal.contents = nil
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
            // Keep geometry height constant; collapse via scale so SCNAnimation can drive growth
            bar.scale = SCNVector3(1, 0.0001, 1)
            // Position bar so base sits at y=0 relative to barTarget
            bar.position.y = Float(box.height) / 2.0
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

            // If bar has an active grow animation, skip manual height updates to keep SCNAnimation smooth
            if bar.animation(forKey: "growYLoop") != nil {
                return
            }

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
        
        func updateMaterials(baseColor: Color, tintColor: Color, useNormalMap: Bool, lightingModel: SCNMaterial.LightingModel) {
            guard let scnView = view,
                  let root = scnView.scene?.rootNode,
                  let bar = root.childNode(withName: "bar", recursively: true),
                  let box = bar.geometry as? SCNBox else { return }
            // Rebuild per-face materials with current colors
            let mats = parent.perFaceMaterials(from: baseColor)
            // Update multiply and lighting model, and normal map settings per new config
            for m in mats {
                m.lightingModel = lightingModel
                m.multiply.contents = UIColor(tintColor)
                if useNormalMap, let normal = UIImage(named: "CubeNormalMap") {
                    m.normal.contents = normal
                    m.normal.intensity = 0.6
                } else {
                    m.normal.contents = nil
                }
            }
            box.materials = mats
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
    @State private var yawDegrees: Double = 0
    @State private var uiScale: CGFloat = 1.5
    @State private var maxSceneHeight: Double = 1.8
    @State private var growth: Double = 1.5
    @State private var baseColor: Color = .indigo
    @State private var tintColor: Color = .indigo
    @State private var useSpring: Bool = true
    @State private var springResponse: Double = 0.35
    @State private var springDamping: Double = 0.85
    @State private var springBlend: Double = 0.0
    @State private var useGravityRamp: Bool = false
    @State private var gravityStrength: Double = 1.0
    private let earthMeters: Double = (Locale.current.usesMetricSystem ? 6_371_000.0 : 3_958.8 * 1609.34)

    @State private var scaleMode: ScaleMode = .scaleTo
    @State private var scaleByFactor: CGFloat = 1.0
    enum ScaleMode: String, CaseIterable, Identifiable { case scaleTo, scaleBy; var id: String { rawValue } }

    @State private var useNormalMapPreview: Bool = true
    @State private var lightingModelPreview: SCNMaterial.LightingModel = .physicallyBased
    @State private var isLooping: Bool = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Live bar preview with controls below
                ZStack {
                    Color(UIColor.systemBackground)
                    configuredBar
                        .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
                        .rotation3DEffect(.degrees(yawDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 6)

                // Scrollable controls on same page
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Radius Bar Controls").font(.headline)
                        HStack {
                            Text("Radius \(Int(radius))m").monospacedDigit()
                            Slider(value: $radius, in: 0...3_323_000)
                            Button("Reset") { animateTo(0) }
                                .buttonStyle(.borderedProminent)
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
                        HStack(spacing: 8) {
                            Text("Yaw")
                            Button("45°") { withAnimation(.easeInOut(duration: 0.25)) { yawDegrees += 45 } }
                            Button("90°") { withAnimation(.easeInOut(duration: 0.25)) { yawDegrees += 90 } }
                            Button("180°") { withAnimation(.easeInOut(duration: 0.25)) { yawDegrees += 180 } }
                            Button("360°") { withAnimation(.easeInOut(duration: 0.35)) { yawDegrees += 360 } }
                            Button("Reset") { withAnimation(.easeInOut(duration: 0.25)) { yawDegrees = 0 } }
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
                        ColorPicker("Tint Color", selection: $tintColor)

                        Picker("Scale Mode", selection: $scaleMode) {
                            Text("Scale To").tag(ScaleMode.scaleTo)
                            Text("Scale By").tag(ScaleMode.scaleBy)
                        }
                        .pickerStyle(.segmented)
                        if scaleMode == .scaleBy {
                            HStack {
                                Text("Scale By \(String(format: "%.2f", scaleByFactor))x")
                                Slider(value: $scaleByFactor, in: 0.5...2.0)
                            }
                        }

                        Toggle("Use Normal Map", isOn: $useNormalMapPreview)
                        Picker("Lighting", selection: $lightingModelPreview) {
                            Text("PBR").tag(SCNMaterial.LightingModel.physicallyBased)
                            Text("Blinn").tag(SCNMaterial.LightingModel.blinn)
                            Text("Lambert").tag(SCNMaterial.LightingModel.lambert)
                            Text("Constant").tag(SCNMaterial.LightingModel.constant)
                        }
                        .pickerStyle(.segmented)

                        Divider()
                        Text("Animation / Physics").font(.headline)
                        Toggle("Use Spring Animation", isOn: $useSpring)
                        if useSpring {
                            HStack {
                                Text("Response \(String(format: "%.2f", springResponse))")
                                Slider(value: $springResponse, in: 0.1...1.2)
                            }
                            HStack {
                                Text("Damping \(String(format: "%.2f", springDamping))")
                                Slider(value: $springDamping, in: 0.2...1.5)
                            }
                            HStack {
                                Text("Blend \(String(format: "%.2f", springBlend))")
                                Slider(value: $springBlend, in: 0.0...1.0)
                            }
                        }
                        Toggle("Gravity-like ramp (accelerate over time)", isOn: $useGravityRamp)
                        if useGravityRamp {
                            HStack {
                                Text("Gravity \(String(format: "%.2f", gravityStrength))x")
                                Slider(value: $gravityStrength, in: 0.2...3.0)
                            }
                        }

                        Divider()
                        Text("Quick Targets").font(.headline)
                        growthButtons
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .navigationTitle("Radius Bar Preview")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Full Bar") {
                        ZStack {
                            Color(UIColor.systemBackground).ignoresSafeArea()
                            configuredBar
                                .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
                                .rotation3DEffect(.degrees(yawDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
                        }
                        .navigationTitle("Full Bar")
                    }
                }
            }
            .onAppear { startLoopingAnimation() }
        }
    }

    private var configuredBar: AnyView {
        let base = IsometricRadiusBar(radius: $radius, baseColor: baseColor, tintColor: tintColor, growthSpeed: growth, maxSceneHeight: maxSceneHeight, uiScale: uiScale, maxRuntimeRadius: 3_323_000.0)
        var cfg = base
        cfg.useNormalMap = useNormalMapPreview
        cfg.lightingModel = lightingModelPreview
        if scaleMode == .scaleTo {
            return AnyView(cfg.frame(width: barWidth, height: barHeight))
        } else {
            return AnyView(cfg.scaleEffect(scaleByFactor))
        }
    }

    private var growthButtons: some View {
        let percents: [Double] = [0.10, 0.20, 0.30, 0.40, 0.50, 0.75, 1.0]
        return WrapHStack(spacing: 8) {
            ForEach(percents, id: \.self) { p in
                Button(String(format: "%.0f%%", p * 100)) {
                    let target = earthMeters * p
                    if useGravityRamp {
                        runGravityRamp(to: target) {
                            animateTo(0)
                        }
                    } else {
                        animateTo(target)
                        // After the animation completes approximately, drop back to 0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            animateTo(0)
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func animateTo(_ target: Double) {
        if useSpring {
            withAnimation(.interpolatingSpring(mass: 1.0, stiffness: springStiffness(), damping: springDampingCoef(), initialVelocity: 0)) {
                radius = min(max(0, target), 3_323_000.0)
            }
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                radius = min(max(0, target), 3_323_000.0)
            }
        }
    }

    private func springStiffness() -> Double {
        // Map `response` and `damping` similar to SwiftUI's spring(response:dampingFraction:blendDuration:)
        // Rough heuristic: stiffness ~ 1/(response^2)
        max(10, 1.0 / max(0.05, springResponse * springResponse))
    }

    private func springDampingCoef() -> Double {
        // Map damping fraction to a coefficient; keep in a stable range
        max(1.0, 10.0 * springDamping)
    }

    private func runGravityRamp(to target: Double, completion: (() -> Void)? = nil) {
        let clampedTarget = min(max(0, target), 3_323_000.0)
        let start = radius
        let delta = clampedTarget - start
        guard abs(delta) > 1 else { completion?(); return }
        let duration = max(0.3, 0.9 / gravityStrength)
        let steps = Int(max(15, duration * 60))
        let dt = duration / Double(steps)
        var t: Double = 0
        let accel = 2.0 / (duration * duration)
        Task { @MainActor in
            for i in 0...steps {
                if i == steps {
                    radius = clampedTarget
                    completion?()
                    break
                }
                t += dt
                let normalized = min(1.0, 0.5 * accel * t * t)
                radius = start + normalized * delta
                try? await Task.sleep(nanoseconds: UInt64(dt * 1_000_000_000))
            }
        }
    }

    private func startLoopingAnimation() {
        guard isLooping else { return }
        let maxTarget = 3_323_000.0
        Task { @MainActor in
            while isLooping {
                // Animate up to max
                if useGravityRamp {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        runGravityRamp(to: maxTarget) {
                            cont.resume()
                        }
                    }
                } else {
                    animateTo(maxTarget)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
                // Brief pause at top
                try? await Task.sleep(nanoseconds: 250_000_000)
                // Reset to zero quickly
                withAnimation(.easeOut(duration: 0.25)) {
                    radius = 0
                }
                // Brief pause at bottom
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }
}

private struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: spacing) { content() }
    }
}
