import SpriteKit
import UIKit

// MARK: - Zyla's Quest (Top-Down Action / Adventure)

final class ZylaQuestScene: SKScene, SKPhysicsContactDelegate {

    private let cfg: PoplurGameConfig
    private let catPlayer:  UInt32 = 0x01
    private let catEnemy:   UInt32 = 0x02
    private let catWall:    UInt32 = 0x04
    private let catItem:    UInt32 = 0x08
    private let catSword:   UInt32 = 0x10

    // State
    private var score = 0
    private var health = 5
    private var maxHealth = 5
    private var isGameOver = false
    private var swordCooldown: TimeInterval = 0
    private var spawnClock: TimeInterval = 0
    private var spawnInterval: TimeInterval = 2.2
    private var wave = 1
    private var killCount = 0
    private var killsPerWave = 6
    private var iFrames: TimeInterval = 0

    // Player movement (virtual joystick state)
    private var moveVector: CGVector = .zero
    private var touchStart: CGPoint?
    private var joystickBase: SKShapeNode?
    private var joystickKnob: SKShapeNode?
    private var joystickTouch: UITouch?
    private var actionTouch: UITouch?

    // Nodes
    private var playerNode: SKNode!
    private var scoreLabel: SKLabelNode!
    private var waveLabel: SKLabelNode!
    private var healthRow: SKNode!
    private var roomNodes: [SKShapeNode] = []

    init(config: PoplurGameConfig, size: CGSize) {
        cfg = config; super.init(size: size); scaleMode = .resizeFill
    }
    required init?(coder aDecoder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        backgroundColor = cfg.skyUIColor
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        buildRoom()
        setupPlayer()
        setupHUD()
        setupJoystick()
        spawnEnemies(count: killsPerWave)
    }

    // MARK: Room

    private func buildRoom() {
        let wallThick: CGFloat = 24
        let inset: CGFloat = 28
        let wallColor = cfg.groundUIColor
        let floorColor = cfg.groundUIColor.zq_blended(withFraction: 0.3, of: .black)

        // Floor
        let floor = SKShapeNode(rectOf: CGSize(width: size.width - inset*2, height: size.height - inset*2 - 80),
                                cornerRadius: 8)
        floor.fillColor = floorColor; floor.strokeColor = .clear
        floor.position = CGPoint(x: size.width/2, y: size.height/2 - 20)
        floor.zPosition = -1; addChild(floor)

        // Floor tiles
        let tileSize: CGFloat = 60
        let startX = inset + tileSize/2
        let startY: CGFloat = 60 + tileSize/2
        var tx = startX
        while tx < size.width - inset {
            var ty = startY
            while ty < size.height - inset {
                let tile = SKShapeNode(rectOf: CGSize(width: tileSize - 2, height: tileSize - 2), cornerRadius: 3)
                tile.fillColor = floorColor.zq_blended(withFraction: CGFloat.random(in: 0...0.1), of: .white)
                tile.strokeColor = cfg.groundUIColor.withAlphaComponent(0.4); tile.lineWidth = 1
                tile.position = CGPoint(x: tx, y: ty); tile.zPosition = -1; addChild(tile)
                ty += tileSize
            }
            tx += tileSize
        }

        // Walls
        let walls: [(CGRect)] = [
            CGRect(x: 0, y: size.height - inset - wallThick, width: size.width, height: wallThick + inset), // top
            CGRect(x: 0, y: 40, width: size.width, height: wallThick + inset - 40),                         // bottom
            CGRect(x: 0, y: 40, width: wallThick + inset, height: size.height - 40),                        // left
            CGRect(x: size.width - wallThick - inset, y: 40, width: wallThick + inset, height: size.height - 40) // right
        ]
        for rect in walls {
            let w = SKShapeNode(rect: rect, cornerRadius: 0)
            w.fillColor = wallColor; w.strokeColor = cfg.accentUIColor.withAlphaComponent(0.4); w.lineWidth = 1.5
            w.zPosition = 2
            let pb = SKPhysicsBody(edgeLoopFrom: rect)
            pb.categoryBitMask = catWall; pb.collisionBitMask = catPlayer | catEnemy; pb.contactTestBitMask = 0
            w.physicsBody = pb
            addChild(w); roomNodes.append(w)
        }

        // Some crates/pillars for cover
        for _ in 0..<4 {
            let px = CGFloat.random(in: 120...(size.width - 120))
            let py = CGFloat.random(in: 120...(size.height - 160))
            let crate = SKShapeNode(rectOf: CGSize(width: 38, height: 38), cornerRadius: 4)
            crate.fillColor = cfg.groundUIColor.zq_blended(withFraction: 0.15, of: .black)
            crate.strokeColor = cfg.accentUIColor.withAlphaComponent(0.5); crate.lineWidth = 1.5
            crate.position = CGPoint(x: px, y: py); crate.zPosition = 3
            let pb = SKPhysicsBody(rectangleOf: CGSize(width: 38, height: 38))
            pb.isDynamic = false; pb.categoryBitMask = catWall
            pb.collisionBitMask = catPlayer | catEnemy; pb.contactTestBitMask = 0
            crate.physicsBody = pb
            addChild(crate)
        }
    }

    // MARK: Player

    private func setupPlayer() {
        playerNode = cfg.character.makeSpriteNode(scale: 0.9)
        playerNode.position = CGPoint(x: size.width/2, y: size.height/2)
        playerNode.zPosition = 5
        let pb = SKPhysicsBody(circleOfRadius: 18)
        pb.categoryBitMask = catPlayer
        pb.contactTestBitMask = catEnemy | catItem
        pb.collisionBitMask = catWall | catEnemy
        pb.linearDamping = 8; pb.angularDamping = 1; pb.allowsRotation = false
        playerNode.physicsBody = pb
        addChild(playerNode)
    }

    // MARK: HUD

    private func setupHUD() {
        scoreLabel = hudLabel("0", pos: CGPoint(x: 20, y: size.height - 50), align: .left, size: 22)
        waveLabel = hudLabel("Wave \(wave)", pos: CGPoint(x: size.width/2, y: size.height - 50), align: .center, size: 18)
        healthRow = SKNode(); healthRow.position = CGPoint(x: size.width - 20, y: size.height - 48)
        healthRow.zPosition = 20; addChild(healthRow)
        refreshHealth()
    }

    @discardableResult
    private func hudLabel(_ text: String, pos: CGPoint, align: SKLabelHorizontalAlignmentMode, size: CGFloat) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        l.text = text; l.fontSize = size; l.fontColor = .white
        l.horizontalAlignmentMode = align; l.position = pos; l.zPosition = 20
        addChild(l); return l
    }

    private func refreshHealth() {
        healthRow.removeAllChildren()
        for i in 0..<maxHealth {
            let heart = SKLabelNode(text: i < health ? "♥" : "♡")
            heart.fontSize = 16
            heart.fontColor = i < health ? UIColor(red: 0.97, green: 0.26, blue: 0.43, alpha: 1) : .gray
            heart.position = CGPoint(x: -CGFloat(i) * 20, y: 0)
            healthRow.addChild(heart)
        }
    }

    // MARK: Joystick

    private func setupJoystick() {
        let r: CGFloat = 52
        let base = SKShapeNode(circleOfRadius: r)
        base.fillColor = UIColor.white.withAlphaComponent(0.08)
        base.strokeColor = UIColor.white.withAlphaComponent(0.22); base.lineWidth = 1.5
        base.position = CGPoint(x: 80, y: 90); base.zPosition = 50; base.name = "jBase"
        addChild(base); joystickBase = base

        let knob = SKShapeNode(circleOfRadius: 26)
        knob.fillColor = cfg.accentUIColor.withAlphaComponent(0.55)
        knob.strokeColor = cfg.accentUIColor; knob.lineWidth = 1.5
        knob.position = CGPoint(x: 80, y: 90); knob.zPosition = 51; knob.name = "jKnob"
        addChild(knob); joystickKnob = knob
    }

    // MARK: Enemies

    private func spawnEnemies(count: Int) {
        for i in 0..<count {
            let delay = Double(i) * 0.35
            run(SKAction.wait(forDuration: delay)) { [weak self] in
                self?.spawnOneEnemy()
            }
        }
    }

    private func spawnOneEnemy() {
        guard !isGameOver else { return }
        // Spawn at room edge, away from player
        let margin: CGFloat = 60
        var pos: CGPoint
        repeat {
            let edge = Int.random(in: 0..<4)
            switch edge {
            case 0: pos = CGPoint(x: CGFloat.random(in: margin...(size.width - margin)), y: size.height - 80)
            case 1: pos = CGPoint(x: CGFloat.random(in: margin...(size.width - margin)), y: 80)
            case 2: pos = CGPoint(x: margin, y: CGFloat.random(in: 80...(size.height - 80)))
            default: pos = CGPoint(x: size.width - margin, y: CGFloat.random(in: 80...(size.height - 80)))
            }
        } while hypot(pos.x - playerNode.position.x, pos.y - playerNode.position.y) < 150

        let enemy = makeEnemyNode()
        enemy.position = pos
        addChild(enemy)

        // Chase player
        chasePlayer(enemy: enemy)
    }

    private func makeEnemyNode() -> SKNode {
        let e = SKNode(); e.name = "enemy"; e.zPosition = 4
        let waveScale = min(1.0 + CGFloat(wave - 1) * 0.08, 1.35)
        let body = SKShapeNode(rectOf: CGSize(width: 40 * waveScale, height: 40 * waveScale), cornerRadius: 5)
        body.fillColor = cfg.accentUIColor.zq_blended(withFraction: 0.2 + CGFloat.random(in: 0...0.15), of: .black)
        body.strokeColor = cfg.accentUIColor; body.lineWidth = 1.5
        // Eyes
        let ex = SKShapeNode(circleOfRadius: 5); ex.fillColor = .white; ex.position = CGPoint(x: -8, y: 5)
        let ey = SKShapeNode(circleOfRadius: 5); ey.fillColor = .white; ey.position = CGPoint(x: 8, y: 5)
        [body, ex, ey].forEach { e.addChild($0) }
        let pb = SKPhysicsBody(circleOfRadius: 18 * waveScale)
        pb.categoryBitMask = catEnemy
        pb.contactTestBitMask = catPlayer | catSword
        pb.collisionBitMask = catWall | catEnemy
        pb.linearDamping = 2; pb.allowsRotation = false
        e.physicsBody = pb
        return e
    }

    private func chasePlayer(enemy: SKNode) {
        guard !isGameOver else { return }
        let baseSpeed: CGFloat = 55 + CGFloat(wave) * 8
        let speed = min(baseSpeed, 130)
        let dx = playerNode.position.x - enemy.position.x
        let dy = playerNode.position.y - enemy.position.y
        let dist = max(hypot(dx, dy), 1)
        let nx = dx / dist; let ny = dy / dist
        enemy.physicsBody?.velocity = CGVector(dx: nx * speed, dy: ny * speed)

        let rechase = SKAction.sequence([
            SKAction.wait(forDuration: 0.6),
            SKAction.run { [weak self, weak enemy] in
                guard let self, let enemy, enemy.parent != nil else { return }
                self.chasePlayer(enemy: enemy)
            }
        ])
        enemy.run(rechase, withKey: "chase")
    }

    // MARK: Sword attack

    private func attack() {
        guard swordCooldown <= 0, !isGameOver else { return }
        swordCooldown = 0.55

        let slash = SKShapeNode(ellipseIn: CGRect(x: -28, y: -14, width: 56, height: 28))
        slash.fillColor = cfg.accentUIColor.withAlphaComponent(0.6)
        slash.strokeColor = cfg.accentUIColor; slash.lineWidth = 1.5
        slash.position = playerNode.position
        slash.zPosition = 6; slash.name = "sword"
        let bodyPath = CGMutablePath()
        let bodySteps = 12
        for index in 0..<bodySteps {
            let angle = (CGFloat(index) / CGFloat(bodySteps)) * .pi * 2
            let point = CGPoint(x: cos(angle) * 28, y: sin(angle) * 14)
            index == 0 ? bodyPath.move(to: point) : bodyPath.addLine(to: point)
        }
        bodyPath.closeSubpath()
        let pb = SKPhysicsBody(polygonFrom: bodyPath)
        pb.isDynamic = false; pb.categoryBitMask = catSword
        pb.contactTestBitMask = catEnemy; pb.collisionBitMask = 0
        slash.physicsBody = pb
        addChild(slash)

        let seq = SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.4, duration: 0.15),
                SKAction.fadeAlpha(to: 0, duration: 0.15)
            ]),
            SKAction.removeFromParent()
        ])
        slash.run(seq)

        // Drop item sometimes
        if Int.random(in: 0..<5) == 0 { spawnItem(at: playerNode.position) }
    }

    // MARK: Items (health potions)

    private func spawnItem(at pos: CGPoint) {
        let item = SKShapeNode(circleOfRadius: 10)
        item.fillColor = UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1)
        item.strokeColor = .white; item.lineWidth = 1.5
        item.position = pos; item.zPosition = 3; item.name = "item"
        let label = SKLabelNode(text: "+")
        label.fontSize = 14; label.fontColor = .white
        label.verticalAlignmentMode = .center; label.horizontalAlignmentMode = .center
        item.addChild(label)
        let pb = SKPhysicsBody(circleOfRadius: 10)
        pb.isDynamic = false; pb.categoryBitMask = catItem
        pb.contactTestBitMask = catPlayer; pb.collisionBitMask = 0
        item.physicsBody = pb
        addChild(item)
        item.run(SKAction.sequence([SKAction.wait(forDuration: 6), SKAction.fadeOut(withDuration: 0.5), SKAction.removeFromParent()]))
    }

    // MARK: Game Loop

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }
        let dt: TimeInterval = 1.0/60.0

        // Cool down timers
        if swordCooldown > 0 { swordCooldown -= dt }
        if iFrames > 0 { iFrames -= dt }

        // Move player
        let speed: CGFloat = 170
        if moveVector != .zero {
            let len = hypot(moveVector.dx, moveVector.dy)
            let nx = moveVector.dx / len * speed
            let ny = moveVector.dy / len * speed
            playerNode.physicsBody?.velocity = CGVector(dx: nx, dy: ny)
        } else {
            let v = playerNode.physicsBody?.velocity ?? .zero
            playerNode.physicsBody?.velocity = CGVector(dx: v.dx * 0.75, dy: v.dy * 0.75)
        }

        // Score tick
        score += 1
        if score % 60 == 0 { scoreLabel.text = "\(score / 60)" }

        // Wave check
        if killCount >= killsPerWave {
            killCount = 0; wave += 1; killsPerWave = min(killsPerWave + 2, 18)
            waveLabel.text = "Wave \(wave)"
            children.filter { $0.name == "enemy" }.forEach { $0.removeFromParent() }
            run(SKAction.wait(forDuration: 1.2)) { [weak self] in
                guard let self else { return }
                self.spawnEnemies(count: self.killsPerWave)
            }
        }
    }

    // MARK: Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let a = contact.bodyA, b = contact.bodyB

        if (a.categoryBitMask == catSword && b.categoryBitMask == catEnemy) ||
           (a.categoryBitMask == catEnemy && b.categoryBitMask == catSword) {
            let enemy = a.categoryBitMask == catEnemy ? a.node : b.node
            killEnemy(enemy)
        }

        if (a.categoryBitMask == catPlayer && b.categoryBitMask == catEnemy) ||
           (a.categoryBitMask == catEnemy && b.categoryBitMask == catPlayer) {
            if iFrames <= 0 { takeDamage() }
        }

        if (a.categoryBitMask == catPlayer && b.categoryBitMask == catItem) ||
           (a.categoryBitMask == catItem && b.categoryBitMask == catPlayer) {
            let item = a.categoryBitMask == catItem ? a.node : b.node
            item?.removeFromParent()
            health = min(maxHealth, health + 1); refreshHealth()
        }
    }

    private func killEnemy(_ node: SKNode?) {
        guard let node, node.parent != nil else { return }
        explode(at: node.position, color: cfg.accentUIColor)
        node.removeFromParent()
        killCount += 1
        score += 50
        scoreLabel.text = "\(score / 60)"
    }

    private func takeDamage() {
        guard !isGameOver else { return }
        iFrames = 1.2
        health -= 1; refreshHealth()
        // Flash player
        let flash = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.25, duration: 0.08),
            SKAction.fadeAlpha(to: 1.0, duration: 0.08)
        ])
        playerNode.run(SKAction.repeat(flash, count: 5))
        if health <= 0 { gameOver() }
    }

    private func explode(at pos: CGPoint, color: UIColor) {
        for _ in 0..<8 {
            let p = SKShapeNode(circleOfRadius: CGFloat.random(in: 3...7))
            p.fillColor = color.withAlphaComponent(0.9); p.strokeColor = .clear
            p.position = pos; p.zPosition = 10; addChild(p)
            let dx = CGFloat.random(in: -80...80)
            let dy = CGFloat.random(in: -80...80)
            p.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: dx, y: dy, duration: 0.35),
                    SKAction.fadeOut(withDuration: 0.35),
                    SKAction.scale(to: 0.1, duration: 0.35)
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func gameOver() {
        isGameOver = true
        playerNode.physicsBody?.velocity = .zero

        let overlay = SKShapeNode(rectOf: size)
        overlay.fillColor = UIColor.black.withAlphaComponent(0.65)
        overlay.strokeColor = .clear; overlay.position = CGPoint(x: size.width/2, y: size.height/2)
        overlay.zPosition = 100; addChild(overlay)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "GAME OVER"; title.fontSize = 40; title.fontColor = cfg.accentUIColor
        title.position = CGPoint(x: 0, y: 40); overlay.addChild(title)

        let sub = SKLabelNode(fontNamed: "AvenirNext-Bold")
        sub.text = "Score: \(score / 60) | Wave \(wave)"; sub.fontSize = 20; sub.fontColor = .white
        sub.position = CGPoint(x: 0, y: -10); overlay.addChild(sub)

        let tap = SKLabelNode(fontNamed: "AvenirNext-Medium")
        tap.text = "Tap to play again"; tap.fontSize = 16; tap.fontColor = UIColor.white.withAlphaComponent(0.65)
        tap.position = CGPoint(x: 0, y: -55)
        tap.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.6), SKAction.fadeAlpha(to: 1.0, duration: 0.6)
        ])))
        overlay.addChild(tap)
    }

    // MARK: Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pos = touch.location(in: self)
            if pos.x < size.width * 0.45 && joystickTouch == nil {
                joystickTouch = touch
                joystickBase?.position = pos
                joystickKnob?.position = pos
            } else if actionTouch == nil {
                actionTouch = touch
                if isGameOver {
                    restart()
                } else {
                    attack()
                }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard touch == joystickTouch, let base = joystickBase, let knob = joystickKnob else { continue }
            let pos = touch.location(in: self)
            let dx = pos.x - base.position.x
            let dy = pos.y - base.position.y
            let dist = hypot(dx, dy)
            let maxR: CGFloat = 50
            let clampedDist = min(dist, maxR)
            let angle = atan2(dy, dx)
            knob.position = CGPoint(
                x: base.position.x + cos(angle) * clampedDist,
                y: base.position.y + sin(angle) * clampedDist
            )
            moveVector = dist > 8 ? CGVector(dx: dx, dy: dy) : .zero
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch == joystickTouch {
                joystickTouch = nil; moveVector = .zero
                joystickKnob?.position = joystickBase?.position ?? joystickKnob?.position ?? .zero
            }
            if touch == actionTouch { actionTouch = nil }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private func restart() {
        let fresh = ZylaQuestScene(config: cfg, size: size)
        view?.presentScene(fresh, transition: SKTransition.fade(withDuration: 0.4))
    }
}

// MARK: - UIColor helpers (ZylaQuest-local)

private extension UIColor {
    func zq_blended(withFraction f: CGFloat, of other: UIColor) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1*(1-f)+r2*f, green: g1*(1-f)+g2*f, blue: b1*(1-f)+b2*f, alpha: a1*(1-f)+a2*f)
    }
}
