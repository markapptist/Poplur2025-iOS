import SwiftUI
import SpriteKit
import CoreGraphics
import UIKit
import CoreImage

extension Notification.Name {
    static let poplurWelcomePanelVisibilityChanged = Notification.Name("poplurWelcomePanelVisibilityChanged")
}

private var isRunningInPreviews: Bool {
    let env = ProcessInfo.processInfo.environment
    return env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || env["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
}

private final class WelcomeScene: SKScene {

    private let welcomePink = UIColor(red: 1, green: 45.0 / 255.0, blue: 150.0 / 255.0, alpha: 1)

    // Coordinator to communicate with SwiftUI
    final class Coordinator: ObservableObject {
        @Published var didTapSignIn = false
        @Published var didTapSignUp = false
    }

    let coordinator: Coordinator

    // Nodes
    private let worldMapNode = SKNode()
    private let flowerNode = SKNode()
    private let floor = SKNode()
    private var backgroundNode: SKSpriteNode?
    private var didAnimateBackground = false
    private var reduceMotion: Bool

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
    // The primary ticket and sparkle alternate are shared with Android's
    // launch-cover artwork, so both platforms open with the same Poplur world.
    private let backgroundAssetNames = ["slideup_alt1"]
    private let defaultBackgroundName = "slideup_alt1"
    private let logoAssetName = "logo"

    // Approved Welcome composition, normalized from the 390 × 845 Good Copy reference:
    // logo at y=155, cube at y=350, and Sign Up at y=635 (from the top). Sign In is
    // derived from Sign Up so the canonical 28pt inter-button gap stays exact on iPhone
    // and iPad instead of stretching with screen height.
    private let buttonSize = CGSize(width: 220, height: 52)
    private let buttonGap: CGFloat = 28
    private let logoSize: CGFloat = 140

    private var signUpCenterY: CGFloat {
        size.height * (1 - 635.0 / 845.0)
    }
    private var signInCenterY: CGFloat {
        signUpCenterY + buttonSize.height + buttonGap
    }
    private var logoCenterY: CGFloat {
        size.height * (1 - 155.0 / 845.0)
    }

    // Track size during animation to avoid size churn
    private var isAnimatingBackground = false
    private var lockedBackgroundSize: CGSize?

    init(size: CGSize, coordinator: Coordinator, reduceMotion: Bool) {
        self.coordinator = coordinator
        self.reduceMotion = reduceMotion
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = welcomePink

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
        buildWorldMapOverlay()
        buildFlower()
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

        // Keep the phone-ratio pink artwork proportional. It covers the viewport and
        // center-crops on wider iPad layouts instead of stretching horizontally.
        let sceneSize = size
        let preSize = ticketSize(for: sceneSize, texture: texture)
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
        let finalPosition = ticketCenter(for: sceneSize)
        let startY = sceneSize.height + (preSize.height / 2) + 40
        bg.position = CGPoint(x: finalPosition.x, y: startY)

        // Fade-in over a couple frames to ensure texture is resident
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.12)
        fadeIn.timingMode = .easeOut
        bg.run(fadeIn)
    }

    private func sizeAndPlaceBackground(_ bg: SKSpriteNode, animateIfNeeded: Bool) {
        let sceneSize = size
        let idealSize = ticketSize(for: sceneSize, texture: bg.texture)

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

        let finalPosition = ticketCenter(for: sceneSize)

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

    private func ticketSize(for sceneSize: CGSize, texture: SKTexture?) -> CGSize {
        let sceneSize = CGSize(width: max(sceneSize.width, 1), height: max(sceneSize.height, 1))
        guard let texture else { return sceneSize }
        let textureSize = texture.size()
        guard textureSize.width > 0, textureSize.height > 0 else { return sceneSize }

        let sceneAspect = sceneSize.width / sceneSize.height
        let textureAspect = textureSize.width / textureSize.height
        if textureAspect > sceneAspect {
            return CGSize(width: sceneSize.height * textureAspect, height: sceneSize.height)
        }
        return CGSize(width: sceneSize.width, height: sceneSize.width / textureAspect)
    }

    private func ticketCenter(for sceneSize: CGSize) -> CGPoint {
        CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
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
        buildWorldMapOverlay()
        layoutAll()
    }

    func setReduceMotion(_ enabled: Bool) {
        guard reduceMotion != enabled else { return }
        reduceMotion = enabled
        buildWorldMapOverlay()
    }

    // MARK: - Foreground Nodes

    /// A portrait-filling dotted world map in normalized, top-origin coordinates.
    /// The polygons intentionally span almost the entire canvas so the map remains
    /// recognizable behind the Welcome foreground on both iPhone and iPad.
    private static let normalizedContinents: [[CGPoint]] = [
        // North America
        [CGPoint(x: 0.02, y: 0.20), CGPoint(x: 0.06, y: 0.12),
         CGPoint(x: 0.13, y: 0.07), CGPoint(x: 0.20, y: 0.10),
         CGPoint(x: 0.25, y: 0.16), CGPoint(x: 0.31, y: 0.15),
         CGPoint(x: 0.34, y: 0.22), CGPoint(x: 0.29, y: 0.28),
         CGPoint(x: 0.25, y: 0.30), CGPoint(x: 0.22, y: 0.38),
         CGPoint(x: 0.17, y: 0.43), CGPoint(x: 0.13, y: 0.37),
         CGPoint(x: 0.09, y: 0.33), CGPoint(x: 0.04, y: 0.29)],
        // Greenland
        [CGPoint(x: 0.27, y: 0.04), CGPoint(x: 0.34, y: 0.05),
         CGPoint(x: 0.37, y: 0.12), CGPoint(x: 0.33, y: 0.18),
         CGPoint(x: 0.28, y: 0.14)],
        // South America
        [CGPoint(x: 0.17, y: 0.42), CGPoint(x: 0.23, y: 0.39),
         CGPoint(x: 0.29, y: 0.44), CGPoint(x: 0.31, y: 0.51),
         CGPoint(x: 0.29, y: 0.59), CGPoint(x: 0.28, y: 0.68),
         CGPoint(x: 0.25, y: 0.78), CGPoint(x: 0.21, y: 0.87),
         CGPoint(x: 0.19, y: 0.77), CGPoint(x: 0.17, y: 0.67),
         CGPoint(x: 0.16, y: 0.56), CGPoint(x: 0.14, y: 0.48)],
        // Europe
        [CGPoint(x: 0.42, y: 0.23), CGPoint(x: 0.46, y: 0.18),
         CGPoint(x: 0.51, y: 0.18), CGPoint(x: 0.56, y: 0.22),
         CGPoint(x: 0.54, y: 0.28), CGPoint(x: 0.49, y: 0.30),
         CGPoint(x: 0.44, y: 0.28)],
        // Africa
        [CGPoint(x: 0.42, y: 0.32), CGPoint(x: 0.49, y: 0.29),
         CGPoint(x: 0.56, y: 0.33), CGPoint(x: 0.59, y: 0.42),
         CGPoint(x: 0.56, y: 0.53), CGPoint(x: 0.53, y: 0.63),
         CGPoint(x: 0.49, y: 0.70), CGPoint(x: 0.45, y: 0.62),
         CGPoint(x: 0.42, y: 0.52), CGPoint(x: 0.39, y: 0.41)],
        // Asia
        [CGPoint(x: 0.52, y: 0.18), CGPoint(x: 0.61, y: 0.11),
         CGPoint(x: 0.71, y: 0.08), CGPoint(x: 0.82, y: 0.11),
         CGPoint(x: 0.91, y: 0.17), CGPoint(x: 0.98, y: 0.27),
         CGPoint(x: 0.95, y: 0.35), CGPoint(x: 0.87, y: 0.39),
         CGPoint(x: 0.82, y: 0.45), CGPoint(x: 0.75, y: 0.41),
         CGPoint(x: 0.69, y: 0.36), CGPoint(x: 0.62, y: 0.35),
         CGPoint(x: 0.57, y: 0.29), CGPoint(x: 0.53, y: 0.26)],
        // South-east Asia
        [CGPoint(x: 0.67, y: 0.40), CGPoint(x: 0.74, y: 0.42),
         CGPoint(x: 0.81, y: 0.47), CGPoint(x: 0.85, y: 0.54),
         CGPoint(x: 0.81, y: 0.59), CGPoint(x: 0.75, y: 0.54),
         CGPoint(x: 0.70, y: 0.51), CGPoint(x: 0.66, y: 0.46)],
        // Australia
        [CGPoint(x: 0.76, y: 0.65), CGPoint(x: 0.83, y: 0.61),
         CGPoint(x: 0.91, y: 0.64), CGPoint(x: 0.96, y: 0.71),
         CGPoint(x: 0.92, y: 0.80), CGPoint(x: 0.85, y: 0.83),
         CGPoint(x: 0.78, y: 0.77)],
        // Japan
        [CGPoint(x: 0.89, y: 0.29), CGPoint(x: 0.91, y: 0.26),
         CGPoint(x: 0.93, y: 0.34), CGPoint(x: 0.90, y: 0.39)],
        // Madagascar
        [CGPoint(x: 0.58, y: 0.62), CGPoint(x: 0.60, y: 0.59),
         CGPoint(x: 0.62, y: 0.70), CGPoint(x: 0.59, y: 0.77)],
    ]

    private func buildWorldMapOverlay() {
        guard size.width > 1, size.height > 1 else { return }

        worldMapNode.removeFromParent()
        worldMapNode.removeAllActions()
        worldMapNode.removeAllChildren()
        worldMapNode.zPosition = -90
        addChild(worldMapNode)

        // One path renders every muted land dot. Only the sparse bright subset gets
        // individual nodes, keeping the continuously animated node count modest.
        let spacing = min(max(size.width / 42, 8), 15)
        let radius = min(max(spacing * 0.22, 1.7), 3.1)
        let columns = Int(ceil(size.width / spacing))
        let rows = Int(ceil(size.height / spacing))
        let basePath = CGMutablePath()
        let highlights = SKNode()
        highlights.name = "worldMapHighlights"
        highlights.zPosition = 1

        for row in 0...rows {
            let topY = CGFloat(row) * spacing
            let normalizedY = topY / size.height
            guard normalizedY >= 0.04, normalizedY <= 0.91 else { continue }

            for column in 0...columns {
                let x = CGFloat(column) * spacing
                let normalizedPoint = CGPoint(x: x / size.width, y: normalizedY)
                guard Self.normalizedContinents.contains(where: {
                    Self.contains(normalizedPoint, in: $0)
                }) else { continue }

                let scenePoint = CGPoint(x: x, y: size.height - topY)
                basePath.addEllipse(in: CGRect(
                    x: scenePoint.x - radius,
                    y: scenePoint.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))

                let highlightHash = (row * 73 + column * 151 + row * column * 19) % 41
                guard highlightHash < 4 else { continue }

                let dot = SKShapeNode(circleOfRadius: radius * 1.12)
                dot.position = scenePoint
                dot.fillColor = .white
                dot.strokeColor = .clear
                dot.glowWidth = radius * 1.2
                dot.blendMode = .add
                dot.zPosition = 1
                highlights.addChild(dot)
                configureBlink(for: dot, row: row, column: column)
            }
        }

        let baseDots = SKShapeNode(path: basePath)
        baseDots.name = "worldMapBaseDots"
        baseDots.fillColor = UIColor(white: 1, alpha: 0.28)
        baseDots.strokeColor = .clear
        baseDots.lineWidth = 0
        baseDots.zPosition = 0
        worldMapNode.addChild(baseDots)
        worldMapNode.addChild(highlights)
    }

    private func configureBlink(for dot: SKShapeNode, row: Int, column: Int) {
        dot.removeAllActions()
        dot.setScale(1)

        guard !reduceMotion else {
            dot.alpha = 0.95
            return
        }

        let phaseSeed = (row * 37 + column * 97 + row * column * 11) % 100
        let periodSeed = (row * 29 + column * 43 + row * column * 7) % 70
        let phase = Double(phaseSeed) / 100 * 1.6
        let rest = 0.55 + Double(periodSeed) / 100
        dot.alpha = 0.42

        let brighten = SKAction.group([
            .fadeAlpha(to: 1, duration: 0.34),
            .scale(to: 1.16, duration: 0.34),
        ])
        brighten.timingMode = .easeInEaseOut
        let dim = SKAction.group([
            .fadeAlpha(to: 0.36, duration: 0.48),
            .scale(to: 0.94, duration: 0.48),
        ])
        dim.timingMode = .easeInEaseOut
        let pulse = SKAction.sequence([
            brighten,
            .wait(forDuration: 0.20),
            dim,
            .wait(forDuration: rest),
        ])
        dot.run(.sequence([
            .wait(forDuration: phase),
            .repeatForever(pulse),
        ]), withKey: "worldMapBlink")
    }

    private static func contains(_ point: CGPoint, in polygon: [CGPoint]) -> Bool {
        guard polygon.count > 2 else { return false }
        var isInside = false
        var previous = polygon.count - 1

        for current in polygon.indices {
            let a = polygon[current]
            let b = polygon[previous]
            if (a.y > point.y) != (b.y > point.y) {
                let intersectionX = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
                if point.x < intersectionX { isInside.toggle() }
            }
            previous = current
        }
        return isInside
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

    // MARK: - Sign-in (static)

    private func buildBouncingSignIn() {
        // Static setup (no physics-driven animation)
        proxy.removeFromParent()
        floor.removeFromParent()

        let signupSize = buttonSize
        let surfaceTexture = buttonSurfaceTexture(size: signupSize)

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

        let signinCapsule = SKSpriteNode(texture: surfaceTexture, size: signupSize)
        signinCapsule.zPosition = 0
        signinNode.addChild(signinCapsule)

        signinNode.addChild(makeButtonLabel("Sign In"))

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

        let capsule = SKSpriteNode(texture: surfaceTexture, size: signupSize)
        capsule.zPosition = 0
        signupNode.addChild(capsule)

        signupNode.addChild(makeButtonLabel("Sign Up"))

        addChild(signupNode)
    }

    private func makeButtonLabel(_ text: String) -> SKNode {
        let container = SKNode()
        let font = UIFont(name: "AvenirNext-Heavy", size: 22)
            ?? UIFont.systemFont(ofSize: 22, weight: .heavy)

        let shadow = SKLabelNode(text: text)
        shadow.fontName = font.fontName
        shadow.fontSize = 22
        shadow.fontColor = UIColor.black.withAlphaComponent(0.16)
        shadow.verticalAlignmentMode = .center
        shadow.horizontalAlignmentMode = .center
        shadow.position.y = -1
        shadow.zPosition = 0
        container.addChild(shadow)

        let mask = SKLabelNode(text: text)
        mask.fontName = font.fontName
        mask.fontSize = 22
        mask.fontColor = .white
        mask.verticalAlignmentMode = .center
        mask.horizontalAlignmentMode = .center

        let crop = SKCropNode()
        crop.maskNode = mask
        crop.zPosition = 1

        let maskFrame = mask.calculateAccumulatedFrame()
        let fillSize = CGSize(
            width: max(1, ceil(maskFrame.width)),
            height: max(1, ceil(maskFrame.height))
        )
        let shaderFill = SKSpriteNode(color: .white, size: fillSize)
        shaderFill.shader = makeButtonTextShader(
            aspectRatio: fillSize.height / fillSize.width
        )
        crop.addChild(shaderFill)
        container.addChild(crop)

        return container
    }

    private func makeButtonTextShader(aspectRatio: CGFloat) -> SKShader {
        let source = """
        void main() {
            // Static approved shader pose: 105deg gradient at the canonical 48%
            // background position. There is deliberately no time-based uniform.
            float phase = 0.48 * (2.0 / 3.0);
            float axis = v_tex_coord.x * 0.965926
                       + (v_tex_coord.y - 0.5) * u_aspect * 0.258819;
            float x = fract(axis / 3.0 + phase);
            vec3 color;

            if (x < 0.16) {
                color = mix(vec3(0.031, 0.008, 0.027), vec3(0.357, 0.071, 0.220), x / 0.16);
            } else if (x < 0.31) {
                color = mix(vec3(0.357, 0.071, 0.220), vec3(1.000, 0.176, 0.541), (x - 0.16) / 0.15);
            } else if (x < 0.45) {
                color = mix(vec3(1.000, 0.176, 0.541), vec3(0.478, 0.000, 0.243), (x - 0.31) / 0.14);
            } else if (x < 0.59) {
                color = mix(vec3(0.478, 0.000, 0.243), vec3(0.086, 0.027, 0.067), (x - 0.45) / 0.14);
            } else if (x < 0.76) {
                color = mix(vec3(0.086, 0.027, 0.067), vec3(1.000, 0.302, 0.620), (x - 0.59) / 0.17);
            } else if (x < 0.90) {
                color = mix(vec3(1.000, 0.302, 0.620), vec3(0.165, 0.039, 0.114), (x - 0.76) / 0.14);
            } else {
                color = mix(vec3(0.165, 0.039, 0.114), vec3(0.031, 0.008, 0.027), (x - 0.90) / 0.10);
            }

            gl_FragColor = vec4(color, 1.0);
        }
        """
        let shader = SKShader(source: source)
        shader.addUniform(
            SKUniform(name: "u_aspect", float: Float(aspectRatio))
        )
        return shader
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

    private func buttonSurfaceTexture(size: CGSize) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false

        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            let insetRect = rect.insetBy(dx: 0.75, dy: 0.75)
            let radius = insetRect.height / 2
            let capsule = UIBezierPath(roundedRect: insetRect, cornerRadius: radius)

            cg.saveGState()
            capsule.addClip()

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let baseColors = [
                UIColor.white.cgColor,
                UIColor(red: 1.0, green: 0.94, blue: 0.98, alpha: 1.0).cgColor,
                UIColor(red: 0.88, green: 0.88, blue: 0.92, alpha: 1.0).cgColor,
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: baseColors,
                locations: [0.0, 0.54, 1.0]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: size.width * 0.22, y: 0),
                    end: CGPoint(x: size.width * 0.82, y: size.height),
                    options: []
                )
            }

            let sheenColors = [
                UIColor.white.withAlphaComponent(0.64).cgColor,
                UIColor.white.withAlphaComponent(0.0).cgColor,
            ] as CFArray
            if let sheen = CGGradient(
                colorsSpace: colorSpace,
                colors: sheenColors,
                locations: [0.0, 1.0]
            ) {
                cg.drawLinearGradient(
                    sheen,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width * 0.72, y: size.height * 0.72),
                    options: []
                )
            }

            let bottomShadeColors = [
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.11).cgColor,
            ] as CFArray
            if let bottomShade = CGGradient(
                colorsSpace: colorSpace,
                colors: bottomShadeColors,
                locations: [0.45, 1.0]
            ) {
                cg.drawLinearGradient(
                    bottomShade,
                    start: CGPoint(x: size.width / 2, y: 0),
                    end: CGPoint(x: size.width / 2, y: size.height),
                    options: []
                )
            }

            cg.restoreGState()

            UIColor.white.withAlphaComponent(0.58).setStroke()
            let highlight = UIBezierPath(
                roundedRect: insetRect.insetBy(dx: 8, dy: 6),
                cornerRadius: max(0, radius - 6)
            )
            highlight.lineWidth = 1
            highlight.stroke()

            UIColor.black.withAlphaComponent(0.10).setStroke()
            capsule.lineWidth = 1.5
            capsule.stroke()
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        let s = WelcomeScene(
            size: size,
            coordinator: coordinator,
            reduceMotion: reduceMotion
        )
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
                .background(Color(red: 1, green: 45.0 / 255.0, blue: 150.0 / 255.0))
                .ignoresSafeArea()
                .onChange(of: geo.size) { _, newSize in s.resize(to: newSize) }
                .onChange(of: reduceMotion) { _, enabled in
                    s.setReduceMotion(enabled)
                }
            }
            .opacity(authPanel == .welcome ? 1 : 0)
            .allowsHitTesting(authPanel == .welcome)

            // Shared confetti — one instance for the entire auth flow; never restarted.
            AuthConfettiBackground()

            // Decorative cube — only shown on the welcome panel; login/signup have their own
            // interactive back-button cube and must not be obscured by this decoration.
            if authPanel == .welcome {
                GeometryReader { geo in
                    LoginCubeView(face: .forward)
                        .frame(width: 128, height: 128)
                        .scaleEffect(cubeVisible ? 1 : 0.3)
                        .opacity(cubeVisible ? 1 : 0)
                        .position(
                            x: geo.size.width / 2,
                            y: geo.size.height * (350.0 / 845.0)
                        )
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
            NotificationCenter.default.post(
                name: .poplurWelcomePanelVisibilityChanged,
                object: authPanel == .welcome
            )
            cubeVisible = false
            withAnimation(.spring(response: 0.6, dampingFraction: 0.62).delay(1.9)) {
                cubeVisible = true
            }
        }
        .onChange(of: authPanel) { _, panel in
            NotificationCenter.default.post(
                name: .poplurWelcomePanelVisibilityChanged,
                object: panel == .welcome
            )
        }
        .onChange(of: auth.isAuthenticated) { _, authed in
            if authed {
                authPanel = .welcome
                teardownScene()
            }
        }
        .onDisappear {
            NotificationCenter.default.post(
                name: .poplurWelcomePanelVisibilityChanged,
                object: false
            )
            teardownScene()
        }
    }
}
