import SpriteKit
import AVFoundation

class HomeFeedLaunchCoverScene: SKScene {

    private var logoNode: SKSpriteNode?
    private var popPlayer: AVAudioPlayer?

    // MARK: - Setup

    static func make() -> HomeFeedLaunchCoverScene {
        let scene = HomeFeedLaunchCoverScene()
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .white
        return scene
    }

    override func didMove(to view: SKView) {
        backgroundColor = .white
        setupLogo()
        startPopLoop()
    }

    private func setupLogo() {
        let logo = SKSpriteNode(imageNamed: "logo")
        logo.size = CGSize(width: 140, height: 140)
        logo.position = CGPoint(x: size.width / 2, y: size.height / 2)
        logo.zPosition = 10
        addChild(logo)
        logoNode = logo
        startIdlePulse()
    }

    private func startIdlePulse() {
        logoNode?.removeAction(forKey: "idle")
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 0.85),
            SKAction.scale(to: 0.95, duration: 0.85)
        ])
        logoNode?.run(.repeatForever(pulse), withKey: "idle")
    }

    // MARK: - Pop Loop

    private func startPopLoop() {
        let popAction = SKAction.run { [weak self] in self?.triggerPop() }
        run(.sequence([
            .wait(forDuration: 0.5),
            popAction,
            .repeatForever(.sequence([
                .wait(forDuration: 2.8),
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
        ])) { [weak self] in
            self?.startIdlePulse()
        }

        emitConfetti(at: logo.position)
    }

    // MARK: - Confetti

    private func emitConfetti(at center: CGPoint) {
        let palette: [UIColor] = [
            UIColor(red: 0.98, green: 0.24, blue: 0.24, alpha: 1),
            UIColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1),
            UIColor(red: 1.00, green: 0.88, blue: 0.00, alpha: 1),
            UIColor(red: 0.18, green: 0.80, blue: 0.24, alpha: 1),
            UIColor(red: 0.20, green: 0.52, blue: 0.98, alpha: 1),
            UIColor(red: 0.76, green: 0.18, blue: 0.90, alpha: 1),
            UIColor(red: 0.98, green: 0.28, blue: 0.65, alpha: 1),
            UIColor(red: 0.00, green: 0.78, blue: 0.80, alpha: 1),
        ]
        for i in 0..<52 {
            spawnPiece(at: center, color: palette[i % palette.count], index: i)
        }
    }

    private func spawnPiece(at center: CGPoint, color: UIColor, index: Int) {
        let w = CGFloat.random(in: 6...15)
        let h = CGFloat.random(in: 5...10)

        let shape: SKShapeNode
        if index % 6 == 0 {
            shape = SKShapeNode(circleOfRadius: w * 0.45)
        } else if index % 6 == 3 {
            // Thin streamer strip
            shape = SKShapeNode(rectOf: CGSize(width: 2, height: h * 1.8), cornerRadius: 1)
        } else {
            shape = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 1.5)
        }
        shape.fillColor = color
        shape.strokeColor = .clear
        shape.position = center
        shape.zPosition = CGFloat.random(in: 6...9)
        addChild(shape)

        let angle = CGFloat.random(in: 0...(2 * .pi))
        let speed = CGFloat.random(in: 200...460)
        let vx = cos(angle) * speed
        let vy = sin(angle) * speed

        let burstDur = Double.random(in: 0.32...0.60)
        let fallDur  = Double.random(in: 0.50...0.85)
        let fallDist = CGFloat.random(in: 260...540)

        // Burst outward
        let burst = SKAction.move(by: CGVector(dx: vx * burstDur, dy: vy * burstDur), duration: burstDur)
        burst.timingMode = .easeOut

        // Fall with gravity
        let fall = SKAction.move(by: CGVector(dx: vx * fallDur * 0.06, dy: -fallDist), duration: fallDur)
        fall.timingMode = .easeIn

        let spin = SKAction.rotate(byAngle: CGFloat.random(in: -7...7), duration: burstDur + fallDur)
        let delayFade = SKAction.wait(forDuration: burstDur + fallDur * 0.40)
        let fadeOut  = SKAction.fadeOut(withDuration: fallDur * 0.60)

        shape.run(.group([
            .sequence([burst, fall, .removeFromParent()]),
            spin,
            .sequence([delayFade, fadeOut])
        ]))
    }

    // MARK: - Pop Sound (synthesised bubble-pop)

    private func playPopSound() {
        guard let data = synthesisePopWAV() else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        do {
            let player = try AVAudioPlayer(data: data)
            player.volume = 0.62
            player.play()
            popPlayer = player // retain until playback finishes
        } catch {}
    }

    private func synthesisePopWAV() -> Data? {
        let sr: Double = 44100
        let dur: Double = 0.13
        let count = Int(sr * dur)
        var samples: [Int16] = []
        samples.reserveCapacity(count)

        for i in 0..<count {
            let t = Double(i) / sr
            // Exponential envelope — punchy attack, fast decay
            let env = exp(-t * 38.0)
            // Pitch sweeps from 680 Hz down to ~90 Hz (gives the "pop" character)
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
        data.append(contentsOf: "RIFF".utf8)
        le32(36 + dataLen)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        le32(16); le16(1); le16(1)            // PCM, mono
        le32(sampleRate)
        le32(sampleRate * 2)                   // byte rate
        le16(2); le16(16)                      // block align, bits per sample
        data.append(contentsOf: "data".utf8)
        le32(dataLen)
        for s in samples { le16(UInt16(bitPattern: s)) }
        return data
    }
}
