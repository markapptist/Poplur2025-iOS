import Foundation

/// Persistent storage for the selected PoplurTheme.
/// PoplurThemeManager reads/writes through this automatically.
/// Call ThemeStorage.load() at app launch to restore the saved theme.
enum ThemeStorage {
    private static let key = "poplur_map_theme_v1"

    static func save(_ theme: PoplurTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: key)
    }

    static func load() -> PoplurTheme {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let theme = PoplurTheme(rawValue: raw) else { return .default }
        return theme
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
