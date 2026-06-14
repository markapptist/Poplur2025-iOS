import UIKit
import GoogleMobileAds

final class AdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdManager()
    
    private var interstitial: InterstitialAd?
    private let interstitialUnitID = "ca-app-pub-3940256099942544/4411468910" // AdMob test interstitial
    
    private var hasStarted = false
    
    private override init() {
        super.init()
        loadInterstitial()
    }
    
    func start() {
        guard !hasStarted else { return }
        // Start the Google Mobile Ads SDK. Current API does not require a nil completion.
        MobileAds.shared.start(completionHandler: nil)
        hasStarted = true
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
