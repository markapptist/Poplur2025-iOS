import Foundation

/// Runtime configuration that is safe to keep in source control.
///
/// Private values can be supplied through UserDefaults, the process environment,
/// or Info.plist. No provider credential is embedded in the application source.
enum AppSecrets {
    static var claudeAPIKey: String {
        value(userDefaultsKey: "poplur_claude_key", configurationKey: "POPLUR_CLAUDE_API_KEY")
    }

    static var mapboxToken: String {
        value(userDefaultsKey: "poplur_mapbox_token", configurationKey: "POPLUR_MAPBOX_TOKEN")
    }

    static var elevenLabsAPIKey: String {
        value(userDefaultsKey: "poplur_elevenlabs_key", configurationKey: "POPLUR_ELEVENLABS_API_KEY")
    }

    static var elevenLabsVoiceID: String {
        value(userDefaultsKey: "poplur_elevenlabs_voice_id", configurationKey: "POPLUR_ELEVENLABS_VOICE_ID")
    }

    static var elevenLabsFrenchVoiceID: String {
        value(userDefaultsKey: "poplur_elevenlabs_french_voice_id", configurationKey: "POPLUR_ELEVENLABS_FRENCH_VOICE_ID")
    }

    private static func value(userDefaultsKey: String, configurationKey: String) -> String {
        let defaultsValue = UserDefaults.standard.string(forKey: userDefaultsKey) ?? ""
        if !defaultsValue.isEmpty { return defaultsValue }

        let environmentValue = ProcessInfo.processInfo.environment[configurationKey] ?? ""
        if !environmentValue.isEmpty { return environmentValue }

        return Bundle.main.object(forInfoDictionaryKey: configurationKey) as? String ?? ""
    }
}
