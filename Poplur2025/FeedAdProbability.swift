import Foundation

enum FeedAdPlacementKind: Sendable {
    case content
    case poplurAd
    case googleMobileAd
}

struct FeedAdProbabilityConfig: Equatable, Sendable {
    var poplurAdPercent: Double
    var googleMobileAdPercent: Double

    // Match Android and the current ads-first feed: Poplur creative remains the
    // majority, while Google inventory is common enough to actually appear in
    // a normal channel session instead of being effectively invisible.
    static let defaultPoplurAdPercent: Double = 70
    static let defaultGoogleMobileAdPercent: Double = 30
    static let sharedDefaults = FeedAdProbabilityConfig(
        poplurAdPercent: defaultPoplurAdPercent,
        googleMobileAdPercent: defaultGoogleMobileAdPercent
    )

    var normalized: FeedAdProbabilityConfig {
        let poplur = poplurAdPercent.adProbabilityClamped(to: 0...100)
        let google = googleMobileAdPercent.adProbabilityClamped(to: 0...100)
        let total = poplur + google
        guard total > 100 else {
            return FeedAdProbabilityConfig(poplurAdPercent: poplur, googleMobileAdPercent: google)
        }
        let scale = 100 / total
        return FeedAdProbabilityConfig(poplurAdPercent: poplur * scale, googleMobileAdPercent: google * scale)
    }

    var contentPercent: Double {
        max(0, 100 - normalized.poplurAdPercent - normalized.googleMobileAdPercent)
    }
}

final class FeedAdProbabilitySettings: ObservableObject {
    static let shared = FeedAdProbabilitySettings()

    private let defaults: UserDefaults

    private enum Keys {
        static let poplurAdPercent = "settings.feedAds.poplurAdPercent"
        static let googleMobileAdPercent = "settings.feedAds.googleMobileAdPercent"
        static let mixVersion = "settings.feedAds.mixVersion"
    }

    private static let currentMixVersion = 2

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateLegacyDefaultsIfNeeded(defaults)
        if defaults.object(forKey: Keys.poplurAdPercent) == nil {
            defaults.set(FeedAdProbabilityConfig.defaultPoplurAdPercent, forKey: Keys.poplurAdPercent)
        }
        if defaults.object(forKey: Keys.googleMobileAdPercent) == nil {
            defaults.set(FeedAdProbabilityConfig.defaultGoogleMobileAdPercent, forKey: Keys.googleMobileAdPercent)
        }
    }

    var config: FeedAdProbabilityConfig {
        FeedAdProbabilityConfig(
            poplurAdPercent: poplurAdPercent,
            googleMobileAdPercent: googleMobileAdPercent
        ).normalized
    }

    var poplurAdPercent: Double {
        get { storedPercent(forKey: Keys.poplurAdPercent, fallback: FeedAdProbabilityConfig.defaultPoplurAdPercent) }
        set { setPercent(newValue, forKey: Keys.poplurAdPercent) }
    }

    var googleMobileAdPercent: Double {
        get { storedPercent(forKey: Keys.googleMobileAdPercent, fallback: FeedAdProbabilityConfig.defaultGoogleMobileAdPercent) }
        set { setPercent(newValue, forKey: Keys.googleMobileAdPercent) }
    }

    func setPercentages(poplur: Double, googleMobile: Double) {
        objectWillChange.send()
        let normalized = FeedAdProbabilityConfig(poplurAdPercent: poplur, googleMobileAdPercent: googleMobile).normalized
        defaults.set(normalized.poplurAdPercent, forKey: Keys.poplurAdPercent)
        defaults.set(normalized.googleMobileAdPercent, forKey: Keys.googleMobileAdPercent)
    }

    nonisolated static func currentConfig(defaults: UserDefaults = .standard) -> FeedAdProbabilityConfig {
        migrateLegacyDefaultsIfNeeded(defaults)
        let fallback = FeedAdProbabilityConfig.sharedDefaults
        let poplur = defaults.object(forKey: Keys.poplurAdPercent) as? Double ?? fallback.poplurAdPercent
        let google = defaults.object(forKey: Keys.googleMobileAdPercent) as? Double ?? fallback.googleMobileAdPercent
        return FeedAdProbabilityConfig(poplurAdPercent: poplur, googleMobileAdPercent: google).normalized
    }

    nonisolated static func placement(
        for index: Int,
        namespace: String,
        defaults: UserDefaults = .standard
    ) -> FeedAdPlacementKind {
        placement(for: index, namespace: namespace, config: currentConfig(defaults: defaults))
    }

    nonisolated static func placement(
        for index: Int,
        namespace: String,
        config: FeedAdProbabilityConfig
    ) -> FeedAdPlacementKind {
        let normalized = config.normalized
        let roll = stablePercent(for: index, namespace: namespace)
        if roll < normalized.poplurAdPercent {
            return .poplurAd
        }
        if roll < normalized.poplurAdPercent + normalized.googleMobileAdPercent {
            return .googleMobileAd
        }
        return .content
    }

    nonisolated static func shouldShowGoogleMobileAd(
        for index: Int,
        namespace: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        placement(for: index, namespace: namespace, defaults: defaults) == .googleMobileAd
    }

    private func storedPercent(forKey key: String, fallback: Double) -> Double {
        let stored = defaults.object(forKey: key) as? Double ?? fallback
        return stored.adProbabilityClamped(to: 0...100)
    }

    private func setPercent(_ value: Double, forKey key: String) {
        objectWillChange.send()
        defaults.set(value.adProbabilityClamped(to: 0...100), forKey: key)
        let normalized = config
        defaults.set(normalized.poplurAdPercent, forKey: Keys.poplurAdPercent)
        defaults.set(normalized.googleMobileAdPercent, forKey: Keys.googleMobileAdPercent)
    }

    nonisolated private static func stablePercent(for index: Int, namespace: String) -> Double {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(namespace)#\(index)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Double(hash % 10_000) / 100.0
    }

    /// Existing installs were seeded with the old 12/6 mix. Migrate only that
    /// exact untouched pair; a person who changed either setting keeps their
    /// explicit choice.
    nonisolated private static func migrateLegacyDefaultsIfNeeded(_ defaults: UserDefaults) {
        guard defaults.integer(forKey: Keys.mixVersion) < currentMixVersion else { return }
        let poplur = defaults.object(forKey: Keys.poplurAdPercent) as? Double
        let google = defaults.object(forKey: Keys.googleMobileAdPercent) as? Double
        if (poplur == nil && google == nil) || (poplur == 12 && google == 6) {
            defaults.set(FeedAdProbabilityConfig.defaultPoplurAdPercent, forKey: Keys.poplurAdPercent)
            defaults.set(FeedAdProbabilityConfig.defaultGoogleMobileAdPercent, forKey: Keys.googleMobileAdPercent)
        }
        defaults.set(currentMixVersion, forKey: Keys.mixVersion)
    }
}

private extension Comparable {
    func adProbabilityClamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
