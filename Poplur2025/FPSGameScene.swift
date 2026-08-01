import SpriteKit
import UIKit

// MARK: - PoplurFPS SpriteKit scene
//
// The software raycaster (FPSRenderer) renders the game into a 640x360 pixel
// buffer shown on `framebuffer`. Presentation is orientation-aware:
//   • Portrait  → the game sits in a "CRT" band with an arcade cabinet marquee
//     above and a control panel (joystick + coloured buttons) below — the
//     cabinet's buttons are the controls.
//   • Landscape → the game fills the screen with translucent floating controls.

final class FPSGameScene: SKScene {
    private let game = FPSGame()
    private let renderer = FPSRenderer()
    private let audio = FPSAudio()
    private var framebuffer: SKSpriteNode!

    private var lastTime: TimeInterval = 0
    private var assetsLoading = false

    // Touch state
    private var joyTouch: UITouch?
    private var joyCenter = CGPoint.zero
    private var joyVec = CGVector.zero
    private var lookTouch: UITouch?
    private var lookLastX: CGFloat = 0
    private var lookDX: Double = 0
    private var fireTouch: UITouch?
    private var interactPending = false
    private var weaponPending = 0        // 0 = none, else weapon index+1
    private var tapPending = false

    // Chrome / control nodes
    private var marqueeBg: SKShapeNode!
    private var marqueeLabel: SKLabelNode!
    private var panelBg: SKShapeNode!
    private var joyBase: SKShapeNode!
    private var joyThumb: SKShapeNode!
    private var buttons: [SKShapeNode] = []   // [0]=fire [1]=interact [2..4]=weapons (landscape translucent)

    // Portrait arcade panel: real neon-panel sprites from the spritesheet as buttons.
    private var panelButtons: [SKSpriteNode] = []   // [0]=fire [1]=use [2..4]=weapons
    private var panelLabels: [SKLabelNode] = []      // weapon number labels on [2..4]
    private var texFire: SKTexture?
    private var texUse: SKTexture?
    private var texWeapon: SKTexture?

    /// Retained for the attract artwork, but gameplay uses the full device viewport.
    /// Aspect-fitting this landscape cabinet in portrait made the live game and its
    /// painted touch targets too small to play.
    private var cabinetNode: SKSpriteNode!
    private enum Cab {
        static let bezel = CGRect(x: 0.2051, y: 0.2247, width: 0.5829, height: 0.5239)  // y-down
        static let joy = (cx: 0.1885, cy: 0.8333, r: 0.0442)
        static let btnR = 0.0276
        static let btnCY = 0.8259
        // green=fire, blue=use, pink=w1, red=w2, red=w3   (yellow START handled separately)
        static let btnCX: [Double] = [0.5028, 0.6022, 0.4013, 0.7099, 0.8032]
        static let startCX = 0.3066     // yellow "START" button → pause
    }
    private var startBtnC = CGPoint.zero
    private var startBtnR: CGFloat = 0

    /// Called when the player taps QUIT in the pause menu.
    var onQuit: (() -> Void)?

    // Pause button + pause menu (SpriteKit nodes so they're crisp and tappable)
    private var pauseBtn: SKShapeNode!
    private var pauseBtnFrame: CGRect = .zero
    private var pauseOverlay: SKNode!
    private var pauseDim: SKSpriteNode!
    private var pauseTitle: SKLabelNode!
    private var pauseOptionNodes: [(bg: SKShapeNode, label: SKLabelNode)] = []
    private var pauseOptionFrames: [CGRect] = []
    private let pauseOptions = ["RESUME", "RESTART", "QUIT"]

    // Current-frame control geometry (scene coords, y-up)
    private var joyC = CGPoint.zero; private var joyR: CGFloat = 46
    private var fireC = CGPoint.zero; private var fireR: CGFloat = 40
    private var interactC = CGPoint.zero; private var interactR: CGFloat = 28
    private var weaponCR: [(CGPoint, CGFloat)] = []
    private var portrait = false

    private let btnColors: [UIColor] = [
        UIColor(fpsHex: 0xffd700), UIColor(fpsHex: 0xff4db8), UIColor(fpsHex: 0x00ff88),
        UIColor(fpsHex: 0x4488ff), UIColor(fpsHex: 0xff4db8)
    ]

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0, y: 0)
        backgroundColor = .black
        scaleMode = .resizeFill

        framebuffer = SKSpriteNode(color: .black, size: size)
        framebuffer.anchorPoint = CGPoint(x: 0, y: 0)
        framebuffer.zPosition = 0
        addChild(framebuffer)

        marqueeBg = SKShapeNode(); marqueeBg.fillColor = UIColor(fpsHex: 0x1a0030); marqueeBg.strokeColor = .clear; marqueeBg.zPosition = 5
        addChild(marqueeBg)
        marqueeLabel = SKLabelNode(fontNamed: "Menlo-Bold"); marqueeLabel.fontColor = UIColor(fpsHex: 0xffd700); marqueeLabel.verticalAlignmentMode = .center; marqueeLabel.zPosition = 6; marqueeLabel.text = "poplur"
        addChild(marqueeLabel)
        panelBg = SKShapeNode(); panelBg.fillColor = UIColor(fpsHex: 0x140022); panelBg.strokeColor = UIColor(fpsHex: 0xc8960a); panelBg.lineWidth = 2; panelBg.zPosition = 5
        addChild(panelBg)

        joyBase = SKShapeNode(circleOfRadius: 46); joyBase.zPosition = 10; addChild(joyBase)
        joyThumb = SKShapeNode(circleOfRadius: 22); joyThumb.zPosition = 11; addChild(joyThumb)
        for _ in 0..<5 {
            let b = SKShapeNode(circleOfRadius: 24); b.zPosition = 10; b.lineWidth = 0
            buttons.append(b); addChild(b)
        }

        // The real cabinet artwork sits behind everything in portrait.
        cabinetNode = SKSpriteNode(texture: panelTexture("01_title_screen/cabinet.png"))
        cabinetNode.zPosition = -1
        cabinetNode.isHidden = true
        addChild(cabinetNode)
        for _ in 0..<5 {
            let s = SKSpriteNode(); s.zPosition = 10; s.isHidden = true
            panelButtons.append(s); addChild(s)
            let l = SKLabelNode(fontNamed: "Menlo-Bold")
            l.fontColor = .white; l.verticalAlignmentMode = .center; l.horizontalAlignmentMode = .center
            l.zPosition = 11; l.isHidden = true
            panelLabels.append(l); addChild(l)
        }

        buildPauseUI()
        setChromeVisible(false)
        game.onSound = { [weak self] sfx in self?.audio.play(sfx) }
        loadAssetsAsync()
    }

    // MARK: Pause UI

    private func buildPauseUI() {
        // Small pause pill, shown top-left while playing.
        pauseBtn = SKShapeNode(circleOfRadius: 20)
        pauseBtn.fillColor = UIColor(white: 0, alpha: 0.42)
        pauseBtn.strokeColor = UIColor(white: 1, alpha: 0.35)
        pauseBtn.lineWidth = 1.5
        pauseBtn.zPosition = 100
        pauseBtn.isHidden = true
        addChild(pauseBtn)
        for dx in [CGFloat(-4), CGFloat(4)] {
            let bar = SKSpriteNode(color: .white, size: CGSize(width: 3.4, height: 14))
            bar.position = CGPoint(x: dx, y: 0)
            pauseBtn.addChild(bar)
        }

        // Full-screen pause menu.
        pauseOverlay = SKNode()
        pauseOverlay.zPosition = 200
        pauseOverlay.isHidden = true
        addChild(pauseOverlay)

        pauseDim = SKSpriteNode(color: UIColor(white: 0, alpha: 0.72), size: size)
        pauseDim.anchorPoint = CGPoint(x: 0, y: 0)
        pauseOverlay.addChild(pauseDim)

        pauseTitle = SKLabelNode(fontNamed: "Menlo-Bold")
        pauseTitle.text = "PAUSED"
        pauseTitle.fontColor = UIColor(fpsHex: 0xff2d8a)
        pauseTitle.verticalAlignmentMode = .center
        pauseTitle.zPosition = 1
        pauseOverlay.addChild(pauseTitle)

        for title in pauseOptions {
            let bg = SKShapeNode()
            bg.fillColor = UIColor(fpsHex: 0x1a0030, alpha: 0.95)
            bg.strokeColor = UIColor(fpsHex: 0xffd700)
            bg.lineWidth = 2
            bg.zPosition = 1
            pauseOverlay.addChild(bg)

            let lbl = SKLabelNode(fontNamed: "Menlo-Bold")
            lbl.text = title
            lbl.fontColor = .white
            lbl.verticalAlignmentMode = .center
            lbl.horizontalAlignmentMode = .center
            lbl.zPosition = 2
            pauseOverlay.addChild(lbl)

            pauseOptionNodes.append((bg, lbl))
        }
    }

    private func layoutPauseUI() {
        let sw = size.width, sh = size.height
        let playing = game.state == .playing
        let paused = game.state == .paused

        pauseBtn.isHidden = !playing
        let pc = CGPoint(x: 44, y: sh - 56)
        pauseBtn.position = pc
        pauseBtnFrame = CGRect(x: pc.x - 26, y: pc.y - 26, width: 52, height: 52)

        pauseOverlay.isHidden = !paused
        guard paused else { return }

        pauseDim.size = size
        pauseDim.position = .zero

        let bw = min(260, sw * 0.62), bh: CGFloat = 48, gap: CGFloat = 14
        let total = CGFloat(pauseOptions.count) * bh + CGFloat(pauseOptions.count - 1) * gap
        let top = sh / 2 + total / 2

        pauseTitle.fontSize = min(44, sw * 0.11)
        pauseTitle.position = CGPoint(x: sw / 2, y: top + 56)

        pauseOptionFrames = []
        for (i, node) in pauseOptionNodes.enumerated() {
            let cy = top - CGFloat(i) * (bh + gap) - bh / 2
            let rect = CGRect(x: sw / 2 - bw / 2, y: cy - bh / 2, width: bw, height: bh)
            node.bg.path = CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
            node.label.position = CGPoint(x: sw / 2, y: cy)
            node.label.fontSize = 19
            pauseOptionFrames.append(rect)
        }
    }

    /// Drop any held joystick / fire / look touches so they don't stay latched across a pause.
    private func releaseControlTouches() {
        joyTouch = nil; fireTouch = nil; lookTouch = nil
        joyVec = .zero; lookDX = 0
        joyThumb.position = joyC
    }

    private func handlePauseTap(_ p: CGPoint) {
        for (i, rect) in pauseOptionFrames.enumerated() where rect.contains(p) {
            switch i {
            case 0: game.resumeGame()
            case 1: game.restartGame()
            default: audio.play(.menuSelect); onQuit?()
            }
            return
        }
    }

    private func setChromeVisible(_ v: Bool) {
        let a: CGFloat = v ? 1 : 0
        marqueeBg.alpha = a; marqueeLabel.alpha = a; panelBg.alpha = a
        joyBase.alpha = a; joyThumb.alpha = a
        for b in buttons { b.alpha = a }
        for s in panelButtons { s.alpha = a }
        for l in panelLabels { l.alpha = a }
    }

    /// Load a spritesheet PNG as a nearest-filtered SKTexture (same bundle layout as FPSAssets).
    private func panelTexture(_ rel: String) -> SKTexture? {
        let parts = rel.split(separator: "/")
        guard parts.count == 2 else { return nil }
        let dir = "PoplurFPS/sprites/\(parts[0])"
        let file = parts[1]
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: dir)
                ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "PoplurFPS/sprites"),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        let t = SKTexture(image: img); t.filteringMode = .nearest
        return t
    }

    private func loadAssetsAsync() {
        guard !assetsLoading else { return }
        assetsLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let assets = FPSAssets.loadAll { pct in
                DispatchQueue.main.async { self?.game.loadProgress = pct }
            }
            DispatchQueue.main.async {
                self?.game.setAssets(assets)
                #if DEBUG
                if ProcessInfo.processInfo.environment["FPS_AUTOPLAY"] == "1" {
                    self?.game.debugStartPlaying()
                }
                #endif
            }
        }
    }

    // MARK: Layout (per frame)

    private func layout() {
        let sw = size.width, sh = size.height
        portrait = sh > sw

        // Fullscreen gameplay in both orientations. Stretching the fixed 640x360
        // software framebuffer preserves every HUD/control edge on tall phones;
        // the old aspect-fit cabinet reduced portrait gameplay to a tiny window.
        cabinetNode.isHidden = true
        framebuffer.isHidden = false
        hideDrawnChrome()
        startBtnR = 0
        framebuffer.position = .zero
        framebuffer.size = CGSize(width: sw, height: sh)

        let controlScale = min(sw, sh)
        joyR = controlScale * 0.14
        joyC = CGPoint(x: sw * (portrait ? 0.18 : 0.13), y: sh * (portrait ? 0.13 : 0.20))
        fireR = controlScale * 0.12
        fireC = CGPoint(x: sw * (portrait ? 0.84 : 0.90), y: sh * (portrait ? 0.13 : 0.18))
        interactR = controlScale * 0.075
        interactC = CGPoint(x: sw * (portrait ? 0.67 : 0.76), y: sh * (portrait ? 0.11 : 0.14))

        positionButton(0, center: fireC, radius: fireR, color: UIColor(fpsHex: 0xff4db8), translucent: true)
        positionButton(1, center: interactC, radius: interactR, color: UIColor(fpsHex: 0x4488ff), translucent: true)

        let weaponR = controlScale * 0.052
        let weaponY = sh * (portrait ? 0.23 : 0.30)
        let weaponXs: [CGFloat] = portrait ? [0.64, 0.76, 0.88] : [0.70, 0.79, 0.88]
        weaponCR = weaponXs.enumerated().map { index, fraction in
            let center = CGPoint(x: sw * fraction, y: weaponY)
            positionWeaponButton(index + 2, center: center, radius: weaponR)
            return (center, weaponR)
        }
        styleJoystick(translucent: true)
    }

    /// Hides every piece of chrome the code used to draw itself.
    private func hideDrawnChrome() {
        marqueeBg.isHidden = true; marqueeLabel.isHidden = true; panelBg.isHidden = true
        for s in panelButtons { s.isHidden = true }
        for l in panelLabels { l.isHidden = true }
        if portrait {
            for b in buttons { b.isHidden = true }
            joyBase.isHidden = true; joyThumb.isHidden = true
        }
    }

    private func styleJoystick(translucent: Bool) {
        joyBase.path = CGPath(ellipseIn: CGRect(x: -joyR, y: -joyR, width: joyR * 2, height: joyR * 2), transform: nil)
        joyBase.position = joyC
        joyThumb.path = CGPath(ellipseIn: CGRect(x: -joyR * 0.5, y: -joyR * 0.5, width: joyR, height: joyR), transform: nil)
        if joyTouch == nil { joyThumb.position = joyC }

        joyBase.isHidden = false; joyThumb.isHidden = false
        if translucent {
            joyBase.fillColor = UIColor(white: 1, alpha: 0.12); joyBase.strokeColor = .clear
            joyThumb.fillColor = UIColor(red: 1, green: 0.3, blue: 0.72, alpha: 0.5); joyThumb.strokeColor = .clear
        } else {
            joyBase.fillColor = UIColor(fpsHex: 0x1a1a26); joyBase.strokeColor = .clear
            joyThumb.fillColor = UIColor(fpsHex: 0x40404f); joyThumb.strokeColor = .clear
        }
    }

    /// Portrait: place a real neon-panel sprite as button `i` (0=fire, 1=use, 2..4=weapons).
    private func positionPanelButton(_ i: Int, center: CGPoint, radius: CGFloat) {
        let s = panelButtons[i]
        let lbl = panelLabels[i]
        s.isHidden = false
        s.texture = (i == 0) ? texFire : (i == 1 ? texUse : texWeapon)
        // Panels are square; draw a touch larger than the touch radius so they read as buttons.
        let side = radius * 2.3
        s.size = CGSize(width: side, height: side)
        s.position = center
        s.color = .black
        if i >= 2 {
            lbl.isHidden = false
            lbl.text = "\(i - 1)"
            lbl.fontSize = radius * 0.85
            lbl.position = center
            let selected = game.player.weapon == (i - 2)
            s.colorBlendFactor = selected ? 0 : 0.45   // dim unselected weapons
            s.setScale(selected ? 1.08 : 1.0)
            lbl.fontColor = selected ? UIColor(fpsHex: 0xffd700) : .white
        } else {
            lbl.isHidden = true
            s.colorBlendFactor = 0
            s.setScale(1.0)
        }
    }

    private func positionButton(_ i: Int, center: CGPoint, radius: CGFloat, color: UIColor, translucent: Bool) {
        let b = buttons[i]
        b.isHidden = false
        b.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        b.position = center
        b.fillColor = translucent ? color.withAlphaComponent(0.38) : color
    }

    private func positionWeaponButton(_ i: Int, center: CGPoint, radius: CGFloat) {
        positionButton(i, center: center, radius: radius, color: btnColors[i], translucent: true)
        let label = panelLabels[i]
        label.isHidden = false
        label.text = "\(i - 1)"
        label.fontSize = radius * 0.9
        label.position = center
    }

    // MARK: Run loop

    override func update(_ currentTime: TimeInterval) {
        var dt = lastTime == 0 ? 0 : currentTime - lastTime
        lastTime = currentTime
        if dt > 0.05 { dt = 0.05 }

        let playing = game.state == .playing
        setChromeVisible(playing)
        layout()
        layoutPauseUI()

        var input = FPSInput()
        if playing {
            let dead = joyR * 0.28
            if joyVec.dy > dead { input.w = true }
            if joyVec.dy < -dead { input.s = true }
            if portrait {
                if joyVec.dx < -dead { input.left = true }
                if joyVec.dx > dead { input.right = true }
            } else {
                if joyVec.dx < -dead { input.a = true }
                if joyVec.dx > dead { input.d = true }
            }
            input.lookDX = lookDX
            input.fire = fireTouch != nil
            input.interact = interactPending
            switch weaponPending { case 1: input.weapon1 = true; case 2: input.weapon2 = true; case 3: input.weapon3 = true; default: break }
        } else {
            if tapPending { input.fire = true; input.interact = true }
        }
        lookDX = 0; interactPending = false; weaponPending = 0; tapPending = false

        game.update(dt, input)
        game.render(renderer)

        if let cg = renderer.snapshot() {
            let tex = SKTexture(cgImage: cg)
            tex.filteringMode = .nearest
            framebuffer.texture = tex
        }
    }

    // MARK: Touch input

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y; return (dx * dx + dy * dy).squareRoot()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // The pause menu swallows all input while it's up.
        if game.state == .paused {
            if let t = touches.first { handlePauseTap(t.location(in: self)) }
            return
        }
        if game.state == .playing, let t = touches.first {
            let p = t.location(in: self)
            // Pause pill (landscape) or the cabinet's painted START button (portrait).
            if pauseBtnFrame.contains(p) || (startBtnR > 0 && dist(p, startBtnC) <= startBtnR + 6) {
                releaseControlTouches()
                game.pauseGame()
                return
            }
        }

        for t in touches {
            let p = t.location(in: self)
            tapPending = true
            if dist(p, fireC) <= fireR + 6 { fireTouch = t; continue }
            if dist(p, interactC) <= interactR + 6 { interactPending = true; continue }
            if portrait {
                var hitWeapon = false
                for (i, weapon) in weaponCR.enumerated() {
                    if dist(p, weapon.0) <= weapon.1 + 6 { weaponPending = i + 1; hitWeapon = true; break }
                }
                if hitWeapon { continue }
            } else {
                var hitWeapon = false
                for (i, weapon) in weaponCR.enumerated() {
                    if dist(p, weapon.0) <= weapon.1 + 6 { weaponPending = i + 1; hitWeapon = true; break }
                }
                if hitWeapon { continue }
            }
            if dist(p, joyC) <= joyR + 20 && joyTouch == nil {
                joyTouch = t; joyCenter = joyC; joyVec = .zero; joyThumb.position = p
            } else if !portrait && lookTouch == nil {
                lookTouch = t; lookLastX = p.x
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            if t == joyTouch {
                var dx = p.x - joyCenter.x, dy = p.y - joyCenter.y
                let maxR = joyR
                let len = (dx * dx + dy * dy).squareRoot()
                if len > maxR { dx = dx / len * maxR; dy = dy / len * maxR }
                joyVec = CGVector(dx: dx, dy: dy)
                joyThumb.position = CGPoint(x: joyCenter.x + dx, y: joyCenter.y + dy)
            } else if t == lookTouch {
                lookDX += Double(p.x - lookLastX) * 12
                lookLastX = p.x
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if t == joyTouch { joyTouch = nil; joyVec = .zero; joyThumb.position = joyC }
            if t == lookTouch { lookTouch = nil }
            if t == fireTouch { fireTouch = nil }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}
