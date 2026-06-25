import Foundation
import SwiftUI
import UIKit

public enum CubeSkin: String, CaseIterable, Identifiable, Codable {
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

    public var displayName: String {
        switch self {
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

    /// Primary theme color used for code-generated cube face textures.
    public var themeUIColor: UIColor {
        switch self {
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
            current = .rainbow
        }
    }

    public func apply(_ skin: CubeSkin) {
        guard current != skin else { return }
        current = skin
        UserDefaults.standard.set(skin.rawValue, forKey: defaultsKey)
        NotificationCenter.default.post(name: .CubeSkinDidChange, object: skin)
    }
}
