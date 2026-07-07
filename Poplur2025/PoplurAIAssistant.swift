import AVFoundation
import Speech
import SwiftUI

enum PoplurAIProfileSortOrder: String {
    case mostRadius
    case leastRadius
}

enum PoplurAICameraMode {
    case open
    case photo
    case video
}

enum PoplurAICommand {
    case openTab(AppTab)
    case openPage(String)
    case goToChannel(String)
    case postToLocation(String?)
    case camera(PoplurAICameraMode)
    case setTourActive(Bool)
    case logout
    case sortPosts(PoplurAIProfileSortOrder)
    case showAnalytics
    case unknown(String)
}

@MainActor
final class PoplurAIAssistantController: ObservableObject {
    @Published var isIlluminated = false
    @Published var isListeningForCommand = false
    @Published var transcript = ""
    @Published var statusText = "Say Hey Poplur"
    @Published private(set) var commandToken = 0

    private(set) var lastCommand: PoplurAICommand?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var wakeTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var isEnabled = false
    private var permissionRequested = false
    private var lastHandledText = ""
    private var lastHandledAt = Date.distantPast
    private var lastTranscriptUpdateAt = Date.distantPast
    private let transcriptUpdateThrottle: TimeInterval = 0.25
    private var suppressRecognitionCallbacksUntil = Date.distantPast
    private var lastRecognitionRestartAt = Date.distantPast
    private var recognitionStartedAt = Date.distantPast
    private var listeningSuppressedUntil = Date.distantPast
    private var wakeWatchdogTask: Task<Void, Never>?
    private var audioSessionObserverTokens: [NSObjectProtocol] = []
    private var eqSyncObserverToken: NSObjectProtocol?
    private var isPausedForAppAudio = false

    var isAvailable: Bool {
        speechRecognizer?.isAvailable == true
    }

    private func setStatus(_ text: String) {
        if statusText != text { statusText = text }
    }

    func start() {
        guard !isEnabled else {
            startWakeWatchdog()
            installEQSyncObserver()
            beginListeningIfAuthorized()
            return
        }
        isEnabled = true
        installAudioSessionObservers()
        installEQSyncObserver()
        startWakeWatchdog()
        requestPermissionsIfNeeded()
    }

    func stop() {
        isEnabled = false
        wakeTask?.cancel()
        wakeTask = nil
        restartTask?.cancel()
        restartTask = nil
        wakeWatchdogTask?.cancel()
        wakeWatchdogTask = nil
        removeAudioSessionObservers()
        removeEQSyncObserver()
        stopRecognitionSession(cancelTask: true, finishRequest: false)
        lastHandledText = ""
        isPausedForAppAudio = false
        isIlluminated = false
        isListeningForCommand = false
        setStatus("Say Hey Poplur")
    }

    func showWakeTutorialPulse() {
        wakeTask?.cancel()
        isIlluminated = true
        isListeningForCommand = false
        setStatus("Say Hey Poplur")
        wakeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            self.isIlluminated = false
            self.isListeningForCommand = false
            self.setStatus("Say Hey Poplur")
        }
    }

    private func requestPermissionsIfNeeded() {
        guard !permissionRequested else {
            beginListeningIfAuthorized()
            return
        }
        permissionRequested = true

        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            AVAudioSession.sharedInstance().requestRecordPermission { micGranted in
                Task { @MainActor in
                    guard let self else { return }
                    if speechStatus == .authorized, micGranted {
                        self.beginListeningIfAuthorized()
                    } else {
                        self.setStatus("Enable microphone and speech access")
                    }
                }
            }
        }
    }

    private func beginListeningIfAuthorized() {
        guard isEnabled else { return }
        guard !shouldPauseForAppAudio else {
            pauseRecognitionForAppAudio()
            return
        }
        guard speechRecognizer?.isAvailable == true else {
            setStatus("Speech recognition is unavailable")
            scheduleRecognitionRestart(delay: 1_500_000_000)
            return
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            setStatus("Speech access is off")
            return
        }
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            setStatus("Microphone access is off")
            return
        }
        restartRecognition()
    }

    private func restartRecognition() {
        guard isEnabled else { return }
        guard !shouldPauseForAppAudio else {
            pauseRecognitionForAppAudio()
            return
        }
        restartTask?.cancel()
        restartTask = nil
        isPausedForAppAudio = false

        stopRecognitionSession(cancelTask: true, finishRequest: false)

        do {
            let audioSession = AVAudioSession.sharedInstance()
            PoplurEQSync.shared.configureAudioSession(for: .wakeRecognition, force: true)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.contextualStrings = [
                "Hey Poplur",
                "Poplur",
                "Ok Poplur",
                "Yo Poplur",
                "take a photo",
                "open camera",
                "start tour",
                "go to channel",
                "show analytics"
            ]
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            guard let format = validInputFormat(for: inputNode, session: audioSession) else {
                setStatus("Microphone is warming up")
                scheduleRecognitionRestart(delay: 2_000_000_000)
                return
            }
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            recognitionStartedAt = Date()
            listeningSuppressedUntil = .distantPast

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let text = result?.bestTranscription.formattedString {
                        let now = Date()
                        if result?.isFinal == true || now.timeIntervalSince(self.lastTranscriptUpdateAt) >= self.transcriptUpdateThrottle {
                            self.lastTranscriptUpdateAt = now
                            self.handleRecognized(text)
                        }
                    }
                    guard Date() >= self.suppressRecognitionCallbacksUntil else { return }
                    if error != nil || result?.isFinal == true {
                        self.scheduleRecognitionRestart(delay: 2_000_000_000)
                    }
                }
            }
            setStatus("Say Hey Poplur")
        } catch {
            setStatus("Poplur AI could not start listening")
            scheduleRecognitionRestart(delay: 1_000_000_000)
        }
    }

    private func validInputFormat(for inputNode: AVAudioInputNode, session: AVAudioSession) -> AVAudioFormat? {
        let format = inputNode.outputFormat(forBus: 0)
        guard session.sampleRate.isFinite,
              session.sampleRate > 0,
              session.inputNumberOfChannels > 0,
              format.sampleRate.isFinite,
              format.sampleRate > 0,
              format.channelCount > 0 else {
            return nil
        }
        return format
    }

    private func scheduleRecognitionRestart(delay: UInt64 = 300_000_000) {
        guard isEnabled else { return }
        guard !shouldPauseForAppAudio else {
            pauseRecognitionForAppAudio()
            return
        }
        restartTask?.cancel()
        let now = Date()
        let secondsSinceLastRestart = now.timeIntervalSince(lastRecognitionRestartAt)
        let minimumDelay: UInt64 = 2_500_000_000
        let throttledDelay: UInt64
        if secondsSinceLastRestart < 1.5 {
            throttledDelay = max(delay, UInt64((1.5 - secondsSinceLastRestart) * 1_000_000_000))
        } else {
            throttledDelay = max(delay, minimumDelay)
        }
        suppressRecognitionCallbacksUntil = now.addingTimeInterval(0.6)
        stopRecognitionSession(cancelTask: true, finishRequest: false)

        restartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: throttledDelay)
            guard !Task.isCancelled else { return }
            if Date() < self.listeningSuppressedUntil {
                let remaining = self.listeningSuppressedUntil.timeIntervalSinceNow
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
                guard !Task.isCancelled else { return }
            }
            guard !self.shouldPauseForAppAudio else {
                self.pauseRecognitionForAppAudio()
                return
            }
            self.lastRecognitionRestartAt = Date()
            self.restartRecognition()
        }
    }

    private func startWakeWatchdog() {
        guard wakeWatchdogTask == nil else { return }
        wakeWatchdogTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 18_000_000_000)
                guard self.isEnabled, Date() >= self.listeningSuppressedUntil else { continue }
                guard !self.shouldPauseForAppAudio else {
                    self.pauseRecognitionForAppAudio()
                    continue
                }
                guard SFSpeechRecognizer.authorizationStatus() == .authorized,
                      AVAudioSession.sharedInstance().recordPermission == .granted else { continue }

                let recognitionAge = Date().timeIntervalSince(self.recognitionStartedAt)
                if !self.audioEngine.isRunning || self.recognitionTask == nil || recognitionAge > 60 {
                    self.restartRecognition()
                }
            }
        }
    }

    private func installAudioSessionObservers() {
        guard audioSessionObserverTokens.isEmpty else { return }
        let center = NotificationCenter.default
        audioSessionObserverTokens = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleRecognitionRestart(delay: 900_000_000)
                }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleRecognitionRestart(delay: 700_000_000)
                }
            }
        ]
    }

    private func removeAudioSessionObservers() {
        let center = NotificationCenter.default
        audioSessionObserverTokens.forEach { center.removeObserver($0) }
        audioSessionObserverTokens.removeAll()
    }

    private var shouldPauseForAppAudio: Bool {
        // Only pause for TTS/music output the app deliberately starts (tracked by PoplurEQSync).
        // isOtherAudioPlaying also returns true for the app's own feed video, which would permanently
        // block wake-word detection whenever the feed is visible — that's the wrong behavior.
        PoplurEQSync.shared.isAppAudioActive
    }

    private func installEQSyncObserver() {
        guard eqSyncObserverToken == nil else { return }
        eqSyncObserverToken = NotificationCenter.default.addObserver(
            forName: .poplurEQSyncChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppAudioStateChanged()
            }
        }
    }

    private func removeEQSyncObserver() {
        if let eqSyncObserverToken {
            NotificationCenter.default.removeObserver(eqSyncObserverToken)
            self.eqSyncObserverToken = nil
        }
    }

    private func handleAppAudioStateChanged() {
        guard isEnabled else { return }
        if shouldPauseForAppAudio {
            pauseRecognitionForAppAudio()
        } else if isPausedForAppAudio {
            isPausedForAppAudio = false
            beginListeningIfAuthorized()
        }
    }

    private func pauseRecognitionForAppAudio() {
        restartTask?.cancel()
        restartTask = nil
        stopRecognitionSession(cancelTask: true, finishRequest: false)
        restorePlaybackAudioSession()
        isPausedForAppAudio = true
        isListeningForCommand = false
        isIlluminated = false
        setStatus("Say Hey Poplur")
    }

    private func stopRecognitionSession(cancelTask: Bool, finishRequest: Bool) {
        if cancelTask {
            recognitionTask?.cancel()
        }
        recognitionTask = nil
        if finishRequest {
            recognitionRequest?.endAudio()
        }
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func restorePlaybackAudioSession() {
        PoplurEQSync.shared.restorePlaybackSessionAfterRecognition()
    }

    private func handleRecognized(_ text: String) {
        transcript = text
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return }
        let now = Date()
        guard normalized != lastHandledText || now.timeIntervalSince(lastHandledAt) > 0.8 else { return }

        if let wakeRange = Self.wakePhraseRange(in: normalized) {
            markHandled(normalized, at: now)
            let commandText = normalized[wakeRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            activateWake()
            if !commandText.isEmpty {
                emitCommand(Self.parse(commandText))
            }
            return
        }

        if isListeningForCommand, !normalized.isEmpty {
            markHandled(normalized, at: now)
            emitCommand(Self.parse(normalized))
        }
    }

    private func markHandled(_ text: String, at date: Date) {
        lastHandledText = text
        lastHandledAt = date
    }

    private func activateWake() {
        wakeTask?.cancel()
        isIlluminated = true
        isListeningForCommand = true
        setStatus("Listening")
        playWakeConfirmationPop()
        NotificationCenter.default.post(name: Notification.Name("PoplurWakeDetected"), object: nil)
        wakeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            self.isListeningForCommand = false
            self.isIlluminated = false
            self.lastHandledText = ""
            self.setStatus("Say Hey Poplur")
        }
    }

    /// `.wakeRecognition` runs the audio session in `.measurement` mode for cleaner
    /// speech-to-text input, but that mode also disables the output-side gain/DSP
    /// that makes the pop cue audible everywhere else it's played in the app. Bump
    /// the mode to `.default` just long enough for the pop to actually sound, then
    /// drop back to `.measurement` so recognition accuracy is unaffected.
    private func playWakeConfirmationPop() {
        let session = AVAudioSession.sharedInstance()
        let wasMeasurement = session.mode == .measurement
        if wasMeasurement {
            try? session.setMode(.default)
        }
        PoplurSoundPlayer.shared.playPop(minimumInterval: 0)
        guard wasMeasurement else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            try? AVAudioSession.sharedInstance().setMode(.measurement)
        }
    }

    private func emitCommand(_ command: PoplurAICommand) {
        wakeTask?.cancel()
        claudeTask?.cancel()
        if case .unknown(let text) = command {
            Task { @MainActor in await self.askClaude(text) }
            return
        }
        lastCommand = command
        commandToken += 1
        isIlluminated = true
        isListeningForCommand = false
        setStatus(Self.feedback(for: command))
        speak(Self.feedback(for: command))
        wakeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self.isIlluminated = false
            self.lastHandledText = ""
            self.setStatus("Say Hey Poplur")
        }
    }

    // MARK: - Claude conversational response

    @Published var aiResponse: String = ""
    @Published var isConversing: Bool = false
    private var claudeTask: Task<Void, Never>?
    private let speechSynth = AVSpeechSynthesizer()

    private func askClaude(_ question: String) async {
        await MainActor.run {
            isConversing = true
            isIlluminated = true
            setStatus("Thinking…")
            aiResponse = ""
        }
        let response = await fetchClaudeResponse(question)
        await MainActor.run {
            aiResponse = response
            setStatus(response)
            isConversing = false
        }
        speak(response)
        try? await Task.sleep(nanoseconds: UInt64(max(Double(response.count) * 55_000_000, 3_000_000_000)))
        await MainActor.run {
            isIlluminated = false
            aiResponse = ""
            lastHandledText = ""
            setStatus("Say Hey Poplur")
        }
    }

    private func fetchClaudeResponse(_ question: String) async -> String {
        guard let apiKey = UserDefaults.standard.string(forKey: "poplur_claude_key"), !apiKey.isEmpty else {
            return "I'm here! Set your Poplur API key in settings to enable full conversation."
        }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return "Something went wrong." }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 120,
            "system": "You are Poplur AI, a friendly voice assistant built into the Poplur social media app. Answer concisely in 1-2 sentences max. Be upbeat and helpful.",
            "messages": [["role": "user", "content": question]]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return "Something went wrong." }
        req.httpBody = bodyData
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = (json["content"] as? [[String: Any]])?.first,
               let text = content["text"] as? String {
                return text
            }
        } catch {}
        return "I didn't catch that. Try again!"
    }

    private func speak(_ text: String) {
        let shouldResumeListening = isEnabled
        stopRecognitionSession(cancelTask: true, finishRequest: false)
        speechSynth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.05
        utterance.volume = 0.92
        PoplurEQSync.shared.configureAudioSession(for: .voicePrompt)
        speechSynth.speak(utterance)
        if shouldResumeListening {
            let estimatedDuration = max(1.8, min(6.0, Double(text.count) * 0.055))
            listeningSuppressedUntil = Date().addingTimeInterval(estimatedDuration + 0.6)
            scheduleRecognitionRestart(delay: UInt64(estimatedDuration * 1_000_000_000))
        }
    }

    static func parse(_ commandText: String) -> PoplurAICommand {
        let text = normalize(commandText)

        if text.contains("logout") || text.contains("log out") || text.contains("sign out") {
            return .logout
        }
        if text.contains("analytics") || text.contains("stats") || text.contains("statistics") {
            return .showAnalytics
        }
        if text.contains("most radius") || text.contains("highest radius") || text.contains("largest radius") || text.contains("biggest radius") {
            return .sortPosts(.mostRadius)
        }
        if text.contains("least radius") || text.contains("lowest radius") || text.contains("smallest radius") {
            return .sortPosts(.leastRadius)
        }
        if text.contains("start tour") || text.contains("begin tour") {
            return .setTourActive(true)
        }
        if text.contains("stop tour") || text.contains("pause tour") || text.contains("end tour") {
            return .setTourActive(false)
        }
        if text.contains("take a photo") || text.contains("take photo") || text.contains("take picture") || text.contains("capture photo") {
            return .camera(.photo)
        }
        if text.contains("take a video") || text.contains("record video") || text.contains("start video") {
            return .camera(.video)
        }
        if text.contains("open camera") || text.contains("go to camera") || text.contains("open record") {
            return .camera(.open)
        }
        if text.contains("post") && (text.contains("location") || text.contains("map") || text.contains("somewhere") || text.contains("here") || text.contains("to ")) {
            return .postToLocation(extractLocation(from: text))
        }
        if let channel = extractChannel(from: text) {
            return .goToChannel(channel)
        }
        if text.contains("tv guide") {
            return .openPage("tv guide")
        }
        if text.contains("messages") || text.contains("mail") || text.contains("dm") {
            return .openPage("messages")
        }
        if text.contains("settings") {
            return .openPage("settings")
        }
        if text.contains("profile") {
            return .openTab(.profile)
        }
        if text.contains("feed") {
            return .openTab(.feed)
        }
        if text.contains("map") {
            return .openTab(.map)
        }
        return .unknown(commandText)
    }

    private static func normalize(_ text: String) -> String {
        var normalized = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        normalized = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let replacements = [
            ("pop blur", "poplur"),
            ("pop blurr", "poplur"),
            ("pop lure", "poplur"),
            ("pop lur", "poplur"),
            ("pop lour", "poplur"),
            ("popler", "poplur"),
            ("poppler", "poplur"),
            ("popular", "poplur"),
            ("poplar", "poplur")
        ]

        for (from, to) in replacements {
            normalized = normalized.replacingOccurrences(of: from, with: to)
        }

        return normalized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func wakePhraseRange(in text: String) -> Range<String.Index>? {
        if let exact = [
            "hey populr",
            "hey poplur",
            "hay poplur",
            "hi poplur",
            "okay poplur",
            "ok poplur",
            "yo poplur"
        ].compactMap({ phrase in
            text.range(of: phrase)
        }).first {
            return exact
        }

        let tokens = text.split(separator: " ")
        guard !tokens.isEmpty else { return nil }

        func isWakeLead(_ token: Substring) -> Bool {
            ["hey", "hay", "hi", "okay", "ok", "yo"].contains(String(token))
        }

        func isPoplurToken(_ token: Substring) -> Bool {
            [
                "poplur",
                "populr",
                "popular",
                "poplar",
                "popler",
                "poppler",
                "poplure",
                "poplurr"
            ].contains(String(token))
        }

        for index in tokens.indices {
            if isPoplurToken(tokens[index]), index == tokens.startIndex {
                return tokens[index].startIndex..<tokens[index].endIndex
            }

            let nextIndex = tokens.index(after: index)
            if nextIndex < tokens.endIndex,
               isWakeLead(tokens[index]),
               isPoplurToken(tokens[nextIndex]) {
                return tokens[index].startIndex..<tokens[nextIndex].endIndex
            }
        }

        return nil
    }

    private static func extractChannel(from text: String) -> String? {
        let channels = ["food", "beauty", "sports", "modelling", "modeling", "fashion", "music", "tech", "news", "french", "spanish", "live"]
        if text.contains("channel") || text.contains("feed") || text.contains("go to") || text.contains("open") {
            if let match = channels.first(where: { text.contains($0) }) {
                return match == "modeling" ? "modelling" : match
            }
            for number in [101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111] where text.contains("\(number)") {
                return "\(number)"
            }
        }
        return nil
    }

    private static func extractLocation(from text: String) -> String? {
        guard let range = text.range(of: " to ") ?? text.range(of: " in ") ?? text.range(of: " at ") else { return nil }
        let location = text[range.upperBound...]
            .replacingOccurrences(of: "location", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return location.isEmpty ? nil : location
    }

    private static func feedback(for command: PoplurAICommand) -> String {
        switch command {
        case .openTab(let tab): return "Opening \(tab.title)"
        case .openPage(let page): return "Opening \(page)"
        case .goToChannel(let channel): return "Tuning to \(channel)"
        case .postToLocation: return "Opening map upload"
        case .camera(let mode):
            switch mode {
            case .open: return "Opening camera"
            case .photo: return "Opening camera for photo"
            case .video: return "Opening camera for video"
            }
        case .setTourActive(let active): return active ? "Starting tour" : "Stopping tour"
        case .logout: return "Logging out"
        case .sortPosts(let order): return order == .mostRadius ? "Sorting by most radius" : "Sorting by least radius"
        case .showAnalytics: return "Opening analytics"
        case .unknown: return "I did not catch that"
        }
    }
}

struct PoplurAIAssistantOverlay: View {
    @ObservedObject var controller: PoplurAIAssistantController
    let accent: Color

    @State private var pulse = false
    @State private var wavePhase: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if controller.isIlluminated {
                    // Full-screen color wash
                    accent
                        .opacity(pulse ? 0.20 : 0.10)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    // Edge glow
                    assistantEdges(in: proxy)
                        .transition(.opacity)

                    // Status / response text
                    VStack(spacing: 0) {
                        Spacer()
                        if controller.isListeningForCommand {
                            // Animated wave while listening
                            HStack(spacing: 5) {
                                ForEach(0..<5, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(accent)
                                        .frame(width: 4, height: 8 + 18 * abs(sin(wavePhase + CGFloat(i) * 0.7)))
                                }
                            }
                            .padding(.bottom, 8)
                        }
                        VStack(spacing: 6) {
                            Text(controller.statusText)
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(4)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(.black.opacity(0.60), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.85), lineWidth: 1.5))
                                .shadow(color: accent.opacity(0.65), radius: 18)
                                .padding(.horizontal, 28)
                        }
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 110)
                    }
                    .transition(.opacity)
                }
            }
            .onChange(of: controller.isIlluminated) { _, active in
                if active {
                    pulse = false
                    wavePhase = 0
                    withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) { pulse = true }
                    withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { wavePhase = .pi * 2 }
                } else {
                    pulse = false
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.22), value: controller.isIlluminated)
    }

    private func assistantEdges(in proxy: GeometryProxy) -> some View {
        let line: CGFloat = pulse ? 22.0 : 12.0
        let opacity: Double = pulse ? 1.0 : 0.65

        return ZStack {
            EdgeGlowEdge(edge: .top, thickness: line)
                .fill(accent.opacity(opacity))
                .blur(radius: 12)
            EdgeGlowEdge(edge: .bottom, thickness: line)
                .fill(accent.opacity(opacity))
                .blur(radius: 12)
            EdgeGlowEdge(edge: .leading, thickness: line)
                .fill(accent.opacity(opacity))
                .blur(radius: 12)
            EdgeGlowEdge(edge: .trailing, thickness: line)
                .fill(accent.opacity(opacity))
                .blur(radius: 12)
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
        .shadow(color: accent.opacity(0.9), radius: pulse ? 32 : 20)
    }
}

private struct EdgeGlowEdge: Shape {
    enum Edge {
        case top
        case bottom
        case leading
        case trailing
    }

    let edge: Edge
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let frame: CGRect
        switch edge {
        case .top:
            frame = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: thickness)
        case .bottom:
            frame = CGRect(x: rect.minX, y: rect.maxY - thickness, width: rect.width, height: thickness)
        case .leading:
            frame = CGRect(x: rect.minX, y: rect.minY, width: thickness, height: rect.height)
        case .trailing:
            frame = CGRect(x: rect.maxX - thickness, y: rect.minY, width: thickness, height: rect.height)
        }
        return Path(frame)
    }
}
