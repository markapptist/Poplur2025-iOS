import SpriteKit
import AVFoundation
import UIKit

// MARK: - Data Extensions

extension Data {
    mutating func append<T>(_ value: T) where T: FixedWidthInteger {
        var mutableValue = value
        let bytes = Swift.withUnsafeBytes(of: &mutableValue) { Data($0) }
        self.append(bytes)
    }
}

// MARK: - Dial Tone Player

/// Plays DTMF dial tones for phone buttons
class DialTonePlayer {
    private var audioPlayers: [String: AVAudioPlayer] = [:]
    private var generatedPlayers: [AVAudioPlayer] = []

    func playTone(for digit: String) {
        configureAudioSessionIfNeeded()
        generatedPlayers.removeAll { !$0.isPlaying }

        // Try to play bundled audio file first
        if let player = loadAudioPlayer(for: digit) {
            player.play()
        } else {
            // Fallback: Generate tone on-the-fly
            generateAndPlayTone(for: digit)
        }
    }

    private func loadAudioPlayer(for digit: String) -> AVAudioPlayer? {
        // Check if already loaded
        if let player = audioPlayers[digit] {
            player.currentTime = 0
            return player
        }

        // Try to load from bundle
        let filename = audioFilename(for: digit)
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil) else {
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            audioPlayers[digit] = player
            return player
        } catch {
            return nil
        }
    }

    private func audioFilename(for digit: String) -> String {
        switch digit {
        case "*": return "dial_star.wav"
        case "#": return "dial_hash.wav"
        default: return "dial_\(digit).wav"
        }
    }

    private func generateAndPlayTone(for digit: String) {
        // Generate DTMF tone in-memory and play it
        guard let audioData = DTMFToneGenerator.generateTone(for: digit, duration: 0.2) else {
            return
        }

        do {
            let player = try AVAudioPlayer(data: audioData)
            player.prepareToPlay()
            player.play()
            generatedPlayers.append(player)
        } catch {
            print("Failed to play generated tone: \(error)")
        }
    }

    private func configureAudioSessionIfNeeded() {
        #if os(iOS)
        // .playback ignores the ringer/silent switch so dial tones are always audible.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    func stopAllTones() {
        audioPlayers.values.forEach { $0.stop() }
        generatedPlayers.forEach { $0.stop() }
        generatedPlayers.removeAll()
    }
}

// MARK: - DTMF Tone Generator

/// Generates DTMF (Dual-Tone Multi-Frequency) tones for phone digits
class DTMFToneGenerator {
    private static let sampleRate: Double = 44100.0

    /// DTMF frequency pairs for each digit
    private static let frequencies: [String: (low: Double, high: Double)] = [
        "1": (697, 1209), "2": (697, 1336), "3": (697, 1477),
        "4": (770, 1209), "5": (770, 1336), "6": (770, 1477),
        "7": (852, 1209), "8": (852, 1336), "9": (852, 1477),
        "*": (941, 1209), "0": (941, 1336), "#": (941, 1477),
        "ring": (440, 480)
    ]

    /// Generate a DTMF tone as WAV audio data
    static func generateTone(for digit: String, duration: Double = 0.2) -> Data? {
        guard let freqs = frequencies[digit] else { return nil }

        let numSamples = Int(sampleRate * duration)
        var samples: [Int16] = []

        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let low = sin(2.0 * .pi * freqs.low * t)
            let high = sin(2.0 * .pi * freqs.high * t)
            let combined = (low + high) / 2.0
            let sample = Int16(combined * Double(Int16.max) * 0.8) // 80% volume
            samples.append(sample)
        }

        return createWAVData(from: samples)
    }

    /// Create WAV file data from PCM samples
    private static func createWAVData(from samples: [Int16]) -> Data {
        var data = Data()

        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels * bitsPerSample / 8)
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = UInt32(samples.count * 2)

        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(36 + dataSize).littleEndian)
        data.append("WAVE".data(using: .ascii)!)

        // Format chunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndian) // Chunk size
        data.append(UInt16(1).littleEndian)  // Audio format (PCM)
        data.append(numChannels.littleEndian)
        data.append(UInt32(sampleRate).littleEndian)
        data.append(byteRate.littleEndian)
        data.append(blockAlign.littleEndian)
        data.append(bitsPerSample.littleEndian)

        // Data chunk
        data.append("data".data(using: .ascii)!)
        data.append(dataSize.littleEndian)

        for sample in samples {
            data.append(sample.littleEndian)
        }

        return data
    }
}

// MARK: - Phone Scene

private enum PhoneMenuScreen {
    case main
    case calls
    case contacts
    case texts
    case games
    case settings
}

private struct PhoneMenuItem {
    let title: String
    let detail: String
    let glyph: String
    let destination: PhoneMenuScreen?
    let action: String?
}

class PhoneScene: SKScene, ObservableObject {
    private var phoneLayer: SKNode?
    private var phoneFrame: CGRect = .zero
    private var phoneArtworkNode: SKSpriteNode?
    private var selectedPhoneBootupSpritesheetName = "poplur_phone_bootup_silver_diamond"
    private var selectedPhoneBatterySpritesheetName = "poplur_phone_battery_01"
    private var signalStatusNode: SKSpriteNode?
    private var signalStatusFrames: [SKTexture] = []
    private var batteryStatusNode: SKSpriteNode?
    private var idleAnimationNode: SKSpriteNode?
    private var isBootingUp = false
    private var wasShowingCallStatusBeforeBootup = false
    private var deviceBatteryLevel: Float = 1.0
    private var batteryObserverTokens: [NSObjectProtocol] = []
    private var isPhoneButtonActive = true
    private var screenNode: SKSpriteNode?
    private var screenTextLabel: SKLabelNode?
    private var callStatusLabel: SKLabelNode?
    private var screenFrames: [SKTexture] = []
    private var menuLayer: SKNode?
    private var menuScreen: PhoneMenuScreen = .main
    private var selectedMenuIndex = 0

    /// Set by PopularPhone to trigger an in-app call when the centre nav key is pressed.
    var onCallButtonTapped: (() -> Void)?

    /// Set by PopularPhone to dismiss the phone screen when the user taps Exit.
    var onDismiss: (() -> Void)?

    private var dialButtons: [SKNode] = []
    private var dialedNumber = ""
    var onDialedNumberChanged: ((String) -> Void)?

    private var isSnakeActive = false
    private var snakeLayer: SKNode?
    private var snakeBody: [SnakeGridPoint] = []
    private var snakeDirection = SnakeGridPoint(x: 1, y: 0)
    private var pendingSnakeDirection = SnakeGridPoint(x: 1, y: 0)
    private var snakeFood = SnakeGridPoint(x: 10, y: 5)
    private var snakeScore = 0
    private let snakeColumns = 16
    private let snakeRows = 10

    private let buttonLayout = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]

    private let tonePlayer = DialTonePlayer()
    private var bootupPlayer: AVAudioPlayer?
    private var ringtonePlayer: AVAudioPlayer?
    private var ringtoneCycleTask: Task<Void, Never>?

    let callingUser: FakeUser

    init(callingUser: FakeUser) {
        self.callingUser = callingUser
        super.init(size: CGSize(width: 400, height: 700))
        self.scaleMode = .resizeFill
        self.backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        batteryObserverTokens.forEach(NotificationCenter.default.removeObserver)
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        startDeviceBatteryMonitoring()
        setupPhone()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard oldSize != size, view != nil else { return }
        setupPhone()
    }

    func applyColorway(_ assetName: String) {
        selectedPhoneBootupSpritesheetName = assetName
        selectedPhoneBatterySpritesheetName = batterySpritesheetName(for: assetName)
        reloadSignalStatusOverlay()
        startBootup()
    }

    func animatePhoneButtonPress(_ control: String) {
        runPhonePressAnimation(for: control)
    }

    func setPhoneButtonActive(_ isActive: Bool, announce: Bool = true) {
        isPhoneButtonActive = isActive
        guard announce else { return }
        generateHapticFeedback()
        flashMenuDetail(isActive ? "BUTTON\nACTIVE" : "BUTTON\nLOCKED")
    }

    private func setupPhone() {
        removeAllChildren()
        removeAction(forKey: "snakeLoop")
        removeAction(forKey: "idleSignalSchedule")
        dialButtons.removeAll()
        phoneArtworkNode = nil
        signalStatusNode = nil
        signalStatusFrames = []
        batteryStatusNode = nil
        idleAnimationNode = nil
        screenNode = nil
        screenTextLabel = nil
        callStatusLabel = nil
        snakeLayer = nil
        menuLayer = nil

        let layer = SKNode()
        layer.position = .zero
        layer.zPosition = 0
        addChild(layer)
        phoneLayer = layer
        phoneFrame = fittedPhoneFrame(in: size)

        addPhoneArtwork(to: layer)
        screenFrames = []
        setupAnimatedScreen()
        setupSignalStatusOverlay()
        setupBatteryIndicator()
        setupDialPad()
        setupCallButton()
        showPhoneMenu(.main)
        scheduleNextIdleSignalAnimation()

        if isSnakeActive {
            startSnakeGame()
        }
    }

    private func setupAnimatedScreen() {
        let screenRect = phoneScreenRect()

        // Custom shape that traces the static LCD border in the phone image.
        // Slightly smaller corner radius than a generic rounded rect to match
        // the chunky rectangular Nokia-era screen bezel.
        let shape = SKShapeNode(path: lcdBorderPath(for: screenRect))
        shape.fillColor = phoneScreenColor
        shape.strokeColor = UIColor(red: 0.08, green: 0.10, blue: 0.0, alpha: 0.55)
        shape.lineWidth = max(1, min(screenRect.width, screenRect.height) * 0.010)
        shape.zPosition = 1.9
        shape.name = "lcd_fill"
        addChild(shape)

        // Transparent sprite kept for position reference by other helpers
        let node = SKSpriteNode(color: .clear, size: screenRect.size)
        node.position = CGPoint(x: screenRect.midX, y: screenRect.midY)
        node.zPosition = 2
        screenNode = node
        addChild(node)

        setupScreenText()
    }

    private func setupSignalStatusOverlay() {
        // Solid background ensures the sprite blends perfectly with the LCD fill colour
        let bg = SKSpriteNode(color: phoneScreenColor, size: signalStatusRect().size)
        bg.position = CGPoint(x: signalStatusRect().midX, y: signalStatusRect().midY)
        bg.zPosition = 6.9
        bg.name = "signal_bg"
        addChild(bg)

        let node = SKSpriteNode(color: .clear, size: signalStatusRect().size)
        node.position = CGPoint(x: signalStatusRect().midX, y: signalStatusRect().midY)
        node.zPosition = 7
        node.name = "signal_status_overlay"
        signalStatusNode = node
        addChild(node)
        reloadSignalStatusOverlay()
    }

    private func reloadSignalStatusOverlay() {
        signalStatusFrames = currentSignalStatusFrames()
        guard let signalStatusNode else { return }
        signalStatusNode.removeAction(forKey: "idleSignalAnimation")
        signalStatusNode.size = signalStatusRect().size
        signalStatusNode.position = CGPoint(x: signalStatusRect().midX, y: signalStatusRect().midY)
        signalStatusNode.texture = signalStatusFrames.last
        updateSignalStatusVisibility()
    }

    private func signalStatusRect() -> CGRect {
        rectFromTop(
            x: Self.signalPatchLeftFraction,
            y: Self.signalPatchTopFraction,
            width: Self.signalPatchWidthFraction,
            height: Self.signalPatchHeightFraction
        )
    }

    private func batteryStatusRect() -> CGRect {
        rectFromTop(
            x: Self.batteryPatchLeftFraction,
            y: Self.batteryPatchTopFraction,
            width: Self.batteryPatchWidthFraction,
            height: Self.batteryPatchHeightFraction
        )
    }

    private func setupBatteryIndicator() {
        let rect = batteryStatusRect()

        let bg = SKSpriteNode(color: phoneScreenColor, size: rect.size)
        bg.position = CGPoint(x: rect.midX, y: rect.midY)
        bg.zPosition = 6.9
        bg.name = "battery_bg"
        addChild(bg)

        let node = SKSpriteNode(
            texture: makeBatteryTexture(level: deviceBatteryLevel, size: rect.size),
            size: rect.size
        )
        node.position = CGPoint(x: rect.midX, y: rect.midY)
        node.zPosition = 7
        node.name = "battery_status_overlay"
        batteryStatusNode = node
        addChild(node)
    }

    private func updateBatteryIndicator() {
        guard let batteryStatusNode else { return }
        batteryStatusNode.texture = makeBatteryTexture(
            level: deviceBatteryLevel,
            size: batteryStatusRect().size
        )
    }

    private func makeBatteryTexture(level: Float, size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let padX = size.width * 0.05
            let padY = size.height * 0.18
            let nubW = size.width * 0.08
            let lineW = max(1.0, size.height * 0.08)

            phoneScreenColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let bodyW = size.width - padX * 2 - nubW
            let bodyH = size.height - padY * 2
            let bodyRect = CGRect(x: padX, y: padY, width: bodyW, height: bodyH)

            // Battery body filled with ink, then cleared in interior (outline effect)
            lcdDarkColor.setFill()
            ctx.fill(bodyRect)
            phoneScreenColor.setFill()
            ctx.fill(bodyRect.insetBy(dx: lineW, dy: lineW))

            // Fill segments based on battery level (4 Nokia-style bars)
            let bars = max(0, min(4, Int((level * 4 + 0.5).rounded())))
            if bars > 0 {
                let segW = (bodyW - lineW * 2) / 4
                lcdDarkColor.setFill()
                ctx.fill(CGRect(x: padX + lineW, y: padY + lineW,
                                width: segW * CGFloat(bars), height: bodyH - lineW * 2))
            }

            // Nub (positive terminal on right side)
            let nubH = bodyH * 0.50
            lcdDarkColor.setFill()
            ctx.fill(CGRect(x: padX + bodyW, y: padY + (bodyH - nubH) / 2,
                            width: nubW * 0.75, height: nubH))
        }
        return SKTexture(image: image)
    }

    private func lcdBorderPath(for rect: CGRect) -> CGPath {
        // Nokia screens had small corner radii — use ~4% of the shorter dimension
        let r = min(rect.width, rect.height) * 0.040
        return UIBezierPath(roundedRect: rect, cornerRadius: r).cgPath
    }

    private func fittedPhoneFrame(in container: CGSize) -> CGRect {
        let aspect = phoneAspectRatio
        let horizontalInset = container.width * Self.phoneHorizontalInsetFraction
        let availableWidth = max(1, container.width - horizontalInset * 2)
        let availableHeight = max(1, container.height)

        let phoneWidth = min(availableWidth, availableHeight * aspect)
        let phoneHeight = phoneWidth / aspect

        return CGRect(
            x: (container.width - phoneWidth) / 2,
            y: (container.height - phoneHeight) / 2,
            width: phoneWidth,
            height: phoneHeight
        )
    }

    private func rectFromTop(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: phoneFrame.minX + phoneFrame.width * x,
            y: phoneFrame.maxY - phoneFrame.height * (y + height),
            width: phoneFrame.width * width,
            height: phoneFrame.height * height
        )
    }

    private func phoneScreenRect() -> CGRect {
        rectFromTop(
            x: screenLeftFraction,
            y: screenTopFraction,
            width: screenWidthFraction,
            height: screenHeightFraction
        )
    }

    private func addPhoneArtwork(to layer: SKNode) {
        let texture = restingPhoneTexture()
        let phone = SKSpriteNode(texture: texture)
        phone.position = CGPoint(x: phoneFrame.midX, y: phoneFrame.midY)
        phone.size = phoneFrame.size
        phone.zPosition = 0
        phoneArtworkNode = phone
        layer.addChild(phone)
    }

    private func startBootup() {
        guard let phoneArtworkNode else { return }

        let frames = currentBootupFrames()
        guard !frames.isEmpty else {
            phoneArtworkNode.texture = restingPhoneTexture()
            updateSignalStatusVisibility()
            scheduleNextIdleSignalAnimation()
            return
        }

        isBootingUp = true
        stopIdleSignalAnimation()
        setInteractiveContentHiddenForBootup(true)
        phoneArtworkNode.removeAction(forKey: "bootup")
        phoneArtworkNode.removeAction(forKey: "phonePressFrame")
        phoneArtworkNode.setScale(1.0)
        phoneLayer?.removeAction(forKey: "bootupVibration")
        removeAction(forKey: "bootupHaptics")

        phoneArtworkNode.texture = frames.first

        let soundDuration = playBootupSound()
        let bootupDuration = max(soundDuration, Self.bootupFallbackDuration)
        let timePerFrame = bootupDuration / Double(frames.count)
        let bootupFrames = SKAction.animate(with: frames, timePerFrame: timePerFrame, resize: false, restore: false)
        let finish = SKAction.run { [weak self] in
            guard let self else { return }
            self.isBootingUp = false
            self.phoneArtworkNode?.texture = self.restingPhoneTexture()
            self.setInteractiveContentHiddenForBootup(false)
            self.reloadSignalStatusOverlay()
            self.scheduleNextIdleSignalAnimation()
        }

        phoneArtworkNode.run(.sequence([bootupFrames, finish]), withKey: "bootup")
        runBootupVibration(duration: bootupDuration)
        runBootupHaptics(duration: bootupDuration)
    }

    private func currentBootupFrames() -> [SKTexture] {
        Self.makeBootupFrames(named: selectedPhoneBootupSpritesheetName)
    }

    private func currentPressFrames() -> [SKTexture] {
        Self.makePressFrames(named: pressSpritesheetName(for: selectedPhoneBootupSpritesheetName))
    }

    private func currentBatteryFrames() -> [SKTexture] {
        Self.makeBatteryFrames(named: selectedPhoneBatterySpritesheetName)
    }

    private func currentSignalStatusFrames() -> [SKTexture] {
        Self.makeSignalStatusFrames(named: signalSpritesheetName(for: selectedPhoneBootupSpritesheetName))
    }

    private func restingPhoneTexture() -> SKTexture {
        let batteryFrames = currentBatteryFrames()
        let texture: SKTexture
        if !batteryFrames.isEmpty {
            texture = batteryFrames[batteryFrameIndex(frameCount: batteryFrames.count)]
        } else {
            texture = currentBootupFrames().last ?? SKTexture(imageNamed: fallbackPhoneArtworkName(for: selectedPhoneBootupSpritesheetName))
        }
        texture.filteringMode = .linear
        return texture
    }

    private func startDeviceBatteryMonitoring() {
        guard batteryObserverTokens.isEmpty else { return }

        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshDeviceBatteryLevel(updateArtwork: false)

        let center = NotificationCenter.default
        batteryObserverTokens = [
            center.addObserver(
                forName: UIDevice.batteryLevelDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshDeviceBatteryLevel(updateArtwork: true)
            },
            center.addObserver(
                forName: UIDevice.batteryStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshDeviceBatteryLevel(updateArtwork: true)
            }
        ]
    }

    private func refreshDeviceBatteryLevel(updateArtwork: Bool) {
        let rawLevel = UIDevice.current.batteryLevel
        let normalizedLevel = rawLevel >= 0 ? min(max(rawLevel, 0), 1) : 1
        let changed = abs(normalizedLevel - deviceBatteryLevel) > 0.001
        deviceBatteryLevel = normalizedLevel

        guard updateArtwork, changed, !isBootingUp else { return }
        phoneArtworkNode?.texture = restingPhoneTexture()
        updateBatteryIndicator()
    }

    private func batteryFrameIndex(frameCount: Int) -> Int {
        guard frameCount > 1 else { return 0 }
        let clampedLevel = CGFloat(min(max(deviceBatteryLevel, 0), 1))
        return min(frameCount - 1, max(0, Int((clampedLevel * CGFloat(frameCount - 1)).rounded())))
    }

    private func scheduleNextIdleSignalAnimation() {
        removeAction(forKey: "idleSignalSchedule")
        guard isPhoneIdleForSignalAnimation else { return }

        startIdleAnimation()

        // Show signal at full bars right away; the idle sweep plays after the random delay.
        signalStatusNode?.texture = signalStatusFrames.last
        updateSignalStatusVisibility()

        let delay = TimeInterval.random(in: 1.2...4.2)
        run(.sequence([
            .wait(forDuration: delay),
            .run { [weak self] in self?.runIdleSignalAnimationIfPossible() }
        ]), withKey: "idleSignalSchedule")
    }

    private func stopIdleSignalAnimation() {
        removeAction(forKey: "idleSignalSchedule")
        signalStatusNode?.removeAction(forKey: "idleSignalAnimation")
        signalStatusNode?.texture = signalStatusFrames.last
        updateSignalStatusVisibility()
        stopIdleAnimation()
    }

    private func idleSpritesheetName(for bootupName: String) -> String? {
        switch bootupName {
        case "poplur_phone_bootup_icy_aqua_turquoise":
            return "poplur_phone_idle_icy_aqua_turquoise"
        case "poplur_phone_bootup_holographic_iridescent":
            return "poplur_phone_idle_holographic_iridescent"
        default:
            return nil
        }
    }

    private func startIdleAnimation() {
        guard let sheetName = idleSpritesheetName(for: selectedPhoneBootupSpritesheetName),
              let phoneLayer else {
            idleAnimationNode?.isHidden = true
            return
        }
        let frames = Self.makeIdleFrames(named: sheetName)
        guard !frames.isEmpty else {
            idleAnimationNode?.isHidden = true
            return
        }

        if idleAnimationNode == nil {
            let node = SKSpriteNode(texture: frames.first)
            node.position = CGPoint(x: phoneFrame.midX, y: phoneFrame.midY)
            node.size = phoneFrame.size
            node.zPosition = 0.8
            node.blendMode = .screen
            node.name = "idleAnimationNode"
            phoneLayer.addChild(node)
            idleAnimationNode = node
        } else {
            idleAnimationNode?.position = CGPoint(x: phoneFrame.midX, y: phoneFrame.midY)
            idleAnimationNode?.size = phoneFrame.size
            idleAnimationNode?.texture = frames.first
        }

        idleAnimationNode?.isHidden = false
        let animate = SKAction.animate(with: frames, timePerFrame: 0.10, resize: false, restore: false)
        idleAnimationNode?.run(.repeatForever(animate), withKey: "idleAnimation")
    }

    private func stopIdleAnimation() {
        idleAnimationNode?.removeAction(forKey: "idleAnimation")
        idleAnimationNode?.isHidden = true
    }

    private func runIdleSignalAnimationIfPossible() {
        guard isPhoneIdleForSignalAnimation,
              let signalStatusNode,
              !signalStatusFrames.isEmpty
        else {
            scheduleNextIdleSignalAnimation()
            return
        }

        updateSignalStatusVisibility()
        let frames = Bool.random() ? signalStatusFrames : Array(signalStatusFrames.reversed())
        let timePerFrame = TimeInterval.random(in: 0.055...0.095)
        let animate = SKAction.animate(with: frames, timePerFrame: timePerFrame, resize: false, restore: false)
        let finish = SKAction.run { [weak self] in
            guard let self else { return }
            self.signalStatusNode?.texture = self.signalStatusFrames.last
            self.scheduleNextIdleSignalAnimation()
        }

        signalStatusNode.run(.sequence([animate, finish]), withKey: "idleSignalAnimation")
    }

    private var isPhoneIdleForSignalAnimation: Bool {
        guard !isBootingUp, !isSnakeActive else { return false }
        guard phoneArtworkNode?.action(forKey: "phonePressFrame") == nil else { return false }
        guard callStatusLabel?.isHidden != false else { return false }
        return true
    }

    private func updateSignalStatusVisibility() {
        let hidden = signalStatusFrames.isEmpty || !isPhoneIdleForSignalAnimation
        signalStatusNode?.isHidden = hidden
        childNode(withName: "signal_bg")?.isHidden = hidden
        batteryStatusNode?.isHidden = hidden
        childNode(withName: "battery_bg")?.isHidden = hidden
    }

    private func setInteractiveContentHiddenForBootup(_ hidden: Bool) {
        if hidden {
            wasShowingCallStatusBeforeBootup = callStatusLabel?.isHidden == false
            // Keep lcd_fill, screenNode, and menuLayer visible so the main menu
            // remains on-screen during the bootup animation.
            screenTextLabel?.isHidden = true
            callStatusLabel?.isHidden = true
            snakeLayer?.isHidden = true
            signalStatusNode?.isHidden = true
            batteryStatusNode?.isHidden = true
            childNode(withName: "signal_bg")?.isHidden = true
            childNode(withName: "battery_bg")?.isHidden = true
            return
        }

        childNode(withName: "lcd_fill")?.isHidden = false
        screenNode?.isHidden = false
        updateSignalStatusVisibility()

        if isSnakeActive {
            snakeLayer?.isHidden = false
            screenTextLabel?.isHidden = true
            menuLayer?.isHidden = true
            signalStatusNode?.isHidden = true
            batteryStatusNode?.isHidden = true
            childNode(withName: "signal_bg")?.isHidden = true
            childNode(withName: "battery_bg")?.isHidden = true
            return
        }

        if wasShowingCallStatusBeforeBootup {
            callStatusLabel?.isHidden = false
            screenTextLabel?.isHidden = true
            menuLayer?.isHidden = true
            snakeLayer?.isHidden = true
            signalStatusNode?.isHidden = true
            batteryStatusNode?.isHidden = true
            childNode(withName: "signal_bg")?.isHidden = true
            childNode(withName: "battery_bg")?.isHidden = true
            wasShowingCallStatusBeforeBootup = false
            return
        }

        if menuLayer != nil {
            menuLayer?.isHidden = false
            screenTextLabel?.isHidden = true
        } else {
            screenTextLabel?.isHidden = false
        }
    }

    private func playBootupSound() -> TimeInterval {
        configureBootupAudioSessionIfNeeded()
        bootupPlayer?.stop()
        bootupPlayer = nil

        guard let url = Bundle.main.url(forResource: "popular_phone_bootup", withExtension: "mp3") else {
            return Self.bootupFallbackDuration
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            bootupPlayer = player
            return player.duration
        } catch {
            return Self.bootupFallbackDuration
        }
    }

    private func configureBootupAudioSessionIfNeeded() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func runBootupVibration(duration: TimeInterval) {
        guard let phoneLayer else { return }

        let shake = SKAction.sequence([
            .moveBy(x: -2.4, y: 1.2, duration: 0.035),
            .moveBy(x: 4.8, y: -2.2, duration: 0.045),
            .moveBy(x: -3.8, y: 1.6, duration: 0.035),
            .moveBy(x: 1.4, y: -0.6, duration: 0.030)
        ])
        let cycles = max(1, Int(duration / 0.145))
        phoneLayer.run(.sequence([
            .repeat(shake, count: cycles),
            .move(to: .zero, duration: 0.05)
        ]), withKey: "bootupVibration")
    }

    private func runBootupHaptics(duration: TimeInterval) {
        #if os(iOS)
        let tick = SKAction.sequence([
            .run { [weak self] in self?.generateHapticFeedback() },
            .wait(forDuration: 0.28)
        ])
        run(.repeat(tick, count: max(1, Int(duration / 0.28))), withKey: "bootupHaptics")
        #endif
    }

    private func addGlitterOverlay(to layer: SKNode) {
        let tex = makeGlitterTexture()
        let node = SKSpriteNode(texture: tex)
        node.position = CGPoint(x: phoneFrame.midX, y: phoneFrame.midY)
        node.size = phoneFrame.size
        node.zPosition = 0.5
        node.blendMode = .screen
        node.alpha = 0.48
        node.shader = makeGlitterMaskShader()
        layer.addChild(node)

        // Slow shimmer so the glitter catches light differently over time
        let shimmer = SKAction.sequence([
            .fadeAlpha(to: 0.28, duration: 1.8),
            .fadeAlpha(to: 0.52, duration: 2.1)
        ])
        node.run(.repeatForever(shimmer))
    }

    private func makeGlitterTexture() -> SKTexture {
        let tile = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: tile)
        let img = renderer.image { _ in
            // Near-black base — dark areas stay transparent against the red body
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: tile)).fill()

            // Dense multi-coloured flecks: purple, pink, gold, silver
            let fleckColors: [UIColor] = [
                UIColor(red: 0.80, green: 0.0,  blue: 0.90, alpha: 0.88),
                UIColor(red: 0.95, green: 0.20, blue: 0.60, alpha: 0.82),
                UIColor(red: 0.90, green: 0.55, blue: 0.10, alpha: 0.78),
                UIColor(red: 0.70, green: 0.68, blue: 0.90, alpha: 0.72),
                UIColor(red: 0.60, green: 0.0,  blue: 0.70, alpha: 0.85),
            ]
            for i in 0..<2800 {
                let fi = CGFloat(i)
                let x = (fi * 1.618).truncatingRemainder(dividingBy: 1.0) * tile.width
                let y = (fi * 2.414).truncatingRemainder(dividingBy: 1.0) * tile.height
                let r = CGFloat(0.9 + fi.truncatingRemainder(dividingBy: 6) * 0.45)
                fleckColors[i % fleckColors.count].setFill()
                UIBezierPath(ovalIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
            }

            // Bright white sparkle dots (the actual "glitter" catch-lights)
            for i in 0..<320 {
                let fi = CGFloat(i)
                let x = (fi * 3.14159).truncatingRemainder(dividingBy: 1.0) * tile.width
                let y = (fi * 2.71828).truncatingRemainder(dividingBy: 1.0) * tile.height
                let r = CGFloat(1.1 + fi.truncatingRemainder(dividingBy: 4) * 1.0)
                UIColor.white.withAlphaComponent(0.88 + fi.truncatingRemainder(dividingBy: 3) * 0.04).setFill()
                UIBezierPath(ovalIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
            }
        }
        return SKTexture(image: img)
    }

    private func makeGlitterMaskShader() -> SKShader {
        let source = """
        void main() {
            vec4 tex = texture2D(u_texture, v_tex_coord);
            vec2 uv = v_tex_coord;

            float bw = 0.138; float bh = 0.052;
            float dx, dy, isButton;
            isButton = 0.0;
            dx=(uv.x-0.28)/bw; dy=(uv.y-0.317)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.50)/bw; dy=(uv.y-0.317)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.72)/bw; dy=(uv.y-0.317)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.28)/bw; dy=(uv.y-0.242)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.50)/bw; dy=(uv.y-0.242)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.72)/bw; dy=(uv.y-0.242)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.28)/bw; dy=(uv.y-0.167)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.50)/bw; dy=(uv.y-0.167)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.72)/bw; dy=(uv.y-0.167)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.28)/bw; dy=(uv.y-0.092)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.50)/bw; dy=(uv.y-0.092)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.72)/bw; dy=(uv.y-0.092)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.50)/0.195; dy=(uv.y-0.503)/0.065; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.235)/0.120; dy=(uv.y-0.503)/0.062; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.765)/0.120; dy=(uv.y-0.503)/0.062; isButton=max(isButton,step(dx*dx+dy*dy,1.0));

            gl_FragColor = vec4(tex.rgb, tex.a * (1.0 - isButton));
        }
        """
        return SKShader(source: source)
    }

    private func makePlasticShader() -> SKShader {
        let source = """
        void main() {
            vec4 tex = texture2D(u_texture, v_tex_coord);
            vec2 uv   = v_tex_coord;

            // ---- Button UV mask (generous clearance so red never touches button edges) ----
            float bw = 0.138; float bh = 0.052;
            float dx, dy, isButton;
            isButton = 0.0;
            // Row 0  (UV y 0.317)
            dx=(uv.x-0.28)/bw; dy=(uv.y-0.317)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.50)/bw; dy=(uv.y-0.317)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.72)/bw; dy=(uv.y-0.317)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            // Row 1  (UV y 0.242)
            dx=(uv.x-0.28)/bw; dy=(uv.y-0.242)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.50)/bw; dy=(uv.y-0.242)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.72)/bw; dy=(uv.y-0.242)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            // Row 2  (UV y 0.167)
            dx=(uv.x-0.28)/bw; dy=(uv.y-0.167)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.50)/bw; dy=(uv.y-0.167)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.72)/bw; dy=(uv.y-0.167)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            // Row 3  (UV y 0.092)
            dx=(uv.x-0.28)/bw; dy=(uv.y-0.092)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.50)/bw; dy=(uv.y-0.092)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.72)/bw; dy=(uv.y-0.092)/bh; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            // Nav: centre, left, right — wider clearance
            dx=(uv.x-0.50)/0.195; dy=(uv.y-0.503)/0.065; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.235)/0.120; dy=(uv.y-0.503)/0.062; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.765)/0.120; dy=(uv.y-0.503)/0.062; isButton=max(isButton,step(dx*dx+dy*dy,1.0));

            // ---- Luminance ----
            float lum = dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722));

            // ---- Hole mask ----
            float holeMask = smoothstep(0.07, 0.22, lum);

            // ---- Body brightness ----
            float b = pow(lum, 0.55);
            b = mix(0.42, 1.0, b);

            // ---- Nokia red palette ----
            vec3 shadowRed = vec3(0.68, 0.04, 0.04);
            vec3 midRed    = vec3(0.82, 0.08, 0.08);
            vec3 litRed    = vec3(0.94, 0.20, 0.20);
            vec3 bodyColor = b < 0.65
                ? mix(shadowRed, midRed,  b / 0.65)
                : mix(midRed,    litRed, (b - 0.65) / 0.35);

            // ---- Matte rubber diffuse ----
            float d = length((uv - vec2(0.50, 0.78)) * vec2(0.80, 1.00));
            float diffuse = pow(max(0.0, 1.0 - d * 1.15), 3.0) * 0.08;
            bodyColor += vec3(diffuse * 0.92, diffuse * 0.18, diffuse * 0.18);

            // ---- Perimeter darkening ----
            vec2 vc = uv - vec2(0.50, 0.48);
            float rim = smoothstep(0.0, 0.55, length(vc * vec2(0.75, 0.88)));
            bodyColor *= mix(1.0, 0.78, rim * rim);

            // ---- Hole colour ----
            vec3 holeColor = vec3(0.045, 0.010, 0.010);

            // ---- Composite body ----
            vec3 bodyFinal = mix(holeColor, bodyColor, holeMask);
            vec4 bodyResult = vec4(clamp(bodyFinal, 0.0, 1.0), tex.a);

            // ---- Button regions keep original photo colour ----
            gl_FragColor = mix(bodyResult, tex, isButton);
        }
        """
        return SKShader(source: source)
    }

    private func makeLCDScreenShader() -> SKShader {
        // Sampled from the LCD background in phone_body: RGB #EFF100,
        // HSV hue 60.7°, saturation 1.0, value 0.945.
        let source = """
        void main() {
            gl_FragColor = vec4(0.9372549, 0.94509804, 0.0, 1.0);
        }
        """
        return SKShader(source: source)
    }

    private func drawConstructedPhone(in layer: SKNode) {
        let body = SKShapeNode(rect: phoneFrame, cornerRadius: phoneFrame.width * 0.105)
        body.fillColor = UIColor(red: 0.055, green: 0.058, blue: 0.055, alpha: 1.0)
        body.strokeColor = UIColor(red: 0.11, green: 0.115, blue: 0.11, alpha: 1.0)
        body.lineWidth = phoneFrame.width * 0.018
        body.zPosition = 0
        layer.addChild(body)

        let facePlate = SKShapeNode(rect: rectFromTop(x: 0.09, y: 0.05, width: 0.82, height: 0.88), cornerRadius: phoneFrame.width * 0.09)
        facePlate.fillColor = UIColor(red: 0.145, green: 0.145, blue: 0.125, alpha: 1.0)
        facePlate.strokeColor = UIColor.black.withAlphaComponent(0.88)
        facePlate.lineWidth = phoneFrame.width * 0.025
        facePlate.zPosition = 0.2
        layer.addChild(facePlate)

        addSideRail(x: 0.045, to: layer)
        addSideRail(x: 0.88, to: layer)
        addScreenAssembly(to: layer)
        addNavigationKeys(to: layer)
        drawWearTexture(in: phoneFrame, on: layer)
    }

    private func addSideRail(x: CGFloat, to layer: SKNode) {
        let railRect = rectFromTop(x: x, y: 0.035, width: 0.075, height: 0.91)
        let rail = SKShapeNode(rect: railRect, cornerRadius: railRect.width * 0.48)
        rail.fillColor = UIColor(red: 0.025, green: 0.029, blue: 0.031, alpha: 1.0)
        rail.strokeColor = UIColor(red: 0.19, green: 0.19, blue: 0.17, alpha: 0.9)
        rail.lineWidth = max(1.5, phoneFrame.width * 0.006)
        rail.zPosition = 0.4
        layer.addChild(rail)
    }

    private func addScreenAssembly(to layer: SKNode) {
        let wellRect = rectFromTop(x: 0.11, y: 0.075, width: 0.78, height: 0.335)
        let well = SKShapeNode(rect: wellRect, cornerRadius: phoneFrame.width * 0.045)
        well.fillColor = UIColor(red: 0.025, green: 0.027, blue: 0.025, alpha: 1.0)
        well.strokeColor = UIColor(red: 0.22, green: 0.22, blue: 0.19, alpha: 0.95)
        well.lineWidth = phoneFrame.width * 0.014
        well.zPosition = 0.8
        layer.addChild(well)

        let glowRect = rectFromTop(x: 0.155, y: 0.105, width: 0.69, height: 0.294)
        let glow = SKShapeNode(rect: glowRect, cornerRadius: phoneFrame.width * 0.032)
        glow.fillColor = phoneYellow.withAlphaComponent(0.96)
        glow.strokeColor = .clear
        glow.zPosition = 1
        layer.addChild(glow)
    }

    private func addNavigationKeys(to layer: SKNode) {
        let left = roundedControl(rect: rectFromTop(x: 0.15, y: 0.455, width: 0.17, height: 0.083), rotation: 0.22)
        left.addChild(controlLabel("⚙", fontSize: phoneFrame.height * 0.032, x: 0, y: -phoneFrame.height * 0.003))
        layer.addChild(left)

        let centerRect = rectFromTop(x: 0.335, y: 0.452, width: 0.33, height: 0.09)
        let center = SKShapeNode(ellipseIn: centerRect)
        center.fillColor = UIColor(red: 0.44, green: 0.42, blue: 0.37, alpha: 1.0)
        center.strokeColor = UIColor.black.withAlphaComponent(0.92)
        center.lineWidth = phoneFrame.width * 0.022
        center.zPosition = 2
        layer.addChild(center)

        let dash = SKShapeNode(rectOf: CGSize(width: phoneFrame.width * 0.14, height: phoneFrame.height * 0.008), cornerRadius: phoneFrame.height * 0.004)
        dash.fillColor = UIColor(red: 0.02, green: 0.52, blue: 0.13, alpha: 1.0)
        dash.strokeColor = .clear
        dash.position = CGPoint(x: centerRect.midX, y: centerRect.midY + phoneFrame.height * 0.003)
        dash.zPosition = 2.2
        layer.addChild(dash)

        let right = roundedControl(rect: rectFromTop(x: 0.68, y: 0.43, width: 0.18, height: 0.15), rotation: -0.25)
        right.addChild(controlLabel("▶", fontSize: phoneFrame.height * 0.031, x: 0, y: phoneFrame.height * 0.034))
        right.addChild(controlLabel("◀", fontSize: phoneFrame.height * 0.031, x: 0, y: -phoneFrame.height * 0.034))
        layer.addChild(right)
    }

    private func roundedControl(rect: CGRect, rotation: CGFloat) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: rect.midX, y: rect.midY)
        node.zRotation = rotation
        node.zPosition = 2

        let shape = SKShapeNode(rectOf: rect.size, cornerRadius: min(rect.width, rect.height) * 0.33)
        shape.fillColor = UIColor(red: 0.43, green: 0.42, blue: 0.37, alpha: 1.0)
        shape.strokeColor = UIColor.black.withAlphaComponent(0.9)
        shape.lineWidth = phoneFrame.width * 0.018
        node.addChild(shape)
        return node
    }

    private func controlLabel(_ text: String, fontSize: CGFloat, x: CGFloat, y: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNextCondensed-Heavy")
        label.text = text
        label.fontColor = phoneYellow
        label.fontSize = fontSize
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: x, y: y)
        label.zPosition = 1
        return label
    }

    private func drawWearTexture(in rect: CGRect, on layer: SKNode) {
        for index in 0..<130 {
            let seed = CGFloat((index * 37) % 101) / 101
            let seedTwo = CGFloat((index * 53) % 97) / 97
            let x = rect.minX + rect.width * (0.11 + seed * 0.78)
            let y = rect.minY + rect.height * (0.06 + seedTwo * 0.88)
            let radius = phoneFrame.width * (0.0025 + CGFloat(index % 4) * 0.001)
            let spot = SKShapeNode(circleOfRadius: radius)
            spot.fillColor = (index % 3 == 0)
                ? UIColor.white.withAlphaComponent(0.065)
                : UIColor.black.withAlphaComponent(0.12)
            spot.strokeColor = .clear
            spot.position = CGPoint(x: x, y: y)
            spot.zPosition = 2.6
            layer.addChild(spot)
        }
    }

    private func createPlaceholderScreen(size: CGSize) -> SKSpriteNode {
        SKSpriteNode(color: phoneScreenColor, size: size)
    }

    private func startScreenPowerUpAnimation() {
        guard let screenNode = screenNode else { return }

        let fadeIn = SKAction.fadeIn(withDuration: 0.36)
        guard !screenFrames.isEmpty else {
            screenNode.run(fadeIn, withKey: "screenPowerUp")
            return
        }
        let bootFrames = SKAction.animate(with: screenFrames, timePerFrame: 0.035, resize: false, restore: false)
        screenNode.run(.group([fadeIn, bootFrames]), withKey: "screenPowerUp")
    }

    private func setupDialPad() {
        let buttonSize = CGSize(width: phoneFrame.width * 0.18, height: phoneFrame.height * 0.055)
        let xCenters: [CGFloat] = [0.30, 0.50, 0.70]
        let yCentersFromTop: [CGFloat] = [0.63, 0.705, 0.78, 0.855]

        for (rowIndex, row) in buttonLayout.enumerated() {
            for (colIndex, digit) in row.enumerated() {
                let xPos = phoneFrame.minX + phoneFrame.width * xCenters[colIndex]
                let yPos = phoneFrame.maxY - phoneFrame.height * yCentersFromTop[rowIndex]

                let button = createDialButton(digit: digit, size: buttonSize)
                button.position = CGPoint(x: xPos, y: yPos)
                button.name = "button_\(digit)"
                button.zPosition = 3

                addChild(button)
                dialButtons.append(button)
            }
        }
    }

    private func setupCallButton() {
        let callRect = rectFromTop(x: 0.335, y: 0.485, width: 0.33, height: 0.08)
        let button = SKNode()
        button.name = "call_button"
        button.position = CGPoint(x: callRect.midX, y: callRect.midY)
        button.zPosition = 3

        let shape = SKShapeNode(ellipseOf: callRect.size)
        shape.name = "call_button"
        shape.fillColor = .white
        shape.strokeColor = .clear
        shape.alpha = 0.01
        button.addChild(shape)

        addChild(button)
    }

    private func createDialButton(digit: String, size: CGSize) -> SKNode {
        let group = SKNode()
        group.name = "button_\(digit)"

        let shape = SKShapeNode(rectOf: size, cornerRadius: size.height * 0.36)
        shape.name = "button_\(digit)"
        shape.fillColor = .white
        shape.strokeColor = .clear
        shape.lineWidth = 0
        shape.alpha = 0.01
        shape.zPosition = 0
        group.addChild(shape)

        return group
    }

    private func buttonSubText(for digit: String) -> String {
        switch digit {
        case "2": return "abc"
        case "3": return "def"
        case "4": return "ghi"
        case "5": return "jkl"
        case "6": return "mno"
        case "7": return "pqrs"
        case "8": return "tuv"
        case "9": return "wxyz"
        case "*": return "+"
        case "0": return "−"
        case "#": return "⇧"
        default:  return ""
        }
    }

    private func glowingKeyLabel(_ text: String, fontSize: CGFloat, y: CGFloat, weight: UIFont.Weight) -> SKNode {
        let group = SKNode()
        group.position = CGPoint(x: 0, y: y)

        let glow = SKLabelNode(fontNamed: "HelveticaNeue-CondensedBlack")
        glow.text = text
        glow.fontColor = keyGlowGreen.withAlphaComponent(0.82)
        glow.fontSize = fontSize
        glow.horizontalAlignmentMode = .center
        glow.verticalAlignmentMode = .center
        glow.blendMode = .add
        glow.alpha = 0.72
        glow.xScale = 1.10
        glow.yScale = 1.10
        glow.zPosition = 0
        group.addChild(glow)

        let main = SKLabelNode()
        main.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
                .foregroundColor: keyGlowGreen,
                .strokeColor: UIColor.white.withAlphaComponent(0.72),
                .strokeWidth: -1.4
            ]
        )
        main.horizontalAlignmentMode = .center
        main.verticalAlignmentMode = .center
        main.blendMode = .add
        main.zPosition = 1
        group.addChild(main)

        let polish = SKLabelNode(fontNamed: "HelveticaNeue-CondensedBlack")
        polish.text = text
        polish.fontColor = UIColor.white.withAlphaComponent(0.52)
        polish.fontSize = fontSize * 0.96
        polish.horizontalAlignmentMode = .center
        polish.verticalAlignmentMode = .center
        polish.position = CGPoint(x: 0, y: fontSize * 0.08)
        polish.blendMode = .add
        polish.alpha = 0.42
        polish.zPosition = 2
        group.addChild(polish)

        return group
    }

    private func showPhoneMenu(_ screen: PhoneMenuScreen, selectedIndex: Int = 0) {
        guard !isSnakeActive else { return }
        menuScreen = screen
        let items = menuItems(for: screen)
        selectedMenuIndex = min(max(0, selectedIndex), max(0, items.count - 1))
        screenTextLabel?.isHidden = true
        callStatusLabel?.isHidden = true
        renderPhoneMenu(items: items)
    }

    private func renderPhoneMenu(items: [PhoneMenuItem]) {
        menuLayer?.removeFromParent()

        let layer = SKNode()
        layer.zPosition = 5.8
        addChild(layer)
        menuLayer = layer

        let screenRect = phoneScreenRect().insetBy(dx: phoneScreenRect().width * 0.045, dy: phoneScreenRect().height * 0.08)
        let titleHeight = screenRect.height * 0.18
        let footerHeight = screenRect.height * 0.14
        let listTop = screenRect.maxY - titleHeight
        let listBottom = screenRect.minY + footerHeight
        let rowHeight = (listTop - listBottom) / CGFloat(max(items.count, 1))

        let titleBar = SKShapeNode(rect: CGRect(x: screenRect.minX, y: screenRect.maxY - titleHeight, width: screenRect.width, height: titleHeight), cornerRadius: screenRect.width * 0.025)
        titleBar.fillColor = UIColor(red: 0.80, green: 0.86, blue: 0.0, alpha: 0.30)
        titleBar.strokeColor = lcdDarkColor.withAlphaComponent(0.60)
        titleBar.lineWidth = max(1, screenRect.height * 0.008)
        titleBar.zPosition = 0
        layer.addChild(titleBar)

        let title = menuTitle(for: menuScreen)
        let titleLabel = menuLabel(title.uppercased(), size: screenRect.height * 0.095, weight: .black)
        titleLabel.position = CGPoint(x: screenRect.midX, y: screenRect.maxY - titleHeight * 0.56)
        titleLabel.zPosition = 2
        layer.addChild(titleLabel)

        for (index, item) in items.enumerated() {
            let y = listTop - rowHeight * CGFloat(index + 1)
            let rowRect = CGRect(x: screenRect.minX, y: y, width: screenRect.width, height: rowHeight * 0.92)
            if index == selectedMenuIndex {
                let highlight = SKShapeNode(rect: rowRect.insetBy(dx: screenRect.width * 0.015, dy: rowHeight * 0.08), cornerRadius: rowHeight * 0.18)
                highlight.fillColor = lcdDarkColor.withAlphaComponent(0.12)
                highlight.strokeColor = lcdDarkColor.withAlphaComponent(0.85)
                highlight.lineWidth = max(1, rowHeight * 0.04)
                highlight.glowWidth = 0
                highlight.zPosition = 0.5
                layer.addChild(highlight)
            }

            let glyph = menuLabel(item.glyph, size: rowHeight * 0.33, weight: .black)
            glyph.position = CGPoint(x: screenRect.minX + screenRect.width * 0.10, y: rowRect.midY - rowHeight * 0.02)
            glyph.zPosition = 2
            layer.addChild(glyph)

            let itemLabel = menuLabel(item.title, size: rowHeight * 0.28, weight: index == selectedMenuIndex ? .black : .heavy)
            itemLabel.horizontalAlignmentMode = .left
            itemLabel.position = CGPoint(x: screenRect.minX + screenRect.width * 0.20, y: rowRect.midY + rowHeight * 0.08)
            itemLabel.zPosition = 2
            layer.addChild(itemLabel)

            if !item.detail.isEmpty {
                let detail = menuLabel(item.detail, size: rowHeight * 0.18, weight: .bold, alpha: index == selectedMenuIndex ? 0.92 : 0.58)
                detail.horizontalAlignmentMode = .left
                detail.position = CGPoint(x: screenRect.minX + screenRect.width * 0.20, y: rowRect.midY - rowHeight * 0.20)
                detail.zPosition = 2
                layer.addChild(detail)
            }
        }

        let softKeys = menuLabel("2/8 MOVE    5 SELECT    * BACK", size: screenRect.height * 0.045, weight: .bold, alpha: 0.78)
        softKeys.position = CGPoint(x: screenRect.midX, y: screenRect.minY + footerHeight * 0.38)
        softKeys.zPosition = 2
        layer.addChild(softKeys)
    }

    private func menuLabel(_ text: String, size: CGFloat, weight: UIFont.Weight, alpha: CGFloat = 1.0) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = size
        label.fontColor = lcdDarkColor.withAlphaComponent(alpha)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.blendMode = .alpha
        return label
    }

    private func menuTitle(for screen: PhoneMenuScreen) -> String {
        switch screen {
        case .main: return "Poplur"
        case .calls: return "Calls"
        case .contacts: return "Contacts"
        case .texts: return "Texts"
        case .games: return "Games"
        case .settings: return "Settings"
        }
    }

    private func menuItems(for screen: PhoneMenuScreen) -> [PhoneMenuItem] {
        switch screen {
        case .main:
            return [
                PhoneMenuItem(title: "Calls", detail: "place and manage calls", glyph: "01", destination: .calls, action: nil),
                PhoneMenuItem(title: "Contacts", detail: "people on Poplur", glyph: "02", destination: .contacts, action: nil),
                PhoneMenuItem(title: "Texts", detail: "inbox and drafts", glyph: "03", destination: .texts, action: nil),
                PhoneMenuItem(title: "Games", detail: "classic extras", glyph: "04", destination: .games, action: nil),
                PhoneMenuItem(title: "Settings", detail: "tones and profile", glyph: "05", destination: .settings, action: nil),
                PhoneMenuItem(title: "Exit", detail: "close phone", glyph: "06", destination: nil, action: "exit")
            ]
        case .calls:
            return [
                PhoneMenuItem(title: "Call \(callingUser.name)", detail: "start Poplur call", glyph: ">", destination: nil, action: "call"),
                PhoneMenuItem(title: "Recent calls", detail: "no missed calls", glyph: "R", destination: nil, action: "noop"),
                PhoneMenuItem(title: "Dial number", detail: "keypad entry", glyph: "#", destination: nil, action: "dial")
            ]
        case .contacts:
            return [
                PhoneMenuItem(title: callingUser.name, detail: "Poplur contact", glyph: "A", destination: nil, action: "call"),
                PhoneMenuItem(title: "Poplur Support", detail: "online", glyph: "B", destination: nil, action: "noop"),
                PhoneMenuItem(title: "Add contact", detail: "coming soon", glyph: "+", destination: nil, action: "noop")
            ]
        case .texts:
            return [
                PhoneMenuItem(title: "Inbox", detail: "3 unread messages", glyph: "I", destination: nil, action: "noop"),
                PhoneMenuItem(title: "Write message", detail: "compose SMS", glyph: "W", destination: nil, action: "noop"),
                PhoneMenuItem(title: "Drafts", detail: "0 saved", glyph: "D", destination: nil, action: "noop")
            ]
        case .games:
            return [
                PhoneMenuItem(title: "Snake", detail: "press 5 to play", glyph: "S", destination: nil, action: "snake"),
                PhoneMenuItem(title: "Memory", detail: "locked", glyph: "M", destination: nil, action: "noop"),
                PhoneMenuItem(title: "Bounce", detail: "locked", glyph: "B", destination: nil, action: "noop")
            ]
        case .settings:
            return [
                PhoneMenuItem(title: "Ring tone", detail: "classic pop", glyph: "T", destination: nil, action: "noop"),
                PhoneMenuItem(title: "Screen glow", detail: "green", glyph: "G", destination: nil, action: "noop"),
                PhoneMenuItem(title: "About", detail: "Poplur phone", glyph: "?", destination: nil, action: "noop")
            ]
        }
    }

    private func handleMenuDigit(_ digit: String) -> Bool {
        guard menuLayer != nil else { return false }
        let items = menuItems(for: menuScreen)

        switch digit {
        case "2":
            selectedMenuIndex = (selectedMenuIndex - 1 + items.count) % items.count
            showPhoneMenu(menuScreen, selectedIndex: selectedMenuIndex)
            return true
        case "8":
            selectedMenuIndex = (selectedMenuIndex + 1) % items.count
            showPhoneMenu(menuScreen, selectedIndex: selectedMenuIndex)
            return true
        case "5", "#":
            activateSelectedMenuItem()
            return true
        case "*":
            if menuScreen == .main {
                return true
            }
            showPhoneMenu(.main)
            return true
        case "1", "3", "4", "6", "7", "9", "0":
            if menuScreen == .main, let shortcut = Int(digit), shortcut >= 1, shortcut <= items.count {
                selectedMenuIndex = shortcut - 1
                activateSelectedMenuItem()
                return true
            }
            return true
        default:
            return false
        }
    }

    private func activateSelectedMenuItem() {
        let items = menuItems(for: menuScreen)
        guard items.indices.contains(selectedMenuIndex) else { return }
        let item = items[selectedMenuIndex]

        if let destination = item.destination {
            showPhoneMenu(destination)
            return
        }

        switch item.action {
        case "call":
            menuLayer?.removeFromParent()
            menuLayer = nil
            placeCurrentCall()
        case "snake":
            startSnakeGame()
        case "dial":
            menuLayer?.removeFromParent()
            menuLayer = nil
            screenTextLabel?.isHidden = false
            updateScreenText()
        case "exit":
            onDismiss?()
        default:
            flashMenuDetail("\(item.title.uppercased())\nCOMING SOON")
        }
    }

    private func flashMenuDetail(_ text: String) {
        menuLayer?.removeFromParent()
        menuLayer = nil
        screenTextLabel?.isHidden = false
        screenTextLabel?.text = text
        screenTextLabel?.fontSize = phoneScreenRect().height * 0.12
        run(.sequence([
            .wait(forDuration: 0.85),
            .run { [weak self] in self?.showPhoneMenu(self?.menuScreen ?? .main, selectedIndex: self?.selectedMenuIndex ?? 0) }
        ]), withKey: "menuFlash")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isBootingUp else { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // LCD screen area is always passive — tapping it never navigates menus
        if phoneScreenRect().contains(location) { return }

        let touchedNodes = nodes(at: location)

        for node in touchedNodes {
            if let callButton = callButtonNode(from: node) {
                handleCallButtonPress(callButton)
                break
            }

            if let buttonNode = buttonNode(from: node) {
                let digit = (buttonNode.name ?? "").replacingOccurrences(of: "button_", with: "")
                handleButtonPress(digit: digit, button: buttonNode)
                break
            }
        }
    }

    private func buttonNode(from node: SKNode) -> SKNode? {
        var current: SKNode? = node
        while let candidate = current {
            if let name = candidate.name, name.hasPrefix("button_") {
                return candidate
            }
            current = candidate.parent
        }
        return nil
    }

    private func callButtonNode(from node: SKNode) -> SKNode? {
        var current: SKNode? = node
        while let candidate = current {
            if candidate.name == "call_button" {
                return candidate
            }
            current = candidate.parent
        }
        return nil
    }

    private func handleCallButtonPress(_ button: SKNode) {
        runPhonePressAnimation(for: "call")

        guard isPhoneButtonActive else {
            generateHapticFeedback()
            flashMenuDetail("BUTTON\nLOCKED")
            return
        }

        if menuLayer != nil {
            activateSelectedMenuItem()
            return
        }

        let scaleDown = SKAction.scale(to: 0.9, duration: 0.08)
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
        button.run(.sequence([scaleDown, scaleUp]))
        generateHapticFeedback()
        placeCurrentCall()
    }

    private func placeCurrentCall() {
        if let handler = onCallButtonTapped {
            handler()
        } else {
            placeCall()
        }
    }

    private func handleButtonPress(digit: String, button: SKNode) {
        runPhonePressAnimation(for: digit)
        playDialTone(for: digit)

        guard isPhoneButtonActive else {
            flashMenuDetail("BUTTON\nLOCKED")
            return
        }

        // Visual feedback
        let scaleDown = SKAction.scale(to: 0.85, duration: 0.1)
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
        let sequence = SKAction.sequence([scaleDown, scaleUp])
        button.run(sequence)

        if isSnakeActive {
            handleSnakeButton(digit)
            return
        }

        if handleMenuDigit(digit) {
            return
        }

        appendDialedDigit(digit)
    }

    private func runPhonePressAnimation(for control: String) {
        guard !isBootingUp, let phoneArtworkNode else { return }
        guard let frameIndex = pressFrameIndex(for: control) else { return }

        let frames = currentPressFrames()
        guard frames.indices.contains(frameIndex) else { return }

        stopIdleSignalAnimation()
        phoneArtworkNode.removeAction(forKey: "phonePressFrame")
        signalStatusNode?.isHidden = true
        batteryStatusNode?.isHidden = true
        childNode(withName: "signal_bg")?.isHidden = true
        childNode(withName: "battery_bg")?.isHidden = true

        phoneArtworkNode.texture = frames[frameIndex]

        phoneArtworkNode.run(.sequence([
            .wait(forDuration: 0.14),
            .run { [weak self, weak phoneArtworkNode] in
                guard let self, let phoneArtworkNode else { return }
                phoneArtworkNode.texture = self.restingPhoneTexture()
                self.scheduleNextIdleSignalAnimation()
            }
        ]), withKey: "phonePressFrame")
    }

    private func pressFrameIndex(for control: String) -> Int? {
        // CGImage y=0 is visual bottom. Row 3 (visual top) = frames 12-15.
        // Frame 0 and 12 are reference/overview images in the sheet — avoid them.
        // Confirmed by visual inspection of each cell:
        // Row 3 (visual top):  12=ref,    13=call,   14=gear,   15=nav
        // Row 2:               8=1,       9=2,       10=3,      11=nav/4
        // Row 1:               4=5,       5=6,       6=7,       7=8
        // Row 0 (visual bot):  0=ref,     1=0,       2=nav,     3=nav
        switch control {
        case "gear":
            return 14
        case "call":
            return 13
        case "navUp", "navLeft":
            return 2
        case "navDown", "navRight":
            return 3
        case "1":
            return 8
        case "2":
            return 9
        case "3":
            return 10
        case "4":
            return 11
        case "5":
            return 4
        case "6":
            return 5
        case "7":
            return 6
        case "8":
            return 7
        case "9":
            return nil  // frame 12 is a reference image — skip to avoid wrong colorway
        case "*":
            return nil  // frame 0 is a reference image — skip
        case "0":
            return 1
        case "#":
            return nil  // frame 15 shows nav highlight — skip to avoid wrong button
        default:
            return nil
        }
    }

    private func playDialTone(for digit: String) {
        // Use the DialTonePlayer which will either play bundled audio or generate tones
        tonePlayer.playTone(for: digit)

        // Generate haptic feedback
        generateHapticFeedback()
    }

    private func generateHapticFeedback() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    func stopAllSounds() {
        tonePlayer.stopAllTones()
        stopRingtone()
        bootupPlayer?.stop()
        bootupPlayer = nil
        phoneLayer?.removeAction(forKey: "bootupVibration")
        removeAction(forKey: "bootupHaptics")
        stopIdleSignalAnimation()
    }

    func startRingtone() {
        stopRingtone()
        playRingBurst()
        ringtoneCycleTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6.0))
                guard !Task.isCancelled else { return }
                DispatchQueue.main.async { [weak self] in self?.playRingBurst() }
            }
        }
    }

    func stopRingtone() {
        ringtoneCycleTask?.cancel()
        ringtoneCycleTask = nil
        ringtonePlayer?.stop()
        ringtonePlayer = nil
    }

    private func playRingBurst() {
        guard let data = DTMFToneGenerator.generateTone(for: "ring", duration: 2.0),
              let player = try? AVAudioPlayer(data: data) else { return }
        ringtonePlayer?.stop()
        ringtonePlayer = player
        player.volume = 0.85
        player.play()
    }

    private func placeCall() {
        let allowedCharacters = Set("0123456789*#+")
        let normalized = dialedNumber.filter { allowedCharacters.contains($0) }
        guard !normalized.isEmpty else { return }

        let encoded = normalized
            .replacingOccurrences(of: "#", with: "%23")
            .replacingOccurrences(of: "+", with: "%2B")

        guard let url = URL(string: "tel://\(encoded)") else { return }

        #if os(iOS)
        UIApplication.shared.open(url)
        #endif
    }

    private func appendDialedDigit(_ digit: String) {
        guard dialedNumber.count < 24 else { return }

        if digit == "*" {
            dialedNumber.append(digit)
        } else {
            dialedNumber.append(digit)
        }

        updateScreenText()
        onDialedNumberChanged?(dialedNumber)
    }

    private func setupScreenText() {
        let screenRect = phoneScreenRect()
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.fontColor = lcdDarkColor
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.numberOfLines = 2
        label.preferredMaxLayoutWidth = screenRect.width * 0.82
        label.position = CGPoint(x: screenRect.midX, y: screenRect.midY - screenRect.height * 0.03)
        label.blendMode = .alpha
        label.zPosition = 5
        addChild(label)
        screenTextLabel = label
        updateScreenText()
    }

    private func updateScreenText() {
        guard let screenTextLabel else { return }

        if dialedNumber.isEmpty {
            screenTextLabel.text = ""
        } else {
            screenTextLabel.text = groupedDialedNumber(dialedNumber)
            let screenHeight = phoneScreenRect().height
            screenTextLabel.fontSize = dialedNumber.count > 12 ? screenHeight * 0.16 : screenHeight * 0.22
        }
    }

    private func groupedDialedNumber(_ value: String) -> String {
        let characters = Array(value)
        guard characters.count > 12 else { return value }
        let midpoint = min(12, characters.count)
        return String(characters[..<midpoint]) + "\n" + String(characters[midpoint...])
    }

    private static func makeScreenFrames() -> [SKTexture] {
        guard let spriteSheet = UIImage(named: "screens"),
              let cgImage = spriteSheet.cgImage
        else { return [] }

        var frames: [SKTexture] = []

        for row in 0..<screenRows {
            for column in 0..<screenColumns {
                let cell = CGRect(
                    x: CGFloat(cgImage.width) * CGFloat(column) / CGFloat(screenColumns),
                    y: CGFloat(cgImage.height) * CGFloat(row) / CGFloat(screenRows),
                    width: CGFloat(cgImage.width) / CGFloat(screenColumns),
                    height: CGFloat(cgImage.height) / CGFloat(screenRows)
                )
                let crop = CGRect(
                    x: cell.minX + cell.width * spriteCropLeftFraction,
                    y: cell.minY + cell.height * spriteCropTopFraction,
                    width: cell.width * spriteCropWidthFraction,
                    height: cell.height * spriteCropHeightFraction
                ).integral

                if let cropped = cgImage.cropping(to: crop) {
                    let image = UIImage(cgImage: cropped, scale: spriteSheet.scale, orientation: spriteSheet.imageOrientation)
                    frames.append(SKTexture(image: image))
                }
            }
        }

        return frames
    }

    private static func makeBootupFrames(named spritesheetName: String) -> [SKTexture] {
        if let cached = bootupFrameCache[spritesheetName] {
            return cached
        }

        guard let spriteSheet = UIImage(named: spritesheetName),
              let cgImage = spriteSheet.cgImage
        else { return [] }

        let cellWidth = CGFloat(cgImage.width) / CGFloat(bootupColumns)
        let cellHeight = CGFloat(cgImage.height) / CGFloat(bootupRows)
        var frames: [SKTexture] = []

        for row in 0..<bootupRows {
            for column in 0..<bootupColumns {
                let cell = CGRect(
                    x: CGFloat(column) * cellWidth,
                    y: CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                ).integral

                if let cropped = cgImage.cropping(to: cell) {
                    let image = UIImage(cgImage: cropped, scale: spriteSheet.scale, orientation: spriteSheet.imageOrientation)
                    let texture = SKTexture(image: image)
                    texture.filteringMode = .linear
                    frames.append(texture)
                }
            }
        }

        bootupFrameCache[spritesheetName] = frames
        return frames
    }

    private static func makePressFrames(named spritesheetName: String) -> [SKTexture] {
        if let cached = pressFrameCache[spritesheetName] {
            return cached
        }

        guard let spriteSheet = UIImage(named: spritesheetName),
              let cgImage = spriteSheet.cgImage
        else { return [] }

        let cellWidth = CGFloat(cgImage.width) / CGFloat(pressColumns)
        let cellHeight = CGFloat(cgImage.height) / CGFloat(pressRows)
        var frames: [SKTexture] = []

        for row in 0..<pressRows {
            for column in 0..<pressColumns {
                let cell = CGRect(
                    x: CGFloat(column) * cellWidth,
                    y: CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                ).integral

                if let cropped = cgImage.cropping(to: cell) {
                    let image = UIImage(cgImage: cropped, scale: spriteSheet.scale, orientation: spriteSheet.imageOrientation)
                    let texture = SKTexture(image: image)
                    texture.filteringMode = .linear
                    frames.append(texture)
                }
            }
        }

        pressFrameCache[spritesheetName] = frames
        return frames
    }

    private static func makeBatteryFrames(named spritesheetName: String) -> [SKTexture] {
        if let cached = batteryFrameCache[spritesheetName] {
            return cached
        }

        guard let spriteSheet = UIImage(named: spritesheetName),
              let cgImage = spriteSheet.cgImage
        else { return [] }

        let cellWidth = CGFloat(cgImage.width) / CGFloat(batteryColumns)
        let cellHeight = CGFloat(cgImage.height) / CGFloat(batteryRows)
        var frames: [SKTexture] = []

        for row in 0..<batteryRows {
            for column in 0..<batteryColumns {
                let cell = CGRect(
                    x: CGFloat(column) * cellWidth,
                    y: CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                ).integral

                if let cropped = cgImage.cropping(to: cell) {
                    let image = UIImage(cgImage: cropped, scale: spriteSheet.scale, orientation: spriteSheet.imageOrientation)
                    let texture = SKTexture(image: image)
                    texture.filteringMode = .linear
                    frames.append(texture)
                }
            }
        }

        batteryFrameCache[spritesheetName] = frames
        return frames
    }

    private static func makeSignalStatusFrames(named spritesheetName: String) -> [SKTexture] {
        if let cached = signalStatusFrameCache[spritesheetName] {
            return cached
        }

        guard let spriteSheet = UIImage(named: spritesheetName),
              let cgImage = spriteSheet.cgImage
        else { return [] }

        let cellWidth = CGFloat(cgImage.width) / CGFloat(signalColumns)
        let cellHeight = CGFloat(cgImage.height) / CGFloat(signalRows)
        var frames: [SKTexture] = []

        for row in 0..<signalRows {
            for column in 0..<signalColumns {
                let cell = CGRect(
                    x: CGFloat(column) * cellWidth,
                    y: CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )
                let crop = CGRect(
                    x: cell.minX + cell.width * signalPatchLeftFraction,
                    y: cell.minY + cell.height * signalPatchTopFraction,
                    width: cell.width * signalPatchWidthFraction,
                    height: cell.height * signalPatchHeightFraction
                ).integral

                if let cropped = cgImage.cropping(to: crop) {
                    let image = UIImage(cgImage: cropped, scale: spriteSheet.scale, orientation: spriteSheet.imageOrientation)
                    let texture = SKTexture(image: image)
                    texture.filteringMode = .nearest
                    frames.append(texture)
                }
            }
        }

        signalStatusFrameCache[spritesheetName] = frames
        return frames
    }

    private static func makeIdleFrames(named spritesheetName: String) -> [SKTexture] {
        if let cached = idleFrameCache[spritesheetName] { return cached }

        guard let spriteSheet = UIImage(named: spritesheetName),
              let cgImage = spriteSheet.cgImage
        else { return [] }

        let cellWidth = CGFloat(cgImage.width) / CGFloat(idleColumns)
        let cellHeight = CGFloat(cgImage.height) / CGFloat(idleRows)
        var frames: [SKTexture] = []

        for row in 0..<idleRows {
            for column in 0..<idleColumns {
                let cell = CGRect(
                    x: CGFloat(column) * cellWidth,
                    y: CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                ).integral
                if let cropped = cgImage.cropping(to: cell) {
                    let image = UIImage(cgImage: cropped, scale: spriteSheet.scale, orientation: spriteSheet.imageOrientation)
                    let texture = SKTexture(image: image)
                    texture.filteringMode = .linear
                    frames.append(texture)
                }
            }
        }

        idleFrameCache[spritesheetName] = frames
        return frames
    }

    private func fallbackPhoneArtworkName(for bootupSpritesheetName: String) -> String {
        switch bootupSpritesheetName {
        case "poplur_phone_bootup_champagne_gold":
            return "poplur_bling_phone_02_champagne_gold"
        case "poplur_phone_bootup_rose_gold_pink":
            return "poplur_bling_phone_03_rose_gold_pink"
        case "poplur_phone_bootup_ruby_red":
            return "poplur_bling_phone_04_ruby_red"
        case "poplur_phone_bootup_sapphire_blue":
            return "poplur_bling_phone_05_sapphire_blue"
        case "poplur_phone_bootup_emerald_green":
            return "poplur_bling_phone_06_emerald_green"
        case "poplur_phone_bootup_amethyst_purple":
            return "poplur_bling_phone_07_amethyst_purple"
        case "poplur_phone_bootup_jet_black_onyx":
            return "poplur_bling_phone_08_jet_black_onyx"
        case "poplur_phone_bootup_icy_aqua_turquoise":
            return "poplur_bling_phone_09_icy_aqua_turquoise"
        case "poplur_phone_bootup_holographic_iridescent":
            return "poplur_bling_phone_10_holographic_iridescent"
        default:
            return "poplur_bling_phone_01_silver_diamond"
        }
    }

    private func pressSpritesheetName(for bootupSpritesheetName: String) -> String {
        switch bootupSpritesheetName {
        case "poplur_phone_bootup_champagne_gold":
            return "poplur_phone_press_champagne_gold"
        case "poplur_phone_bootup_rose_gold_pink":
            return "poplur_phone_press_rose_gold_pink"
        case "poplur_phone_bootup_ruby_red":
            return "poplur_phone_press_ruby_red"
        case "poplur_phone_bootup_sapphire_blue":
            return "poplur_phone_press_sapphire_blue"
        case "poplur_phone_bootup_emerald_green":
            return "poplur_phone_press_emerald_green"
        case "poplur_phone_bootup_amethyst_purple":
            return "poplur_phone_press_amethyst_purple"
        case "poplur_phone_bootup_jet_black_onyx":
            return "poplur_phone_press_jet_black_onyx"
        case "poplur_phone_bootup_icy_aqua_turquoise":
            return "poplur_phone_press_icy_aqua_turquoise"
        case "poplur_phone_bootup_holographic_iridescent":
            return "poplur_phone_press_holographic_iridescent"
        default:
            return "poplur_phone_press_silver_diamond"
        }
    }

    private func batterySpritesheetName(for bootupSpritesheetName: String) -> String {
        switch bootupSpritesheetName {
        case "poplur_phone_bootup_champagne_gold":
            return "poplur_phone_battery_02"
        case "poplur_phone_bootup_rose_gold_pink":
            return "poplur_phone_battery_03"
        case "poplur_phone_bootup_ruby_red":
            return "poplur_phone_battery_04"
        case "poplur_phone_bootup_sapphire_blue":
            return "poplur_phone_battery_05"
        case "poplur_phone_bootup_emerald_green":
            return "poplur_phone_battery_06"
        case "poplur_phone_bootup_amethyst_purple":
            return "poplur_phone_battery_07"
        case "poplur_phone_bootup_jet_black_onyx":
            return "poplur_phone_battery_08"
        case "poplur_phone_bootup_icy_aqua_turquoise":
            return "poplur_phone_battery_09"
        case "poplur_phone_bootup_holographic_iridescent":
            return "poplur_phone_battery_10"
        default:
            return "poplur_phone_battery_01"
        }
    }

    private func signalSpritesheetName(for bootupSpritesheetName: String) -> String {
        switch bootupSpritesheetName {
        case "poplur_phone_bootup_champagne_gold":
            return "poplur_phone_signal_champagne_gold"
        case "poplur_phone_bootup_rose_gold_pink":
            return "poplur_phone_signal_rose_gold_pink"
        case "poplur_phone_bootup_ruby_red":
            return "poplur_phone_signal_ruby_red"
        case "poplur_phone_bootup_sapphire_blue":
            return "poplur_phone_signal_sapphire_blue"
        case "poplur_phone_bootup_emerald_green":
            return "poplur_phone_signal_emerald_green"
        case "poplur_phone_bootup_amethyst_purple":
            return "poplur_phone_signal_amethyst_purple"
        case "poplur_phone_bootup_jet_black_onyx":
            return "poplur_phone_signal_jet_black_onyx"
        case "poplur_phone_bootup_icy_aqua_turquoise":
            return "poplur_phone_signal_icy_aqua_turquoise"
        case "poplur_phone_bootup_holographic_iridescent":
            return "poplur_phone_signal_holographic_iridescent"
        default:
            return "poplur_phone_signal_silver_diamond"
        }
    }

    private func startSnakeGame() {
        isSnakeActive = true
        stopIdleSignalAnimation()
        signalStatusNode?.isHidden = true
        batteryStatusNode?.isHidden = true
        childNode(withName: "signal_bg")?.isHidden = true
        childNode(withName: "battery_bg")?.isHidden = true
        menuLayer?.removeFromParent()
        menuLayer = nil
        snakeScore = 0
        snakeDirection = SnakeGridPoint(x: 1, y: 0)
        pendingSnakeDirection = snakeDirection
        snakeBody = [
            SnakeGridPoint(x: 5, y: 5),
            SnakeGridPoint(x: 4, y: 5),
            SnakeGridPoint(x: 3, y: 5)
        ]
        placeSnakeFood()

        screenNode?.removeAction(forKey: "screenPowerUp")
        screenNode?.isHidden = true
        childNode(withName: "lcd_fill")?.isHidden = true
        screenTextLabel?.isHidden = true

        snakeLayer?.removeFromParent()
        let layer = SKNode()
        let screenRect = phoneScreenRect()
        layer.position = CGPoint(x: screenRect.midX, y: screenRect.midY)
        layer.zPosition = 4
        addChild(layer)
        snakeLayer = layer

        redrawSnake()
        runSnakeLoop()
    }

    private func runSnakeLoop() {
        removeAction(forKey: "snakeLoop")
        let tick = SKAction.sequence([
            .wait(forDuration: 0.18),
            .run { [weak self] in self?.advanceSnake() }
        ])
        run(.repeatForever(tick), withKey: "snakeLoop")
    }

    private func handleSnakeButton(_ digit: String) {
        switch digit {
        case "2":
            setSnakeDirection(SnakeGridPoint(x: 0, y: 1))
        case "8":
            setSnakeDirection(SnakeGridPoint(x: 0, y: -1))
        case "4":
            setSnakeDirection(SnakeGridPoint(x: -1, y: 0))
        case "6":
            setSnakeDirection(SnakeGridPoint(x: 1, y: 0))
        case "5":
            startSnakeGame()
        case "*":
            stopSnakeGame()
        default:
            break
        }
    }

    private func setSnakeDirection(_ direction: SnakeGridPoint) {
        guard direction.x + snakeDirection.x != 0 || direction.y + snakeDirection.y != 0 else { return }
        pendingSnakeDirection = direction
    }

    private func advanceSnake() {
        guard isSnakeActive, let head = snakeBody.first else { return }

        snakeDirection = pendingSnakeDirection
        let newHead = SnakeGridPoint(x: head.x + snakeDirection.x, y: head.y + snakeDirection.y)

        guard newHead.x >= 0,
              newHead.x < snakeColumns,
              newHead.y >= 0,
              newHead.y < snakeRows,
              !snakeBody.contains(newHead)
        else {
            showSnakeGameOver()
            return
        }

        snakeBody.insert(newHead, at: 0)
        if newHead == snakeFood {
            snakeScore += 1
            placeSnakeFood()
        } else {
            snakeBody.removeLast()
        }

        redrawSnake()
    }

    private func stopSnakeGame() {
        isSnakeActive = false
        removeAction(forKey: "snakeLoop")
        snakeLayer?.removeFromParent()
        snakeLayer = nil
        screenNode?.isHidden = false
        childNode(withName: "lcd_fill")?.isHidden = false
        screenTextLabel?.isHidden = false
        updateSignalStatusVisibility()
        showPhoneMenu(.games)
        scheduleNextIdleSignalAnimation()
    }

    private func showSnakeGameOver() {
        removeAction(forKey: "snakeLoop")
        redrawSnake(gameOver: true)
    }

    private func placeSnakeFood() {
        let available = (0..<snakeColumns).flatMap { x in
            (0..<snakeRows).map { y in SnakeGridPoint(x: x, y: y) }
        }.filter { !snakeBody.contains($0) }
        snakeFood = available.randomElement() ?? SnakeGridPoint(x: 10, y: 5)
    }

    private func redrawSnake(gameOver: Bool = false) {
        guard let snakeLayer else { return }
        snakeLayer.removeAllChildren()

        let screenSize = phoneScreenRect().size
        let background = SKShapeNode(rectOf: screenSize, cornerRadius: screenSize.width * screenCornerRadiusFraction)
        background.fillColor = phoneScreenColor
        background.strokeColor = UIColor(red: 0.10, green: 0.18, blue: 0.10, alpha: 1.0)
        background.lineWidth = max(1, screenSize.height * 0.008)
        background.zPosition = 0
        snakeLayer.addChild(background)

        let cellWidth = screenSize.width / CGFloat(snakeColumns)
        let cellHeight = screenSize.height / CGFloat(snakeRows)

        func nodePosition(for point: SnakeGridPoint) -> CGPoint {
            CGPoint(
                x: -screenSize.width / 2 + CGFloat(point.x) * cellWidth + cellWidth / 2,
                y: -screenSize.height / 2 + CGFloat(point.y) * cellHeight + cellHeight / 2
            )
        }

        let foodNode = SKShapeNode(rectOf: CGSize(width: cellWidth * 0.78, height: cellHeight * 0.78), cornerRadius: 2)
        foodNode.fillColor = UIColor(red: 0.12, green: 0.18, blue: 0.08, alpha: 1.0)
        foodNode.strokeColor = .clear
        foodNode.position = nodePosition(for: snakeFood)
        foodNode.zPosition = 2
        snakeLayer.addChild(foodNode)

        for (index, point) in snakeBody.enumerated() {
            let segment = SKShapeNode(rectOf: CGSize(width: cellWidth * 0.82, height: cellHeight * 0.82), cornerRadius: 2)
            segment.fillColor = index == 0
                ? UIColor(red: 0.05, green: 0.10, blue: 0.04, alpha: 1.0)
                : UIColor(red: 0.09, green: 0.16, blue: 0.06, alpha: 1.0)
            segment.strokeColor = .clear
            segment.position = nodePosition(for: point)
            segment.zPosition = 3
            snakeLayer.addChild(segment)
        }

        let scoreLabel = SKLabelNode(text: gameOver ? "GAME OVER  5=RETRY  *=EXIT" : "SNAKE \(snakeScore)")
        scoreLabel.fontName = "Menlo-Bold"
        scoreLabel.fontSize = gameOver ? screenSize.height * 0.047 : screenSize.height * 0.064
        scoreLabel.fontColor = lcdDarkColor
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: 0, y: screenSize.height / 2 - 16)
        scoreLabel.blendMode = .alpha
        scoreLabel.zPosition = 5
        snakeLayer.addChild(scoreLabel)
    }

    private func keyLabel(for digit: String) -> String {
        switch digit {
        case "1": return "1∞"
        case "2": return "2abc"
        case "3": return "3def"
        case "4": return "4ghi"
        case "5": return "5jkl"
        case "6": return "6mno"
        case "7": return "7pqrs"
        case "8": return "8tuv"
        case "9": return "9wxyz"
        case "*": return "* +"
        case "0": return "0.-"
        case "#": return "⇧ #"
        default: return digit
        }
    }

    // MARK: - Call state display on LCD

    /// Called by PopularPhone whenever CallSessionManager.callState or
    /// elapsedSeconds changes. Updates the LCD screen to show call status.
    func applyCallState(_ state: CallState, elapsed: Int) {
        switch state {
        case .idle:
            stopRingtone()
            clearCallStatus()
        case .outgoing(let calleeName):
            startRingtone()
            showCallStatus("CALLING\n\(calleeName.uppercased())", pulsing: true)
        case .incoming(let callerName, _, _):
            startRingtone()
            showCallStatus("INCOMING\n\(callerName.uppercased())", pulsing: true)
        case .connected(let calleeName, _):
            stopRingtone()
            let duration = CallSessionManager.formattedDuration(elapsed)
            showCallStatus("\(calleeName.uppercased())\n\(duration)", pulsing: false)
        case .ended(let reason):
            stopRingtone()
            let msg: String
            switch reason {
            case .hangUp:   msg = "CALL ENDED"
            case .declined: msg = "DECLINED"
            case .noAnswer: msg = "NO ANSWER"
            }
            showCallStatus(msg, pulsing: false)
        }
    }

    private func showCallStatus(_ text: String, pulsing: Bool) {
        stopIdleSignalAnimation()
        signalStatusNode?.isHidden = true
        batteryStatusNode?.isHidden = true
        childNode(withName: "signal_bg")?.isHidden = true
        childNode(withName: "battery_bg")?.isHidden = true
        screenTextLabel?.isHidden = true
        menuLayer?.isHidden = true
        snakeLayer?.isHidden = true

        let screenRect = phoneScreenRect()

        if callStatusLabel == nil {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.numberOfLines = 2
            label.preferredMaxLayoutWidth = screenRect.width * 0.88
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: screenRect.midX, y: screenRect.midY)
            label.zPosition = 6
            addChild(label)
            callStatusLabel = label
        }

        callStatusLabel?.isHidden = false
        callStatusLabel?.text = text
        callStatusLabel?.fontColor = lcdDarkColor
        callStatusLabel?.fontSize = screenRect.height * 0.14
        callStatusLabel?.blendMode = .alpha

        callStatusLabel?.removeAction(forKey: "pulse")
        if pulsing {
            let pulse = SKAction.repeatForever(.sequence([
                .fadeAlpha(to: 0.28, duration: 0.55),
                .fadeAlpha(to: 1.00, duration: 0.55)
            ]))
            callStatusLabel?.run(pulse, withKey: "pulse")
        } else {
            callStatusLabel?.alpha = 1.0
        }
    }

    private func clearCallStatus() {
        callStatusLabel?.removeAction(forKey: "pulse")
        callStatusLabel?.isHidden = true
        screenTextLabel?.isHidden = false
        snakeLayer?.isHidden = false
        if !isSnakeActive {
            menuLayer?.isHidden = false
        }
        updateSignalStatusVisibility()
        scheduleNextIdleSignalAnimation()
    }

    private static let screenColumns = 5
    private static let screenRows = 8
    private static let bootupColumns = 4
    private static let bootupRows = 4
    private static let pressColumns = 4
    private static let pressRows = 4
    private static let signalColumns = 4
    private static let signalRows = 4
    private static let batteryColumns = 4
    private static let batteryRows = 4
    private static let idleColumns = 4
    private static let idleRows = 2
    private static let phoneHorizontalInsetFraction: CGFloat = 0.0
    private static let bootupFallbackDuration: TimeInterval = 1.8
    private static var bootupFrameCache: [String: [SKTexture]] = [:]
    private static var pressFrameCache: [String: [SKTexture]] = [:]
    private static var batteryFrameCache: [String: [SKTexture]] = [:]
    private static var signalStatusFrameCache: [String: [SKTexture]] = [:]
    private static var idleFrameCache: [String: [SKTexture]] = [:]
    private let phoneAspectRatio: CGFloat = 1024.0 / 1536.0
    private let screenLeftFraction: CGFloat = 0.240
    private let screenTopFraction: CGFloat = 0.183
    private let screenWidthFraction: CGFloat = 0.520
    private let screenHeightFraction: CGFloat = 0.245
    private let screenCornerRadiusFraction: CGFloat = 0.040
    private var phoneYellow: UIColor {
        UIColor(red: 0.91, green: 0.96, blue: 0.04, alpha: 1.0)
    }
    private var phoneScreenColor: UIColor {
        UIColor(red: 0.9372549, green: 0.94509804, blue: 0.0, alpha: 1.0)
    }
    private var lcdDarkColor: UIColor {
        UIColor(red: 0.03, green: 0.16, blue: 0.01, alpha: 1.0)
    }
    private var keyGlowGreen: UIColor {
        UIColor(red: 0.31, green: 1.0, blue: 0.28, alpha: 1.0)
    }
    private var lcdGlowGreen: UIColor {
        UIColor(red: 0.20, green: 1.0, blue: 0.18, alpha: 1.0)
    }
    private static let spriteCropLeftFraction: CGFloat = 0.118
    private static let spriteCropTopFraction: CGFloat = 0.12
    private static let spriteCropWidthFraction: CGFloat = 0.79
    private static let spriteCropHeightFraction: CGFloat = 0.69
    private static let signalPatchLeftFraction: CGFloat = 0.265
    private static let signalPatchTopFraction: CGFloat = 0.195
    private static let signalPatchWidthFraction: CGFloat = 0.135
    private static let signalPatchHeightFraction: CGFloat = 0.058
    // Battery: mirrored to top-right of LCD (symmetric with signal at top-left)
    private static let batteryPatchLeftFraction: CGFloat = 0.600
    private static let batteryPatchTopFraction: CGFloat = 0.195
    private static let batteryPatchWidthFraction: CGFloat = 0.135
    private static let batteryPatchHeightFraction: CGFloat = 0.058
}

private struct SnakeGridPoint: Equatable {
    let x: Int
    let y: Int
}
