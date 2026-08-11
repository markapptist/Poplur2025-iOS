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
    private var webView: WKWebView!
    private let hostLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private var observations: [NSKeyValueObservation] = []

    private enum Palette {
        static let chrome = UIColor(red: 20 / 255, green: 14 / 255, blue: 24 / 255, alpha: 1)
        static let accent = UIColor(red: 1, green: 72 / 255, blue: 154 / 255, alpha: 1)
        static let text = UIColor(red: 1, green: 240 / 255, blue: 248 / 255, alpha: 1)
    }

    init(url: URL) {
        self.initialURL = url
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PoplurInAppBrowser is created in code only") }

    deinit {
        observations.forEach { $0.invalidate() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || navigationController?.isBeingDismissed == true else { return }
        (webView as? PoplurManagedWebView)?.poplurTearDown()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.chrome

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
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

    @objc private func closeTapped() {
        webView.stopLoading()
        dismiss(animated: true)
    }

    @objc private func backTapped() {
        if webView.canGoBack { webView.goBack() } else { closeTapped() }
    }
}

extension PoplurInAppBrowserViewController: WKNavigationDelegate {
    /// Only http(s) is ours to show. A tel:/mailto:/itms- link is a system
    /// action, and anything else is refused rather than guessed at.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }
        if scheme == "http" || scheme == "https" {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if UIApplication.shared.canOpenURL(url) { UIApplication.shared.open(url) }
    }
}

extension PoplurInAppBrowserViewController: WKUIDelegate {
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
