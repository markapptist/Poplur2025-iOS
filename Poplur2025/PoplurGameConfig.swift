import Foundation
import UIKit

enum PoplurGameType: String, Codable, CaseIterable {
    case sideScroller   = "pop_runner"
    case arcadeShooter  = "stella_blast"
    case actionAdventure = "zyla_quest"
    case sports         = "rex_hoops"

    var displayName: String {
        switch self {
        case .sideScroller:    "Side Scroller"
        case .arcadeShooter:   "Arcade Shooter"
        case .actionAdventure: "Action / Adventure"
        case .sports:          "Sports"
        }
    }
}

struct PoplurGameConfig: Codable {
    let game: PoplurGameType
    let character: PoplurCharacterID
    let gameName: String
    let theme: String
    let skyColor: String
    let groundColor: String
    let accentColor: String
    let difficulty: String
    let speed: Double
    let powerUps: [String]
    let enemyType: String
    let specialMechanic: String

    var skyUIColor: UIColor   { UIColor(hex: skyColor) ?? UIColor(red: 0.10, green: 0.10, blue: 0.20, alpha: 1) }
    var groundUIColor: UIColor { UIColor(hex: groundColor) ?? UIColor(red: 0.06, green: 0.12, blue: 0.12, alpha: 1) }
    var accentUIColor: UIColor { UIColor(hex: accentColor) ?? UIColor(red: 0.91, green: 0.27, blue: 0.38, alpha: 1) }

    static let fallback = PoplurGameConfig(
        game: .arcadeShooter, character: .stella,
        gameName: "Stella Starfall", theme: "Space",
        skyColor: "#050713", groundColor: "#111B3D", accentColor: "#00F5FF",
        difficulty: "medium", speed: 260,
        powerUps: ["triple shot", "shield"], enemyType: "neon drones", specialMechanic: "drag-to-fly auto fire"
    )
}

extension UIColor {
    convenience init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
