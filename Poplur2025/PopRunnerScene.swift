import SpriteKit
import UIKit

// MARK: - Pop Runner (Side Scroller)

@MainActor
final class PopRunnerScene: SKScene, SKPhysicsContactDelegate {

    // MARK: Config
    private let cfg: PoplurGameConfig

    // MARK: Physics bits
    private let catPlayer:     UInt32 = 0x01
    private let catGround:     UInt32 = 0x02
    private let catObstacle:   UInt32 = 0x04
    private let catCoin:       UInt32 = 0x08

    // MARK: State
    private var score = 0
    private var jumpCount = 0
    private var isGameOver = false
    private var gameSpeed: CGFloat
    private var spawnClock: TimeInterval = 0
    private var spawnInterval: TimeInterval = 2.0
    private var scoreClock: TimeInterval = 0
    private var bgOffset: [CGFloat] = [0, 0, 0]

    // MARK: Nodes
    private var playerNode: SKNode!
    private var playerBody: SKPhysicsBody!
    private var groundNodes: [SKSpriteNode] = []
    private var scoreLabel: SKLabelNode!
    private var comboLabel: SKLabelNode!
    private var bgLayers: [SKNode] = []

    // MARK: Init
    init(config: PoplurGameConfig, size: CGSize) {
        self.cfg = config
        self.gameSpeed = CGFloat(config.speed)
        super.init(size: size)
        scaleMode = .resizeFill
    }
    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: Setup
    override func didMove(to view: SKView) {
        backgroundColor = cfg.skyUIColor
        physicsWorld.gravity = CGVector(dx: 0, dy: -16)
        physicsWorld.contactDelegate = self

        setupBackground()
        setupGround()
        setupPlayer()
        setupHUD()
        startGameMusic()
    }

    // MARK: Background (3 parallax layers)
    private func setupBackground() {
        let colors: [UIColor] = [
            cfg.skyUIColor.pr_blended(withFraction: 0.0, of: UIColor.black),
            cfg.skyUIColor.pr_blended(withFraction: 0.25, of: UIColor.black),
            cfg.skyUIColor.pr_blended(withFraction: 0.45, of: UIColor.black)
        ]
        let speeds: [CGFloat] = [0.15, 0.35, 0.65]
        for (i, color) in colors.enumerated() {
            let layer = SKNode(); layer.zPosition = CGFloat(-3 + i)
            // Draw simple silhouette hills/buildings
            let shape = SKShapeNode(rectOf: CGSize(width: size.width * 3, height: size.height * 0.45))
            shape.fillColor = color.withAlphaComponent(0.55)
            shape.strokeColor = .clear
            shape.position = CGPoint(x: size.width / 2, y: size.height * (0.22 + CGFloat(i) * 0.04))
            layer.addChild(shape)
            // Skyline bumps
            for j in 0..<Int(size.width / 60) {
                let h = CGFloat.random(in: 40...(80 + CGFloat(i)*30))
                let w = CGFloat.random(in: 18...(30 + CGFloat(i)*10))
                let bld = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 2)
                bld.fillColor = color.pr_blended(withFraction: 0.15, of: UIColor.black)
                bld.strokeColor = .clear
                bld.position = CGPoint(x: CGFloat(j) * 65 + CGFloat.random(in: 0...30),
                                       y: size.height * 0.22 + h / 2)
                layer.addChild(bld)
            }
            layer.userData = ["speed": speeds[i]]
            bgLayers.append(layer)
            addChild(layer)
        }
    }

    // MARK: Ground
    private func setupGround() {
        let groundH: CGFloat = size.height * 0.14
        for i in 0..<3 {
            let tile = SKSpriteNode(color: cfg.groundUIColor, size: CGSize(width: size.width + 2, height: groundH))
            tile.position = CGPoint(x: CGFloat(i) * size.width, y: groundH / 2)
            tile.zPosition = 0
            tile.physicsBody = SKPhysicsBody(rectangleOf: tile.size)
            tile.physicsBody?.isDynamic = false
            tile.physicsBody?.categoryBitMask = catGround
            tile.physicsBody?.collisionBitMask = catPlayer
            groundNodes.append(tile)
            addChild(tile)
        }
        // Ground accent line
        let accent = SKShapeNode(rectOf: CGSize(width: size.width * 4, height: 3))
        accent.fillColor = cfg.accentUIColor; accent.strokeColor = .clear
        accent.position = CGPoint(x: size.width/2, y: groundH)
        accent.zPosition = 1
        addChild(accent)
    }

    // MARK: Player
    private func setupPlayer() {
        // Create a placeholder node so physics and actions can be attached after async sprite creation
        let container = SKNode()
        container.position = CGPoint(x: size.width * 0.22, y: size.height * 0.14 + 60)
        container.zPosition = 5
        self.playerNode = container
        addChild(container)

        // Defer sprite creation to an async context if the factory is async
        Task { [weak self] in
            guard let self else { return }
            // If makeSpriteNode is synchronous, this will still work; if it's async, we can `await` it.
            let sprite = await self.cfg.character.makeSpriteNode(scale: 1.0)
            sprite.position = .zero
            container.addChild(sprite)

            // Set up physics body on the container so collisions work regardless of sprite loading
            let pb = SKPhysicsBody(rectangleOf: CGSize(width: 36, height: 60), center: CGPoint(x: 0, y: 10))
            pb.categoryBitMask = self.catPlayer
            pb.contactTestBitMask = self.catGround | self.catObstacle | self.catCoin
            pb.collisionBitMask = self.catGround | self.catObstacle
            pb.allowsRotation = false; pb.restitution = 0; pb.friction = 0.2
            container.physicsBody = pb
            self.playerBody = pb

            // Run cycle: bob up and down
            let bob = SKAction.sequence([
                SKAction.moveBy(x: 0, y: 4, duration: 0.22),
                SKAction.moveBy(x: 0, y: -4, duration: 0.22)
            ])
            container.run(SKAction.repeatForever(bob), completion: {})
        }
    }

    // MARK: HUD
    private func setupHUD() {
        scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        scoreLabel.fontSize = 22; scoreLabel.fontColor = .white
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.position = CGPoint(x: 20, y: size.height - 52)
        scoreLabel.zPosition = 20; scoreLabel.text = "0"
        addChild(scoreLabel)

        let nameLbl = SKLabelNode(fontNamed: "AvenirNext-Bold")
        nameLbl.fontSize = 13; nameLbl.fontColor = cfg.accentUIColor.withAlphaComponent(0.85)
        nameLbl.horizontalAlignmentMode = .left
        nameLbl.position = CGPoint(x: 20, y: size.height - 72)
        nameLbl.zPosition = 20; nameLbl.text = cfg.gameName
        addChild(nameLbl)

        comboLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        comboLabel.fontSize = 28; comboLabel.fontColor = cfg.accentUIColor
        comboLabel.position = CGPoint(x: size.width/2, y: size.height * 0.55)
        comboLabel.zPosition = 20; comboLabel.alpha = 0
        addChild(comboLabel)
    }

    private func startGameMusic() {
        // Music handled externally; just note tone
    }

    // MARK: Game Loop
    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }

        // Scroll ground tiles
        let dt: CGFloat = 1.0 / 60.0
        for tile in groundNodes {
            tile.position.x -= gameSpeed * dt
            if tile.position.x < -size.width / 2 {
                tile.position.x += size.width * 3
            }
        }

        // Scroll parallax backgrounds
        for (i, layer) in bgLayers.enumerated() {
            let speed = gameSpeed * [0.15, 0.32, 0.6][i]
            layer.position.x -= speed * dt
            if layer.position.x < -size.width * 1.5 { layer.position.x = 0 }
        }

        // Scroll obstacles + coins
        for child in children {
            if child.name == "obstacle" || child.name == "coin" {
                child.position.x -= gameSpeed * dt
                if child.position.x < -80 { child.removeFromParent() }
            }
        }

        // Speed ramp
        gameSpeed = min(CGFloat(cfg.speed) * 2.2, gameSpeed + 0.3 * dt)
        spawnInterval = max(0.9, spawnInterval - 0.002 * dt)

        // Score
        scoreClock += dt
        if scoreClock >= 0.1 { score += 1; scoreLabel.text = "\(score)"; scoreClock = 0 }

        // Spawn obstacles / coins
        spawnClock += dt
        if spawnClock >= spawnInterval {
            spawnClock = 0
            Bool.random() ? spawnObstacle() : spawnCoin()
        }

        // Reset jump count when grounded (y velocity near zero)
        if let vel = playerNode.physicsBody?.velocity, abs(vel.dy) < 5 {
            jumpCount = 0
        }
    }

    // MARK: Spawning
    private func spawnObstacle() {
        let groundH = size.height * 0.14
        let type = Int.random(in: 0..<3)
        let node: SKNode

        switch type {
        case 0: // Rock on ground
            let rock = SKShapeNode(circleOfRadius: CGFloat.random(in: 18...30))
            rock.fillColor = UIColor(red: 0.5, green: 0.45, blue: 0.4, alpha: 1)
            rock.strokeColor = UIColor(red: 0.3, green: 0.27, blue: 0.24, alpha: 1); rock.lineWidth = 2
            node = rock
            node.position = CGPoint(x: size.width + 40, y: groundH + 25)
        case 1: // Floating platform
            let plat = SKShapeNode(rectOf: CGSize(width: 80, height: 16), cornerRadius: 4)
            plat.fillColor = cfg.accentUIColor.pr_blended(withFraction: 0.3, of: UIColor.black)
            plat.strokeColor = cfg.accentUIColor; plat.lineWidth = 1.5
            node = plat
            node.position = CGPoint(x: size.width + 50, y: groundH + CGFloat.random(in: 70...130))
        default: // Enemy blob
            let blob = SKNode()
            let body = SKShapeNode(circleOfRadius: 20)
            body.fillColor = cfg.accentUIColor.pr_blended(withFraction: 0.2, of: UIColor.black)
            body.strokeColor = cfg.accentUIColor; body.lineWidth = 2
            let eye1 = SKShapeNode(circleOfRadius: 5); eye1.fillColor = .white; eye1.position = CGPoint(x: -7, y: 6)
            let eye2 = SKShapeNode(circleOfRadius: 5); eye2.fillColor = .white; eye2.position = CGPoint(x: 7, y: 6)
            let p1 = SKShapeNode(circleOfRadius: 3); p1.fillColor = .black; p1.position = CGPoint(x: -7, y: 6)
            let p2 = SKShapeNode(circleOfRadius: 3); p2.fillColor = .black; p2.position = CGPoint(x: 7, y: 6)
            [body, eye1, eye2, p1, p2].forEach { blob.addChild($0) }
            node = blob
            node.position = CGPoint(x: size.width + 40, y: groundH + 25)
            let bounce = SKAction.sequence([SKAction.moveBy(x: 0, y: 15, duration: 0.35), SKAction.moveBy(x: 0, y: -15, duration: 0.35)])
            node.run(SKAction.repeatForever(bounce))
        }

        node.name = "obstacle"
        let pb = SKPhysicsBody(circleOfRadius: 22)
        pb.isDynamic = false; pb.categoryBitMask = catObstacle
        pb.contactTestBitMask = catPlayer; pb.collisionBitMask = catPlayer
        node.physicsBody = pb
        addChild(node)
    }

    private func spawnCoin() {
        let groundH = size.height * 0.14
        let coin = SKShapeNode(circleOfRadius: 12)
        coin.fillColor = UIColor(red: 1, green: 0.85, blue: 0.1, alpha: 1)
        coin.strokeColor = UIColor(red: 0.8, green: 0.6, blue: 0, alpha: 1); coin.lineWidth = 2
        let star = SKLabelNode(text: "★")
        star.fontSize = 10; star.fontColor = .white
        star.verticalAlignmentMode = .center; coin.addChild(star)
        coin.name = "coin"
        coin.position = CGPoint(x: size.width + 30, y: groundH + CGFloat.random(in: 40...130))
        let pb = SKPhysicsBody(circleOfRadius: 12)
        pb.isDynamic = false; pb.categoryBitMask = catCoin; pb.contactTestBitMask = catPlayer
        coin.physicsBody = pb
        coin.run(SKAction.sequence([SKAction.rotate(byAngle: .pi * 2, duration: 1)]).repeated())
        addChild(coin)
    }

    // MARK: Touch
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isGameOver {
            let fresh = PopRunnerScene(config: cfg, size: size)
            view?.presentScene(fresh, transition: SKTransition.fade(withDuration: 0.35))
            return
        }
        if jumpCount < 2 {
            jumpCount += 1
            playerNode.physicsBody?.velocity = CGVector(dx: 0, dy: 0)
            let impulse: CGFloat = jumpCount == 1 ? 340 : 260
            playerNode.physicsBody?.applyImpulse(CGVector(dx: 0, dy: impulse))
            let squish = SKAction.sequence([
                SKAction.scaleX(to: 0.8, y: 1.3, duration: 0.06),
                SKAction.scaleX(to: 1.0, y: 1.0, duration: 0.1)
            ])
            playerNode.run(squish)
        }
    }

    // MARK: Contacts
    func didBegin(_ contact: SKPhysicsContact) {
        let a = contact.bodyA.categoryBitMask, b = contact.bodyB.categoryBitMask
        if (a == catPlayer && b == catObstacle) || (a == catObstacle && b == catPlayer) {
            triggerGameOver()
        }
        if (a == catPlayer && b == catCoin) || (a == catCoin && b == catPlayer) {
            let coinNode = contact.bodyA.categoryBitMask == catCoin ? contact.bodyA.node : contact.bodyB.node
            coinNode?.removeFromParent()
            score += 10; scoreLabel.text = "\(score)"
            flash(text: "+10")
        }
    }

    // MARK: Game Over
    private func triggerGameOver() {
        guard !isGameOver else { return }
        isGameOver = true
        physicsWorld.speed = 0

        let shake = SKAction.sequence([
            SKAction.moveBy(x: -8, y: 0, duration: 0.04),
            SKAction.moveBy(x: 8, y: 0, duration: 0.04)
        ])
        camera?.run(SKAction.repeat(shake, count: 4))

        let overlay = SKShapeNode(rectOf: size)
        overlay.fillColor = UIColor.black.withAlphaComponent(0.65); overlay.strokeColor = .clear
        overlay.position = CGPoint(x: size.width/2, y: size.height/2); overlay.zPosition = 30
        addChild(overlay)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy"); title.text = "GAME OVER"
        title.fontSize = 36; title.fontColor = .white; title.position = CGPoint(x: 0, y: 60); title.zPosition = 1
        overlay.addChild(title)

        let sub = SKLabelNode(fontNamed: "AvenirNext-Bold"); sub.text = "Score: \(score)"
        sub.fontSize = 22; sub.fontColor = cfg.accentUIColor; sub.position = CGPoint(x: 0, y: 16); sub.zPosition = 1
        overlay.addChild(sub)

        let hint = SKLabelNode(fontNamed: "AvenirNext-Regular"); hint.text = "Tap to play again"
        hint.fontSize = 15; hint.fontColor = .lightGray; hint.position = CGPoint(x: 0, y: -22); hint.zPosition = 1
        hint.run(SKAction.repeatForever(SKAction.sequence([SKAction.fadeAlpha(to: 0.3, duration: 0.7), SKAction.fadeAlpha(to: 1, duration: 0.7)])))
        overlay.addChild(hint)
    }

    private func flash(text: String) {
        comboLabel.text = text; comboLabel.alpha = 1
        comboLabel.run(SKAction.sequence([
            SKAction.scale(to: 1.4, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.15),
            SKAction.wait(forDuration: 0.4),
            SKAction.fadeOut(withDuration: 0.3)
        ]))
    }
}
private extension SKAction {
    func repeated() -> SKAction { SKAction.repeatForever(self) }
}

private extension UIColor {
    func pr_blended(withFraction fraction: CGFloat, of other: UIColor) -> UIColor {
        let f = max(0, min(1, fraction))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        // Convert both colors to RGBA space; if conversion fails, return self
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
