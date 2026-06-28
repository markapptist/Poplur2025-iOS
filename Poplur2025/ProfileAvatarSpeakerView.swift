import SwiftUI
import SpriteKit
import SceneKit
import AVFoundation

// MARK: - ProfileAvatarSpeakerView
// Replaces the static profile image with an animated avatar that speaks stats on tap.
// 2D mode uses SpriteKit; 3D mode uses SceneKit. Controlled by AppStorage.

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
                ProfileAvatar3DView(profileImage: profileImage, isSpeaking: $isSpeaking, size: size)
                    .frame(width: size, height: size * 1.25)
            } else {
                ProfileAvatar2DView(
                    profileImage: profileImage,
                    profileImageURL: profileImageURL,
                    isSpeaking: $isSpeaking,
                    size: size
                )
                .frame(width: size, height: size * 1.25)
            }

            if isSpeaking {
                speakingIndicator
                    .offset(y: 8)
            } else {
                // Hint to tap
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

    // MARK: - Speaking Indicator

    private var speakingIndicator: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                SpeakBarView(delay: Double(i) * 0.07)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }

    // MARK: - Speech

    private func speakStats() {
        guard !isSpeaking else {
            synth.stopSpeaking(at: .immediate)
            isSpeaking = false
            return
        }

        let radiusText: String
        if totalRadiusKM >= 1_000 {
            radiusText = String(format: "%.0f thousand kilometers", totalRadiusKM / 1_000)
        } else if totalRadiusKM >= 1 {
            radiusText = String(format: "%.0f kilometers", totalRadiusKM)
        } else {
            radiusText = "just getting started"
        }
        let postText = postCount == 1 ? "1 post" : "\(postCount) posts"
        let text = "You have \(radiusText) of radius worldwide, from \(postText)."

        isSpeaking = true
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.50
        utterance.pitchMultiplier = 1.08
        utterance.volume = 0.95

        let delegate = ProfileSpeechDelegate { isSpeaking = false }
        speechDelegate = delegate
        synth.delegate = delegate
        synth.speak(utterance)
    }
}

// MARK: - Animated Equalizer Bar

private struct SpeakBarView: View {
    let delay: Double
    @State private var scale: CGFloat = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .frame(width: 3, height: scale * 14)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.25)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) { scale = 0.3 }
            }
    }
}

// MARK: - 2D SpriteKit Avatar

struct ProfileAvatar2DView: UIViewRepresentable {
    let profileImage: UIImage?
    let profileImageURL: URL?
    @Binding var isSpeaking: Bool
    let size: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.backgroundColor = .clear
        view.allowsTransparency = true
        let sceneSize = CGSize(width: size, height: size * 1.25)
        let scene = ProfileAvatar2DScene(size: sceneSize)
        scene.backgroundColor = .clear
        scene.scaleMode = .aspectFit
        view.presentScene(scene)
        context.coordinator.scene = scene
        // Load profile image async
        Task { await context.coordinator.loadImage(url: profileImageURL, fallback: profileImage) }
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if isSpeaking {
            context.coordinator.scene?.startSpeaking()
        } else {
            context.coordinator.scene?.stopSpeaking()
        }
    }

    class Coordinator {
        var scene: ProfileAvatar2DScene?

        func loadImage(url: URL?, fallback: UIImage?) async {
            if let url = url,
               let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                await MainActor.run { scene?.setProfileImage(image) }
            } else if let image = fallback {
                await MainActor.run { scene?.setProfileImage(image) }
            }
        }
    }
}

// MARK: - 2D SK Scene

final class ProfileAvatar2DScene: SKScene {
    private var faceNode: SKShapeNode!
    private var glowNode: SKShapeNode!
    private var mouthNode: SKShapeNode!
    private var mouthTimer: Timer?

    override func didMove(to view: SKView) {
        let cx = size.width / 2
        let faceR = size.width * 0.42
        let faceY = size.height * 0.56

        // Outer glow (shows when speaking)
        glowNode = SKShapeNode(circleOfRadius: faceR + 5)
        glowNode.position = CGPoint(x: cx, y: faceY)
        glowNode.strokeColor = UIColor.systemPink
        glowNode.lineWidth = 3
        glowNode.glowWidth = 10
        glowNode.alpha = 0
        addChild(glowNode)

        // Face circle
        faceNode = SKShapeNode(circleOfRadius: faceR)
        faceNode.position = CGPoint(x: cx, y: faceY)
        faceNode.fillColor = .darkGray
        faceNode.strokeColor = UIColor.white.withAlphaComponent(0.35)
        faceNode.lineWidth = 2
        addChild(faceNode)

        // Mouth — starts closed (scaleY ≈ 0)
        let mouthW = faceR * 0.62
        let mouthH = faceR * 0.20
        mouthNode = SKShapeNode(ellipseOf: CGSize(width: mouthW, height: mouthH))
        mouthNode.position = CGPoint(x: cx, y: faceY - faceR * 0.52)
        mouthNode.fillColor = .black
        mouthNode.strokeColor = UIColor.white.withAlphaComponent(0.5)
        mouthNode.lineWidth = 1.5
        mouthNode.yScale = 0.1
        addChild(mouthNode)
    }

    func setProfileImage(_ image: UIImage) {
        faceNode.fillTexture = SKTexture(image: image)
        faceNode.fillColor = .white
    }

    func startSpeaking() {
        glowNode.removeAllActions()
        glowNode.run(SKAction.fadeAlpha(to: 1, duration: 0.2))
        glowNode.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.04, duration: 0.5),
            SKAction.scale(to: 1.00, duration: 0.5)
        ])))

        var open = false
        mouthTimer?.invalidate()
        mouthTimer = Timer.scheduledTimer(withTimeInterval: 0.13, repeats: true) { [weak self] _ in
            guard let self else { return }
            open.toggle()
            self.mouthNode.run(SKAction.scaleY(to: open ? 1.0 : 0.1, duration: 0.10))
        }
    }

    func stopSpeaking() {
        mouthTimer?.invalidate()
        mouthTimer = nil
        mouthNode.run(SKAction.scaleY(to: 0.1, duration: 0.15))
        glowNode.removeAllActions()
        glowNode.run(SKAction.fadeAlpha(to: 0, duration: 0.3))
    }
}

// MARK: - 3D SceneKit Avatar

struct ProfileAvatar3DView: UIViewRepresentable {
    let profileImage: UIImage?
    @Binding var isSpeaking: Bool
    let size: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        view.scene = scene

        // Camera
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.position = SCNVector3(0, 0, 2.8)
        scene.rootNode.addChildNode(cam)

        // Ambient light
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1400
        scene.rootNode.addChildNode(ambient)

        // Face plane — circular masked profile image
        let facePlane = SCNPlane(width: 1.5, height: 1.5)
        facePlane.firstMaterial?.diffuse.contents = circularImage(profileImage, size: 512)
        facePlane.firstMaterial?.isDoubleSided = true
        facePlane.firstMaterial?.lightingModel = .constant

        let faceNode = SCNNode(geometry: facePlane)
        faceNode.name = "face"
        faceNode.position = SCNVector3(0, 0.08, 0)
        scene.rootNode.addChildNode(faceNode)

        // Gentle float
        let up = SCNAction.moveBy(x: 0, y: 0.05, z: 0, duration: 1.3)
        let dn = SCNAction.moveBy(x: 0, y: -0.05, z: 0, duration: 1.3)
        up.timingMode = .easeInEaseOut; dn.timingMode = .easeInEaseOut
        faceNode.runAction(SCNAction.repeatForever(.sequence([up, dn])))

        // Slight oscillation
        let rotLeft = SCNAction.rotateBy(x: 0, y: 0.08, z: 0, duration: 1.8)
        let rotRight = SCNAction.rotateBy(x: 0, y: -0.08, z: 0, duration: 1.8)
        rotLeft.timingMode = .easeInEaseOut; rotRight.timingMode = .easeInEaseOut
        faceNode.runAction(SCNAction.repeatForever(.sequence([rotLeft, rotRight])))

        // Mouth plane
        let mouthPlane = SCNPlane(width: 0.6, height: 0.14)
        mouthPlane.firstMaterial?.diffuse.contents = UIColor.black
        mouthPlane.firstMaterial?.lightingModel = .constant
        mouthPlane.firstMaterial?.isDoubleSided = true
        let mouthNode = SCNNode(geometry: mouthPlane)
        mouthNode.name = "mouth"
        mouthNode.position = SCNVector3(0, -0.57, 0.01)
        mouthNode.scale = SCNVector3(1, 0.1, 1)
        scene.rootNode.addChildNode(mouthNode)

        context.coordinator.faceNode = faceNode
        context.coordinator.mouthNode = mouthNode
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if isSpeaking {
            context.coordinator.startSpeaking()
        } else {
            context.coordinator.stopSpeaking()
        }
    }

    class Coordinator {
        var faceNode: SCNNode?
        var mouthNode: SCNNode?
        var mouthTimer: Timer?

        func startSpeaking() {
            faceNode?.geometry?.firstMaterial?.emission.contents =
                UIColor(red: 0.25, green: 0.15, blue: 0.55, alpha: 0.35)

            var open = false
            mouthTimer?.invalidate()
            mouthTimer = Timer.scheduledTimer(withTimeInterval: 0.13, repeats: true) { [weak self] _ in
                guard let mn = self?.mouthNode else { return }
                open.toggle()
                let targetY: Float = open ? 1.0 : 0.1
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.10
                mn.scale = SCNVector3(mn.scale.x, targetY, mn.scale.z)
                SCNTransaction.commit()
            }
        }

        func stopSpeaking() {
            mouthTimer?.invalidate()
            mouthTimer = nil
            faceNode?.geometry?.firstMaterial?.emission.contents = UIColor.clear
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.15
            mouthNode?.scale = SCNVector3(1, 0.1, 1)
            SCNTransaction.commit()
        }
    }

    private func circularImage(_ image: UIImage?, size: CGFloat) -> UIImage {
        let s = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: s)
        return renderer.image { ctx in
            ctx.cgContext.addEllipse(in: CGRect(origin: .zero, size: s))
            ctx.cgContext.clip()
            if let img = image {
                img.draw(in: CGRect(origin: .zero, size: s))
            } else {
                UIColor.systemGray.setFill()
                ctx.cgContext.fill(CGRect(origin: .zero, size: s))
            }
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
