import SwiftUI
import AVFoundation

// MARK: – Duration constant shared with FeedView
let kCommercialTransitionDuration: TimeInterval = 1.5

// MARK: – Channel/video-change transition (plays commercial_transition.mp4)
struct PoplurTransitionFlash: View {
    let channelNumber: Int
    let channelCategory: String

    init(channelNumber: Int, channelCategory: String = "Poplur TV") {
        self.channelNumber = channelNumber
        self.channelCategory = channelCategory
    }

    var body: some View {
        CommercialTransitionVideoView()
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: – Commercial transition video (one-shot, auto-fades)

private struct CommercialTransitionVideoView: UIViewRepresentable {
    func makeUIView(context: Context) -> CommercialTransitionUIView { CommercialTransitionUIView() }
    func updateUIView(_ uiView: CommercialTransitionUIView, context: Context) {}
}

private final class CommercialTransitionUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?

    init() {
        super.init(frame: .zero)
        backgroundColor = .black
        // commercial_transition first; fall back to feed_end_transition
        let url = Bundle.main.url(forResource: "commercial_transition", withExtension: "mp4")
               ?? Bundle.main.url(forResource: "feed_end_transition",   withExtension: "mp4")
        guard let url else { return }

        let player = AVPlayer(url: url)
        player.isMuted = false
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        self.player = player
        self.playerLayer = layer
        player.play()

        let fadeDuration: TimeInterval = 0.12
        DispatchQueue.main.asyncAfter(deadline: .now() + kCommercialTransitionDuration - fadeDuration) {
            UIView.animate(withDuration: fadeDuration) { layer.opacity = 0 }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    deinit { player?.pause() }
}

// MARK: – Looping TV static (shown while a feed video buffers)

struct TVStaticLoopingView: UIViewRepresentable {
    func makeUIView(context: Context) -> TVStaticLoopingUIView { TVStaticLoopingUIView() }
    func updateUIView(_ uiView: TVStaticLoopingUIView, context: Context) {}
}

final class TVStaticLoopingUIView: UIView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    init() {
        super.init(frame: .zero)
        backgroundColor = .black
        guard let url = Bundle.main.url(forResource: "tv_static", withExtension: "mp4") else {
            print("[TVStaticLooping] tv_static.mp4 not found in bundle")
            return
        }
        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        let layer = AVPlayerLayer(player: queuePlayer)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        self.player = queuePlayer
        self.looper = looper
        self.playerLayer = layer
        queuePlayer.play()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    deinit { player?.pause() }
}
