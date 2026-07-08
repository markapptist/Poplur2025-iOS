import AVFoundation
import Foundation

// MARK: - PoplurFPS procedural audio
//
// All SFX are synthesised at runtime (no audio files) into short PCM buffers and
// played through a small pool of AVAudioPlayerNodes so shots/hits can overlap.
// Retro square/saw/noise voices match the pixel-art arcade aesthetic.

enum FPSSfx {
    case shoot(Int)        // weapon index 0..4
    case enemyHit
    case enemyDie
    case pickup
    case hurt
    case menuSelect
    case footstep
    case win
    case lose
    case door
}

final class FPSAudio {
    private enum Wave { case sine, square, saw, triangle }

    private let sr: Double = 22050
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var players: [AVAudioPlayerNode] = []
    private var idx = 0
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var started = false
    var enabled = true

    init() {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 22050,
                               channels: 1, interleaved: false)!
        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.55
        configureSession()
        prerender()
        start()
    }

    private func configureSession() {
        // .ambient → mixes with other audio and respects the mute switch.
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.ambient, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    private func start() {
        guard !started else { return }
        do {
            try engine.start()
            for p in players { p.play() }
            started = true
        } catch { started = false }
    }

    // MARK: Playback

    func play(_ sfx: FPSSfx) {
        guard enabled else { return }
        if !started { start() }
        guard started, let buf = cache[key(for: sfx)] else { return }
        let p = players[idx]
        idx = (idx + 1) % players.count
        p.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
    }

    private func key(for sfx: FPSSfx) -> String {
        switch sfx {
        case .shoot(let w):  return "shoot\(max(0, min(4, w)))"
        case .enemyHit:      return "hit"
        case .enemyDie:      return "die"
        case .pickup:        return "pickup"
        case .hurt:          return "hurt"
        case .menuSelect:    return "menu"
        case .footstep:      return "step"
        case .win:           return "win"
        case .lose:          return "lose"
        case .door:          return "door"
        }
    }

    // MARK: Synthesis

    private func prerender() {
        cache["shoot0"] = buffer(synth(0.12, 780, 220, .square, 0.15, 30, 0.5))                    // pistol
        cache["shoot1"] = buffer(mix(synth(0.24, 320, 90, .saw, 0.55, 14, 0.55),
                                     synth(0.10, 180, 60, .sine, 0.7, 24, 0.4)))                   // shotgun
        cache["shoot2"] = buffer(mix(synth(0.18, 520, 940, .square, 0.05, 15, 0.42),
                                     synth(0.18, 260, 470, .sine, 0.0, 15, 0.25)))                 // plasma
        cache["shoot3"] = buffer(mix(synth(0.34, 170, 55, .saw, 0.7, 8, 0.6),
                                     synth(0.20, 90, 40, .sine, 0.4, 10, 0.4)))                    // rocket
        cache["shoot4"] = buffer(mix(synth(0.34, 1600, 300, .sine, 0.08, 9, 0.4),
                                     synth(0.30, 800, 150, .square, 0.05, 11, 0.2)))               // railgun
        cache["hit"]    = buffer(synth(0.09, 420, 180, .square, 0.4, 30, 0.4))
        cache["die"]    = buffer(mix(synth(0.42, 320, 42, .saw, 0.3, 6, 0.5),
                                     synth(0.20, 160, 60, .square, 0.5, 12, 0.3)))
        cache["pickup"] = buffer(arp([660, 990, 1320], 0.06, .square, 0.4))
        cache["hurt"]   = buffer(mix(synth(0.26, 220, 120, .saw, 0.5, 10, 0.5),
                                     synth(0.12, 140, 80, .sine, 0.6, 16, 0.3)))
        cache["menu"]   = buffer(synth(0.08, 900, 1350, .square, 0, 22, 0.4))
        cache["step"]   = buffer(synth(0.06, 120, 70, .sine, 0.6, 40, 0.22))
        cache["win"]    = buffer(arp([523, 659, 784, 1046], 0.11, .square, 0.42))
        cache["lose"]   = buffer(arp([440, 349, 262], 0.16, .saw, 0.45))
        cache["door"]   = buffer(mix(synth(0.5, 90, 135, .saw, 0.25, 3, 0.34),
                                     synth(0.5, 60, 70, .sine, 0.1, 3, 0.2)))
    }

    /// One voice: pitch glides f0→f1 over `dur`, exponential amplitude decay, optional noise blend.
    private func synth(_ dur: Double, _ f0: Double, _ f1: Double, _ wave: Wave,
                       _ noise: Double, _ decay: Double, _ vol: Double) -> [Float] {
        let n = max(1, Int(dur * sr))
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let frac = t / dur
            let f = f0 + (f1 - f0) * frac
            phase += f / sr
            let ph = phase.truncatingRemainder(dividingBy: 1)
            var s: Double
            switch wave {
            case .sine:     s = sin(2 * .pi * ph)
            case .square:   s = ph < 0.5 ? 1 : -1
            case .saw:      s = 2 * ph - 1
            case .triangle: s = 4 * abs(ph - 0.5) - 1
            }
            if noise > 0 { s = s * (1 - noise) + Double.random(in: -1...1) * noise }
            // short 3ms attack to avoid clicks
            let attack = min(1.0, t / 0.003)
            let amp = exp(-t * decay) * attack
            out[i] = Float(max(-1, min(1, s * amp * vol)))
        }
        return out
    }

    private func arp(_ freqs: [Double], _ noteDur: Double, _ wave: Wave, _ vol: Double) -> [Float] {
        var out: [Float] = []
        for f in freqs { out += synth(noteDur, f, f, wave, 0, 9, vol) }
        return out
    }

    private func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        let n = max(a.count, b.count)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let v = (i < a.count ? a[i] : 0) + (i < b.count ? b[i] : 0)
            out[i] = max(-1, min(1, v))
        }
        return out
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: format,
                                   frameCapacity: AVAudioFrameCount(samples.count))!
        buf.frameLength = AVAudioFrameCount(samples.count)
        let ch = buf.floatChannelData![0]
        for i in 0..<samples.count { ch[i] = samples[i] }
        return buf
    }
}
