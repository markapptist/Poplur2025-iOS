import SwiftUI

/// A profile-only visual theme. These identifiers are persisted and must remain stable.
enum ProfileTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case `default`
    case chocolate
    case rainbowNeon
    case camouflage
    case toy
    case rubberPink
    case icyCrystal
    case luxeGold
    case glamPink

    var id: String { rawValue }

    static var customThemes: [ProfileTheme] {
        allCases.filter { $0 != .default }
    }

    var displayName: String {
        switch self {
        case .default: return "Default Poplur"
        case .chocolate: return "Chocolate"
        case .rainbowNeon: return "Rainbow Neon"
        case .camouflage: return "Camouflage"
        case .toy: return "Toy"
        case .rubberPink: return "Rubber Pink"
        case .icyCrystal: return "Icy Crystal"
        case .luxeGold: return "Luxe Gold"
        case .glamPink: return "Glam Pink"
        }
    }

    /// Full-resolution asset. `nil` preserves the existing native profile exactly.
    var backgroundAssetName: String? {
        switch self {
        case .default: return nil
        case .chocolate: return "profile_theme_chocolate"
        case .rainbowNeon: return "profile_theme_rainbow_neon"
        case .camouflage: return "profile_theme_camouflage"
        case .toy: return "profile_theme_toy"
        case .rubberPink: return "profile_theme_rubber_pink"
        case .icyCrystal: return "profile_theme_icy_crystal"
        case .luxeGold: return "profile_theme_luxe_gold"
        case .glamPink: return "profile_theme_glam_pink"
        }
    }

    /// Picker-only downsample. The picker never loads a full-resolution background.
    var thumbnailAssetName: String? {
        backgroundAssetName.map { "\($0)_thumb" }
    }

    var primaryAccent: Color {
        switch self {
        case .default: return DS.Color.accent
        case .chocolate: return Color(profileHex: 0xFF3B8D)
        case .rainbowNeon: return Color(profileHex: 0x00E7FF)
        case .camouflage: return Color(profileHex: 0xF43F8E)
        case .toy: return Color(profileHex: 0x1677FF)
        case .rubberPink: return Color(profileHex: 0xFF2E88)
        case .icyCrystal: return Color(profileHex: 0x19BDF2)
        case .luxeGold: return Color(profileHex: 0xF5C452)
        case .glamPink: return Color(profileHex: 0xFF2D9B)
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .default: return Color(profileHex: 0x8A63FF)
        case .chocolate: return Color(profileHex: 0x8B4A2B)
        case .rainbowNeon: return Color(profileHex: 0xFF3B9D)
        case .camouflage: return Color(profileHex: 0xA68B5B)
        case .toy: return Color(profileHex: 0xFF335F)
        case .rubberPink: return Color(profileHex: 0x2EE8FF)
        case .icyCrystal: return Color(profileHex: 0xEC4FB4)
        case .luxeGold: return Color(profileHex: 0xE9378F)
        case .glamPink: return Color(profileHex: 0x49DDF7)
        }
    }

    var foreground: Color {
        switch self {
        case .default: return .black
        case .chocolate: return Color(profileHex: 0xFFF4EA)
        case .rainbowNeon: return .white
        case .camouflage: return Color(profileHex: 0xF7F0DE)
        case .toy: return Color(profileHex: 0x222222)
        case .rubberPink: return .white
        case .icyCrystal: return Color(profileHex: 0x17324D)
        case .luxeGold: return Color(profileHex: 0xFFF7D6)
        case .glamPink: return .white
        }
    }

    var overlayColor: Color {
        switch self {
        case .default: return .clear
        case .chocolate: return Color(profileHex: 0x180A05)
        case .rainbowNeon: return Color(profileHex: 0x100A34)
        case .camouflage: return Color(profileHex: 0x0B0E09)
        case .toy: return .white
        case .rubberPink: return Color(profileHex: 0x08080B)
        case .icyCrystal: return .white
        case .luxeGold: return Color(profileHex: 0x090705)
        case .glamPink: return Color(profileHex: 0x0A0209)
        }
    }

    var overlayOpacity: Double {
        switch self {
        case .default: return 0
        case .chocolate: return 0.16
        case .rainbowNeon: return 0.12
        case .camouflage: return 0.20
        case .toy: return 0.05
        case .rubberPink: return 0.12
        case .icyCrystal: return 0.08
        case .luxeGold: return 0.15
        case .glamPink: return 0.14
        }
    }

    var statusBarAppearance: ProfileThemeStatusBarAppearance {
        switch self {
        case .default, .toy, .icyCrystal: return .darkContent
        case .chocolate, .rainbowNeon, .camouflage, .rubberPink, .luxeGold, .glamPink:
            return .lightContent
        }
    }

    /// All supplied themes are included today; this field is the premium-gating extension point.
    var availability: ProfileThemeAvailability { .included }

    var preferredColorScheme: ColorScheme? {
        switch statusBarAppearance {
        case .inherited: return nil
        case .lightContent: return .dark
        case .darkContent: return .light
        }
    }

    var webStatusBarValue: String {
        switch statusBarAppearance {
        case .inherited: return "dark"
        case .lightContent: return "light"
        case .darkContent: return "dark"
        }
    }
}

enum ProfileThemeAvailability: String, Codable, Sendable {
    case included
    case premium
}

enum ProfileThemeStatusBarAppearance: String, Codable, Sendable {
    case inherited
    case lightContent
    case darkContent
}

private extension Color {
    init(profileHex value: UInt32) {
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
