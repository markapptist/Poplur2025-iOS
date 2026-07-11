import SwiftUI
import SpriteKit
import CoreGraphics
import UIKit
import CoreImage

private var isRunningInPreviews: Bool {
    let env = ProcessInfo.processInfo.environment
    return env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || env["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
}

private final class WelcomeScene: SKScene {

    // Coordinator to communicate with SwiftUI
    final class Coordinator: ObservableObject {
        @Published var didTapSignIn = false
        @Published var didTapSignUp = false
    }

    let coordinator: Coordinator

    // Nodes
    private let dottedOverlayNode = SKNode()
    private let flowerNode = SKNode()
    private let scallopMaskNode = SKShapeNode()
    private let floor = SKNode()
    private var backgroundNode: SKSpriteNode?
    private var didAnimateBackground = false

    // Warm-up gate
    private var didWarmUp = false
    private var warmUpFramesRemaining = 8        // wait more frames
    private var firstUpdateTime: TimeInterval?
    private let warmUpMinElapsed: TimeInterval = 0.28 // and at least ~280ms

    // Removed long stall: set hard delay to zero so intro begins after brief warm-up
    private let delayBeforeStart: TimeInterval = 0.0

    // Whether your background art is fully opaque. If true, we can skip blending during the move.
    // Set true if backgrounds are JPEG/opaque; keep false if they need transparency.
    private let isBackgroundOpaque: Bool = false

    // Texture cache for multiple backgrounds
    private var backgroundTextures: [String: SKTexture] = [:]

    // We’ll keep a proxy but won’t use it for animation anymore
    private let proxy = SKShapeNode(rectOf: CGSize(width: 260, height: 56), cornerRadius: 28)

    // Node names
    private let buttonShadowName = "buttonShadow"
    private let signinNodeName = "signin"
    private let signupNodeName = "signup"
    private let signupShadowName = "signupShadow"

    // Layout constants (SpriteKit points)
    private let floorY: CGFloat = 24
    private let bounceAreaHeight: CGFloat = 180

    // Asset names
    private let backgroundAssetNames = ["slideup", "slideup_alt1", "slideup_alt2"]
    private let defaultBackgroundName = "slideup"
    private let logoAssetName = "logo"

    // Layout is anchored from the bottom of the screen (matching the login cube, which is
    // pinned 8pt above the bottom edge) so the gap between logo/buttons/cube stays equal
    // regardless of device height, rather than mixing top-, center-, and bottom-anchored math.
    // cube: 200pt tall, 8pt bottom padding → cube spans [8, 208] from the bottom.
    private let sectionSpacing: CGFloat = 28   // equal gap: logo↔buttons and buttons↔cube
    private let buttonGap: CGFloat = 16        // tighter gap within the Sign In / Sign Up pair
    private let buttonSize = CGSize(width: 220, height: 52)
    private let logoSize: CGFloat = 200

    private var signUpCenterY: CGFloat {
        let bottom = 208 + sectionSpacing
        return bottom + buttonSize.height / 2
    }
    private var signInCenterY: CGFloat {
        let bottom = signUpCenterY + buttonSize.height / 2 + buttonGap
        return bottom + buttonSize.height / 2
    }
    private var logoCenterY: CGFloat {
        let bottom = signInCenterY + buttonSize.height / 2 + sectionSpacing
        return bottom + logoSize / 2
    }

    // Track size during animation to avoid size churn
    private var isAnimatingBackground = false
    private var lockedBackgroundSize: CGSize?

    init(size: CGSize, coordinator: Coordinator) {
        self.coordinator = coordinator
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .white

        // Pipeline tuning
        self.view?.ignoresSiblingOrder = true
        // Note: SKScene.view is nil in init; we will also set this from WelcomeView via SpriteView modifiers.
    }

    required init?(coder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        // Make sure SKView is optimized
        view.ignoresSiblingOrder = true
        #if os(iOS)
        if view.preferredFramesPerSecond < 120 {
            view.preferredFramesPerSecond = 120 // take advantage of ProMotion where available
        }
        #endif

        setupPhysics()
        preloadBackgrounds { [weak self] in
            self?.buildBackground(using: self?.defaultBackgroundName ?? "")
            // Do not animate here; we wait for warm-up in update(_:)
        }
        buildDottedOverlay()
        buildFlower()
        buildScallopedBottom()
        buildBouncingSignIn()
        layoutAll()

        // Warm up the pop sound once to avoid first-play hitch later
        if !isRunningInPreviews {
            let warmUp = SKAction.sequence([
                .wait(forDuration: 0.05),
                .playSoundFileNamed("pop", waitForCompletion: false)
            ])
            run(warmUp, withKey: "warmUpPopSound")
        }
    }

    private func setupPhysics() {
        physicsWorld.gravity = CGVector(dx: 0, dy: -7.5)
    }

    // MARK: - Backgrounds (multiple)

    private func preloadBackgrounds(completion: @escaping () -> Void) {
        var textures: [SKTexture] = []

        for name in backgroundAssetNames {
            if let uiImage = UIImage(named: name) {
                let tex = SKTexture(image: uiImage)
                tex.filteringMode = .linear // smoother sampling during motion
                backgroundTextures[name] = tex
                textures.append(tex)
            }
        }

        if textures.isEmpty {
            let fallbackImage = UIImage(systemName: "photo") ?? UIImage()
            let tex = SKTexture(image: fallbackImage)
            tex.filteringMode = .linear
            backgroundTextures[defaultBackgroundName] = tex
            textures = [tex]
        }

        SKTexture.preload(textures) {
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    private func buildBackground(using name: String) {
        if let bg = backgroundNode, let tex = backgroundTextures[name] {
            bg.texture = tex
            sizeAndPlaceBackground(bg, animateIfNeeded: false)
            return
        }

        guard let texture = backgroundTextures[name] ?? backgroundTextures[defaultBackgroundName] else { return }

        // Pre-compute size bounds to pre-size node before adding
        let sceneSize = size
        let baseSize = texture.size()
        let targetWidth = sceneSize.width * 0.85
        let targetHeight = sceneSize.height * 0.85
        let sx = targetWidth / max(baseSize.width, 1)
        let sy = targetHeight / max(baseSize.height, 1)
        let fitScale = min(sx, sy)
        let preSize = CGSize(width: baseSize.width * fitScale, height: baseSize.height * fitScale)
        lockedBackgroundSize = preSize

        let bg = SKSpriteNode(texture: texture, size: preSize)
        bg.name = "background"
        bg.zPosition = -100
        bg.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        if isBackgroundOpaque {
            bg.blendMode = .replace
        } // else default alpha blending

        // Make first frame invisible, then fade in once uploaded (hides upload hitch)
        bg.alpha = 0.0

        backgroundNode = bg
        addChild(bg)

        // Place offscreen initially; animation will start after warm-up in update(_:)
        let finalPosition = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        let startY = sceneSize.height + (preSize.height / 2) + 40
        bg.position = CGPoint(x: finalPosition.x, y: startY)

        // Fade-in over a couple frames to ensure texture is resident
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.12)
        fadeIn.timingMode = .easeOut
        bg.run(fadeIn)
    }

    private func sizeAndPlaceBackground(_ bg: SKSpriteNode, animateIfNeeded: Bool) {
        guard let baseSize = bg.texture?.size() else { return }

        let sceneSize = size
        let targetWidth = sceneSize.width * 0.85
        let targetHeight = sceneSize.height * 0.85
        let sx = targetWidth / max(baseSize.width, 1)
        let sy = targetHeight / max(baseSize.height, 1)
        let fitScale = min(sx, sy)
        let idealSize = CGSize(width: baseSize.width * fitScale, height: baseSize.height * fitScale)

        // Keep the size locked during the animation to prevent churn
        if !isAnimatingBackground {
            if let locked = lockedBackgroundSize {
                if abs(locked.width - idealSize.width) > 1.0 || abs(locked.height - idealSize.height) > 1.0 {
                    lockedBackgroundSize = idealSize
                }
            } else {
                lockedBackgroundSize = idealSize
            }
            if let locked = lockedBackgroundSize {
                if abs(bg.size.width - locked.width) > 1.0 || abs(bg.size.height - locked.height) > 1.0 {
                    bg.size = locked
                }
            }
        }

        let finalPosition = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)

        if animateIfNeeded {
            isAnimatingBackground = true

            // Start above screen (if not already)
            let startY = sceneSize.height + (bg.size.height / 2) + 40
            if bg.position.y < startY - 1 || bg.position.y > startY + 1 {
                bg.position = CGPoint(x: finalPosition.x, y: startY)
            }

            // Drop + settle (spring-like: overshoot past rest position, then settle back)
            let dropDuration: TimeInterval = 0.8
            let settleDuration: TimeInterval = 0.28
            let overshoot: CGFloat = 22

            let deltaY = (finalPosition.y + overshoot) - bg.position.y
            let moveDown = SKAction.moveBy(x: 0, y: deltaY, duration: dropDuration)
            moveDown.timingMode = .easeOut

            let settle = SKAction.moveTo(y: finalPosition.y, duration: settleDuration)
            settle.timingMode = .easeInEaseOut

            // When finished, unfreeze size and then strictly sequence: logo fade -> button fade
            let finish = SKAction.run { [weak self] in
                self?.isAnimatingBackground = false
                self?.fadeLogoThenButton()
            }

            bg.run(.sequence([moveDown, settle, finish]), withKey: "bgDropIn")
        } else {
            bg.removeAction(forKey: "bgDropIn")
            bg.position = finalPosition
        }
    }

    // Strict sequence: first logo fade, then button fade (and shadow), then sound + confetti
    private func fadeLogoThenButton() {
        // Tunable timings
        let logoFadeDuration: TimeInterval = 0.45
        let buttonFadeDuration: TimeInterval = 0.45

        // Logo
        if let logo = flowerNode.childNode(withName: "logo") as? SKSpriteNode {
            logo.removeAllActions()
            // Keep fully hidden until we jump to half opacity, then animate to 1.0
            logo.alpha = 0.0

            let jumpToHalf = SKAction.run { [weak logo] in
                logo?.alpha = 0.5
            }
            let fadeToFull = SKAction.fadeAlpha(to: 1.0, duration: logoFadeDuration)
            fadeToFull.timingMode = .easeIn
            let fadeSequence = SKAction.sequence([jumpToHalf, fadeToFull])

            // Logo drops in from above with a small spring overshoot, in parallel with the fade
            let restPosition = CGPoint(x: size.width / 2, y: logoCenterY)
            let dropDown = SKAction.move(to: CGPoint(x: restPosition.x, y: restPosition.y + 18), duration: logoFadeDuration * 1.15)
            dropDown.timingMode = .easeOut
            let settle = SKAction.move(to: restPosition, duration: logoFadeDuration * 0.45)
            settle.timingMode = .easeInEaseOut
            let dropSequence = SKAction.sequence([dropDown, settle])

            let fadeAndDrop = SKAction.group([fadeSequence, dropSequence])

            // After logo completes, reveal the logo shadow, then start button fade
            let sequence = SKAction.sequence([
                fadeAndDrop,
                SKAction.run { [weak self] in
                    // Reveal the logo shadow now
                    if let self, let shadow = self.flowerNode.children.first(where: { $0 !== logo && $0 is SKSpriteNode }) as? SKSpriteNode {
                        shadow.alpha = 0.2
                    }
                    self?.fadeButton(duration: buttonFadeDuration)
                }
            ])
            logo.run(sequence, withKey: "logoHalfThenFullThenButton")
        } else {
            // If no logo found, just proceed to button fade
            fadeButton(duration: buttonFadeDuration)
        }
    }

    private func fadeButton(duration: TimeInterval) {
        // Button and shadow fade together
        let fade = SKAction.fadeIn(withDuration: duration)
        fade.timingMode = .easeIn

        if let signinSprite = childNode(withName: signinNodeName) {
            signinSprite.removeAllActions()
            signinSprite.alpha = 0.0
            signinSprite.run(fade, withKey: "buttonFade")
        }

        if let shadowSprite = childNode(withName: buttonShadowName) {
            shadowSprite.removeAllActions()
            shadowSprite.alpha = 0.0
            shadowSprite.run(fade, withKey: "buttonShadowFade")
        }

        if let signupNode = childNode(withName: signupNodeName) {
            signupNode.removeAllActions()
            signupNode.alpha = 0.0
            signupNode.run(fade, withKey: "signupButtonFade")
        }

        if let signupShadow = childNode(withName: signupShadowName) {
            signupShadow.removeAllActions()
            signupShadow.alpha = 0.0
            signupShadow.run(fade, withKey: "signupShadowFade")
        }

        // After button fade finishes: play pop sound.
        let playPop = SKAction.sequence([
            .wait(forDuration: duration),
            .playSoundFileNamed("pop", waitForCompletion: false)
        ])
        if !isRunningInPreviews {
            self.run(playPop, withKey: "playPop")
        }
    }

    // Floating helper: up-down forever with easing and optional phase offset start
    private func startFloating(node: SKNode, amplitude: CGFloat, period: TimeInterval, phaseOffset: TimeInterval) {
        // Ensure we don’t stack multiple floaters
        node.removeAction(forKey: "floatForever")

        let up = SKAction.moveBy(x: 0, y: amplitude, duration: period / 2)
        up.timingMode = .easeInEaseOut
        let down = SKAction.moveBy(x: 0, y: -amplitude, duration: period / 2)
        down.timingMode = .easeInEaseOut
        let cycle = SKAction.sequence([up, down])
        let forever = SKAction.repeatForever(cycle)

        if phaseOffset > 0 {
            // Start mid-cycle to offset phase
            let delay = SKAction.wait(forDuration: phaseOffset)
            node.run(SKAction.sequence([delay, forever]), withKey: "floatForever")
        } else {
            node.run(forever, withKey: "floatForever")
        }
    }

    // Handle taps on the welcome buttons to trigger navigation
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // signinNode is a plain SKNode (see buildBouncingSignIn), not SKSpriteNode — the
        // previous `as? SKSpriteNode` cast always failed, so this branch never ran and
        // Sign In silently did nothing when tapped.
        if let signinSprite = childNode(withName: signinNodeName),
           signinSprite.contains(location) {
            // Simple tap feedback
            let pulseDown = SKAction.scale(to: 0.96, duration: 0.06)
            let pulseUp = SKAction.scale(to: 1.0, duration: 0.08)
            pulseDown.timingMode = .easeOut
            pulseUp.timingMode = .easeInEaseOut
            signinSprite.run(.sequence([pulseDown, pulseUp]))

            // Notify SwiftUI to navigate
            coordinator.didTapSignIn = true
            return
        }

        if let signupNode = childNode(withName: signupNodeName),
           signupNode.contains(location) {
            let pulseDown = SKAction.scale(to: 0.96, duration: 0.06)
            let pulseUp = SKAction.scale(to: 1.0, duration: 0.08)
            pulseDown.timingMode = .easeOut
            pulseUp.timingMode = .easeInEaseOut
            signupNode.run(.sequence([pulseDown, pulseUp]))

            coordinator.didTapSignUp = true
        }
    }

    // External API to resize scene without recreating it
    func resize(to newSize: CGSize) {
        self.size = newSize
        // Only update size if not animating; otherwise keep locked size until after
        if let bg = backgroundNode, !isAnimatingBackground {
            lockedBackgroundSize = nil // allow recompute to new ideal size
            sizeAndPlaceBackground(bg, animateIfNeeded: false)
        }
        layoutAll()
    }

    // MARK: - Foreground Nodes

    private func buildDottedOverlay() {
        dottedOverlayNode.removeAllChildren()
        dottedOverlayNode.zPosition = 12
        addChild(dottedOverlayNode)

        let insetTop: CGFloat = 24
        let overlayWidth = min(600, size.width - 48)
        let overlayHeight: CGFloat = 640 - insetTop - 18
        let overlayMinY = max(size.height - 640 + insetTop, 0)
        let overlayRect = CGRect(x: (size.width - overlayWidth)/2,
                                 y: overlayMinY,
                                 width: overlayWidth,
                                 height: max(0, overlayHeight))

        let dotSize: CGFloat = 6
        let spacingX: CGFloat = 10
        let spacingY: CGFloat = 12
        let cols = max(0, Int(overlayRect.width / (dotSize + spacingX)))
        let rows = max(0, Int(overlayRect.height / (dotSize + spacingY)))

        for r in 0..<rows {
            for c in 0..<cols {
                let circle = SKShapeNode(circleOfRadius: dotSize/2)
                let opacity: CGFloat = ((r + c) % 7 == 0) ? 0.9 : 0.35
                circle.fillColor = UIColor(white: 1.0, alpha: opacity)
                circle.strokeColor = .clear
                let x = overlayRect.minX + CGFloat(c) * (dotSize + spacingX) + dotSize
                let y = overlayRect.minY + CGFloat(r) * (dotSize + spacingY) + dotSize
                circle.position = CGPoint(x: x, y: y)
                circle.zPosition = 0
                dottedOverlayNode.addChild(circle)
            }
        }
        dottedOverlayNode.alpha = 0.25
    }

    private func buildFlower() {
        // "Logo" sprite
        flowerNode.removeAllChildren()
        flowerNode.zPosition = 13
        addChild(flowerNode)

        // Anchored the same distance from the bottom as the buttons and cube, so the gap
        // between each of them stays equal (see logoCenterY / signInCenterY / signUpCenterY).
        let center = CGPoint(x: size.width/2, y: logoCenterY)
        // Logo starts off the top of the screen and drops in (see fadeLogoThenButton)
        let startPosition = CGPoint(x: center.x, y: size.height + 160)

        // Load the logo texture
        let texture: SKTexture
        if let uiImage = UIImage(named: logoAssetName) {
            texture = SKTexture(image: uiImage)
        } else {
            let fallback = UIImage(systemName: "app.fill") ?? UIImage()
            texture = SKTexture(image: fallback)
        }

        let sprite = SKSpriteNode(texture: texture)
        sprite.name = "logo"
        sprite.size = CGSize(width: logoSize, height: logoSize)
        sprite.position = startPosition
        sprite.zPosition = 0
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        // Start hidden; we will fade in after background animation
        sprite.alpha = 0.0

        // Optional subtle shadow by duplicating with offset; start hidden until logo finishes
        let shadow = SKSpriteNode(texture: texture)
        shadow.size = sprite.size
        shadow.position = CGPoint(x: center.x + 4, y: center.y - 6)
        shadow.color = .black
        shadow.colorBlendFactor = 1.0
        shadow.alpha = 0.0   // hide shadow initially
        shadow.zPosition = -0.5

        flowerNode.addChild(shadow)
        flowerNode.addChild(sprite)
    }

    private func buildScallopedBottom() {
        scallopMaskNode.removeFromParent()
        scallopMaskNode.zPosition = 14

        let width = size.width
        let height: CGFloat = 18
        let diameter: CGFloat = 18
        let spacing: CGFloat = 8
        let total = Int((width + spacing) / (diameter + spacing))
        let y = height / 2

        // Even-odd path: full rect with circles appended (holes)
        let path = UIBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height))
        for i in 0..<total {
            let x = (CGFloat(i) * (diameter + spacing)) + diameter / 2
            let circle = UIBezierPath(ovalIn: CGRect(x: x - diameter/2, y: y - diameter/2, width: diameter, height: diameter))
            path.append(circle)
        }
        let shape = SKShapeNode(path: path.cgPath)
        shape.fillColor = .white
        shape.strokeColor = .clear
        shape.lineWidth = 0

        scallopMaskNode.addChild(shape)
        scallopMaskNode.position = CGPoint(x: 0, y: 0)
        addChild(scallopMaskNode)
    }

    // MARK: - Sign-in (static)

    private func buildBouncingSignIn() {
        // Static setup (no physics-driven animation)
        proxy.removeFromParent()
        floor.removeFromParent()

        let signupSize = buttonSize

        // Sign In — same white capsule style as Sign Up.
        let signinShadow = SKShapeNode(rectOf: signupSize, cornerRadius: signupSize.height / 2)
        signinShadow.name = buttonShadowName
        signinShadow.fillColor = UIColor.black.withAlphaComponent(0.18)
        signinShadow.strokeColor = .clear
        signinShadow.alpha = 0.0
        signinShadow.zPosition = 20.4
        addChild(signinShadow)

        let signinNode = SKNode()
        signinNode.name = signinNodeName
        signinNode.zPosition = 21
        signinNode.alpha = 0.0 // start hidden; fade in after background animation

        let signinCapsule = SKShapeNode(rectOf: signupSize, cornerRadius: signupSize.height / 2)
        signinCapsule.fillColor = .white
        signinCapsule.strokeColor = UIColor.black.withAlphaComponent(0.08)
        signinCapsule.lineWidth = 1.5
        signinCapsule.zPosition = 0
        signinNode.addChild(signinCapsule)

        let signinLabel = SKLabelNode(text: "Sign In")
        signinLabel.fontName = "AvenirNext-Heavy"
        signinLabel.fontSize = 22
        signinLabel.fontColor = .black
        signinLabel.verticalAlignmentMode = .center
        signinLabel.horizontalAlignmentMode = .center
        signinLabel.zPosition = 1
        signinNode.addChild(signinLabel)

        addChild(signinNode)
        let signupShadow = SKShapeNode(rectOf: signupSize, cornerRadius: signupSize.height / 2)
        signupShadow.name = signupShadowName
        signupShadow.fillColor = UIColor.black.withAlphaComponent(0.18)
        signupShadow.strokeColor = .clear
        signupShadow.alpha = 0.0
        signupShadow.zPosition = 20.4
        addChild(signupShadow)

        let signupNode = SKNode()
        signupNode.name = signupNodeName
        signupNode.zPosition = 21
        signupNode.alpha = 0.0

        let capsule = SKShapeNode(rectOf: signupSize, cornerRadius: signupSize.height / 2)
        capsule.fillColor = .white
        capsule.strokeColor = UIColor.black.withAlphaComponent(0.08)
        capsule.lineWidth = 1.5
        capsule.zPosition = 0
        signupNode.addChild(capsule)

        let label = SKLabelNode(text: "Sign Up")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 22
        label.fontColor = .black
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 1
        signupNode.addChild(label)

        addChild(signupNode)
    }

    private func layoutAll() {
        // Sign In sits above Sign Up, both anchored from the bottom (see signInCenterY /
        // signUpCenterY) so spacing to the logo above and the cube below stays equal.
        // Note: signinNode/signupNode are plain SKNode, not SKSpriteNode — casting to
        // SKSpriteNode here always failed silently, which is why Sign In never actually
        // moved off its default (0, 0) position. Position SKNode directly instead.
        let signinTarget = CGPoint(x: size.width / 2, y: signInCenterY)
        if let signinSprite = childNode(withName: signinNodeName) {
            signinSprite.position = signinTarget
        }
        if let shadowSprite = childNode(withName: buttonShadowName) {
            shadowSprite.position = CGPoint(x: signinTarget.x, y: signinTarget.y - 6)
        }
        let signupTarget = CGPoint(x: size.width / 2, y: signUpCenterY)
        if let signupNode = childNode(withName: signupNodeName) {
            signupNode.position = signupTarget
        }
        if let signupShadow = childNode(withName: signupShadowName) {
            signupShadow.position = CGPoint(x: signupTarget.x, y: signupTarget.y - 6)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
    }

    override func update(_ currentTime: TimeInterval) {
        if firstUpdateTime == nil {
            firstUpdateTime = currentTime
        }

        if !didWarmUp {
            let elapsed = (firstUpdateTime.map { currentTime - $0 } ?? 0)

            // Wait for both: a minimal warm-up AND the explicit delay (now zero)
            if warmUpFramesRemaining > 0 || elapsed < warmUpMinElapsed || elapsed < delayBeforeStart {
                if warmUpFramesRemaining > 0 { warmUpFramesRemaining -= 1 }
                return
            } else {
                didWarmUp = true
                if let bg = backgroundNode, !didAnimateBackground {
                    sizeAndPlaceBackground(bg, animateIfNeeded: true)
                    didAnimateBackground = true
                }
            }
        }
    }

    // Helper to create gradient texture (kept in case you need it elsewhere)
    private func gradientTexture(size: CGSize, colors: [UIColor], startPoint: CGPoint, endPoint: CGPoint) -> SKTexture {
        let layer = CAGradientLayer()
        layer.frame = CGRect(origin: .zero, size: size)
        layer.colors = colors.map { $0.cgColor }
        layer.startPoint = startPoint
        layer.endPoint = endPoint

        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else {
            return SKTexture()
        }
        layer.render(in: ctx)
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        return SKTexture(image: image)
    }

}

private final class AuthConfettiScene: SKScene {
    private var emitter: SKEmitterNode?

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.backgroundColor = .clear
        // Decorative background only — 60fps is plenty and halves GPU work vs. 120fps.
        view.preferredFramesPerSecond = 60
        startIfNeeded()
    }

    func resize(to newSize: CGSize) {
        size = newSize
        emitter?.position = CGPoint(x: newSize.width / 2, y: newSize.height + 40)
        emitter?.particlePositionRange = CGVector(dx: newSize.width + 400, dy: newSize.height * 2)
    }

    private func startIfNeeded() {
        guard emitter == nil else { return }
        let emitter = makeEmitter(size: size)
        emitter.zPosition = 1
        emitter.position = CGPoint(x: size.width / 2, y: size.height + 40)
        addChild(emitter)
        self.emitter = emitter
    }

    private func makeEmitter(size: CGSize) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        let colors: [UIColor] = [
            .systemPink, .systemOrange, .systemYellow,
            .systemGreen, .systemBlue, .systemPurple
        ]
        emitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: colors,
            times: (0..<colors.count).map { NSNumber(value: Float($0) / Float(max(colors.count - 1, 1))) }
        )
        emitter.particleColorBlendFactor = 1.0

        let confettiSize = CGSize(width: 18, height: 34)
        emitter.particleTexture = SKTexture(image: UIGraphicsImageRenderer(size: confettiSize).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: confettiSize))
        })

        emitter.particlePositionRange = CGVector(dx: size.width + 400, dy: 0)
        emitter.emissionAngle = -.pi / 2
        emitter.emissionAngleRange = .pi / 5
        emitter.particleSpeed = 220
        emitter.particleSpeedRange = 90
        emitter.yAcceleration = -65
        emitter.xAcceleration = 20
        // Light, continuous sprinkle rather than a dense storm — birthRate * lifetime is the
        // max number of particles alive at once (was 420 * 7.5 ≈ 3150; now ~40 * 4 ≈ 160),
        // which was the main source of lag on this screen.
        emitter.particleBirthRate = 45
        emitter.numParticlesToEmit = 0
        emitter.particleLifetime = 4.2
        emitter.particleLifetimeRange = 1.0
        emitter.particleRotationRange = .pi
        emitter.particleRotationSpeed = 2.5
        emitter.particleScale = 0.55
        emitter.particleScaleRange = 0.22
        emitter.particleScaleSpeed = -0.03
        emitter.particleAlpha = 1.0
        emitter.particleAlphaRange = 0.1
        emitter.particleAlphaSpeed = -0.05
        emitter.particleBlendMode = .alpha
        return emitter
    }
}

struct AuthConfettiBackground: View {
    @State private var scene: AuthConfettiScene?

    private func ensureScene(size: CGSize) -> AuthConfettiScene {
        if let scene { return scene }
        let newScene = AuthConfettiScene(size: size)
        scene = newScene
        return newScene
    }

    var body: some View {
        GeometryReader { geo in
            let scene = ensureScene(size: geo.size)
            SpriteView(scene: scene, options: [.allowsTransparency])
                .background(Color.clear)
                .ignoresSafeArea()
                .onChange(of: geo.size) { _, newSize in
                    scene.resize(to: newSize)
                }
        }
        .allowsHitTesting(false)
        .onDisappear {
            scene?.isPaused = true
            scene?.removeAllActions()
            scene?.removeAllChildren()
            scene = nil
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @StateObject private var coordinator = WelcomeScene.Coordinator()
    @EnvironmentObject private var stripeCoordinator: StripeTransitionCoordinator

    @State private var scene: WelcomeScene?
    @State private var cubeVisible = false
    @State private var authPanel: CarouselPanel = .welcome
    @State private var goingForward = true

    private enum CarouselPanel: Int {
        case welcome = 0, login = 1, signUp = 2
        var aiScreen: AuthAIScreen {
            switch self {
            case .welcome: return .welcome
            case .login:   return .login
            case .signUp:  return .signUp
            }
        }
    }

    private func ensureScene(size: CGSize) -> WelcomeScene {
        if let s = scene { return s }
        let s = WelcomeScene(size: size, coordinator: coordinator)
        scene = s
        return s
    }

    private func teardownScene() {
        scene?.isPaused = true
        scene?.removeAllActions()
        scene?.removeAllChildren()
        scene = nil
    }

    private func navigate(to panel: CarouselPanel) {
        goingForward = panel.rawValue > authPanel.rawValue
        withAnimation(.easeInOut(duration: 0.38)) {
            authPanel = panel
        }
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            // Welcome scene — stays in hierarchy; opacity and hit-testing controlled so it never
            // gets recreated during carousel transitions (which would restart the animations).
            GeometryReader { geo in
                let s = ensureScene(size: geo.size)
                Group {
                    if isRunningInPreviews {
                        Color.white.overlay(Text("Welcome Preview").font(.headline))
                    } else {
                        SpriteView(scene: s)
                    }
                }
                .background(Color.white)
                .ignoresSafeArea()
                .onChange(of: geo.size) { _, newSize in s.resize(to: newSize) }
            }
            .opacity(authPanel == .welcome ? 1 : 0)
            .allowsHitTesting(authPanel == .welcome)

            // Shared confetti — one instance for the entire auth flow; never restarted.
            AuthConfettiBackground()

            // Decorative cube — only shown on the welcome panel; login/signup have their own
            // interactive back-button cube and must not be obscured by this decoration.
            if authPanel == .welcome {
                VStack {
                    Spacer()
                    LoginCubeView()
                        .frame(width: 200, height: 200)
                        .scaleEffect(cubeVisible ? 1 : 0.3)
                        .opacity(cubeVisible ? 1 : 0)
                        .padding(.bottom, 8)
                }
                .allowsHitTesting(false)
            }

            // Single AI guide instance — screen switches with panel; .id() forces a fresh
            // greeting (new VM) each time a new panel appears.
            AuthAIGuide(screen: authPanel.aiScreen)
                .id(authPanel)

            // Login panel — slides in from the right on forward navigation
            if authPanel == .login {
                LoginView(
                    isCarousel: true,
                    onBack: { navigate(to: .welcome) },
                    onGoToSignUp: { navigate(to: .signUp) }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: goingForward ? .trailing : .leading),
                    removal:   .move(edge: goingForward ? .leading  : .trailing)
                ))
                .zIndex(goingForward ? 1 : 2)
            }

            // Sign Up panel — slides in from the right on forward navigation
            if authPanel == .signUp {
                SignUpView(
                    isCarousel: true,
                    onBack: { navigate(to: .login) }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: goingForward ? .trailing : .leading),
                    removal:   .move(edge: goingForward ? .leading  : .trailing)
                ))
                .zIndex(goingForward ? 2 : 1)
            }
        }
        .onReceive(coordinator.$didTapSignIn) { tapped in
            if tapped {
                coordinator.didTapSignIn = false
                navigate(to: .login)
            }
        }
        .onReceive(coordinator.$didTapSignUp) { tapped in
            if tapped {
                coordinator.didTapSignUp = false
                navigate(to: .signUp)
            }
        }
        .onAppear {
            cubeVisible = false
            withAnimation(.spring(response: 0.6, dampingFraction: 0.62).delay(1.9)) {
                cubeVisible = true
            }
        }
        .onChange(of: auth.isAuthenticated) { _, authed in
            if authed {
                authPanel = .welcome
                teardownScene()
            }
        }
        .onDisappear { teardownScene() }
    }
}
