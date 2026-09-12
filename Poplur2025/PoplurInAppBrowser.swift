import UIKit
import WebKit

/// Poplur's own browser, for ad and suggestion click-throughs.
///
/// This replaced `SFSafariViewController`. That class is Safari: it wears
/// Safari's chrome, offers "Open in the <app>" banners, and reads to the user
/// as leaving Poplur — which is exactly what it is. The ad window in the web
/// layer already presents itself as a window that BECOMES a browser, so the
/// native half has to keep the user inside the app for that to be true.
///
/// Two things here are load-bearing rather than cosmetic:
///
///  - The configuration is a FRESH one. The app's own `WKWebView` carries
///    Poplur's `WKScriptMessageHandler` bridge; reusing its configuration would
///    hand an untrusted landing page the same channel the app uses to reach
///    native. This one has no handlers and no bridge.
///  - The data store is non-persistent, so cookies and storage the shop sets
///    die with the window instead of following the user around the app.
final class PoplurInAppBrowserViewController: UIViewController {
    private let initialURL: URL
    private var onDismiss: (() -> Void)?
    private var webView: WKWebView!
    private let hostLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private var observations: [NSKeyValueObservation] = []
    private let loadFailurePanel = UIView()
    private var loadTimeoutWorkItem: DispatchWorkItem?

    private enum Palette {
        static let chrome = UIColor(red: 20 / 255, green: 14 / 255, blue: 24 / 255, alpha: 1)
        static let accent = UIColor(red: 1, green: 72 / 255, blue: 154 / 255, alpha: 1)
        static let text = UIColor(red: 1, green: 240 / 255, blue: 248 / 255, alpha: 1)
    }

    init(url: URL, onDismiss: @escaping () -> Void) {
        self.initialURL = url
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PoplurInAppBrowser is created in code only") }

    deinit {
        observations.forEach { $0.invalidate() }
        loadTimeoutWorkItem?.cancel()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || navigationController?.isBeingDismissed == true else { return }
        (webView as? PoplurManagedWebView)?.poplurTearDown()
        releaseHostOcclusionOnce()
    }

    /// UIKit reports presentation refusal only through controller state. The
    /// caller invokes this when the browser never acquired a presenter so the
    /// signed-in Home renderer cannot remain parked behind a missing screen.
    func presentationFailed() {
        if isViewLoaded {
            (webView as? PoplurManagedWebView)?.poplurTearDown()
        }
        releaseHostOcclusionOnce()
    }

    private func releaseHostOcclusionOnce() {
        let release = onDismiss
        onDismiss = nil
        release?()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.chrome

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        // WebKit has no public per-WKWebView geolocation delegate on iOS.
        // Shadow the API before any page script runs so an advertiser cannot
        // inherit the location permission Poplur uses for its own map.
        config.userContentController.addUserScript(WKUserScript(
            source: Self.locationDenialScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        let web = PoplurManagedWebView(
            performanceName: "InAppBrowserWeb",
            priority: 200,
            configuration: config
        )
        web.allowsBackForwardNavigationGestures = true
        web.navigationDelegate = self
        web.uiDelegate = self
        web.backgroundColor = Palette.chrome
        web.isOpaque = false
        webView = web

        let bar = buildChromeBar()

        [bar, progressView, web].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        progressView.progressTintColor = Palette.accent
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.08)
        progressView.alpha = 0

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 52),

            progressView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            web.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        installLoadFailurePanel(below: progressView)

        observations = [
            web.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in
                guard let self else { return }
                let done = web.estimatedProgress >= 1
                self.progressView.setProgress(Float(web.estimatedProgress), animated: true)
                UIView.animate(withDuration: 0.2) { self.progressView.alpha = done ? 0 : 1 }
                if done { self.progressView.setProgress(0, animated: false) }
            },
            web.observe(\.url, options: [.new]) { [weak self] web, _ in
                self?.hostLabel.text = Self.displayHost(for: web.url)
            },
        ]

        hostLabel.text = Self.displayHost(for: initialURL)
        web.load(URLRequest(url: initialURL))
    }

    /// Advertiser pages are outside Poplur’s control, but they must never leave
    /// someone staring at an undismissable black WebKit canvas. Keep the native
    /// chrome available and offer an explicit retry when navigation fails or
    /// produces no first response in a bounded window.
    private func installLoadFailurePanel(below chrome: UIView) {
        loadFailurePanel.backgroundColor = Palette.chrome
        loadFailurePanel.isHidden = true
        loadFailurePanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadFailurePanel)

        let title = UILabel()
        title.text = "This page didn’t load"
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = Palette.text
        title.textAlignment = .center

        let message = UILabel()
        message.text = "The destination may be unavailable. You can try again or return to Poplur."
        message.font = .systemFont(ofSize: 15, weight: .regular)
        message.textColor = Palette.text.withAlphaComponent(0.78)
        message.numberOfLines = 0
        message.textAlignment = .center

        var retryConfiguration = UIButton.Configuration.filled()
        retryConfiguration.title = "Try again"
        retryConfiguration.baseBackgroundColor = Palette.accent
        retryConfiguration.baseForegroundColor = .white
        retryConfiguration.cornerStyle = .medium
        let retry = UIButton(configuration: retryConfiguration)
        retry.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        var closeConfiguration = UIButton.Configuration.plain()
        closeConfiguration.title = "Return to Poplur"
        closeConfiguration.baseForegroundColor = Palette.text
        let close = UIButton(configuration: closeConfiguration)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, message, retry, close])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        loadFailurePanel.addSubview(stack)

        NSLayoutConstraint.activate([
            loadFailurePanel.topAnchor.constraint(equalTo: chrome.bottomAnchor),
            loadFailurePanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadFailurePanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadFailurePanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: loadFailurePanel.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: loadFailurePanel.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: loadFailurePanel.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: loadFailurePanel.trailingAnchor, constant: -32),
            retry.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func armLoadTimeout() {
        loadTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.showLoadFailure()
        }
        loadTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    private func clearLoadFailure() {
        loadTimeoutWorkItem?.cancel()
        loadTimeoutWorkItem = nil
        loadFailurePanel.isHidden = true
    }

    private func showLoadFailure() {
        guard loadFailurePanel.isHidden else { return }
        loadTimeoutWorkItem?.cancel()
        loadTimeoutWorkItem = nil
        webView.stopLoading()
        loadFailurePanel.isHidden = false
    }

    private func buildChromeBar() -> UIView {
        let bar = UIView()
        bar.backgroundColor = Palette.chrome

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = Palette.accent
        close.accessibilityLabel = "Close browser"
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.tintColor = Palette.text
        back.accessibilityLabel = "Back"
        back.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        let lock = UIImageView(image: UIImage(systemName: "lock.fill"))
        lock.tintColor = Palette.text.withAlphaComponent(0.7)
        lock.contentMode = .scaleAspectFit

        hostLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        hostLabel.textColor = Palette.text
        hostLabel.lineBreakMode = .byTruncatingTail

        // "IN POPLUR" rather than a site name: the point of this bar is to say
        // where you still are.
        let badge = UILabel()
        badge.text = "IN POPLUR"
        badge.font = .systemFont(ofSize: 10, weight: .heavy)
        badge.textColor = Palette.accent

        let title = UIStackView(arrangedSubviews: [lock, hostLabel])
        title.axis = .horizontal
        title.spacing = 5
        title.alignment = .center

        let stack = UIStackView(arrangedSubviews: [close, back, title, UIView(), badge])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        let hairline = UIView()
        hairline.backgroundColor = Palette.accent.withAlphaComponent(0.35)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(hairline)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            lock.widthAnchor.constraint(equalToConstant: 11),
            hairline.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
        ])
        return bar
    }

    private static func displayHost(for url: URL?) -> String {
        guard let host = url?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static let locationDenialScript = #"""
    (() => {
      const denied = Object.freeze({ code: 1, message: 'Permission denied' });
      const reject = (_success, failure) => {
        if (typeof failure === 'function') queueMicrotask(() => failure(denied));
      };
      const blocked = Object.freeze({
        getCurrentPosition: reject,
        watchPosition: (_success, failure) => { reject(_success, failure); return -1; },
        clearWatch: () => {}
      });
      try {
        const navigatorPrototype = Object.getPrototypeOf(navigator);
        Object.defineProperty(navigatorPrototype, 'geolocation', {
          get: () => blocked,
          configurable: false,
          enumerable: true
        });
      } catch (_) {}
      try {
        Object.defineProperty(navigator, 'geolocation', {
          value: blocked,
          configurable: false,
          enumerable: false,
          writable: false
        });
      } catch (_) {}
    })();
    """#

    @objc private func closeTapped() {
        webView.stopLoading()
        dismiss(animated: true)
    }

    @objc private func retryTapped() {
        clearLoadFailure()
        webView.load(URLRequest(url: initialURL, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    @objc private func backTapped() {
        if webView.canGoBack { webView.goBack() } else { closeTapped() }
    }
}

extension PoplurInAppBrowserViewController: WKNavigationDelegate {
    /// Only credential-free HTTPS is ours to show. A tel:/mailto:/itms- link
    /// is an intentional system action; an HTTP redirect is simply refused so
    /// an advertiser can never bounce this Poplur-owned surface into Safari.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame != false, let destination = Self.googleRedirectDestination(url) {
            decisionHandler(.cancel)
            webView.load(URLRequest(url: destination))
            return
        }
        if scheme == "https", url.user == nil, url.password == nil {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if ["tel", "mailto", "itms-apps"].contains(scheme),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        clearLoadFailure()
        armLoadTimeout()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        clearLoadFailure()
        // Google's Lucky endpoint can render a notice instead of an HTTP redirect.
        guard let host = webView.url?.host?.lowercased(), ["google.com", "www.google.com"].contains(host) else { return }
        webView.evaluateJavaScript("document.title.includes('Redirect Notice') || document.body.innerText.includes('Redirect Notice') ? document.querySelector('a[href^=\"https://\"]')?.href : null") { [weak webView] value, _ in
            guard let webView, ["google.com", "www.google.com"].contains(webView.url?.host?.lowercased() ?? ""),
                  let raw = value as? String, let destination = URL(string: raw),
                  destination.scheme == "https", destination.user == nil, destination.password == nil,
                  destination.host?.isEmpty == false, !["google.com", "www.google.com"].contains(destination.host!.lowercased()) else { return }
            webView.load(URLRequest(url: destination))
        }
    }

    static func googleRedirectDestination(_ url: URL) -> URL? {
        guard ["google.com", "www.google.com"].contains(url.host?.lowercased() ?? ""), url.path == "/url",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = parts.queryItems?.first(where: { $0.name == "q" || $0.name == "url" })?.value,
              let target = URL(string: raw), target.scheme == "https", target.host?.isEmpty == false,
              target.user == nil, target.password == nil,
              !["google.com", "www.google.com"].contains(target.host!.lowercased()) else { return nil }
        return target
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        showLoadFailure()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        showLoadFailure()
    }
}

extension PoplurInAppBrowserViewController: WKUIDelegate {
    /// Poplur itself may already hold camera/microphone and motion permission
    /// for calls and the map. External pages never inherit those grants.
    @available(iOS 15.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.deny)
    }

    @available(iOS 15.0, *)
    func webView(
        _ webView: WKWebView,
        requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.deny)
    }

    /// `target="_blank"` has no second window to open here, so it loads in this
    /// one — otherwise those links silently do nothing.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
