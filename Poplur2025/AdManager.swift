import UIKit
import GoogleMobileAds
import FirebaseFirestore

final class AdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdManager()
    static let feedAdVisibilityNotification = Notification.Name("PoplurFeedAdVisibility")
    
    private var interstitial: InterstitialAd?
    // Retain a presented ad until its delegate reports dismissal or failure.
    private var presentingAd: InterstitialAd?
    private var isLoading = false
    private var retryWorkItem: DispatchWorkItem?
    private var retryAttempt = 0
    private var loadedAt: Date?
    private var sdkReady = false
    private weak var pendingPresenter: UIViewController?
    private var pendingExpiry: DispatchWorkItem?
    private var isPresenting = false
    /// The earliest an interstitial may show again. The per-post cadence alone
    /// put one on screen every second advance; a floor in TIME is what that
    /// cadence cannot express, and it is the standard control for full-screen
    /// inventory. Kept identical to Android's MIN_INTERSTITIAL_GAP_MS.
    private var nextInterstitialAllowedAt: Date = .distantPast
    private static let minimumInterstitialGap: TimeInterval = 180
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
        // The server's ads switch, public/ads { enabled }. Ads are off for the beta
        // (owner decision, 30 Sep 2026): a missing, unreadable or false switch means
        // no ads, so they can be turned on later without shipping a new build.
        Firestore.firestore().collection("public").document("ads").getDocument { [weak self] snapshot, error in
            guard let self else { return }
            guard error == nil, snapshot?.data()?["enabled"] as? Bool == true else {
                PoplurDiagLog.append("[Ads] switched off on the server (public/ads); no ads")
                return
            }
            DispatchQueue.main.async { self.startSDK() }
        }
    }

    private func startSDK() {
        PoplurDiagLog.append("[Ads] SDK starting with configured production unit")
        // Cap the creative's Digital Content Label. Precisely: the labels are
        // ordered MA < T < PG < G, so .teen excludes ONLY the MA bucket. It is
        // NOT a category filter and does NOT reliably keep gambling out —
        // social-casino and betting creatives are routinely labelled T. The
        // control that actually governs that category is console-side: AdMob →
        // Blocking controls → Sensitive categories → "Gambling & betting".
        // This narrows the ceiling; it does not close the category.
        MobileAds.shared.requestConfiguration.maxAdContentRating = .teen
        MobileAds.shared.start { [weak self] _ in
            DispatchQueue.main.async {
                self?.sdkReady = true
                PoplurDiagLog.append("[Ads] SDK ready")
                self?.loadInterstitial()
            }
        }
    }
    
    func loadInterstitial() {
        guard sdkReady, !isLoading, interstitial == nil, let interstitialUnitID else { return }
        retryWorkItem?.cancel()
        retryWorkItem = nil
        isLoading = true
        PoplurDiagLog.append("[Ads] requesting interstitial")
        let request = Request()
        InterstitialAd.load(with: interstitialUnitID, request: request) { [weak self] ad, error in
            guard let self = self else { return }
            self.isLoading = false
            if error != nil {
                self.interstitial = nil
                self.cancelPendingPresentation()
                let failure = error! as NSError
                NSLog("[Ads] load failed domain=%@ code=%ld: %@", failure.domain, failure.code, failure.localizedDescription)
                PoplurDiagLog.append("[Ads] load failed domain=\(failure.domain) code=\(failure.code): \(failure.localizedDescription)")
                self.scheduleRetry()
                return
            }
            self.interstitial = ad
            self.interstitial?.fullScreenContentDelegate = self
            self.loadedAt = Date()
            self.retryAttempt = 0
            NSLog("[Ads] interstitial ready")
            PoplurDiagLog.append("[Ads] interstitial ready")
            // Keep Feed visible while inventory loads at an eligible break.
            // After that lease, retain the ad for the NEXT natural transition.
            if let presenter = self.pendingPresenter {
                self.presentInterstitial(from: presenter)
            }
        }
    }
    
    func presentInterstitial(from root: UIViewController) {
        guard Date() >= nextInterstitialAllowedAt else {
            cancelPendingPresentation()
            return
        }
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
            presentingAd = ad
            interstitial = nil
            pendingExpiry?.cancel()
            pendingExpiry = nil
            pendingPresenter = nil
            isPresenting = true
            nextInterstitialAllowedAt = Date().addingTimeInterval(Self.minimumInterstitialGap)
            ad.fullScreenContentDelegate = self
            PoplurDiagLog.append("[Ads] presenting at Feed transition")
            ad.present(from: presenter)
        } else {
            if pendingPresenter == nil {
                pendingPresenter = root
                // Loading inventory does not cover the WebView. Publishing
                // open here hid the cube/HUD on every no-fill transition.
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
        PoplurDiagLog.append("[Ads] interstitial impression recorded")
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

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        publishFeedAdVisibility(true)
    }
    
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        presentingAd = nil
        PoplurDiagLog.append("[Ads] interstitial dismissed")
        isPresenting = false
        publishFeedAdVisibility(false)
        interstitial = nil
        loadInterstitial()
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        // Nothing was shown, so the floor has nothing to space out. Leaving it
        // armed would spend three minutes of inventory on an impression that
        // never happened.
        nextInterstitialAllowedAt = .distantPast
        presentingAd = nil
        PoplurDiagLog.append("[Ads] presentation failed: \(error.localizedDescription)")
        isPresenting = false
        NSLog("[Ads] presentation failed: %@", error.localizedDescription)
        publishFeedAdVisibility(false)
        interstitial = nil
        loadInterstitial()
    }
}
