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
    private var rainAccumulator: TimeInterval = 0
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

    private let rainPalette: [UIColor] = [
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

    // MARK: - Continuous confetti rain

    override func update(_ currentTime: TimeInterval) {
        guard isConfigured, size.width > 1, size.height > 1 else { return }
        let dt = lastUpdateTime > 0 ? min(currentTime - lastUpdateTime, 0.05) : 0
        lastUpdateTime = currentTime
        rainAccumulator += dt
        if rainAccumulator >= 0.09 {
            rainAccumulator -= 0.09
            spawnRainPiece()
        }
    }

    private func spawnRainPiece() {
        let color = rainPalette[Int.random(in: 0..<rainPalette.count)]
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

    // MARK: - Confetti burst on pop

    private func emitBurst(at center: CGPoint) {
        for i in 0..<28 {
            spawnBurstPiece(at: center, color: rainPalette[i % rainPalette.count], index: i)
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
