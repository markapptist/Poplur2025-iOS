import SwiftUI
import AVFoundation

// MARK: - Coordinator

final class StripeTransitionCoordinator: ObservableObject {
    @Published var isVisible: Bool = false
    private var midpointAction: (() -> Void)?

    func trigger(midpoint: @escaping () -> Void) {
        midpointAction = midpoint
        isVisible = true
    }

    fileprivate func fireMidpoint() {
        midpointAction?()
        midpointAction = nil
    }

    fileprivate func fireComplete() {
        isVisible = false
    }
}

// MARK: - Overlay View

struct StripeTransitionOverlay: View {
    @ObservedObject var coordinator: StripeTransitionCoordinator

    var body: some View {
        VideoTransitionPlayerView(coordinator: coordinator)
            .ignoresSafeArea()
            .allowsHitTesting(true)
    }
}

// MARK: - Video player (UIKit bridge)

private struct VideoTransitionPlayerView: UIViewRepresentable {
    let coordinator: StripeTransitionCoordinator

    func makeUIView(context: Context) -> VideoTransitionUIView {
        VideoTransitionUIView(coordinator: coordinator)
    }

    func updateUIView(_ uiView: VideoTransitionUIView, context: Context) {}
}

final class VideoTransitionUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var timeObserver: Any?

    init(coordinator: StripeTransitionCoordinator) {
        super.init(frame: .zero)
        backgroundColor = .black
        guard let url = Bundle.main.url(forResource: "auth_transition", withExtension: "mp4") else {
            print("[VideoTransition] auth_transition.mp4 not found in bundle")
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = false

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        self.player = player
        self.playerLayer = layer

        // Navigation fires at 3.0s — visually covered by the opening of the effect
        let midTime = CMTime(seconds: 3.0, preferredTimescale: 600)
        timeObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: midTime)],
            queue: .main
        ) { [weak self] in
            _ = self  // capture self to keep alive
            coordinator.fireMidpoint()
        }

        // Overlay hides when video finishes
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            _ = self
            coordinator.fireComplete()
        }

        player.play()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    deinit {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        NotificationCenter.default.removeObserver(self)
        player?.pause()
    }
}
