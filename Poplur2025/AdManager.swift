import UIKit
import GoogleMobileAds

final class AdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdManager()
    static let feedAdVisibilityNotification = Notification.Name("PoplurFeedAdVisibility")
    
    private var interstitial: InterstitialAd?
    private var isLoading = false
    private var retryWorkItem: DispatchWorkItem?
    private var retryAttempt = 0
    private var loadedAt: Date?
    private var sdkReady = false
    private weak var pendingPresenter: UIViewController?
    private var pendingExpiry: DispatchWorkItem?
    private var isPresenting = false
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
        NotificationCenter.default.addObserver(self, selector: #selector(resumePreload),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(cancelPendingPresentation),
            name: UIApplication.willResignActiveNotification, object: nil)
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
        hasStarted = true
        MobileAds.shared.start { [weak self] _ in
            DispatchQueue.main.async {
                self?.sdkReady = true
                self?.loadInterstitial()
            }
        }
    }
    
    func loadInterstitial() {
        guard sdkReady, !isLoading, interstitial == nil, let interstitialUnitID else { return }
        retryWorkItem?.cancel()
        retryWorkItem = nil
        isLoading = true
        let request = Request()
        InterstitialAd.load(with: interstitialUnitID, request: request) { [weak self] ad, error in
            guard let self = self else { return }
            self.isLoading = false
            if error != nil {
                self.interstitial = nil
                self.cancelPendingPresentation()
                let failure = error! as NSError
                NSLog("[Ads] load failed domain=%@ code=%ld: %@", failure.domain, failure.code, failure.localizedDescription)
                self.scheduleRetry()
                return
            }
            self.interstitial = ad
            self.interstitial?.fullScreenContentDelegate = self
            self.loadedAt = Date()
            self.retryAttempt = 0
            NSLog("[Ads] interstitial ready")
            // The feed is paused for at most two seconds at an eligible break.
            // After that lease, retain the ad for the NEXT natural transition.
            if let presenter = self.pendingPresenter {
                self.presentInterstitial(from: presenter)
            }
        }
    }
    
    func presentInterstitial(from root: UIViewController) {
        guard UIApplication.shared.applicationState == .active, !isPresenting else {
            cancelPendingPresentation()
            return
        }
        if !hasStarted { start() }
        guard interstitialUnitID != nil else { return }
        if let loadedAt, Date().timeIntervalSince(loadedAt) >= 3_500 { interstitial = nil }
        if let ad = interstitial {
            var presenter = root
            while let presented = presenter.presentedViewController, !presented.isBeingDismissed { presenter = presented }
            guard presenter.viewIfLoaded?.window != nil, !(presenter is UIAlertController) else {
                cancelPendingPresentation()
                return
            }
            do { try ad.canPresent(from: presenter) } catch {
                NSLog("[Ads] cannot present: %@", error.localizedDescription)
                interstitial = nil
                cancelPendingPresentation()
                loadInterstitial()
                return
            }
            interstitial = nil
            pendingExpiry?.cancel()
            pendingExpiry = nil
            pendingPresenter = nil
            isPresenting = true
            ad.fullScreenContentDelegate = self
            publishFeedAdVisibility(true)
            ad.present(from: presenter)
        } else {
            if pendingPresenter == nil {
                pendingPresenter = root
                publishFeedAdVisibility(true)
                let expiry = DispatchWorkItem { [weak self] in self?.cancelPendingPresentation() }
                pendingExpiry = expiry
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: expiry)
                NSLog("[Ads] feed break waiting for preload (maximum 2 seconds)")
            }
            loadInterstitial()
        }
    }

    @objc func cancelPendingPresentation() {
        let wasPending = pendingPresenter != nil || pendingExpiry != nil
        pendingExpiry?.cancel()
        pendingExpiry = nil
        pendingPresenter = nil
        if wasPending && !isPresenting { publishFeedAdVisibility(false) }
    }

    @objc private func resumePreload() {
        guard hasStarted, !isPresenting else { return }
        if interstitial == nil { retryAttempt = 0; loadInterstitial() }
    }

    private func publishFeedAdVisibility(_ visible: Bool) {
        NotificationCenter.default.post(
            name: Self.feedAdVisibilityNotification,
            object: self,
            userInfo: ["open": visible]
        )
    }

    private func scheduleRetry() {
        guard retryAttempt < 4 else { return }
        let delay = min(120.0, 15.0 * pow(2.0, Double(retryAttempt)))
        retryAttempt += 1
        let work = DispatchWorkItem { [weak self] in
            guard UIApplication.shared.applicationState == .active else { return }
            self?.loadInterstitial()
        }
        retryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        NSLog("[Ads] interstitial impression recorded")
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
        isPresenting = false
        publishFeedAdVisibility(false)
        interstitial = nil
        loadInterstitial()
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        isPresenting = false
        NSLog("[Ads] presentation failed: %@", error.localizedDescription)
        publishFeedAdVisibility(false)
        interstitial = nil
        loadInterstitial()
    }
}
