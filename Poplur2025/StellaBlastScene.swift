import SpriteKit
import UIKit

// MARK: - Stella's Blast (Vertical Arcade Shooter)

final class StellaBlastScene: SKScene, SKPhysicsContactDelegate {

    private let cfg: PoplurGameConfig
    private let catPlayer:  UInt32 = 0x01
    private let catBullet:  UInt32 = 0x02
    private let catEnemy:   UInt32 = 0x04
    private let catPowerUp: UInt32 = 0x08

    private var playerNode: SKNode!
    private var playerX: CGFloat = 0
    private var lives = 3
    private var score = 0
    private var wave = 1
    private var isGameOver = false
    private var shootClock: TimeInterval = 0
    private var waveSpawnDone = false
    private var enemiesRemaining = 0
    private var tripleShot = false
    private var shieldActive = false
    private var shieldNode: SKShapeNode?

    private var scoreLabel: SKLabelNode!
    private var waveLabel:  SKLabelNode!
    private var livesRow:   SKNode!
    private var starNodes:  [SKShapeNode] = []

    init(config: PoplurGameConfig, size: CGSize) {
        cfg = config; super.init(size: size); scaleMode = .resizeFill
    }
    required init?(coder aDecoder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        backgroundColor = cfg.skyUIColor
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        setupStars()
        setupPlayer()
        setupHUD()
        spawnWave()
    }

    // MARK: Stars
    private func setupStars() {
        for _ in 0..<60 {
            let s = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.8...2.5))
            s.fillColor = .white.withAlphaComponent(CGFloat.random(in: 0.3...0.9))
            s.strokeColor = .clear
            s.position = CGPoint(x: CGFloat.random(in: 0...size.width), y: CGFloat.random(in: 0...size.height))
            s.name = "star"
            addChild(s)
            starNodes.append(s)
        }
    }

    // MARK: Player
    private func setupPlayer() {
        playerX = size.width / 2
        playerNode = cfg.character.makeSpriteNode(scale: 0.85)
        playerNode.position = CGPoint(x: playerX, y: size.height * 0.12)
        playerNode.zPosition = 5

        let pb = SKPhysicsBody(circleOfRadius: 22)
        pb.isDynamic = false          // player is moved manually, not by physics
        pb.categoryBitMask    = catPlayer
        pb.contactTestBitMask = catEnemy | catPowerUp
        pb.collisionBitMask   = 0
        playerNode.physicsBody = pb

        addChild(playerNode)

        // Engine glow
        let glow = SKShapeNode(ellipseIn: CGRect(x: -16, y: -28, width: 32, height: 18))
        glow.fillColor = cfg.accentUIColor.withAlphaComponent(0.6); glow.strokeColor = .clear
        glow.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.2, duration: 0.3), SKAction.fadeAlpha(to: 0.7, duration: 0.3)
        ])))
        playerNode.addChild(glow)
    }

    // MARK: HUD
    private func setupHUD() {
        scoreLabel = hLabel("0", pos: CGPoint(x: 20, y: size.height - 50), align: .left, size: 22)
        waveLabel = hLabel("Wave \(wave)", pos: CGPoint(x: size.width/2, y: size.height - 50), align: .center, size: 18)
        livesRow = SKNode(); livesRow.position = CGPoint(x: size.width - 20, y: size.height - 48)
        livesRow.zPosition = 20; addChild(livesRow)
        refreshLives()
    }

    private func hLabel(_ text: String, pos: CGPoint, align: SKLabelHorizontalAlignmentMode, size: CGFloat) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        l.text = text; l.fontSize = size; l.fontColor = .white
        l.horizontalAlignmentMode = align; l.position = pos; l.zPosition = 20
        addChild(l); return l
    }

    private func refreshLives() {
        livesRow.removeAllChildren()
        for i in 0..<lives {
            let heart = SKLabelNode(text: "♥"); heart.fontSize = 18
            heart.fontColor = UIColor(red: 0.97, green: 0.26, blue: 0.43, alpha: 1)
            heart.position = CGPoint(x: -CGFloat(i) * 22, y: 0)
            livesRow.addChild(heart)
        }
    }

    // MARK: Wave
    private func spawnWave() {
        let cols = 5, rows = wave > 2 ? 2 : 1
        enemiesRemaining = cols * rows
        let startX = size.width * 0.15
        let colSpacing = size.width * 0.18
        for row in 0..<rows {
            for col in 0..<cols {
                let delay = Double(row * cols + col) * 0.18
                let tx = startX + CGFloat(col) * colSpacing
                let ty = size.height + 60 + CGFloat(row) * 70
                run(SKAction.wait(forDuration: delay)) { [weak self] in
                    self?.spawnEnemy(at: CGPoint(x: tx, y: ty), col: col, row: row)
                }
            }
        }
        waveSpawnDone = true
    }

    private func spawnEnemy(at pos: CGPoint, col: Int, row: Int) {
        let enemy = SKNode()
        // Body
        let body = SKShapeNode(rectOf: CGSize(width: 44, height: 34), cornerRadius: 6)
        body.fillColor = cfg.accentUIColor.blended(withFraction: 0.3 + CGFloat(row) * 0.1, of: UIColor.black)
        body.strokeColor = cfg.accentUIColor; body.lineWidth = 1.5
        // Eyes
        let e1 = SKShapeNode(circleOfRadius: 5); e1.fillColor = .white; e1.position = CGPoint(x: -10, y: 4)
        let e2 = SKShapeNode(circleOfRadius: 5); e2.fillColor = .white; e2.position = CGPoint(x: 10, y: 4)
        let p1 = SKShapeNode(circleOfRadius: 3); p1.fillColor = cfg.skyUIColor; p1.position = CGPoint(x: -10, y: 4)
        let p2 = SKShapeNode(circleOfRadius: 3); p2.fillColor = cfg.skyUIColor; p2.position = CGPoint(x: 10, y: 4)
        [body, e1, e2, p1, p2].forEach { enemy.addChild($0) }
        enemy.position = pos; enemy.zPosition = 4; enemy.name = "enemy"

        let speed = CGFloat(cfg.speed) * 0.5 + CGFloat(wave) * 20
        let moveDown = SKAction.moveBy(x: 0, y: -(pos.y - size.height * 0.5), duration: TimeInterval(pos.y / speed))
        let wobble = SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: CGFloat(col % 2 == 0 ? 20 : -20), y: 0, duration: 0.6),
            SKAction.moveBy(x: CGFloat(col % 2 == 0 ? -20 : 20), y: 0, duration: 0.6)
        ]))
        enemy.run(SKAction.group([moveDown, wobble]))

        let pb = SKPhysicsBody(rectangleOf: CGSize(width: 44, height: 34))
        pb.isDynamic = false; pb.categoryBitMask = catEnemy
        pb.contactTestBitMask = catBullet | catPlayer; pb.collisionBitMask = 0
        enemy.physicsBody = pb
        addChild(enemy)
    }

    // MARK: Loop
    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }
        let dt: TimeInterval = 1.0/60.0

        // Scroll stars
        for s in starNodes {
            s.position.y -= CGFloat(cfg.speed) * 0.08 * CGFloat(dt)
            if s.position.y < 0 { s.position.y = size.height }
        }

        // Auto-fire
        shootClock += dt
        let fireRate = tripleShot ? 0.22 : 0.38
        if shootClock >= fireRate { shootClock = 0; fireBullet() }

        // Move bullets
        for child in children where child.name == "bullet" {
            child.position.y += 700 * CGFloat(dt)
            if child.position.y > size.height + 20 { child.removeFromParent() }
        }

        // Check wave clear
        if enemiesRemaining <= 0 && waveSpawnDone {
            waveSpawnDone = false; wave += 1
            waveLabel.text = "Wave \(wave)"
            let wait = SKAction.wait(forDuration: 1.5)
            run(wait) { [weak self] in self?.spawnWave() }
        }

        // Enemies reaching bottom
        for child in children where child.name == "enemy" {
            if child.position.y < size.height * 0.08 {
                child.removeFromParent(); enemiesRemaining -= 1; loseLife()
            }
        }
    }

    private func fireBullet() {
        let offsets: [CGFloat] = tripleShot ? [-18, 0, 18] : [0]
        for dx in offsets {
            let b = SKShapeNode(rectOf: CGSize(width: 4, height: 16), cornerRadius: 2)
            b.fillColor = cfg.accentUIColor; b.strokeColor = .clear
            b.position = CGPoint(x: playerNode.position.x + dx, y: playerNode.position.y + 40)
            b.zPosition = 4; b.name = "bullet"
            let pb = SKPhysicsBody(rectangleOf: CGSize(width: 4, height: 16))
            pb.isDynamic = false; pb.categoryBitMask = catBullet
            pb.contactTestBitMask = catEnemy; pb.collisionBitMask = 0
            b.physicsBody = pb
            addChild(b)
        }
    }

    // MARK: Touch
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let dx = t.location(in: self).x - t.previousLocation(in: self).x
        playerX = (playerX + dx).clamped(to: 30...(size.width - 30))
        playerNode.position.x = playerX
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isGameOver, let _ = touches.first { restartGame() }
    }

    // MARK: Contacts
    func didBegin(_ contact: SKPhysicsContact) {
        let a = contact.bodyA, b = contact.bodyB
        if (a.categoryBitMask == catBullet && b.categoryBitMask == catEnemy) ||
           (a.categoryBitMask == catEnemy  && b.categoryBitMask == catBullet) {
            let enemy  = a.categoryBitMask == catEnemy  ? a.node : b.node
            let bullet = a.categoryBitMask == catBullet ? a.node : b.node
            explode(at: enemy?.position ?? .zero, color: cfg.accentUIColor)
            enemy?.removeFromParent(); bullet?.removeFromParent()
            enemiesRemaining -= 1
            score += 10 * wave; scoreLabel.text = "\(score)"
            if score % 500 == 0 { dropPowerUp() }
        }
        if (a.categoryBitMask == catPlayer && b.categoryBitMask == catEnemy) ||
           (a.categoryBitMask == catEnemy  && b.categoryBitMask == catPlayer) {
            if shieldActive { return }
            let enemy = a.categoryBitMask == catEnemy ? a.node : b.node
            enemy?.removeFromParent(); enemiesRemaining -= 1; loseLife()
        }
        if (a.categoryBitMask == catPlayer && b.categoryBitMask == catPowerUp) ||
           (a.categoryBitMask == catPowerUp && b.categoryBitMask == catPlayer) {
            let pu = a.categoryBitMask == catPowerUp ? a.node : b.node
            pu?.removeFromParent(); activatePowerUp()
        }
    }

    private func loseLife() {
        guard !isGameOver else { return }
        lives -= 1; refreshLives()
        let flash = SKAction.sequence([SKAction.fadeAlpha(to: 0.3, duration: 0.08), SKAction.fadeAlpha(to: 1, duration: 0.08)])
        playerNode.run(SKAction.repeat(flash, count: 3))
        if lives <= 0 { triggerGameOver() }
    }

    private func explode(at pos: CGPoint, color: UIColor) {
        for _ in 0..<8 {
            let p = SKShapeNode(circleOfRadius: CGFloat.random(in: 2...6))
            p.fillColor = color; p.strokeColor = .clear; p.position = pos; p.zPosition = 6
            addChild(p)
            let dx = CGFloat.random(in: -60...60), dy = CGFloat.random(in: -60...60)
            p.run(SKAction.sequence([
                SKAction.group([SKAction.moveBy(x: dx, y: dy, duration: 0.35), SKAction.fadeOut(withDuration: 0.35)]),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func dropPowerUp() {
        let pu = SKShapeNode(circleOfRadius: 14)
        pu.fillColor = UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1)
        pu.strokeColor = .white; pu.lineWidth = 2; pu.name = "powerup"
        let lbl = SKLabelNode(text: "★"); lbl.fontSize = 12; lbl.verticalAlignmentMode = .center
        pu.addChild(lbl)
        pu.position = CGPoint(x: CGFloat.random(in: 60...(size.width-60)), y: size.height + 20)
        pu.zPosition = 4
        let pb = SKPhysicsBody(circleOfRadius: 14); pb.isDynamic = false
        pb.categoryBitMask = catPowerUp; pb.contactTestBitMask = catPlayer; pb.collisionBitMask = 0
        pu.physicsBody = pb
        addChild(pu)
        pu.run(SKAction.sequence([SKAction.moveTo(y: -30, duration: 4), SKAction.removeFromParent()]))
    }

    private func activatePowerUp() {
        tripleShot = true
        run(SKAction.wait(forDuration: 6)) { [weak self] in self?.tripleShot = false }
    }

    private func triggerGameOver() {
        isGameOver = true
        showOverlay(title: "MISSION FAILED", sub: "Score: \(score)")
    }

    private func restartGame() {
        removeAllChildren(); removeAllActions()
        lives = 3; score = 0; wave = 1; isGameOver = false; tripleShot = false
        playerX = size.width / 2; enemiesRemaining = 0; waveSpawnDone = false
        setupStars(); setupPlayer(); setupHUD(); spawnWave()
    }

    private func showOverlay(title: String, sub: String) {
        let overlay = SKShapeNode(rectOf: size)
        overlay.fillColor = UIColor.black.withAlphaComponent(0.7); overlay.strokeColor = .clear
        overlay.position = CGPoint(x: size.width/2, y: size.height/2); overlay.zPosition = 30
        let t = SKLabelNode(fontNamed: "AvenirNext-Heavy"); t.text = title
        t.fontSize = 34; t.fontColor = .white; t.position = CGPoint(x: 0, y: 55)
        let s = SKLabelNode(fontNamed: "AvenirNext-Bold"); s.text = sub
        s.fontSize = 22; s.fontColor = cfg.accentUIColor; s.position = CGPoint(x: 0, y: 15)
        let h = SKLabelNode(fontNamed: "AvenirNext-Regular"); h.text = "Tap to continue"
        h.fontSize = 14; h.fontColor = .lightGray; h.position = CGPoint(x: 0, y: -22)
        h.run(SKAction.repeatForever(SKAction.sequence([SKAction.fadeAlpha(to: 0.3, duration: 0.7), SKAction.fadeAlpha(to: 1, duration: 0.7)])))
        [t, s, h].forEach { overlay.addChild($0) }
        addChild(overlay)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

extension UIColor {
    func blended(withFraction fraction: CGFloat, of other: UIColor) -> UIColor {
        let f = max(0, min(1, fraction))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
            return self
        }
        let r = r1 * (1 - f) + r2 * f
        let g = g1 * (1 - f) + g2 * f
        let b = b1 * (1 - f) + b2 * f
        let a = a1 * (1 - f) + a2 * f
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}
