import SwiftUI
import UIKit

/// Owns the selected profile theme independently from user profile and cube-skin state.
@MainActor
final class ProfileThemeStore: ObservableObject {
    static let shared = ProfileThemeStore()
    static let storageKey = "poplur.profile.theme.v1"

    @Published private(set) var selectedTheme: ProfileTheme

    private let defaults: UserDefaults
    private let assetExists: (String) -> Bool

    init(
        userDefaults: UserDefaults = .standard,
        assetExists: @escaping (String) -> Bool = { UIImage(named: $0) != nil }
    ) {
        defaults = userDefaults
        self.assetExists = assetExists

        let storedValue = userDefaults.string(forKey: Self.storageKey)
        let storedTheme = storedValue.flatMap(ProfileTheme.init(rawValue:)) ?? .default
        selectedTheme = Self.runtimeTheme(storedTheme, assetExists: assetExists)

        if let storedValue,
           ProfileTheme(rawValue: storedValue) == nil || selectedTheme != storedTheme {
            userDefaults.set(ProfileTheme.default.rawValue, forKey: Self.storageKey)
        }
    }

    func select(_ theme: ProfileTheme) {
        let resolvedTheme = Self.runtimeTheme(theme, assetExists: assetExists)
        guard selectedTheme != resolvedTheme else { return }
        selectedTheme = resolvedTheme
        defaults.set(resolvedTheme.rawValue, forKey: Self.storageKey)
    }

    func resetToDefault() {
        select(.default)
    }

    @discardableResult
    func select(stableID: String) -> ProfileTheme {
        guard let theme = ProfileTheme(rawValue: stableID) else {
            if selectedTheme != .default {
                selectedTheme = .default
            }
            defaults.set(ProfileTheme.default.rawValue, forKey: Self.storageKey)
            return selectedTheme
        }
        select(theme)
        return selectedTheme
    }

    private static func runtimeTheme(
        _ theme: ProfileTheme,
        assetExists: (String) -> Bool
    ) -> ProfileTheme {
        guard let assetName = theme.backgroundAssetName else { return .default }
        return assetExists(assetName) ? theme : .default
    }
}
