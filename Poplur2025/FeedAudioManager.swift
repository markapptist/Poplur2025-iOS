import Foundation
import AVFoundation

final class FeedAudioManager {
    static let shared = FeedAudioManager()

    // Keep weak references so players can deallocate
    private let players = NSHashTable<AVPlayer>.weakObjects()

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
        player.play()
    }

    func stopAll() {
        for p in players.allObjects {
            p.pause()
            p.replaceCurrentItem(with: nil)
        }
        players.removeAllObjects()
    }
}
