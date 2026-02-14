import SwiftUI
import SpriteKit
import CoreGraphics
import UIKit
import CoreImage

private final class WelcomeScene: SKScene {

    // Coordinator to communicate with SwiftUI
    final class Coordinator: ObservableObject {
        @Published var didTapSignIn = false
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

    // Layout constants (SpriteKit points)
    private let floorY: CGFloat = 24
    private let bounceAreaHeight: CGFloat = 180

    // Asset names
    private let backgroundAssetNames = ["slideup", "slideup_alt1", "slideup_alt2"]
    private let defaultBackgroundName = "slideup"
    private let logoAssetName = "logo"
    private let signinAssetName = "signin"

    // Vertical offset to place the button relative to center (negative moves up, positive down)
    private let buttonVerticalOffset: CGFloat = -120

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
        let warmUp = SKAction.sequence([
            .wait(forDuration: 0.05),
            .playSoundFileNamed("pop", waitForCompletion: false)
        ])
        run(warmUp, withKey: "warmUpPopSound")
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

            // Drop + settle
            let dropDuration: TimeInterval = 0.65
            let settleDuration: TimeInterval = 0.20
            let overshoot: CGFloat = 14

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
        let logoFadeDuration: TimeInterval = 0.35
        let buttonFadeDuration: TimeInterval = 0.35

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

            // After logo completes, reveal the logo shadow, then start button fade
            let sequence = SKAction.sequence([
                jumpToHalf,
                fadeToFull,
                SKAction.run { [weak self] in
                    // Reveal the logo shadow now
                    if let self, let shadow = self.flowerNode.children.first(where: { $0 !== logo && $0 is SKSpriteNode }) as? SKSpriteNode {
                        shadow.alpha = 0.2
                    }
                    self?.fadeButton(duration: buttonFadeDuration)
                    // Start floating the logo after it is fully visible
                    if let logo = self?.flowerNode.childNode(withName: "logo") as? SKSpriteNode {
                        self?.startFloating(node: logo, amplitude: 10, period: 2.6, phaseOffset: 0.0)
                    }
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

        if let signinSprite = childNode(withName: signinNodeName) as? SKSpriteNode {
            signinSprite.removeAllActions()
            signinSprite.alpha = 0.0
            let sequence = SKAction.sequence([
                fade,
                SKAction.run { [weak self, weak signinSprite] in
                    // Begin floating after it’s visible; slight phase so it’s not perfectly synced with logo
                    if let node = signinSprite {
                        self?.startFloating(node: node, amplitude: 8, period: 2.4, phaseOffset: 0.5)
                    }
                }
            ])
            signinSprite.run(sequence, withKey: "buttonFade")
        }

        if let shadowSprite = childNode(withName: buttonShadowName) as? SKSpriteNode {
            shadowSprite.removeAllActions()
            shadowSprite.alpha = 0.0
            shadowSprite.run(fade, withKey: "buttonShadowFade")
        }

        // After button fade finishes: play pop sound, then spawn confetti
        let playPopThenConfetti = SKAction.sequence([
            .wait(forDuration: duration),
            .playSoundFileNamed("pop", waitForCompletion: false),
            .run { [weak self] in
                guard let self else { return }
                let emitter = self.makeConfettiEmitter(size: self.size)
                emitter.zPosition = 200 // above UI
                emitter.position = CGPoint(x: self.size.width / 2, y: self.size.height + 40) // slightly above top
                self.addChild(emitter)

                // Let it run for >= 5 seconds, then stop birth and remove after particles dissipate
                let birthWindow: TimeInterval = 5.5
                let cleanup = SKAction.sequence([
                    .wait(forDuration: birthWindow),
                    .run { emitter.particleBirthRate = 0 },
                    .wait(forDuration: 3.0), // allow remaining particles to fall out
                    .removeFromParent()
                ])
                emitter.run(cleanup)
            }
        ])
        self.run(playPopThenConfetti, withKey: "popThenConfetti")
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

    // Handle taps on the sign-in button to trigger navigation
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        if let signinSprite = childNode(withName: signinNodeName) as? SKSpriteNode,
           signinSprite.contains(location) {
            // Simple tap feedback
            let pulseDown = SKAction.scale(to: 0.96, duration: 0.06)
            let pulseUp = SKAction.scale(to: 1.0, duration: 0.08)
            pulseDown.timingMode = .easeOut
            pulseUp.timingMode = .easeInEaseOut
            signinSprite.run(.sequence([pulseDown, pulseUp]))

            // Notify SwiftUI to navigate
            coordinator.didTapSignIn = true
        }
    }

    // Create a confetti emitter that spans the top of the screen and falls down
    private func makeConfettiEmitter(size: CGSize) -> SKEmitterNode {
        let emitter = SKEmitterNode()

        // Colors
        let colors: [UIColor] = [
            .systemPink, .systemOrange, .systemYellow,
            .systemGreen, .systemBlue, .systemPurple
        ]
        let seq = SKKeyframeSequence(
            keyframeValues: colors,
            times: (0..<colors.count).map { NSNumber(value: Float($0) / Float(max(colors.count - 1, 1))) }
        )
        emitter.particleColorSequence = seq
        emitter.particleColorBlendFactor = 1.0

        // Confetti texture (rectangle) — visible size
        let confettiSize = CGSize(width: 8, height: 15)
        emitter.particleTexture = SKTexture(image: UIGraphicsImageRenderer(size: confettiSize).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: confettiSize))
        })

        // Position at (set by caller), span full width plus margin and a small vertical band
        emitter.particlePositionRange = CGVector(dx: size.width + 400, dy: size.height * 2)

        // Emit downward
        emitter.emissionAngle = -.pi / 2         // straight down
        emitter.emissionAngleRange = .pi / 6     // +/- 30 degrees spread

        // Motion: initial downward speed plus downward acceleration for fall
        emitter.particleSpeed = 120
        emitter.particleSpeedRange = 80
        emitter.yAcceleration = 200              // positive pulls downward
        emitter.xAcceleration = 25

        // Lifetime and rate (ensure reach bottom on tall screens and visible >= 5s)
        emitter.particleBirthRate = 420          // denser to "fill" the screen
        emitter.numParticlesToEmit = 0           // continuous; we'll stop later
        emitter.particleLifetime = 7.5
        emitter.particleLifetimeRange = 1.5

        // Spin/scale/alpha
        emitter.particleRotationRange = .pi
        emitter.particleRotationSpeed = 3.0
        emitter.particleScale = 1.0
        emitter.particleScaleRange = 0.5
        emitter.particleScaleSpeed = -0.06
        emitter.particleAlpha = 1.0
        emitter.particleAlphaRange = 0.1
        emitter.particleAlphaSpeed = -0.05
        emitter.particleBlendMode = .alpha

        // Optional: immediate one-shot burst for visibility
        let burst = SKEmitterNode()
        burst.particleTexture = emitter.particleTexture
        burst.particleColorSequence = emitter.particleColorSequence
        burst.particleColorBlendFactor = 1.0
        burst.position = .zero // local to emitter; inherits emitter's world position
        burst.particlePositionRange = emitter.particlePositionRange
        burst.emissionAngle = emitter.emissionAngle
        burst.emissionAngleRange = emitter.emissionAngleRange
        burst.particleBirthRate = 0
        burst.numParticlesToEmit = 220
        burst.particleLifetime = 6.5
        burst.particleLifetimeRange = 1.0
        burst.particleSpeed = 160
        burst.particleSpeedRange = 100
        burst.yAcceleration = 200
        burst.xAcceleration = 25
        burst.particleRotationRange = .pi
        burst.particleRotationSpeed = 3.0
        burst.particleScale = 1.0
        burst.particleScaleRange = 0.5
        burst.particleScaleSpeed = -0.06
        burst.particleAlpha = 1.0
        burst.particleAlphaRange = 0.1
        burst.particleAlphaSpeed = -0.05
        burst.particleBlendMode = .alpha

        emitter.addChild(burst)

        // Auto-stop and cleanup for burst
        let removeBurst = SKAction.sequence([
            .wait(forDuration: 0.05),
            .run { burst.particleBirthRate = 0 },
            .wait(forDuration: 7.0),
            .removeFromParent()
        ])
        emitter.run(removeBurst)

        return emitter
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

        // Position somewhere near the top; adjust as desired
        let center = CGPoint(x: size.width/2, y: size.height - 240)

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
        sprite.size = CGSize(width: 200, height: 200)
        sprite.position = center
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

        // Create the sign-in sprite from assets
        let texture: SKTexture
        let baseSize: CGSize
        if let uiImage = UIImage(named: signinAssetName) {
            texture = SKTexture(image: uiImage)
            baseSize = uiImage.size // points
        } else {
            let fallback = UIImage(systemName: "rectangle.and.hand.point.up.left.fill") ?? UIImage()
            texture = SKTexture(image: fallback)
            baseSize = fallback.size
        }

        // Compute size preserving aspect ratio with a max width
        let maxWidth: CGFloat = 220 // adjust to taste
        let scale = min(1.0, maxWidth / max(baseSize.width, 1))
        let finalSize = CGSize(width: baseSize.width * scale, height: baseSize.height * scale)

        // Visible sign-in sprite (static)
        let signinSprite = SKSpriteNode(texture: texture)
        signinSprite.name = signinNodeName
        signinSprite.size = finalSize
        signinSprite.zPosition = 21
        signinSprite.alpha = 0.0 // start hidden; fade in after background animation
        addChild(signinSprite)

        // Optional soft shadow sprite
        let shadowSprite = SKSpriteNode(texture: texture)
        shadowSprite.name = buttonShadowName
        shadowSprite.size = finalSize
        shadowSprite.color = .black
        shadowSprite.colorBlendFactor = 1.0
        shadowSprite.alpha = 0.0 // start hidden together with button
        shadowSprite.zPosition = 20.5
        addChild(shadowSprite)
    }

    private func layoutAll() {
        // Fixed baseline position for sign-in (no animation)
        let midY = size.height / 2 + buttonVerticalOffset
        let target = CGPoint(x: size.width/2, y: midY)

        if let signinSprite = childNode(withName: signinNodeName) as? SKSpriteNode {
            signinSprite.position = target
        }
        if let shadowSprite = childNode(withName: buttonShadowName) as? SKSpriteNode {
            shadowSprite.position = CGPoint(x: target.x, y: target.y - 6)
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

    // MARK: - Public: confetti replay on demand
    func startConfettiNow() {
        // Play the pop sound (optional) and spawn a new confetti emitter immediately.
        let playPop = SKAction.playSoundFileNamed("pop", waitForCompletion: false)
        self.run(playPop)

        let emitter = self.makeConfettiEmitter(size: self.size)
        emitter.zPosition = 200
        emitter.position = CGPoint(x: self.size.width / 2, y: self.size.height + 40)
        self.addChild(emitter)

        // Same lifecycle as before: run for ~5.5s, then stop birth and remove after particles dissipate.
        let birthWindow: TimeInterval = 5.5
        let cleanup = SKAction.sequence([
            .wait(forDuration: birthWindow),
            .run { emitter.particleBirthRate = 0 },
            .wait(forDuration: 3.0),
            .removeFromParent()
        ])
        emitter.run(cleanup)
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @StateObject private var coordinator = WelcomeScene.Coordinator()

    // Persist the scene to avoid rebuilds during early layout changes
    @State private var scene: WelcomeScene?

    @State private var navigateToLogin = false

    private func ensureScene(size: CGSize) -> WelcomeScene {
        if let s = scene { return s }
        let s = WelcomeScene(size: size, coordinator: coordinator)
        scene = s
        return s
    }

    private func teardownScene() {
        // Pause and release the SpriteKit scene to avoid any CAMetalLayer churn
        scene?.isPaused = true
        scene?.removeAllActions()
        scene?.removeAllChildren()
        scene = nil
    }

    var body: some View {
        NavigationStack {
            NavigationLink(isActive: $navigateToLogin) {
                LoginView()
            } label: { EmptyView() }
            .hidden()

            ZStack {
                GeometryReader { geo in
                    let s = ensureScene(size: geo.size)
                    SpriteView(scene: s)
                        .background(Color.white)
                        .ignoresSafeArea()
                        .onChange(of: geo.size) { newSize in
                            // Inform scene about size changes without recreating it
                            s.resize(to: newSize)
                        }
                }
            }
            .onReceive(coordinator.$didTapSignIn) { tapped in
                if tapped {
                    navigateToLogin = true
                    coordinator.didTapSignIn = false
                }
            }
            .onAppear {
                // Only replay confetti when WelcomeView appears again. Do not replay the intro.
                scene?.startConfettiNow()
            }
            .onChange(of: auth.isAuthenticated) { authed in
                if authed {
                    // Proactively tear down the SpriteKit scene before the root swaps to HomeView.
                    navigateToLogin = false
                    teardownScene()
                }
            }
            .onDisappear {
                // Defensive: if WelcomeView disappears for any reason, release the scene.
                teardownScene()
            }
            .navigationBarHidden(true)
        }
    }
}
