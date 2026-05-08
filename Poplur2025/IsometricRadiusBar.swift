import SwiftUI
import SceneKit
import ObjectiveC

extension Notification.Name {
    static let currentPostRadiusDidChange = Notification.Name("CurrentPostRadiusDidChange")
    static let showCapturedPreviewRequested = Notification.Name("ShowCapturedPreviewRequested")
}

extension Notification.Name {
    static let capturePreviewDidDismiss = Notification.Name("CapturePreviewDidDismiss")
}

extension Notification.Name {
    static let radiusBarGlobeTap = Notification.Name("RadiusBarGlobeTap")
}

extension Notification.Name {
    static let radiusBarHoldBegan = Notification.Name("RadiusBarHoldBegan")
    static let radiusBarHoldEnded = Notification.Name("RadiusBarHoldEnded")
}

extension Notification.Name {
    static let animateRadiusBarToValue = Notification.Name("AnimateRadiusBarToValue")
}

public struct IsometricRadiusBar: View {
    @Binding public var radius: Double
    @State private var dragStartRadius: Double? = nil
    @State private var usesImperial: Bool = Locale.current.usesMetricSystem == false
    @State private var holdTimer: CADisplayLink? = nil
    @State private var holdStartTime: CFTimeInterval? = nil
    @State private var holdStartRadius: Double = 0
    @State private var drainTimer: CADisplayLink? = nil
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

    public var autoLoop: Bool = false
    @State private var isAutoLooping: Bool = false
    @State private var autoLoopTask: Task<Void, Never>? = nil
    
    // Smooth animation state for external radius changes
    @State private var animationTask: Task<Void, Never>? = nil

    private var earthRadiusMeters: Double { usesImperial ? 3958.8 * 1609.34 : 6371.0 * 1000.0 }
    private var earthRadiusCapMeters: Double { earthRadiusMeters }

    public init(radius: Binding<Double>, baseColor: Color = .cyan, tintColor: Color = .teal, pitchDegrees: Double = 10.0, yawDegrees: Double = 20.0, growthSpeed: Double = 1.5, maxSceneHeight: Double = 2.4, uiScale: CGFloat = 1.5, maxRuntimeRadius: Double? = nil) {
        self._radius = radius
        self.baseColor = baseColor
        self.tintColor = tintColor
        self.pitchDegrees = pitchDegrees
        self.yawDegrees = yawDegrees
        self.growthSpeed = growthSpeed
        self.maxSceneHeight = maxSceneHeight
        self.uiScale = uiScale
        self.maxRuntimeRadius = maxRuntimeRadius ?? (Locale.current.usesMetricSystem ? 6_371_000.0 : 3_958.8 * 1609.34)
        // autoLoop defaults to false by declaration, no assignment needed here
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
                maxRuntimeRadius: maxRuntimeRadius,
                useNormalMap: useNormalMap,
                lightingModel: lightingModel,
                autoLoop: autoLoop
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
        // Removed currentPostRadiusDidChange and ForceRadiusBarUpdate handlers - HomeView manages these via binding
        .onReceive(NotificationCenter.default.publisher(for: .radiusBarHoldBegan)) { _ in
            stopDrain()
            startHoldIncrease()
        }
        .onReceive(NotificationCenter.default.publisher(for: .radiusBarHoldEnded)) { _ in
            stopHoldIncrease()
        }
        .onReceive(NotificationCenter.default.publisher(for: .animateRadiusBarToValue)) { note in
            if let targetRadius = note.userInfo?["radius"] as? Double {
                print("🔵 [RadiusBar] Received animateRadiusBarToValue: \(targetRadius)m")
                let duration = (note.userInfo?["duration"] as? Double) ?? 0.8
                animateToRadius(targetRadius, duration: duration)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .MapSuggestedRadius)) { note in
            if let targetRadius = note.userInfo?["radius"] as? Double {
                print("🔵 [RadiusBar] Received MapSuggestedRadius: \(targetRadius)m")
                let duration = (note.userInfo?["duration"] as? Double) ?? 2.0
                animateToRadius(targetRadius, duration: duration)
            }
        }
        // Removed cameraCubeHoldBegan and cameraCubeHoldEnded notifications and related actions
        // Removed capturePreviewDidDismiss notification that resets radius to zero
        .onAppear {
            print("🟢 [RadiusBar] BAR IS NOW VISIBLE - onAppear called, autoLoop: \(autoLoop)")
            print("🟢 [RadiusBar] Current radius: \(radius)m")
            
            if autoLoop { startAutoLooping() }
        }
        .onDisappear {
            print("🔴 [RadiusBar] BAR IS NOW HIDDEN - onDisappear called")
            stopAutoLooping()
        }
    }
}

private extension IsometricRadiusBar {
    func dragGesture(in size: CGSize) -> some Gesture {
        let height = max(1, size.height)
        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Ignore manual drag while recording hold or drain is active
                if holdTimer != nil || drainTimer != nil { return }
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
                if holdTimer != nil || drainTimer != nil { return }
                dragStartRadius = nil
            }
    }

    func startHoldIncrease() {
        // Stop any existing timers (hold or drain)
        stopHoldIncrease()
        stopDrain()
        // Record the start state for a faster pressurized ramp
        holdStartTime = CACurrentMediaTime()
        holdStartRadius = radius
        let proxy = DisplayLinkProxy { _ in
            guard let start = holdStartTime else { return }
            let elapsed = CACurrentMediaTime() - start
            // Replaced original quintic ease-in with fast-start S-curve and shorter duration
            let duration: CFTimeInterval = 5.0 // quicker response
            let t = max(0.0, min(1.0, elapsed / duration))
            // Fast-start S-curve: ease out then ease in (emphasize early movement)
            let pressure = 0.5 - 0.5 * cos(Double.pi * t)
            let target = min(self.maxRuntimeRadius, self.earthRadiusCapMeters)
            let next = holdStartRadius + (target - holdStartRadius) * pressure
            self.radius = min(max(0, next), self.maxRuntimeRadius)
            if t >= 1.0 {
                self.stopHoldIncrease()
            }
        }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        objc_setAssociatedObject(link, UnsafeRawPointer(bitPattern: 0xDEADBEEF)!, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        link.add(to: .main, forMode: .common)
        holdTimer = link
    }

    func stopHoldIncrease() {
        holdStartTime = nil
        holdTimer?.invalidate()
        holdTimer = nil
        startDrain()
    }

    func startDrain() {
        stopDrain()
        let startRadius = radius
        let startTime = CACurrentMediaTime()
        let duration: CFTimeInterval = 1.2 // quick fall
        let proxy = DisplayLinkProxy { _ in
            let elapsed = CACurrentMediaTime() - startTime
            let t = max(0.0, min(1.0, elapsed / duration))
            // Ease-out (fast at start, slow at end)
            let easeOut = 1.0 - pow(1.0 - t, 3.0)
            let next = max(0, startRadius * (1.0 - easeOut))
            self.radius = next
            if t >= 1.0 || next <= 0.5 {
                self.stopDrain()
                self.radius = 0
            }
        }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        objc_setAssociatedObject(link, UnsafeRawPointer(bitPattern: 0xFEEDBEEF)!, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        link.add(to: .main, forMode: .common)
        drainTimer = link
    }

    func stopDrain() {
        drainTimer?.invalidate()
        drainTimer = nil
    }

    // Removed startAutoIncrease() and stopAutoIncrease() functions as instructed

    func startAutoLooping() {
        stopAutoLooping()
        isAutoLooping = true
        autoLoopTask = Task { @MainActor in
            var goingUp = true
            let earthMeters: Double = (Locale.current.usesMetricSystem ? 6_371_000.0 : 3_958.8 * 1609.34)
            var targetHigh = earthMeters * Double.random(in: 0.3...0.8)
            let fps: Double = 60.0
            let dt: Double = 1.0 / fps
            while !Task.isCancelled && isAutoLooping {
                let current = radius
                let target = goingUp ? min(targetHigh, maxRuntimeRadius) : 0.0
                let diff = target - current
                let ratePerSecond = max(0.25, min(0.6, abs(diff) / (earthMeters * 2.0)))
                let step = diff * ratePerSecond * dt
                let next = current + step
                withAnimation(.interpolatingSpring(mass: 1.0, stiffness: springStiffnessAuto(), damping: springDampingCoefAuto(), initialVelocity: 0)) {
                    radius = min(max(0, next), maxRuntimeRadius)
                }
                if goingUp {
                    if abs(diff) < max(250.0, targetHigh * 0.01) {
                        goingUp = false
                    }
                } else {
                    if radius <= 1.0 {
                        goingUp = true
                        targetHigh = earthMeters * Double.random(in: 0.3...0.8)
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(dt * 1_000_000_000))
            }
        }
    }

    func stopAutoLooping() {
        isAutoLooping = false
        autoLoopTask?.cancel()
        autoLoopTask = nil
    }

    func springStiffnessAuto() -> Double { max(10, 1.0 / max(0.05, 0.35 * 0.35)) }
    func springDampingCoefAuto() -> Double { max(1.0, 10.0 * 0.85) }
    
    /// Smoothly animates the radius to a target value using frame-by-frame interpolation
    func animateToRadius(_ target: Double, duration: Double = 0.8) {
        print("🎬 [RadiusBar] animateToRadius called: \(target)m over \(duration)s (current: \(radius)m)")
        
        // Stop any active hold/drain timers that would interfere
        stopHoldIncrease()
        stopDrain()
        stopAutoLooping()
        
        // Cancel any existing animation
        animationTask?.cancel()
        
        let clampedTarget = min(max(0, target), maxRuntimeRadius)
        let startValue = radius
        
        print("🎬 [RadiusBar] Animation: \(startValue)m → \(clampedTarget)m")
        
        // If already at target, don't animate
        if abs(startValue - clampedTarget) < 1.0 {
            print("⚠️ [RadiusBar] Already at target, skipping animation")
            return
        }
        
        // Manual frame-by-frame animation for smooth SceneKit updates
        let fps: Double = 60.0
        let frameDuration: Double = 1.0 / fps
        let startTime = CACurrentMediaTime()
        
        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - startTime
                let t = min(1.0, elapsed / duration)
                
                // Ease in-out interpolation (cubic)
                let eased = easeInOutCubic(t)
                let interpolated = startValue + (clampedTarget - startValue) * eased
                
                radius = interpolated
                
                if t >= 1.0 {
                    radius = clampedTarget
                    print("✅ [RadiusBar] Animation completed at \(clampedTarget)m")
                    break
                }
                
                try? await Task.sleep(nanoseconds: UInt64(frameDuration * 1_000_000_000))
            }
        }
        print("✅ [RadiusBar] Frame-by-frame animation started")
    }
    
    /// Cubic ease-in-out interpolation for smooth animations
    private func easeInOutCubic(_ t: Double) -> Double {
        if t < 0.5 {
            return 4 * t * t * t
        } else {
            let f = (2 * t) - 2
            return 0.5 * f * f * f + 1
        }
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
    var maxRuntimeRadius: Double

    var useNormalMap: Bool
    var lightingModel: SCNMaterial.LightingModel
    var autoLoop: Bool

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling4X
        scnView.isPlaying = true
        scnView.preferredFramesPerSecond = 60
        scnView.scene = makeScene()
        context.coordinator.view = scnView

        context.coordinator.prepareInitialState()
        context.coordinator.setAutoLoopingEnabled(autoLoop)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Force update on every radius change to ensure animations happen
        print("🔄 [RadiusBarSceneView] updateUIView called with radius=\(radius)m")
        context.coordinator.updateHeight(from: radius)
        context.coordinator.updateMaterials(baseColor: baseColor, tintColor: tintColor, useNormalMap: useNormalMap, lightingModel: lightingModel)
        context.coordinator.setAutoLoopingEnabled(autoLoop)
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
        let box = SCNBox(width: 0.60, height: CGFloat(maxSceneHeight), length: 0.60, chamferRadius: 0.06)
        box.chamferSegmentCount = 3
        // Updated: pass radius = 0 for initial setup
        box.materials = perFaceMaterials(from: baseColor, radius: 0)
        let node = SCNNode(geometry: box)
        node.name = "bar"
        // Set pivot to bottom-center so scaling grows upward
        if let box = node.geometry as? SCNBox {
            let minY: Float = -Float(box.height) / 2.0
            node.pivot = SCNMatrix4MakeTranslation(0, minY, 0)
            // Position so that when scale.y == 1, the bar base sits at y=0 relative to barTarget
            node.position = SCNVector3(0, Float(box.height) / 2.0, 0)
        }
        // Start with no collapsed scale
        node.scale = SCNVector3(1, 1, 1)
        // Fixed subtle 3D effect
        node.eulerAngles = SCNVector3(Float(6.0 * .pi / 180), Float(-10.0 * .pi / 180), 0)
        barTarget.addChildNode(node)

        // Lights (omni + ambient + subtle rim)
        let omni = SCNLight()
        omni.type = .omni
        omni.intensity = 1200
        let omniNode = SCNNode()
        omniNode.light = omni
        omniNode.position = SCNVector3(4, 6, 8)
        scene.rootNode.addChildNode(omniNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 500
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 700
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(Float(20.0 * .pi / 180), Float(-160.0 * .pi / 180), 0)
        scene.rootNode.addChildNode(rimNode)

        let fill = SCNLight()
        fill.type = .omni
        fill.intensity = 600
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(-4, 5, -6)
        scene.rootNode.addChildNode(fillNode)

        // Removed radial shadow disk and cachedShadowImage as per instructions

        // Helper function to create multiple thin horizontal stripes texture
        func makeMultiStripeTexture(size: CGSize = CGSize(width: 512, height: 256), baseColor: UIColor = UIColor.systemIndigo, stripeColor: UIColor = .white, stripeCount: Int = 8, stripeThickness: CGFloat = 0.06, stripeSpacing: CGFloat = 0.08) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                // Fill base color
                baseColor.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                // Draw multiple thin horizontal stripes centered around the equator
                let totalHeight = size.height
                let bandHeight = totalHeight * stripeThickness
                let gapHeight = totalHeight * stripeSpacing
                let totalStripeBlock = CGFloat(stripeCount) * bandHeight + CGFloat(stripeCount - 1) * gapHeight
                var y = (totalHeight - totalStripeBlock) / 2.0
                for _ in 0..<stripeCount {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: bandHeight)
                    stripeColor.setFill()
                    ctx.fill(rect)
                    y += bandHeight + gapHeight
                }
            }
        }

        // Add a small spinning Earth globe near the bar
        let globeRadius: CGFloat = 0.10
        let globe = SCNSphere(radius: globeRadius)
        let globeMat = SCNMaterial()
        // Apply a multi-stripe texture and glossy finish
        // Replaced multi-stripe texture with earth_day texture from asset catalog
        let earthTexture = UIImage(named: "earth_day")
        globeMat.diffuse.contents = earthTexture
        globeMat.normal.contents = UIImage(named: "8k_Earth_normal_map")
        globeMat.normal.intensity = 0.8
        globeMat.metalness.contents = 0.0
        globeMat.roughness.contents = 0.15
        globeMat.specular.contents = UIColor.white
        globeMat.shininess = 0.6
        globe.materials = [globeMat]
        let globeNode = SCNNode(geometry: globe)
        globeNode.name = "globe"
        globeNode.scale = SCNVector3(1, 1, 1)  // <--- Added line to keep globe scale constant
        // Position globe centered above the bar top face with a slight gap
        globeNode.position = SCNVector3(0.0, Float((box.height / 2.0) + CGFloat(globeRadius) + 0.20), 0.0)
        // Give a subtle tilt like Earth's axial tilt
        globeNode.eulerAngles.x = Float(-23.5 * .pi / 180)
        barTarget.addChildNode(globeNode)

        // Add constant spin animation to globe node with random direction and faster speed
        let spin = CABasicAnimation(keyPath: "rotation")
        // Random unit axis
        let ax = Float.random(in: -1...1)
        let ay = Float.random(in: -1...1)
        let az = Float.random(in: -1...1)
        let len = max(0.0001, sqrt(ax*ax + ay*ay + az*az))
        let ux = ax/len, uy = ay/len, uz = az/len
        spin.fromValue = NSValue(scnVector4: SCNVector4(ux, uy, uz, 0))
        spin.toValue = NSValue(scnVector4: SCNVector4(ux, uy, uz, Float(2 * Double.pi)))
        spin.duration = 1.2 // faster spin
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        globeNode.addAnimation(spin, forKey: "globeRandomSpin")

        // Removed growYLoop keyframe animation block per instructions

        return scene
    }

    // Updated signature to accept radius
    private func perFaceMaterials(from color: Color, radius: Double) -> [SCNMaterial] {
        func uiColor(_ c: Color) -> UIColor {
            #if os(iOS)
            return UIColor(c)
            #else
            return UIColor.systemTeal
            #endif
        }
        func mat(_ color: UIColor, metal: CGFloat = 0.05, rough: CGFloat = 0.25) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.lightingModel = lightingModel
            m.multiply.contents = uiColor(self.tintColor).withAlphaComponent(0.4)
            if useNormalMap, let normal = UIImage(named: "CubeNormalMap") {
                m.normal.contents = normal
                m.normal.intensity = 0.6
            } else {
                m.normal.contents = nil
            }
            m.metalness.contents = metal
            m.roughness.contents = rough
            m.isDoubleSided = true
            m.specular.contents = UIColor.white.withAlphaComponent(0.2)
            m.shininess = 0.3
            return m
        }

        // Vertical gradient image helper (unused now, kept for reference)
        func verticalGradientImage(bottom: UIColor, top: UIColor, size: CGSize = CGSize(width: 8, height: 256)) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                let colors = [bottom.cgColor, top.cgColor] as CFArray
                let space = CGColorSpaceCreateDeviceRGB()
                if let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0.0, 1.0]) {
                    ctx.cgContext.drawLinearGradient(grad, start: CGPoint(x: size.width/2, y: size.height), end: CGPoint(x: size.width/2, y: 0), options: [])
                }
            }
        }
        // New helper to create vertical gradient with 3 stops: bottom, middle, top
        func verticalGradientImage3(bottom: UIColor, middle: UIColor, top: UIColor, size: CGSize = CGSize(width: 8, height: 256)) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                let colors = [bottom.cgColor, middle.cgColor, top.cgColor] as CFArray
                let locations: [CGFloat] = [0.0, 0.5, 1.0]
                let space = CGColorSpaceCreateDeviceRGB()
                if let grad = CGGradient(colorsSpace: space, colors: colors, locations: locations) {
                    ctx.cgContext.drawLinearGradient(grad, start: CGPoint(x: size.width/2, y: size.height), end: CGPoint(x: size.width/2, y: 0), options: [])
                }
            }
        }

        // Replace gradient-based diffuse with solid base color on all faces:

        let base = uiColor(color)
        let mFront = mat(base)
        let mRight = mat(base)
        let mBack = mat(base)
        let mLeft = mat(base)
        let mTop = mat(base)
        let mBottom = mat(base)
        return [mFront, mRight, mBack, mLeft, mTop, mBottom]
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
        
        private var followLink: CADisplayLink?
        private let globeRadius: CGFloat = 0.10

        private var loopLink: CADisplayLink?
        private var loopPhase: Phase = .idle
        private var loopTime: CFTimeInterval = 0
        private var loopDuration: CFTimeInterval = 2.5
        private var loopTargetHeight: Double = 0
        private enum Phase { case idle, rising, falling }
        
        private var tapObserver: NSObjectProtocol?

        init(_ parent: RadiusBarSceneView) { self.parent = parent }
        
        deinit {
            stopFollowingGlobe()
            stopLoopingBar()
            if let token = tapObserver {
                NotificationCenter.default.removeObserver(token)
                tapObserver = nil
            }
        }

        func prepareInitialState() {
            guard let scnView = view,
                  let root = scnView.scene?.rootNode,
                  let bar = root.childNode(withName: "bar", recursively: true),
                  let box = bar.geometry as? SCNBox else { return }
            // Keep geometry height constant; collapse via scale so SCNAnimation can drive growth
            bar.scale = SCNVector3(1, 1, 1)
            // Position bar so base sits at y=0 relative to barTarget
            // Apply 75% cap to initial bar height
            let capped = min(Double(box.height), parent.maxSceneHeight * 0.75)
            box.height = CGFloat(capped)
            bar.position.y = Float(capped / 2.0)
            
            startFollowingGlobe()
            // Removed startLoopingBar() call here as per instructions
            
            tapObserver = NotificationCenter.default.addObserver(forName: .radiusBarGlobeTap, object: nil, queue: .main) { [weak self] _ in
                self?.globePop()
            }
        }

        func markInitialAnimationRun() {
            didRunInitialAnimation = true
        }

        func updateHeight(from radius: Double) {
            updateHeight(from: radius, isInitial: false)
        }

        func updateHeight(from radius: Double, isInitial: Bool) {
            print("🔧 [Coordinator] updateHeight START - radius=\(radius)m isInitial=\(isInitial)")
            
            guard let scnView = view,
                  let root = scnView.scene?.rootNode,
                  let bar = root.childNode(withName: "bar", recursively: true),
                  let box = bar.geometry as? SCNBox else {
                print("⚠️ [Coordinator] updateHeight FAILED - missing scene components")
                return
            }
            
            print("🔧 [Coordinator] Current box.height = \(box.height)")
            
            if loopLink != nil {
                print("⚠️ [Coordinator] updateHeight SKIPPED - loopLink is active")
                return
            }

            // Removed early return for active growYLoop animation so manual height updates always apply

            let targetH = clampedHeight(radius)
            // Hard cap to ensure we never exceed 75% of the visible scene height
            let hardMaxH: Double = parent.maxSceneHeight * 0.75
            let appliedH = min(targetH, hardMaxH)
            
            print("🎯 [Coordinator] Height calculation: radius=\(radius)m → targetH=\(targetH) → appliedH=\(appliedH)")
            print("🎯 [Coordinator] Applying animation: \(box.height) → \(appliedH)")

            // Allow implicit animations to work - don't disable actions
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.8)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            box.height = CGFloat(appliedH)
            bar.position.y = Float(appliedH / 2.0)
            CATransaction.commit()
            
            print("✅ [Coordinator] Bar height command sent: \(appliedH) (animation should be running)")
        }

        private func clampedHeight(_ radius: Double) -> Double {
            let r = max(0, radius)
            // Use a logarithmic scale for better visual representation across the huge range
            // Most posts are 0-100km, but we support up to 3,323km
            let minH: Double = 0.05  // Minimum visible height (5cm) so bar is never invisible
            let maxH: Double = parent.maxSceneHeight
            
            if r <= 1.0 {
                // Below 1m, stay at minimum height
                return minH
            }
            
            // Logarithmic scaling for better visual distribution
            // Reference points: 100m = ~10%, 1km = ~25%, 10km = ~50%, 100km = ~75%, 1000km = 100%
            let logMin = log10(100.0)  // 100m is our baseline
            let logMax = log10(1_000_000.0)  // 1000km is full height
            let logR = log10(r)
            let t = min(1.0, max(0.0, (logR - logMin) / (logMax - logMin)))
            
            let result = minH + (maxH - minH) * t
            print("📏 [clampedHeight] radius=\(r)m → log(\(logR)) → t=\(t) → height=\(result)")
            return min(result, maxH)
        }
        
        func updateMaterials(baseColor: Color, tintColor: Color, useNormalMap: Bool, lightingModel: SCNMaterial.LightingModel) {
            guard let scnView = view,
                  let root = scnView.scene?.rootNode,
                  let bar = root.childNode(withName: "bar", recursively: true),
                  let box = bar.geometry as? SCNBox else { return }
            // Rebuild per-face materials with current colors and current radius
            let mats = parent.perFaceMaterials(from: baseColor, radius: parent.radius)
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

        private func startFollowingGlobe() {
            stopFollowingGlobe()
            let link = CADisplayLink(target: self, selector: #selector(followTick(_:)))
            link.add(to: .main, forMode: .common)
            followLink = link
        }

        private func stopFollowingGlobe() {
            followLink?.invalidate()
            followLink = nil
        }
        
        private func startLoopingBar() {
            stopLoopingBar()
            pickNewTarget()
            loopPhase = .rising
            loopTime = 0
            let link = CADisplayLink(target: self, selector: #selector(loopTick(_:)))
            link.add(to: .main, forMode: .common)
            loopLink = link
        }

        private func stopLoopingBar() {
            loopLink?.invalidate()
            loopLink = nil
            loopPhase = .idle
        }
        
        private func pickNewTarget() {
            // Choose a random target between 30% and 80% of maxSceneHeight
            let minFrac: Double = 0.30
            let maxFrac: Double = 0.80
            let frac = Double.random(in: minFrac...maxFrac)
            loopTargetHeight = parent.maxSceneHeight * frac
            loopDuration = 2.2 + CFTimeInterval.random(in: 0.0...0.8)
        }

        private func easeInOut(_ t: Double) -> Double {
            // Smoothstep-like ease-in-out
            let tt = max(0.0, min(1.0, t))
            return tt * tt * (3 - 2 * tt)
        }

        @objc private func followTick(_ link: CADisplayLink) {
            guard let scnView = view,
                  let root = scnView.scene?.rootNode,
                  let bar = root.childNode(withName: "bar", recursively: true),
                  let box = bar.geometry as? SCNBox,
                  let barTarget = root.childNode(withName: "barTarget", recursively: true),
                  let globe = barTarget.childNode(withName: "globe", recursively: false) else { return }
            let baseGap: CGFloat = 0.08 // closer hover gap
            // Subtle bobbing using time
            let t = CGFloat(link.timestamp)
            let bob = sin(t * 2.0) * 0.01 // ~1 cm bobbing
            // Compute the bar's top center in its local space, then convert to barTarget's space
            let halfH = box.height / 2.0
            let topLocal = SCNVector3(0, Float(halfH), 0)
            let topInBarTarget = bar.convertPosition(topLocal, to: barTarget)
            let yAboveTop = topInBarTarget.y + Float(globeRadius + baseGap + bob)
            globe.position = SCNVector3(0, yAboveTop, 0)
        }

        @objc private func loopTick(_ link: CADisplayLink) {
            guard let scnView = view,
                  let root = scnView.scene?.rootNode,
                  let bar = root.childNode(withName: "bar", recursively: true),
                  let box = bar.geometry as? SCNBox else { return }
            let dt = link.duration
            switch loopPhase {
            case .idle:
                return
            case .rising:
                loopTime += dt
                let t = min(1.0, loopTime / loopDuration)
                let eased = easeInOut(t)
                let h = loopTargetHeight * eased
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                box.height = CGFloat(h)
                bar.position.y = Float(h / 2.0)
                CATransaction.commit()
                if t >= 1.0 {
                    loopPhase = .falling
                    loopTime = 0
                }
            case .falling:
                loopTime += dt
                let t = min(1.0, loopTime / (loopDuration * 0.8))
                let eased = easeInOut(t)
                let h = loopTargetHeight * (1.0 - eased)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                box.height = CGFloat(h)
                bar.position.y = Float(h / 2.0)
                CATransaction.commit()
                if t >= 1.0 {
                    pickNewTarget()
                    loopPhase = .rising
                    loopTime = 0
                }
            }
        }
        
        func globePop() {
            guard let scnView = view,
                  let root = scnView.scene?.rootNode,
                  let barTarget = root.childNode(withName: "barTarget", recursively: true),
                  let globe = barTarget.childNode(withName: "globe", recursively: false) else { return }
            
            let scaleUp = SCNAction.scale(to: 1.15, duration: 0.18)
            scaleUp.timingMode = .easeInEaseOut
            let scaleDown = SCNAction.scale(to: 1.0, duration: 0.22)
            scaleDown.timingMode = .easeInEaseOut
            let sequence = SCNAction.sequence([scaleUp, scaleDown])
            globe.runAction(sequence, forKey: "globePop")
        }

        func setAutoLoopingEnabled(_ enabled: Bool) {
            if enabled {
                if loopLink == nil { startLoopingBar() }
            } else {
                if loopLink != nil { stopLoopingBar() }
            }
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

// MARK: - Public API for triggering radius animations

/// Helper to animate the radius bar from anywhere in your app
public struct RadiusBarAnimator {
    /// Animate the bar to a specific radius value
    /// - Parameters:
    ///   - radius: Target radius in meters
    ///   - duration: Animation duration in seconds (default: 0.8)
    public static func animate(to radius: Double, duration: Double = 0.8) {
        print("🟡 [RadiusBarAnimator] POSTING animateRadiusBarToValue notification with radius: \(radius)m")
        NotificationCenter.default.post(
            name: .animateRadiusBarToValue,
            object: nil,
            userInfo: ["radius": radius, "duration": duration]
        )
    }
    
    /// Update the bar to show a post's radius (uses currentPostRadiusDidChange notification)
    /// - Parameter radius: The post's radius in meters
    public static func showPostRadius(_ radius: Double, duration: Double = 0.8) {
        print("🟡 [RadiusBarAnimator] POSTING currentPostRadiusDidChange notification with radius: \(radius)m")
        NotificationCenter.default.post(
            name: .currentPostRadiusDidChange,
            object: nil,
            userInfo: ["radius": radius, "duration": duration]
        )
    }
    
    /// Instantly set the bar radius without animation (for initialization)
    /// - Parameter radius: Target radius in meters
    public static func setInstant(_ radius: Double) {
        print("🟡 [RadiusBarAnimator] POSTING ForceRadiusBarUpdate notification with radius: \(radius)m (instant)")
        NotificationCenter.default.post(
            name: Notification.Name("ForceRadiusBarUpdate"),
            object: nil,
            userInfo: ["radius": radius, "duration": 0.0]
        )
    }
}

// MARK: - Preview

private struct RadiusBarOnlyPreview: View {
    private enum LightingChoice: String, CaseIterable, Identifiable {
        case physicallyBased, blinn, lambert, constant
        var id: String { rawValue }
        var model: SCNMaterial.LightingModel {
            switch self {
            case .physicallyBased: return .physicallyBased
            case .blinn: return .blinn
            case .lambert: return .lambert
            case .constant: return .constant
            }
        }
        static func from(_ model: SCNMaterial.LightingModel) -> LightingChoice {
            switch model {
            case .physicallyBased: return .physicallyBased
            case .blinn: return .blinn
            case .lambert: return .lambert
            case .constant: return .constant
            default: return .physicallyBased
            }
        }
    }

    @State private var radius: Double = 2500
    @State private var barWidth: CGFloat = 98
    @State private var barHeight: CGFloat = 390
    @State private var tilt: Double = -8
    @State private var yawDegrees: Double = 0
    @State private var uiScale: CGFloat = 1.5
    @State private var maxSceneHeight: Double = 1.8
    @State private var growth: Double = 1.5
    @State private var baseColor: Color = Color(white: 0.2)
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
    @State private var lightingChoice: LightingChoice = .physicallyBased
    @State private var isLooping: Bool = true

    @State private var selectedTab: AppTab = .record
    enum AppTab: String, CaseIterable, Identifiable {
        case record, feed, profile, map
        var id: String { rawValue }
    }
    
    @State private var isHoldingRecord: Bool = false
    @State private var feedSimValue: Double = 0
    @State private var feedAnimTask: Task<Void, Never>? = nil
    
    @State private var isIncreasing: Bool = false
    @State private var increaseTask: Task<Void, Never>? = nil

    @EnvironmentObject private var isometricBarSettings: IsometricBarSettings

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Tab", selection: $selectedTab) {
                    Text("Record").tag(AppTab.record)
                    Text("Feed").tag(AppTab.feed)
                    Text("Profile").tag(AppTab.profile)
                    Text("Map").tag(AppTab.map)
                }
                .pickerStyle(.segmented)

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
                        if selectedTab == .feed || selectedTab == .profile || selectedTab == .map {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Simulate Tab Content:").font(.subheadline).fontWeight(.medium)
                                HStack(spacing: 12) {
                                    Button(action: {
                                        let maxVal: Double = 3_323_000.0
                                        let newVal = Double.random(in: 0...maxVal)
                                        feedSimValue = newVal
                                        print("🔴 [Preview] Button tapped - calling animator with \(Int(newVal))m")
                                        // Use the new animation API
                                        RadiusBarAnimator.animate(to: newVal, duration: 0.8)
                                    }) {
                                        VStack(spacing: 2) {
                                            Image(systemName: "photo")
                                            Text("\(Int(feedSimValue)) m")
                                                .monospacedDigit()
                                                .font(.caption2)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .accessibilityLabel("Simulate feed/profile content")
                                    
                                    Button("Quick 1km") {
                                        print("🔴 [Preview] 1km button tapped")
                                        RadiusBarAnimator.showPostRadius(1_000, duration: 0.5)
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button("5km") {
                                        print("🔴 [Preview] 5km button tapped")
                                        RadiusBarAnimator.showPostRadius(5_000, duration: 0.6)
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button("50km") {
                                        print("🔴 [Preview] 50km button tapped")
                                        RadiusBarAnimator.showPostRadius(50_000, duration: 0.8)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                
                                // DEBUG: Direct binding test
                                Button("🧪 Test Direct Binding") {
                                    print("🔴 [Preview] Direct binding test - animating to 10km")
                                    withAnimation(.easeInOut(duration: 0.8)) {
                                        radius = 10_000
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                        }
                        HStack(spacing: 12) {
                            Button(isIncreasing ? "Stop Increasing" : "Start Increasing") {
                                toggleIncreasing()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(isIncreasing ? .red : .green)
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
                        Picker("Lighting", selection: $lightingChoice) {
                            Text("PBR").tag(LightingChoice.physicallyBased)
                            Text("Blinn").tag(LightingChoice.blinn)
                            Text("Lambert").tag(LightingChoice.lambert)
                            Text("Constant").tag(LightingChoice.constant)
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
            .onChange(of: selectedTab) { newValue in
                if newValue == .record && !isHoldingRecord {
                    radius = 0
                }
            }
            .onChange(of: isHoldingRecord) { newValue in
                if selectedTab == .record && !newValue {
                    radius = 0
                }
            }
            .onDisappear { stopIncreasingLoop() }
        }
    }

    private var configuredBar: AnyView {
        let tabBase: Color
        let tabTint: Color
        switch selectedTab {
        case .record:
            tabBase = Color(white: 0.2)
            tabTint = .indigo
        case .feed:
            tabBase = Color(white: 0.2)
            tabTint = .teal
        case .profile:
            tabBase = Color(white: 0.2)
            tabTint = .pink
        case .map:
            tabBase = Color(white: 0.2)
            tabTint = .green
        }
        let effectiveRadius: Binding<Double> = $radius
        
        let base = IsometricRadiusBar(radius: effectiveRadius, baseColor: tabBase, tintColor: tabTint, growthSpeed: 1.5, maxSceneHeight: 1.8, uiScale: 1.5, maxRuntimeRadius: 3_323_000.0)
        var cfg = base
        cfg.useNormalMap = useNormalMapPreview
        cfg.lightingModel = lightingChoice.model
        cfg.autoLoop = true
        if selectedTab == .record || selectedTab == .feed || selectedTab == .profile || selectedTab == .map {
            cfg.autoLoop = false
        }

        var view = AnyView(cfg)
        // Apply app-matching sizing and tilt from shared settings
        view = AnyView(view
            .frame(width: isometricBarSettings.barWidth, height: isometricBarSettings.barHeight)
            .rotation3DEffect(.degrees(isometricBarSettings.barTiltDegrees), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
        )
        // If the preview wants to scale the whole bar additionally, apply it after frame/tilt
        if scaleMode == .scaleBy {
            view = AnyView(view.scaleEffect(scaleByFactor))
        }
        return view
    }

    private var growthButtons: some View {
        let percents: [Double] = [0.10, 0.20, 0.30, 0.40, 0.50, 0.75, 1.0]
        return WrapHStack(spacing: 8) {
            ForEach(percents, id: \.self) { p in
                Button(String(format: "%.0f%%", p * 100)) {
                    let target = earthMeters * p
                    animateTo(target)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func animateTo(_ target: Double) {
        withAnimation(.interpolatingSpring(mass: 1.0, stiffness: springStiffness(), damping: springDampingCoef(), initialVelocity: 0)) {
            radius = min(max(0, target), 3_323_000.0)
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
        animateTo(clampedTarget)
        completion?()
    }

    private func startLoopingAnimation() {
        Task { @MainActor in
            // Water-like continuous driver: small nudges each frame
            var goingUp = true
            var targetHigh = earthMeters * Double.random(in: 0.3...0.8)
            let fps: Double = 60.0
            let dt: Double = 1.0 / fps
            while isLooping {
                if selectedTab == .record || selectedTab == .feed || selectedTab == .profile || selectedTab == .map {
                    try? await Task.sleep(nanoseconds: UInt64(dt * 1_000_000_000))
                    continue
                }
                let current = radius
                let target = goingUp ? targetHigh : 0.0
                // Move a small fraction toward the target each frame
                let diff = target - current
                // Speed: reach ~in 4–6 seconds depending on distance
                let ratePerSecond = max(0.25, min(0.6, abs(diff) / (earthMeters * 2.0)))
                let step = diff * ratePerSecond * dt
                let next = current + step
                withAnimation(.interpolatingSpring(mass: 1.0, stiffness: springStiffness(), damping: springDampingCoef(), initialVelocity: 0)) {
                    radius = min(max(0, next), 3_323_000.0)
                }
                // Check bounds to flip direction
                if goingUp {
                    if abs(diff) < max(250.0, targetHigh * 0.01) { // close to high target
                        goingUp = false
                    }
                } else {
                    if radius <= 1.0 { // close to zero
                        goingUp = true
                        targetHigh = earthMeters * Double.random(in: 0.3...0.8)
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(dt * 1_000_000_000))
            }
        }
    }

    private func tweenRadius(to target: Double, duration: Double = 0.6) {
        let start = radius
        let end = min(max(0, target), 3_323_000.0)
        if start == end { return }
        feedAnimTask?.cancel()
        let fps: Double = 60.0
        let dt: Double = 1.0 / fps
        let startTime = CACurrentMediaTime()
        feedAnimTask = Task { @MainActor in
            while !Task.isCancelled {
                let t = min(1.0, (CACurrentMediaTime() - startTime) / duration)
                // Smooth ease-in-out
                let eased = t * t * (3 - 2 * t)
                let value = start + (end - start) * eased
                radius = value
                if t >= 1.0 { break }
                try? await Task.sleep(nanoseconds: UInt64(dt * 1_000_000_000))
            }
        }
    }
    
    private func toggleIncreasing() {
        isIncreasing.toggle()
        if isIncreasing {
            startIncreasingLoop()
        } else {
            stopIncreasingLoop()
        }
    }

    private func startIncreasingLoop() {
        stopIncreasingLoop()
        let maxVal: Double = 3_323_000.0
        increaseTask = Task { @MainActor in
            let fps: Double = 60.0
            let dt: Double = 1.0 / fps
            while !Task.isCancelled && isIncreasing {
                // Increase toward max at a steady rate; wrap to 0 when reaching cap
                let stepPerSecond = maxVal / 6.0 // reach cap in ~6s
                let next = min(maxVal, radius + stepPerSecond * dt)
                withAnimation(.easeInOut(duration: dt)) {
                    radius = next
                }
                if abs(next - maxVal) < 1.0 {
                    // wrap back to zero and continue increasing
                    withAnimation(.easeInOut(duration: 0.3)) { radius = 0 }
                }
                try? await Task.sleep(nanoseconds: UInt64(dt * 1_000_000_000))
            }
        }
    }

    private func stopIncreasingLoop() {
        increaseTask?.cancel()
        increaseTask = nil
    }
}

private struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: spacing) { content() }
    }
}

#if DEBUG
// Preview-only fallback declarations if the app target doesn’t import these types here.
// Comment these out if the real types are available to this file.
// IsometricBarSettings is now imported from IsometricBarSettings.swift
private struct SharedPreviewSettings {
    static let settings: IsometricBarSettings = {
        let s = IsometricBarSettings()
        s.horizontalOffset = 80
        s.bottomOffset = 1
        s.barWidth = 98
        s.barHeight = 390
        s.barTiltDegrees = -8
        return s
    }()
}
#endif

#Preview("Radius Bar Properties") {
    RadiusBarOnlyPreview()
        .environmentObject(SharedPreviewSettings.settings)
}
