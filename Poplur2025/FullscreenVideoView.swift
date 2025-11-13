import SwiftUI
import AVFoundation
import AVKit

struct FullscreenVideoView: View {
    let url: URL
    // New: explicit playback control binding
    @Binding var shouldPlay: Bool
    let isMuted: Bool
    let shouldLoop: Bool

    @State private var player: AVQueuePlayer = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?
    @State private var item: AVPlayerItem?
    @State private var playerObserver: Any?
    @State private var itemStatusObserver: NSKeyValueObservation?

    // Prevent overlapping configure tasks from racing
    @State private var configID: Int = 0

    // Segment control
    private let maxPlaybackDuration: Double = 10.0
    @State private var boundaryObserver: Any?

    // Backward-compat initializer (keeps older call sites working)
    init(url: URL, isActive: Binding<Bool>, isMuted: Bool = true, shouldLoop: Bool = true) {
        self.url = url
        // Map legacy isActive to shouldPlay
        self._shouldPlay = Binding(get: { isActive.wrappedValue }, set: { isActive.wrappedValue = $0 })
        self.isMuted = isMuted
        self.shouldLoop = shouldLoop
    }

    // New designated initializer
    init(url: URL, shouldPlay: Binding<Bool>, isMuted: Bool = true, shouldLoop: Bool = true) {
        self.url = url
        self._shouldPlay = shouldPlay
        self.isMuted = isMuted
        self.shouldLoop = shouldLoop
    }

    var body: some View {
        VideoPlayerContainer(player: player)
            .onAppear {
                configureForURL(url)
            }
            .onChange(of: url) { newURL in
                configureForURL(newURL)
            }
            .onChange(of: shouldPlay) { _ in
                updatePlayback()
            }
            .onChange(of: isMuted) { _ in
                player.isMuted = isMuted
                if shouldPlay { updatePlayback() }
            }
            .onDisappear {
                teardown()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private func configureForURL(_ url: URL) {
        // Bump generation; any in-flight task will become stale
        configID &+= 1

        // Teardown previous item/looper synchronously on main
        removeBoundaryObserver()
        looper = nil
        if let old = item {
            removeItemObservers(old)
        }
        player.pause()
        player.removeAllItems()
        item = nil

        // Build asset quickly without pre-awaiting keys
        let options: [String: Any] = [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "Poplur2025 iOS Player"
            ]
        ]
        let asset = AVURLAsset(url: url, options: options)

        // We need duration to set a 0..min(10s, duration) loop
        Task { @MainActor in
            let myID = configID
            var durationSeconds: Double = maxPlaybackDuration
            do {
                let duration = try await asset.load(.duration)
                let total = CMTimeGetSeconds(duration)
                if total.isFinite && total > 0 {
                    durationSeconds = min(maxPlaybackDuration, total)
                } else {
                    durationSeconds = maxPlaybackDuration
                }
            } catch {
                durationSeconds = maxPlaybackDuration
            }
            // If config changed while awaiting, abort
            guard myID == configID else { return }

            let newItem = AVPlayerItem(asset: asset)
            self.item = newItem
            self.addItemObservers(newItem)

            // Configure player/looper with time range
            let start = CMTime(seconds: 0, preferredTimescale: 600)
            let end = CMTime(seconds: durationSeconds, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: start, end: end)

            if self.shouldLoop {
                if !(self.player is AVQueuePlayer) {
                    self.player = AVQueuePlayer()
                }
                let queue = self.player
                queue.automaticallyWaitsToMinimizeStalling = true
                queue.isMuted = self.isMuted
                queue.actionAtItemEnd = .none
                queue.removeAllItems()

                self.looper = AVPlayerLooper(player: queue, templateItem: newItem, timeRange: timeRange)
            } else {
                self.looper = nil
                self.player.replaceCurrentItem(with: newItem)
                addBoundaryObserver(at: end)
            }

            self.player.isMuted = self.isMuted
            self.player.automaticallyWaitsToMinimizeStalling = true
            self.player.currentItem?.preferredPeakBitRate = 1_500_000 // lower for faster start

            // Ensure we start from segment start; do not auto-play here
            self.player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                self.updatePlayback()
            }
        }
    }

    private func updatePlayback() {
        if shouldPlay {
            if !isMuted {
                activatePlaybackAudioSession()
            }
            player.play()
        } else {
            player.pause()
        }
    }

    private func activatePlaybackAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("[AudioSession] Failed to activate playback session: \(error.localizedDescription)")
        }
    }

    private func teardown() {
        removeBoundaryObserver()
        player.pause()
        player.removeAllItems()
        looper = nil
        if let it = item {
            removeItemObservers(it)
        }
        item = nil
        if let obs = playerObserver {
            NotificationCenter.default.removeObserver(obs)
            playerObserver = nil
        }
        configID &+= 1
    }

    // MARK: - Observers

    private func addItemObservers(_ item: AVPlayerItem) {
        itemStatusObserver = item.observe(\.status, options: [.new, .initial]) { item, _ in
            switch item.status {
            case .readyToPlay:
                self.updatePlayback()
            case .failed:
                print("[Video] Item failed: \(item.error?.localizedDescription ?? "unknown")")
            case .unknown:
                break
            @unknown default:
                break
            }
        }

        playerObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { note in
            let err = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)?.localizedDescription ?? "unknown"
            print("[Video] FailedToPlayToEnd: \(err)")
        }
    }

    private func removeItemObservers(_ item: AVPlayerItem) {
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        if let obs = playerObserver {
            NotificationCenter.default.removeObserver(obs)
            playerObserver = nil
        }
    }

    private func addBoundaryObserver(at endTime: CMTime) {
        removeBoundaryObserver()
        let times = [NSValue(time: endTime)]
        boundaryObserver = player.addBoundaryTimeObserver(forTimes: times, queue: .main) { [weak player] in
            player?.pause()
            player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func removeBoundaryObserver() {
        if let obs = boundaryObserver {
            player.removeTimeObserver(obs)
            boundaryObserver = nil
        }
    }
}

private final class PlayerContainerViewController: UIViewController {
    let player: AVPlayer
    private let playerVC = AVPlayerViewController()

    init(player: AVPlayer) {
        self.player = player
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        playerVC.player = player
        playerVC.showsPlaybackControls = false
        playerVC.videoGravity = .resizeAspectFill
        playerVC.view.backgroundColor = .black
        playerVC.view.isUserInteractionEnabled = false

        addChild(playerVC)
        view.addSubview(playerVC.view)
        playerVC.didMove(toParent: self)

        playerVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func update(with player: AVPlayer) {
        playerVC.player = player
        playerVC.videoGravity = .resizeAspectFill
    }
}

private struct VideoPlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> PlayerContainerViewController {
        PlayerContainerViewController(player: player)
    }

    func updateUIViewController(_ vc: PlayerContainerViewController, context: Context) {
        vc.update(with: player)
    }
}
