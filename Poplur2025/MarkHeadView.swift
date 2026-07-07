import SwiftUI
import SceneKit
import AVFoundation
import Accelerate

// MARK: - View

struct MarkHeadView: UIViewRepresentable {
    /// Set to the text you want spoken. Nil = idle / stop.
    @Binding var speakText: String?
    /// Called when speech finishes or is stopped.
    var onFinished: () -> Void = {}
    /// Called once when the GLB scene finishes loading and is ready to render.
    var onLoaded: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinished: onFinished, onLoaded: onLoaded) }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.isOpaque = false
        v.backgroundColor = .clear
        v.allowsCameraControl = false
        v.antialiasingMode = .multisampling4X
        v.autoenablesDefaultLighting = false
        v.isPlaying = true
        v.rendersContinuously = true
        v.scene = SCNScene()
        context.coordinator.load(into: v)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        if let text = speakText {
            context.coordinator.speak(text)
        } else {
            context.coordinator.stopSpeaking()
        }
    }
}

// MARK: - Coordinator

final class MarkHeadViewCoordinator: NSObject, AVSpeechSynthesizerDelegate {

    // ── SceneKit ──────────────────────────────────────────────────────────
    private weak var scnView: SCNView?
    // morphMap: target name → (owning node, index in that node's SCNMorpher)
    private var morphMap: [String: (SCNNode, Int)] = [:]
    private var isLoaded = false

    // ── Audio engine ──────────────────────────────────────────────────────
    private let engine    = AVAudioEngine()
    private let player    = AVAudioPlayerNode()
    // write-mode synth — separate from any live-speak synth
    private let writeSynth = AVSpeechSynthesizer()
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    private var amplitudeTimeline: [Float] = []   // one RMS value per chunkSize frames
    private let chunkSize: vDSP_Length = 1024     // ~46 ms at 22 050 Hz

    // ── Playback tracking ─────────────────────────────────────────────────
    private var playbackStart: CFTimeInterval = 0
    private var chunkDuration: Double = 0

    // ── Animation ─────────────────────────────────────────────────────────
    private var displayLink: CADisplayLink?
    private var blinkTimer: Timer?
    private var currentJaw: Float = 0
    private var targetJaw:  Float = 0

    // ── State ─────────────────────────────────────────────────────────────
    private var isSpeaking = false
    private var lastText: String?
    let onFinished: () -> Void
    let onLoaded: () -> Void

    init(onFinished: @escaping () -> Void, onLoaded: @escaping () -> Void) {
        self.onFinished = onFinished
        self.onLoaded = onLoaded
        super.init()
        writeSynth.delegate = self
        engine.attach(player)
    }

    // MARK: Load model

    func load(into view: SCNView) {
        scnView = view
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let scene = self.loadHeadScene()
            DispatchQueue.main.async {
                if let scene { self.configure(scene, in: view) }
                else { print("[MarkHeadView] No head model could be loaded.") }
            }
        }
    }

    private func loadHeadScene() -> SCNScene? {
        // Primary: load MarkHead.scn from the Assets catalog data asset, then apply PBR textures.
        if let scene = loadFromAssetsDataset() {
            print("[MarkHeadView] Loaded MarkHead from Assets catalog")
            return scene
        }
        // Fallback: bundle file paths (only present in debug builds with source-tree access).
        for candidate in [("MarkHead", "scn"), ("MarkHead", "dae")] {
            guard let url = Bundle.main.url(forResource: candidate.0, withExtension: candidate.1),
                  let scene = try? SCNScene(url: url, options: [
                      SCNSceneSource.LoadingOption.convertUnitsToMeters: true,
                      SCNSceneSource.LoadingOption.convertToYUp: true
                  ]) else {
                continue
            }
            print("[MarkHeadView] Loaded \(candidate.0).\(candidate.1) from bundle")
            applyMeshyTextures(to: scene)
            return scene
        }
        return makeProceduralFallbackScene()
    }

    private func loadFromAssetsDataset() -> SCNScene? {
        guard let asset = NSDataAsset(name: "MarkHeadScene") else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("MarkHead_loaded.scn")
        do {
            try asset.data.write(to: tmp, options: .atomic)
        } catch {
            print("[MarkHeadView] Failed to write temp SCN: \(error)")
            return nil
        }
        guard let scene = try? SCNScene(url: tmp, options: [
            SCNSceneSource.LoadingOption.convertUnitsToMeters: true,
            SCNSceneSource.LoadingOption.convertToYUp: true
        ]) else { return nil }
        applyMeshyTextures(to: scene)
        return scene
    }

    private func applyMeshyTextures(to scene: SCNScene) {
        let prefix = "Meshy_AI_Mark_character_head_3_0630045036_image-to-3d-texture"
        let diffuse  = UIImage(named: "\(prefix)e")          // imageset name ends with extra 'e'
        let normal   = UIImage(named: "\(prefix)_normal")
        let metallic = UIImage(named: "\(prefix)_metallic")
        let roughness = UIImage(named: "\(prefix)_roughness")
        let emission = UIImage(named: "\(prefix)_emission")
        scene.rootNode.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { mat in
                mat.lightingModel = .physicallyBased
                if let diffuse  { mat.diffuse.contents  = diffuse }
                if let normal   { mat.normal.contents   = normal;  mat.normal.intensity = 0.8 }
                if let metallic { mat.metalness.contents = metallic }
                if let roughness { mat.roughness.contents = roughness }
                if let emission { mat.emission.contents = emission; mat.emission.intensity = 0.15 }
            }
        }
    }

    private func makeProceduralFallbackScene() -> SCNScene {
        let scene = SCNScene()
        let root = SCNNode()
        let head = SCNNode(geometry: SCNSphere(radius: 0.42))
        head.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.96, green: 0.68, blue: 0.46, alpha: 1)
        head.position = SCNVector3(0, 0.18, 0)
        root.addChildNode(head)
        let hair = SCNNode(geometry: SCNSphere(radius: 0.43))
        hair.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.24, green: 0.11, blue: 0.04, alpha: 1)
        hair.scale = SCNVector3(1.04, 0.45, 0.96)
        hair.position = SCNVector3(0, 0.46, -0.02)
        root.addChildNode(hair)
        for x in [-0.15, 0.15] as [Float] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.045))
            eye.geometry?.firstMaterial?.diffuse.contents = UIColor.white
            eye.position = SCNVector3(x, 0.25, 0.38)
            root.addChildNode(eye)
            let pupil = SCNNode(geometry: SCNSphere(radius: 0.022))
            pupil.geometry?.firstMaterial?.diffuse.contents = UIColor.systemBlue
            pupil.position = SCNVector3(x, 0.25, 0.415)
            root.addChildNode(pupil)
        }
        let mouth = SCNNode(geometry: SCNTorus(ringRadius: 0.075, pipeRadius: 0.009))
        mouth.name = "jawOpen"
        mouth.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.20, green: 0.04, blue: 0.03, alpha: 1)
        mouth.scale = SCNVector3(1.2, 0.38, 1)
        mouth.position = SCNVector3(0, 0.03, 0.405)
        root.addChildNode(mouth)
        scene.rootNode.addChildNode(root)
        return scene
    }

    private func configure(_ imported: SCNScene, in view: SCNView) {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let root = SCNNode()
        imported.rootNode.childNodes.forEach { root.addChildNode($0.clone()) }

        // Discover every morph target across all nodes
        root.enumerateHierarchy { node, _ in
            guard let morpher = node.morpher else { return }
            for (i, target) in morpher.targets.enumerated() {
                guard let name = target.name, morphMap[name] == nil else { continue }
                morphMap[name] = (node, i)
            }
        }

        // Scale + centre the head
        normalize(root)

        // Lighting
        addLight(to: scene, type: .ambient, intensity: 450)
        addLight(to: scene, type: .directional, intensity: 1000, euler: SCNVector3(-0.4, 0.4, 0))
        let rim = addLight(to: scene, type: .directional, intensity: 300, euler: SCNVector3(0.15, Float.pi - 0.35, 0))
        rim.light?.color = UIColor(red: 0.55, green: 0.70, blue: 1.0, alpha: 1)
        scene.rootNode.addChildNode(root)

        // Camera — frame to show head
        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 32
        cam.position = SCNVector3(0, 0.04, 2.45)
        scene.rootNode.addChildNode(cam)
        view.pointOfView = cam

        // Idle float + sway
        func ease(_ a: SCNAction) -> SCNAction { a.timingMode = .easeInEaseOut; return a }
        root.runAction(.repeatForever(.sequence([ease(.moveBy(x: 0, y: 0.007, z: 0, duration: 1.6)),
                                                 ease(.moveBy(x: 0, y: -0.007, z: 0, duration: 1.6))])))
        root.runAction(.repeatForever(.sequence([ease(.rotateBy(x: 0, y: 0.07, z: 0, duration: 2.4)),
                                                 ease(.rotateBy(x: 0, y: -0.07, z: 0, duration: 2.4))])))

        view.scene = scene
        isLoaded = true
        onLoaded()
        scheduleBlink()
    }

    @discardableResult
    private func addLight(to scene: SCNScene, type: SCNLight.LightType, intensity: CGFloat,
                          euler: SCNVector3 = .init()) -> SCNNode {
        let n = SCNNode(); n.light = SCNLight()
        n.light?.type = type; n.light?.intensity = intensity
        n.eulerAngles = euler
        scene.rootNode.addChildNode(n)
        return n
    }

    private func normalize(_ root: SCNNode) {
        var minV = SIMD3<Float>(repeating:  Float.greatestFiniteMagnitude)
        var maxV = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        var found = false
        root.enumerateHierarchy { node, _ in
            guard node.geometry != nil else { return }
            let (lo, hi) = node.boundingBox
            let corners: [SCNVector3] = [
                .init(lo.x, lo.y, lo.z), .init(lo.x, lo.y, hi.z),
                .init(lo.x, hi.y, lo.z), .init(lo.x, hi.y, hi.z),
                .init(hi.x, lo.y, lo.z), .init(hi.x, lo.y, hi.z),
                .init(hi.x, hi.y, lo.z), .init(hi.x, hi.y, hi.z)
            ]
            for c in corners {
                let w = node.convertPosition(c, to: root)
                let v = SIMD3<Float>(w.x, w.y, w.z)
                minV = simd_min(minV, v); maxV = simd_max(maxV, v); found = true
            }
        }
        guard found else { return }
        let ext = maxV - minV
        let maxExt = max(ext.x, max(ext.y, ext.z))
        let s = maxExt > 0 ? Float(1.22) / maxExt : 1
        let mid = (minV + maxV) * 0.5
        root.scale = SCNVector3(s, s, s)
        root.position = SCNVector3(-mid.x * s, -mid.y * s + 0.04, -mid.z * s)
    }

    // MARK: Speak

    func speak(_ text: String) {
        guard isLoaded else { return }
        guard text != lastText || !isSpeaking else { return }
        stopSpeaking()
        isSpeaking = true
        lastText = text
        pendingBuffers = []
        amplitudeTimeline = []

        let utt = AVSpeechUtterance(string: text)
        utt.voice = AVSpeechSynthesisVoice(language: "en-US")
        utt.rate = 0.50
        utt.pitchMultiplier = 0.98
        utt.volume = 0.9

        // Pre-render to PCM buffers on a background thread (write() itself is async-ish,
        // but the callback fires on a synthesis thread — delegate fires on main when done)
        writeSynth.write(utt) { [weak self] buf in
            guard let self, let pcm = buf as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return }
            self.pendingBuffers.append(pcm)
            self.extractAmplitude(pcm)
        }
        // speechSynthesizer(_:didFinish:) fires when all buffers have been written
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in self?.startPlayback() }
    }

    // MARK: Amplitude Analysis

    private func extractAmplitude(_ pcm: AVAudioPCMBuffer) {
        guard let data = pcm.floatChannelData?[0] else { return }
        let total = Int(pcm.frameLength)
        let chunk = Int(chunkSize)
        var i = 0
        while i < total {
            let count = vDSP_Length(min(chunk, total - i))
            var rms: Float = 0
            vDSP_rmsqv(data + i, 1, &rms, count)
            amplitudeTimeline.append(rms)
            i += chunk
        }
    }

    // MARK: Playback

    private func startPlayback() {
        guard let format = pendingBuffers.first?.format else { finishSpeaking(); return }

        // How long each amplitude sample represents
        chunkDuration = Double(chunkSize) / format.sampleRate

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("[MarkHeadView] Audio session: \(error)") }

        if engine.isRunning { player.stop(); engine.stop() }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do { try engine.start() } catch {
            print("[MarkHeadView] Engine start failed: \(error)")
            finishSpeaking(); return
        }

        let last = pendingBuffers.count - 1
        for (i, buf) in pendingBuffers.enumerated() {
            if i == last {
                player.scheduleBuffer(buf) { [weak self] in
                    DispatchQueue.main.async { self?.finishSpeaking() }
                }
            } else {
                player.scheduleBuffer(buf)
            }
        }
        player.play()
        playbackStart = CACurrentMediaTime()
        startLipSync()
    }

    // MARK: Lip Sync (CADisplayLink)

    private func startLipSync() {
        displayLink?.invalidate()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60)
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        let elapsed = CACurrentMediaTime() - playbackStart
        let idx = chunkDuration > 0 ? Int(elapsed / chunkDuration) : 0
        let amp: Float = idx < amplitudeTimeline.count ? amplitudeTimeline[idx] : 0

        // Jaw open — scale amplitude to 0…1 range, smooth with lerp
        targetJaw = min(1.0, amp * 14.0)
        currentJaw += (targetJaw - currentJaw) * 0.30
        let jaw = currentJaw

        setMorph("jawOpen",           weight: jaw)
        setMorph("mouthInteriorOpen", weight: jaw * 0.65)
        setMorph("browInnerUp",       weight: min(0.55, jaw * 1.1))

        // Cycle through open-mouth visemes using audio rhythm
        let t = Float(elapsed)
        let cycle = sin(t * 7.5) * 0.5 + 0.5   // 0…1 at ~1.2 Hz
        if jaw > 0.12 {
            setMorph("mouthFunnel",  weight: jaw * cycle * 0.45)
            setMorph("mouthPucker",  weight: jaw * (1 - cycle) * 0.30)
            // Alternate between vowel shapes
            let vowelCycle = (sin(t * 4.8) + 1) * 0.5
            setMorph("viseme_AA", weight: jaw * max(0, vowelCycle - 0.6) * 2.5)
            setMorph("viseme_O",  weight: jaw * max(0, 0.6 - vowelCycle) * 1.8)
        } else {
            setMorph("mouthFunnel", weight: 0)
            setMorph("mouthPucker", weight: 0)
            setMorph("viseme_AA",   weight: 0)
            setMorph("viseme_O",    weight: 0)
        }

    }

    // MARK: Morph helpers

    private func setMorph(_ name: String, weight: Float) {
        guard let (node, idx) = morphMap[name], let morpher = node.morpher else { return }
        morpher.setWeight(CGFloat(max(0, min(1, weight))), forTargetAt: idx)
    }

    private func resetAllMorphs() {
        for (node, idx) in morphMap.values {
            node.morpher?.setWeight(0, forTargetAt: idx)
        }
    }

    // MARK: Stop / Finish

    func stopSpeaking() {
        if engine.isRunning { player.stop() }
        displayLink?.invalidate(); displayLink = nil
        if isSpeaking { finishSpeaking() }
    }

    private func finishSpeaking() {
        displayLink?.invalidate(); displayLink = nil
        isSpeaking = false
        lastText = nil
        currentJaw = 0; targetJaw = 0
        resetAllMorphs()
        scheduleBlink()
        onFinished()
    }

    // MARK: Idle Blink

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        let interval = Double.random(in: 2.5...5.5)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.doBlink()
        }
    }

    private func doBlink() {
        setMorph("eyeBlinkLeft", weight: 1)
        setMorph("eyeBlinkRight", weight: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.setMorph("eyeBlinkLeft",  weight: 0)
            self?.setMorph("eyeBlinkRight", weight: 0)
            self?.scheduleBlink()
        }
    }

    deinit {
        displayLink?.invalidate()
        blinkTimer?.invalidate()
        engine.stop()
    }
}

// Alias so UIViewRepresentable can find the type
extension MarkHeadView {
    typealias Coordinator = MarkHeadViewCoordinator
}
