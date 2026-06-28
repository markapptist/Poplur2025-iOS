import SwiftUI

public enum PoplurCubeSkinStyle: String, CaseIterable, Sendable {
    case neon, glass, ice, gold, rubber, camo, chocolate
}

public struct PoplurCubeSkin: Sendable {
    public let style: PoplurCubeSkinStyle

    // Core palette
    public let baseTint: Color
    public let primaryGlow: Color
    public let accent: Color

    // Visual feel (semantic — for SwiftUI styling)
    public let metalness: CGFloat   // 0..1
    public let roughness: CGFloat   // 0..1

    // Hold menu visuals
    public let wheelBackground: Color
    public let wheelBorder: Color
    public let wheelGlowOpacity: Double
}

public final class PoplurCubeSkinManager: ObservableObject {
    @Published public var current: PoplurCubeSkin

    public init(default style: PoplurCubeSkinStyle = .neon) {
        self.current = PoplurCubeSkin.presets[style] ?? PoplurCubeSkin.presets[.neon]!
    }

    public func setStyle(_ style: PoplurCubeSkinStyle) {
        if let preset = PoplurCubeSkin.presets[style] {
            current = preset
        }
    }
}

public extension PoplurCubeSkin {
    static let presets: [PoplurCubeSkinStyle: PoplurCubeSkin] = [
        .neon: PoplurCubeSkin(
            style: .neon,
            baseTint: .white.opacity(0.9),
            primaryGlow: Color(red: 0.75, green: 0.9, blue: 1.0),
            accent: .pink,
            metalness: 0.05,
            roughness: 0.35,
            wheelBackground: Color.black.opacity(0.35),
            wheelBorder: Color.white.opacity(0.35),
            wheelGlowOpacity: 0.65
        ),
        .glass: PoplurCubeSkin(
            style: .glass,
            baseTint: .white.opacity(0.92),
            primaryGlow: Color(red: 0.85, green: 0.95, blue: 1.0),
            accent: .cyan,
            metalness: 0.15,
            roughness: 0.45,
            wheelBackground: Color.white.opacity(0.12),
            wheelBorder: Color.white.opacity(0.35),
            wheelGlowOpacity: 0.45
        ),
        .ice: PoplurCubeSkin(
            style: .ice,
            baseTint: .white.opacity(0.92),
            primaryGlow: Color(red: 0.70, green: 0.90, blue: 1.0),
            accent: .blue,
            metalness: 0.12,
            roughness: 0.50,
            wheelBackground: Color.white.opacity(0.10),
            wheelBorder: Color.white.opacity(0.35),
            wheelGlowOpacity: 0.50
        ),
        .gold: PoplurCubeSkin(
            style: .gold,
            baseTint: Color(red: 0.98, green: 0.88, blue: 0.45),
            primaryGlow: Color(red: 1.0, green: 0.95, blue: 0.6),
            accent: Color(red: 0.9, green: 0.75, blue: 0.2),
            metalness: 1.0,
            roughness: 0.28,
            wheelBackground: Color(red: 0.20, green: 0.16, blue: 0.05).opacity(0.85),
            wheelBorder: Color(red: 0.95, green: 0.82, blue: 0.34).opacity(0.75),
            wheelGlowOpacity: 0.25
        ),
        .rubber: PoplurCubeSkin(
            style: .rubber,
            baseTint: .white.opacity(0.92),
            primaryGlow: Color(red: 0.8, green: 0.9, blue: 1.0),
            accent: .purple,
            metalness: 0.0,
            roughness: 0.90,
            wheelBackground: Color.black.opacity(0.55),
            wheelBorder: Color.black.opacity(0.65),
            wheelGlowOpacity: 0.15
        ),
        .camo: PoplurCubeSkin(
            style: .camo,
            baseTint: Color(red: 0.7, green: 0.75, blue: 0.6),
            primaryGlow: Color(red: 0.8, green: 0.9, blue: 0.8),
            accent: Color(red: 0.6, green: 0.7, blue: 0.5),
            metalness: 0.05,
            roughness: 0.85,
            wheelBackground: Color(red: 0.18, green: 0.2, blue: 0.16).opacity(0.9),
            wheelBorder: Color(red: 0.4, green: 0.45, blue: 0.35).opacity(0.75),
            wheelGlowOpacity: 0.12
        ),
        .chocolate: PoplurCubeSkin(
            style: .chocolate,
            baseTint: Color(red: 0.9, green: 0.8, blue: 0.7),
            primaryGlow: Color(red: 1.0, green: 0.92, blue: 0.82),
            accent: Color(red: 0.6, green: 0.35, blue: 0.2),
            metalness: 0.05,
            roughness: 0.70,
            wheelBackground: Color(red: 0.12, green: 0.07, blue: 0.04).opacity(0.92),
            wheelBorder: Color(red: 0.45, green: 0.30, blue: 0.18).opacity(0.75),
            wheelGlowOpacity: 0.15
        )
    ]
}
