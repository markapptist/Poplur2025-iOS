import SpriteKit
import UIKit

// MARK: - Poplur Pet SpriteKit Scene

final class PoplurPetScene: SKScene {

    // MARK: State

    var petState: PetState
    private var lastUpdate: TimeInterval = 0
    private var saveTimer:  TimeInterval = 0
    private var poopTimer:  TimeInterval = 0
    private let simSpeed:   Double       = 60   // 1 sim-minute = 1 real second

    // MARK: Layout nodes

    private var bgNode        = SKNode()
    private var petContainer  = SKNode()
    private var poopNode      = SKNode()
    private var menuLayer     = SKNode()
    private var cursorNode    = SKShapeNode()
    private var effectsLayer  = SKNode()
    private var statsPanel    = SKNode()
    private var dialogNode    = SKNode()

    // MARK: Menu state

    private let allActions = PetMenuAction.allCases
    private var selectedIndex = 0
    private var showingStats  = false
    private var activeAnim:   PetState.Mood? = nil   // nil = use petState.currentMood
    private var animResetTimer: TimeInterval = 0

    // MARK: Tint colours (one per screen background style, cycling with stage)

    private var bgTint: UIColor {
        switch petState.stage {
        case .egg:   return UIColor(red: 0.78, green: 0.85, blue: 1.00, alpha: 1) // lavender
        case .baby:  return UIColor(red: 1.00, green: 0.80, blue: 0.82, alpha: 1) // pink
        case .teen:  return UIColor(red: 0.78, green: 1.00, blue: 0.88, alpha: 1) // mint
        case .adult: return UIColor(red: 1.00, green: 0.90, blue: 0.68, alpha: 1) // peach
        }
    }

    // MARK: Init

    init(petState: PetState, size: CGSize) {
        self.petState = petState
        super.init(size: size)
        scaleMode = .resizeFill
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Scene lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 1)
        rebuildBackground()
        setupPetContainer()
        setupMenuBar()
        setupCursor()
        effectsLayer.zPosition = 50
        addChild(effectsLayer)
        refreshPetSprite(animated: false)
        updateCursor()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        rebuildBackground()
        layoutMenuBar()
        updateCursor()
    }

    // MARK: Game loop

    override func update(_ currentTime: TimeInterval) {
        guard lastUpdate > 0 else { lastUpdate = currentTime; return }
        let dt = min(currentTime - lastUpdate, 1.0 / 15.0)
        lastUpdate = currentTime

        petState.tick(seconds: dt * simSpeed)

        saveTimer += dt
        if saveTimer > 30 { PetSaveManager.save(petState); saveTimer = 0 }

        // Poop event: roughly every 4 simulated minutes if not already dirty
        poopTimer += dt * simSpeed
        if poopTimer > 240 && !petState.hasPoop && petState.stage != .egg {
            if Double.random(in: 0...1) < 0.012 {
                petState.hasPoop = true
                refreshPoopNode()
            }
            poopTimer = 0
        }

        // Check stage evolution
        let target = petState.targetStage
        if target != petState.stage {
            evolve(to: target)
        }

        // Reset action animation after 2 sim-seconds
        if activeAnim != nil {
            animResetTimer += dt * simSpeed
            if animResetTimer > 2 { clearActionAnim() }
        }

        updatePetMood()
    }

    // MARK: Background

    private func rebuildBackground() {
        bgNode.removeFromParent()
        bgNode = PoplurPetArt.makeBackground(size: size, tint: bgTint)
        addChild(bgNode)
    }

    // MARK: Pet container

    private func setupPetContainer() {
        petContainer.position = petCenter
        petContainer.zPosition = 10
        addChild(petContainer)

        poopNode.zPosition = 12
        addChild(poopNode)
    }

    private var petCenter: CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2 + 12)
    }

    private func refreshPetSprite(animated: Bool) {
        petContainer.removeAllChildren()
        let mood = activeAnim ?? petState.currentMood
        let scale: CGFloat = petState.stage == .adult ? 1.3 : (petState.stage == .teen ? 1.15 : 1.0)
        let pet = PoplurPetArt.makePet(stage: petState.stage, mood: mood, scale: scale)
        pet.position = .zero
        petContainer.addChild(pet)
        petContainer.position = petCenter

        // Idle bob animation
        petContainer.removeAction(forKey: "bob")
        if mood == .idle || mood == .happy {
            let bob = SKAction.sequence([
                SKAction.moveBy(x: 0, y: 4, duration: 0.55),
                SKAction.moveBy(x: 0, y: -4, duration: 0.55)
            ])
            petContainer.run(SKAction.repeatForever(bob), withKey: "bob")
        } else if mood == .sick {
            let shake = SKAction.sequence([
                SKAction.moveBy(x: -4, y: 0, duration: 0.08),
                SKAction.moveBy(x: 8, y: 0, duration: 0.08),
                SKAction.moveBy(x: -4, y: 0, duration: 0.08),
                SKAction.wait(forDuration: 1.2)
            ])
            petContainer.run(SKAction.repeatForever(shake), withKey: "bob")
        }

        if animated {
            petContainer.alpha = 0
            petContainer.run(SKAction.fadeIn(withDuration: 0.25))
        }
    }

    private func refreshPoopNode() {
        poopNode.removeAllChildren()
        guard petState.hasPoop else { return }
        let poop = PoplurPetArt.makePoop(scale: 0.85)
        poop.position = CGPoint(x: petCenter.x + 32, y: petCenter.y - 28)
        poopNode.addChild(poop)
        // Gentle sway
        poop.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.rotate(byAngle: 0.12, duration: 0.6),
            SKAction.rotate(byAngle: -0.12, duration: 0.6)
        ])))
    }

    // MARK: Menu bar

    private var menuBarY: CGFloat { 22 }

    private func setupMenuBar() {
        menuLayer.zPosition = 20
        addChild(menuLayer)
        layoutMenuBar()
    }

    private func layoutMenuBar() {
        menuLayer.removeAllChildren()
        let count  = CGFloat(allActions.count)
        let spacing = size.width / (count + 1)
        for (i, action) in allActions.enumerated() {
            let icon = PoplurPetArt.makeMenuIcon(for: action, scale: 0.9)
            icon.position = CGPoint(x: spacing * CGFloat(i + 1), y: menuBarY)
            icon.name = "menu_\(i)"
            menuLayer.addChild(icon)
        }
    }

    private func menuIconPosition(at index: Int) -> CGPoint {
        let count   = CGFloat(allActions.count)
        let spacing = size.width / (count + 1)
        return CGPoint(x: spacing * CGFloat(index + 1), y: menuBarY)
    }

    // MARK: Cursor

    private func setupCursor() {
        cursorNode.zPosition = 25
        addChild(cursorNode)
        updateCursor()
    }

    private func updateCursor() {
        cursorNode.removeAllChildren()
        let pos = menuIconPosition(at: selectedIndex)
        let ring = SKShapeNode(rectOf: CGSize(width: 22, height: 22), cornerRadius: 4)
        ring.strokeColor = UIColor(red: 0.9, green: 0.3, blue: 0.7, alpha: 1)
        ring.lineWidth = 2; ring.fillColor = .clear; ring.zPosition = 1
        cursorNode.position = pos
        cursorNode.addChild(ring)
        // Pulse
        cursorNode.removeAction(forKey: "pulse")
        cursorNode.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.12, duration: 0.4),
            SKAction.scale(to: 0.95, duration: 0.4)
        ])), withKey: "pulse")
    }

    // MARK: Stats panel

    private func toggleStats() {
        showingStats.toggle()
        statsPanel.removeFromParent()
        guard showingStats else { return }
        statsPanel = makeStatsPanel()
        addChild(statsPanel)
    }

    private func makeStatsPanel() -> SKNode {
        let n = SKNode()
        n.zPosition = 40
        let w: CGFloat = size.width * 0.88
        let h: CGFloat = size.height * 0.52
        let x = size.width / 2
        let y = size.height / 2 + 8

        let bg = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 10)
        bg.fillColor = UIColor(red: 1.0, green: 0.98, blue: 0.92, alpha: 0.96)
        bg.strokeColor = UIColor(red: 0.9, green: 0.3, blue: 0.65, alpha: 1); bg.lineWidth = 2
        bg.position = CGPoint(x: x, y: y); bg.zPosition = 1
        n.addChild(bg)

        let bars: [(String, Float, UIColor)] = [
            ("HUNGER",    petState.hunger,      UIColor(red: 1.0, green: 0.55, blue: 0.20, alpha: 1)),
            ("HAPPY",     petState.happiness,   UIColor(red: 1.0, green: 0.30, blue: 0.60, alpha: 1)),
            ("CLEAN",     petState.cleanliness, UIColor(red: 0.25, green: 0.72, blue: 0.98, alpha: 1)),
            ("ENERGY",    petState.energy,      UIColor(red: 0.40, green: 0.88, blue: 0.40, alpha: 1)),
            ("HEALTH",    petState.health,      UIColor(red: 0.85, green: 0.25, blue: 0.85, alpha: 1)),
        ]

        let barW: CGFloat = w * 0.50
        let barH: CGFloat = 9
        let gap:  CGFloat = (h - 24) / CGFloat(bars.count + 1)
        let startY = y + h * 0.38

        for (i, (label, val, color)) in bars.enumerated() {
            let rowY = startY - CGFloat(i) * gap

            let lbl = SKLabelNode(text: label)
            lbl.fontName = "AvenirNext-Bold"; lbl.fontSize = 9
            lbl.fontColor = UIColor(red: 0.25, green: 0.12, blue: 0.04, alpha: 1)
            lbl.horizontalAlignmentMode = .right
            lbl.position = CGPoint(x: x - barW / 2 - 6, y: rowY - 4)
            lbl.zPosition = 2
            n.addChild(lbl)

            let track = SKShapeNode(rectOf: CGSize(width: barW, height: barH), cornerRadius: barH / 2)
            track.fillColor = UIColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1); track.strokeColor = .clear
            track.position = CGPoint(x: x, y: rowY); track.zPosition = 2
            n.addChild(track)

            let fill = CGFloat(val) / 100 * barW
            let filled = SKShapeNode(rectOf: CGSize(width: max(4, fill), height: barH - 2), cornerRadius: (barH - 2) / 2)
            filled.fillColor = color; filled.strokeColor = .clear
            filled.position = CGPoint(x: x - barW / 2 + max(4, fill) / 2, y: rowY); filled.zPosition = 3
            n.addChild(filled)

            let valLbl = SKLabelNode(text: "\(Int(val))")
            valLbl.fontName = "AvenirNext-Bold"; valLbl.fontSize = 8.5
            valLbl.fontColor = color
            valLbl.horizontalAlignmentMode = .left
            valLbl.position = CGPoint(x: x + barW / 2 + 5, y: rowY - 4)
            valLbl.zPosition = 2
            n.addChild(valLbl)
        }

        // Age + care score
        let age = Int(petState.ageSeconds / 60)
        let info = SKLabelNode(text: "Age \(age)m · Care \(petState.careScore)")
        info.fontName = "AvenirNext-Medium"; info.fontSize = 8
        info.fontColor = UIColor(red: 0.5, green: 0.3, blue: 0.1, alpha: 0.8)
        info.position = CGPoint(x: x, y: y - h * 0.42); info.zPosition = 2
        n.addChild(info)

        if petState.isSick {
            let sick = SKLabelNode(text: "🤒 SICK")
            sick.fontName = "AvenirNext-Bold"; sick.fontSize = 10
            sick.fontColor = UIColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 1)
            sick.position = CGPoint(x: x, y: y + h * 0.42); sick.zPosition = 2
            n.addChild(sick)
        }

        // Tap anywhere to dismiss
        n.name = "statsPanel"
        return n
    }

    // MARK: Mood update

    private func updatePetMood() {
        let mood = petState.currentMood
        guard let child = petContainer.children.first else { return }
        let needsRefresh = !(child.name ?? "").contains(mood.rawValue)
        if needsRefresh { refreshPetSprite(animated: false) }

        // Ensure poop node is in sync
        if petState.hasPoop && poopNode.children.isEmpty { refreshPoopNode() }
        if !petState.hasPoop && !poopNode.children.isEmpty { poopNode.removeAllChildren() }
    }

    // MARK: Evolution

    private func evolve(to newStage: PetState.Stage) {
        petState.stage = newStage
        rebuildBackground()

        let flash = SKShapeNode(rectOf: size)
        flash.fillColor = .white; flash.strokeColor = .clear; flash.position = CGPoint(x: size.width/2, y: size.height/2)
        flash.zPosition = 100
        addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.1),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))

        petContainer.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.3),
            SKAction.run { [weak self] in
                self?.refreshPetSprite(animated: true)
                self?.spawnSparkles(count: 6)
            }
        ]))
        PetSaveManager.save(petState)
    }

    // MARK: Care actions

    func confirmAction() {
        if showingStats { toggleStats(); return }

        let action = allActions[selectedIndex]

        switch action {
        case .meal:
            petState.feed()
            playActionAnim(.eating)
            spawnFloatingIcon(text: "🍔")
        case .snack:
            petState.snack()
            playActionAnim(.happy)
            spawnFloatingIcon(text: "🍪")
        case .play:
            petState.play()
            playActionAnim(.playing)
            spawnSparkles(count: 4)
        case .bath:
            petState.bath()
            playActionAnim(.idle)
            refreshPoopNode()
            spawnDrops()
        case .medicine:
            petState.medicine()
            spawnSparkles(count: 5)
        case .sleep:
            petState.toggleSleep()
            if petState.isSleeping { spawnZzz() }
            refreshPetSprite(animated: true)
        case .stats:
            toggleStats()
        }

        PetSaveManager.save(petState)
    }

    func selectPrevious() { selectedIndex = (selectedIndex - 1 + allActions.count) % allActions.count; updateCursor() }
    func selectNext()     { selectedIndex = (selectedIndex + 1) % allActions.count; updateCursor() }

    // MARK: Action animations

    private func playActionAnim(_ mood: PetState.Mood) {
        activeAnim = mood
        animResetTimer = 0
        refreshPetSprite(animated: true)
    }

    private func clearActionAnim() {
        activeAnim = nil
        animResetTimer = 0
        refreshPetSprite(animated: false)
    }

    // MARK: Effects

    private func spawnFloatingIcon(text: String) {
        let lbl = SKLabelNode(text: text)
        lbl.fontSize = 26
        lbl.position = CGPoint(x: petCenter.x + CGFloat.random(in: -20...20),
                               y: petCenter.y + 20)
        lbl.zPosition = 60
        addChild(lbl)
        lbl.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: 50, duration: 1.0),
                SKAction.fadeOut(withDuration: 1.0)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    private func spawnSparkles(count: Int) {
        for i in 0..<count {
            let s = PoplurPetArt.makeSparkle(scale: 0.8)
            let angle = CGFloat(i) / CGFloat(count) * .pi * 2
            let r: CGFloat = CGFloat.random(in: 28...55)
            s.position = CGPoint(x: petCenter.x + cos(angle) * r,
                                 y: petCenter.y + sin(angle) * r)
            s.zPosition = 60
            s.setScale(0.1)
            addChild(s)
            s.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 1.2, duration: 0.25),
                    SKAction.rotate(byAngle: .pi * 0.5, duration: 0.25)
                ]),
                SKAction.group([
                    SKAction.scale(to: 0, duration: 0.35),
                    SKAction.fadeOut(withDuration: 0.35)
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func spawnDrops() {
        for _ in 0..<6 {
            let drop = SKShapeNode(ellipseIn: CGRect(x: -3, y: -5, width: 6, height: 10))
            drop.fillColor = UIColor(red: 0.4, green: 0.75, blue: 1.0, alpha: 0.85)
            drop.strokeColor = .clear
            drop.position = CGPoint(x: petCenter.x + CGFloat.random(in: -40...40),
                                    y: petCenter.y + CGFloat.random(in: 10...45))
            drop.zPosition = 60
            addChild(drop)
            drop.run(SKAction.sequence([
                SKAction.moveBy(x: CGFloat.random(in: -10...10), y: -55, duration: 0.6),
                SKAction.fadeOut(withDuration: 0.2),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func spawnZzz() {
        let zzz = PoplurPetArt.makeZzzNode(scale: 1.0)
        zzz.position = CGPoint(x: petCenter.x + 28, y: petCenter.y + 30)
        zzz.zPosition = 60
        addChild(zzz)
        zzz.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 8, y: 30, duration: 2.0),
                SKAction.sequence([
                    SKAction.wait(forDuration: 1.4),
                    SKAction.fadeOut(withDuration: 0.6)
                ])
            ]),
            SKAction.removeFromParent()
        ]))
    }

    private func spawnHearts() {
        for i in 0..<3 {
            let h = PoplurPetArt.makeHeart(scale: 0.7)
            h.position = CGPoint(x: petCenter.x + CGFloat(i - 1) * 22, y: petCenter.y + 18)
            h.zPosition = 60; h.setScale(0.3)
            addChild(h)
            h.run(SKAction.sequence([
                SKAction.wait(forDuration: Double(i) * 0.12),
                SKAction.group([
                    SKAction.scale(to: 1.0, duration: 0.25),
                    SKAction.moveBy(x: 0, y: 40, duration: 0.9),
                    SKAction.sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.3)])
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }

    // MARK: Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)

        // Dismiss stats on tap
        if showingStats { toggleStats(); return }

        // Check menu icon taps
        for (i, _) in allActions.enumerated() {
            let pos = menuIconPosition(at: i)
            if abs(loc.x - pos.x) < 18 && abs(loc.y - pos.y) < 18 {
                selectedIndex = i
                updateCursor()
                confirmAction()
                return
            }
        }

        // Tap pet = confetti hearts
        let pc = petCenter
        if abs(loc.x - pc.x) < 50 && abs(loc.y - pc.y) < 60 {
            spawnHearts()
        }
    }
}
