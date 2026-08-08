import UIKit

#if canImport(GoogleMobileAds)
import GoogleMobileAds

final class AdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdManager()

    private let samplePublisherID = "ca-app-pub-3940256099942544"
    private var interstitial: InterstitialAd?
    private var hasStarted = false

    private var interstitialUnitID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "ADMOB_INTERSTITIAL_UNIT_ID") as? String
        return value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private override init() {
        super.init()
    }

    func start() {
        guard !hasStarted else { return }
        MobileAds.shared.start(completionHandler: nil)
        hasStarted = true
        loadInterstitial()
    }

    func loadInterstitial() {
        guard let interstitialUnitID, isProductionAdUnit(interstitialUnitID) else {
            interstitial = nil
            return
        }

        InterstitialAd.load(with: interstitialUnitID, request: Request()) { [weak self] ad, _ in
            guard let self else { return }
            self.interstitial = ad
            self.interstitial?.fullScreenContentDelegate = self
        }
    }

    func presentInterstitial(from root: UIViewController) {
        guard interstitialUnitID.map(isProductionAdUnit) == true else { return }
        if let interstitial {
            interstitial.present(from: root)
        } else {
            loadInterstitial()
        }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        interstitial = nil
        loadInterstitial()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        interstitial = nil
        loadInterstitial()
    }

    private func isProductionAdUnit(_ id: String) -> Bool {
        !id.isEmpty && !id.contains(samplePublisherID)
    }
}
#else
final class AdManager {
    static let shared = AdManager()
    private init() {}
    func start() {}
    func loadInterstitial() {}
    func presentInterstitial(from root: UIViewController) {}
}
#endif
