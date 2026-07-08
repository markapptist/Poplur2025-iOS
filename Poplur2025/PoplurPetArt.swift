import SpriteKit
import UIKit

// MARK: - Procedural pixel-art sprite builder for Poplur Pet
// Sprites are built from SKShapeNode geometry (box + dot helpers) at the
// requested scale. u = scale * 4 is the base "pixel" unit.

enum PoplurPetArt {

    // MARK: Shared helpers

    private static func box(_ w: CGFloat, _ h: CGFloat, _ c: UIColor, _ p: CGPoint,
                            r: CGFloat = 0, z: CGFloat = 0, stroke: UIColor? = nil) -> SKShapeNode {
        let n = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: r)
        n.fillColor   = c
        n.strokeColor = stroke ?? UIColor(red: 0.12, green: 0.06, blue: 0.01, alpha: 0.8)
        n.lineWidth   = max(0.4, w * 0.04)
        n.position    = p
        n.zPosition   = z
        return n
    }

    private static func dot(_ r: CGFloat, _ c: UIColor, _ p: CGPoint, z: CGFloat = 0) -> SKShapeNode {
        let n = SKShapeNode(circleOfRadius: r)
        n.fillColor   = c
        n.strokeColor = .clear
        n.position    = p
        n.zPosition   = z
        return n
    }

    // MARK: - Egg

    static func makeEgg(scale: CGFloat, cracked: Bool = false) -> SKNode {
        let n = SKNode()
        let u = scale * 4
        let cream = UIColor(red: 1.0, green: 0.96, blue: 0.82, alpha: 1)
        let dark  = UIColor(red: 0.18, green: 0.09, blue: 0.02, alpha: 1)
        let pink  = UIColor(red: 1.0,  green: 0.68, blue: 0.78, alpha: 0.55)

        let body = SKShapeNode(ellipseIn: CGRect(x: -u*3.5, y: -u*4.2, width: u*7, height: u*8.8))
        body.fillColor = cream; body.strokeColor = dark; body.lineWidth = u*0.32
        n.addChild(body)

        for sign: CGFloat in [-1, 1] {
            n.addChild(dot(u*0.65, dark, CGPoint(x: sign * u*1.1, y: u*0.6), z: 2))
            let b = SKShapeNode(ellipseIn: CGRect(x: -u*0.9, y: -u*0.45, width: u*1.8, height: u*0.9))
            b.fillColor = pink; b.strokeColor = .clear; b.zPosition = 2
            b.position = CGPoint(x: sign * u*1.8, y: -u*0.1)
            n.addChild(b)
        }

        if cracked {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -u*0.4, y: u*2.2))
            path.addLine(to: CGPoint(x: u*0.2, y: u*1.0))
            path.addLine(to: CGPoint(x: -u*0.1, y: 0))
            let crack = SKShapeNode(path: path)
            crack.strokeColor = dark.withAlphaComponent(0.6); crack.lineWidth = u*0.22
            crack.fillColor = .clear; crack.zPosition = 3
            n.addChild(crack)
        }
        return n
    }

    // MARK: - Baby

    static func makeBaby(scale: CGFloat, mood: PetState.Mood) -> SKNode {
        let n   = SKNode()
        let u   = scale * 4
        let cream = UIColor(red: 1.0,  green: 0.95, blue: 0.80, alpha: 1)
        let dark  = UIColor(red: 0.12, green: 0.07, blue: 0.02, alpha: 1)
        let pink  = UIColor(red: 1.0,  green: 0.68, blue: 0.78, alpha: 0.60)

        // Ears
        for sign: CGFloat in [-1, 1] {
            n.addChild(box(u*1.7, u*2.1, cream, CGPoint(x: sign * u*2.9, y: u*4.9), r: u*0.4, z: 0))
            let inner = SKShapeNode(ellipseIn: CGRect(x: -u*0.35, y: -u*0.4, width: u*0.7, height: u*1.0))
            inner.fillColor = pink; inner.strokeColor = .clear; inner.zPosition = 0.5
            inner.position = CGPoint(x: sign * u*2.9, y: u*5.0)
            n.addChild(inner)
        }

        // Body
        n.addChild(box(u*7.2, u*7.0, cream, .zero, r: u*3.0, z: 1))

        // Eyes
        let eyeY: CGFloat = u * (mood == .sleeping ? 1.0 : 0.8)
        addEyes(to: n, at: eyeY, spreadX: u*2.0, u: u, dark: dark, sleeping: mood == .sleeping)

        // Blush
        if mood != .sick && mood != .sleeping {
            for sign: CGFloat in [-1, 1] {
                let b = SKShapeNode(ellipseIn: CGRect(x: -u, y: -u*0.45, width: u*2, height: u*0.9))
                b.fillColor = pink; b.strokeColor = .clear; b.zPosition = 2
                b.position = CGPoint(x: sign * u*2.8, y: eyeY - u*1.0)
                n.addChild(b)
            }
        }

        addMouth(to: n, at: CGPoint(x: 0, y: -u*1.0), mood: mood, u: u, dark: dark)

        // Paws
        for sign: CGFloat in [-1, 1] {
            let paw = SKShapeNode(ellipseIn: CGRect(x: -u*1.1, y: -u*0.65, width: u*2.2, height: u*1.3))
            paw.fillColor = cream; paw.strokeColor = dark; paw.lineWidth = u*0.22
            paw.position = CGPoint(x: sign * u*1.8, y: -u*4.1); paw.zPosition = 1
            n.addChild(paw)
        }
        return n
    }

    // MARK: - Teen

    static func makeTeen(scale: CGFloat, mood: PetState.Mood) -> SKNode {
        let n     = SKNode()
        let u     = scale * 4
        let cream = UIColor(red: 1.0,  green: 0.95, blue: 0.80, alpha: 1)
        let dark  = UIColor(red: 0.12, green: 0.07, blue: 0.02, alpha: 1)
        let pink  = UIColor(red: 1.0,  green: 0.68, blue: 0.78, alpha: 0.60)

        for sign: CGFloat in [-1, 1] {
            n.addChild(box(u*1.6, u*2.8, cream, CGPoint(x: sign * u*3.2, y: u*6.0), r: u*0.4, z: 0))
            let inner = SKShapeNode(ellipseIn: CGRect(x: -u*0.32, y: -u*0.32, width: u*0.64, height: u*1.4))
            inner.fillColor = pink; inner.strokeColor = .clear; inner.zPosition = 0.5
            inner.position = CGPoint(x: sign * u*3.2, y: u*6.1)
            n.addChild(inner)
        }

        n.addChild(box(u*8.5, u*8.5, cream, .zero, r: u*3.2, z: 1))

        let eyeY: CGFloat = u * 1.5
        addEyes(to: n, at: eyeY, spreadX: u*2.2, u: u, dark: dark, sleeping: mood == .sleeping)

        if mood != .sick && mood != .sleeping {
            for sign: CGFloat in [-1, 1] {
                let b = SKShapeNode(ellipseIn: CGRect(x: -u*1.1, y: -u*0.5, width: u*2.2, height: u))
                b.fillColor = pink; b.strokeColor = .clear; b.zPosition = 2
                b.position = CGPoint(x: sign * u*3.0, y: eyeY - u*1.1)
                n.addChild(b)
            }
        }

        addMouth(to: n, at: CGPoint(x: 0, y: -u*1.1), mood: mood, u: u, dark: dark)

        for sign: CGFloat in [-1, 1] {
            n.addChild(box(u*1.8, u*2.0, cream, CGPoint(x: sign * u*2.0, y: -u*5.5), r: u*0.7, z: 1))
        }

        let tp = CGMutablePath()
        tp.move(to: CGPoint(x: u*3.5, y: -u*3.0))
        tp.addCurve(to: CGPoint(x: u*5.5, y: u*1.5),
                    control1: CGPoint(x: u*6.5, y: -u*2.5), control2: CGPoint(x: u*7.5, y: 0))
        let tail = SKShapeNode(path: tp)
        tail.strokeColor = cream; tail.lineWidth = u*0.85; tail.fillColor = .clear; tail.zPosition = 0
        n.addChild(tail)
        return n
    }

    // MARK: - Adult

    static func makeAdult(scale: CGFloat, mood: PetState.Mood) -> SKNode {
        let n     = SKNode()
        let u     = scale * 4
        let cream = UIColor(red: 1.0,  green: 0.95, blue: 0.80, alpha: 1)
        let dark  = UIColor(red: 0.12, green: 0.07, blue: 0.02, alpha: 1)
        let pink  = UIColor(red: 1.0,  green: 0.68, blue: 0.78, alpha: 0.60)

        for sign: CGFloat in [-1, 1] {
            n.addChild(box(u*1.8, u*3.5, cream, CGPoint(x: sign * u*3.5, y: u*7.5), r: u*0.4, z: 0))
            let inner = SKShapeNode(ellipseIn: CGRect(x: -u*0.4, y: -u*0.4, width: u*0.8, height: u*1.8))
            inner.fillColor = pink; inner.strokeColor = .clear; inner.zPosition = 0.5
            inner.position = CGPoint(x: sign * u*3.5, y: u*7.6)
            n.addChild(inner)
        }

        n.addChild(box(u*9, u*8.0, cream, CGPoint(x: 0, y: u*2.5), r: u*3.5, z: 1))
        n.addChild(box(u*7.5, u*6.5, cream, CGPoint(x: 0, y: -u*3.5), r: u*2.0, z: 1))

        let eyeY: CGFloat = u * 4.5
        addEyes(to: n, at: eyeY, spreadX: u*2.4, u: u, dark: dark, sleeping: mood == .sleeping)

        if mood != .sick && mood != .sleeping {
            for sign: CGFloat in [-1, 1] {
                let b = SKShapeNode(ellipseIn: CGRect(x: -u*1.3, y: -u*0.6, width: u*2.6, height: u*1.2))
                b.fillColor = pink; b.strokeColor = .clear; b.zPosition = 2
                b.position = CGPoint(x: sign * u*3.2, y: eyeY - u*1.2)
                n.addChild(b)
            }
        }

        addMouth(to: n, at: CGPoint(x: 0, y: u*1.5), mood: mood, u: u, dark: dark)

        for sign: CGFloat in [-1, 1] {
            n.addChild(box(u*2.2, u*2.5, cream, CGPoint(x: sign * u*2.3, y: -u*7.0), r: u, z: 1))
            n.addChild(box(u*1.5, u*2.5, cream, CGPoint(x: sign * u*4.8, y: -u*2.5), r: u*0.6, z: 0))
        }

        let tp = CGMutablePath()
        tp.move(to: CGPoint(x: u*3.2, y: -u*5.0))
        tp.addCurve(to: CGPoint(x: u*6.5, y: u*1.0),
                    control1: CGPoint(x: u*7.5, y: -u*4.0), control2: CGPoint(x: u*9.0, y: -u*1.0))
        let tail = SKShapeNode(path: tp)
        tail.strokeColor = cream; tail.lineWidth = u; tail.fillColor = .clear; tail.zPosition = 0
        n.addChild(tail)
        return n
    }

    // MARK: - Shared sub-builders

    private static func addEyes(to n: SKNode, at y: CGFloat, spreadX: CGFloat,
                                u: CGFloat, dark: UIColor, sleeping: Bool) {
        if sleeping {
            for sign: CGFloat in [-1, 1] {
                let e = SKShapeNode(rectOf: CGSize(width: u*1.8, height: u*0.5), cornerRadius: u*0.25)
                e.fillColor = dark; e.strokeColor = .clear
                e.position = CGPoint(x: sign * spreadX, y: y); e.zPosition = 2
                n.addChild(e)
            }
        } else {
            for sign: CGFloat in [-1, 1] {
                let white = SKShapeNode(circleOfRadius: u*1.15)
                white.fillColor = .white; white.strokeColor = dark; white.lineWidth = u*0.2
                white.position = CGPoint(x: sign * spreadX, y: y); white.zPosition = 2
                n.addChild(white)
                let pupil = dot(u*0.72, dark, CGPoint(x: sign * spreadX, y: y), z: 3)
                n.addChild(pupil)
                let shine = dot(u*0.28, .white, CGPoint(x: sign * spreadX + u*0.36, y: y + u*0.36), z: 4)
                n.addChild(shine)
            }
        }
    }

    private static func addMouth(to n: SKNode, at pos: CGPoint, mood: PetState.Mood, u: CGFloat, dark: UIColor) {
        switch mood {
        case .happy, .playing, .eating:
            let p = CGMutablePath()
            let w: CGFloat = mood == .eating ? u*0.6 : u*1.1
            p.move(to: CGPoint(x: -w, y: u*0.4))
            p.addCurve(to: CGPoint(x: w, y: u*0.4),
                       control1: CGPoint(x: -w, y: -u*0.9),
                       control2: CGPoint(x: w, y: -u*0.9))
            let s = SKShapeNode(path: p)
            s.strokeColor = dark; s.lineWidth = u*0.35; s.fillColor = .clear
            s.position = pos; s.zPosition = 2
            n.addChild(s)
            if mood == .eating {
                let inner = SKShapeNode(ellipseIn: CGRect(x: -u*0.5, y: -u*0.55, width: u, height: u*0.9))
                inner.fillColor = dark.withAlphaComponent(0.75); inner.strokeColor = .clear
                inner.position = pos; inner.zPosition = 3
                n.addChild(inner)
            }
        case .sad, .sick:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -u*0.8, y: -u*0.45))
            p.addCurve(to: CGPoint(x: u*0.8, y: -u*0.45),
                       control1: CGPoint(x: -u*0.8, y: u*0.5),
                       control2: CGPoint(x: u*0.8, y: u*0.5))
            let s = SKShapeNode(path: p)
            s.strokeColor = dark; s.lineWidth = u*0.32; s.fillColor = .clear
            s.position = pos; s.zPosition = 2
            n.addChild(s)
        case .sleeping:
            let m = SKShapeNode(rectOf: CGSize(width: u, height: u*0.3), cornerRadius: u*0.15)
            m.fillColor = dark; m.strokeColor = .clear
            m.position = pos; m.zPosition = 2
            n.addChild(m)
        default:
            let m = dot(u*0.34, dark, pos, z: 2)
            n.addChild(m)
        }
    }

    // MARK: - Poop

    static func makePoop(scale: CGFloat) -> SKNode {
        let n     = SKNode()
        let u     = scale * 3
        let brown = UIColor(red: 0.44, green: 0.25, blue: 0.07, alpha: 1)
        let dark  = UIColor(red: 0.20, green: 0.10, blue: 0.02, alpha: 1)
        for (i, dims) in [(0, (u*2.2, u*1.3)), (1, (u*2.8, u*1.5)), (2, (u*1.8, u*1.0))] {
            let o = SKShapeNode(ellipseIn: CGRect(x: -dims.0/2, y: -dims.1/2, width: dims.0, height: dims.1))
            o.fillColor = brown; o.strokeColor = dark; o.lineWidth = u*0.18
            o.position = CGPoint(x: 0, y: dims.1 * 0.45 * CGFloat(i)); o.zPosition = CGFloat(i)
            n.addChild(o)
        }
        for sign: CGFloat in [-1, 1] {
            n.addChild(dot(u*0.28, dark, CGPoint(x: sign * u*0.5, y: u*0.9), z: 3))
        }
        return n
    }

    // MARK: - Menu Icons (7 actions)

    static func makeMenuIcon(for action: PetMenuAction, scale: CGFloat) -> SKNode {
        let n = SKNode()
        let u = scale * 3
        let dark = UIColor(red: 0.08, green: 0.04, blue: 0.01, alpha: 0.88)

        switch action {
        case .meal:
            // Fork + knife silhouette
            for (sign, hasTines): (CGFloat, Bool) in [(-1, true), (1, false)] {
                n.addChild(box(u*0.4, u*2.6, dark, CGPoint(x: sign * u*0.65, y: 0), z: 1, stroke: .clear))
                if hasTines {
                    for i: CGFloat in [-1, 0, 1] {
                        n.addChild(box(u*0.18, u*0.9, dark, CGPoint(x: sign * u*0.65 + i * u*0.22, y: u*1.7), z: 1, stroke: .clear))
                    }
                } else {
                    // Knife blade widening
                    let blade = SKShapeNode(rectOf: CGSize(width: u*0.65, height: u*1.2), cornerRadius: u*0.1)
                    blade.fillColor = dark; blade.strokeColor = .clear
                    blade.position = CGPoint(x: sign * u*0.65, y: u*1.5); blade.zPosition = 1
                    n.addChild(blade)
                }
            }

        case .snack:
            let c = SKShapeNode(circleOfRadius: u*1.4)
            c.fillColor = UIColor(red: 0.86, green: 0.65, blue: 0.34, alpha: 1)
            c.strokeColor = dark; c.lineWidth = u*0.3; c.zPosition = 1
            n.addChild(c)
            for p in [CGPoint(x: -u*0.45, y: u*0.5), CGPoint(x: u*0.5, y: -u*0.3), CGPoint(x: -u*0.15, y: -u*0.75)] {
                n.addChild(dot(u*0.3, dark, p, z: 2))
            }

        case .play:
            let body = SKShapeNode(rectOf: CGSize(width: u*3.2, height: u*2.1), cornerRadius: u*0.8)
            body.fillColor = UIColor(red: 0.32, green: 0.15, blue: 0.58, alpha: 1)
            body.strokeColor = dark; body.lineWidth = u*0.25; body.zPosition = 1
            n.addChild(body)
            for _ in [CGRect(x: -u*0.3, y: -u*0.2, width: u*0.6, height: u*0.3),
                      CGRect(x: -u*1.1, y: -u*0.15, width: u*0.3, height: u*0.6)] {
                let r = SKShapeNode(rect: CGRect(x: -u*0.3, y: -u*0.2, width: u*0.6, height: u*0.3))
                r.fillColor = dark.withAlphaComponent(0.5); r.strokeColor = .clear; r.position = CGPoint(x: -u*0.9, y: 0); r.zPosition = 2
                n.addChild(r)
            }
            for p in [CGPoint(x: u*0.7, y: u*0.3), CGPoint(x: u*1.05, y: -u*0.1)] {
                n.addChild(dot(u*0.28, dark, p, z: 2))
            }

        case .bath:
            let body = SKShapeNode(ellipseIn: CGRect(x: -u*1.5, y: -u, width: u*3, height: u*2))
            body.fillColor = UIColor(red: 1.0, green: 0.88, blue: 0.18, alpha: 1)
            body.strokeColor = dark; body.lineWidth = u*0.28; body.zPosition = 1
            n.addChild(body)
            let head = SKShapeNode(circleOfRadius: u*0.95)
            head.fillColor = UIColor(red: 1.0, green: 0.88, blue: 0.18, alpha: 1)
            head.strokeColor = dark; head.lineWidth = u*0.25
            head.position = CGPoint(x: u*0.85, y: u*0.95); head.zPosition = 1
            n.addChild(head)
            let beak = SKShapeNode(rectOf: CGSize(width: u*0.85, height: u*0.42), cornerRadius: u*0.1)
            beak.fillColor = UIColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1); beak.strokeColor = dark; beak.lineWidth = u*0.15
            beak.position = CGPoint(x: u*1.65, y: u); beak.zPosition = 2
            n.addChild(beak)
            n.addChild(dot(u*0.22, dark, CGPoint(x: u*1.1, y: u*1.2), z: 2))

        case .medicine:
            let h1 = SKShapeNode(rectOf: CGSize(width: u, height: u*2.4), cornerRadius: u*0.55)
            h1.fillColor = UIColor(red: 0.72, green: 0.20, blue: 0.82, alpha: 1)
            h1.strokeColor = dark; h1.lineWidth = u*0.25; h1.position = CGPoint(x: -u*0.5, y: 0); h1.zPosition = 1
            n.addChild(h1)
            let h2 = SKShapeNode(rectOf: CGSize(width: u, height: u*2.4), cornerRadius: u*0.55)
            h2.fillColor = .white; h2.strokeColor = dark; h2.lineWidth = u*0.25
            h2.position = CGPoint(x: u*0.5, y: 0); h2.zPosition = 1
            n.addChild(h2)
            let divider = SKShapeNode(rectOf: CGSize(width: u*2.2, height: u*0.22))
            divider.fillColor = dark.withAlphaComponent(0.3); divider.strokeColor = .clear; divider.zPosition = 2
            n.addChild(divider)

        case .sleep:
            let moonPath = CGMutablePath()
            moonPath.addArc(center: .zero, radius: u*1.5, startAngle: .pi*0.3, endAngle: .pi*1.6, clockwise: false)
            moonPath.addArc(center: CGPoint(x: u*0.35, y: u*0.25), radius: u*1.1,
                            startAngle: .pi*1.6, endAngle: .pi*0.3, clockwise: true)
            let moon = SKShapeNode(path: moonPath)
            moon.fillColor = UIColor(red: 1.0, green: 0.92, blue: 0.30, alpha: 1)
            moon.strokeColor = dark; moon.lineWidth = u*0.28; moon.zPosition = 1
            n.addChild(moon)

        case .stats:
            let face = SKShapeNode(circleOfRadius: u*1.45)
            face.fillColor = UIColor(red: 1.0, green: 0.87, blue: 0.30, alpha: 1)
            face.strokeColor = dark; face.lineWidth = u*0.3; face.zPosition = 1
            n.addChild(face)
            for sign: CGFloat in [-1, 1] {
                n.addChild(dot(u*0.32, dark, CGPoint(x: sign * u*0.55, y: u*0.5), z: 2))
            }
            let sp = CGMutablePath()
            sp.move(to: CGPoint(x: -u*0.65, y: -u*0.18))
            sp.addCurve(to: CGPoint(x: u*0.65, y: -u*0.18),
                        control1: CGPoint(x: -u*0.65, y: -u*0.9),
                        control2: CGPoint(x: u*0.65, y: -u*0.9))
            let smile = SKShapeNode(path: sp)
            smile.strokeColor = dark; smile.lineWidth = u*0.3; smile.fillColor = .clear; smile.zPosition = 2
            n.addChild(smile)
        }
        return n
    }

    // MARK: - Effects

    static func makeSparkle(scale: CGFloat, color: UIColor = UIColor(red: 1, green: 0.92, blue: 0.22, alpha: 1)) -> SKNode {
        let n = SKNode()
        let u = scale * 2.5
        for a in stride(from: 0.0, to: .pi * 2, by: .pi / 4) {
            let arm = SKShapeNode(rectOf: CGSize(width: u * 0.22, height: u * 1.6))
            arm.fillColor = color; arm.strokeColor = .clear; arm.zRotation = CGFloat(a); arm.zPosition = 1
            n.addChild(arm)
        }
        let center = dot(u * 0.5, UIColor.white, .zero, z: 2)
        n.addChild(center)
        return n
    }

    static func makeHeart(scale: CGFloat) -> SKNode {
        let n = SKNode()
        let u = scale * 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -u))
        path.addCurve(to: CGPoint(x: -u*1.2, y: u*0.3),
                      control1: CGPoint(x: -u*0.8, y: -u*1.6), control2: CGPoint(x: -u*2.0, y: -u*0.3))
        path.addCurve(to: CGPoint(x: 0, y: u*1.5),
                      control1: CGPoint(x: -u*1.2, y: u*1.1), control2: CGPoint(x: -u*0.4, y: u*1.7))
        path.addCurve(to: CGPoint(x: u*1.2, y: u*0.3),
                      control1: CGPoint(x: u*0.4, y: u*1.7), control2: CGPoint(x: u*1.2, y: u*1.1))
        path.addCurve(to: CGPoint(x: 0, y: -u),
                      control1: CGPoint(x: u*2.0, y: -u*0.3), control2: CGPoint(x: u*0.8, y: -u*1.6))
        let heart = SKShapeNode(path: path)
        heart.fillColor = UIColor(red: 1, green: 0.32, blue: 0.52, alpha: 1)
        heart.strokeColor = UIColor(red: 0.7, green: 0.1, blue: 0.22, alpha: 1); heart.lineWidth = u * 0.2; heart.zPosition = 1
        n.addChild(heart)
        return n
    }

    static func makeZzzNode(scale: CGFloat) -> SKNode {
        let n = SKNode()
        let u = scale * 3
        let lbls: [(String, CGFloat)] = [("Z", u * 1.1), ("z", u * 0.82), ("z", u * 0.60)]
        for (i, (txt, size)) in lbls.enumerated() {
            let l = SKLabelNode(text: txt)
            l.fontName = "AvenirNext-Bold"
            l.fontSize = size
            l.fontColor = UIColor(red: 0.55, green: 0.55, blue: 1.0, alpha: 0.92)
            l.position = CGPoint(x: CGFloat(i) * u * 0.85, y: CGFloat(i) * u * 0.85)
            l.zPosition = 1
            n.addChild(l)
        }
        return n
    }

    // MARK: - Screen background (wavy stripes)

    static func makeBackground(size: CGSize, tint: UIColor) -> SKNode {
        let n = SKNode()
        let count = 8
        let h = size.height / CGFloat(count)
        let base = UIColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 1)
        for i in 0..<count {
            let stripe = SKShapeNode(rectOf: CGSize(width: size.width, height: h))
            stripe.fillColor = i.isMultiple(of: 2) ? base : tint.withAlphaComponent(0.55)
            stripe.strokeColor = .clear
            stripe.position = CGPoint(x: size.width / 2, y: h * (CGFloat(i) + 0.5))
            stripe.zPosition = -10
            n.addChild(stripe)
        }
        return n
    }

    // Convenience: build the right pet node for a given stage + mood
    static func makePet(stage: PetState.Stage, mood: PetState.Mood, scale: CGFloat) -> SKNode {
        switch stage {
        case .egg:   return makeEgg(scale: scale)
        case .baby:  return makeBaby(scale: scale, mood: mood)
        case .teen:  return makeTeen(scale: scale, mood: mood)
        case .adult: return makeAdult(scale: scale, mood: mood)
        }
    }
}
