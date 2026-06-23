import Foundation

// MARK: - Bumper State

enum BumperState: Equatable {
    case idle
    case generating
    case ready(audioData: Data)
    case failed

    static func == (lhs: BumperState, rhs: BumperState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.generating, .generating), (.failed, .failed): return true
        case (.ready(let a), .ready(let b)): return a == b
        default: return false
        }
    }

    var audioData: Data? {
        if case .ready(let d) = self { return d }
        return nil
    }
}

// MARK: - Bumper Service
// Generates a Claude script, then speaks it via ElevenLabs.
// Both have free tiers — no payment required.

@MainActor
final class BumperService: ObservableObject {
    static let shared = BumperService()

    @Published private(set) var bumpers: [String: BumperState] = [:]

    private var inFlight: Set<String> = []

    var isConfigured: Bool { ElevenLabsService.shared.isConfigured }

    // MARK: - Public API

    func prefetch(_ post: FeedPost, channelName: String = "General", channelID: String = "") {
        guard isConfigured else { return }
        guard bumpers[post.id] == nil, !inFlight.contains(post.id) else { return }
        inFlight.insert(post.id)
        bumpers[post.id] = .generating

        Task { [weak self] in
            await self?.generate(post, channelName: channelName, channelID: channelID)
        }
    }

    func reset(postID: String) {
        bumpers.removeValue(forKey: postID)
        inFlight.remove(postID)
    }

    // MARK: - Generation Pipeline

    private func generate(_ post: FeedPost, channelName: String, channelID: String) async {
        defer { inFlight.remove(post.id) }
        let language = resolveLanguage(post: post, channelID: channelID)
        do {
            let script = try await generateScript(for: post, channelName: channelName, language: language)
            let voice: ElevenLabsService.Voice = language == .french ? .french : .english
            let data = try await ElevenLabsService.shared.audioData(for: script, voice: voice)
            bumpers[post.id] = .ready(audioData: data)
        } catch {
            bumpers[post.id] = .failed
        }
    }

    // MARK: - Language

    private func resolveLanguage(post: FeedPost, channelID: String) -> PoplurLanguage {
        let fromPost = PoplurLanguage.fromCode(post.sourceLanguageCode)
        if fromPost != .english { return fromPost }
        return AITranslationCaptionProvider.sourceLanguage(for: channelID)
    }

    // MARK: - Claude Script

    private func generateScript(for post: FeedPost, channelName: String, language: PoplurLanguage) async throws -> String {
        let claudeKey = UserDefaults.standard.string(forKey: "poplur_claude_key") ?? Secrets.claudeAPIKey
        guard !claudeKey.isEmpty else {
            return fallbackScript(for: post, channelName: channelName, language: language)
        }

        let parts    = [post.cityName, post.countryName].compactMap { $0 }
        let location = parts.isEmpty ? nil : parts.joined(separator: ", ")

        var context = "Channel: \(channelName)"
        if let loc = location      { context += "\nLocation: \(loc)" }
        if post.isLiveStream       { context += "\nThis is a LIVE broadcast." }
        if post.viewCount > 100    { context += "\nTrending: \(post.viewCount) views." }
        if let h = post.adHeadline { context += "\nVideo headline: \(h)" }

        let langLine: String
        switch language {
        case .french:  langLine = "Write the sentence in French (français). Sound like a natural French TV presenter."
        case .spanish: langLine = "Write the sentence in Spanish (español). Sound like a natural Spanish TV presenter."
        case .english: langLine = "Write the sentence in English. Sound like a natural English-speaking TV presenter."
        }

        let prompt = """
        You are a charismatic TV host for Poplur, a social video app. \
        Using the details below, write ONE natural spoken sentence (12–22 words) that a host \
        would say live on air to introduce the next video. \
        Reference the channel and location naturally — don't just list them. \
        Be warm, specific, and engaging. Vary your phrasing. \
        \(langLine) \
        Return ONLY the spoken sentence — no quotes, no labels, no extra text.

        \(context)
        """

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(claudeKey,          forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 80,
            "messages": [["role": "user", "content": prompt]]
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            return fallbackScript(for: post, channelName: channelName, language: language)
        }

        let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = (json?["content"] as? [[String: Any]])?.first
        let text    = (content?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text ?? fallbackScript(for: post, channelName: channelName, language: language)
    }

    private func fallbackScript(for post: FeedPost, channelName: String, language: PoplurLanguage) -> String {
        let parts    = [post.cityName, post.countryName].compactMap { $0 }
        let location = parts.joined(separator: ", ")
        switch language {
        case .french:
            if !location.isEmpty {
                return post.isLiveStream
                    ? "En direct depuis \(location) sur la chaîne \(channelName) — ne bougez pas."
                    : "Juste après, sur la chaîne \(channelName) — une vidéo en provenance de \(location)."
            }
            return "La prochaine vidéo arrive sur Poplur \(channelName) — restez avec nous."
        case .spanish:
            if !location.isEmpty {
                return post.isLiveStream
                    ? "En vivo desde \(location) en el canal \(channelName) — no te vayas."
                    : "A continuación en \(channelName) — contenido llegando desde \(location)."
            }
            return "El próximo video ya viene en Poplur \(channelName) — quédate."
        case .english:
            if !location.isEmpty {
                return post.isLiveStream
                    ? "Coming up — a live \(channelName.lowercased()) broadcast from \(location). Stay right here."
                    : "Next up on \(channelName) — fresh content just in from \(location)."
            }
            return "Coming up on \(channelName) — the next video is on its way. Don't go anywhere."
        }
    }
}
