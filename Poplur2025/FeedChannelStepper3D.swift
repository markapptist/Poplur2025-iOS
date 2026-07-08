import SwiftUI
import SceneKit
import UIKit

enum FeedChannelButtonKind: Equatable {
    case up
    case ch
    case down

    var unpressedAssetName: String {
        switch self {
        case .up: return "feed_channel_up_unpressed"
        case .ch: return "feed_channel_ch_unpressed"
        case .down: return "feed_channel_down_unpressed"
        }
    }

    var pressedAssetName: String {
        switch self {
        case .up: return "feed_channel_up_pressed"
        case .ch: return "feed_channel_ch_pressed"
        case .down: return "feed_channel_down_pressed"
        }
    }

    var sceneSize: CGSize {
        switch self {
        case .ch: return CGSize(width: 1.72, height: 1.16)
        case .up: return CGSize(width: 1.58, height: 1.36)
        case .down: return CGSize(width: 1.52, height: 1.40)
        }
    }
}

struct FeedChannelStepper3D: View {
    let activeButton: FeedChannelButtonKind?
    let pressToken: Int
    let onUp: () -> Void
    let onDown: () -> Void
    @ObservedObject private var skinStore = CubeSkinStore.shared

    var body: some View {
        // Plain up/down chevron buttons — no plate/background behind them,
        // and no middle "CH" tile (they're just the two arrows now).
        VStack(spacing: 20) {
            FeedChannelButtonHitTarget(accessibilityLabel: "Channel up", action: onUp) {
                ThemedFeedChannelButton(
                    kind: .up,
                    skin: skinStore.current,
                    isPressed: activeButton == .up,
                    pressToken: pressToken
                )
                .frame(width: 76, height: 76)
            }

            FeedChannelButtonHitTarget(accessibilityLabel: "Channel down", action: onDown) {
                ThemedFeedChannelButton(
                    kind: .down,
                    skin: skinStore.current,
                    isPressed: activeButton == .down,
                    pressToken: pressToken
                )
                .frame(width: 76, height: 76)
            }
        }
        .frame(width: 86, height: 200)
    }
}

private struct ThemedFeedChannelButton: View {
    let kind: FeedChannelButtonKind
    let skin: CubeSkin
    let isPressed: Bool
    let pressToken: Int

    private var theme: CubeSkinAppTheme { skin.appTheme }

    var body: some View {
        // No background plate — just the themed chevron glyph. It keeps the skin's
        // glossy shader + glow so it still reads as a button, and dips slightly when pressed.
        icon
            .foregroundStyle(iconStyle)
            .shadow(color: glowColor, radius: skin == .camo ? 2 : 8)
            .shadow(color: Color.black.opacity(skin == .toy ? 0.16 : 0.55), radius: 2, x: 0, y: 2)
            .scaleEffect(isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.58), value: pressToken)
            .animation(.spring(response: 0.20, dampingFraction: 0.62), value: isPressed)
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .up:
            Image(systemName: "chevron.up")
                .poplurIconShader()
                .font(.system(size: 30, weight: .black, design: .rounded))
        case .ch:
            Text("CH")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .poplurTextShader(intensity: 0.78)
                .minimumScaleFactor(0.72)
        case .down:
            Image(systemName: "chevron.down")
                .poplurIconShader()
                .font(.system(size: 31, weight: .black, design: .rounded))
        }
    }

    private var iconStyle: some ShapeStyle {
        switch skin {
        case .rainbow:
            return AnyShapeStyle(
                LinearGradient(colors: [.yellow, .green, .cyan, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        case .toy where kind == .up:
            return AnyShapeStyle(Color(red: 0.02, green: 0.23, blue: 0.72))
        case .toy where kind == .down:
            return AnyShapeStyle(Color(red: 0.92, green: 0.10, blue: 0.10))
        default:
            return AnyShapeStyle(theme.primaryText)
        }
    }

    private var glowColor: Color {
        switch skin {
        case .ice: return Color.white.opacity(0.78)
        case .sparklePink, .rainbow, .rubber: return theme.accent.opacity(0.86)
        default: return theme.shadow
        }
    }
}

struct FeedChannelButtonHitTarget<Content: View>: View {
    let accessibilityLabel: String
    let action: () -> Void
    let content: Content

    init(accessibilityLabel: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture()
                .onEnded(action)
        )
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isButton)
    }
}

private struct FeedChannelButtonSceneView: UIViewRepresentable {
    let kind: FeedChannelButtonKind
    let isPressed: Bool
    let pressToken: Int

    func makeUIView(context: Context) -> FeedChannelButtonSceneHost {
        let view = FeedChannelButtonSceneHost(kind: kind)
        view.update(isPressed: isPressed, pressToken: pressToken)
        return view
    }

    func updateUIView(_ uiView: FeedChannelButtonSceneHost, context: Context) {
        uiView.update(isPressed: isPressed, pressToken: pressToken)
    }
}

private final class FeedChannelButtonSceneHost: SCNView {
    private let kind: FeedChannelButtonKind
    private let buttonNode = SCNNode()
    private let faceNode = SCNNode()
    private let baseEuler = SCNVector3(-0.14, 0.16, -0.01)
    private var lastAssetName: String?
    private var lastPressToken = 0

    init(kind: FeedChannelButtonKind) {
        self.kind = kind
        super.init(frame: .zero, options: nil)
        configureScene()
    }

    required init?(coder: NSCoder) {
        self.kind = .ch
        super.init(coder: coder)
        configureScene()
    }

    func update(isPressed: Bool, pressToken: Int) {
        setTexture(assetName: isPressed ? kind.pressedAssetName : kind.unpressedAssetName)

        guard pressToken != lastPressToken else { return }
        lastPressToken = pressToken

        if isPressed {
            runPressAnimation()
        }
    }

    private func configureScene() {
        backgroundColor = .clear
        allowsCameraControl = false
        autoenablesDefaultLighting = false
        antialiasingMode = .multisampling4X
        isJitteringEnabled = true
        isUserInteractionEnabled = false
        preferredFramesPerSecond = 60
        rendersContinuously = true

        let scene = SCNScene()
        self.scene = scene

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 32
        cameraNode.position = SCNVector3(0, 0, 4.2)
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 390
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 840
        key.light?.color = UIColor(red: 0.72, green: 0.18, blue: 1.0, alpha: 1)
        key.position = SCNVector3(-1.2, 1.7, 2.4)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.intensity = 560
        rim.light?.color = UIColor(red: 0.08, green: 0.54, blue: 1.0, alpha: 1)
        rim.position = SCNVector3(1.3, -1.1, 1.8)
        scene.rootNode.addChildNode(rim)

        buttonNode.eulerAngles = baseEuler
        scene.rootNode.addChildNode(buttonNode)

        let size = kind.sceneSize
        let body = SCNBox(
            width: size.width * 0.88,
            height: size.height * 0.76,
            length: 0.16,
            chamferRadius: kind == .ch ? 0.16 : 0.13
        )
        let bodyMaterial = SCNMaterial()
        bodyMaterial.lightingModel = .physicallyBased
        bodyMaterial.diffuse.contents = UIColor(red: 0.05, green: 0.03, blue: 0.10, alpha: 0.96)
        bodyMaterial.emission.contents = kind == .down
            ? UIColor(red: 0.02, green: 0.13, blue: 0.35, alpha: 1)
            : UIColor(red: 0.22, green: 0.03, blue: 0.25, alpha: 1)
        bodyMaterial.metalness.contents = 0.35
        bodyMaterial.roughness.contents = 0.26
        body.materials = Array(repeating: bodyMaterial, count: 6)

        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, -0.02, -0.09)
        buttonNode.addChildNode(bodyNode)

        let face = SCNPlane(width: size.width, height: size.height)
        let faceMaterial = SCNMaterial()
        faceMaterial.isDoubleSided = true
        faceMaterial.lightingModel = .constant
        faceMaterial.diffuse.contents = UIImage(named: kind.unpressedAssetName)
        faceMaterial.transparencyMode = .aOne
        faceMaterial.blendMode = .alpha
        face.materials = [faceMaterial]

        faceNode.geometry = face
        faceNode.position = SCNVector3(0, 0, 0.035)
        buttonNode.addChildNode(faceNode)

        startIdleFloat()
    }

    private func setTexture(assetName: String) {
        guard assetName != lastAssetName,
              let material = faceNode.geometry?.firstMaterial else { return }
        material.diffuse.contents = UIImage(named: assetName)
        lastAssetName = assetName
    }

    private func runPressAnimation() {
        buttonNode.removeAction(forKey: "idle-float")
        buttonNode.removeAction(forKey: "press")
        buttonNode.position = SCNVector3Zero
        buttonNode.scale = SCNVector3(1, 1, 1)
        buttonNode.eulerAngles = baseEuler

        let compress = SCNAction.group([
            .scale(to: 0.88, duration: 0.07),
            .moveBy(x: 0, y: -0.012, z: -0.10, duration: 0.07),
            .rotateTo(x: CGFloat(baseEuler.x - 0.10), y: CGFloat(baseEuler.y - 0.03), z: CGFloat(baseEuler.z), duration: 0.07)
        ])
        compress.timingMode = .easeOut

        let overshoot = SCNAction.group([
            .scale(to: 1.12, duration: 0.13),
            .moveBy(x: 0, y: 0.020, z: 0.14, duration: 0.13),
            .rotateTo(x: CGFloat(baseEuler.x + 0.05), y: CGFloat(baseEuler.y + 0.05), z: CGFloat(baseEuler.z), duration: 0.13)
        ])
        overshoot.timingMode = .easeOut

        let settle = SCNAction.group([
            .scale(to: 1.0, duration: 0.10),
            .move(to: SCNVector3Zero, duration: 0.10),
            .rotateTo(x: CGFloat(baseEuler.x), y: CGFloat(baseEuler.y), z: CGFloat(baseEuler.z), duration: 0.10)
        ])
        settle.timingMode = .easeInEaseOut

        let restartIdle = SCNAction.run { [weak self] _ in
            self?.startIdleFloat()
        }

        buttonNode.runAction(.sequence([compress, overshoot, settle, restartIdle]), forKey: "press")
    }

    private func startIdleFloat() {
        guard buttonNode.action(forKey: "idle-float") == nil else { return }
        let floatUp = SCNAction.moveBy(x: 0, y: 0.018, z: 0.0, duration: 0.9)
        floatUp.timingMode = .easeInEaseOut
        let floatDown = SCNAction.moveBy(x: 0, y: -0.018, z: 0.0, duration: 0.9)
        floatDown.timingMode = .easeInEaseOut
        buttonNode.runAction(.repeatForever(.sequence([floatUp, floatDown])), forKey: "idle-float")
    }
}
