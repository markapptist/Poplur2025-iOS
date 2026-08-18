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
    private var hasGreeted = false

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
        // Heard, not seen: speak the greeting once. No typewriter — appending to displayedText
        // per character re-rendered the confetti-heavy pre-login view ~150x for nothing (lag).
        guard !hasGreeted else { return }
        hasGreeted = true
        speak(screen.greeting)
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

    // Pre-login, so this goes through the backend's unauthenticated,
    // rate-limited guest route; the per-screen system prompt lives server-side.
    private func callClaude(question: String) async -> String {
        let wireScreen: String
        switch screen {
        case .welcome: wireScreen = "welcome"
        case .login:   wireScreen = "login"
        case .signUp:  wireScreen = "signUp"
        }
        do {
            return try await PoplurAIBackendClient()
                .authGuideReply(screen: wireScreen, question: question)
        } catch {
            return screen.greeting
        }
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
