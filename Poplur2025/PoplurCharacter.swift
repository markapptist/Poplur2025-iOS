import UIKit
import SpriteKit

// MARK: - Character Definitions

enum PoplurCharacterID: String, CaseIterable, Codable {
    case pop, zyla, blip, rex, stella, glitch

    var displayName: String {
        switch self {
        case .pop: "Pop"; case .zyla: "Zyla"; case .blip: "Blip"
        case .rex: "Rex"; case .stella: "Stella"; case .glitch: "Glitch"
        }
    }
    var role: String {
        switch self {
        case .pop: "The Hero"; case .zyla: "The Adventurer"; case .blip: "The Speedster"
        case .rex: "The Powerhouse"; case .stella: "The Tech Hero"; case .glitch: "The Wildcard"
        }
    }
    var specialAbility: String {
        switch self {
        case .pop: "Double Jump"; case .zyla: "Blade Dash"; case .blip: "Speed Burst"
        case .rex: "Ground Slam"; case .stella: "Cannon Shot"; case .glitch: "Shapeshift"
        }
    }
    var primaryColor: UIColor {
        switch self {
        case .pop:    UIColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 1)
        case .zyla:   UIColor(red: 0.08, green: 0.50, blue: 0.24, alpha: 1)
        case .blip:   UIColor(red: 0.11, green: 0.31, blue: 0.86, alpha: 1)
        case .rex:    UIColor(red: 0.85, green: 0.50, blue: 0.03, alpha: 1)
        case .stella: UIColor(red: 0.06, green: 0.46, blue: 0.58, alpha: 1)
        case .glitch: UIColor(red: 0.93, green: 0.29, blue: 0.60, alpha: 1)
        }
    }
    var accentColor: UIColor {
        switch self {
        case .pop:    UIColor(red: 0.15, green: 0.40, blue: 0.94, alpha: 1)
        case .zyla:   UIColor(red: 0.42, green: 0.13, blue: 0.67, alpha: 1)
        case .blip:   UIColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1)
        case .rex:    UIColor(red: 0.99, green: 0.85, blue: 0.41, alpha: 1)
        case .stella: UIColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1)
        case .glitch: UIColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 1)
        }
    }

    func makeSpriteNode(scale: CGFloat = 1.0) -> SKNode {
        PoplurCharacterSprite.make(character: self, scale: scale)
    }
}

// MARK: - Sprite Builder

enum PoplurCharacterSprite {
    private static let skin = UIColor(red: 0.96, green: 0.77, blue: 0.64, alpha: 1)

    static func make(character: PoplurCharacterID, scale: CGFloat) -> SKNode {
        let root = SKNode()
        let u = 5.0 * scale
        switch character {
        case .pop:    buildPop(root, u: u)
        case .zyla:   buildZyla(root, u: u)
        case .blip:   buildBlip(root, u: u)
        case .rex:    buildRex(root, u: u)
        case .stella: buildStella(root, u: u)
        case .glitch: buildGlitch(root, u: u)
        }
        return root
    }

    private static func box(_ w: CGFloat, _ h: CGFloat, _ c: UIColor, _ pos: CGPoint, zPos: CGFloat = 0) -> SKShapeNode {
        let n = SKShapeNode(rectOf: CGSize(width: w, height: h))
        n.fillColor = c; n.strokeColor = UIColor.black.withAlphaComponent(0.35); n.lineWidth = 0.4
        n.position = pos; n.zPosition = zPos; return n
    }
    private static func dot(_ r: CGFloat, _ c: UIColor, _ pos: CGPoint, zPos: CGFloat = 0) -> SKShapeNode {
        let n = SKShapeNode(circleOfRadius: r)
        n.fillColor = c; n.strokeColor = UIColor.black.withAlphaComponent(0.25); n.lineWidth = 0.3
        n.position = pos; n.zPosition = zPos; return n
    }

    // MARK: Pop — red/blue hero
    static func buildPop(_ r: SKNode, u: CGFloat) {
        let red = UIColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 1)
        let blue = UIColor(red: 0.13, green: 0.25, blue: 0.75, alpha: 1)
        let dark = UIColor(red: 0.06, green: 0.07, blue: 0.14, alpha: 1)
        let brown = UIColor(red: 0.47, green: 0.21, blue: 0.07, alpha: 1)
        [box(u*1.4, u*0.65, dark, CGPoint(x: -u, y: -u*3.2)),
         box(u*1.4, u*0.65, dark, CGPoint(x: u, y: -u*3.2)),
         box(u*1.0, u*2.2, blue, CGPoint(x: -u*0.9, y: -u*1.8)),
         box(u*1.0, u*2.2, blue, CGPoint(x: u*0.9, y: -u*1.8)),
         box(u*2.8, u*3.2, red, .zero),
         box(u*1.5, u*1.9, blue, CGPoint(x: 0, y: u*0.3), zPos: 1),
         box(u*0.85, u*2.4, red, CGPoint(x: -u*1.8, y: u*0.2)),
         box(u*0.85, u*2.4, red, CGPoint(x: u*1.8, y: u*0.2)),
         dot(u*0.85, .white, CGPoint(x: -u*1.85, y: -u*0.9)),
         dot(u*0.85, .white, CGPoint(x: u*1.85, y: -u*0.9)),
         box(u*0.85, u*0.6, skin, CGPoint(x: 0, y: u*2.1)),
         box(u*2.8, u*2.8, skin, CGPoint(x: 0, y: u*3.7)),
         box(u*0.8, u*0.65, .white, CGPoint(x: -u*0.65, y: u*3.95), zPos: 2),
         box(u*0.8, u*0.65, .white, CGPoint(x: u*0.65, y: u*3.95), zPos: 2),
         dot(u*0.28, dark, CGPoint(x: -u*0.65, y: u*3.95), zPos: 3),
         dot(u*0.28, dark, CGPoint(x: u*0.65, y: u*3.95), zPos: 3),
         box(u*1.0, u*0.25, brown, CGPoint(x: 0, y: u*3.3), zPos: 2),
         box(u*3.6, u*0.28, blue, CGPoint(x: 0, y: u*5.35)),
         box(u*2.7, u*1.45, blue, CGPoint(x: 0, y: u*6.2))
        ].forEach { r.addChild($0) }
        let lbl = SKLabelNode(text: "P"); lbl.fontName = "AvenirNext-Heavy"
        lbl.fontSize = u*1.3; lbl.fontColor = UIColor(red: 1, green: 0.85, blue: 0, alpha: 1)
        lbl.verticalAlignmentMode = .center; lbl.position = CGPoint(x: 0, y: u*6.2); lbl.zPosition = 2
        r.addChild(lbl)
    }

    // MARK: Zyla — green tunic + energy sword
    static func buildZyla(_ r: SKNode, u: CGFloat) {
        let green = UIColor(red: 0.08, green: 0.50, blue: 0.24, alpha: 1)
        let brown = UIColor(red: 0.36, green: 0.23, blue: 0.16, alpha: 1)
        let purple = UIColor(red: 0.42, green: 0.13, blue: 0.67, alpha: 1)
        let dkPurple = UIColor(red: 0.29, green: 0.04, blue: 0.50, alpha: 1)
        let gold = UIColor(red: 0.83, green: 0.69, blue: 0.22, alpha: 1)
        let blade = UIColor(red: 0.91, green: 0.47, blue: 0.98, alpha: 0.85)
        [box(u*1.2, u*0.85, brown, CGPoint(x: -u*0.8, y: -u*3.2)),
         box(u*1.2, u*0.85, brown, CGPoint(x: u*0.8, y: -u*3.2)),
         box(u*0.85, u*2.0, brown, CGPoint(x: -u*0.8, y: -u*1.8)),
         box(u*0.85, u*2.0, brown, CGPoint(x: u*0.8, y: -u*1.8)),
         box(u*2.4, u*3.0, UIColor(red: 0.06, green: 0.38, blue: 0.18, alpha: 1), CGPoint(x: 0, y: u*0.1), zPos: -1),
         box(u*2.4, u*3.2, green, .zero),
         box(u*2.6, u*0.38, gold, CGPoint(x: 0, y: -u*0.9), zPos: 1),
         box(u*0.75, u*2.4, green, CGPoint(x: -u*1.7, y: u*0.2)),
         box(u*0.75, u*2.4, green, CGPoint(x: u*1.7, y: u*0.2)),
         box(u*0.3, u*1.2, brown, CGPoint(x: u*2.9, y: -u*0.1), zPos: 2),
         box(u*0.85, u*0.25, gold, CGPoint(x: u*2.9, y: u*0.65), zPos: 2),
         box(u*0.2, u*3.0, purple, CGPoint(x: u*2.9, y: u*2.2), zPos: 2),
         box(u*0.1, u*2.85, blade, CGPoint(x: u*2.9, y: u*2.2), zPos: 3),
         box(u*0.85, u*0.55, skin, CGPoint(x: 0, y: u*2.1)),
         box(u*2.6, u*2.6, skin, CGPoint(x: 0, y: u*3.7)),
         box(u*0.75, u*0.58, .white, CGPoint(x: -u*0.55, y: u*3.9), zPos: 2),
         box(u*0.75, u*0.58, .white, CGPoint(x: u*0.55, y: u*3.9), zPos: 2),
         dot(u*0.26, UIColor(red: 0.49, green: 0.14, blue: 0.75, alpha: 1), CGPoint(x: -u*0.55, y: u*3.9), zPos: 3),
         dot(u*0.26, UIColor(red: 0.49, green: 0.14, blue: 0.75, alpha: 1), CGPoint(x: u*0.55, y: u*3.9), zPos: 3),
         box(u*2.8, u*0.5, dkPurple, CGPoint(x: 0, y: u*5.3)),
         box(u*2.8, u*0.55, dkPurple, CGPoint(x: -u*0.1, y: u*5.75)),
         dot(u*0.75, dkPurple, CGPoint(x: -u*0.15, y: u*6.35)),
         box(u*1.7, u*0.26, gold, CGPoint(x: 0, y: u*5.3), zPos: 1)
        ].forEach { r.addChild($0) }
        let earL = earNode(pointing: -1, u: u); r.addChild(earL)
        let earR = earNode(pointing: 1, u: u);  r.addChild(earR)
    }
    private static func earNode(pointing: CGFloat, u: CGFloat) -> SKShapeNode {
        let p = CGMutablePath()
        let bx: CGFloat = pointing * u * 1.55
        p.addLines(between: [CGPoint(x: bx, y: u*3.2), CGPoint(x: pointing*u*2.1, y: u*4.2), CGPoint(x: pointing*u*1.25, y: u*4.2)])
        let n = SKShapeNode(path: p); n.fillColor = skin; n.strokeColor = UIColor.black.withAlphaComponent(0.3); n.lineWidth = 0.4
        return n
    }

    // MARK: Blip — blue speedster + visor
    static func buildBlip(_ r: SKNode, u: CGFloat) {
        let blue = UIColor(red: 0.11, green: 0.31, blue: 0.86, alpha: 1)
        let ltBlue = UIColor(red: 0.38, green: 0.64, blue: 0.98, alpha: 1)
        let yellow = UIColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1)
        let dark = UIColor(red: 0.06, green: 0.07, blue: 0.14, alpha: 1)
        let glowY = UIColor(red: 0.99, green: 0.93, blue: 0.64, alpha: 0.7)
        [box(u*1.6, u*0.62, yellow, CGPoint(x: -u*0.85, y: -u*3.2)),
         box(u*1.6, u*0.62, yellow, CGPoint(x: u*0.85, y: -u*3.2)),
         box(u*1.45, u*0.18, glowY, CGPoint(x: -u*0.85, y: -u*3.55)),
         box(u*1.45, u*0.18, glowY, CGPoint(x: u*0.85, y: -u*3.55)),
         box(u*0.85, u*2.0, blue, CGPoint(x: -u*0.85, y: -u*1.8)),
         box(u*0.85, u*2.0, blue, CGPoint(x: u*0.85, y: -u*1.8)),
         box(u*2.5, u*3.1, blue, CGPoint(x: 0, y: u*0.1)),
         box(u*0.75, u*2.3, blue, CGPoint(x: -u*1.65, y: u*0.2)),
         box(u*0.75, u*2.3, blue, CGPoint(x: u*1.65, y: u*0.2)),
         box(u*2.65, u*2.7, ltBlue, CGPoint(x: 0, y: u*3.65)),
         box(u*2.7, u*1.0, dark, CGPoint(x: 0, y: u*3.9), zPos: 2),
         box(u*0.85, u*0.7, UIColor(red: 0.22, green: 0.74, blue: 0.98, alpha: 0.6), CGPoint(x: -u*0.6, y: u*3.95), zPos: 3),
         box(u*0.85, u*0.7, UIColor(red: 0.22, green: 0.74, blue: 0.98, alpha: 0.6), CGPoint(x: u*0.6, y: u*3.95), zPos: 3),
         box(u*0.55, u*0.2, blue, CGPoint(x: u*0.2, y: u*3.25), zPos: 2)
        ].forEach { r.addChild($0) }
        let bolt = SKShapeNode(); let bp = CGMutablePath()
        bp.move(to: CGPoint(x: -u*0.35, y: u*1.7)); bp.addLine(to: CGPoint(x: u*0.2, y: u*0.2))
        bp.addLine(to: CGPoint(x: -u*0.05, y: u*0.2)); bp.addLine(to: CGPoint(x: u*0.35, y: -u*1.4))
        bp.addLine(to: CGPoint(x: -u*0.35, y: u*0.35)); bp.addLine(to: CGPoint(x: 0.0, y: u*0.35))
        bolt.path = bp; bolt.fillColor = yellow; bolt.strokeColor = .clear; bolt.zPosition = 1
        r.addChild(bolt)
    }

    // MARK: Rex — orange powerhouse
    static func buildRex(_ r: SKNode, u: CGFloat) {
        let orange = UIColor(red: 0.85, green: 0.50, blue: 0.03, alpha: 1)
        let dkOrange = UIColor(red: 0.71, green: 0.34, blue: 0.02, alpha: 1)
        let amber = UIColor(red: 0.97, green: 0.76, blue: 0.25, alpha: 1)
        let cream = UIColor(red: 0.99, green: 0.93, blue: 0.80, alpha: 1)
        let pink = UIColor(red: 0.99, green: 0.64, blue: 0.64, alpha: 1)
        let dark = UIColor(red: 0.06, green: 0.07, blue: 0.14, alpha: 1)
        [box(u*1.9, u*0.75, dkOrange, CGPoint(x: -u*1.0, y: -u*3.3)),
         box(u*1.9, u*0.75, dkOrange, CGPoint(x: u*1.0, y: -u*3.3)),
         box(u*1.35, u*2.2, dkOrange, CGPoint(x: -u*0.95, y: -u*1.8)),
         box(u*1.35, u*2.2, dkOrange, CGPoint(x: u*0.95, y: -u*1.8)),
         box(u*4.0, u*3.6, orange, CGPoint(x: 0, y: u*0.2)),
         dot(u*1.3, cream, CGPoint(x: 0, y: u*0.0), zPos: 1),
         box(u*1.25, u*3.2, orange, CGPoint(x: -u*3.1, y: u*0.3)),
         box(u*1.25, u*3.2, orange, CGPoint(x: u*3.1, y: u*0.3)),
         dot(u*1.6, dkOrange, CGPoint(x: -u*3.1, y: -u*1.4)),
         dot(u*1.6, dkOrange, CGPoint(x: u*3.1, y: -u*1.4)),
         box(u*3.9, u*0.5, orange, CGPoint(x: 0, y: u*2.1)),
         box(u*3.8, u*3.6, amber, CGPoint(x: 0, y: u*4.0)),
         dot(u*0.95, orange, CGPoint(x: -u*2.1, y: u*5.55)),
         dot(u*0.95, orange, CGPoint(x: u*2.1, y: u*5.55)),
         dot(u*0.52, pink, CGPoint(x: -u*2.1, y: u*5.55), zPos: 1),
         dot(u*0.52, pink, CGPoint(x: u*2.1, y: u*5.55), zPos: 1),
         dot(u*0.75, .white, CGPoint(x: -u*0.95, y: u*4.1)),
         dot(u*0.75, .white, CGPoint(x: u*0.95, y: u*4.1)),
         dot(u*0.45, dark, CGPoint(x: -u*0.95, y: u*4.1), zPos: 1),
         dot(u*0.45, dark, CGPoint(x: u*0.95, y: u*4.1), zPos: 1),
         dot(u*0.18, .white, CGPoint(x: -u*0.75, y: u*4.28), zPos: 2),
         dot(u*0.18, .white, CGPoint(x: u*1.15, y: u*4.28), zPos: 2),
         box(u*0.42, u*0.52, .white, CGPoint(x: -u*0.28, y: u*2.88), zPos: 2),
         box(u*0.42, u*0.52, .white, CGPoint(x: u*0.28, y: u*2.88), zPos: 2)
        ].forEach { r.addChild($0) }
        let grin = SKShapeNode(); let gp = CGMutablePath()
        gp.move(to: CGPoint(x: -u*1.3, y: u*3.0))
        gp.addQuadCurve(to: CGPoint(x: u*1.3, y: u*3.0), control: CGPoint(x: 0, y: u*2.25))
        grin.path = gp; grin.strokeColor = dkOrange; grin.lineWidth = u*0.28; grin.fillColor = .clear; grin.zPosition = 1
        r.addChild(grin)
    }

    // MARK: Stella — cyan power suit
    static func buildStella(_ r: SKNode, u: CGFloat) {
        let suit = UIColor(red: 0.06, green: 0.46, blue: 0.58, alpha: 1)
        let dark = UIColor(red: 0.05, green: 0.19, blue: 0.27, alpha: 1)
        let cyan = UIColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1)
        let ltCyan = UIColor(red: 0.49, green: 0.93, blue: 0.98, alpha: 1)
        let navy = UIColor(red: 0.07, green: 0.13, blue: 0.25, alpha: 1)
        [box(u*1.3, u*0.85, dark, CGPoint(x: -u*0.85, y: -u*3.2)),
         box(u*1.3, u*0.85, dark, CGPoint(x: u*0.85, y: -u*3.2)),
         box(u*0.95, u*2.2, suit, CGPoint(x: -u*0.85, y: -u*1.8)),
         box(u*0.95, u*2.2, suit, CGPoint(x: u*0.85, y: -u*1.8)),
         box(u*2.65, u*3.35, suit, CGPoint(x: 0, y: u*0.1)),
         box(u*2.1, u*2.4, dark, CGPoint(x: 0, y: u*0.2), zPos: 1),
         dot(u*0.52, cyan, .zero, zPos: 2),
         dot(u*0.28, .white, .zero, zPos: 3),
         box(u*0.95, u*0.7, dark, CGPoint(x: -u*1.85, y: u*1.6), zPos: 1),
         box(u*0.95, u*0.7, dark, CGPoint(x: u*1.85, y: u*1.6), zPos: 1),
         box(u*0.85, u*2.5, suit, CGPoint(x: -u*1.78, y: u*0.2)),
         box(u*0.95, u*2.5, dark, CGPoint(x: u*1.78, y: u*0.2)),
         box(u*1.25, u*0.85, dark, CGPoint(x: u*2.8, y: -u*0.55)),
         dot(u*0.42, cyan, CGPoint(x: u*3.5, y: -u*0.55), zPos: 1),
         box(u*2.85, u*3.05, navy, CGPoint(x: 0, y: u*3.8)),
         box(u*2.55, u*1.28, cyan, CGPoint(x: 0, y: u*3.88), zPos: 2),
         box(u*1.8, u*0.85, ltCyan, CGPoint(x: 0, y: u*3.92), zPos: 3)
        ].forEach { r.addChild($0) }
    }

    // MARK: Glitch — pink round wildcard
    static func buildGlitch(_ r: SKNode, u: CGFloat) {
        let pink = UIColor(red: 0.93, green: 0.29, blue: 0.60, alpha: 1)
        let dkPink = UIColor(red: 0.74, green: 0.10, blue: 0.37, alpha: 1)
        let purple = UIColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 1)
        let blush = UIColor(red: 0.98, green: 0.44, blue: 0.60, alpha: 0.65)
        let dark = UIColor(red: 0.06, green: 0.07, blue: 0.14, alpha: 1)
        let cyanFx = UIColor(red: 0.40, green: 0.91, blue: 0.98, alpha: 0.3)
        let magFx  = UIColor(red: 0.94, green: 0.67, blue: 0.98, alpha: 0.25)
        [box(u*4.2, u*5.0, cyanFx, CGPoint(x: u*0.28, y: u*0.8), zPos: -2),
         box(u*4.2, u*5.0, magFx, CGPoint(x: -u*0.28, y: u*0.8), zPos: -1),
         box(u*1.15, u*0.6, dkPink, CGPoint(x: -u*0.95, y: -u*2.8)),
         box(u*1.15, u*0.6, dkPink, CGPoint(x: u*0.95, y: -u*2.8)),
         box(u*0.72, u*1.8, pink, CGPoint(x: -u*2.5, y: u*0.15)),
         box(u*0.72, u*1.8, pink, CGPoint(x: u*2.5, y: u*0.15)),
         box(u*4.3, u*5.0, pink, CGPoint(x: 0, y: u*1.0)),
         dot(u*2.1, pink, CGPoint(x: 0, y: u*1.0)),
         dot(u*0.65, blush, CGPoint(x: -u*1.55, y: u*0.35), zPos: 2),
         dot(u*0.65, blush, CGPoint(x: u*1.55, y: u*0.35), zPos: 2),
         dot(u*1.5, .white, CGPoint(x: -u*0.95, y: u*1.55)),
         dot(u*1.5, .white, CGPoint(x: u*0.95, y: u*1.55)),
         dot(u*1.02, purple, CGPoint(x: -u*0.95, y: u*1.55), zPos: 1),
         dot(u*1.02, purple, CGPoint(x: u*0.95, y: u*1.55), zPos: 1),
         dot(u*0.6, dark, CGPoint(x: -u*0.95, y: u*1.55), zPos: 2),
         dot(u*0.6, dark, CGPoint(x: u*0.95, y: u*1.55), zPos: 2),
         dot(u*0.26, .white, CGPoint(x: -u*0.7, y: u*1.75), zPos: 3),
         dot(u*0.26, .white, CGPoint(x: u*1.2, y: u*1.75), zPos: 3),
         dot(u*0.22, UIColor(red: 0.99, green: 0.93, blue: 0.55, alpha: 1), CGPoint(x: u*1.75, y: u*2.7), zPos: 3),
         dot(u*0.16, UIColor(red: 0.99, green: 0.93, blue: 0.55, alpha: 1), CGPoint(x: -u*1.9, y: u*2.3), zPos: 3)
        ].forEach { r.addChild($0) }
        let smile = SKShapeNode(); let sp = CGMutablePath()
        sp.move(to: CGPoint(x: -u*0.95, y: u*0.28)); sp.addQuadCurve(to: CGPoint(x: u*0.95, y: u*0.28), control: CGPoint(x: 0, y: -u*0.4))
        smile.path = sp; smile.strokeColor = dkPink; smile.lineWidth = u*0.26; smile.fillColor = .clear; smile.zPosition = 2
        r.addChild(smile)
    }
}
