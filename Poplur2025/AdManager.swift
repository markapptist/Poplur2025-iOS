import UIKit
import GoogleMobileAds

final class AdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdManager()
    static let feedAdVisibilityNotification = Notification.Name("PoplurFeedAdVisibility")
    
    private var interstitial: InterstitialAd?
    private weak var pendingRootViewController: UIViewController?
    private var presentationPending = false
    private var isLoading = false
    private var interstitialUnitID: String? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "PoplurAdMobInterstitialUnitID"
        ) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("ca-app-pub-"),
              !trimmed.contains("3940256099942544") else { return nil }
        return trimmed
    }
    
    private var hasStarted = false
    
    private override init() {
        super.init()
        // loadInterstitial() is intentionally NOT called here — the singleton is accessed
        // at app launch, so any network request in init() fires before the first frame.
        // start() is called after the first frame and triggers the ad preload there.
    }

    func start() {
        guard !hasStarted else { return }
        guard interstitialUnitID != nil else {
            print("[Ads] Production interstitial unit is missing or invalid; ads disabled")
            return
        }
        MobileAds.shared.start(completionHandler: nil)
        hasStarted = true
        loadInterstitial()
    }
    
    func loadInterstitial() {
        guard !isLoading, let interstitialUnitID else { return }
        isLoading = true
        let request = Request()
        InterstitialAd.load(with: interstitialUnitID, request: request) { [weak self] ad, error in
            guard let self = self else { return }
            self.isLoading = false
            if error != nil {
                self.interstitial = nil
                print("[Ads] Interstitial failed to load: \(error!.localizedDescription)")
                return
            }
            self.interstitial = ad
            self.interstitial?.fullScreenContentDelegate = self
            self.presentPendingInterstitialIfPossible()
        }
    }
    
    func presentInterstitial(from root: UIViewController) {
        if let ad = interstitial {
            presentationPending = false
            pendingRootViewController = nil
            interstitial = nil
            ad.fullScreenContentDelegate = self
            publishFeedAdVisibility(true)
            ad.present(from: root)
        } else {
            // Feed changes are often faster than the first network response.
            // Keep one eligible presentation and fulfil it when AdMob returns
            // instead of dropping the only real-ad opportunity in the session.
            presentationPending = true
            pendingRootViewController = root
            loadInterstitial()
        }
    }

    private func publishFeedAdVisibility(_ visible: Bool) {
        NotificationCenter.default.post(
            name: Self.feedAdVisibilityNotification,
            object: self,
            userInfo: ["open": visible]
        )
    }

    private func presentPendingInterstitialIfPossible() {
        guard presentationPending,
              let root = pendingRootViewController,
              root.viewIfLoaded?.window != nil else {
            return
        }
        presentInterstitial(from: root)
    }

    /// The web home has no view controller of its own to present from — find
    /// the key window's root, the same one FeedView used to resolve by hand.
    @MainActor
    func presentInterstitialOverKeyWindow() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else {
            print("[Ads] No active window to present interstitial")
            return
        }
        presentInterstitial(from: root)
    }
    
    // MARK: - GADFullScreenContentDelegate
    
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        publishFeedAdVisibility(false)
        interstitial = nil
        loadInterstitial()
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        publishFeedAdVisibility(false)
        interstitial = nil
        loadInterstitial()
    }
}
