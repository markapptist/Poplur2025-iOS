import Foundation
import SwiftUI

enum ColorSchemePreference: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Auto"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

enum PoplurLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case french = "fr"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .french: return "French"
        case .spanish: return "Spanish"
        }
    }

    var shortName: String {
        switch self {
        case .english: return "EN"
        case .french: return "FR"
        case .spanish: return "ES"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .french: return "🇫🇷"
        case .spanish: return "🇪🇸"
        }
    }

    static func fromCode(_ code: String?) -> PoplurLanguage {
        guard let code, let language = PoplurLanguage(rawValue: code) else {
            return .english
        }
        return language
    }
}

enum HoldMenuLayoutPreference: String, CaseIterable, Identifiable, Sendable {
    case horizontal = "horizontal"
    case vertical = "vertical"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }
}

enum TransitionStylePreference: String, CaseIterable, Identifiable, Sendable {
    case twoD = "2d"
    case threeD = "3d"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .twoD: return "2D"
        case .threeD: return "3D"
        }
    }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults: UserDefaults
    private init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults

        // Seed defaults if missing
        if defaults.object(forKey: Keys.maxVideoDurationSeconds) == nil {
            defaults.set(15.0, forKey: Keys.maxVideoDurationSeconds) // default can be changed
        }
        if defaults.object(forKey: Keys.preferredLanguageCode) == nil {
            defaults.set(PoplurLanguage.english.rawValue, forKey: Keys.preferredLanguageCode)
        }
        if defaults.object(forKey: Keys.closedCaptionsEnabled) == nil {
            defaults.set(true, forKey: Keys.closedCaptionsEnabled)
        }
        if defaults.object(forKey: Keys.holdMenuLayoutPreference) == nil {
            defaults.set(HoldMenuLayoutPreference.horizontal.rawValue, forKey: Keys.holdMenuLayoutPreference)
        }
        if defaults.object(forKey: Keys.transitionStylePreference) == nil {
            defaults.set(TransitionStylePreference.twoD.rawValue, forKey: Keys.transitionStylePreference)
        }
    }

    private enum Keys {
        static let maxVideoDurationSeconds = "settings.maxVideoDurationSeconds"
        static let isPrivateAccount = "settings.isPrivateAccount"
        static let notificationsEnabled = "settings.notificationsEnabled"
        static let hudSleepTimerEnabled = "settings.hudSleepTimerEnabled"
        static let preferredLanguageCode = "settings.preferredLanguageCode"
        static let closedCaptionsEnabled = "settings.closedCaptionsEnabled"
        static let colorSchemePreference = "settings.colorSchemePreference"
        static let holdMenuLayoutPreference = "settings.holdMenuLayoutPreference"
        static let transitionStylePreference = "settings.transitionStylePreference"
        static let tiltControlEnabled = "settings.tiltControlEnabled"
    }

    // MARK: - Video duration limit

    var maxVideoDurationSeconds: Double {
        get {
            let value = defaults.double(forKey: Keys.maxVideoDurationSeconds)
            // If the key was never set, double(forKey:) returns 0; guard with a sensible default.
            return value > 0 ? value : 15.0
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.maxVideoDurationSeconds)
        }
    }

    // MARK: - Optional: other settings used in AppSettingsView

    var isPrivateAccount: Bool {
        get { defaults.object(forKey: Keys.isPrivateAccount) as? Bool ?? false }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.isPrivateAccount)
        }
    }

    var notificationsEnabled: Bool {
        get { defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.notificationsEnabled)
        }
    }

    // MARK: - HUD sleep timer

    var hudSleepTimerEnabled: Bool {
        get { defaults.object(forKey: Keys.hudSleepTimerEnabled) as? Bool ?? true }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.hudSleepTimerEnabled)
        }
    }

    // MARK: - Language and captions

    var preferredLanguage: PoplurLanguage {
        get { PoplurLanguage.fromCode(defaults.string(forKey: Keys.preferredLanguageCode)) }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: Keys.preferredLanguageCode)
        }
    }

    var closedCaptionsEnabled: Bool {
        get { defaults.object(forKey: Keys.closedCaptionsEnabled) as? Bool ?? true }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.closedCaptionsEnabled)
        }
    }

    func toggleClosedCaptions() {
        closedCaptionsEnabled.toggle()
    }

    // MARK: - Color scheme

    var colorSchemePreference: ColorSchemePreference {
        get {
            let raw = defaults.string(forKey: Keys.colorSchemePreference) ?? "system"
            return ColorSchemePreference(rawValue: raw) ?? .system
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: Keys.colorSchemePreference)
        }
    }

    // MARK: - Hold menu

    var holdMenuLayoutPreference: HoldMenuLayoutPreference {
        get {
            let raw = defaults.string(forKey: Keys.holdMenuLayoutPreference) ?? HoldMenuLayoutPreference.horizontal.rawValue
            return HoldMenuLayoutPreference(rawValue: raw) ?? .horizontal
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: Keys.holdMenuLayoutPreference)
        }
    }

    // MARK: - Tilt control

    var tiltControlEnabled: Bool {
        get { defaults.object(forKey: Keys.tiltControlEnabled) as? Bool ?? false }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.tiltControlEnabled)
            if newValue {
                CubeMotionPoster.shared.start()
            } else {
                CubeMotionPoster.shared.stop()
            }
        }
    }

    // MARK: - Transitions

    var transitionStylePreference: TransitionStylePreference {
        get {
            let raw = defaults.string(forKey: Keys.transitionStylePreference) ?? TransitionStylePreference.twoD.rawValue
            return TransitionStylePreference(rawValue: raw) ?? .twoD
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: Keys.transitionStylePreference)
        }
    }
}
