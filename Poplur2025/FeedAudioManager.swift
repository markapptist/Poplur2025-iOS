import Foundation
import AVFoundation

extension Notification.Name {
    static let poplurEQSyncChanged = Notification.Name("PoplurEQSyncChanged")
}

final class PoplurEQSync {
    static let shared = PoplurEQSync()

    enum Lane: Hashable {
        case mapRadio
        case feedBumper
        case feedVideo
        case rainAmbient
        case cityMusic
        case holdMenu
        case transientFX
    }

    private var activeLanes: Set<Lane> = []
    private var lastTransientSoundAt: TimeInterval = 0
    private var lastMenuClickAt: TimeInterval = 0

    private init() {}

    func begin(_ lane: Lane) {
        let changed = !activeLanes.contains(lane)
        activeLanes.insert(lane)
        if changed { notifyChanged() }
    }

    func end(_ lane: Lane) {
        let changed = activeLanes.remove(lane) != nil
        if changed { notifyChanged() }
    }

    func isActive(_ lane: Lane) -> Bool {
        activeLanes.contains(lane)
    }

    var isVoiceActive: Bool {
        activeLanes.contains(.mapRadio) || activeLanes.contains(.feedBumper)
    }

    var rainVolumeMultiplier: Float {
        if isVoiceActive { return 0.22 }
        if activeLanes.contains(.feedVideo) { return 0.45 }
        return 1.0
    }

    var cityMusicMultiplier: Float {
        if isVoiceActive { return 0.11 }
        if activeLanes.contains(.rainAmbient) { return 0.72 }
        return 1.0
    }

    var feedVideoVolumeMultiplier: Float {
        activeLanes.contains(.feedBumper) ? 0.12 : 1.0
    }

    func shouldPlayMenuClick() -> Bool {
        guard !isVoiceActive else { return false }
        let now = Date().timeIntervalSinceReferenceDate
        let minimumInterval: TimeInterval = activeLanes.contains(.holdMenu) ? 0.060 : 0.075
        guard now - lastMenuClickAt >= minimumInterval else { return false }
        lastMenuClickAt = now
        return true
    }

    func shouldPlayTransientSound(minimumInterval: TimeInterval = 0.12) -> Bool {
        guard !isVoiceActive else { return false }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastTransientSoundAt >= minimumInterval else { return false }
        lastTransientSoundAt = now
        return true
    }

    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .poplurEQSyncChanged, object: self)
        }
    }
}

final class FeedAudioManager {
    static let shared = FeedAudioManager()

    // Keep weak references so players can deallocate
    private let players = NSHashTable<AVPlayer>.weakObjects()
    private weak var currentPlayer: AVPlayer?
    private var eqObserver: NSObjectProtocol?

    var isGloballyMuted: Bool = false {
        didSet {
            for p in players.allObjects {
                p.isMuted = isGloballyMuted
                if !isGloballyMuted {
                    p.volume = PoplurEQSync.shared.feedVideoVolumeMultiplier
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
        eqObserver = NotificationCenter.default.addObserver(forName: .poplurEQSyncChanged, object: nil, queue: .main) { [weak self] _ in
            self?.applyEQSync()
        }
    }

    deinit {
        if let eqObserver {
            NotificationCenter.default.removeObserver(eqObserver)
        }
    }

    func register(_ player: AVPlayer) {
        players.add(player)
        player.volume = PoplurEQSync.shared.feedVideoVolumeMultiplier
        player.isMuted = isGloballyMuted
    }

    func unregister(_ player: AVPlayer) {
        players.remove(player)
        if currentPlayer === player {
            currentPlayer = nil
            PoplurEQSync.shared.end(.feedVideo)
            NotificationCenter.default.post(name: .ActiveFeedPlayerDidChange, object: nil)
        } else if currentPlayer == nil || players.allObjects.isEmpty {
            PoplurEQSync.shared.end(.feedVideo)
        }
    }

    func playExclusively(_ player: AVPlayer) {
        configureAudiblePlaybackSession()
        PoplurEQSync.shared.begin(.feedVideo)
        player.volume = PoplurEQSync.shared.feedVideoVolumeMultiplier
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
        PoplurEQSync.shared.end(.feedVideo)
        NotificationCenter.default.post(name: .ActiveFeedPlayerDidChange, object: nil)
    }

    private func applyEQSync() {
        let targetVolume = PoplurEQSync.shared.feedVideoVolumeMultiplier
        for player in players.allObjects {
            player.volume = targetVolume
        }
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
