import SpriteKit
import UIKit

// MARK: - Rex Hoops (Basketball Sports)

final class RexHoopsScene: SKScene, SKPhysicsContactDelegate {

    private let cfg: PoplurGameConfig
    private let catBall:   UInt32 = 0x01
    private let catHoop:   UInt32 = 0x02
    private let catGround: UInt32 = 0x04
    private let catSensor: UInt32 = 0x08

    // Game state
    private var score = 0
    private var streak = 0
    private var shotClock = 24
    private var shotClockAccum: TimeInterval = 0
    private var isAiming = false
    private var isBallInFlight = false
    private var isGameOver = false
    private var ballNode: SKNode!
    private var playerNode: SKNode!
    private var hoopNode: SKNode!
    private var scoreSensor: SKNode!
    private var aimArrow: SKShapeNode?

    // Dragging
    private var dragStart: CGPoint?
    private var launchMultiplier: CGFloat = 1.0

    // Scoring
    private var pendingScore = false

    // HUD
    private var scoreLabel: SKLabelNode!
    private var streakLabel: SKLabelNode!
    private var shotClockLabel: SKLabelNode!
    private var comboLabel: SKLabelNode!

    // Court decoration
    private var hoopY: CGFloat = 0

    init(config: PoplurGameConfig, size: CGSize) {
        cfg = config; super.init(size: size); scaleMode = .resizeFill
    }
    required init?(coder aDecoder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        backgroundColor = cfg.skyUIColor
        physicsWorld.gravity = CGVector(dx: 0, dy: -14)
        physicsWorld.contactDelegate = self
        buildCourt()
        setupHoop()
        setupPlayer()
        setupBall()
        setupHUD()
    }

    // MARK: Court

    private func buildCourt() {
        // Floor
        let floor = SKSpriteNode(color: cfg.groundUIColor, size: CGSize(width: size.width, height: 60))
        floor.position = CGPoint(x: size.width/2, y: 30); floor.zPosition = 0
        let pb = SKPhysicsBody(rectangleOf: floor.size)
        pb.isDynamic = false; pb.categoryBitMask = catGround
        pb.collisionBitMask = catBall; pb.contactTestBitMask = catBall
        floor.physicsBody = pb; addChild(floor)

        // Court lines
        let mid = SKShapeNode(rectOf: CGSize(width: size.width - 40, height: 3))
        mid.fillColor = cfg.accentUIColor.withAlphaComponent(0.4); mid.strokeColor = .clear
        mid.position = CGPoint(x: size.width/2, y: 64); mid.zPosition = 1; addChild(mid)

        // Three-point arc (decorative)
        let arcPath = CGMutablePath()
        arcPath.addArc(center: CGPoint(x: size.width * 0.22, y: 65), radius: size.height * 0.32,
                       startAngle: 0, endAngle: .pi, clockwise: false)
        let arc = SKShapeNode(path: arcPath)
        arc.strokeColor = cfg.accentUIColor.withAlphaComponent(0.3); arc.lineWidth = 2
        arc.fillColor = .clear; arc.zPosition = 1; addChild(arc)

        // Backboard position
        hoopY = size.height * 0.62
    }

    // MARK: Hoop

    private func setupHoop() {
        let hoopX = size.width * 0.78
        hoopNode = SKNode(); hoopNode.position = CGPoint(x: hoopX, y: hoopY); hoopNode.zPosition = 3
        addChild(hoopNode)

        // Backboard
        let board = SKShapeNode(rectOf: CGSize(width: 8, height: 80), cornerRadius: 2)
        board.fillColor = UIColor.white.withAlphaComponent(0.9); board.strokeColor = .gray; board.lineWidth = 1
        board.position = CGPoint(x: 28, y: 0); hoopNode.addChild(board)

        // Rim (two endpoints of hoop)
        let rimLeft = SKShapeNode(circleOfRadius: 5)
        rimLeft.fillColor = UIColor(red: 0.95, green: 0.45, blue: 0.1, alpha: 1)
        rimLeft.strokeColor = .clear; rimLeft.position = CGPoint(x: -18, y: -6)
        let pb1 = SKPhysicsBody(circleOfRadius: 5); pb1.isDynamic = false
        pb1.categoryBitMask = catHoop; pb1.collisionBitMask = catBall; rimLeft.physicsBody = pb1
        hoopNode.addChild(rimLeft)

        let rimRight = SKShapeNode(circleOfRadius: 5)
        rimRight.fillColor = UIColor(red: 0.95, green: 0.45, blue: 0.1, alpha: 1)
        rimRight.strokeColor = .clear; rimRight.position = CGPoint(x: 18, y: -6)
        let pb2 = SKPhysicsBody(circleOfRadius: 5); pb2.isDynamic = false
        pb2.categoryBitMask = catHoop; pb2.collisionBitMask = catBall; rimRight.physicsBody = pb2
        hoopNode.addChild(rimRight)

        // Rim bar
        let bar = SKShapeNode(rectOf: CGSize(width: 36, height: 4))
        bar.fillColor = UIColor(red: 0.95, green: 0.45, blue: 0.1, alpha: 1)
        bar.strokeColor = .clear; bar.position = CGPoint(x: 0, y: -6); hoopNode.addChild(bar)

        // Net (visual only)
        for i in 0..<6 {
            let netLine = SKShapeNode()
            let path = CGMutablePath()
            let sx = CGFloat(-15 + i * 6)
            path.move(to: CGPoint(x: sx, y: -8))
            path.addLine(to: CGPoint(x: sx + CGFloat.random(in: -4...4), y: -30))
            netLine.path = path
            netLine.strokeColor = UIColor.white.withAlphaComponent(0.5); netLine.lineWidth = 1
            hoopNode.addChild(netLine)
        }

        // Score sensor (invisible trigger zone inside net)
        scoreSensor = SKNode(); scoreSensor.position = CGPoint(x: hoopX, y: hoopY - 18); scoreSensor.zPosition = 3
        let sPb = SKPhysicsBody(rectangleOf: CGSize(width: 28, height: 10))
        sPb.isDynamic = false; sPb.categoryBitMask = catSensor
        sPb.contactTestBitMask = catBall; sPb.collisionBitMask = 0
        scoreSensor.physicsBody = sPb
        addChild(scoreSensor)

        // Support pole
        let pole = SKShapeNode(rectOf: CGSize(width: 6, height: size.height * 0.38))
        pole.fillColor = UIColor.gray.withAlphaComponent(0.6); pole.strokeColor = .clear
        pole.position = CGPoint(x: hoopX + 28, y: hoopY - size.height * 0.19); pole.zPosition = 2
        addChild(pole)
    }

    // MARK: Player

    private func setupPlayer() {
        playerNode = cfg.character.makeSpriteNode(scale: 1.1)
        playerNode.position = CGPoint(x: size.width * 0.22, y: 85)
        playerNode.zPosition = 5; addChild(playerNode)
    }

    // MARK: Ball

    private func setupBall() {
        resetBall()
    }

    private func resetBall() {
        ballNode?.removeFromParent()
        let ball = SKShapeNode(circleOfRadius: 14)
        ball.fillColor = UIColor(red: 0.93, green: 0.47, blue: 0.15, alpha: 1)
        ball.strokeColor = UIColor(red: 0.6, green: 0.25, blue: 0.05, alpha: 1); ball.lineWidth = 2
        // Ball lines
        for angle in [CGFloat.pi/4, CGFloat.pi/2, CGFloat(3)*CGFloat.pi/4] {
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: 14, startAngle: angle - 0.7, endAngle: angle + 0.7, clockwise: false)
            line.path = path; line.strokeColor = UIColor(red: 0.6, green: 0.25, blue: 0.05, alpha: 0.7)
            line.lineWidth = 1.5; ball.addChild(line)
        }
        ball.name = "ball"; ball.zPosition = 6

        let pb = SKPhysicsBody(circleOfRadius: 14)
        pb.categoryBitMask = catBall
        pb.contactTestBitMask = catHoop | catGround | catSensor
        pb.collisionBitMask = catHoop | catGround
        pb.restitution = 0.55; pb.friction = 0.3; pb.linearDamping = 0.15
        ball.physicsBody = pb
        ball.position = CGPoint(x: size.width * 0.22, y: 120)
        addChild(ball); ballNode = ball
        isBallInFlight = false; pendingScore = false
    }

    // MARK: HUD

    private func setupHUD() {
        scoreLabel = hudLabel("0", pos: CGPoint(x: 20, y: size.height - 50), align: .left, size: 30)
        streakLabel = hudLabel("", pos: CGPoint(x: size.width - 20, y: size.height - 50), align: .right, size: 18)
        shotClockLabel = hudLabel("24", pos: CGPoint(x: size.width/2, y: size.height - 50), align: .center, size: 22)
        comboLabel = hudLabel("", pos: CGPoint(x: size.width/2, y: size.height * 0.45), align: .center, size: 34)
        comboLabel.alpha = 0
    }

    @discardableResult
    private func hudLabel(_ text: String, pos: CGPoint, align: SKLabelHorizontalAlignmentMode, size: CGFloat) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        l.text = text; l.fontSize = size; l.fontColor = .white
        l.horizontalAlignmentMode = align; l.position = pos; l.zPosition = 20
        addChild(l); return l
    }

    // MARK: Aim Arrow

    private func updateAimArrow(from start: CGPoint, to end: CGPoint) {
        aimArrow?.removeFromParent()
        let dx = end.x - start.x; let dy = end.y - start.y
        let launchV = CGVector(dx: -dx * 1.8 * launchMultiplier, dy: -dy * 1.8 * launchMultiplier)

        let arrowPath = CGMutablePath()
        var pos = CGPoint(x: ballNode.position.x, y: ballNode.position.y)
        arrowPath.move(to: pos)
        let steps = 18
        let dt: CGFloat = 0.07
        for _ in 0..<steps {
            let vx = launchV.dx
            var vy = launchV.dy
            vy += -14 * 60 * dt
            pos.x += vx * dt; pos.y += vy * dt
            arrowPath.addLine(to: pos)
        }
        let arrow = SKShapeNode(path: arrowPath)
        arrow.strokeColor = cfg.accentUIColor.withAlphaComponent(0.55)
        arrow.lineWidth = 2
        arrow.zPosition = 7; addChild(arrow); aimArrow = arrow
    }

    // MARK: Game Loop

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }
        let dt: TimeInterval = 1.0/60.0

        // Shot clock
        if isBallInFlight {
            shotClockAccum += dt
            if shotClockAccum >= 1.0 {
                shotClockAccum = 0; shotClock -= 1
                shotClockLabel.text = "\(shotClock)"
                if shotClock <= 0 { triggerGameOver() }
            }
        }

        // Ball out of bounds
        if isBallInFlight, let ball = ballNode {
            if ball.position.x > size.width + 40 || ball.position.x < -40 || ball.position.y < -40 {
                streak = 0; streakLabel.text = ""
                run(SKAction.wait(forDuration: 0.4)) { [weak self] in self?.resetBall() }
            }
        }
    }

    // MARK: Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let a = contact.bodyA, b = contact.bodyB
        if (a.categoryBitMask == catBall && b.categoryBitMask == catSensor) ||
           (a.categoryBitMask == catSensor && b.categoryBitMask == catBall) {
            if isBallInFlight && !pendingScore {
                pendingScore = true
                run(SKAction.wait(forDuration: 0.08)) { [weak self] in self?.scoreBasket() }
            }
        }
        if (a.categoryBitMask == catBall && b.categoryBitMask == catGround) ||
           (a.categoryBitMask == catGround && b.categoryBitMask == catBall) {
            if isBallInFlight && !pendingScore {
                streak = 0; streakLabel.text = ""
                run(SKAction.wait(forDuration: 0.7)) { [weak self] in self?.resetBall() }
            }
        }
    }

    private func scoreBasket() {
        streak += 1
        let pts = streak >= 3 ? 3 : (streak == 2 ? 2 : 1)
        score += pts
        shotClock = min(shotClock + 6, 24)
        scoreLabel.text = "\(score)"
        shotClockLabel.text = "\(shotClock)"
        streakLabel.text = streak >= 2 ? "🔥 x\(streak)" : ""

        // Combo popup
        let msg = streak >= 4 ? "UNREAL! +\(pts)" : streak >= 3 ? "FIRE! +\(pts)" : streak >= 2 ? "Nice! +\(pts)" : "+\(pts)"
        comboLabel.text = msg
        comboLabel.fontSize = streak >= 3 ? 40 : 28
        comboLabel.fontColor = streak >= 3 ? cfg.accentUIColor : .white
        comboLabel.alpha = 1
        comboLabel.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.3, duration: 0.12), SKAction.fadeAlpha(to: 1, duration: 0.12)]),
            SKAction.group([SKAction.scale(to: 1.0, duration: 0.25), SKAction.fadeAlpha(to: 0, duration: 0.8)])
        ]))

        run(SKAction.wait(forDuration: 0.6)) { [weak self] in self?.resetBall() }
    }

    private func triggerGameOver() {
        isGameOver = true
        let overlay = SKShapeNode(rectOf: size)
        overlay.fillColor = UIColor.black.withAlphaComponent(0.7)
        overlay.strokeColor = .clear; overlay.position = CGPoint(x: size.width/2, y: size.height/2)
        overlay.zPosition = 100; addChild(overlay)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "BUZZER!"; title.fontSize = 44; title.fontColor = cfg.accentUIColor
        title.position = CGPoint(x: 0, y: 40); overlay.addChild(title)

        let sub = SKLabelNode(fontNamed: "AvenirNext-Bold")
        sub.text = "Final Score: \(score)"; sub.fontSize = 22; sub.fontColor = .white
        sub.position = CGPoint(x: 0, y: -8); overlay.addChild(sub)

        let tap = SKLabelNode(fontNamed: "AvenirNext-Medium")
        tap.text = "Tap to play again"; tap.fontSize = 16; tap.fontColor = UIColor.white.withAlphaComponent(0.6)
        tap.position = CGPoint(x: 0, y: -52)
        tap.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.6), SKAction.fadeAlpha(to: 1.0, duration: 0.6)
        ])))
        overlay.addChild(tap)
    }

    // MARK: Touch (drag-to-shoot)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, !isGameOver, !isBallInFlight else {
            if isGameOver, touches.first != nil { restart() }
            return
        }
        let pos = touch.location(in: self)
        dragStart = pos; isAiming = true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, isAiming, let start = dragStart else { return }
        let pos = touch.location(in: self)
        updateAimArrow(from: start, to: pos)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, isAiming, let start = dragStart else { return }
        aimArrow?.removeFromParent(); aimArrow = nil
        isAiming = false

        let pos = touch.location(in: self)
        let dx = pos.x - start.x; let dy = pos.y - start.y
        let mag = hypot(dx, dy)
        guard mag > 15 else { return }  // too small a drag

        let launchDx = -dx * 1.8 * launchMultiplier
        let launchDy = -dy * 1.8 * launchMultiplier

        ballNode.physicsBody?.velocity = CGVector(dx: launchDx, dy: launchDy)
        isBallInFlight = true; dragStart = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isAiming = false; dragStart = nil
        aimArrow?.removeFromParent(); aimArrow = nil
    }

    private func restart() {
        let fresh = RexHoopsScene(config: cfg, size: size)
        view?.presentScene(fresh, transition: SKTransition.fade(withDuration: 0.4))
    }
}
