import Foundation
import Testing
@testable import Poplur2025

@MainActor
struct ProfileThemeStoreTests {
    @Test
    func manifestStableIDsRemainExact() {
        #expect(ProfileTheme.customThemes.map(\.rawValue) == [
            "chocolate",
            "rainbowNeon",
            "camouflage",
            "toy",
            "rubberPink",
            "icyCrystal",
            "luxeGold",
            "glamPink"
        ])
        #expect(ProfileTheme.customThemes.allSatisfy { $0.backgroundAssetName != nil })
        #expect(ProfileTheme.customThemes.allSatisfy { $0.thumbnailAssetName != nil })
        #expect(ProfileTheme.default.webStatusBarValue == "dark")
    }

    @Test
    func selectionPersistsByStableIDAndRestoresSynchronously() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProfileThemeStore(userDefaults: defaults, assetExists: { _ in true })
        store.select(.glamPink)

        #expect(defaults.string(forKey: ProfileThemeStore.storageKey) == "glamPink")

        let restored = ProfileThemeStore(userDefaults: defaults, assetExists: { _ in true })
        #expect(restored.selectedTheme == .glamPink)
    }

    @Test
    func unknownOrMissingThemeFallsBackSafelyToDefault() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("futureUnknownTheme", forKey: ProfileThemeStore.storageKey)
        let unknown = ProfileThemeStore(userDefaults: defaults, assetExists: { _ in true })
        #expect(unknown.selectedTheme == .default)
        #expect(defaults.string(forKey: ProfileThemeStore.storageKey) == "default")

        defaults.set(ProfileTheme.chocolate.rawValue, forKey: ProfileThemeStore.storageKey)
        let missingAsset = ProfileThemeStore(userDefaults: defaults, assetExists: { _ in false })
        #expect(missingAsset.selectedTheme == .default)
        #expect(defaults.string(forKey: ProfileThemeStore.storageKey) == "default")
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let name = "ProfileThemeStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            throw ProfileThemeTestError.defaultsUnavailable
        }
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }
}

private enum ProfileThemeTestError: Error {
    case defaultsUnavailable
}
