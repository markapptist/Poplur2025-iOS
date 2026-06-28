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

    @AppStorage("poplur_profileAvatarIs3D") private var is3D = false
    @State private var isSpeaking = false
    @State private var synth = AVSpeechSynthesizer()
    @State private var speechDelegate: ProfileSpeechDelegate?

    var body: some View {
        ZStack(alignment: .bottom) {
            if is3D {
                PixelHead3DView(profileImage: profileImage, profileImageURL: profileImageURL,
                                isSpeaking: $isSpeaking, size: size)
                    .frame(width: size, height: size * 1.25)
            } else {
                PixelHead2DView(profileImage: profileImage, profileImageURL: profileImageURL,
                                isSpeaking: $isSpeaking, size: size)
                    .frame(width: size, height: size * 1.25)
            }

            if isSpeaking {
                speakingIndicator.offset(y: 8)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(5)
                    .background(Circle().fill(Color.black.opacity(0.35)))
                    .offset(y: 8)
            }
        }
        .onTapGesture { speakStats() }
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
        let text = "You have \(postCount) posts and your total radius is \(km)."
        isSpeaking = true
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.50
        utterance.pitchMultiplier = 0.98
        utterance.volume = 0.9
        let delegate = ProfileSpeechDelegate { isSpeaking = false }
        speechDelegate = delegate
        synth.delegate = delegate
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        synth.speak(utterance)
    }

    private func stopSpeaking() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
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
        let v = SKView(); v.backgroundColor = .clear; v.allowsTransparency = true
        let sceneSize = CGSize(width: size, height: size * 1.25)
        let scene = PixelHead2DScene(size: sceneSize)
        scene.backgroundColor = .clear; scene.scaleMode = .aspectFit
        v.presentScene(scene)
        context.coordinator.scene = scene
        Task { await context.coordinator.loadImage(url: profileImageURL, fallback: profileImage) }
        return v
    }

    func updateUIView(_ v: SKView, context: Context) {
        isSpeaking ? context.coordinator.scene?.startSpeaking() : context.coordinator.scene?.stopSpeaking()
    }

    class Coordinator {
        var scene: PixelHead2DScene?
        func loadImage(url: URL?, fallback: UIImage?) async {
            var img = fallback
            if let url, let (data, _) = try? await URLSession.shared.data(from: url) {
                img = UIImage(data: data) ?? fallback
            }
            let colors = img.map { pixelGrid(from: $0, cols: 20, rows: 20) } ?? defaultGrid()
            await MainActor.run { scene?.buildPixels(colors) }
        }
    }
}

// MARK: - 2D Pixel Scene

final class PixelHead2DScene: SKScene {
    private var pixelNodes: [[SKShapeNode]] = []
    private let cols = 20, rows = 20
    private var mouthTimer: Timer?
    private var mouthOpen = false
    private var glowNode: SKShapeNode?
    private var colors: [[UIColor]] = []

    func buildPixels(_ colorGrid: [[UIColor]]) {
        removeAllChildren()
        pixelNodes = []
        colors = colorGrid
        let pW = size.width / CGFloat(cols)
        let pH = size.height * 0.88 / CGFloat(rows)
        let offsetY: CGFloat = size.height * 0.06

        // Subtle glow ring
        let glow = SKShapeNode(ellipseIn: CGRect(x: 2, y: 2, width: size.width - 4, height: size.height * 0.88 - 4))
        glow.strokeColor = UIColor.white.withAlphaComponent(0.25); glow.lineWidth = 1.5
        glow.fillColor = .clear; glow.position = CGPoint(x: 0, y: offsetY); glow.alpha = 0
        addChild(glow); glowNode = glow

        for row in 0..<rows {
            var rowNodes: [SKShapeNode] = []
            for col in 0..<cols {
                let color = colorGrid[row][col]
                if color.isTransparent { rowNodes.append(SKShapeNode()); continue }
                let rect = CGRect(x: CGFloat(col) * pW + 0.5, y: offsetY + CGFloat(row) * pH + 0.5,
                                  width: pW - 1, height: pH - 1)
                let node = SKShapeNode(rect: rect, cornerRadius: 1)
                node.fillColor = color; node.strokeColor = .clear
                addChild(node); rowNodes.append(node)
            }
            pixelNodes.append(rowNodes)
        }
    }

    func startSpeaking() {
        glowNode?.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.85, duration: 0.18),
            SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.45, duration: 0.5),
                SKAction.fadeAlpha(to: 0.85, duration: 0.5)
            ]))
        ]))
        mouthTimer?.invalidate()
        mouthTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.animateMouth()
        }
    }

    func stopSpeaking() {
        mouthTimer?.invalidate(); mouthTimer = nil
        glowNode?.removeAllActions(); glowNode?.alpha = 0
        setMouthRow(open: false)
    }

    private func animateMouth() {
        mouthOpen.toggle(); setMouthRow(open: mouthOpen)
    }

    private func setMouthRow(open: Bool) {
        let mouthRow = rows - 6
        guard mouthRow >= 0, mouthRow < pixelNodes.count else { return }
        for (col, node) in pixelNodes[mouthRow].enumerated() {
            let isMouthCol = col >= cols/4 && col <= cols - cols/4
            if isMouthCol {
                let targetColor: UIColor = open ? .black : (colors.count > mouthRow ? colors[mouthRow][safe: col] ?? .black : .black)
                node.fillColor = targetColor
            }
        }
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
        isSpeaking ? context.coordinator.startSpeaking() : context.coordinator.stopSpeaking()
    }

    class Coordinator {
        var scene: SCNScene?
        weak var v: SCNView?
        var headRoot: SCNNode?
        var mouthNodes: [SCNNode] = []
        var mouthTimer: Timer?

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

// MARK: - Speech Delegate

final class ProfileSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onFinish() }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.onFinish() }
    }
}
