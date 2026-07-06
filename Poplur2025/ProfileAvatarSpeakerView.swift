import SwiftUI
import SpriteKit
import SceneKit
import AVFoundation

// MARK: - ProfileAvatarSpeakerView

struct ProfileAvatarSpeakerView: View {
    let profileImage: UIImage?
    let profileImageURL: URL?
    let totalRadiusKM: Double
    let postCount: Int
    let size: CGFloat
    let skin: CubeSkin

    @State private var isSpeaking = false
    @State private var speakText: String?
    @State private var headLoaded = false
    @State private var placeholderPulse = false

    var body: some View {
        let theme = skin.appTheme
        let palette = skin.profileHeadPalette
        ZStack(alignment: .bottom) {
            ZStack {
                if palette.hasHalo {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [palette.accent.opacity(0.95), palette.accent2.opacity(0.74)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(2, size * 0.035)
                        )
                        .frame(width: size * 0.98, height: size * 0.98)
                        .shadow(color: palette.glow, radius: size * 0.18)
                }
                if !headLoaded {
                    Circle()
                        .fill(palette.accent.opacity(placeholderPulse ? 0.22 : 0.10))
                        .frame(width: size * 0.72, height: size * 0.72)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: placeholderPulse)
                        .onAppear { placeholderPulse = true }
                }
                MarkHeadView(speakText: $speakText, onFinished: {
                    isSpeaking = false
                    speakText = nil
                }, onLoaded: {
                    withAnimation(.easeIn(duration: 0.4)) { headLoaded = true }
                })
                .frame(width: size * 1.12, height: size * 1.20)
                .opacity(headLoaded ? 1 : 0)
                if isSpeaking {
                    SpeechBubble(color: palette.accent)
                        .frame(width: size * 0.46, height: size * 0.34)
                        .offset(x: size * 0.54, y: -size * 0.28)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: size * 1.42, height: size * 1.28)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.20, style: .continuous)
                    .strokeBorder(
                        palette.accent.opacity(isSpeaking ? 0.92 : 0.54),
                        lineWidth: isSpeaking ? 3 : 1.5
                    )
                    .shadow(color: palette.accent.opacity(isSpeaking ? 0.75 : 0), radius: isSpeaking ? 14 : 0)
                    .animation(.easeInOut(duration: 0.22), value: isSpeaking)
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.76), value: isSpeaking)
            .onTapGesture { speakStats() }

            if isSpeaking {
                speakingIndicator.offset(y: 8)
            } else {
                Button {
                    triggerWake()
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.accent.opacity(0.90))
                        .padding(5)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .offset(y: 8)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PoplurWakeDetected"))) { _ in
            triggerWake()
        }
    }

    private func triggerWake() {
        guard !isSpeaking else { return }
        isSpeaking = true
        speakText = "Hey! I'm here and listening."
    }

    private var speakingIndicator: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                SpeakBarView(delay: Double(i) * 0.07)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
    }

    private func speakStats() {
        guard !isSpeaking else { stopSpeaking(); return }
        let km = totalRadiusKM < 1 ? "\(Int(totalRadiusKM * 1000)) meters" : String(format: "%.1f kilometres", totalRadiusKM)
        isSpeaking = true
        speakText = "You have \(postCount) posts and your total radius is \(km)."
    }

    private func stopSpeaking() {
        speakText = nil
        isSpeaking = false
    }
}

// MARK: - Profile Head Palette

private struct ProfileHeadPalette {
    let fill: Color
    let face: Color
    let line: Color
    let accent: Color
    let accent2: Color
    let glow: Color
    let hair: Color
    let shirt: Color
    let isToy: Bool
    let hasHalo: Bool
}

private extension CubeSkin {
    var profileHeadPalette: ProfileHeadPalette {
        let theme = appTheme
        switch self {
        case .toy:
            return ProfileHeadPalette(
                fill: Color(red: 1.0, green: 0.74, blue: 0.48),
                face: Color(red: 1.0, green: 0.74, blue: 0.52),
                line: Color(red: 0.08, green: 0.16, blue: 0.38),
                accent: theme.accent,
                accent2: theme.accent2,
                glow: Color(red: 1.0, green: 0.74, blue: 0.05).opacity(0.34),
                hair: Color(red: 0.32, green: 0.16, blue: 0.06),
                shirt: Color(red: 0.06, green: 0.22, blue: 0.66),
                isToy: true,
                hasHalo: true
            )
        case .chocolate:
            return ProfileHeadPalette(
                fill: Color(red: 0.38, green: 0.16, blue: 0.05),
                face: Color(red: 0.48, green: 0.22, blue: 0.08),
                line: Color(red: 1.0, green: 0.78, blue: 0.54),
                accent: theme.accent,
                accent2: theme.accent2,
                glow: theme.shadow,
                hair: Color(red: 0.20, green: 0.08, blue: 0.02),
                shirt: Color(red: 0.26, green: 0.11, blue: 0.03),
                isToy: false,
                hasHalo: true
            )
        case .camo:
            return ProfileHeadPalette(
                fill: Color(red: 0.20, green: 0.23, blue: 0.12),
                face: Color(red: 0.26, green: 0.28, blue: 0.16),
                line: Color(red: 0.88, green: 0.80, blue: 0.38),
                accent: theme.accent,
                accent2: theme.accent2,
                glow: theme.shadow,
                hair: Color(red: 0.11, green: 0.14, blue: 0.07),
                shirt: Color(red: 0.13, green: 0.17, blue: 0.09),
                isToy: false,
                hasHalo: true
            )
        case .ice:
            return ProfileHeadPalette(
                fill: Color(red: 0.04, green: 0.28, blue: 0.48),
                face: Color(red: 0.06, green: 0.42, blue: 0.72),
                line: Color(red: 0.82, green: 0.96, blue: 1.0),
                accent: theme.accent,
                accent2: theme.accent2,
                glow: Color(red: 0.42, green: 0.86, blue: 1.0).opacity(0.54),
                hair: Color(red: 0.40, green: 0.78, blue: 1.0),
                shirt: Color(red: 0.02, green: 0.20, blue: 0.36),
                isToy: false,
                hasHalo: false
            )
        case .sparklePink:
            return ProfileHeadPalette(
                fill: Color(red: 0.50, green: 0.02, blue: 0.32),
                face: Color(red: 0.84, green: 0.10, blue: 0.62),
                line: Color.white.opacity(0.92),
                accent: theme.accent,
                accent2: theme.accent2,
                glow: theme.shadow,
                hair: Color(red: 0.18, green: 0.00, blue: 0.12),
                shirt: Color(red: 0.26, green: 0.02, blue: 0.20),
                isToy: false,
                hasHalo: false
            )
        case .rainbow:
            return ProfileHeadPalette(
                fill: Color(red: 0.06, green: 0.08, blue: 0.20),
                face: Color(red: 0.92, green: 0.52, blue: 0.46),
                line: .white,
                accent: Color(red: 0.16, green: 0.95, blue: 1.0),
                accent2: Color(red: 1.0, green: 0.20, blue: 0.90),
                glow: Color(red: 0.18, green: 0.90, blue: 1.0).opacity(0.45),
                hair: Color(red: 0.14, green: 0.02, blue: 0.22),
                shirt: Color(red: 0.03, green: 0.08, blue: 0.24),
                isToy: false,
                hasHalo: false
            )
        case .gold:
            return ProfileHeadPalette(
                fill: Color(red: 0.58, green: 0.40, blue: 0.06),
                face: Color(red: 0.84, green: 0.64, blue: 0.18),
                line: Color(red: 1.0, green: 0.94, blue: 0.58),
                accent: theme.accent,
                accent2: theme.accent2,
                glow: theme.shadow,
                hair: Color(red: 0.38, green: 0.24, blue: 0.04),
                shirt: Color(red: 0.18, green: 0.13, blue: 0.04),
                isToy: false,
                hasHalo: true
            )
        case .standard, .rubber:
            return ProfileHeadPalette(
                fill: Color(red: 0.07, green: 0.06, blue: 0.09),
                face: Color(red: 0.12, green: 0.10, blue: 0.16),
                line: Color.white.opacity(0.92),
                accent: theme.accent,
                accent2: theme.accent2,
                glow: theme.shadow,
                hair: Color(red: 0.24, green: 0.06, blue: 0.44),
                shirt: Color(red: 0.05, green: 0.05, blue: 0.07),
                isToy: false,
                hasHalo: false
            )
        }
    }
}

private struct SpeechBubble: View {
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color, lineWidth: 2)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.18)))
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(color).frame(width: 5, height: 5)
                }
            }
        }
    }
}

// MARK: - Pixel Head 2D (SpriteKit Canvas)

struct PixelHead2DView: UIViewRepresentable {
    let profileImage: UIImage?
    let profileImageURL: URL?
    @Binding var isSpeaking: Bool
    let size: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SKView {
        let v = SKView()
        v.backgroundColor = .clear
        v.allowsTransparency = true
        v.ignoresSiblingOrder = true
        v.isUserInteractionEnabled = false
        v.preferredFramesPerSecond = 30
        let sceneSize = CGSize(width: size, height: size * 1.25)
        let scene = PixelHead2DScene(size: sceneSize)
        scene.backgroundColor = .clear; scene.scaleMode = .aspectFit
        v.presentScene(scene)
        context.coordinator.scene = scene
        scene.buildTalkingHead()
        return v
    }

    func updateUIView(_ v: SKView, context: Context) {
        context.coordinator.setSpeaking(isSpeaking)
    }

    static func dismantleUIView(_ uiView: SKView, coordinator: Coordinator) {
        coordinator.scene?.tearDown()
        coordinator.scene = nil
        uiView.presentScene(nil)
    }

    class Coordinator {
        var scene: PixelHead2DScene?
        private var lastSpeaking = false

        func setSpeaking(_ speaking: Bool) {
            guard speaking != lastSpeaking else { return }
            lastSpeaking = speaking
            speaking ? scene?.startSpeaking() : scene?.stopSpeaking()
        }
    }
}

// MARK: - 2D Talking Head Scene

final class PixelHead2DScene: SKScene {
    private let frameNames = (1...12).map { String(format: "profile_talking_head_%02d", $0) }
    private lazy var textures: [SKTexture] = frameNames.map {
        let texture = SKTexture(imageNamed: $0)
        texture.filteringMode = .linear
        return texture
    }
    private var headSprite: SKSpriteNode?
    private var glowNode: SKShapeNode?

    func buildTalkingHead() {
        removeAllChildren()
        guard let first = textures.first else { return }

        let glowRect = CGRect(
            x: size.width * 0.05,
            y: size.height * 0.08,
            width: size.width * 0.90,
            height: size.height * 0.76
        )
        let glow = SKShapeNode(ellipseIn: glowRect)
        glow.strokeColor = UIColor.white.withAlphaComponent(0.26)
        glow.lineWidth = 2
        glow.fillColor = .clear
        glow.alpha = 0
        addChild(glow)
        glowNode = glow

        let sprite = SKSpriteNode(texture: first)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.zPosition = 1
        sprite.setScale(fitScale(for: first))
        addChild(sprite)
        headSprite = sprite
        runIdleLoop()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard let texture = headSprite?.texture else { return }
        headSprite?.position = CGPoint(x: size.width / 2, y: size.height / 2)
        headSprite?.setScale(fitScale(for: texture))
    }

    func startSpeaking() {
        guard let headSprite else { return }
        guard headSprite.action(forKey: "talkingFace") == nil else { return }
        glowNode?.removeAllActions()
        glowNode?.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.86, duration: 0.16),
            SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.42, duration: 0.34),
                SKAction.fadeAlpha(to: 0.86, duration: 0.34)
            ]))
        ]), withKey: "talkGlow")

        headSprite.removeAction(forKey: "idleFace")
        let talking = [3, 4, 12, 1, 3, 4, 10, 1].compactMap { texture(number: $0) }
        headSprite.run(
            SKAction.repeatForever(SKAction.animate(with: talking, timePerFrame: 0.085, resize: false, restore: false)),
            withKey: "talkingFace"
        )
    }

    func stopSpeaking() {
        guard headSprite?.action(forKey: "talkingFace") != nil else {
            runIdleLoop()
            return
        }
        glowNode?.removeAction(forKey: "talkGlow")
        glowNode?.run(SKAction.fadeAlpha(to: 0, duration: 0.18))
        headSprite?.removeAction(forKey: "talkingFace")
        headSprite?.texture = texture(number: 1)
        runIdleLoop()
    }

    func tearDown() {
        removeAllActions()
        children.forEach { $0.removeAllActions() }
        removeAllChildren()
        headSprite = nil
        glowNode = nil
    }

    private func runIdleLoop() {
        guard let headSprite, headSprite.action(forKey: "idleFace") == nil else { return }
        let neutral = SKAction.setTexture(texture(number: 1), resize: false)
        let sequence = SKAction.sequence([
            neutral,
            .wait(forDuration: 1.15),
            .setTexture(texture(number: 7), resize: false),
            .wait(forDuration: 0.18),
            neutral,
            .wait(forDuration: 1.45),
            .setTexture(texture(number: 2), resize: false),
            .wait(forDuration: 0.32),
            neutral,
            .wait(forDuration: 1.25),
            .setTexture(texture(number: 5), resize: false),
            .wait(forDuration: 0.28),
            .setTexture(texture(number: 10), resize: false),
            .wait(forDuration: 0.20),
            neutral,
            .wait(forDuration: 1.65),
            .setTexture(texture(number: 9), resize: false),
            .wait(forDuration: 0.22),
            neutral,
            .wait(forDuration: 1.05)
        ])
        headSprite.run(.repeatForever(sequence), withKey: "idleFace")
    }

    private func texture(number: Int) -> SKTexture {
        let index = min(max(number - 1, 0), textures.count - 1)
        return textures[index]
    }

    private func fitScale(for texture: SKTexture) -> CGFloat {
        let textureSize = texture.size()
        guard textureSize.width > 0, textureSize.height > 0 else { return 1 }
        let maxWidth = size.width * 0.96
        let maxHeight = size.height * 0.98
        return min(maxWidth / textureSize.width, maxHeight / textureSize.height)
    }
}

// MARK: - Pixel Head 3D (SceneKit Voxels)

struct PixelHead3DView: UIViewRepresentable {
    let profileImage: UIImage?
    let profileImageURL: URL?
    @Binding var isSpeaking: Bool
    let size: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear; v.allowsCameraControl = false
        v.autoenablesDefaultLighting = false
        v.antialiasingMode = .multisampling4X

        let scene = SCNScene(); v.scene = scene

        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 52
        cam.position = SCNVector3(0, 0, 3.2)
        scene.rootNode.addChildNode(cam)

        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light?.type = .ambient; ambient.light?.intensity = 800
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode(); key.light = SCNLight()
        key.light?.type = .directional; key.light?.intensity = 1200
        key.eulerAngles = SCNVector3(-0.5, 0.4, 0)
        scene.rootNode.addChildNode(key)

        context.coordinator.scene = scene
        context.coordinator.v = v
        Task { await context.coordinator.loadImage(url: profileImageURL, fallback: profileImage) }
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        context.coordinator.setSpeaking(isSpeaking)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.stopSpeaking()
        coordinator.scene = nil
        uiView.scene = nil
    }

    class Coordinator {
        var scene: SCNScene?
        weak var v: SCNView?
        var headRoot: SCNNode?
        var mouthNodes: [SCNNode] = []
        var mouthTimer: Timer?
        private var lastSpeaking = false

        func loadImage(url: URL?, fallback: UIImage?) async {
            var img = fallback
            if let url, let (data, _) = try? await URLSession.shared.data(from: url) {
                img = UIImage(data: data) ?? fallback
            }
            let cols = 16, rows = 16
            let grid = img.map { pixelGrid(from: $0, cols: cols, rows: rows) } ?? defaultGrid(cols: cols, rows: rows)
            await MainActor.run { buildVoxels(grid, cols: cols, rows: rows) }
        }

        private func buildVoxels(_ grid: [[UIColor]], cols: Int, rows: Int) {
            headRoot?.removeFromParentNode()
            mouthNodes = []

            let root = SCNNode(); scene?.rootNode.addChildNode(root)
            headRoot = root

            let voxelSize: Float = 0.135
            let gap: Float = 0.005
            let step = voxelSize + gap
            let offX = -Float(cols) * step / 2
            let offY = -Float(rows) * step / 2

            for row in 0..<rows {
                for col in 0..<cols {
                    let color = grid[row][col]
                    if color.isTransparent { continue }
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    color.getRed(&r, green: &g, blue: &b, alpha: &a)
                    let brightness = Float(r * 0.299 + g * 0.587 + b * 0.114)
                    let depth = 0.04 + brightness * 0.10

                    let box = SCNBox(width: CGFloat(voxelSize), height: CGFloat(voxelSize),
                                    length: CGFloat(depth), chamferRadius: 0.01)
                    box.firstMaterial?.diffuse.contents = color
                    box.firstMaterial?.lightingModel = .phong
                    box.firstMaterial?.specular.contents = UIColor.white
                    box.firstMaterial?.shininess = 12

                    let node = SCNNode(geometry: box)
                    node.position = SCNVector3(
                        offX + Float(col) * step + voxelSize/2,
                        offY + Float(row) * step + voxelSize/2,
                        0
                    )
                    root.addChildNode(node)

                    // Tag mouth row nodes
                    let mouthRow = rows - 6
                    let isMouthCol = col >= cols/4 && col <= cols - cols/4
                    if row == mouthRow && isMouthCol { mouthNodes.append(node) }
                }
            }

            // Float animation
            let up = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: 1.4)
            let dn = SCNAction.moveBy(x: 0, y: -0.06, z: 0, duration: 1.4)
            up.timingMode = .easeInEaseOut; dn.timingMode = .easeInEaseOut
            root.runAction(SCNAction.repeatForever(.sequence([up, dn])))

            // Gentle Y-axis wobble
            let rotL = SCNAction.rotateBy(x: 0, y: 0.12, z: 0, duration: 2.0)
            let rotR = SCNAction.rotateBy(x: 0, y: -0.12, z: 0, duration: 2.0)
            rotL.timingMode = .easeInEaseOut; rotR.timingMode = .easeInEaseOut
            root.runAction(SCNAction.repeatForever(.sequence([rotL, rotR])))
        }

        func setSpeaking(_ speaking: Bool) {
            guard speaking != lastSpeaking else { return }
            lastSpeaking = speaking
            speaking ? startSpeaking() : stopSpeaking()
        }

        func startSpeaking() {
            headRoot?.geometry?.firstMaterial?.emission.contents = UIColor(white: 0.15, alpha: 1)
            var open = false
            mouthTimer?.invalidate()
            mouthTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
                guard let self else { return }
                open.toggle()
                let targetZ: Float = open ? 0.14 : 0.04
                for node in self.mouthNodes {
                    if let box = node.geometry as? SCNBox {
                        SCNTransaction.begin()
                        SCNTransaction.animationDuration = 0.10
                        box.firstMaterial?.diffuse.contents = open ? UIColor.black : box.firstMaterial?.diffuse.contents
                        node.scale = SCNVector3(1, open ? 1 : 0.3, targetZ / max(Float(box.length), 0.01))
                        SCNTransaction.commit()
                    }
                }
            }
        }

        func stopSpeaking() {
            mouthTimer?.invalidate(); mouthTimer = nil
            for node in mouthNodes {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.15
                node.scale = SCNVector3(1, 0.3, 1)
                SCNTransaction.commit()
            }
        }
    }
}

// MARK: - Pixel sampling helpers

func pixelGrid(from image: UIImage, cols: Int, rows: Int) -> [[UIColor]] {
    let targetSize = CGSize(width: cols, height: rows)
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    let tiny = renderer.image { ctx in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
    guard let cgImg = tiny.cgImage,
          let data = cgImg.dataProvider?.data,
          let ptr = CFDataGetBytePtr(data) else {
        return defaultGrid(cols: cols, rows: rows)
    }
    let bytesPerPixel = cgImg.bitsPerPixel / 8
    var grid: [[UIColor]] = []
    for row in 0..<rows {
        var rowColors: [UIColor] = []
        for col in 0..<cols {
            let offset = (row * cols + col) * bytesPerPixel
            let r = CGFloat(ptr[offset]) / 255
            let g = CGFloat(ptr[offset + 1]) / 255
            let b = CGFloat(ptr[offset + 2]) / 255
            let a = bytesPerPixel > 3 ? CGFloat(ptr[offset + 3]) / 255 : CGFloat(1)
            rowColors.append(UIColor(red: r, green: g, blue: b, alpha: a < 0.1 ? 0 : 1))
        }
        grid.append(rowColors)
    }
    return grid
}

func defaultGrid(cols: Int = 20, rows: Int = 20) -> [[UIColor]] {
    (0..<rows).map { row in
        (0..<cols).map { col in
            let cx = cols / 2, cy = rows / 2
            let dx = col - cx, dy = row - cy
            let r = Int(sqrt(Double(dx*dx + dy*dy)))
            return r < cols/2 - 2 ? UIColor(red: 0.6, green: 0.45, blue: 0.35, alpha: 1) : .clear
        }
    }
}

private extension UIColor {
    var isTransparent: Bool {
        var a: CGFloat = 0; getWhite(nil, alpha: &a); return a < 0.05
    }
}

// MARK: - Speak Bar

private struct SpeakBarView: View {
    let delay: Double
    @State private var h: CGFloat = 4
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.85))
            .frame(width: 3, height: h)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.38).repeatForever(autoreverses: true).delay(delay)) { h = 16 }
            }
    }
}

