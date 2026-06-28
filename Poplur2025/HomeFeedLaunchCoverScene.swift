import SpriteKit
import AVFoundation

class HomeFeedLaunchCoverScene: SKScene {

    private var logoNode: SKSpriteNode?
    private var popPlayer: AVAudioPlayer?
    private lazy var cachedPopWAV: Data? = synthesisePopWAV()

    private var loadingLabel: SKLabelNode?
    private var loadingTrack: SKShapeNode?
    private var loadingFill: SKShapeNode?
    private var isConfigured = false
    private var phaseIndex = 0
    private var lastUpdateTime: TimeInterval = 0
    private var particleAccumulator: TimeInterval = 0
    private var particleModeElapsed: TimeInterval = 0
    private var particleModeOrder: [LoadingParticleMode] = LoadingParticleMode.allCases.shuffled()
    private var particleModeIndex = 0
    private var showLoadingDetails = true
    private var loadingBarWidth: CGFloat = 220
    private let loadingBarHeight: CGFloat = 4

    private let loadingPhases: [String] = ([
        "scanning your social radius",
        "calibrating your neural feed",
        "learning local creator signals",
        "mapping nearby content",
        "ranking posts by proximity",
        "discovering your community",
        "processing social graph data",
        "tuning your experience",
        "building your intelligent feed",
        "syncing real-time signals",
        "personalizing your world",
        "analyzing nearby activity",
    ] as [String]).shuffled()

    private enum LoadingParticleMode: CaseIterable {
        case confetti
        case bubbles
        case smoke
        case rain
        case snow
        case sparkle

        var spawnInterval: TimeInterval {
            switch self {
            case .confetti: return 0.09
            case .bubbles: return 0.07
            case .smoke: return 0.11
            case .rain: return 0.025
            case .snow: return 0.055
            case .sparkle: return 0.08
            }
        }

        var dwellDuration: TimeInterval { 2.4 }
    }

    private var currentParticleMode: LoadingParticleMode {
        guard !particleModeOrder.isEmpty else { return .confetti }
        return particleModeOrder[particleModeIndex % particleModeOrder.count]
    }

    private let particlePalette: [UIColor] = [
        .systemPink, .systemOrange, .systemYellow,
        .systemGreen, .systemBlue, .systemPurple,
    ]

    // MARK: - Setup

    static func make(showLoadingDetails: Bool = true) -> HomeFeedLaunchCoverScene {
        let scene = HomeFeedLaunchCoverScene()
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .white
        scene.showLoadingDetails = showLoadingDetails
        return scene
    }

    override func didMove(to view: SKView) {
        backgroundColor = .white
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        view.shouldCullNonVisibleNodes = false
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        configureSceneIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        configureSceneIfNeeded()
        layoutLaunchNodes()
    }

    func setLoadingDetailsVisible(_ visible: Bool) {
        showLoadingDetails = visible
        configureSceneIfNeeded()
        loadingTrack?.isHidden = !visible
        loadingFill?.isHidden = !visible
        loadingLabel?.isHidden = !visible
    }

    private func configureSceneIfNeeded() {
        guard !isConfigured, size.width > 1, size.height > 1 else {
            layoutLaunchNodes()
            return
        }
        isConfigured = true
        setupLogo()
        if showLoadingDetails {
            setupLoadingBar()
            startPhaseLoop()
        }
        startPopLoop()
        layoutLaunchNodes()
    }

    override func willMove(from view: SKView) {
        stopLaunchAudioAndActions()
    }

    deinit {
        stopLaunchAudioAndActions()
    }

    private func stopLaunchAudioAndActions() {
        removeAction(forKey: "popLoop")
        removeAction(forKey: "phaseLoop")
        logoNode?.removeAllActions()
        loadingFill?.removeAllActions()
        popPlayer?.stop()
        popPlayer = nil
    }

    private func setupLogo() {
        let logo = SKSpriteNode(imageNamed: "logo")
        logo.size = CGSize(width: 140, height: 140)
        logo.zPosition = 10
        logo.alpha = 0
        logo.setScale(0.35)
        addChild(logo)
        logoNode = logo

        // Entrance: fade in + bounce scale
        let entrance = SKAction.group([
            SKAction.fadeIn(withDuration: 0.35),
            SKAction.sequence([
                SKAction.scale(to: 1.16, duration: 0.42),
                SKAction.scale(to: 0.91, duration: 0.14),
                SKAction.scale(to: 1.04, duration: 0.10),
                SKAction.scale(to: 1.00, duration: 0.08)
            ])
        ])
        logo.run(entrance) { [weak self] in self?.startIdlePulse() }

        // Slow continuous rotation runs alongside everything else
        logo.run(.repeatForever(.rotate(byAngle: 2 * .pi, duration: 12.0)), withKey: "rotate")
    }

    private func setupLoadingBar() {
        // Track
        let track = SKShapeNode()
        track.fillColor = UIColor.black.withAlphaComponent(0.10)
        track.strokeColor = .clear
        track.zPosition = 5
        addChild(track)
        loadingTrack = track

        // Fill — loops left-to-right so the screen never appears frozen.
        let fill = SKShapeNode()
        fill.fillColor = UIColor(red: 0.0, green: 0.47, blue: 1.0, alpha: 1)
        fill.strokeColor = .clear
        fill.zPosition = 6
        addChild(fill)
        loadingFill = fill

        let grow = SKAction.customAction(withDuration: 2.4) { [weak self] node, elapsed in
            guard let self else { return }
            guard let shape = node as? SKShapeNode else { return }
            let t = CGFloat(elapsed / 2.4)
            let eased = 1 - pow(1 - t, 3)
            let w = max(self.loadingBarHeight, self.loadingBarWidth * eased)
            shape.path = UIBezierPath(
                roundedRect: CGRect(x: 0, y: -self.loadingBarHeight / 2, width: w, height: self.loadingBarHeight),
                cornerRadius: self.loadingBarHeight / 2
            ).cgPath
        }
        fill.run(.repeatForever(grow), withKey: "loadingFillLoop")

        // Phase label
        let label = SKLabelNode(fontNamed: "HelveticaNeue")
        label.fontSize = 13
        label.fontColor = UIColor.black.withAlphaComponent(0.45)
        label.text = loadingPhases[0]
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .top
        label.zPosition = 6
        addChild(label)
        loadingLabel = label
    }

    private func layoutLaunchNodes() {
        guard size.width > 1, size.height > 1 else { return }
        let cx = size.width / 2
        let centerY = size.height / 2
        let logoSize = min(max(size.width * 0.34, 120), 170)
        loadingBarWidth = min(max(size.width - 72, 180), 300)
        let barY = centerY - logoSize / 2 - 36

        logoNode?.size = CGSize(width: logoSize, height: logoSize)
        logoNode?.position = CGPoint(x: cx, y: centerY)

        loadingTrack?.position = CGPoint(x: cx, y: barY)
        loadingTrack?.path = UIBezierPath(
            roundedRect: CGRect(
                x: -loadingBarWidth / 2,
                y: -loadingBarHeight / 2,
                width: loadingBarWidth,
                height: loadingBarHeight
            ),
            cornerRadius: loadingBarHeight / 2
        ).cgPath

        loadingFill?.position = CGPoint(x: cx - loadingBarWidth / 2, y: barY)
        loadingLabel?.position = CGPoint(x: cx, y: barY - loadingBarHeight / 2 - 10)
    }

    private func startPhaseLoop() {
        let advance = SKAction.run { [weak self] in
            guard let self else { return }
            self.phaseIndex = (self.phaseIndex + 1) % self.loadingPhases.count
            let lbl = self.loadingLabel
            lbl?.run(.fadeOut(withDuration: 0.20)) { [weak self] in
                guard let self else { return }
                lbl?.text = self.loadingPhases[self.phaseIndex]
                lbl?.run(.fadeIn(withDuration: 0.20))
            }
        }
        run(.repeatForever(.sequence([.wait(forDuration: 0.9), advance])), withKey: "phaseLoop")
    }

    private func startIdlePulse() {
        logoNode?.removeAction(forKey: "idle")
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 0.85),
            SKAction.scale(to: 0.95, duration: 0.85)
        ])
        logoNode?.run(.repeatForever(pulse), withKey: "idle")
    }

    // MARK: - Pop loop — fires every 1.2 s

    private func startPopLoop() {
        let popAction = SKAction.run { [weak self] in self?.triggerPop() }
        run(.sequence([
            .wait(forDuration: 0.5),
            popAction,
            .repeatForever(.sequence([
                .wait(forDuration: 1.2),
                popAction
            ]))
        ]), withKey: "popLoop")
    }

    private func triggerPop() {
        guard let logo = logoNode else { return }
        playPopSound()
        logo.removeAction(forKey: "idle")
        logo.run(.sequence([
            SKAction.scale(to: 1.42, duration: 0.09),
            SKAction.scale(to: 0.82, duration: 0.08),
            SKAction.scale(to: 1.12, duration: 0.07),
            SKAction.scale(to: 0.94, duration: 0.06),
            SKAction.scale(to: 1.00, duration: 0.05)
        ])) { [weak self] in self?.startIdlePulse() }
        emitBurst(at: logo.position)
    }

    // MARK: - Rotating particle effects

    override func update(_ currentTime: TimeInterval) {
        guard isConfigured, size.width > 1, size.height > 1 else { return }
        let dt = lastUpdateTime > 0 ? min(currentTime - lastUpdateTime, 0.05) : 0
        lastUpdateTime = currentTime

        particleModeElapsed += dt
        if particleModeElapsed >= currentParticleMode.dwellDuration {
            advanceParticleMode()
        }

        let mode = currentParticleMode
        particleAccumulator += dt
        while particleAccumulator >= mode.spawnInterval {
            particleAccumulator -= mode.spawnInterval
            spawnParticle(mode)
        }
    }

    private func advanceParticleMode() {
        particleModeElapsed = 0
        particleAccumulator = 0
        guard !particleModeOrder.isEmpty else { return }
        particleModeIndex = (particleModeIndex + 1) % particleModeOrder.count
        if particleModeIndex == 0 {
            particleModeOrder.shuffle()
        }
    }

    private func spawnParticle(_ mode: LoadingParticleMode) {
        switch mode {
        case .confetti: spawnConfettiPiece()
        case .bubbles: spawnBubblePiece()
        case .smoke: spawnSmokePiece()
        case .rain: spawnRainDrop()
        case .snow: spawnSnowflake()
        case .sparkle: spawnSparkle()
        }
    }

    private func spawnConfettiPiece() {
        let color = particlePalette[Int.random(in: 0..<particlePalette.count)]
        let x = CGFloat.random(in: 0...size.width)
        let w = CGFloat.random(in: 5...13)
        let h = CGFloat.random(in: 4...9)
        let kind = Int.random(in: 0...5)

        let shape: SKShapeNode
        switch kind {
        case 0:  shape = SKShapeNode(circleOfRadius: w * 0.42)
        case 3:  shape = SKShapeNode(rectOf: CGSize(width: 2, height: h * 2.0), cornerRadius: 1)
        default: shape = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 1.5)
        }
        shape.fillColor = color
        shape.strokeColor = .clear
        shape.position = CGPoint(x: x, y: size.height + 14)
        shape.zPosition = CGFloat.random(in: 3...7)
        addChild(shape)

        let dur = Double.random(in: 1.8...3.4)
        let drift = CGFloat.random(in: -38...38)
        let fall = SKAction.move(to: CGPoint(x: x + drift, y: -20), duration: dur)
        let spin = SKAction.rotate(byAngle: CGFloat.random(in: -8...8), duration: dur)
        let fadeDelay = SKAction.wait(forDuration: dur * 0.78)
        let fadeOut  = SKAction.fadeOut(withDuration: dur * 0.22)

        shape.run(.group([
            fall,
            spin,
            .sequence([fadeDelay, fadeOut, .removeFromParent()])
        ]))
    }

    private func spawnBubblePiece() {
        let radius = CGFloat.random(in: 4...16)
        let bubble = SKShapeNode(circleOfRadius: radius)
        bubble.fillColor = UIColor.white.withAlphaComponent(0.05)
        bubble.strokeColor = UIColor.systemBlue.withAlphaComponent(CGFloat.random(in: 0.30...0.58))
        bubble.lineWidth = CGFloat.random(in: 1.0...2.2)
        bubble.position = CGPoint(x: CGFloat.random(in: 0...size.width), y: -radius - 8)
        bubble.zPosition = CGFloat.random(in: 2...6)
        addChild(bubble)

        let dur = Double.random(in: 2.6...4.8)
        let drift = CGFloat.random(in: -52...52)
        bubble.run(.group([
            .move(by: CGVector(dx: drift, dy: size.height + radius * 4), duration: dur),
            .scale(to: CGFloat.random(in: 1.15...1.75), duration: dur),
            .sequence([.wait(forDuration: dur * 0.68), .fadeOut(withDuration: dur * 0.32), .removeFromParent()])
        ]))
    }

    private func spawnSmokePiece() {
        let radius = CGFloat.random(in: 18...44)
        let smoke = SKShapeNode(circleOfRadius: radius)
        smoke.fillColor = UIColor(white: CGFloat.random(in: 0.42...0.70), alpha: CGFloat.random(in: 0.08...0.18))
        smoke.strokeColor = .clear
        smoke.position = CGPoint(x: CGFloat.random(in: 0...size.width), y: -radius)
        smoke.zPosition = CGFloat.random(in: 1...3)
        smoke.setScale(CGFloat.random(in: 0.35...0.72))
        addChild(smoke)

        let dur = Double.random(in: 3.2...5.4)
        let drift = CGFloat.random(in: -70...70)
        smoke.run(.group([
            .move(by: CGVector(dx: drift, dy: size.height * CGFloat.random(in: 0.42...0.68)), duration: dur),
            .scale(to: CGFloat.random(in: 1.45...2.45), duration: dur),
            .sequence([.wait(forDuration: dur * 0.30), .fadeOut(withDuration: dur * 0.70), .removeFromParent()])
        ]))
    }

    private func spawnRainDrop() {
        let drop = SKShapeNode(rectOf: CGSize(width: CGFloat.random(in: 1.5...2.6), height: CGFloat.random(in: 18...34)), cornerRadius: 1)
        drop.fillColor = UIColor.systemBlue.withAlphaComponent(CGFloat.random(in: 0.36...0.62))
        drop.strokeColor = .clear
        let x = CGFloat.random(in: -20...(size.width + 20))
        drop.position = CGPoint(x: x, y: size.height + 24)
        drop.zPosition = CGFloat.random(in: 2...6)
        drop.zRotation = CGFloat.random(in: -0.18...0.18)
        addChild(drop)

        let dur = Double.random(in: 0.75...1.25)
        let drift = CGFloat.random(in: -20...20)
        drop.run(.sequence([
            .group([
                .move(to: CGPoint(x: x + drift, y: -40), duration: dur),
                .fadeOut(withDuration: dur)
            ]),
            .removeFromParent()
        ]))
    }

    private func spawnSnowflake() {
        let radius = CGFloat.random(in: 2.0...5.5)
        let snow = SKShapeNode(circleOfRadius: radius)
        snow.fillColor = UIColor.white.withAlphaComponent(CGFloat.random(in: 0.62...0.92))
        snow.strokeColor = .clear
        let x = CGFloat.random(in: 0...size.width)
        snow.position = CGPoint(x: x, y: size.height + 12)
        snow.zPosition = CGFloat.random(in: 3...7)
        addChild(snow)

        let dur = Double.random(in: 3.0...6.0)
        let drift = CGFloat.random(in: -74...74)
        let sway = SKAction.sequence([
            .moveBy(x: CGFloat.random(in: -18...18), y: 0, duration: dur * 0.25),
            .moveBy(x: CGFloat.random(in: -18...18), y: 0, duration: dur * 0.25),
            .moveBy(x: CGFloat.random(in: -18...18), y: 0, duration: dur * 0.25),
            .moveBy(x: CGFloat.random(in: -18...18), y: 0, duration: dur * 0.25)
        ])
        snow.run(.group([
            .move(to: CGPoint(x: x + drift, y: -20), duration: dur),
            sway,
            .sequence([.wait(forDuration: dur * 0.82), .fadeOut(withDuration: dur * 0.18), .removeFromParent()])
        ]))
    }

    private func spawnSparkle() {
        let s = CGFloat.random(in: 4...11)
        let sparkle = SKShapeNode(rectOf: CGSize(width: s, height: s), cornerRadius: 1)
        sparkle.fillColor = particlePalette.randomElement()?.withAlphaComponent(CGFloat.random(in: 0.58...0.90)) ?? UIColor.systemYellow
        sparkle.strokeColor = .clear
        sparkle.position = CGPoint(x: CGFloat.random(in: 0...size.width), y: CGFloat.random(in: 0...size.height))
        sparkle.zPosition = CGFloat.random(in: 5...9)
        sparkle.zRotation = .pi / 4
        sparkle.setScale(0.15)
        addChild(sparkle)

        let dur = Double.random(in: 0.75...1.35)
        sparkle.run(.sequence([
            .group([.fadeIn(withDuration: dur * 0.18), .scale(to: CGFloat.random(in: 0.9...1.4), duration: dur * 0.30)]),
            .group([.rotate(byAngle: CGFloat.random(in: -2.8...2.8), duration: dur * 0.52), .fadeOut(withDuration: dur * 0.52)]),
            .removeFromParent()
        ]))
    }

    // MARK: - Confetti burst on pop

    private func emitBurst(at center: CGPoint) {
        switch currentParticleMode {
        case .confetti:
            for i in 0..<28 {
                spawnBurstPiece(at: center, color: particlePalette[i % particlePalette.count], index: i)
            }
        case .bubbles:
            for i in 0..<18 { spawnBubbleBurstPiece(at: center, index: i) }
        case .smoke:
            for i in 0..<12 { spawnSmokeBurstPiece(at: center, index: i) }
        case .rain:
            for i in 0..<22 { spawnRainBurstPiece(at: center, index: i) }
        case .snow:
            for i in 0..<26 { spawnSnowBurstPiece(at: center, index: i) }
        case .sparkle:
            for i in 0..<34 { spawnSparkleBurstPiece(at: center, index: i) }
        }
    }

    private func spawnBurstPiece(at center: CGPoint, color: UIColor, index: Int) {
        let w = CGFloat.random(in: 6...15)
        let h = CGFloat.random(in: 5...10)
        let shape: SKShapeNode
        switch index % 6 {
        case 0:  shape = SKShapeNode(circleOfRadius: w * 0.45)
        case 3:  shape = SKShapeNode(rectOf: CGSize(width: 2, height: h * 1.8), cornerRadius: 1)
        default: shape = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 1.5)
        }
        shape.fillColor = color
        shape.strokeColor = .clear
        shape.position = center
        shape.zPosition = CGFloat.random(in: 6...9)
        addChild(shape)

        let angle = CGFloat.random(in: 0...(2 * .pi))
        let speed = CGFloat.random(in: 200...440)
        let vx = cos(angle) * speed
        let vy = sin(angle) * speed
        let bd = Double.random(in: 0.32...0.60)
        let fd = Double.random(in: 0.50...0.85)
        let fallDist = CGFloat.random(in: 250...520)

        let burst = SKAction.move(by: CGVector(dx: vx * bd, dy: vy * bd), duration: bd)
        burst.timingMode = .easeOut
        let fall = SKAction.move(by: CGVector(dx: vx * fd * 0.06, dy: -fallDist), duration: fd)
        fall.timingMode = .easeIn
        let spin = SKAction.rotate(byAngle: CGFloat.random(in: -7...7), duration: bd + fd)
        let fadeDelay = SKAction.wait(forDuration: bd + fd * 0.40)
        let fadeOut = SKAction.fadeOut(withDuration: fd * 0.60)

        shape.run(.group([
            .sequence([burst, fall, .removeFromParent()]),
            spin,
            .sequence([fadeDelay, fadeOut])
        ]))
    }

    private func spawnBubbleBurstPiece(at center: CGPoint, index: Int) {
        let radius = CGFloat.random(in: 5...18)
        let bubble = SKShapeNode(circleOfRadius: radius)
        bubble.fillColor = UIColor.white.withAlphaComponent(0.05)
        bubble.strokeColor = UIColor.systemBlue.withAlphaComponent(0.48)
        bubble.lineWidth = 1.6
        bubble.position = center
        bubble.zPosition = 8
        addChild(bubble)

        let angle = CGFloat(index) / 18.0 * 2 * .pi + CGFloat.random(in: -0.18...0.18)
        let distance = CGFloat.random(in: 110...260)
        let dur = Double.random(in: 0.85...1.45)
        bubble.run(.sequence([
            .group([
                .move(by: CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance + 90), duration: dur),
                .scale(to: CGFloat.random(in: 1.3...1.9), duration: dur),
                .fadeOut(withDuration: dur)
            ]),
            .removeFromParent()
        ]))
    }

    private func spawnSmokeBurstPiece(at center: CGPoint, index: Int) {
        let radius = CGFloat.random(in: 18...46)
        let smoke = SKShapeNode(circleOfRadius: radius)
        smoke.fillColor = UIColor(white: CGFloat.random(in: 0.45...0.68), alpha: CGFloat.random(in: 0.10...0.20))
        smoke.strokeColor = .clear
        smoke.position = center
        smoke.zPosition = 7
        smoke.setScale(0.25)
        addChild(smoke)

        let angle = CGFloat(index) / 12.0 * 2 * .pi
        let dur = Double.random(in: 1.2...2.0)
        smoke.run(.sequence([
            .group([
                .move(by: CGVector(dx: cos(angle) * CGFloat.random(in: 30...130), dy: abs(sin(angle)) * 90 + CGFloat.random(in: 80...180)), duration: dur),
                .scale(to: CGFloat.random(in: 1.4...2.4), duration: dur),
                .fadeOut(withDuration: dur)
            ]),
            .removeFromParent()
        ]))
    }

    private func spawnRainBurstPiece(at center: CGPoint, index: Int) {
        let drop = SKShapeNode(rectOf: CGSize(width: 2, height: CGFloat.random(in: 16...32)), cornerRadius: 1)
        drop.fillColor = UIColor.systemBlue.withAlphaComponent(0.58)
        drop.strokeColor = .clear
        drop.position = center
        drop.zPosition = 8
        addChild(drop)

        let angle = CGFloat(index) / 22.0 * 2 * .pi
        let distance = CGFloat.random(in: 120...310)
        let dur = Double.random(in: 0.45...0.80)
        drop.zRotation = angle - .pi / 2
        drop.run(.sequence([
            .group([
                .move(by: CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance - 60), duration: dur),
                .fadeOut(withDuration: dur)
            ]),
            .removeFromParent()
        ]))
    }

    private func spawnSnowBurstPiece(at center: CGPoint, index: Int) {
        let snow = SKShapeNode(circleOfRadius: CGFloat.random(in: 2.5...6.0))
        snow.fillColor = UIColor.white.withAlphaComponent(0.88)
        snow.strokeColor = .clear
        snow.position = center
        snow.zPosition = 8
        addChild(snow)

        let angle = CGFloat(index) / 26.0 * 2 * .pi
        let distance = CGFloat.random(in: 80...230)
        let dur = Double.random(in: 1.1...1.9)
        snow.run(.sequence([
            .group([
                .move(by: CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance - 120), duration: dur),
                .fadeOut(withDuration: dur)
            ]),
            .removeFromParent()
        ]))
    }

    private func spawnSparkleBurstPiece(at center: CGPoint, index: Int) {
        let s = CGFloat.random(in: 5...12)
        let sparkle = SKShapeNode(rectOf: CGSize(width: s, height: s), cornerRadius: 1)
        sparkle.fillColor = particlePalette[index % particlePalette.count].withAlphaComponent(0.88)
        sparkle.strokeColor = .clear
        sparkle.position = center
        sparkle.zPosition = 9
        sparkle.zRotation = .pi / 4
        addChild(sparkle)

        let angle = CGFloat(index) / 34.0 * 2 * .pi
        let distance = CGFloat.random(in: 120...280)
        let dur = Double.random(in: 0.65...1.15)
        sparkle.run(.sequence([
            .group([
                .move(by: CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance), duration: dur),
                .rotate(byAngle: CGFloat.random(in: -5...5), duration: dur),
                .fadeOut(withDuration: dur)
            ]),
            .removeFromParent()
        ]))
    }

    // MARK: - Pop sound

    private func playPopSound() {
        guard let data = cachedPopWAV else { return }
        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.volume = 0.62
        player.play()
        popPlayer = player
    }

    private func synthesisePopWAV() -> Data? {
        let sr: Double = 44100
        let dur: Double = 0.13
        let count = Int(sr * dur)
        var samples = [Int16]()
        samples.reserveCapacity(count)
        for i in 0..<count {
            let t = Double(i) / sr
            let env = exp(-t * 38.0)
            let freq = max(90.0, 680.0 - t * 4500.0)
            let wave = sin(2.0 * .pi * freq * t)
            samples.append(Int16(wave * env * Double(Int16.max) * 0.68))
        }
        return buildWAV(samples: samples, sampleRate: UInt32(sr))
    }

    private func buildWAV(samples: [Int16], sampleRate: UInt32) -> Data {
        var data = Data()
        data.reserveCapacity(44 + samples.count * 2)
        func le16(_ v: UInt16) { data.append(UInt8(v & 0xFF)); data.append(UInt8(v >> 8)) }
        func le32(_ v: UInt32) { le16(UInt16(v & 0xFFFF)); le16(UInt16(v >> 16)) }
        let dataLen = UInt32(samples.count * 2)
        data.append(contentsOf: "RIFF".utf8); le32(36 + dataLen)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        le32(16); le16(1); le16(1)
        le32(sampleRate); le32(sampleRate * 2); le16(2); le16(16)
        data.append(contentsOf: "data".utf8); le32(dataLen)
        for s in samples { le16(UInt16(bitPattern: s)) }
        return data
    }
}
