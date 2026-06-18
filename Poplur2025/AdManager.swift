import UIKit
import GoogleMobileAds

final class AdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdManager()
    
    private var interstitial: InterstitialAd?
    private let interstitialUnitID = "ca-app-pub-3940256099942544/4411468910" // AdMob test interstitial
    
    private var hasStarted = false
    
    private override init() {
        super.init()
        // loadInterstitial() is intentionally NOT called here — the singleton is accessed
        // at app launch, so any network request in init() fires before the first frame.
        // start() is called after the first frame and triggers the ad preload there.
    }

    func start() {
        guard !hasStarted else { return }
        MobileAds.shared.start(completionHandler: nil)
        hasStarted = true
        loadInterstitial()
    }
    
    func loadInterstitial() {
        let request = Request()
        InterstitialAd.load(with: interstitialUnitID, request: request) { [weak self] ad, error in
            guard let self = self else { return }
            if error != nil {
                // Optionally log the error
                self.interstitial = nil
                return
            }
            self.interstitial = ad
            self.interstitial?.fullScreenContentDelegate = self
        }
    }
    
    func presentInterstitial(from root: UIViewController) {
        if let ad = interstitial {
            ad.present(from: root)
        } else {
            loadInterstitial()
        }
    }
    
    // MARK: - GADFullScreenContentDelegate
    
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        interstitial = nil
        loadInterstitial()
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        interstitial = nil
        loadInterstitial()
    }
}
