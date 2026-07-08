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
    private var buttons: [SKShapeNode] = []   // [0]=fire [1]=interact [2..4]=weapons

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

        setChromeVisible(false)
        loadAssetsAsync()
    }

    private func setChromeVisible(_ v: Bool) {
        let a: CGFloat = v ? 1 : 0
        marqueeBg.alpha = a; marqueeLabel.alpha = a; panelBg.alpha = a
        joyBase.alpha = a; joyThumb.alpha = a
        for b in buttons { b.alpha = a }
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
        let playing = game.state == .playing || game.state == .paused ||
                      game.state == .dead || game.state == .win
        let scale = min(sw / 640, sh / 360)
        let bw = 640 * scale, bh = 360 * scale
        let bx = (sw - bw) / 2
        let marqueeH = sh * 0.10
        // y-up: portrait gameplay puts the band near the top.
        let by = (portrait && playing) ? (sh - marqueeH - bh) : (sh - bh) / 2

        framebuffer.position = CGPoint(x: bx, y: by)
        framebuffer.size = CGSize(width: bw, height: bh)

        if portrait && playing {
            // Marquee above band
            marqueeBg.path = CGPath(rect: CGRect(x: 0, y: sh - marqueeH, width: sw, height: marqueeH), transform: nil)
            marqueeLabel.position = CGPoint(x: sw / 2, y: sh - marqueeH / 2)
            marqueeLabel.fontSize = marqueeH * 0.42
            marqueeBg.isHidden = false; marqueeLabel.isHidden = false
            // Control panel below band
            let panelTop = by                    // band bottom
            panelBg.path = CGPath(rect: CGRect(x: 0, y: 0, width: sw, height: panelTop), transform: nil)
            panelBg.isHidden = false
            let cy = panelTop / 2
            joyR = min(panelTop * 0.34, sw * 0.13)
            joyC = CGPoint(x: sw * 0.20, y: cy)
            let btnR = joyR * 0.55
            let bx0 = sw * 0.44
            let gap = (sw * 0.90 - bx0) / 4
            weaponCR = []
            for i in 0..<5 {
                let c = CGPoint(x: bx0 + CGFloat(i) * gap, y: cy)
                positionButton(i, center: c, radius: btnR, color: btnColors[i], translucent: false)
                weaponCR.append((c, btnR))
            }
            fireC = weaponCR[0].0; fireR = btnR
            interactC = weaponCR[1].0; interactR = btnR
            styleJoystick(translucent: false)
        } else {
            marqueeBg.isHidden = true; marqueeLabel.isHidden = true; panelBg.isHidden = true
            // Translucent floating controls
            joyR = sh * 0.14
            joyC = CGPoint(x: sw * 0.13, y: sh * 0.20)
            fireR = sh * 0.12; fireC = CGPoint(x: sw * 0.90, y: sh * 0.18)
            interactR = sh * 0.075; interactC = CGPoint(x: sw * 0.76, y: sh * 0.14)
            positionButton(0, center: fireC, radius: fireR, color: UIColor(fpsHex: 0xff4db8), translucent: true)
            positionButton(1, center: interactC, radius: interactR, color: UIColor(fpsHex: 0x4488ff), translucent: true)
            for i in 2..<5 { buttons[i].isHidden = true }
            weaponCR = []
            styleJoystick(translucent: true)
        }
    }

    private func styleJoystick(translucent: Bool) {
        joyBase.path = CGPath(ellipseIn: CGRect(x: -joyR, y: -joyR, width: joyR * 2, height: joyR * 2), transform: nil)
        joyBase.position = joyC
        joyThumb.path = CGPath(ellipseIn: CGRect(x: -joyR * 0.5, y: -joyR * 0.5, width: joyR, height: joyR), transform: nil)
        if joyTouch == nil { joyThumb.position = joyC }
        if translucent {
            joyBase.fillColor = UIColor(white: 1, alpha: 0.12); joyBase.strokeColor = .clear
            joyThumb.fillColor = UIColor(red: 1, green: 0.3, blue: 0.72, alpha: 0.5); joyThumb.strokeColor = .clear
        } else {
            joyBase.fillColor = UIColor(fpsHex: 0x1a1a26); joyBase.strokeColor = .clear
            joyThumb.fillColor = UIColor(fpsHex: 0x40404f); joyThumb.strokeColor = .clear
        }
    }

    private func positionButton(_ i: Int, center: CGPoint, radius: CGFloat, color: UIColor, translucent: Bool) {
        let b = buttons[i]
        b.isHidden = false
        b.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        b.position = center
        b.fillColor = translucent ? color.withAlphaComponent(0.38) : color
    }

    // MARK: Run loop

    override func update(_ currentTime: TimeInterval) {
        var dt = lastTime == 0 ? 0 : currentTime - lastTime
        lastTime = currentTime
        if dt > 0.05 { dt = 0.05 }

        let playing = game.state == .playing
        setChromeVisible(playing)
        layout()

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
        for t in touches {
            let p = t.location(in: self)
            tapPending = true
            if dist(p, fireC) <= fireR + 6 { fireTouch = t; continue }
            if dist(p, interactC) <= interactR + 6 { interactPending = true; continue }
            if portrait {
                var hitWeapon = false
                for i in 2..<weaponCR.count {
                    if dist(p, weaponCR[i].0) <= weaponCR[i].1 + 6 { weaponPending = i - 1; hitWeapon = true; break }
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
