import Foundation
import AVFoundation

final class FeedAudioManager {
    static let shared = FeedAudioManager()

    // Keep weak references so players can deallocate
    private let players = NSHashTable<AVPlayer>.weakObjects()
    private weak var currentPlayer: AVPlayer?

    var isGloballyMuted: Bool = false {
        didSet {
            for p in players.allObjects {
                p.isMuted = isGloballyMuted
                if !isGloballyMuted {
                    p.volume = 1.0
                }
            }
        }
    }

    private init() {
        NotificationCenter.default.addObserver(forName: Notification.Name("PauseGlobalFeedAudio"), object: nil, queue: .main) { [weak self] _ in
            self?.stopAll()
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("FeedLaunchLoadingDidStart"), object: nil, queue: .main) { [weak self] _ in
            self?.isGloballyMuted = true
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("FeedLaunchLoadingDidFinish"), object: nil, queue: .main) { [weak self] _ in
            self?.isGloballyMuted = false
        }
    }

    func register(_ player: AVPlayer) {
        players.add(player)
        player.volume = 1.0
        player.isMuted = isGloballyMuted
    }

    func playExclusively(_ player: AVPlayer) {
        configureAudiblePlaybackSession()
        player.volume = 1.0
        player.isMuted = isGloballyMuted
        // Pause everyone else first
        for p in players.allObjects {
            if p != player {
                p.pause()
            }
        }
        if currentPlayer !== player {
            currentPlayer = player
            NotificationCenter.default.post(name: .ActiveFeedPlayerDidChange, object: player)
        }
        player.play()
    }

    func enableAudiblePlayback() {
        configureAudiblePlaybackSession()
        isGloballyMuted = false
    }

    var activePlayer: AVPlayer? {
        currentPlayer
    }

    func stopAll() {
        for p in players.allObjects {
            p.pause()
            p.replaceCurrentItem(with: nil)
        }
        players.removeAllObjects()
        currentPlayer = nil
        NotificationCenter.default.post(name: .ActiveFeedPlayerDidChange, object: nil)
    }

    private func configureAudiblePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("[FeedAudioManager] Failed to configure playback audio session: \(error)")
        }
    }
}
