import SwiftUI
import SpriteKit

// MARK: - PoplurTheme Enum

/// Maps to the existing CubeSkin system while providing map-specific theming data.
public enum PoplurTheme: String, CaseIterable, Identifiable {
    case `default`   // standard
    case dark        // rubber
    case ice
    case gold
    case glitter     // sparklePink
    case rainbow
    case chocolate
    case carnival    // toy
    case camo
    case toyBox      // toy variant

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .default:    return "Default"
        case .dark:       return "Dark"
        case .ice:        return "Ice"
        case .gold:       return "Gold"
        case .glitter:    return "Glitter"
        case .rainbow:    return "Rainbow"
        case .chocolate:  return "Chocolate"
        case .carnival:   return "Carnival"
        case .camo:       return "Camo"
        case .toyBox:     return "Toy Box"
        }
    }

    public var cubeSkin: CubeSkin {
        switch self {
        case .default:   return .standard
        case .dark:      return .rubber
        case .ice:       return .ice
        case .gold:      return .gold
        case .glitter:   return .sparklePink
        case .rainbow:   return .rainbow
        case .chocolate: return .chocolate
        case .carnival:  return .toy
        case .camo:      return .camo
        case .toyBox:    return .toy
        }
    }
}

public extension CubeSkin {
    var poplurTheme: PoplurTheme {
        switch self {
        case .standard:    return .default
        case .rubber:      return .dark
        case .ice:         return .ice
        case .gold:        return .gold
        case .sparklePink, .clay: return .glitter
        case .rainbow:     return .rainbow
        case .chocolate:   return .chocolate
        case .toy:         return .carnival
        case .camo:        return .camo
        }
    }
}

// MARK: - Map Glow Config

public struct PoplurMapGlowConfig {
    let primary: Color
    let secondary: Color
    let radius: CGFloat
    let opacity: Double
    let animates: Bool
}

// MARK: - Particle Config

public enum PoplurMapParticleKind {
    case none
    case snow
    case sparkles
    case stars
    case confetti
    case rain
    case dust
    case floatingOrbs
}

public struct PoplurMapParticleConfig {
    let kind: PoplurMapParticleKind
    let birthRate: CGFloat
    let lifetime: CGFloat
    let color: UIColor
    let color2: UIColor
}

// MARK: - Radius Style

public enum PoplurRadiusStyle {
    case pulse
    case ripple
    case glow
    case softBlur
    case sparkle
}

// MARK: - Theme Data

public struct PoplurMapThemeData {
    let glow: PoplurMapGlowConfig
    let particles: PoplurMapParticleConfig
    let radiusStyle: PoplurRadiusStyle
    let radiusColors: [Color]
    let glassBlur: CGFloat
    let glassTint: Color
    let glassOpacity: Double
    let controlAccent: Color
    let controlBackground: Color
    let markerGlow: Color
    let bottomSheetTint: Color
    let searchTint: Color
    let shadowColor: Color
    let animationStyle: PoplurMapAnimationStyle
}

public enum PoplurMapAnimationStyle {
    case energetic  // fast, bouncy
    case smooth     // slow, eased
    case sharp      // instant with snap
    case dreamy     // slow fade
}

// MARK: - Theme Data Factory

public extension PoplurTheme {
    var mapThemeData: PoplurMapThemeData {
        switch self {
        case .default:
            return PoplurMapThemeData(
                glow: PoplurMapGlowConfig(primary: Color(red: 0.20, green: 0.98, blue: 1.00), secondary: Color(red: 1.00, green: 0.20, blue: 0.92), radius: 14, opacity: 0.7, animates: true),
                particles: PoplurMapParticleConfig(kind: .floatingOrbs, birthRate: 1.2, lifetime: 6, color: UIColor(red: 0.20, green: 0.98, blue: 1.00, alpha: 0.5), color2: UIColor(red: 1.00, green: 0.20, blue: 0.92, alpha: 0.4)),
                radiusStyle: .pulse,
                radiusColors: [Color(red: 0.20, green: 0.98, blue: 1.00), Color(red: 1.00, green: 0.20, blue: 0.92)],
                glassBlur: 18,
                glassTint: Color(red: 0.02, green: 0.04, blue: 0.18),
                glassOpacity: 0.62,
                controlAccent: Color(red: 0.20, green: 0.98, blue: 1.00),
                controlBackground: Color(red: 0.02, green: 0.04, blue: 0.18).opacity(0.88),
                markerGlow: Color(red: 0.20, green: 0.98, blue: 1.00),
                bottomSheetTint: Color(red: 0.02, green: 0.04, blue: 0.18),
                searchTint: Color(red: 0.20, green: 0.98, blue: 1.00),
                shadowColor: Color(red: 0.80, green: 0.12, blue: 1.00).opacity(0.4),
                animationStyle: .energetic
            )
        case .dark:
            return PoplurMapThemeData(
                glow: PoplurMapGlowConfig(primary: Color(red: 1.00, green: 0.24, blue: 0.78), secondary: Color(red: 0.92, green: 0.12, blue: 0.42), radius: 12, opacity: 0.65, animates: true),
                particles: PoplurMapParticleConfig(kind: .floatingOrbs, birthRate: 0.8, lifetime: 8, color: UIColor(red: 1.00, green: 0.20, blue: 0.72, alpha: 0.4), color2: UIColor(red: 0.40, green: 0.02, blue: 0.80, alpha: 0.35)),
                radiusStyle: .glow,
                radiusColors: [Color(red: 1.00, green: 0.24, blue: 0.78), Color(red: 0.40, green: 0.02, blue: 0.80)],
                glassBlur: 22,
                glassTint: Color(red: 0.06, green: 0.00, blue: 0.04),
                glassOpacity: 0.78,
                controlAccent: Color(red: 1.00, green: 0.24, blue: 0.78),
                controlBackground: Color(red: 0.08, green: 0.00, blue: 0.05).opacity(0.90),
                markerGlow: Color(red: 1.00, green: 0.24, blue: 0.78),
                bottomSheetTint: Color(red: 0.10, green: 0.00, blue: 0.06),
                searchTint: Color(red: 1.00, green: 0.24, blue: 0.78),
                shadowColor: Color(red: 1.00, green: 0.10, blue: 0.50).opacity(0.5),
                animationStyle: .smooth
            )
        case .ice:
            return PoplurMapThemeData(
                glow: PoplurMapGlowConfig(primary: Color(red: 0.56, green: 0.90, blue: 1.00), secondary: Color.white, radius: 18, opacity: 0.8, animates: true),
                particles: PoplurMapParticleConfig(kind: .snow, birthRate: 2.5, lifetime: 8, color: UIColor(white: 1.0, alpha: 0.8), color2: UIColor(red: 0.56, green: 0.90, blue: 1.00, alpha: 0.6)),
                radiusStyle: .softBlur,
                radiusColors: [Color(red: 0.56, green: 0.90, blue: 1.00), Color.white.opacity(0.8)],
                glassBlur: 24,
                glassTint: Color(red: 0.82, green: 0.96, blue: 1.00),
                glassOpacity: 0.38,
                controlAccent: Color(red: 0.56, green: 0.90, blue: 1.00),
                controlBackground: Color.white.opacity(0.32),
                markerGlow: Color(red: 0.56, green: 0.90, blue: 1.00),
                bottomSheetTint: Color(red: 0.90, green: 0.97, blue: 1.00),
                searchTint: Color(red: 0.56, green: 0.90, blue: 1.00),
                shadowColor: Color(red: 0.40, green: 0.72, blue: 1.00).opacity(0.35),
                animationStyle: .dreamy
            )
        case .gold:
            return PoplurMapThemeData(
                glow: PoplurMapGlowConfig(primary: Color(red: 1.00, green: 0.82, blue: 0.18), secondary: Color(red: 1.00, green: 0.60, blue: 0.08), radius: 16, opacity: 0.85, animates: true),
                particles: PoplurMapParticleConfig(kind: .sparkles, birthRate: 2.0, lifetime: 5, color: UIColor(red: 1.00, green: 0.90, blue: 0.34, alpha: 0.9), color2: UIColor(red: 1.00, green: 0.70, blue: 0.10, alpha: 0.7)),
                radiusStyle: .pulse,
                radiusColors: [Color(red: 1.00, green: 0.82, blue: 0.18), Color(red: 1.00, green: 0.94, blue: 0.52)],
                glassBlur: 16,
                glassTint: Color(red: 0.12, green: 0.08, blue: 0.01),
                glassOpacity: 0.72,
                controlAccent: Color(red: 1.00, green: 0.82, blue: 0.18),
                controlBackground: Color(red: 0.12, green: 0.08, blue: 0.01).opacity(0.88),
                markerGlow: Color(red: 1.00, green: 0.82, blue: 0.18),
                bottomSheetTint: Color(red: 0.14, green: 0.10, blue: 0.02),
                searchTint: Color(red: 1.00, green: 0.82, blue: 0.18),
                shadowColor: Color(red: 0.80, green: 0.55, blue: 0.08).opacity(0.55),
                animationStyle: .smooth
            )
        case .glitter:
            return PoplurMapThemeData(
                glow: PoplurMapGlowConfig(primary: Color(red: 1.00, green: 0.36, blue: 0.78), secondary: Color(red: 1.00, green: 0.72, blue: 0.90), radius: 20, opacity: 0.9, animates: true),
                particles: PoplurMapParticleConfig(kind: .sparkles, birthRate: 4.0, lifetime: 4, color: UIColor(red: 1.00, green: 0.36, blue: 0.78, alpha: 0.9), color2: UIColor(red: 1.00, green: 0.80, blue: 0.95, alpha: 0.8)),
                radiusStyle: .sparkle,
                radiusColors: [Color(red: 1.00, green: 0.36, blue: 0.78), Color(red: 1.00, green: 0.72, blue: 0.90)],
                glassBlur: 20,
                glassTint: Color(red: 0.20, green: 0.02, blue: 0.12),
                glassOpacity: 0.65,
                controlAccent: Color(red: 1.00, green: 0.36, blue: 0.78),
                controlBackground: Color(red: 0.20, green: 0.02, blue: 0.12).opacity(0.85),
                markerGlow: Color(red: 1.00, green: 0.36, blue: 0.78),
                bottomSheetTint: Color(red: 0.22, green: 0.02, blue: 0.14),
                searchTint: Color(red: 1.00, green: 0.36, blue: 0.78),
                shadowColor: Color(red: 1.00, green: 0.18, blue: 0.74).opacity(0.5),
                animationStyle: .energetic
            )
        case .rainbow:
            return PoplurMapThemeData(
                glow: PoplurMapGlowConfig(primary: Color(red: 1.00, green: 0.18, blue: 0.18), secondary: Color(red: 0.02, green: 0.78, blue: 1.00), radius: 16, opacity: 0.75, animates: true),
                particles: PoplurMapParticleConfig(kind: .floatingOrbs, birthRate: 2.5, lifetime: 5, color: UIColor(red: 1.00, green: 0.36, blue: 0.02, alpha: 0.7), color2: UIColor(red: 0.02, green: 0.78, blue: 1.00, alpha: 0.7)),
                radiusStyle: .ripple,
                radiusColors: [.red, .yellow, .green, .cyan, .pink],
                glassBlur: 18,
                glassTint: Color(red: 0.02, green: 0.03, blue: 0.12),
                glassOpacity: 0.60,
                controlAccent: Color(red: 0.02, green: 0.78, blue: 1.00),
                controlBackground: Color(red: 0.02, green: 0.04, blue: 0.18).opacity(0.88),
                markerGlow: Color(red: 1.00, green: 0.82, blue: 0.05),
                bottomSheetTint: Color(red: 0.02, green: 0.03, blue: 0.12),
                searchTint: Color(red: 0.05, green: 0.88, blue: 0.34),
                shadowColor: Color(red: 1.00, green: 0.18, blue: 0.82).opacity(0.4),
                animationStyle: .energetic
            )
        case .chocolate:
            return PoplurMapThemeData(
                glow: PoplurMapGlowConfig(primary: Color(red: 0.98, green: 0.62, blue: 0.24), secondary: Color(red: 0.56, green: 0.23, blue: 0.05), radius: 14, opacity: 0.7, animates: true),
                particles: PoplurMapParticleConfig(kind: .dust, birthRate: 1.5, lifetime: 7, color: UIColor(red: 0.56, green: 0.23, blue: 0.05, alpha: 0.4), color2: UIColor(red: 0.98, green: 0.62, blue: 0.24, alpha: 0.3)),
                radiusStyle: .glow,
                radiusColors: [Color(red: 0.98, green: 0.62, blue: 0.24), Color(red: 0.88, green: 0.42, blue: 0.12)],
                glassBlur: 16,
                glassTint: Color(red: 0.24, green: 0.10, blue: 0.02),
                glassOpacity: 0.74,
                controlAccent: Color(red: 0.98, green: 0.62, blue: 0.24),
                controlBackground: Color(red: 0.20, green: 0.08, blue: 0.01).opacity(0.90),
                markerGlow: Color(red: 0.98, green: 0.62, blue: 0.24),
                bottomSheetTint: Color(red: 0.22, green: 0.09, blue: 0.02),
                searchTint: Color(red: 0.98, green: 0.62, blue: 0.24),
                shadowColor: Color(red: 0.56, green: 0.23, blue: 0.05).opacity(0.45),
                animationStyle: .smooth
            )
        case .carnival:
            return PoplurMapThemeData(
                glow: PoplurMapGlowConfig(primary: Color(red: 0.02, green: 0.28, blue: 0.74), secondary: Color(red: 0.92, green: 0.12, blue: 0.12), radius: 18, opacity: 0.85, animates: true),
                particles: PoplurMapParticleConfig(kind: .confetti, birthRate: 3.0, lifetime: 4.5, color: UIColor(red: 1.00, green: 0.22, blue: 0.22, alpha: 0.9), color2: UIColor(red: 0.02, green: 0.28, blue: 0.74, alpha: 0.9)),
                radiusStyle: .pulse,
                radiusColors: [Color(red: 0.92, green: 0.12, blue: 0.12), Color(red: 0.02, green: 0.28, blue: 0.74), Color(red: 1.00, green: 0.72, blue: 0.02)],
                glassBlur: 16,
                glassTint: Color(red: 0.92, green: 0.92, blue: 0.92),
                glassOpacity: 0.38,
                controlAccent: Color(red: 0.02, green: 0.28, blue: 0.74),
                controlBackground: Color.white.opacity(0.55),
                markerGlow: Color(red: 0.92, green: 0.12, blue: 0.12),
                bottomSheetTint: Color.white,
                searchTint: Color(red: 0.02, green: 0.28, blue: 0.74),
                shadowColor: Color(red: 0.92, green: 0.12, blue: 0.12).opacity(0.4),
                animationStyle: .energetic
            )
        case .camo:
            return PoplurMapThemeData(
                glow: PoplurMapGlowConfig(primary: Color(red: 0.48, green: 0.62, blue: 0.25), secondary: Color(red: 0.33, green: 0.44, blue: 0.20), radius: 10, opacity: 0.55, animates: false),
                particles: PoplurMapParticleConfig(kind: .dust, birthRate: 0.8, lifetime: 10, color: UIColor(red: 0.22, green: 0.30, blue: 0.13, alpha: 0.35), color2: UIColor(red: 0.48, green: 0.62, blue: 0.25, alpha: 0.25)),
                radiusStyle: .softBlur,
                radiusColors: [Color(red: 0.48, green: 0.62, blue: 0.25), Color(red: 0.33, green: 0.44, blue: 0.20)],
                glassBlur: 14,
                glassTint: Color(red: 0.14, green: 0.18, blue: 0.06),
                glassOpacity: 0.76,
                controlAccent: Color(red: 0.70, green: 0.76, blue: 0.34),
                controlBackground: Color(red: 0.12, green: 0.16, blue: 0.05).opacity(0.90),
                markerGlow: Color(red: 0.48, green: 0.62, blue: 0.25),
                bottomSheetTint: Color(red: 0.14, green: 0.18, blue: 0.07),
                searchTint: Color(red: 0.70, green: 0.76, blue: 0.34),
                shadowColor: Color(red: 0.22, green: 0.30, blue: 0.13).opacity(0.5),
                animationStyle: .sharp
            )
        case .toyBox:
            return PoplurMapThemeData(
                glow: PoplurMapGlowConfig(primary: Color(red: 0.02, green: 0.28, blue: 0.74), secondary: Color(red: 0.92, green: 0.12, blue: 0.12), radius: 20, opacity: 0.9, animates: true),
                particles: PoplurMapParticleConfig(kind: .stars, birthRate: 2.5, lifetime: 5, color: UIColor(red: 1.00, green: 0.82, blue: 0.10, alpha: 0.9), color2: UIColor(red: 0.02, green: 0.78, blue: 1.00, alpha: 0.8)),
                radiusStyle: .sparkle,
                radiusColors: [Color(red: 0.92, green: 0.12, blue: 0.12), Color(red: 0.02, green: 0.28, blue: 0.74), Color(red: 1.00, green: 0.72, blue: 0.02)],
                glassBlur: 18,
                glassTint: Color.white,
                glassOpacity: 0.42,
                controlAccent: Color(red: 0.92, green: 0.12, blue: 0.12),
                controlBackground: Color.white.opacity(0.60),
                markerGlow: Color(red: 1.00, green: 0.72, blue: 0.02),
                bottomSheetTint: Color.white,
                searchTint: Color(red: 0.02, green: 0.28, blue: 0.74),
                shadowColor: Color(red: 0.92, green: 0.12, blue: 0.12).opacity(0.45),
                animationStyle: .energetic
            )
        }
    }

    var animationDuration: Double {
        switch mapThemeData.animationStyle {
        case .energetic: return 0.28
        case .smooth:    return 0.45
        case .sharp:     return 0.15
        case .dreamy:    return 0.65
        }
    }
}
