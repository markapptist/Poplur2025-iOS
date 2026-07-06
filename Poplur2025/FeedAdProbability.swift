import Foundation

enum FeedAdPlacementKind: Sendable {
    case content
    case poplurAd
    case googleMobileAd
}

struct FeedAdProbabilityConfig: Equatable, Sendable {
    var poplurAdPercent: Double
    var googleMobileAdPercent: Double

    static let defaultPoplurAdPercent: Double = 12
    static let defaultGoogleMobileAdPercent: Double = 6
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
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
}

private extension Comparable {
    func adProbabilityClamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
