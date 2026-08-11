import SwiftUI
import UIKit

// MARK: - Public: inline view placed as first child in any .refreshable ScrollView's content

/// Place this as the **first item** inside the scroll view's VStack/content, paired with
/// `.refreshable {}` on the same ScrollView.  It hides the native spinner and replaces it
/// with the Poplur logo animation (Snapchat-style: winds up as you pull, spins while loading).
///
/// Example:
///   ScrollView {
///       VStack {
///           PoplurRefreshHeader()           // ← add here, zero height
///           // ... rest of content ...
///       }
///   }
///   .refreshable { await reload() }
struct PoplurRefreshHeader: UIViewRepresentable {
    func makeUIView(context: Context) -> _PoplurRefreshInstallerView {
        _PoplurRefreshInstallerView()
    }
    func updateUIView(_ uiView: _PoplurRefreshInstallerView, context: Context) {}
}

// MARK: - Installer (UIView that lives inside the scroll content)

final class _PoplurRefreshInstallerView: UIView {
    private weak var observedScrollView: UIScrollView?
    private var kvoToken: NSKeyValueObservation?
    private var didCustomise = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !didCustomise else { return }
        // Try synchronously; fall back to KVO if the scroll view has no refreshControl yet.
        DispatchQueue.main.async { [weak self] in self?.hookScrollView() }
    }

    private func hookScrollView() {
        // Walk up the UIKit hierarchy — we are inside the UIScrollView's content host,
        // so the path is: _InstallerView → _UIHostingView(s) → UIScrollView.
        var cur: UIView? = superview
        while let v = cur {
            if let sv = v as? UIScrollView {
                if let rc = sv.refreshControl {
                    customise(rc, scrollView: sv)
                } else {
                    // .refreshable hasn't set the refreshControl yet — observe it.
                    observedScrollView = sv
                    kvoToken = sv.observe(\.refreshControl, options: [.new]) { [weak self] sv, _ in
                        guard let self, let rc = sv.refreshControl else { return }
                        self.customise(rc, scrollView: sv)
                        self.kvoToken = nil
                    }
                }
                return
            }
            cur = v.superview
        }
    }

    private func customise(_ rc: UIRefreshControl, scrollView: UIScrollView) {
        guard !didCustomise else { return }
        didCustomise = true

        rc.tintColor = .clear   // hide the native spinner

        let logo = _PoplurRefreshLogoView(scrollView: scrollView)
        logo.translatesAutoresizingMaskIntoConstraints = false
        rc.addSubview(logo)
        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: rc.centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: rc.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 60),
            logo.heightAnchor.constraint(equalToConstant: 60),
        ])
    }

    deinit { kvoToken = nil }
}

// MARK: - Animated logo view

private final class _PoplurRefreshLogoView: UIView {
    private let imageView = UIImageView()
    private weak var scrollView: UIScrollView?
    private weak var refreshControl: UIRefreshControl?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var refreshingObservation: NSKeyValueObservation?

    private var wasRefreshing = false
    private var isSpinning    = false
    private var hapticFired   = false
    private let pullThreshold: CGFloat = 68

    init(scrollView: UIScrollView) {
        self.scrollView = scrollView
        super.init(frame: .zero)
        backgroundColor = .clear

        imageView.image = UIImage(named: "logo")
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.alpha = 0
        imageView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        refreshControl = scrollView.refreshControl
        contentOffsetObservation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, _ in
            self?.updateState()
        }
        refreshingObservation = refreshControl?.observe(\.isRefreshing, options: [.initial, .new]) { [weak self] _, _ in
            self?.updateState()
        }
        refreshControl?.addTarget(self, action: #selector(refreshValueChanged), for: .valueChanged)
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit {
        contentOffsetObservation?.invalidate()
        refreshingObservation?.invalidate()
        refreshControl?.removeTarget(self, action: #selector(refreshValueChanged), for: .valueChanged)
    }

    @objc private func refreshValueChanged() {
        updateState()
    }

    private func updateState() {
        guard let sv = scrollView else { return }
        let isRefreshing = sv.refreshControl?.isRefreshing == true

        if isRefreshing {
            if !wasRefreshing {
                wasRefreshing = true
                hapticFired   = false
                snapToRefreshing()
            }
        } else {
            if wasRefreshing {
                wasRefreshing = false
                snapToIdle()
                return
            }
            // Live pull tracking: negative contentOffset means pulling down
            let pull = -sv.contentOffset.y - sv.adjustedContentInset.top
            if pull > 1 {
                let p = min(1.0, pull / pullThreshold)
                applyPullProgress(p)
            } else {
                resetHidden()
            }
        }
    }

    // MARK: pull progress (called every frame — no UIView.animate, direct assignment only)

    private func applyPullProgress(_ p: CGFloat) {
        let scale = 0.2 + p * 0.8          // 0.2 → 1.0
        let wind  = p * (.pi * 0.6)        // 0 → ~108° clockwise wind-up
        imageView.alpha = min(1, p * 1.6)  // fully opaque at 62% pull
        imageView.transform = CGAffineTransform(scaleX: scale, y: scale).rotated(by: wind)

        if p >= 1.0, !hapticFired {
            hapticFired = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
            bounceScale()
        } else if p < 0.95 {
            hapticFired = false
        }
    }

    private func resetHidden() {
        guard imageView.alpha > 0 else { return }
        imageView.alpha = 0
        imageView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        hapticFired = false
    }

    // MARK: state transitions (used for refresh start/end)

    private func snapToRefreshing() {
        stopSpin()
        imageView.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.15) {
            self.imageView.alpha = 1
            self.imageView.transform = .identity
        } completion: { _ in
            self.startSpin()
        }
    }

    private func snapToIdle() {
        stopSpin()
        UIView.animate(withDuration: 0.20) {
            self.imageView.alpha = 0
            self.imageView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        }
    }

    private func bounceScale() {
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            usingSpringWithDamping: 0.38,
            initialSpringVelocity: 5,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.imageView.transform = CGAffineTransform(scaleX: 1.28, y: 1.28)
                .rotated(by: .pi * 0.6)   // locked at wind-up angle
        } completion: { _ in
            UIView.animate(withDuration: 0.12) {
                self.imageView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
                    .rotated(by: .pi * 0.6)
            }
        }
    }

    // MARK: spin

    private func startSpin() {
        guard !isSpinning else { return }
        isSpinning = true
        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = 0
        anim.toValue   = 2 * Double.pi
        anim.duration  = 0.7
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        imageView.layer.add(anim, forKey: "poplurSpin")
    }

    private func stopSpin() {
        guard isSpinning else { return }
        isSpinning = false
        imageView.layer.removeAnimation(forKey: "poplurSpin")
    }
}
