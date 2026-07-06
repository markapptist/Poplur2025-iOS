import Foundation
import AVFoundation

extension Notification.Name {
    static let poplurEQSyncChanged = Notification.Name("PoplurEQSyncChanged")
}

final class PoplurEQSync {
    static let shared = PoplurEQSync()

    enum AudioSessionRole: Equatable {
        case ambientPlayback
        case mixedPlayback
        case feedPlayback
        case voicePrompt
        case wakeRecognition
    }

    enum Lane: Hashable {
        case mapRadio
        case feedBumper
        case feedVideo
        case standaloneVideo
        case rainAmbient
        case cityMusic
        case holdMenu
        case transientFX
    }

    private var activeLanes: Set<Lane> = []
    private var lastTransientSoundAt: TimeInterval = 0
    private var lastMenuClickAt: TimeInterval = 0
    private var currentAudioSessionRole: AudioSessionRole?
    private let lock = NSLock()

    private init() {}

    func begin(_ lane: Lane) {
        let changed = withLock {
            let changed = !$0.activeLanes.contains(lane)
            $0.activeLanes.insert(lane)
            return changed
        }
        if changed { notifyChanged() }
    }

    func end(_ lane: Lane) {
        let changed = withLock { $0.activeLanes.remove(lane) != nil }
        if changed {
            if lane == .feedBumper || lane == .mapRadio {
                restorePlaybackSessionAfterRecognition()
            }
            notifyChanged()
        }
    }

    func isActive(_ lane: Lane) -> Bool {
        withLock { $0.activeLanes.contains(lane) }
    }

    var isVoiceActive: Bool {
        withLock { state in
            state.activeLanes.contains(.mapRadio) || state.activeLanes.contains(.feedBumper)
        }
    }

    var isAppAudioActive: Bool {
        withLock { state in
            state.activeLanes.contains(.mapRadio)
                || state.activeLanes.contains(.feedBumper)
                || state.activeLanes.contains(.feedVideo)
                || state.activeLanes.contains(.standaloneVideo)
                || state.activeLanes.contains(.rainAmbient)
                || state.activeLanes.contains(.cityMusic)
        }
    }

    var rainVolumeMultiplier: Float {
        if isVoiceActive { return 0.22 }
        if isActive(.feedVideo) { return 0.45 }
        return 1.0
    }

    var cityMusicMultiplier: Float {
        if isVoiceActive { return 0.11 }
        if isActive(.rainAmbient) { return 0.72 }
        return 1.0
    }

    var feedVideoVolumeMultiplier: Float {
        isActive(.feedBumper) ? 0.12 : 1.0
    }

    func shouldPlayMenuClick() -> Bool {
        guard !isVoiceActive else { return false }
        return withLock { state in
            let now = Date().timeIntervalSinceReferenceDate
            let minimumInterval: TimeInterval = state.activeLanes.contains(.holdMenu) ? 0.060 : 0.075
            guard now - state.lastMenuClickAt >= minimumInterval else { return false }
            state.lastMenuClickAt = now
            return true
        }
    }

    func shouldPlayTransientSound(minimumInterval: TimeInterval = 0.12) -> Bool {
        guard !isVoiceActive else { return false }
        return withLock { state in
            let now = Date().timeIntervalSinceReferenceDate
            guard now - state.lastTransientSoundAt >= minimumInterval else { return false }
            state.lastTransientSoundAt = now
            return true
        }
    }

    func configureAudioSession(for role: AudioSessionRole, force: Bool = false) {
        let shouldApply = withLock { state -> Bool in
            guard force || state.currentAudioSessionRole != role else { return false }
            state.currentAudioSessionRole = role
            return true
        }
        guard shouldApply else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            switch role {
            case .ambientPlayback:
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try session.setActive(true, options: [])
            case .mixedPlayback:
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true, options: [])
            case .feedPlayback:
                try session.setCategory(.playback, mode: .moviePlayback, options: [])
                try session.setActive(true, options: [])
            case .voicePrompt:
                try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
                try session.setActive(true, options: [])
            case .wakeRecognition:
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            }
        } catch {
            withLock { state in
                if state.currentAudioSessionRole == role {
                    state.currentAudioSessionRole = nil
                }
            }
            print("[PoplurEQSync] Audio session setup failed for \(role): \(error)")
        }
    }

    func restorePlaybackSessionAfterRecognition() {
        if isActive(.feedVideo) || isActive(.standaloneVideo) {
            configureAudioSession(for: .feedPlayback, force: true)
        } else if isActive(.mapRadio) || isActive(.rainAmbient) || isActive(.cityMusic) || isActive(.feedBumper) {
            configureAudioSession(for: .mixedPlayback, force: true)
        } else {
            configureAudioSession(for: .ambientPlayback, force: true)
        }
    }

    func deactivateAudioSessionIfIdle() {
        guard !isAppAudioActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            withLock { $0.currentAudioSessionRole = nil }
        } catch {
            print("[PoplurEQSync] Audio session deactivation failed: \(error)")
        }
    }

    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .poplurEQSyncChanged, object: self)
        }
    }

    private func withLock<T>(_ body: (PoplurEQSync) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(self)
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
        PoplurEQSync.shared.configureAudioSession(for: .feedPlayback)
    }
}

// MARK: - PoplurSoundPlayer

final class PoplurSoundPlayer {
    static let shared = PoplurSoundPlayer()
    private var popPlayer: AVAudioPlayer?

    private init() {
        if let url = Bundle.main.url(forResource: "pop", withExtension: "mp3") {
            popPlayer = try? AVAudioPlayer(contentsOf: url)
            popPlayer?.prepareToPlay()
        }
    }

    func playPop(minimumInterval: TimeInterval = 0.18) {
        guard PoplurEQSync.shared.shouldPlayTransientSound(minimumInterval: minimumInterval) else { return }
        guard let p = popPlayer else { return }
        if p.isPlaying { p.stop(); p.currentTime = 0 }
        p.play()
    }
}
