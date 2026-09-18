import AVFoundation
import Combine
import Foundation

/// Playback, rather than time since mounting the view, owns the splash lifetime.
@MainActor
final class SplashPlayback: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var progress = 0.0
    @Published private(set) var elapsed = 0.0
    @Published private(set) var hasFinished = false
    private var statusObservation: NSKeyValueObservation?
    private var notifications: [NSObjectProtocol] = []
    private var timeObserver: Any?
    private var stallTimer: Timer?
    private var lastAdvance = ProcessInfo.processInfo.systemUptime
    private var active = false

    init(url: URL? = Bundle.main.url(forResource: "poplur_splash", withExtension: "mp4")) {
        player.isMuted = true
        player.actionAtItemEnd = .pause
        guard let url else { hasFinished = true; return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in self?.finish() }
        }
        for name in [AVPlayerItem.didPlayToEndTimeNotification, AVPlayerItem.failedToPlayToEndTimeNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.finish() }
            })
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1 / 24, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, !self.hasFinished else { return }
                let seconds = time.seconds
                if seconds.isFinite, seconds > self.elapsed {
                    self.elapsed = seconds
                    self.lastAdvance = ProcessInfo.processInfo.systemUptime
                }
                let duration = self.player.currentItem?.duration.seconds ?? 0
                if seconds.isFinite, duration.isFinite, duration > 0 { self.progress = min(1, max(0, seconds / duration)) }
            }
        }
    }

    func setActive(_ value: Bool) {
        guard value != active, !hasFinished else { return }
        active = value
        stallTimer?.invalidate()
        stallTimer = nil
        if value {
            lastAdvance = ProcessInfo.processInfo.systemUptime
            player.play()
            // Only an actual decoder stall may bypass completion. Background time
            // does not count, and healthy playback has no wall-clock deadline.
            stallTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.active, !self.hasFinished else { return }
                    if ProcessInfo.processInfo.systemUptime - self.lastAdvance >= 10 { self.finish() }
                }
            }
        } else { player.pause() }
    }

    private func finish() {
        guard !hasFinished else { return }
        player.pause()
        stallTimer?.invalidate()
        stallTimer = nil
        progress = 1
        hasFinished = true
        // Keep the final frame visible while authentication/Home finishes loading.
    }

    func stop() {
        active = false
        player.pause()
        stallTimer?.invalidate()
        stallTimer = nil
        statusObservation = nil
        notifications.forEach(NotificationCenter.default.removeObserver)
        notifications.removeAll()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    deinit {
        stallTimer?.invalidate()
        notifications.forEach(NotificationCenter.default.removeObserver)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }
}
