import Foundation
import UIKit

// MARK: - Bumper State

enum BumperState: Equatable {
    case idle
    case generating
    case ready(BumperPayload)
    case failed

    static func == (lhs: BumperState, rhs: BumperState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.generating, .generating), (.failed, .failed): return true
        case (.ready(let a), .ready(let b)): return a == b
        default: return false
        }
    }

    var payload: BumperPayload? {
        if case .ready(let payload) = self { return payload }
        return nil
    }
}

struct BumperPayload: Equatable, Identifiable {
    let id: String
    let script: String
    let audioData: Data?
}

// MARK: - Bumper Service
// Generates a Claude script, then speaks it via ElevenLabs.
// Both have free tiers — no payment required.

@MainActor
final class BumperService: ObservableObject {
    static let shared = BumperService()

    @Published private(set) var bumpers: [String: BumperState] = [:]

    private struct GenerationRequest {
        let post: FeedPost
        let channelName: String
        let channelID: String
    }

    private struct ActiveGeneration {
        let token: UUID
        let task: Task<Void, Never>
    }

    // A bumper can contain encoded speech, so an item count alone is not a
    // sufficient ownership bound. These are deliberately absolute rather than
    // scaled to device RAM: scrolling farther must never let the feed retain an
    // ever larger speech library.
    private let itemLimit = 24
    private let audioByteLimit = 4 * 1_024 * 1_024
    private let pendingGenerationLimit = 8
    private let concurrentGenerationLimit = 2

    private var accessOrder: [String] = []
    private var generationTasks: [String: ActiveGeneration] = [:]
    private var pendingGenerations: [GenerationRequest] = []
    private var lifecycleObservers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.cancelGenerationAndPurge() }
            },
            center.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.cancelGenerationAndPurge() }
            },
        ]
    }

    deinit {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        generationTasks.values.forEach { $0.task.cancel() }
    }

    var isConfigured: Bool { ElevenLabsService.shared.isConfigured }

    // MARK: - Public API

    func activate(_ post: FeedPost, channelName: String = "General", channelID: String = "") -> BumperPayload {
        if let payload = bumpers[post.id]?.payload {
            touch(post.id)
            return payload
        }

        let language = resolveLanguage(post: post, channelID: channelID)
        let fallback = BumperPayload(
            id: post.id,
            script: fallbackScript(for: post, channelName: channelName, language: language),
            audioData: nil
        )
        store(.ready(fallback), for: post.id)
        generateIfNeeded(post, channelName: channelName, channelID: channelID)
        return fallback
    }

    func prefetch(_ post: FeedPost, channelName: String = "General", channelID: String = "") {
        generateIfNeeded(post, channelName: channelName, channelID: channelID)
    }

    func reset(postID: String) {
        generationTasks.removeValue(forKey: postID)?.task.cancel()
        pendingGenerations.removeAll { $0.post.id == postID }
        bumpers.removeValue(forKey: postID)
        accessOrder.removeAll { $0 == postID }
        startQueuedGenerationsIfPossible()
    }

    // MARK: - Generation Pipeline

    private func generateIfNeeded(_ post: FeedPost, channelName: String, channelID: String) {
        guard generationTasks[post.id] == nil,
              !pendingGenerations.contains(where: { $0.post.id == post.id }) else {
            touch(post.id)
            return
        }

        if bumpers[post.id] == nil {
            store(.generating, for: post.id)
        } else {
            touch(post.id)
        }

        let request = GenerationRequest(post: post, channelName: channelName, channelID: channelID)
        if pendingGenerations.count >= pendingGenerationLimit,
           let dropped = pendingGenerations.first {
            pendingGenerations.removeFirst()
            if case .generating? = bumpers[dropped.post.id] {
                store(.failed, for: dropped.post.id)
            }
        }
        pendingGenerations.append(request)
        startQueuedGenerationsIfPossible()
    }

    private func startQueuedGenerationsIfPossible() {
        while generationTasks.count < concurrentGenerationLimit,
              !pendingGenerations.isEmpty {
            let request = pendingGenerations.removeFirst()
            let postID = request.post.id
            let token = UUID()
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                let state = await self.generate(
                    request.post,
                    channelName: request.channelName,
                    channelID: request.channelID
                )
                guard !Task.isCancelled else {
                    self.generationDidFinish(postID: postID, token: token, state: nil)
                    return
                }
                self.generationDidFinish(postID: postID, token: token, state: state)
            }
            generationTasks[postID] = ActiveGeneration(token: token, task: task)
        }
    }

    private func generationDidFinish(postID: String, token: UUID, state: BumperState?) {
        guard generationTasks[postID]?.token == token else { return }
        generationTasks.removeValue(forKey: postID)
        if let state { store(state, for: postID) }
        startQueuedGenerationsIfPossible()
    }

    private func generate(_ post: FeedPost, channelName: String, channelID: String) async -> BumperState {
        let language = resolveLanguage(post: post, channelID: channelID)
        do {
            let script = try await generateScript(for: post, channelName: channelName, language: language)
            try Task.checkCancellation()
            let data: Data?
            if isConfigured {
                let voice: ElevenLabsService.Voice = language == .french ? .french : .english
                data = try? await ElevenLabsService.shared.audioData(for: script, voice: voice)
            } else {
                data = nil
            }
            if Task.isCancelled { return .failed }
            // A single unexpectedly large response cannot consume the whole
            // application-owned bumper budget. Keep the script and let the
            // normal speech fallback present it without retaining the bytes.
            let boundedData = data.flatMap { $0.count <= audioByteLimit ? $0 : nil }
            return .ready(BumperPayload(id: post.id, script: script, audioData: boundedData))
        } catch {
            if bumpers[post.id]?.payload == nil {
                return .failed
            }
            return bumpers[post.id] ?? .failed
        }
    }

    private func store(_ state: BumperState, for postID: String) {
        bumpers[postID] = state
        touch(postID)
        enforceRetentionLimits()
    }

    private func touch(_ postID: String) {
        accessOrder.removeAll { $0 == postID }
        accessOrder.append(postID)
    }

    private func retainedAudioByteCount() -> Int {
        bumpers.values.reduce(into: 0) { total, state in
            total += state.payload?.audioData?.count ?? 0
        }
    }

    private func enforceRetentionLimits() {
        var cancelledActiveGeneration = false
        while bumpers.count > itemLimit || retainedAudioByteCount() > audioByteLimit {
            guard let victim = accessOrder.first else { break }
            accessOrder.removeFirst()
            bumpers.removeValue(forKey: victim)
            pendingGenerations.removeAll { $0.post.id == victim }
            if let active = generationTasks.removeValue(forKey: victim) {
                active.task.cancel()
                cancelledActiveGeneration = true
            }
        }
        if cancelledActiveGeneration {
            startQueuedGenerationsIfPossible()
        }
    }

    private func cancelGenerationAndPurge() {
        generationTasks.values.forEach { $0.task.cancel() }
        generationTasks.removeAll()
        pendingGenerations.removeAll()
        bumpers.removeAll()
        accessOrder.removeAll()
    }

    // MARK: - Language

    private func resolveLanguage(post: FeedPost, channelID: String) -> PoplurLanguage {
        let fromPost = PoplurLanguage.fromCode(post.sourceLanguageCode)
        if fromPost != .english { return fromPost }
        return AITranslationCaptionProvider.sourceLanguage(for: channelID)
    }

    // MARK: - Claude Script

    private func generateScript(for post: FeedPost, channelName: String, language: PoplurLanguage) async throws -> String {
        let parts    = [post.cityName, post.countryName].compactMap { $0 }
        let location = parts.isEmpty ? nil : parts.joined(separator: ", ")

        var context = "Channel: \(channelName)"
        if let loc = location      { context += "\nLocation: \(loc)" }
        if post.isLiveStream       { context += "\nThis is a LIVE broadcast." }
        if post.viewCount > 100    { context += "\nTrending: \(post.viewCount) views." }
        if let h = post.adHeadline { context += "\nVideo headline: \(h)" }
        if post.radius > 0 {
            let rKm = post.radius >= 1000
                ? String(format: "%.0f km", post.radius / 1000)
                : String(format: "%.0f m", post.radius)
            context += "\nRadius reach: \(rKm)"
        }

        // The host-sentence prompt lives on the backend (POST /bumper/script);
        // the device only sends the structured context and the language.
        let wireLanguage: String
        switch language {
        case .french:  wireLanguage = "french"
        case .spanish: wireLanguage = "spanish"
        case .english: wireLanguage = "english"
        }

        do {
            let script = try await PoplurAIBackendClient()
                .bumperScript(context: context, language: wireLanguage)
            return script.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return fallbackScript(for: post, channelName: channelName, language: language)
        }
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
