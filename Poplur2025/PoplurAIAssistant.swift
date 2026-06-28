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
    private var isEnabled = false
    private var permissionRequested = false
    private var lastHandledText = ""

    var isAvailable: Bool {
        speechRecognizer?.isAvailable == true
    }

    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        requestPermissionsIfNeeded()
    }

    func stop() {
        isEnabled = false
        wakeTask?.cancel()
        wakeTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        isIlluminated = false
        isListeningForCommand = false
        statusText = "Say Hey Poplur"
    }

    func showWakeTutorialPulse() {
        wakeTask?.cancel()
        isIlluminated = true
        isListeningForCommand = false
        statusText = "Say Hey Poplur"
        wakeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            self.isIlluminated = false
            self.isListeningForCommand = false
            self.statusText = "Say Hey Poplur"
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
                        self.statusText = "Enable microphone and speech access"
                    }
                }
            }
        }
    }

    private func beginListeningIfAuthorized() {
        guard isEnabled else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            statusText = "Speech access is off"
            return
        }
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            statusText = "Microphone access is off"
            return
        }
        restartRecognition()
    }

    private func restartRecognition() {
        guard isEnabled else { return }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let text = result?.bestTranscription.formattedString {
                        self.handleRecognized(text)
                    }
                    if error != nil || result?.isFinal == true {
                        self.scheduleRecognitionRestart()
                    }
                }
            }
            statusText = "Say Hey Poplur"
        } catch {
            statusText = "Poplur AI could not start listening"
        }
    }

    private func scheduleRecognitionRestart() {
        guard isEnabled else { return }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.restartRecognition()
        }
    }

    private func handleRecognized(_ text: String) {
        transcript = text
        let normalized = Self.normalize(text)
        guard normalized != lastHandledText else { return }

        if let wakeRange = Self.wakePhraseRange(in: normalized) {
            lastHandledText = normalized
            let commandText = normalized[wakeRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            activateWake()
            if !commandText.isEmpty {
                emitCommand(Self.parse(commandText))
            }
            return
        }

        if isListeningForCommand, !normalized.isEmpty {
            lastHandledText = normalized
            emitCommand(Self.parse(normalized))
        }
    }

    private func activateWake() {
        wakeTask?.cancel()
        isIlluminated = true
        isListeningForCommand = true
        statusText = "Listening"
        wakeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            self.isListeningForCommand = false
            self.isIlluminated = false
            self.statusText = "Say Hey Poplur"
        }
    }

    private func emitCommand(_ command: PoplurAICommand) {
        wakeTask?.cancel()
        lastCommand = command
        commandToken += 1
        isIlluminated = true
        isListeningForCommand = false
        statusText = Self.feedback(for: command)
        wakeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            self.isIlluminated = false
            self.statusText = "Say Hey Poplur"
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
        text.lowercased()
            .replacingOccurrences(of: "pop blur", with: "poplur")
            .replacingOccurrences(of: "pop lure", with: "poplur")
            .replacingOccurrences(of: "popler", with: "poplur")
            .replacingOccurrences(of: "popular", with: "poplur")
            .replacingOccurrences(of: "poplar", with: "poplur")
    }

    private static func wakePhraseRange(in text: String) -> Range<String.Index>? {
        ["hey populr", "hey poplur", "okay poplur", "ok poplur"].compactMap { phrase in
            text.range(of: phrase)
        }.first
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

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if controller.isIlluminated {
                    assistantEdges(in: proxy)
                        .transition(.opacity)

                    VStack {
                        Spacer()
                        Text(controller.statusText)
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.52), in: Capsule())
                            .overlay(Capsule().stroke(accent.opacity(0.9), lineWidth: 1))
                            .shadow(color: accent.opacity(0.72), radius: 16)
                            .padding(.bottom, proxy.safeAreaInsets.bottom + 120)
                    }
                    .transition(.opacity)
                }
            }
            .onChange(of: controller.isIlluminated) { _, active in
                if active {
                    pulse = false
                    withAnimation(.easeInOut(duration: 0.78).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                } else {
                    pulse = false
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.18), value: controller.isIlluminated)
    }

    private func assistantEdges(in proxy: GeometryProxy) -> some View {
        let line = pulse ? 18.0 : 10.0
        let opacity = pulse ? 0.95 : 0.62

        return ZStack {
            EdgeGlowEdge(edge: .top, thickness: line)
                .fill(accent.opacity(opacity))
                .blur(radius: 10)
            EdgeGlowEdge(edge: .bottom, thickness: line)
                .fill(accent.opacity(opacity))
                .blur(radius: 10)
            EdgeGlowEdge(edge: .leading, thickness: line)
                .fill(accent.opacity(opacity))
                .blur(radius: 10)
            EdgeGlowEdge(edge: .trailing, thickness: line)
                .fill(accent.opacity(opacity))
                .blur(radius: 10)
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
        .shadow(color: accent.opacity(0.9), radius: pulse ? 28 : 18)
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
