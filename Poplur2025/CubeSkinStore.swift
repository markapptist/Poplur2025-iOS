import Foundation
import SwiftUI
import UIKit

public enum CubeSkin: String, CaseIterable, Identifiable, Codable {
    case standard = "default"
    case rainbow
    case sparklePink
    case gold
    case toy
    case chocolate
    case camo
    case rubber
    case ice

    public var id: String { rawValue }

    // Name of a base diffuse texture to apply to each face. These should be added to the asset catalog by the app.
    // If per-face variants exist later, you can extend this to provide an array of face-specific names.
    public var diffuseAssetName: String {
        switch self {
        case .standard: return "SkinRubber"
        case .rainbow: return "SkinRainbow"
        case .sparklePink: return "SkinSparklePink"
        case .gold: return "SkinGold"
        case .toy: return "SkinToy"
        case .chocolate: return "SkinChocolate"
        case .camo: return "SkinCamo"
        case .rubber: return "SkinRubber"
        case .ice: return "SkinIce"
        }
    }

    /// Asset name of the 4×3 cube-net image in the asset catalog (1448×1086, 362×362 tiles).
    /// Layout: top=(1,0), left=(0,1), center=(1,1), right=(2,1), far-right=(3,1), bottom=(1,2).
    public var cubemapAssetName: String {
        switch self {
        case .standard:    return "cubemaps 4"
        case .rainbow:     return "cubemaps"
        case .sparklePink: return "cubemaps 5"
        case .gold:        return "cubemaps 1"
        case .toy:         return "cubemaps 6"
        case .chocolate:   return "cubemaps 2"
        case .camo:        return "cubemaps 7"
        case .rubber:      return "cubemaps 4"
        case .ice:         return "cubemaps 3"
        }
    }

    /// Asset name for the hold-menu panel and tile background texture.
    public var holdMenuAssetName: String {
        switch self {
        case .standard:    return "holdmenu 3"
        case .ice:         return "holdmenu"
        case .camo:        return "holdmenu 1"
        case .chocolate:   return "holdmenu 2"
        case .rubber:      return "holdmenu 3"
        case .gold:        return "holdmenu 4"
        case .sparklePink: return "holdmenu 5"
        case .rainbow:     return "holdmenu 6"
        case .toy:         return "holdmenu 7"
        }
    }

    public var displayName: String {
        switch self {
        case .standard: return "Default"
        case .rainbow: return "Rainbow"
        case .sparklePink: return "Sparkle Pink"
        case .gold: return "Gold"
        case .toy: return "Toy"
        case .chocolate: return "Chocolate"
        case .camo: return "Camo"
        case .rubber: return "Rubber"
        case .ice: return "Ice"
        }
    }

    /// Asset name for the themed loading-screen logo image.
    public var logoAssetName: String {
        switch self {
        case .standard:    return "logo"
        case .rainbow:     return "logo_rainbow"
        case .sparklePink: return "logo_sparkle_pink"
        case .gold:        return "logo_gold"
        case .toy:         return "logo_toy"
        case .chocolate:   return "logo_chocolate"
        case .camo:        return "logo_camo"
        case .rubber:      return "logo_rubber"
        case .ice:         return "logo_ice"
        }
    }

    /// Primary theme color used for code-generated cube face textures.
    public var themeUIColor: UIColor {
        switch self {
        case .standard:    return UIColor(red: 0.20, green: 0.65, blue: 0.90, alpha: 1)
        case .rainbow:     return UIColor(red: 0.55, green: 0.10, blue: 0.95, alpha: 1)
        case .sparklePink: return UIColor(red: 1.00, green: 0.40, blue: 0.70, alpha: 1)
        case .gold:        return UIColor(red: 0.88, green: 0.68, blue: 0.10, alpha: 1)
        case .toy:         return UIColor(red: 0.95, green: 0.20, blue: 0.20, alpha: 1)
        case .chocolate:   return UIColor(red: 0.45, green: 0.25, blue: 0.08, alpha: 1)
        case .camo:        return UIColor(red: 0.30, green: 0.48, blue: 0.18, alpha: 1)
        case .rubber:      return UIColor(red: 0.20, green: 0.65, blue: 0.90, alpha: 1)
        case .ice:         return UIColor(red: 0.75, green: 0.92, blue: 1.00, alpha: 1)
        }
    }

    /// Border neon-glow color for the cube face emission mask.
    public var borderAccentColor: UIColor {
        switch self {
        case .standard:    return UIColor(red: 0.16, green: 0.88, blue: 1.00, alpha: 1)
        case .rainbow:     return UIColor(red: 0.60, green: 0.28, blue: 1.00, alpha: 1)
        case .sparklePink: return UIColor(red: 1.00, green: 0.35, blue: 0.72, alpha: 1)
        case .gold:        return UIColor(red: 0.95, green: 0.78, blue: 0.18, alpha: 1)
        case .toy:         return UIColor(red: 0.92, green: 0.14, blue: 0.14, alpha: 1)
        case .chocolate:   return UIColor(red: 0.72, green: 0.40, blue: 0.08, alpha: 1)
        case .camo:        return UIColor(red: 0.48, green: 0.56, blue: 0.22, alpha: 1)
        case .rubber:      return UIColor(red: 0.16, green: 0.88, blue: 1.00, alpha: 1)
        case .ice:         return UIColor(red: 0.55, green: 0.88, blue: 1.00, alpha: 1)
        }
    }

    /// Icon and label fill color in the cube face emission mask.
    public var iconFillColor: UIColor {
        switch self {
        case .standard: return .white
        case .rainbow, .sparklePink, .toy, .rubber: return .white
        case .gold:        return UIColor(red: 1.00, green: 0.95, blue: 0.60, alpha: 1)
        case .chocolate:   return UIColor(red: 0.92, green: 0.65, blue: 0.25, alpha: 1)
        case .camo:        return UIColor(red: 0.82, green: 0.84, blue: 0.56, alpha: 1)
        case .ice:         return UIColor(red: 0.82, green: 0.96, blue: 1.00, alpha: 1)
        }
    }

    public var alternateAppIconName: String? {
        switch self {
        case .standard:    return nil
        case .rainbow:     return "AppIconRainbow"
        case .sparklePink: return "AppIconSparklePink"
        case .gold:        return "AppIconGold"
        case .toy:         return "AppIconToy"
        case .chocolate:   return "AppIconChocolate"
        case .camo:        return "AppIconCamo"
        case .rubber:      return "AppIconRubber"
        case .ice:         return "AppIconIce"
        }
    }

    public var appIconPreviewAssetName: String {
        switch self {
        case .standard:    return "appicon_default"
        default:           return logoAssetName
        }
    }

}

// MARK: - Programmatic texture generation

extension CubeSkin {
    /// Returns a 300×300 programmatic background texture for this skin.
    /// Only `.rubber` varies per face — all other skins ignore `tab`.
    func makeTexture(tab: AppTab = .map) -> UIImage {
        let size = CGSize(width: 300, height: 300)
        let rect = CGRect(origin: .zero, size: size)
        let corner: CGFloat = 28
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let g = ctx.cgContext
            switch self {

            // ── GOLD ─────────────────────────────────────────────────────────
            case .gold:
                UIBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), cornerRadius: corner).addClip()
                let gradC: [CGColor] = [
                    UIColor(red: 0.48, green: 0.26, blue: 0.00, alpha: 1).cgColor,
                    UIColor(red: 1.00, green: 0.82, blue: 0.08, alpha: 1).cgColor,
                    UIColor(red: 0.86, green: 0.63, blue: 0.04, alpha: 1).cgColor,
                    UIColor(red: 0.36, green: 0.18, blue: 0.00, alpha: 1).cgColor,
                ]
                let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: gradC as CFArray, locations: [0.0, 0.35, 0.65, 1.0])!
                g.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 300, y: 300), options: [])
                let specC = [UIColor.white.withAlphaComponent(0.42).cgColor,
                             UIColor.white.withAlphaComponent(0.00).cgColor] as CFArray
                let specGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: specC, locations: [0, 1])!
                g.drawLinearGradient(specGrad, start: CGPoint(x: 18, y: 18), end: CGPoint(x: 185, y: 160), options: [])
                let innerRing = UIBezierPath(roundedRect: rect.insetBy(dx: 16, dy: 16), cornerRadius: corner - 6)
                innerRing.lineWidth = 3.5
                UIColor(red: 1.0, green: 0.92, blue: 0.32, alpha: 0.58).setStroke()
                innerRing.stroke()
                let outerRing = UIBezierPath(roundedRect: rect.insetBy(dx: 9, dy: 9), cornerRadius: corner - 2)
                outerRing.lineWidth = 5
                UIColor(red: 0.22, green: 0.10, blue: 0.00, alpha: 0.65).setStroke()
                outerRing.stroke()

            // ── TOY / CIRCUS ─────────────────────────────────────────────────
            case .toy:
                UIBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), cornerRadius: corner).addClip()
                UIColor(red: 1.0, green: 0.99, blue: 0.92, alpha: 1).setFill()
                UIBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), cornerRadius: corner).fill()
                let circusRed  = UIColor(red: 0.93, green: 0.12, blue: 0.12, alpha: 1)
                let circusBlue = UIColor(red: 0.09, green: 0.24, blue: 0.88, alpha: 1)
                let circusYellow = UIColor(red: 1.00, green: 0.80, blue: 0.00, alpha: 1)
                let borderPath = UIBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), cornerRadius: corner)
                borderPath.lineWidth = 22
                let segCount = 24
                let perimeter = 2 * (rect.insetBy(dx: 6, dy: 6).width + rect.insetBy(dx: 6, dy: 6).height)
                let segLen = perimeter / CGFloat(segCount)
                let palette: [UIColor] = [circusRed, circusBlue, circusYellow]
                for i in 0..<segCount {
                    palette[i % 3].setStroke()
                    borderPath.setLineDash([segLen - 2, CGFloat(segCount - 1) * segLen + 2], count: 2, phase: CGFloat(i) * segLen)
                    borderPath.stroke()
                }
                let dotSpots: [(CGFloat, CGFloat, UIColor)] = [
                    (38, 38, circusRed), (262, 38, circusBlue), (262, 262, circusYellow), (38, 262, circusRed),
                ]
                for (dx, dy, color) in dotSpots {
                    color.setFill()
                    UIBezierPath(ovalIn: CGRect(x: dx - 9, y: dy - 9, width: 18, height: 18)).fill()
                    UIColor.white.withAlphaComponent(0.55).setFill()
                    UIBezierPath(ovalIn: CGRect(x: dx - 4, y: dy - 6, width: 7, height: 6)).fill()
                }

            // ── RAINBOW ──────────────────────────────────────────────────────
            case .rainbow:
                UIBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), cornerRadius: corner).addClip()
                let rbC: [CGColor] = [
                    UIColor(red: 1.0, green: 0.00, blue: 0.00, alpha: 1).cgColor,
                    UIColor(red: 1.0, green: 0.50, blue: 0.00, alpha: 1).cgColor,
                    UIColor(red: 1.0, green: 1.00, blue: 0.00, alpha: 1).cgColor,
                    UIColor(red: 0.0, green: 0.88, blue: 0.00, alpha: 1).cgColor,
                    UIColor(red: 0.0, green: 0.70, blue: 1.00, alpha: 1).cgColor,
                    UIColor(red: 0.0, green: 0.00, blue: 1.00, alpha: 1).cgColor,
                    UIColor(red: 0.6, green: 0.00, blue: 1.00, alpha: 1).cgColor,
                ]
                let rbGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: rbC as CFArray, locations: [0.0, 0.17, 0.33, 0.50, 0.67, 0.83, 1.0])!
                g.drawLinearGradient(rbGrad, start: .zero, end: CGPoint(x: 300, y: 300), options: [])
                let rbGlossC = [UIColor.white.withAlphaComponent(0.30).cgColor,
                                UIColor.white.withAlphaComponent(0.00).cgColor] as CFArray
                let rbGloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: rbGlossC, locations: [0, 1])!
                g.drawLinearGradient(rbGloss, start: .zero, end: CGPoint(x: 0, y: 155), options: [])

            // ── RUBBER ───────────────────────────────────────────────────────
            case .standard, .rubber:
                let accent: UIColor = {
                    switch tab {
                    case .feed:     return UIColor(red: 0.61, green: 0.35, blue: 0.97, alpha: 1)
                    case .profile:  return UIColor(red: 1.00, green: 0.18, blue: 0.54, alpha: 1)
                    case .map:      return UIColor(red: 0.24, green: 0.50, blue: 1.00, alpha: 1)
                    case .record:   return UIColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1)
                    case .settings: return UIColor(red: 0.30, green: 1.00, blue: 0.36, alpha: 1)
                    }
                }()
                UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1).setFill()
                UIBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), cornerRadius: corner).fill()
                g.saveGState()
                UIBezierPath(roundedRect: rect.insetBy(dx: 20, dy: 20), cornerRadius: corner - 10).addClip()
                let dotR: CGFloat = 5.0, step: CGFloat = 18.0
                var bx: CGFloat = 24
                while bx < 280 {
                    var by: CGFloat = 24
                    while by < 280 {
                        UIColor(red: 0.22, green: 0.22, blue: 0.22, alpha: 1).setFill()
                        UIBezierPath(ovalIn: CGRect(x: bx - dotR, y: by - dotR, width: dotR * 2, height: dotR * 2)).fill()
                        UIColor(red: 0.36, green: 0.36, blue: 0.36, alpha: 0.9).setFill()
                        UIBezierPath(ovalIn: CGRect(x: bx - dotR * 0.5, y: by - dotR * 0.85, width: dotR, height: dotR * 0.65)).fill()
                        by += step
                    }
                    bx += step
                }
                g.restoreGState()
                let accentRing = UIBezierPath(roundedRect: rect.insetBy(dx: 9, dy: 9), cornerRadius: corner - 2)
                accentRing.lineWidth = 6
                accent.setStroke()
                accentRing.stroke()
                let glowRing = UIBezierPath(roundedRect: rect.insetBy(dx: 16, dy: 16), cornerRadius: corner - 6)
                glowRing.lineWidth = 8
                accent.withAlphaComponent(0.20).setStroke()
                glowRing.stroke()

            // ── ICE ──────────────────────────────────────────────────────────
            case .ice:
                UIBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), cornerRadius: corner).addClip()
                let iceC: [CGColor] = [
                    UIColor(red: 0.03, green: 0.07, blue: 0.22, alpha: 1).cgColor,
                    UIColor(red: 0.06, green: 0.14, blue: 0.36, alpha: 1).cgColor,
                    UIColor(red: 0.04, green: 0.10, blue: 0.26, alpha: 1).cgColor,
                ]
                let iceGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: iceC as CFArray, locations: [0.0, 0.5, 1.0])!
                g.drawLinearGradient(iceGrad, start: .zero, end: CGPoint(x: 300, y: 300), options: [])
                UIColor(red: 0.72, green: 0.92, blue: 1.0, alpha: 0.42).setStroke()
                g.setLineWidth(1.1)
                func crack(_ pts: [CGPoint]) {
                    let p = UIBezierPath(); p.move(to: pts[0])
                    pts.dropFirst().forEach { p.addLine(to: $0) }; p.stroke()
                }
                crack([CGPoint(x: 42, y: 0),  CGPoint(x: 112, y: 88),  CGPoint(x: 78,  y: 162), CGPoint(x: 148, y: 218)])
                crack([CGPoint(x: 112, y: 88), CGPoint(x: 172, y: 52)])
                crack([CGPoint(x: 300, y: 238),CGPoint(x: 218, y: 188), CGPoint(x: 258, y: 128), CGPoint(x: 178, y: 96)])
                crack([CGPoint(x: 218, y: 188),CGPoint(x: 186, y: 228), CGPoint(x: 196, y: 278)])
                crack([CGPoint(x: 238, y: 8),  CGPoint(x: 198, y: 66),  CGPoint(x: 228, y: 102)])
                let iceGlowC = [UIColor(red: 0.22, green: 0.66, blue: 1.0, alpha: 0.16).cgColor,
                                UIColor(red: 0.10, green: 0.32, blue: 0.80, alpha: 0.00).cgColor] as CFArray
                let iceGlow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: iceGlowC, locations: [0, 1])!
                g.drawRadialGradient(iceGlow, startCenter: CGPoint(x: 150, y: 150), startRadius: 0,
                                     endCenter: CGPoint(x: 150, y: 150), endRadius: 160, options: [])
                let iceBorder = UIBezierPath(roundedRect: rect.insetBy(dx: 11, dy: 11), cornerRadius: corner - 3)
                iceBorder.lineWidth = 3
                UIColor(red: 0.48, green: 0.88, blue: 1.0, alpha: 0.52).setStroke()
                iceBorder.stroke()

            // ── SPARKLE PINK ─────────────────────────────────────────────────
            case .sparklePink:
                UIBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), cornerRadius: corner).addClip()
                let pkC: [CGColor] = [
                    UIColor(red: 1.0, green: 0.44, blue: 0.72, alpha: 1).cgColor,
                    UIColor(red: 0.88, green: 0.08, blue: 0.48, alpha: 1).cgColor,
                    UIColor(red: 1.0, green: 0.62, blue: 0.82, alpha: 1).cgColor,
                ]
                let pkGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: pkC as CFArray, locations: [0.0, 0.5, 1.0])!
                g.drawLinearGradient(pkGrad, start: .zero, end: CGPoint(x: 300, y: 300), options: [])
                let sparkles: [(CGFloat, CGFloat)] = [
                    (50,50),(250,42),(78,242),(258,258),(150,78),(200,202),
                    (40,152),(268,152),(128,262),(212,60),(90,120),(210,130),
                    (170,220),(60,210),(240,190),
                ]
                for (sx, sy) in sparkles {
                    UIColor.white.withAlphaComponent(0.18).setFill()
                    UIBezierPath(ovalIn: CGRect(x: sx - 9, y: sy - 9, width: 18, height: 18)).fill()
                    UIColor.white.withAlphaComponent(0.90).setFill()
                    UIBezierPath(ovalIn: CGRect(x: sx - 3.5, y: sy - 3.5, width: 7, height: 7)).fill()
                }
                let pkGlossC = [UIColor.white.withAlphaComponent(0.26).cgColor,
                                UIColor.white.withAlphaComponent(0.00).cgColor] as CFArray
                let pkGloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: pkGlossC, locations: [0, 1])!
                g.drawRadialGradient(pkGloss, startCenter: CGPoint(x: 75, y: 75), startRadius: 0,
                                     endCenter: CGPoint(x: 75, y: 75), endRadius: 130, options: [])

            // ── CHOCOLATE ────────────────────────────────────────────────────
            case .chocolate:
                UIBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), cornerRadius: corner).addClip()
                let chkC: [CGColor] = [
                    UIColor(red: 0.30, green: 0.16, blue: 0.04, alpha: 1).cgColor,
                    UIColor(red: 0.50, green: 0.28, blue: 0.08, alpha: 1).cgColor,
                    UIColor(red: 0.24, green: 0.12, blue: 0.02, alpha: 1).cgColor,
                ]
                let chkGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: chkC as CFArray, locations: [0.0, 0.45, 1.0])!
                g.drawLinearGradient(chkGrad, start: .zero, end: CGPoint(x: 300, y: 300), options: [])
                UIColor(red: 0.18, green: 0.09, blue: 0.01, alpha: 0.55).setStroke()
                g.setLineWidth(2.0)
                for xi: CGFloat in [75, 150, 225] {
                    let p = UIBezierPath(); p.move(to: CGPoint(x: xi, y: 14)); p.addLine(to: CGPoint(x: xi, y: 286)); p.stroke()
                }
                for yi: CGFloat in [75, 150, 225] {
                    let p = UIBezierPath(); p.move(to: CGPoint(x: 14, y: yi)); p.addLine(to: CGPoint(x: 286, y: yi)); p.stroke()
                }
                let chkGlossC = [UIColor.white.withAlphaComponent(0.13).cgColor,
                                  UIColor.white.withAlphaComponent(0.00).cgColor] as CFArray
                let chkGloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: chkGlossC, locations: [0, 1])!
                g.drawRadialGradient(chkGloss, startCenter: CGPoint(x: 75, y: 60), startRadius: 0,
                                     endCenter: CGPoint(x: 75, y: 60), endRadius: 148, options: [])

            // ── CAMO ─────────────────────────────────────────────────────────
            case .camo:
                UIColor(red: 0.30, green: 0.38, blue: 0.19, alpha: 1).setFill()
                UIBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), cornerRadius: corner).fill()
                let blobs: [(CGFloat, CGFloat, CGFloat, CGFloat, UIColor)] = [
                    (18,  18,  118,  78, UIColor(red: 0.17, green: 0.22, blue: 0.09, alpha: 1)),
                    (102, 58,  128,  98, UIColor(red: 0.44, green: 0.41, blue: 0.20, alpha: 1)),
                    (178, 14,   98,  88, UIColor(red: 0.11, green: 0.15, blue: 0.06, alpha: 1)),
                    (38,  128, 108,  88, UIColor(red: 0.38, green: 0.34, blue: 0.17, alpha: 1)),
                    (128, 148, 118,  78, UIColor(red: 0.17, green: 0.22, blue: 0.09, alpha: 1)),
                    (238,  98,  68, 118, UIColor(red: 0.44, green: 0.41, blue: 0.20, alpha: 1)),
                    (28,  218, 128,  68, UIColor(red: 0.11, green: 0.15, blue: 0.06, alpha: 1)),
                    (178, 198,  98,  88, UIColor(red: 0.35, green: 0.31, blue: 0.14, alpha: 1)),
                ]
                for (bx, by, bw, bh, bc) in blobs {
                    bc.setFill()
                    UIBezierPath(ovalIn: CGRect(x: bx, y: by, width: bw, height: bh)).fill()
                }
            }
        }
    }
}

/// Notification posted when the selected cube skin changes.
public extension Notification.Name {
    static let CubeSkinDidChange = Notification.Name("CubeSkinDidChange")
}

/// Shared store for the selected cube skin. Persists via UserDefaults and broadcasts changes.
public final class CubeSkinStore: ObservableObject {
    public static let shared = CubeSkinStore()
    private let defaultsKey = "CubeSkin.rawValue"

    @Published public private(set) var current: CubeSkin

    private init() {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey), let skin = CubeSkin(rawValue: raw) {
            current = skin
        } else {
            current = .standard
        }
        syncAppIcon()
    }

    public func apply(_ skin: CubeSkin) {
        guard current != skin else { return }
        current = skin
        UserDefaults.standard.set(skin.rawValue, forKey: defaultsKey)
        syncAppIcon()
        NotificationCenter.default.post(name: .CubeSkinDidChange, object: skin)
    }

    public func syncAppIcon() {
        let iconName = current.alternateAppIconName
        DispatchQueue.main.async {
            guard UIApplication.shared.supportsAlternateIcons else { return }
            guard UIApplication.shared.alternateIconName != iconName else { return }
            UIApplication.shared.setAlternateIconName(iconName) { error in
                if let error {
                    print("App icon update failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct CubeSkinAppTheme {
    let background: Color
    let backgroundMid: Color
    let backgroundDeep: Color
    let surface: Color
    let surfaceStrong: Color
    let controlFill: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let accent2: Color
    let border: Color
    let badgeFill: Color
    let badgeText: Color
    let shadow: Color
    let textureOpacity: Double
    let prefersLightContent: Bool
}

extension CubeSkin {
    var appTheme: CubeSkinAppTheme {
        switch self {
        case .standard, .rainbow:
            return CubeSkinAppTheme(
                background: Color(red: 0.02, green: 0.03, blue: 0.12),
                backgroundMid: Color(red: 0.02, green: 0.18, blue: 0.16),
                backgroundDeep: Color(red: 0.18, green: 0.02, blue: 0.28),
                surface: Color(red: 0.02, green: 0.04, blue: 0.18).opacity(0.82),
                surfaceStrong: Color(red: 0.03, green: 0.02, blue: 0.20).opacity(0.94),
                controlFill: Color.white.opacity(0.12),
                primaryText: .white,
                secondaryText: Color.white.opacity(0.68),
                accent: Color(red: 0.20, green: 0.98, blue: 1.00),
                accent2: Color(red: 1.00, green: 0.20, blue: 0.92),
                border: Color.white.opacity(0.34),
                badgeFill: Color.black.opacity(0.58),
                badgeText: .white,
                shadow: Color(red: 0.80, green: 0.12, blue: 1.00).opacity(0.40),
                textureOpacity: 0.26,
                prefersLightContent: true
            )
        case .sparklePink:
            return CubeSkinAppTheme(
                background: Color(red: 0.14, green: 0.00, blue: 0.08),
                backgroundMid: Color(red: 0.32, green: 0.02, blue: 0.22),
                backgroundDeep: Color(red: 0.03, green: 0.00, blue: 0.05),
                surface: Color(red: 0.18, green: 0.01, blue: 0.12).opacity(0.84),
                surfaceStrong: Color(red: 0.28, green: 0.02, blue: 0.18).opacity(0.94),
                controlFill: Color.white.opacity(0.14),
                primaryText: .white,
                secondaryText: Color.white.opacity(0.68),
                accent: Color(red: 1.00, green: 0.24, blue: 0.78),
                accent2: Color(red: 1.00, green: 0.72, blue: 0.90),
                border: Color(red: 1.00, green: 0.32, blue: 0.82).opacity(0.62),
                badgeFill: Color.black.opacity(0.62),
                badgeText: .white,
                shadow: Color(red: 1.00, green: 0.12, blue: 0.74).opacity(0.42),
                textureOpacity: 0.36,
                prefersLightContent: true
            )
        case .gold:
            return CubeSkinAppTheme(
                background: Color(red: 0.08, green: 0.06, blue: 0.01),
                backgroundMid: Color(red: 0.20, green: 0.14, blue: 0.02),
                backgroundDeep: Color(red: 0.02, green: 0.02, blue: 0.00),
                surface: Color(red: 0.14, green: 0.11, blue: 0.03).opacity(0.88),
                surfaceStrong: Color(red: 0.18, green: 0.13, blue: 0.03).opacity(0.95),
                controlFill: Color(red: 0.95, green: 0.78, blue: 0.18).opacity(0.16),
                primaryText: Color(red: 1.00, green: 0.94, blue: 0.62),
                secondaryText: Color(red: 0.94, green: 0.86, blue: 0.62).opacity(0.76),
                accent: Color(red: 0.98, green: 0.78, blue: 0.18),
                accent2: Color(red: 1.00, green: 0.94, blue: 0.52),
                border: Color(red: 0.98, green: 0.82, blue: 0.28).opacity(0.58),
                badgeFill: Color.black.opacity(0.58),
                badgeText: Color(red: 1.00, green: 0.94, blue: 0.62),
                shadow: Color(red: 1.00, green: 0.72, blue: 0.12).opacity(0.32),
                textureOpacity: 0.28,
                prefersLightContent: true
            )
        case .toy:
            return CubeSkinAppTheme(
                background: Color(red: 1.00, green: 0.96, blue: 0.86),
                backgroundMid: Color(red: 1.00, green: 0.98, blue: 0.92),
                backgroundDeep: Color(red: 0.94, green: 0.86, blue: 0.70),
                surface: Color.white.opacity(0.72),
                surfaceStrong: Color.white.opacity(0.88),
                controlFill: Color.white.opacity(0.92),
                primaryText: Color(red: 0.10, green: 0.12, blue: 0.16),
                secondaryText: Color(red: 0.22, green: 0.26, blue: 0.32).opacity(0.74),
                accent: Color(red: 0.92, green: 0.10, blue: 0.10),
                accent2: Color(red: 0.02, green: 0.23, blue: 0.72),
                border: Color(red: 1.00, green: 0.72, blue: 0.02).opacity(0.66),
                badgeFill: Color(red: 0.10, green: 0.12, blue: 0.16).opacity(0.68),
                badgeText: .white,
                shadow: Color.black.opacity(0.12),
                textureOpacity: 0.18,
                prefersLightContent: false
            )
        case .chocolate:
            return CubeSkinAppTheme(
                background: Color(red: 0.18, green: 0.08, blue: 0.02),
                backgroundMid: Color(red: 0.34, green: 0.16, blue: 0.04),
                backgroundDeep: Color(red: 0.08, green: 0.03, blue: 0.01),
                surface: Color(red: 0.22, green: 0.10, blue: 0.03).opacity(0.88),
                surfaceStrong: Color(red: 0.28, green: 0.12, blue: 0.03).opacity(0.96),
                controlFill: Color(red: 0.72, green: 0.40, blue: 0.10).opacity(0.20),
                primaryText: Color(red: 1.00, green: 0.92, blue: 0.82),
                secondaryText: Color(red: 0.95, green: 0.78, blue: 0.62).opacity(0.78),
                accent: Color(red: 0.95, green: 0.56, blue: 0.20),
                accent2: Color(red: 1.00, green: 0.80, blue: 0.54),
                border: Color(red: 0.86, green: 0.48, blue: 0.16).opacity(0.58),
                badgeFill: Color.black.opacity(0.56),
                badgeText: .white,
                shadow: Color(red: 0.95, green: 0.40, blue: 0.10).opacity(0.24),
                textureOpacity: 0.26,
                prefersLightContent: true
            )
        case .camo:
            return CubeSkinAppTheme(
                background: Color(red: 0.06, green: 0.09, blue: 0.04),
                backgroundMid: Color(red: 0.16, green: 0.19, blue: 0.08),
                backgroundDeep: Color(red: 0.02, green: 0.04, blue: 0.02),
                surface: Color(red: 0.09, green: 0.12, blue: 0.05).opacity(0.88),
                surfaceStrong: Color(red: 0.12, green: 0.15, blue: 0.06).opacity(0.96),
                controlFill: Color(red: 0.48, green: 0.56, blue: 0.22).opacity(0.16),
                primaryText: Color(red: 0.94, green: 0.90, blue: 0.66),
                secondaryText: Color(red: 0.84, green: 0.82, blue: 0.62).opacity(0.78),
                accent: Color(red: 0.86, green: 0.78, blue: 0.34),
                accent2: Color(red: 0.48, green: 0.62, blue: 0.25),
                border: Color(red: 0.80, green: 0.76, blue: 0.42).opacity(0.52),
                badgeFill: Color.black.opacity(0.55),
                badgeText: Color(red: 0.94, green: 0.90, blue: 0.66),
                shadow: Color(red: 0.70, green: 0.70, blue: 0.22).opacity(0.20),
                textureOpacity: 0.34,
                prefersLightContent: true
            )
        case .rubber:
            return CubeSkinAppTheme(
                background: Color(red: 0.02, green: 0.02, blue: 0.025),
                backgroundMid: Color(red: 0.08, green: 0.08, blue: 0.09),
                backgroundDeep: Color(red: 0.00, green: 0.00, blue: 0.00),
                surface: Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.88),
                surfaceStrong: Color(red: 0.02, green: 0.02, blue: 0.03).opacity(0.96),
                controlFill: Color.white.opacity(0.11),
                primaryText: Color.white.opacity(0.92),
                secondaryText: Color.white.opacity(0.64),
                accent: Color(red: 0.76, green: 0.20, blue: 1.00),
                accent2: Color(red: 0.16, green: 0.70, blue: 1.00),
                border: Color(red: 0.76, green: 0.20, blue: 1.00).opacity(0.54),
                badgeFill: Color.black.opacity(0.64),
                badgeText: .white,
                shadow: Color(red: 0.72, green: 0.18, blue: 1.00).opacity(0.36),
                textureOpacity: 0.32,
                prefersLightContent: true
            )
        case .ice:
            return CubeSkinAppTheme(
                background: Color(red: 0.00, green: 0.07, blue: 0.16),
                backgroundMid: Color(red: 0.02, green: 0.20, blue: 0.38),
                backgroundDeep: Color(red: 0.00, green: 0.02, blue: 0.08),
                surface: Color(red: 0.02, green: 0.13, blue: 0.26).opacity(0.84),
                surfaceStrong: Color(red: 0.03, green: 0.15, blue: 0.30).opacity(0.94),
                controlFill: Color(red: 0.62, green: 0.90, blue: 1.00).opacity(0.15),
                primaryText: Color(red: 0.82, green: 0.96, blue: 1.00),
                secondaryText: Color(red: 0.70, green: 0.88, blue: 1.00).opacity(0.76),
                accent: Color(red: 0.42, green: 0.86, blue: 1.00),
                accent2: Color(red: 0.82, green: 0.96, blue: 1.00),
                border: Color(red: 0.62, green: 0.90, blue: 1.00).opacity(0.62),
                badgeFill: Color.black.opacity(0.52),
                badgeText: Color(red: 0.82, green: 0.96, blue: 1.00),
                shadow: Color(red: 0.38, green: 0.78, blue: 1.00).opacity(0.36),
                textureOpacity: 0.40,
                prefersLightContent: true
            )
        }
    }
}

struct CubeSkinThemedBackground: View {
    let skin: CubeSkin

    var body: some View {
        let theme = skin.appTheme
        ZStack {
            LinearGradient(
                colors: [theme.background, theme.backgroundMid, theme.backgroundDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(uiImage: skin.makeTexture(tab: .profile))
                .resizable()
                .scaledToFill()
                .opacity(theme.textureOpacity)
                .saturation(skin == .toy ? 0.72 : 1.12)
                .contrast(skin == .toy ? 0.88 : 1.12)
            if skin == .rainbow {
                LinearGradient(
                    colors: [
                        Color.red.opacity(0.26),
                        Color.green.opacity(0.18),
                        Color.blue.opacity(0.22),
                        Color.pink.opacity(0.26)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct CubeSkinTileBackground: View {
    let skin: CubeSkin
    var tab: AppTab = .profile
    var cornerRadius: CGFloat = 18

    var body: some View {
        let theme = skin.appTheme
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Image(uiImage: skin.makeTexture(tab: tab))
            .resizable()
            .scaledToFill()
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(theme.prefersLightContent ? 0.10 : 0.22),
                        Color.clear,
                        theme.backgroundDeep.opacity(theme.prefersLightContent ? 0.30 : 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(shape)
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [theme.border, theme.accent.opacity(0.82), theme.accent2.opacity(0.48)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
            )
            .shadow(color: theme.shadow, radius: 10, x: 0, y: 6)
    }
}
