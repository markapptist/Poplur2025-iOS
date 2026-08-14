import Foundation
import AVFoundation
import UIKit

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
            // Voice overlays share the playback session already used by Feed and Map.
            // Re-applying that category as an overlay restarts the audio I/O path
            // and is heard as a skip. Wake-word recognition restores its session
            // explicitly after the microphone is stopped.
            if lane == .feedBumper && !isActive(.feedVideo) {
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
        guard UIApplication.shared.applicationState == .active else { return false }
        guard !isVoiceActive else { return false }
        return withLock { state in
            let now = Date().timeIntervalSinceReferenceDate
            guard now - state.lastTransientSoundAt >= minimumInterval else { return false }
            state.lastTransientSoundAt = now
            return true
        }
    }

    /// Ensures a short in-app effect can play without changing the active media
    /// session. Category/mode changes restart the audio I/O path and briefly cut Feed
    /// playback, so preserve the current app-audio role whenever one is active.
    func prepareAudioSessionForTransientSound() {
        guard !isAppAudioActive else { return }
        configureAudioSession(for: .ambientPlayback)
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
                // Mode is `.default`, NOT `.measurement`.
                //
                // `.measurement` disables the system's output gain/DSP. That is
                // fine for a session that only listens, but "Hey Poplur" is meant
                // to listen AT ALL TIMES — so this role is effectively the app's
                // permanent session, and it was silencing everything the app
                // played. Confirmed on device: the session sat at
                // `PlayAndRecord/Measurement`, volume 1.00, Speaker, not on
                // silent — and there was no sound anywhere.
                //
                // The codebase already knew the mode kills output: the wake
                // confirmation pop (PoplurAIAssistant.playWakeConfirmationPop)
                // bumps to `.default` for 0.35s purely so that ONE cue can be
                // heard. That workaround was treating the symptom for a single
                // sound while every other sound in the app stayed muted.
                //
                // `.default` still recognises speech; `.measurement` only buys
                // marginally cleaner input by turning off processing. A slightly
                // lower wake-word accuracy is an obviously better trade than an
                // app with no audio.
                try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
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

    /// Background is an ownership boundary, not a lower-volume playback mode.
    /// Clear every stale logical lane before deactivating the process-wide audio
    /// session. The sole exception is an *actively playing* station whose user
    /// explicitly selected Settings → Radio → Outside app.
    func enforceBackgroundPolicy(preservingOutsideRadio: Bool) {
        let changed = withLock { state -> Bool in
            let previous = state.activeLanes
            if preservingOutsideRadio, previous.contains(.mapRadio) {
                state.activeLanes = [.mapRadio]
                state.currentAudioSessionRole = .mixedPlayback
            } else {
                state.activeLanes.removeAll(keepingCapacity: false)
                state.currentAudioSessionRole = preservingOutsideRadio ? .mixedPlayback : nil
            }
            return previous != state.activeLanes
        }

        if !preservingOutsideRadio {
            do {
                try AVAudioSession.sharedInstance().setActive(
                    false,
                    options: [.notifyOthersOnDeactivation]
                )
            } catch {
                PoplurDiagLog.append("[BackgroundFence] audio deactivation failed: \(error)")
            }
        }
        if changed { notifyChanged() }
    }

    func diagnosticsLine() -> String {
        withLock { state in
            let lanes = state.activeLanes.map { lane -> String in
                switch lane {
                case .mapRadio: return "mapRadio"
                case .feedBumper: return "feedBumper"
                case .feedVideo: return "feedVideo"
                case .standaloneVideo: return "standaloneVideo"
                case .rainAmbient: return "rainAmbient"
                case .cityMusic: return "cityMusic"
                case .holdMenu: return "holdMenu"
                case .transientFX: return "transientFX"
                }
            }.sorted().joined(separator: ",")
            let role: String
            switch state.currentAudioSessionRole {
            case .ambientPlayback: role = "ambient"
            case .mixedPlayback: role = "mixed"
            case .feedPlayback: role = "feed"
            case .voicePrompt: role = "voice"
            case .wakeRecognition: role = "recognition"
            case nil: role = "none"
            }
            return "role=\(role) lanes=\(lanes.isEmpty ? "none" : lanes)"
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

/// One background authority for all process-wide owners. Individual screens
/// still tear themselves down, but this fence closes races where a late async
/// callback reactivated audio after its screen's first stop notification.
/// Nothing here runs while Poplur is the visible app.
@MainActor
final class PoplurBackgroundResourceFence {
    static let shared = PoplurBackgroundResourceFence()

    private var webRadioState = "off"
    private var webRadioScope = "screen"
    private var enteredBackgroundAt: Date?
    private var backgroundResidentBytes: UInt64?
    private var auditTask: Task<Void, Never>?
    private var graceTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    func updateWebRadio(state: String, scope: String) {
        guard ["off", "muted", "fallback", "live"].contains(state),
              ["screen", "app", "outside"].contains(scope) else { return }
        webRadioState = state
        webRadioScope = scope
    }

    func enterBackground() {
        guard enteredBackgroundAt == nil else { return }
        enteredBackgroundAt = Date()
        backgroundResidentBytes = PoplurDiagLog.residentMemoryBytes()
        snapshot(reason: "background-before-fence")
        applyFence(reason: "entry")

        if graceTaskID == .invalid {
            graceTaskID = UIApplication.shared.beginBackgroundTask(withName: "PoplurResourceFence") { [weak self] in
                Task { @MainActor in self?.finishGraceTask() }
            }
        }

        auditTask?.cancel()
        auditTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Catch AVPlayer/AudioContext promises which resolve after the first
            // lifecycle callback and try to reclaim the session.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, UIApplication.shared.applicationState == .background else {
                self.finishGraceTask()
                return
            }
            self.applyFence(reason: "one-second-recheck")
            self.snapshot(reason: "background-after-fence")
            self.finishGraceTask()

            // A suspended app will not execute these sleeps. If an allowed or
            // leaked background owner keeps the process runnable, one tiny
            // sample every five minutes gives the next device pull an RSS slope.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                guard !Task.isCancelled,
                      UIApplication.shared.applicationState == .background else { return }
                self.snapshot(reason: "background-five-minute-sample")
            }
        }
    }

    func enterForeground() {
        auditTask?.cancel()
        auditTask = nil
        finishGraceTask()
        snapshot(reason: "foreground-return")
        enteredBackgroundAt = nil
        backgroundResidentBytes = nil
    }

    private var preservesOutsideRadio: Bool {
        webRadioScope == "outside" && (webRadioState == "live" || webRadioState == "fallback")
    }

    private func applyFence(reason: String) {
        NotificationCenter.default.post(name: .StopMapAudio, object: nil)
        NotificationCenter.default.post(name: .PauseGlobalFeedAudio, object: nil)
        FeedAudioManager.shared.stopAll()
        PostLoginHomeWebView.PoplurWebSpeech.shared.cancel()
        CameraAIAnnouncer.shared.resetSession()
        PoplurEQSync.shared.enforceBackgroundPolicy(
            preservingOutsideRadio: preservesOutsideRadio
        )
        PoplurDiagLog.append(
            "[BackgroundFence] applied reason=\(reason) outsideRadio=\(preservesOutsideRadio)"
        )
    }

    private func snapshot(reason: String) {
        let resident = PoplurDiagLog.residentMemoryBytes()
        let deltaMB: String
        if let resident, let baseline = backgroundResidentBytes {
            deltaMB = String(format: "%.1f", Double(Int64(resident) - Int64(baseline)) / 1_048_576.0)
        } else {
            deltaMB = "unknown"
        }
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
        let elapsed = enteredBackgroundAt.map { String(format: "%.1f", Date().timeIntervalSince($0)) } ?? "0.0"
        let line = "[ResourceSnapshot] reason=\(reason) "
            + "rssMB=\(PoplurDiagLog.megabytes(resident)) rssDeltaMB=\(deltaMB) "
            + "backgroundFor=\(elapsed)s outsideRadio=\(preservesOutsideRadio) "
            + "webRadio=\(webRadioScope)/\(webRadioState) "
            + "audioCategory=\(session.category.rawValue) audioMode=\(session.mode.rawValue) "
            + "route=\(outputs.isEmpty ? "none" : outputs) "
            + "eq={\(PoplurEQSync.shared.diagnosticsLine())} "
            + "performance={\(PoplurPerformanceManager.shared.diagnosticsLine())}"
        PoplurDiagLog.append(line)
        captureWebSnapshot(reason: reason)
    }

    private func captureWebSnapshot(reason: String) {
        guard let webView = PostLoginHomeWebView.liveWebView else {
            PoplurDiagLog.append("[WebResourceSnapshot] reason=\(reason) webView=none")
            return
        }
        let script = """
        (() => JSON.stringify({
          audio: typeof window.__poplurAudioDebug === 'function' ? window.__poplurAudioDebug() : 'unavailable',
          radio: document.documentElement.dataset.poplurRadio || 'unset',
          radioContext: document.documentElement.dataset.poplurRadioContext || 'unset',
          displayActive: typeof window.__poplurDisplayActive === 'function' ? !!window.__poplurDisplayActive() : null,
          playingMedia: Array.from(document.querySelectorAll('audio,video')).filter(el => !el.paused).length
        }))()
        """
        webView.evaluateJavaScript(script) { value, error in
            let result = (value as? String) ?? "unavailable"
            let suffix = error.map { " error=\($0.localizedDescription)" } ?? ""
            PoplurDiagLog.append(
                "[WebResourceSnapshot] reason=\(reason) data=\(result)\(suffix)"
            )
        }
    }

    private func finishGraceTask() {
        guard graceTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(graceTaskID)
        graceTaskID = .invalid
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
