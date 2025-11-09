import SwiftUI
import AVFoundation
import AVKit

struct FullscreenVideoView: View {
    let url: URL
    @Binding var isActive: Bool
    let isMuted: Bool
    let shouldLoop: Bool

    @State private var player: AVQueuePlayer = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?
    @State private var item: AVPlayerItem?
    @State private var playerObserver: Any?
    @State private var itemStatusObserver: NSKeyValueObservation?

    // Prevent overlapping configure tasks from racing
    @State private var configID: Int = 0

    init(url: URL, isActive: Binding<Bool>, isMuted: Bool = true, shouldLoop: Bool = true) {
        self.url = url
        self._isActive = isActive
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
            .onChange(of: isActive) { _ in
                updatePlayback()
            }
            .onDisappear {
                teardown()
            }
            .ignoresSafeArea()
            // Make sure the video layer never blocks taps from overlays
            .allowsHitTesting(false)
    }

    private func configureForURL(_ url: URL) {
        // Bump generation; any in-flight task will become stale
        configID &+= 1
        let myID = configID

        // Teardown previous item/looper synchronously on main
        looper = nil
        if let old = item {
            removeItemObservers(old)
        }
        player.pause()
        player.removeAllItems()
        item = nil

        // Build asset with streaming-friendly options
        let options: [String: Any] = [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "Poplur2025 iOS Player"
            ]
        ]
        let asset = AVURLAsset(url: url, options: options)

        // Use modern async loading API
        Task {
            // Load properties asynchronously (off-main)
            do {
                let playable = try await asset.load(.isPlayable)
                let protected = try await asset.load(.hasProtectedContent)

                if !playable || protected {
                    print("[Video] Asset not playable or protected. URL=\(asset.url.absoluteString)")
                }
            } catch {
                print("[Video] Asset key load failed: \(error.localizedDescription)")
            }

            // Construct a fresh item per configuration
            let newItem = AVPlayerItem(asset: asset)

            await MainActor.run {
                // If a newer configuration started, ignore this one
                guard myID == self.configID else { return }

                // Attach observers to this item for status/error logging
                self.item = newItem
                self.addItemObservers(newItem)

                // Configure player
                if self.shouldLoop {
                    // Ensure we are using a queue player
                    if !(self.player is AVQueuePlayer) {
                        self.player = AVQueuePlayer()
                    }
                    let queue = self.player
                    queue.automaticallyWaitsToMinimizeStalling = true
                    queue.isMuted = self.isMuted
                    queue.actionAtItemEnd = .none
                    queue.removeAllItems() // just in case
                    // IMPORTANT: Do NOT also call replaceCurrentItem(with:) with newItem
                    self.looper = AVPlayerLooper(player: queue, templateItem: newItem)
                } else {
                    // Non-looping: directly replace the current item
                    self.looper = nil
                    self.player.replaceCurrentItem(with: newItem)
                }

                self.player.isMuted = self.isMuted
                self.player.automaticallyWaitsToMinimizeStalling = true
                // Reasonable default; helps start faster on slow networks
                self.player.currentItem?.preferredPeakBitRate = 4_000_000

                self.updatePlayback()
            }
        }
    }

    private func updatePlayback() {
        if isActive {
            player.play()
        } else {
            player.pause()
        }
    }

    private func teardown() {
        // Ensure everything is detached before view goes away
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
        // Invalidate any in-flight configure task
        configID &+= 1
    }

    // MARK: - Observers

    private func addItemObservers(_ item: AVPlayerItem) {
        itemStatusObserver = item.observe(\.status, options: [.new, .initial]) { item, _ in
            switch item.status {
            case .readyToPlay:
                if self.isActive { self.player.play() }
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
