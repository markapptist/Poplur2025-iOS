import SpriteKit
import AVFoundation

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
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
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
        "*": (941, 1209), "0": (941, 1336), "#": (941, 1477)
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

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        setupPhone()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard oldSize != size, view != nil else { return }
        setupPhone()
    }

    private func setupPhone() {
        removeAllChildren()
        removeAction(forKey: "snakeLoop")
        dialButtons.removeAll()
        screenNode = nil
        screenTextLabel = nil
        callStatusLabel = nil
        snakeLayer = nil
        menuLayer = nil

        let layer = SKNode()
        layer.zPosition = 0
        addChild(layer)
        phoneLayer = layer
        phoneFrame = fittedPhoneFrame(in: size)

        addPhoneArtwork(to: layer)
        screenFrames = []
        setupAnimatedScreen()
        setupDialPad()
        setupCallButton()
        showPhoneMenu(.main)

        if isSnakeActive {
            startSnakeGame()
        }
    }

    private func setupAnimatedScreen() {
        let screenRect = phoneScreenRect()
        let node = SKSpriteNode(texture: roundedLCDTexture(size: screenRect.size), color: .clear, size: screenRect.size)

        node.position = CGPoint(x: screenRect.midX, y: screenRect.midY)
        node.zPosition = 2
        screenNode = node
        addChild(node)

        setupScreenText()
    }

    private func fittedPhoneFrame(in container: CGSize) -> CGRect {
        let aspect = phoneAspectRatio

        let widthFromHeight = container.height * aspect
        let phoneWidth = max(container.width, widthFromHeight)
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
        let phone = SKSpriteNode(imageNamed: "phone_body")
        phone.position = CGPoint(x: phoneFrame.midX, y: phoneFrame.midY)
        phone.size = phoneFrame.size
        phone.zPosition = 0
        phone.shader = makePlasticShader()
        layer.addChild(phone)
    }

    private func makePlasticShader() -> SKShader {
        let source = """
        void main() {
            vec4 tex = texture2D(u_texture, v_tex_coord);
            vec2 uv   = v_tex_coord;

            // ---- Button UV mask ----
            // Keypad: xCenters [0.28,0.50,0.72], yCentersFromTop [0.683,0.758,0.833,0.908]
            // UV y = 1.0 - yFromTop. Half-extents with margin: bw=0.11, bh=0.040
            float bw = 0.11; float bh = 0.040;
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
            // Nav: centre (0.50, 0.503), left (0.235, 0.503), right (0.765, 0.503)
            dx=(uv.x-0.50)/0.170; dy=(uv.y-0.503)/0.052; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.235)/0.100; dy=(uv.y-0.503)/0.050; isButton=max(isButton,step(dx*dx+dy*dy,1.0));
            dx=(uv.x-0.765)/0.100; dy=(uv.y-0.503)/0.050; isButton=max(isButton,step(dx*dx+dy*dy,1.0));

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

            // ---- Glitter sparkle (twinkling gold flecks on body, animated) ----
            float sparkle, h1, h2, h3, speed, phase, twinkle, sparkDist;
            vec2 nb, sparkPos;
            sparkle = 0.0;
            float cellSize = 0.065;
            vec2 cellI = floor(uv / cellSize);
            for (int sx = -1; sx <= 1; sx++) {
                for (int sy = -1; sy <= 1; sy++) {
                    nb = cellI + vec2(float(sx), float(sy));
                    h1 = fract(sin(dot(nb, vec2(127.1, 311.7))) * 43758.545);
                    h2 = fract(sin(dot(nb, vec2(269.5, 183.3))) * 53778.725);
                    h3 = fract(sin(dot(nb, vec2(73.1,  451.7))) * 83738.245);
                    sparkPos = (nb + vec2(h1, h2)) * cellSize;
                    speed = 1.8 + h3 * 4.5;
                    phase = h3 * 6.28318;
                    twinkle = pow(max(0.0, sin(u_time * speed + phase)), 10.0);
                    sparkDist = length(uv - sparkPos);
                    sparkle = max(sparkle, twinkle * smoothstep(0.022, 0.002, sparkDist));
                }
            }
            sparkle *= holeMask * (1.0 - isButton);
            bodyColor += vec3(sparkle * 1.4, sparkle * 1.1, sparkle * 0.5);

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

    private func roundedLCDTexture(size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let radius = size.width * screenCornerRadiusFraction
            let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
            phoneScreenColor.setFill()
            path.fill()
        }
        return SKTexture(image: image)
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
        let xCenters: [CGFloat] = [0.28, 0.50, 0.72]
        let yCentersFromTop: [CGFloat] = [0.683, 0.758, 0.833, 0.908]

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
        let callRect = rectFromTop(x: 0.335, y: 0.452, width: 0.33, height: 0.09)
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
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
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
        // Visual feedback
        let scaleDown = SKAction.scale(to: 0.85, duration: 0.1)
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
        let sequence = SKAction.sequence([scaleDown, scaleUp])
        button.run(sequence)

        // Play dial tone
        playDialTone(for: digit)

        if isSnakeActive {
            handleSnakeButton(digit)
            return
        }

        if handleMenuDigit(digit) {
            return
        }

        appendDialedDigit(digit)
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

    private func startSnakeGame() {
        isSnakeActive = true
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
        screenTextLabel?.isHidden = false
        showPhoneMenu(.games)
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
            clearCallStatus()
        case .outgoing(let calleeName):
            showCallStatus("CALLING\n\(calleeName.uppercased())", pulsing: true)
        case .incoming(let callerName, _, _):
            showCallStatus("INCOMING\n\(callerName.uppercased())", pulsing: true)
        case .connected(let calleeName, _):
            let duration = CallSessionManager.formattedDuration(elapsed)
            showCallStatus("\(calleeName.uppercased())\n\(duration)", pulsing: false)
        case .ended(let reason):
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
    }

    private static let screenColumns = 5
    private static let screenRows = 8
    private let phoneAspectRatio: CGFloat = 1024.0 / 1536.0
    private let screenLeftFraction: CGFloat = 0.205
    private let screenTopFraction: CGFloat = 0.145
    private let screenWidthFraction: CGFloat = 0.590
    private let screenHeightFraction: CGFloat = 0.235
    private let screenCornerRadiusFraction: CGFloat = 0.045
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
}

private struct SnakeGridPoint: Equatable {
    let x: Int
    let y: Int
}
