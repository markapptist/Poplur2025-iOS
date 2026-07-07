import SpriteKit
import UIKit

// MARK: - PoplurFPS SpriteKit scene
//
// SpriteKit hosts a single full-scene SKSpriteNode whose texture is refreshed
// each frame from the software raycaster (FPSRenderer). SpriteKit provides the
// run loop (update:) and touch input; all pixels come from the renderer.

final class FPSGameScene: SKScene {
    private let game = FPSGame()
    private let renderer = FPSRenderer()
    private var framebuffer: SKSpriteNode!

    private var lastTime: TimeInterval = 0
    private var assetsLoading = false

    // Touch control state
    private var joyTouch: UITouch?
    private var joyOrigin = CGPoint.zero
    private var joyVec = CGVector.zero
    private var lookTouch: UITouch?
    private var lookLastX: CGFloat = 0
    private var lookDX: Double = 0
    private var fireTouch: UITouch?
    private var interactPending = false
    private var tapPending = false

    // Control node frames (scene coords, anchor bottom-left)
    private var fireRect = CGRect.zero
    private var interactRect = CGRect.zero
    private var joyBase: SKShapeNode!
    private var joyThumb: SKShapeNode!
    private var fireBtn: SKShapeNode!
    private var interactBtn: SKShapeNode!

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0, y: 0)
        backgroundColor = .black
        scaleMode = .aspectFit

        framebuffer = SKSpriteNode(color: .black, size: size)
        framebuffer.anchorPoint = CGPoint(x: 0, y: 0)
        framebuffer.position = .zero
        framebuffer.zPosition = 0
        addChild(framebuffer)

        setupControls()
        loadAssetsAsync()
    }

    private func setupControls() {
        let W = size.width

        // Virtual joystick (bottom-left)
        let jr: CGFloat = 46
        let jc = CGPoint(x: 70, y: 66)
        joyBase = SKShapeNode(circleOfRadius: jr)
        joyBase.position = jc
        joyBase.fillColor = UIColor(red: 0.91, green: 0.12, blue: 0.55, alpha: 0.18)
        joyBase.strokeColor = UIColor(red: 0.91, green: 0.12, blue: 0.55, alpha: 0.5)
        joyBase.lineWidth = 2
        joyBase.zPosition = 10
        addChild(joyBase)
        joyThumb = SKShapeNode(circleOfRadius: 20)
        joyThumb.position = jc
        joyThumb.fillColor = UIColor(red: 0.91, green: 0.12, blue: 0.55, alpha: 0.6)
        joyThumb.strokeColor = UIColor(red: 1, green: 0.3, blue: 0.72, alpha: 1)
        joyThumb.lineWidth = 2
        joyThumb.zPosition = 11
        addChild(joyThumb)

        // Fire button (bottom-right)
        let fr: CGFloat = 34
        let fc = CGPoint(x: W - 56, y: 56)
        fireBtn = SKShapeNode(circleOfRadius: fr)
        fireBtn.position = fc
        fireBtn.fillColor = UIColor(red: 0.78, green: 0, blue: 0.39, alpha: 0.6)
        fireBtn.strokeColor = UIColor(fpsHex: 0xffd700)
        fireBtn.lineWidth = 3
        fireBtn.zPosition = 10
        addChild(fireBtn)
        fireRect = CGRect(x: fc.x - fr - 8, y: fc.y - fr - 8, width: (fr + 8) * 2, height: (fr + 8) * 2)

        // Interact button (above fire)
        let ir: CGFloat = 26
        let ic = CGPoint(x: W - 120, y: 60)
        interactBtn = SKShapeNode(circleOfRadius: ir)
        interactBtn.position = ic
        interactBtn.fillColor = UIColor(red: 0.2, green: 0, blue: 0.78, alpha: 0.6)
        interactBtn.strokeColor = UIColor(fpsHex: 0xaa88ff)
        interactBtn.lineWidth = 3
        interactBtn.zPosition = 10
        addChild(interactBtn)
        interactRect = CGRect(x: ic.x - ir - 8, y: ic.y - ir - 8, width: (ir + 8) * 2, height: (ir + 8) * 2)

        setControlsVisible(false)
    }

    private func setControlsVisible(_ visible: Bool) {
        let a: CGFloat = visible ? 1 : 0
        joyBase.alpha = a; joyThumb.alpha = a; fireBtn.alpha = a; interactBtn.alpha = a
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

    // MARK: Run loop

    override func update(_ currentTime: TimeInterval) {
        var dt = lastTime == 0 ? 0 : currentTime - lastTime
        lastTime = currentTime
        if dt > 0.05 { dt = 0.05 }

        setControlsVisible(game.state == .playing)

        var input = FPSInput()
        if game.state == .playing {
            // Joystick → movement
            let dead: CGFloat = 10
            if joyVec.dx < -dead { input.a = true }
            if joyVec.dx > dead { input.d = true }
            if joyVec.dy > dead { input.w = true }
            if joyVec.dy < -dead { input.s = true }
            input.lookDX = lookDX
            input.fire = fireTouch != nil
            input.interact = interactPending
        } else {
            // Menu / dead / win / paused: a tap acts as fire + interact
            if tapPending { input.fire = true; input.interact = true }
        }
        lookDX = 0
        interactPending = false
        tapPending = false

        game.update(dt, input)
        game.render(renderer)

        if let cg = renderer.snapshot() {
            let tex = SKTexture(cgImage: cg)
            tex.filteringMode = .nearest
            framebuffer.texture = tex
        }
    }

    // MARK: Touch input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            tapPending = true
            if fireRect.contains(p) { fireTouch = t; continue }
            if interactRect.contains(p) { interactPending = true; continue }
            if p.x < size.width * 0.42 && joyTouch == nil {
                joyTouch = t; joyOrigin = p; joyVec = .zero
                joyThumb.position = p; joyBase.position = p
            } else if lookTouch == nil {
                lookTouch = t; lookLastX = p.x
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            if t == joyTouch {
                var dx = p.x - joyOrigin.x, dy = p.y - joyOrigin.y
                let maxR: CGFloat = 40
                let len = (dx * dx + dy * dy).squareRoot()
                if len > maxR { dx = dx / len * maxR; dy = dy / len * maxR }
                joyVec = CGVector(dx: dx, dy: dy)
                joyThumb.position = CGPoint(x: joyOrigin.x + dx, y: joyOrigin.y + dy)
            } else if t == lookTouch {
                lookDX += Double(p.x - lookLastX) * 12   // touch drag → look sensitivity
                lookLastX = p.x
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if t == joyTouch { joyTouch = nil; joyVec = .zero; joyThumb.position = joyBase.position }
            if t == lookTouch { lookTouch = nil }
            if t == fireTouch { fireTouch = nil }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}
