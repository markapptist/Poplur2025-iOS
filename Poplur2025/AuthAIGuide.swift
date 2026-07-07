import SwiftUI
import AVFoundation

// MARK: - Screen context

enum AuthAIScreen {
    case welcome, login, signUp

    var greeting: String {
        switch self {
        case .welcome:
            return "Welcome to Poplur — every post has a reach radius you control, from your block to the whole planet. Tap Sign Up to join, or Sign In to come back."
        case .login:
            return "Good to have you back. Enter your email and password. If you need a reset, tap FORGOT."
        case .signUp:
            return "Let's get you set up. Choose personal for your own posts, or business if you represent a brand."
        }
    }

    var systemPrompt: String {
        switch self {
        case .welcome:
            return "You are Poplur's onboarding guide. Poplur is a location-based social app — every post has a radius that controls how far it reaches. Answer in 1-2 warm, friendly sentences."
        case .login:
            return "You are Poplur's sign-in helper. The user is logging in with email and password. If stuck, they can tap FORGOT to reset. Answer in 1-2 sentences."
        case .signUp:
            return "You are Poplur's sign-up guide. Personal accounts are for individual creators; business accounts unlock brand features. Answer in 1-2 friendly sentences."
        }
    }
}

// MARK: - View model

@MainActor
final class AuthAIGuideVM: ObservableObject {
    @Published var displayedText = ""
    @Published var isTyping = false
    @Published var isExpanded = false
    @Published var userInput = ""
    @Published var isAwaiting = false

    private let screen: AuthAIScreen
    private var typingTask: Task<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()

    init(screen: AuthAIScreen) {
        self.screen = screen
    }

    /// Speaks the guide text aloud. Respects the shared pre-login mute toggle so the
    /// PoplurMuteButton silences the AI voice along with the background music.
    private func speak(_ text: String) {
        guard !UserDefaults.standard.bool(forKey: "poplur_prelogin_music_muted") else { return }
        // Ensure an audible, mixable playback session (works even if the music player hasn't
        // started yet, and even with the ring/silent switch on).
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.06
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func startGreeting() {
        guard displayedText.isEmpty else { return }
        typeText(screen.greeting, delay: 22_000_000)
    }

    func send() {
        let q = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isAwaiting else { return }
        userInput = ""
        isExpanded = false
        isAwaiting = true
        typingTask?.cancel()
        displayedText = ""
        Task {
            let answer = await callClaude(question: q)
            isAwaiting = false
            typeText(answer, delay: 18_000_000)
        }
    }

    private func typeText(_ text: String, delay: UInt64) {
        typingTask?.cancel()
        speak(text)
        typingTask = Task {
            isTyping = true
            for char in text {
                guard !Task.isCancelled else { return }
                displayedText.append(char)
                try? await Task.sleep(nanoseconds: delay)
            }
            isTyping = false
        }
    }

    private func callClaude(question: String) async -> String {
        let key = UserDefaults.standard.string(forKey: "poplur_claude_key") ?? Secrets.claudeAPIKey
        guard !key.isEmpty, let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            return screen.greeting
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 10
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 80,
            "system": screen.systemPrompt,
            "messages": [["role": "user", "content": question]]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return screen.greeting
        }
        req.httpBody = bodyData
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = (json["content"] as? [[String: Any]])?.first,
               let text = content["text"] as? String {
                return text
            }
        } catch {}
        return screen.greeting
    }
}

// MARK: - Guide view

struct AuthAIGuide: View {
    let screen: AuthAIScreen
    @StateObject private var vm: AuthAIGuideVM

    init(screen: AuthAIScreen) {
        self.screen = screen
        _vm = StateObject(wrappedValue: AuthAIGuideVM(screen: screen))
    }

    var body: some View {
        // Poplur AI is HEARD, not seen — no visible card. It just speaks its greeting on appear
        // (see AuthAIGuideVM.startGreeting → speak). Zero-size so it never affects layout.
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onAppear { vm.startGreeting() }
    }
}

// MARK: - Typing dots

struct AuthAITypingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.36, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(phase == i ? 1.0 : 0.3))
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: phase)
            }
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}
