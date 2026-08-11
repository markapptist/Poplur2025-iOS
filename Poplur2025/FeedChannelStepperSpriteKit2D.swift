import SwiftUI
import SpriteKit

struct FeedChannelStepperSpriteKit2D: View {
    let activeButton: FeedChannelButtonKind?
    let pressToken: Int
    let onUp: () -> Void
    let onDown: () -> Void

    var body: some View {
        FeedChannelStepper3D(
            activeButton: activeButton,
            pressToken: pressToken,
            onUp: onUp,
            onDown: onDown
        )
    }
}

private struct FeedChannelButtonSpriteView: UIViewRepresentable {
    let kind: FeedChannelButtonKind
    let isPressed: Bool
    let pressToken: Int

    func makeUIView(context: Context) -> FeedChannelButtonSpriteHost {
        let view = FeedChannelButtonSpriteHost(kind: kind)
        view.update(isPressed: isPressed, pressToken: pressToken)
        return view
    }

    func updateUIView(_ uiView: FeedChannelButtonSpriteHost, context: Context) {
        uiView.update(isPressed: isPressed, pressToken: pressToken)
    }

    static func dismantleUIView(_ uiView: FeedChannelButtonSpriteHost, coordinator: ()) {
        uiView.poplurTearDown()
    }
}

private final class FeedChannelButtonSpriteHost: PoplurManagedSKView {
    private let buttonScene: FeedChannelButtonSpriteScene

    init(kind: FeedChannelButtonKind) {
        buttonScene = FeedChannelButtonSpriteScene(kind: kind)
        super.init(performanceName: "FeedChannelButton2D")
        configureView()
    }

    required init?(coder: NSCoder) {
        buttonScene = FeedChannelButtonSpriteScene(kind: .ch)
        super.init(coder: coder)
        configureView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        buttonScene.size = bounds.size
        buttonScene.layoutButton()
    }

    func update(isPressed: Bool, pressToken: Int) {
        buttonScene.update(isPressed: isPressed, pressToken: pressToken)
    }

    private func configureView() {
        backgroundColor = .clear
        allowsTransparency = true
        ignoresSiblingOrder = true
        isUserInteractionEnabled = false
        preferredFramesPerSecond = PoplurPerformanceManager.shared.targetFPS

        buttonScene.scaleMode = .resizeFill
        buttonScene.backgroundColor = .clear
        presentScene(buttonScene)
    }
}

private final class FeedChannelButtonSpriteScene: SKScene {
    private let kind: FeedChannelButtonKind
    private let rootNode = SKNode()
    private let glowNode = SKSpriteNode()
    private let spriteNode = SKSpriteNode()
    private var lastAssetName: String?
    private var lastPressToken = 0
    private var centerPoint = CGPoint.zero

    init(kind: FeedChannelButtonKind) {
        self.kind = kind
        super.init(size: .zero)
        configureScene()
    }

    required init?(coder aDecoder: NSCoder) {
        kind = .ch
        super.init(coder: aDecoder)
        configureScene()
    }

    func layoutButton() {
        guard size.width > 0, size.height > 0 else { return }
        centerPoint = CGPoint(x: size.width / 2, y: size.height / 2)
        rootNode.position = centerPoint

        let texture = spriteNode.texture ?? SKTexture(imageNamed: kind.unpressedAssetName)
        let textureSize = texture.size()
        guard textureSize.width > 0, textureSize.height > 0 else { return }

        let scale = min(size.width / textureSize.width, size.height / textureSize.height) * 0.98
        let buttonSize = CGSize(width: textureSize.width * scale, height: textureSize.height * scale)
        spriteNode.size = buttonSize
        glowNode.size = CGSize(width: buttonSize.width * 1.08, height: buttonSize.height * 1.08)
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
        addChild(rootNode)

        glowNode.zPosition = 1
        glowNode.alpha = 0.28
        glowNode.blendMode = .add
        rootNode.addChild(glowNode)

        spriteNode.zPosition = 2
        rootNode.addChild(spriteNode)

        setTexture(assetName: kind.unpressedAssetName)
        startIdleFloat()
    }

    private func setTexture(assetName: String) {
        guard assetName != lastAssetName else { return }
        let texture = SKTexture(imageNamed: assetName)
        texture.filteringMode = .linear
        spriteNode.texture = texture
        glowNode.texture = texture
        lastAssetName = assetName
        layoutButton()
    }

    private func runPressAnimation() {
        rootNode.removeAction(forKey: "idle-float")
        rootNode.removeAction(forKey: "press")
        glowNode.removeAction(forKey: "press-glow")

        rootNode.position = centerPoint
        rootNode.setScale(1.0)
        rootNode.zRotation = 0
        glowNode.alpha = 0.28

        let compress = SKAction.group([
            .scale(to: 0.86, duration: 0.07),
            .rotate(toAngle: kind == .up ? 0.06 : -0.06, duration: 0.07)
        ])
        compress.timingMode = .easeOut

        let overshoot = SKAction.group([
            .scale(to: 1.15, duration: 0.13),
            .rotate(toAngle: kind == .up ? -0.04 : 0.04, duration: 0.13)
        ])
        overshoot.timingMode = .easeOut

        let settle = SKAction.group([
            .scale(to: 1.0, duration: 0.10),
            .rotate(toAngle: 0, duration: 0.10)
        ])
        settle.timingMode = .easeInEaseOut

        let restartIdle = SKAction.run { [weak self] in
            self?.startIdleFloat()
        }

        rootNode.run(.sequence([compress, overshoot, settle, restartIdle]), withKey: "press")

        glowNode.run(
            .sequence([
                .fadeAlpha(to: 0.74, duration: 0.07),
                .fadeAlpha(to: 0.34, duration: 0.18),
                .fadeAlpha(to: 0.28, duration: 0.08)
            ]),
            withKey: "press-glow"
        )
    }

    private func startIdleFloat() {
        guard rootNode.action(forKey: "idle-float") == nil else { return }
        let floatUp = SKAction.moveBy(x: 0, y: 1.8, duration: 0.9)
        floatUp.timingMode = .easeInEaseOut
        let floatDown = SKAction.moveBy(x: 0, y: -1.8, duration: 0.9)
        floatDown.timingMode = .easeInEaseOut
        rootNode.run(.repeatForever(.sequence([floatUp, floatDown])), withKey: "idle-float")
    }
}
