import SwiftUI
import WatchKit
import SceneKit
import UIKit
import AVFoundation
import CoreLocation
@preconcurrency import WatchConnectivity

// MARK: - Types

enum RadiusTrend { case up, down, stable }

// MARK: - Audio (radio bed + the press-and-hold static easter egg)

/// TV static, synthesised rather than bundled — a short noise burst with a
/// fade in/out envelope, wrapped as WAV bytes for AVAudioPlayer.
private func makeStaticWAV(duration: TimeInterval) -> Data {
    let sampleRate = 22_050
    let product = Double(sampleRate) * duration
    let sampleCount = max(1, Int(product.isFinite ? min(max(product, 1), 1_000_000) : 1))
    var samples: [Int16] = []
    samples.reserveCapacity(sampleCount)
    for i in 0..<sampleCount {
        let fadeIn  = min(1.0, Double(i) / 440.0)
        let fadeOut = min(1.0, Double(sampleCount - i) / 880.0)
        let noise   = Double.random(in: -1.0...1.0) * 0.62 * fadeIn * fadeOut
        samples.append(Int16(min(Int(Int16.max), max(Int(Int16.min), Int(noise * Double(Int16.max))))))
    }
    var d = Data()
    func u16(_ v: UInt16) { var b = v.littleEndian; withUnsafeBytes(of: &b) { d.append(contentsOf: $0) } }
    func u32(_ v: UInt32) { var b = v.littleEndian; withUnsafeBytes(of: &b) { d.append(contentsOf: $0) } }
    let ch: UInt16 = 1, bps: UInt16 = 16
    let ds = UInt32(samples.count * 2)
    d.append(contentsOf: "RIFF".utf8); u32(36 + ds)
    d.append(contentsOf: "WAVE".utf8)
    d.append(contentsOf: "fmt ".utf8); u32(16); u16(1); u16(ch)
    u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * UInt32(ch * bps / 8)); u16(ch * bps / 8); u16(bps)
    d.append(contentsOf: "data".utf8); u32(ds)
    for s in samples { var b = s.littleEndian; withUnsafeBytes(of: &b) { d.append(contentsOf: $0) } }
    return d
}

/// The watch's own radio. It doesn't follow the phone: it takes the watch's
/// location, works out where you are, and "tunes in" to a rotation of local
/// channels — each introduced by the Poplur AI host voice (the same British
/// radio voice the phone falls back to) over a looping music bed. Fully
/// on-device, so it works with no network and no companion app.
@MainActor
final class WatchAudio: NSObject, CLLocationManagerDelegate, AVSpeechSynthesizerDelegate {
    static let shared = WatchAudio()

    private var radio: AVAudioPlayer?          // looping music bed
    private var noise: AVAudioPlayer?          // static easter-egg noise
    private let synth = AVSpeechSynthesizer()  // Poplur AI host voice
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    private var isRunning = false
    private var isStatic  = false
    private var didWelcome = false
    private var areaName = "your area"
    private var channels: [String] = []
    private var channelIndex = 0
    private var hostTimer: Timer?
    private var watchdog: Timer?
    private var didRequestFix = false

    private let bedFull: Float = 0.5    // music bed at full
    private let bedDuck: Float = 0.14   // ducked under the host voice

    private override init() {
        super.init()
        synth.delegate = self
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    // MARK: Start / stop

    func startRadio() {
        guard !isRunning else { radio?.play(); return }
        isRunning = true
        activateSession()
        startBed()
        rebuildChannels(for: areaName)     // seed generic channels immediately
        requestLocationFix()               // refine to the real area when it lands
        // Open with the welcome, then keep tuning between channels.
        scheduleTuneIn(after: 1.4)
    }

    func stopRadio() {
        isRunning = false
        hostTimer?.invalidate(); hostTimer = nil
        watchdog?.invalidate(); watchdog = nil
        synth.stopSpeaking(at: .immediate)
        radio?.pause()
    }

    private func startBed() {
        if let radio { radio.volume = bedFull; radio.play(); return }
        guard let asset = NSDataAsset(name: "radio_bed") else { return }
        radio = try? AVAudioPlayer(data: asset.data)
        radio?.numberOfLoops = -1
        radio?.volume = bedFull
        radio?.play()
    }

    // MARK: Location → local area

    private func requestLocationFix() {
        guard !didRequestFix else { return }
        didRequestFix = true
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        default:
            break   // denied/restricted → keep broadcasting "your area"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.reverseGeocode(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silent: the host keeps broadcasting from "your area".
    }

    private func reverseGeocode(_ loc: CLLocation) {
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            Task { @MainActor in
                guard let self else { return }
                guard let p = placemarks?.first else { return }
                let name = p.locality
                    ?? p.subLocality
                    ?? p.subAdministrativeArea
                    ?? p.administrativeArea
                    ?? p.name
                if let name, !name.isEmpty {
                    self.areaName = name
                    self.rebuildChannels(for: name)
                }
            }
        }
    }

    private func rebuildChannels(for area: String) {
        channels = [
            "Poplur \(area)",
            "\(area) Live",
            "\(area) After Dark",
            "The \(area) Underground",
            "Poplur Radio One"
        ]
    }

    // MARK: The host cycle

    private func scheduleTuneIn(after seconds: TimeInterval) {
        hostTimer?.invalidate()
        hostTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tuneIn() }
        }
    }

    private func tuneIn() {
        guard isRunning, !isStatic, !synth.isSpeaking else { return }
        let channel = channels.isEmpty ? "Poplur Radio" : channels[channelIndex % channels.count]
        let script: String
        if !didWelcome {
            didWelcome = true
            script = "You're locked in to Poplur Radio, live and direct from \(areaName). Let's hear what's on the air near you."
        } else {
            script = Self.channelLine(channel: channel, area: areaName, index: channelIndex)
        }
        channelIndex += 1
        speak(script)
    }

    private func speak(_ text: String) {
        radio?.setVolume(bedDuck, fadeDuration: 0.3)   // duck the bed under the voice
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.preferredRadioVoice()
        u.rate = 0.49
        u.pitchMultiplier = 0.98
        u.volume = 1.0
        u.preUtteranceDelay = 0.05
        u.postUtteranceDelay = 0.10
        synth.speak(u)
        // Safety net: if the synthesizer never reports back (e.g. a missing voice
        // asset), don't let the broadcast stall — resume after a length-based estimate.
        watchdog?.invalidate()
        let estimate = min(30.0, 3.5 + Double(text.count) * 0.09)
        watchdog = Timer.scheduledTimer(withTimeInterval: estimate, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resumeAfterSegment() }
        }
    }

    /// Bring the bed back up and queue the next tune-in — called by either the
    /// synthesizer finishing or the watchdog, whichever lands first.
    private func resumeAfterSegment() {
        watchdog?.invalidate(); watchdog = nil
        guard isRunning, !isStatic else { return }
        radio?.setVolume(bedFull, fadeDuration: 0.6)
        scheduleTuneIn(after: 6.5)   // musical breather between segments
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeAfterSegment() }
    }

    /// The Poplur AI host voice — a British radio voice, matching the phone's
    /// on-device fallback (`PoplurMapRadioHost.preferredRadioVoice`).
    static func preferredRadioVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let british = voices.filter { $0.language == "en-GB" }
        let preferredNames = ["serena", "daniel", "martha", "arthur", "kate"]
        if let named = british.first(where: { v in
            preferredNames.contains { v.name.lowercased().contains($0) }
        }) { return named }
        if let premium  = british.first(where: { $0.quality == .premium })  { return premium }
        if let enhanced = british.first(where: { $0.quality == .enhanced }) { return enhanced }
        if let anyPrem  = voices.first(where: { $0.language.hasPrefix("en") && $0.quality == .premium })  { return anyPrem }
        if let anyEnh   = voices.first(where: { $0.language.hasPrefix("en") && $0.quality == .enhanced }) { return anyEnh }
        return AVSpeechSynthesisVoice(language: "en-GB")
    }

    private static func channelLine(channel: String, area: String, index: Int) -> String {
        let lines = [
            "You're tuned to \(channel). The signal's strong here in \(area) tonight.",
            "This is \(channel) — every post around \(area), straight to your wrist.",
            "Picking up \(channel) now. \(area) is buzzing on the Poplur dial.",
            "Coming through on \(channel), live from the streets of \(area).",
            "Stay locked to \(channel). More from \(area) right after this.",
            "\(channel) has the local frequency — \(area), you're on the air.",
            "That's the sound of \(channel), broadcasting across \(area).",
            "Poplur's got \(area) covered. You're listening to \(channel)."
        ]
        return lines[((index % lines.count) + lines.count) % lines.count]
    }

    // MARK: Easter egg — hold the face for TV static (picture + sound)

    func startStatic() {
        isStatic = true
        activateSession()
        synth.stopSpeaking(at: .immediate)     // cut the host while held
        hostTimer?.invalidate(); hostTimer = nil
        watchdog?.invalidate(); watchdog = nil
        radio?.setVolume(0.05, fadeDuration: 0.1)
        noise = try? AVAudioPlayer(data: makeStaticWAV(duration: 1.6))
        noise?.numberOfLoops = -1
        noise?.volume = 0.75
        noise?.play()
    }

    func stopStatic() {
        isStatic = false
        noise?.stop()
        noise = nil
        radio?.setVolume(bedFull, fadeDuration: 0.4)
        if isRunning { scheduleTuneIn(after: 2.0) }   // resume the broadcast
    }
}

// MARK: - TV static overlay (press-and-hold easter egg)

private struct StaticOverlay: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let seed = Int(tl.date.timeIntervalSinceReferenceDate * 24)
            Canvas { ctx, size in
                let block: CGFloat = 5
                let cols = Int(size.width / block) + 1
                let rows = Int(size.height / block) + 1
                var s = UInt64(bitPattern: Int64(seed &+ 1)) ^ 6_364_136_223_846_793_005
                for row in 0..<rows {
                    for col in 0..<cols {
                        s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                        let v = Double(s >> 33) / Double(1 << 31)
                        ctx.fill(
                            Path(CGRect(x: CGFloat(col) * block, y: CGFloat(row) * block,
                                        width: block, height: block)),
                            with: .color(Color(white: v, opacity: 0.92))
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

// MARK: - Clay palette (matches the phone welcome / loading aesthetic)

private enum Clay {
    // Blue "loading" slab the background fades to on the phone.
    static let slab      = UIColor(red: 0.122, green: 0.420, blue: 1.0, alpha: 1)      // #1F6BFF
    static let slabHi    = UIColor(red: 0.184, green: 0.482, blue: 1.0, alpha: 1)      // #2F7BFF
    static let dot       = UIColor(red: 0.839, green: 0.063, blue: 0.424, alpha: 0.34) // pink stud
    // Confetti — Apple system colors, same set as the phone auth confetti.
    static let confetti: [UIColor] = [
        UIColor(red: 1.00, green: 0.176, blue: 0.333, alpha: 1),
        UIColor(red: 1.00, green: 0.584, blue: 0.00,  alpha: 1),
        UIColor(red: 1.00, green: 0.800, blue: 0.00,  alpha: 1),
        UIColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1),
        UIColor(red: 0.00,  green: 0.478, blue: 1.00,  alpha: 1),
        UIColor(red: 0.686, green: 0.322, blue: 0.871, alpha: 1)
    ]
    // Clay-pink readout gradient (white → pink), legible on blue.
    static let pink: [Color] = [
        Color(red: 1.0, green: 1.0, blue: 1.0),
        Color(red: 1.0, green: 0.827, blue: 0.917),
        Color(red: 1.0, green: 0.486, blue: 0.753),
        Color(red: 0.961, green: 0.235, blue: 0.600)
    ]
    static let green = Color(red: 0.541, green: 1.0, blue: 0.651)
    static let red   = Color(red: 1.0, green: 0.353, blue: 0.353)
}

// MARK: - Clay globe (real Poplur clay globe via GLTFSceneKit)

private struct ClayGlobeSceneView: WKInterfaceObjectRepresentable {
    typealias WKInterfaceObjectType = WKInterfaceSCNScene

    func makeWKInterfaceObject(context: Context) -> WKInterfaceSCNScene {
        let scnScene = WKInterfaceSCNScene()
        let scene = SCNScene()
        // WKInterfaceSCNScene renders opaque and a single-image scene background
        // would warp as an environment map, so put the blue clay-dot slab on a
        // flat unlit plane behind the globe; solid blue fills any margin.
        scene.background.contents = UIColor(red: 0.122, green: 0.420, blue: 1.0, alpha: 1)
        let backdrop = SCNNode(geometry: SCNPlane(width: 11, height: 13))
        if let m = backdrop.geometry?.firstMaterial {
            m.lightingModel = .constant
            m.isDoubleSided = true
            m.diffuse.contents = UIColor(red: 0.122, green: 0.420, blue: 1.0, alpha: 1)
            m.shaderModifiers = [.fragment: Self.dotShader]   // animated pulsing clay dots
        }
        backdrop.position = SCNVector3(0, 0.34, -8)
        scene.rootNode.addChildNode(backdrop)

        let globeNode = Self.loadClayGlobe() ?? Self.fallbackGlobe()
        RuntimeGlobe.normalize(globeNode, targetExtent: 1.62)
        globeNode.position = SCNVector3(0, 0.30, 0)         // centred in the face
        globeNode.eulerAngles = SCNVector3(0, 0, Float(-15.0 * .pi / 180))  // gentle clay tilt
        scene.rootNode.addChildNode(globeNode)

        globeNode.runAction(.repeatForever(
            .rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 12)
        ))

        // The 3D "poplur" wordmark floats in front of the globe, facing forward
        // (it holds still while the globe spins behind it).
        if let word = Self.loadWordmark() {
            RuntimeGlobe.normalize(word, targetExtent: 0.72)
            word.position = SCNVector3(0, 0.26, 1.9)
            scene.rootNode.addChildNode(word)
        }

        // Camera framed so the globe rides in the upper ~60% of the face.
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 32
        cameraNode.position = SCNVector3(0, 0.30, 3.5)   // level with the globe → centred
        scene.rootNode.addChildNode(cameraNode)

        // Warm key + cool fill + soft ambient — matches the phone's clay lighting.
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 850
        key.light?.color = UIColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1)
        key.eulerAngles = SCNVector3(-0.5, -0.5, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 280
        fill.light?.color = UIColor(red: 0.624, green: 0.816, blue: 1.0, alpha: 1)
        fill.eulerAngles = SCNVector3(0.3, 0.8, 0)
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 420
        ambient.light?.color = UIColor(red: 0.85, green: 0.90, blue: 1.0, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        scnScene.scene = scene
        scnScene.preferredFramesPerSecond = 30
        return scnScene
    }

    func updateWKInterfaceObject(_ wkInterfaceObject: WKInterfaceSCNScene, context: Context) {}

    // The clay globe ships as a self-contained USDZ (geometry + UVs), which
    // SceneKit loads natively on watchOS — no third-party glTF decoder.
    static func loadClayGlobe() -> SCNNode? {
        guard let asset = NSDataAsset(name: "poplur_clay_globe") else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("poplur_clay_globe.usdz")
        do { try asset.data.write(to: tmp, options: .atomic) } catch { return nil }
        guard let scene = try? SCNScene(url: tmp, options: nil) else { return nil }
        let root = SCNNode()
        for child in scene.rootNode.childNodes { root.addChildNode(child) }
        guard !root.childNodes.isEmpty else { return nil }
        applyClayTextures(to: root)
        return root
    }

    // The "poplur" wordmark ships as a self-contained USDZ; textures bound in code.
    static func loadWordmark() -> SCNNode? {
        guard let asset = NSDataAsset(name: "poplur_wordmark") else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("poplur_wordmark.usdz")
        do { try asset.data.write(to: tmp, options: .atomic) } catch { return nil }
        guard let scene = try? SCNScene(url: tmp, options: nil) else { return nil }
        let root = SCNNode()
        for child in scene.rootNode.childNodes { root.addChildNode(child) }
        guard !root.childNodes.isEmpty else { return nil }
        let base = UIImage(named: "word_basecolor")
        let normalMap = UIImage(named: "word_normal")
        let emissive = UIImage(named: "word_emissive")
        root.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            for material in geometry.materials {
                material.lightingModel = .blinn
                material.diffuse.contents = base
                material.normal.contents = normalMap
                material.emission.contents = emissive
                material.specular.contents = UIColor(white: 0.12, alpha: 1)
                material.shininess = 0.4
            }
        }
        return root
    }

    // Fragment shader modifier: blue slab + pink clay dots that pulse over time.
    static let dotShader = """
    #pragma body
    vec2 uv = _surface.diffuseTexcoord;
    float hi = 1.0 - smoothstep(0.0, 0.55, distance(uv, vec2(0.5, 0.72)));
    vec3 base = mix(vec3(0.122, 0.420, 1.0), vec3(0.184, 0.482, 1.0), hi * 0.5);
    vec2 grid = vec2(uv.x * 46.0, uv.y * 55.0);
    vec2 g = fract(grid) - 0.5;
    // Travelling wave across the grid so the studs visibly breathe (matches the
    // phone's pulsing clay-dot field) — each dot also swells, not just brightens.
    float phase = u_time * 2.4 - (floor(grid.x) * 0.45 + floor(grid.y) * 0.38);
    float pulse = 0.5 + 0.5 * sin(phase);
    float dotMask = 1.0 - smoothstep(0.10 + 0.06 * pulse, 0.26 + 0.06 * pulse, length(g));
    float a = dotMask * (0.10 + 0.40 * pulse);
    _output.color.rgb = mix(base, vec3(0.839, 0.063, 0.424), a);
    _output.color.a = 1.0;
    """

    // SceneKit's USD import reads geometry + UVs but not the usdz's textures,
    // so bind the baked JPEG maps (bundled as imagesets) onto every material.
    private static func applyClayTextures(to root: SCNNode) {
        let base = UIImage(named: "clay_basecolor")
        let normalMap = UIImage(named: "clay_normal")
        let emissive = UIImage(named: "clay_emissive")
        root.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            for material in geometry.materials {
                material.lightingModel = .blinn
                material.diffuse.contents = base
                material.normal.contents = normalMap
                material.emission.contents = emissive
                material.specular.contents = UIColor(white: 0.10, alpha: 1)
                material.shininess = 0.35
                material.isDoubleSided = false
            }
        }
    }

    // Blue clay-slab dot background, baked once for the opaque scene.
    static func backgroundImage() -> UIImage {
        // Create a bitmap context using Core Graphics (available on watchOS)
        let size = CGSize(width: 200, height: 244)
        let width = Int(size.width)
        let height = Int(size.height)
        let bitsPerComponent = 8
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return UIImage()
        }

        // Allocate pixel buffer
        guard let data = calloc(height, bytesPerRow) else {
            return UIImage()
        }
        defer { free(data) }

        guard let ctx = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return UIImage()
        }

        // Flip to match UIKit coordinate system for consistency
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        // Background fill (blue slab)
        ctx.setFillColor(UIColor(red: 0.122, green: 0.420, blue: 1.0, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        // Soft top highlight (radial gradient)
        let gradColors = [
            UIColor(red: 0.184, green: 0.482, blue: 1.0, alpha: 0.55).cgColor,
            UIColor(red: 0.122, green: 0.420, blue: 1.0, alpha: 0.0).cgColor
        ] as CFArray
        let locations: [CGFloat] = [0.0, 1.0]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: locations) {
            let w = size.width, h = size.height
            let center = CGPoint(x: w * 0.5, y: h * 0.30)
            ctx.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: h * 0.5,
                options: []
            )
        }

        // Pink clay stud dots on a 9pt grid
        ctx.setFillColor(UIColor(red: 0.839, green: 0.063, blue: 0.424, alpha: 0.34).cgColor)
        let step: CGFloat = 9
        let dot: CGFloat = 1.2
        var y: CGFloat = step / 2
        while y < size.height {
            var x: CGFloat = step / 2
            while x < size.width {
                let rect = CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2)
                ctx.fillEllipse(in: rect)
                x += step
            }
            y += step
        }

        // Create image
        guard let cgImage = ctx.makeImage() else { return UIImage() }
        return UIImage(cgImage: cgImage, scale: WKInterfaceDevice.current().screenScale, orientation: .up)
    }

    // Simple clay-blue sphere if the model can't be decoded.
    static func fallbackGlobe() -> SCNNode {
        let sphere = SCNSphere(radius: 1.0)
        sphere.segmentCount = 48
        let mat = SCNMaterial()
        mat.lightingModel = .blinn
        mat.diffuse.contents = UIColor(red: 0.13, green: 0.45, blue: 0.86, alpha: 1)
        sphere.materials = [mat]
        return SCNNode(geometry: sphere)
    }
}

// Local center/scale helper (RuntimeGLBLoader lives in the phone target only).
private enum RuntimeGlobe {
    static func normalize(_ node: SCNNode, targetExtent: Float) {
        let (minB, maxB) = node.boundingBox
        var lo = minB, hi = maxB
        node.enumerateChildNodes { child, _ in
            guard child.geometry != nil else { return }
            let b = child.boundingBox
            let corners = [
                SCNVector3(b.min.x, b.min.y, b.min.z), SCNVector3(b.max.x, b.max.y, b.max.z)
            ]
            for c in corners {
                let p = child.convertPosition(c, to: node)
                lo = SCNVector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
                hi = SCNVector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
            }
        }
        let size = SCNVector3(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
        let maxDim = max(size.x, max(size.y, size.z))
        guard maxDim.isFinite, maxDim > 0 else { return }
        let center = SCNVector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
        let scale = targetExtent / maxDim
        node.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
        node.scale = SCNVector3(scale, scale, scale)
    }
}

// MARK: - Blue clay-slab dot background

private struct ClayBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // Blue slab + soft top highlight
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(Clay.slab)))
            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.1, y: -h * 0.35, width: w * 0.8, height: h * 0.9)),
                with: .radialGradient(
                    Gradient(colors: [Color(Clay.slabHi).opacity(0.55), .clear]),
                    center: CGPoint(x: w * 0.5, y: h * 0.34),
                    startRadius: 0, endRadius: h * 0.55
                )
            )
            // Pink clay stud dots on a 9pt grid
            let step: CGFloat = 9
            let r: CGFloat = 1.2
            var y: CGFloat = step / 2
            while y < h {
                var x: CGFloat = step / 2
                while x < w {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(Color(Clay.dot)))
                    x += step
                }
                y += step
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Confetti (falling clay-color chips, phone auth-confetti feel)

private struct ConfettiChip {
    let x0: CGFloat        // 0..1 horizontal start
    let delay: Double
    let dur: Double
    let drift: CGFloat     // horizontal drift fraction
    let size: CGFloat
    let spin: Double
    let color: Color
}

private struct ConfettiLayer: View {
    let chips: [ConfettiChip]

    init(count: Int = 30) {
        // Deterministic pseudo-random from index — no per-frame allocation.
        var out: [ConfettiChip] = []
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            // `seed >> 33` tops out at 2^31, so dividing by UInt32.max only ever
            // reached 0.5 — which pinned every chip to the left half of the face.
            return Double(seed >> 33) / Double(1 << 31)
        }
        for _ in 0..<count {
            let palette = Clay.confetti
            let chipColor: Color = {
                guard !palette.isEmpty else { return .white }
                let raw = rnd() * Double(palette.count)
                let idx = max(0, min(palette.count - 1, Int(raw)))
                return Color(palette[idx])
            }()
            out.append(ConfettiChip(
                x0: CGFloat(rnd()),
                delay: rnd() * 3.2,
                dur: 3.0 + rnd() * 2.2,
                drift: CGFloat(rnd() - 0.5) * 0.28,
                size: 6 + CGFloat(rnd()) * 5,
                spin: (rnd() - 0.5) * 8,
                color: chipColor
            ))
        }
        chips = out
    }

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width, h = size.height
                for c in chips {
                    let phase = ((t + c.delay).truncatingRemainder(dividingBy: c.dur)) / c.dur
                    let y = CGFloat(phase) * (h + 30) - 15
                    let x = c.x0 * w + CGFloat(sin(phase * .pi * 2)) * c.drift * w
                    let alpha = phase < 0.85 ? 1.0 : (1.0 - (phase - 0.85) / 0.15)
                    var chip = ctx
                    chip.translateBy(x: x, y: y)
                    chip.rotate(by: .radians(c.spin * phase * .pi))
                    chip.opacity = alpha
                    chip.fill(
                        Path(roundedRect: CGRect(x: -c.size / 2, y: -c.size * 0.9,
                                                 width: c.size, height: c.size * 1.8),
                             cornerRadius: 1),
                        with: .color(c.color)
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Clay-pink radius / posts readout

private struct ClayReadout: View {
    @ObservedObject var store: WatchRadiusStore
    let showKm: Bool

    private var pink: LinearGradient {
        LinearGradient(colors: Clay.pink, startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(spacing: 1) {
            Text("RADIUS")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(Color(red: 0.87, green: 0.93, blue: 1.0))

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(store.displayValue(metric: showKm))
                    .font(.system(size: 30, weight: .black, design: .rounded))
                Text(showKm ? "km" : "mi")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(pink)
            .shadow(color: Color(red: 0.47, green: 0.0, blue: 0.24).opacity(0.55), radius: 1, y: 1)
            .id("radius_\(showKm)")
            .transition(.opacity)

            HStack(spacing: 3) {
                trendGlyph
                Text("\(store.postCount) posts")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.92, green: 0.95, blue: 1.0))
            }
        }
        .shadow(color: Color(red: 0.03, green: 0.07, blue: 0.31).opacity(0.55), radius: 3, y: 1)
        .animation(.easeInOut(duration: 0.35), value: showKm)
    }

    @ViewBuilder private var trendGlyph: some View {
        switch store.trend {
        case .up:     Image(systemName: "triangle.fill").font(.system(size: 8, weight: .black)).foregroundColor(Clay.green)
        case .down:   Image(systemName: "triangle.fill").rotationEffect(.degrees(180)).font(.system(size: 8, weight: .black)).foregroundColor(Clay.red)
        case .stable: Rectangle().fill(Clay.green.opacity(0.8)).frame(width: 8, height: 2).cornerRadius(1)
        }
    }
}

// MARK: - Main watch view

struct RadiusWatchView: View {
    @EnvironmentObject private var store: WatchRadiusStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var showStatic = false
    @State private var showKm = true
    private let switchTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // The globe scene fills the face and carries the blue clay-dot slab as
            // its baked background; confetti + readout overlay on top.
            ClayGlobeSceneView()
            ConfettiLayer()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ClayReadout(store: store, showKm: showKm)
                    .padding(.bottom, 4)
            }

            // Easter egg: hold the face and it drops to TV static, picture + sound.
            if showStatic { StaticOverlay() }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        // Press-and-hold anywhere on the face → static while held, back on release.
        // watchOS long-press: `perform` fires once the hold threshold is crossed,
        // `onPressingChanged(false)` fires on release (also after a plain tap, where
        // stopStatic() is a harmless no-op) — a quick tap still toggles km/mi.
        .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 60, perform: {
            withAnimation(.easeIn(duration: 0.12)) { showStatic = true }
            WatchAudio.shared.startStatic()
        }, onPressingChanged: { pressing in
            if !pressing {
                withAnimation(.easeOut(duration: 0.22)) { showStatic = false }
                WatchAudio.shared.stopStatic()
            }
        })
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.35)) { showKm.toggle() }
        }
        .onReceive(switchTimer) { _ in
            withAnimation(.easeInOut(duration: 0.35)) { showKm.toggle() }
        }
        .onAppear { WatchAudio.shared.startRadio(); store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { WatchAudio.shared.startRadio(); store.refresh() }
            else { WatchAudio.shared.stopRadio(); WatchAudio.shared.stopStatic() }
        }
        .persistentSystemOverlays(.hidden)
        .accessibilityLabel("Poplur watch — clay globe. Tap to toggle km/mi, hold for static.")
    }
}

// MARK: - WatchRadiusStore

@MainActor
final class WatchRadiusStore: NSObject, ObservableObject {
    @Published private(set) var radiusMeters: Double
    @Published private(set) var postCount: Int
    @Published private(set) var updatedAt: Date?
    @Published private(set) var trend: RadiusTrend = .stable

    private let radiusKey  = "poplur.watch.overallRadiusMeters"
    private let prevKey    = "poplur.watch.previousRadiusMeters"
    private let postKey    = "poplur.watch.postCount"
    private let updatedKey = "poplur.watch.updatedAt"

    override init() {
        let d = UserDefaults.standard
        radiusMeters = d.double(forKey: "poplur.watch.overallRadiusMeters")
        postCount    = d.integer(forKey: "poplur.watch.postCount")
        let ts = d.double(forKey: "poplur.watch.updatedAt")
        updatedAt = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        super.init()
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        recomputeTrend()
        configureSession()
    }

    var batteryPercent: Int {
        let level = WKInterfaceDevice.current().batteryLevel
        return level < 0 ? 0 : Int(level * 100)
    }

    func displayValue(metric: Bool) -> String {
        guard updatedAt != nil else { return "—" }
        guard radiusMeters > 0 else { return "0" }
        if metric {
            let km = radiusMeters / 1_000
            return km >= 10 ? String(format: "%.0f", km) : String(format: "%.1f", km)
        } else {
            let mi = radiusMeters / 1_609.344
            return mi >= 10 ? String(format: "%.0f", mi) : String(format: "%.1f", mi)
        }
    }

    var needsPhoneSync: Bool { updatedAt == nil }

    private func recomputeTrend() {
        let prev = UserDefaults.standard.double(forKey: prevKey)
        guard prev > 0, radiusMeters > 0 else { trend = .stable; return }
        let delta     = radiusMeters - prev
        let threshold = max(radiusMeters * 0.03, 1_000.0)
        trend = delta > threshold ? .up : delta < -threshold ? .down : .stable
    }

    private func apply(_ payload: [String: Any]) {
        guard let snapshot = WatchRadiusSnapshot(payload: payload),
              snapshot.shouldReplace(lastUpdatedAt: updatedAt) else { return }

        let d = UserDefaults.standard
        d.set(radiusMeters, forKey: prevKey)
        radiusMeters = snapshot.radiusMeters
        postCount    = snapshot.postCount
        updatedAt    = Date(timeIntervalSince1970: snapshot.updatedAt)
        d.set(radiusMeters, forKey: radiusKey)
        d.set(postCount,    forKey: postKey)
        d.set(snapshot.updatedAt, forKey: updatedKey)
        recomputeTrend()
    }

    func refresh() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        // A context delivered before this process activated is not replayed as
        // a delegate callback. Consume the persisted value, then ask the phone.
        apply(session.receivedApplicationContext)
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": "radiusSnapshot"], replyHandler: { [weak self] payload in
            Task { @MainActor in self?.apply(payload) }
        }, errorHandler: { error in
            print("[WatchRadiusStore] Radius refresh pending: \(error.localizedDescription)")
        })
    }

    private func configureSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

}

extension WatchRadiusStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.refresh() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }
}

#Preview {
    RadiusWatchView()
        .environmentObject(WatchRadiusStore())
}
