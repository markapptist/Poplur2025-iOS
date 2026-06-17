import Foundation
import AVFoundation

final class FeedAudioManager {
    static let shared = FeedAudioManager()

    // Keep weak references so players can deallocate
    private let players = NSHashTable<AVPlayer>.weakObjects()
    private weak var currentPlayer: AVPlayer?

    private init() {
        NotificationCenter.default.addObserver(forName: Notification.Name("PauseGlobalFeedAudio"), object: nil, queue: .main) { [weak self] _ in
            self?.stopAll()
        }
    }

    func register(_ player: AVPlayer) {
        players.add(player)
    }

    func playExclusively(_ player: AVPlayer) {
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
}
