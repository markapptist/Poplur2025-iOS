import Foundation

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults: UserDefaults
    private init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults

        // Seed defaults if missing
        if defaults.object(forKey: Keys.maxVideoDurationSeconds) == nil {
            defaults.set(15.0, forKey: Keys.maxVideoDurationSeconds) // default can be changed
        }
    }

    private enum Keys {
        static let maxVideoDurationSeconds = "settings.maxVideoDurationSeconds"
        static let isPrivateAccount = "settings.isPrivateAccount"
        static let notificationsEnabled = "settings.notificationsEnabled"
    }

    // MARK: - Video duration limit

    var maxVideoDurationSeconds: Double {
        get {
            let value = defaults.double(forKey: Keys.maxVideoDurationSeconds)
            // If the key was never set, double(forKey:) returns 0; guard with a sensible default.
            return value > 0 ? value : 15.0
        }
        set {
            defaults.set(newValue, forKey: Keys.maxVideoDurationSeconds)
            // If later you bind UI to this, consider @Published to notify observers:
            // DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    // MARK: - Optional: other settings used in AppSettingsView

    var isPrivateAccount: Bool {
        get { defaults.object(forKey: Keys.isPrivateAccount) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.isPrivateAccount) }
    }

    var notificationsEnabled: Bool {
        get { defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.notificationsEnabled) }
    }
}
