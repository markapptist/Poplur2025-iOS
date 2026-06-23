import AVFoundation
import SceneKit
import SpriteKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Public entry point

struct PoplurTransitionFlash: View {
    let channelNumber: Int
    let channelCategory: String
    @ObservedObject private var settings = SettingsStore.shared

    init(channelNumber: Int, channelCategory: String = "Poplur TV") {
        self.channelNumber = channelNumber
        self.channelCategory = channelCategory
    }

    var body: some View {
        if settings.transitionStylePreference == .threeD {
            PoplurTransitionFlash3D(channelNumber: channelNumber, channelCategory: channelCategory)
        } else {
            PoplurTransitionFlash2D(channelNumber: channelNumber, channelCategory: channelCategory)
        }
    }
}

// MARK: - 2D flat variant (TimelineView + Canvas noise, spring pop-in)

private struct PoplurTransitionFlash2D: View {
    let channelNumber: Int
    let channelCategory: String

    @StateObject private var staticSound = TVStaticSoundPlayer()
    @State private var logoVisible = false
    @State private var channelVisible = false

    private let tvGreen = Color(red: 0.31, green: 1.0, blue: 0.25)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()
                staticNoise
                scanlineOverlay
                glitchBands
                foregroundInterference
                tuneCard(in: proxy.size)
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            staticSound.play(duration: 0.64)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { logoVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { channelVisible = true }
        }
        .onDisappear { staticSound.stop() }
    }

    private var staticNoise: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            Canvas(opaque: true, colorMode: .linear) { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                let grain = max(CGFloat(4), min(CGFloat(7), size.width / 78))
                var y: CGFloat = 0
                while y < size.height {
                    let rowGain = Double.random(in: 0.64...1.16)
                    var x: CGFloat = 0
                    while x < size.width {
                        let white = Double.random(in: 0.03...0.98)
                        let opacity = min(1.0, Double.random(in: 0.44...0.96) * rowGain)
                        ctx.fill(
                            Path(CGRect(x: x, y: y, width: grain + 0.8, height: grain + 0.8)),
                            with: .color(Color(white: white, opacity: opacity))
                        )
                        x += grain
                    }
                    y += grain
                }
                for _ in 0..<8 {
                    let isBright = Bool.random()
                    ctx.fill(
                        Path(CGRect(
                            x: CGFloat.random(in: -28...24),
                            y: CGFloat.random(in: 0...max(size.height, 1)),
                            width: size.width + CGFloat.random(in: 24...90),
                            height: CGFloat.random(in: 2...18)
                        )),
                        with: .color(Color(white: isBright ? 1.0 : 0.0, opacity: Double.random(in: 0.18...0.74)))
                    )
                }
            }
        }
        .contrast(1.35)
        .saturation(0.12)
        .ignoresSafeArea()
    }

    private var scanlineOverlay: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.34)))
                y += 3
            }
        }
        .blendMode(.multiply)
        .ignoresSafeArea()
    }

    private var glitchBands: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { _ in
            Canvas { ctx, size in
                for _ in 0..<Int.random(in: 2...5) {
                    let h = CGFloat.random(in: 10...44)
                    ctx.fill(
                        Path(CGRect(x: CGFloat.random(in: -24...24), y: CGFloat.random(in: 0...max(size.height - h, 1)),
                                    width: size.width + 48, height: h)),
                        with: .color(Color.white.opacity(Double.random(in: 0.05...0.16)))
                    )
                }
            }
        }
        .blendMode(.screen)
        .ignoresSafeArea()
    }

    private var foregroundInterference: some View {
        LinearGradient(
            colors: [.black.opacity(0.34), .clear, .black.opacity(0.22), .clear, .black.opacity(0.36)],
            startPoint: .top, endPoint: .bottom
        )
        .blendMode(.multiply)
        .ignoresSafeArea()
    }

    private func tuneCard(in size: CGSize) -> some View {
        let logoWidth = min(max(size.width * 0.34, 116), 194)
        let channelFont = min(max(size.width * 0.078, 30), 48)
        let categoryFont = min(max(size.width * 0.038, 15), 22)

        return VStack(spacing: 16) {
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: logoWidth)
                .shadow(color: .black.opacity(0.78), radius: 20, x: 0, y: 10)
                .shadow(color: .white.opacity(0.28), radius: 2, x: 0, y: 0)
                .scaleEffect(logoVisible ? 1.0 : 0.05)
                .opacity(logoVisible ? 1.0 : 0.0)
                .animation(.spring(response: 0.34, dampingFraction: 0.50), value: logoVisible)

            VStack(spacing: 3) {
                Text("CH \(channelNumber)")
                    .font(.system(size: channelFont, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.7).lineLimit(1)
                Text(channelCategory.uppercased())
                    .font(.system(size: categoryFont, weight: .heavy, design: .rounded))
                    .tracking(1.6).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(tvGreen)
            .shadow(color: tvGreen.opacity(0.92), radius: 9, x: 0, y: 0)
            .shadow(color: .black.opacity(0.82), radius: 2, x: 1, y: 1)
            .scaleEffect(channelVisible ? 1.0 : 0.05)
            .opacity(channelVisible ? 1.0 : 0.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.52), value: channelVisible)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 3D SceneKit variant

private struct PoplurTransitionFlash3D: View {
    let channelNumber: Int
    let channelCategory: String
    @StateObject private var sound = TVStaticSoundPlayer()

    var body: some View {
        GeometryReader { geo in
            _TV3DViewRepresentable(
                size: geo.size,
                channelNumber: channelNumber,
                channelCategory: channelCategory
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { sound.play(duration: 0.64) }
        .onDisappear { sound.stop() }
    }
}

private struct _TV3DViewRepresentable: UIViewRepresentable {
    let size: CGSize
    let channelNumber: Int
    let channelCategory: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: CGRect(origin: .zero, size: size))
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = false
        scnView.showsStatistics = false
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60

        let scene = buildScene()
        scnView.scene = scene
        context.coordinator.scene = scene

        // Sequence: logo flip at 0.08s, text tilt-in at 0.28s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            context.coordinator.animateLogo()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            context.coordinator.animateText()
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // MARK: Coordinator — holds scene ref and runs SCNActions
    final class Coordinator {
        var scene: SCNScene?

        func animateLogo() {
            guard let logo = scene?.rootNode.childNode(withName: "logo", recursively: false) else { return }
            // Flip from π (back-face) to 0 (front-face) + spring bounce scale
            let flip = SCNAction.rotateBy(x: 0, y: -.pi, z: 0, duration: 0.30)
            flip.timingMode = .easeOut
            let bounce = SCNAction.sequence([
                .scale(to: 1.22, duration: 0.12),
                .scale(to: 0.88, duration: 0.09),
                .scale(to: 1.04, duration: 0.07),
                .scale(to: 1.0,  duration: 0.05)
            ])
            logo.runAction(.group([flip, bounce]))
        }

        func animateText() {
            for name in ["ch_text", "cat_text"] {
                guard let node = scene?.rootNode.childNode(withName: name, recursively: false) else { continue }
                let tiltIn = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.26, usesShortestUnitArc: true)
                tiltIn.timingMode = .easeOut
                let fadeIn = SCNAction.fadeIn(duration: 0.06)
                let bounce = SCNAction.sequence([
                    .scale(to: 1.18, duration: 0.10),
                    .scale(to: 0.92, duration: 0.07),
                    .scale(to: 1.0,  duration: 0.06)
                ])
                node.runAction(.group([tiltIn, fadeIn, bounce]))
            }
        }
    }

    // MARK: Scene builder
    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        // Animated SpriteKit noise as SceneKit background
        let bgSize = CGSize(width: 512, height: 512)
        let bgSK = SKScene(size: bgSize)
        bgSK.backgroundColor = .black
        let noiseBG = SKSpriteNode(color: .white, size: bgSize)
        noiseBG.position = CGPoint(x: bgSize.width / 2, y: bgSize.height / 2)
        noiseBG.shader = noiseShader()
        bgSK.addChild(noiseBG)
        scene.background.contents = bgSK

        // Camera
        let cam = SCNCamera()
        cam.zNear = 0.1
        cam.zFar = 100
        cam.fieldOfView = 60
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 0, 8)
        scene.rootNode.addChildNode(camNode)

        // Ambient light so constant-lit materials still need it to avoid pure-black output
        let ambLight = SCNLight()
        ambLight.type = .ambient
        ambLight.intensity = 1000
        let ambNode = SCNNode()
        ambNode.light = ambLight
        scene.rootNode.addChildNode(ambNode)

        // Logo: SCNPlane with logo texture, starts facing away
        let logoPlane = SCNPlane(width: 3.0, height: 3.0)
        let logoMat = SCNMaterial()
        logoMat.diffuse.contents = UIImage(named: "logo")
        logoMat.lightingModel = .constant
        logoMat.isDoubleSided = false
        logoPlane.materials = [logoMat]
        let logoNode = SCNNode(geometry: logoPlane)
        logoNode.name = "logo"
        logoNode.position = SCNVector3(0, 0.8, 0)
        logoNode.eulerAngles.y = .pi  // Start facing away; flip animation reverses this
        scene.rootNode.addChildNode(logoNode)

        let green = UIColor(red: 0.306, green: 1.0, blue: 0.251, alpha: 1.0)
        let glow  = UIColor(red: 0.04, green: 0.28, blue: 0.04, alpha: 1.0)

        // CH N — 3D extruded text
        let chGeo = SCNText(string: "CH \(channelNumber)", extrusionDepth: 0.28)
        chGeo.font = UIFont.monospacedSystemFont(ofSize: 1.1, weight: .black)
        chGeo.flatness = 0.05
        chGeo.containerFrame = CGRect(x: -3.5, y: 0, width: 7, height: 1.5)
        chGeo.alignmentMode = CATextLayerAlignmentMode.center.rawValue
        let chMat = SCNMaterial()
        chMat.diffuse.contents = green
        chMat.emission.contents = glow
        chMat.lightingModel = .constant
        chGeo.materials = [chMat]
        let chNode = SCNNode(geometry: chGeo)
        chNode.name = "ch_text"
        chNode.position = SCNVector3(0, -1.0, 0)
        chNode.eulerAngles.x = -.pi / 2.2  // Start tilted away (face up)
        chNode.opacity = 0
        scene.rootNode.addChildNode(chNode)

        // Category — 3D extruded text, smaller
        let catGeo = SCNText(string: channelCategory.uppercased(), extrusionDepth: 0.18)
        catGeo.font = UIFont.monospacedSystemFont(ofSize: 0.65, weight: .heavy)
        catGeo.flatness = 0.05
        catGeo.containerFrame = CGRect(x: -3.5, y: 0, width: 7, height: 1.0)
        catGeo.alignmentMode = CATextLayerAlignmentMode.center.rawValue
        let catMat = SCNMaterial()
        catMat.diffuse.contents = green
        catMat.emission.contents = glow
        catMat.lightingModel = .constant
        catGeo.materials = [catMat]
        let catNode = SCNNode(geometry: catGeo)
        catNode.name = "cat_text"
        catNode.position = SCNVector3(0, -2.1, 0)
        catNode.eulerAngles.x = -.pi / 2.2
        catNode.opacity = 0
        scene.rootNode.addChildNode(catNode)

        return scene
    }

    private func noiseShader() -> SKShader {
        SKShader(source: """
            void main() {
                vec2 uv = v_tex_coord;
                float t = u_time * 53.0;
                float a = fract(sin(dot(uv * vec2(127.1, 311.7) + fract(t * 0.031), vec2(127.1, 311.7))) * 43758.5453);
                float b = fract(sin(dot(uv * vec2(213.4, 169.7) + fract(t * 0.017), vec2(269.5, 183.3))) * 43758.5453);
                float grain = a * b * 2.2;
                float scanY = floor(uv.y * 180.0 + t * 4.1);
                float bandRand = fract(sin(scanY * 9.721) * 43758.5453);
                float band = step(0.97, bandRand);
                float c = min(1.0, grain + band * a * 1.5);
                gl_FragColor = vec4(vec3(c), v_color_mix.a);
            }
        """)
    }
}

// MARK: - Shared audio player

private final class TVStaticSoundPlayer: ObservableObject {
    private var player: AVAudioPlayer?
    private var stopWorkItem: DispatchWorkItem?

    deinit { stop() }

    func play(duration: TimeInterval) {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {}
        do {
            let data = Self.makeStaticWAV(duration: duration)
            let player = try AVAudioPlayer(data: data)
            player.numberOfLoops = 0
            player.volume = 0.52
            player.prepareToPlay()
            player.play()
            self.player = player
            let item = DispatchWorkItem { [weak self] in self?.stop() }
            stopWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
        } catch {}
    }

    func stop() {
        stopWorkItem?.cancel()
        stopWorkItem = nil
        player?.stop()
        player = nil
    }

    private static func makeStaticWAV(duration: TimeInterval) -> Data {
        let sampleRate = 22_050
        let sampleCount = max(1, Int(Double(sampleRate) * duration))
        var samples: [Int16] = []
        samples.reserveCapacity(sampleCount)
        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleRate)
            let fadeIn  = min(1.0, Double(i) / 520.0)
            let fadeOut = min(1.0, Double(sampleCount - i) / 1_350.0)
            let env     = min(fadeIn, fadeOut)
            let hiss    = Double.random(in: -1.0...1.0) * 0.88
            let crackle = Double.random(in: 0...1) > 0.992 ? Double.random(in: -1.0...1.0) * 0.55 : 0
            let lowHum  = sin(2.0 * .pi * 59.94 * t) * 0.08
            let value   = max(-1.0, min(1.0, (hiss + crackle + lowHum) * env))
            samples.append(Int16(value * Double(Int16.max) * 0.72))
        }
        return makeWAVData(from: samples, sampleRate: sampleRate)
    }

    private static func makeWAVData(from samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate   = UInt32(sampleRate) * UInt32(numChannels * bitsPerSample / 8)
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize   = UInt32(samples.count * 2)
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(36 + dataSize).littleEndian)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndian)
        data.append(UInt16(1).littleEndian)
        data.append(numChannels.littleEndian)
        data.append(UInt32(sampleRate).littleEndian)
        data.append(byteRate.littleEndian)
        data.append(blockAlign.littleEndian)
        data.append(bitsPerSample.littleEndian)
        data.append("data".data(using: .ascii)!)
        data.append(dataSize.littleEndian)
        for sample in samples { data.append(sample.littleEndian) }
        return data
    }
}
