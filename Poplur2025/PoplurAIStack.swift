import Foundation
import CoreLocation
import FirebaseAuth

enum PoplurAIContentType: String, CaseIterable, Codable, Sendable, Identifiable {
    case image
    case video
    case edit
    case vfx
    case vfxVideo = "vfx_video"
    case threeDModel = "3d_model"
    case voice
    case music
    case game
    case coupon
    case campaign

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .image: return "Images"
        case .video: return "Videos"
        case .edit: return "AI Edits"
        case .vfx, .vfxVideo: return "VFX"
        case .threeDModel: return "3D Characters"
        case .voice: return "Voice"
        case .music: return "Music"
        case .game: return "Games"
        case .coupon: return "Coupons"
        case .campaign: return "Campaigns"
        }
    }

    var providerLabel: String {
        "Powered by \(defaultProvider.displayName)"
    }

    var defaultProvider: PoplurAIProvider {
        switch self {
        case .image, .video, .edit:
            return .google
        case .threeDModel:
            return .meshy
        case .voice:
            return .voice
        case .music:
            return .music
        case .game:
            return .game
        case .vfx, .vfxVideo:
            return .vfx
        case .coupon, .campaign:
            return .google
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo.fill"
        case .video: return "video.fill"
        case .edit: return "wand.and.stars"
        case .vfx, .vfxVideo: return "sparkles.tv.fill"
        case .threeDModel: return "cube.transparent.fill"
        case .voice: return "waveform"
        case .music: return "music.note"
        case .game: return "gamecontroller.fill"
        case .coupon: return "ticket.fill"
        case .campaign: return "megaphone.fill"
        }
    }
}

enum PoplurAIProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case google
    case meshy
    case voice
    case music
    case game
    case vfx

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google: return "Google AI Studio"
        case .meshy: return "Meshy"
        case .voice: return "ElevenLabs"
        case .music: return "Suno"
        case .game: return "Rosebud AI"
        case .vfx: return "Poplur VFX"
        }
    }

    var requiredEnvironmentVariable: String {
        switch self {
        case .google: return "GOOGLE_AI_API_KEY"
        case .meshy: return "MESHY_API_KEY"
        case .voice: return "ELEVENLABS_API_KEY"
        case .music: return "SUNO_API_KEY"
        case .game: return "GAME_PROVIDER_API_KEY"
        case .vfx: return "VFX_PROVIDER_API_KEY"
        }
    }
}

enum PoplurAIGenerationStatus: String, CaseIterable, Codable, Sendable {
    case queued
    case processing
    case completed
    case failed
    case cancelled
}

enum CreatorCreditTransactionType: String, CaseIterable, Codable, Sendable {
    case subscriptionGrant = "subscription_grant"
    case purchasedCredits = "purchased_credits"
    case promotionalGrant = "promotional_grant"
    case referralReward = "referral_reward"
    case adReward = "ad_reward"
    case aiGenerationSpend = "ai_generation_spend"
    case radiusBoostSpend = "radius_boost_spend"
    case refund
    case adminAdjustment = "admin_adjustment"
}

enum PoplurPlan: String, CaseIterable, Codable, Sendable {
    case free
    case creator
    case business

    func canGenerateAI(with credits: Int) -> Bool {
        switch self {
        case .free:
            return credits > 0
        case .creator, .business:
            return true
        }
    }

    var canUseBusinessCampaignTools: Bool { self == .business }
}

struct PoplurAIStackConfig: Sendable {
    var providerEnabled: [PoplurAIProvider: Bool]
    var creditCostByContentType: [PoplurAIContentType: Int]
    var boostCostByTier: [RadiusBoostTier: Int]
    var maxPromptLength: Int
    var maxVideoDurationSeconds: Int
    var maxGenerationsPerUserPerDay: Int
    var freePromotionalCreditAmount: Int
    var watermarkEnabledForFreeUsers: Bool
    var providerTimeoutSeconds: TimeInterval

    static let productionDefaults = PoplurAIStackConfig(
        providerEnabled: Dictionary(uniqueKeysWithValues: PoplurAIProvider.allCases.map { ($0, true) }),
        creditCostByContentType: [
            .image: 5,
            .voice: 10,
            .music: 25,
            .threeDModel: 50,
            .game: 75,
            .video: 100,
            .edit: 100,
            .vfx: 125,
            .vfxVideo: 125,
            .coupon: 15,
            .campaign: 0
        ],
        boostCostByTier: [
            .local: 10,
            .neighborhood: 25,
            .city: 80,
            .regional: 250
        ],
        maxPromptLength: 1_000,
        maxVideoDurationSeconds: 15,
        maxGenerationsPerUserPerDay: 50,
        freePromotionalCreditAmount: 25,
        watermarkEnabledForFreeUsers: true,
        providerTimeoutSeconds: 120
    )

    func estimatedCost(for contentType: PoplurAIContentType, campaignAssets: [PoplurAIContentType] = []) -> Int {
        if contentType == .campaign {
            return campaignAssets.reduce(0) { $0 + estimatedCost(for: $1) }
        }
        return creditCostByContentType[contentType] ?? 0
    }
}

struct CreatorCreditBalance: Codable, Sendable {
    var userId: String
    var availableCredits: Int
    var reservedCredits: Int
    var updatedAt: Date

    var totalCredits: Int { availableCredits + reservedCredits }
}

struct CreatorCreditTransaction: Identifiable, Codable, Sendable {
    var id: String
    var userId: String
    var amount: Int
    var type: CreatorCreditTransactionType
    var relatedJobId: String?
    var relatedPostId: String?
    var provider: PoplurAIProvider?
    var contentType: PoplurAIContentType?
    var createdAt: Date
    var metadata: [String: String]
}

struct AIGenerationJob: Identifiable, Codable, Sendable {
    var id: String
    var userId: String
    var provider: PoplurAIProvider
    var contentType: PoplurAIContentType
    var prompt: String
    var inputAssetIds: [String]
    var status: PoplurAIGenerationStatus
    var creditsReserved: Int
    var creditsCharged: Int
    var outputAssetIds: [String]
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var metadata: [String: String]
}

struct RadiusBoostTransaction: Identifiable, Codable, Sendable {
    var id: String
    var userId: String
    var postId: String
    var tier: RadiusBoostTier
    var creditsCharged: Int
    var boostedRadiusMeters: Int
    var boostExpiresAt: Date
    var createdAt: Date
    var metadata: [String: String]
}

enum RadiusBoostTier: String, CaseIterable, Codable, Sendable, Identifiable {
    case local
    case neighborhood
    case city
    case regional

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "Local Boost"
        case .neighborhood: return "Neighborhood Boost"
        case .city: return "City Boost"
        case .regional: return "Regional Boost"
        }
    }

    var additionalRadiusMeters: Int {
        switch self {
        case .local: return 1_000
        case .neighborhood: return 5_000
        case .city: return 25_000
        case .regional: return 100_000
        }
    }

    var duration: TimeInterval { 24 * 60 * 60 }
}

struct AIMapPublishMetadata: Codable, Sendable {
    var latitude: Double
    var longitude: Double
    var locationName: String
    var address: String?
    var radiusMeters: Int
    var contentType: PoplurAIContentType
    var businessId: String?
    var campaignId: String?
    var expirationDate: Date?
    var tags: [String]
    var category: String?
}

struct AIMapPost: Identifiable, Codable, Sendable {
    var id: String
    var userId: String
    var assetIds: [String]
    var publishMetadata: AIMapPublishMetadata
    var organicRadiusMeters: Int
    var boostedRadiusMeters: Int
    var boostExpiresAt: Date?
    var engagementScore: Double
    var visibilityStatus: String
}

struct AICampaign: Identifiable, Codable, Sendable {
    var id: String
    var businessId: String
    var userId: String
    var prompt: String
    var generatedAssetIds: [String]
    var status: PoplurAIGenerationStatus
    var scheduledPublishAt: Date?
    var location: AIMapPublishMetadata
    var radiusMeters: Int
    var createdAt: Date
    var updatedAt: Date
}

struct AIGenerationRequest: Codable, Sendable {
    var userId: String
    var plan: PoplurPlan
    var contentType: PoplurAIContentType
    var prompt: String
    var inputAssetIds: [String]
    var publishMetadata: AIMapPublishMetadata?
    var campaignAssetTypes: [PoplurAIContentType]
    var metadata: [String: String]
}

struct AIProviderResponse: Codable, Sendable {
    var jobId: String
    var provider: PoplurAIProvider
    var contentType: PoplurAIContentType
    var status: PoplurAIGenerationStatus
    var estimatedCostCredits: Int
    var outputUrl: URL?
    var outputAssetId: String?
    var providerRawResponse: [String: String]
}

protocol AIProviderAdapter: Sendable {
    var provider: PoplurAIProvider { get }
    func generateImage(_ request: AIGenerationRequest) async throws -> AIProviderResponse
    func generateVideo(_ request: AIGenerationRequest) async throws -> AIProviderResponse
    func editVideo(_ request: AIGenerationRequest) async throws -> AIProviderResponse
    func generate3DModel(_ request: AIGenerationRequest) async throws -> AIProviderResponse
    func generateVoice(_ request: AIGenerationRequest) async throws -> AIProviderResponse
    func generateMusic(_ request: AIGenerationRequest) async throws -> AIProviderResponse
    func generateGame(_ request: AIGenerationRequest) async throws -> AIProviderResponse
    func generateVFX(_ request: AIGenerationRequest) async throws -> AIProviderResponse
}

enum AIStackError: LocalizedError, Equatable {
    case backendBaseURLMissing
    case providerDisabled(PoplurAIProvider)
    case promptTooLong
    case aiLockedForPlan
    case insufficientCredits
    case negativeBalanceRejected
    case unsupportedProviderMethod(PoplurAIProvider, PoplurAIContentType)
    case providerMustRunOnBackend(PoplurAIProvider)
    case backendError(Int)
    case invalidLocation

    var errorDescription: String? {
        switch self {
        case .backendBaseURLMissing:
            return "Poplur AI backend is not configured."
        case .providerDisabled(let provider):
            return "\(provider.displayName) is currently disabled."
        case .promptTooLong:
            return "Prompt is too long."
        case .aiLockedForPlan:
            return "Use Creator Credits to generate AI content."
        case .insufficientCredits:
            return "Not enough Creator Credits."
        case .negativeBalanceRejected:
            return "Creator Credit balance cannot go negative."
        case .unsupportedProviderMethod(let provider, let type):
            return "\(provider.displayName) does not support \(type.displayName)."
        case .providerMustRunOnBackend(let provider):
            return "\(provider.displayName) must be called through Poplur's backend."
        case .backendError(let status):
            return "Poplur AI returned an error (HTTP \(status)). Please try again."
        case .invalidLocation:
            return "Choose a real map location before publishing."
        }
    }
}

extension AIProviderAdapter {
    func generateImage(_ request: AIGenerationRequest) async throws -> AIProviderResponse {
        throw AIStackError.unsupportedProviderMethod(provider, request.contentType)
    }
    func generateVideo(_ request: AIGenerationRequest) async throws -> AIProviderResponse {
        throw AIStackError.unsupportedProviderMethod(provider, request.contentType)
    }
    func editVideo(_ request: AIGenerationRequest) async throws -> AIProviderResponse {
        throw AIStackError.unsupportedProviderMethod(provider, request.contentType)
    }
    func generate3DModel(_ request: AIGenerationRequest) async throws -> AIProviderResponse {
        throw AIStackError.unsupportedProviderMethod(provider, request.contentType)
    }
    func generateVoice(_ request: AIGenerationRequest) async throws -> AIProviderResponse {
        throw AIStackError.unsupportedProviderMethod(provider, request.contentType)
    }
    func generateMusic(_ request: AIGenerationRequest) async throws -> AIProviderResponse {
        throw AIStackError.unsupportedProviderMethod(provider, request.contentType)
    }
    func generateGame(_ request: AIGenerationRequest) async throws -> AIProviderResponse {
        throw AIStackError.unsupportedProviderMethod(provider, request.contentType)
    }
    func generateVFX(_ request: AIGenerationRequest) async throws -> AIProviderResponse {
        throw AIStackError.unsupportedProviderMethod(provider, request.contentType)
    }
}

struct BackendOnlyAIProvider: AIProviderAdapter {
    let provider: PoplurAIProvider

    private func placeholderResponse(for request: AIGenerationRequest) throws -> AIProviderResponse {
        // TODO: Implement this provider on Poplur's backend using provider credentials from environment variables.
        // Mobile must only call Poplur AI API endpoints and never provider APIs directly.
        throw AIStackError.providerMustRunOnBackend(provider)
    }

    func generateImage(_ request: AIGenerationRequest) async throws -> AIProviderResponse { try placeholderResponse(for: request) }
    func generateVideo(_ request: AIGenerationRequest) async throws -> AIProviderResponse { try placeholderResponse(for: request) }
    func editVideo(_ request: AIGenerationRequest) async throws -> AIProviderResponse { try placeholderResponse(for: request) }
    func generate3DModel(_ request: AIGenerationRequest) async throws -> AIProviderResponse { try placeholderResponse(for: request) }
    func generateVoice(_ request: AIGenerationRequest) async throws -> AIProviderResponse { try placeholderResponse(for: request) }
    func generateMusic(_ request: AIGenerationRequest) async throws -> AIProviderResponse { try placeholderResponse(for: request) }
    func generateGame(_ request: AIGenerationRequest) async throws -> AIProviderResponse { try placeholderResponse(for: request) }
    func generateVFX(_ request: AIGenerationRequest) async throws -> AIProviderResponse { try placeholderResponse(for: request) }
}

typealias GoogleAIProvider = BackendOnlyAIProvider
typealias MeshyProvider = BackendOnlyAIProvider
typealias VoiceProvider = BackendOnlyAIProvider
typealias GameProvider = BackendOnlyAIProvider
typealias VFXProvider = BackendOnlyAIProvider

struct PoplurAIBackendEndpoint {
    static let generateImage = "/ai/generate/image"
    static let generateVideo = "/ai/generate/video"
    static let generateEdit = "/ai/generate/edit"
    static let generateVFX = "/ai/generate/vfx"
    static let generate3D = "/ai/generate/3d"
    static let generateVoice = "/ai/generate/voice"
    static let generateMusic = "/ai/generate/music"
    static let generateGame = "/ai/generate/game"
    static let jobs = "/ai/jobs"
    static let radioHost = "/radio/host"
    static let assistantChat = "/assistant/chat"
    static let assistantGuestChat = "/assistant/guest-chat"
    static let tvStyle = "/tv/style"
    static let bumperScript = "/bumper/script"
    static let gameConfig = "/games/config"
    static let radiusBoost = "/posts/%@/radius-boost"
    static let businessCampaign = "/businesses/%@/ai-campaigns"
}

struct PoplurRadioHostBackendResponse: Sendable {
    let script: String
    let audioData: Data
    let mimeType: String
    let stationName: String?
}

struct PoplurAIBackendClient: Sendable {
    static let defaultBaseURL = URL(string: "https://us-central1-poplur2025.cloudfunctions.net/poplurAiApi")!

    var baseURL: URL?
    var urlSession: URLSession = .shared

    init(baseURL: URL? = nil) {
        if let configured = ProcessInfo.processInfo.environment["POPLUR_AI_API_BASE_URL"], let url = URL(string: configured) {
            self.baseURL = url
        } else {
            self.baseURL = baseURL ?? Self.defaultBaseURL
        }
    }

    func generate(_ request: AIGenerationRequest) async throws -> AIProviderResponse {
        guard let baseURL else { throw AIStackError.backendBaseURLMissing }
        let endpoint = endpointPath(for: request.contentType)
        let token = try await firebaseIDToken()
        var urlRequest = URLRequest(url: apiURL(baseURL: baseURL, endpoint: endpoint))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: httpBody(for: request))
        let (data, urlResponse) = try await urlSession.data(for: urlRequest)
        guard let http = urlResponse as? HTTPURLResponse else {
            throw AIStackError.backendBaseURLMissing
        }
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 402: throw AIStackError.insufficientCredits
            case 403: throw AIStackError.aiLockedForPlan
            default:  throw AIStackError.backendError(http.statusCode)
            }
        }
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let job = payload?["job"] as? [String: Any] else {
            throw AIStackError.backendError(http.statusCode)
        }
        return response(from: job, fallbackRequest: request)
    }

    /// Hey Poplur's conversational turn. The Anthropic key lives on the
    /// backend with the other provider credentials — mobile never calls
    /// api.anthropic.com directly, same rule as every provider above.
    func assistantReply(question: String) async throws -> String {
        guard let baseURL else { throw AIStackError.backendBaseURLMissing }
        let token = try await firebaseIDToken()
        var urlRequest = URLRequest(url: apiURL(baseURL: baseURL, endpoint: PoplurAIBackendEndpoint.assistantChat))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: ["question": question])

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reply = payload["reply"] as? String,
              !reply.isEmpty else {
            throw AIStackError.backendError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return reply
    }

    /// Shared POST helper for the small JSON-in/JSON-out Claude endpoints.
    /// `authenticated: false` is only for the pre-login guest routes.
    private func postJSON(
        endpoint: String,
        body: [String: Any],
        authenticated: Bool = true
    ) async throws -> [String: Any] {
        guard let baseURL else { throw AIStackError.backendBaseURLMissing }
        var urlRequest = URLRequest(url: apiURL(baseURL: baseURL, endpoint: endpoint))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            let token = try await firebaseIDToken()
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIStackError.backendError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return payload
    }

    /// Poplur TV broadcast metadata for one post image. Claude runs on the
    /// backend; the device only ships the reduced JPEG.
    func tvStyleMetadata(imageBase64: String) async throws -> [String: Any] {
        try await postJSON(
            endpoint: PoplurAIBackendEndpoint.tvStyle,
            body: ["imageBase64": imageBase64]
        )
    }

    /// One spoken TV-host sentence introducing the next feed video.
    func bumperScript(context: String, language: String) async throws -> String {
        let payload = try await postJSON(
            endpoint: PoplurAIBackendEndpoint.bumperScript,
            body: ["context": context, "language": language]
        )
        guard let script = payload["script"] as? String, !script.isEmpty else {
            throw AIStackError.backendError(0)
        }
        return script
    }

    /// A generated mini-game session config, returned as raw JSON data so the
    /// caller can decode its own config type.
    func gameConfig(mode: String, prompt: String?) async throws -> Data {
        var body: [String: Any] = ["mode": mode]
        if let prompt, !prompt.isEmpty { body["prompt"] = prompt }
        let payload = try await postJSON(endpoint: PoplurAIBackendEndpoint.gameConfig, body: body)
        guard let config = payload["config"] as? [String: Any] else {
            throw AIStackError.backendError(0)
        }
        return try JSONSerialization.data(withJSONObject: config)
    }

    /// Pre-login auth-screen guide answer. No Firebase user exists yet, so
    /// this hits the unauthenticated, rate-limited guest route.
    func authGuideReply(screen: String, question: String) async throws -> String {
        let payload = try await postJSON(
            endpoint: PoplurAIBackendEndpoint.assistantGuestChat,
            body: ["screen": screen, "question": question],
            authenticated: false
        )
        guard let reply = payload["reply"] as? String, !reply.isEmpty else {
            throw AIStackError.backendError(0)
        }
        return reply
    }

    func radioHostAudio(
        script: String,
        cityName: String,
        stopTitle: String,
        stationName: String?,
        style: String = "warm local FM radio host"
    ) async throws -> PoplurRadioHostBackendResponse {
        guard let baseURL else { throw AIStackError.backendBaseURLMissing }
        let token = try await firebaseIDToken()
        var urlRequest = URLRequest(url: apiURL(baseURL: baseURL, endpoint: PoplurAIBackendEndpoint.radioHost))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "script": script,
            "cityName": cityName,
            "stopTitle": stopTitle,
            "stationName": stationName ?? "the local station",
            "style": style
        ])

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hostedScript = payload["script"] as? String,
              let audioBase64 = payload["audioBase64"] as? String,
              let audioData = Data(base64Encoded: audioBase64) else {
            throw AIStackError.providerMustRunOnBackend(.google)
        }

        return PoplurRadioHostBackendResponse(
            script: hostedScript,
            audioData: audioData,
            mimeType: payload["mimeType"] as? String ?? "audio/wav",
            stationName: payload["stationName"] as? String
        )
    }

    func endpointPath(for contentType: PoplurAIContentType) -> String {
        switch contentType {
        case .image: return PoplurAIBackendEndpoint.generateImage
        case .video: return PoplurAIBackendEndpoint.generateVideo
        case .edit: return PoplurAIBackendEndpoint.generateEdit
        case .vfx, .vfxVideo: return PoplurAIBackendEndpoint.generateVFX
        case .threeDModel: return PoplurAIBackendEndpoint.generate3D
        case .voice: return PoplurAIBackendEndpoint.generateVoice
        case .music: return PoplurAIBackendEndpoint.generateMusic
        case .game: return PoplurAIBackendEndpoint.generateGame
        case .coupon, .campaign: return PoplurAIBackendEndpoint.businessCampaign
        }
    }

    private func apiURL(baseURL: URL, endpoint: String) -> URL {
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(base)/\(path)") ?? baseURL
    }

    private func firebaseIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw AIStackError.aiLockedForPlan
        }
        return try await withCheckedThrowingContinuation { continuation in
            user.getIDToken { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: AIStackError.aiLockedForPlan)
                }
            }
        }
    }

    private func httpBody(for request: AIGenerationRequest) -> [String: Any] {
        var body: [String: Any] = [
            "prompt": request.prompt,
            "sourceAssetIds": request.inputAssetIds,
            "metadata": request.metadata.merging([
                "client": "ios",
                "requestedContentType": request.contentType.rawValue
            ]) { current, _ in current }
        ]
        if let publishMetadata = request.publishMetadata {
            body["location"] = [
                "latitude": publishMetadata.latitude,
                "longitude": publishMetadata.longitude,
                "locationName": publishMetadata.locationName,
                "address": publishMetadata.address ?? "",
                "radiusMeters": publishMetadata.radiusMeters,
                "category": publishMetadata.category ?? ""
            ]
            body["channelId"] = publishMetadata.category ?? publishMetadata.contentType.rawValue
        }
        return body
    }

    private func response(from job: [String: Any], fallbackRequest request: AIGenerationRequest) -> AIProviderResponse {
        let outputAssetIds = job["outputAssetIds"] as? [String] ?? []
        let outputUrls = job["outputUrls"] as? [String] ?? []
        let outputUrlString = job["outputUrl"] as? String ?? outputUrls.first
        let rawProvider = job["provider"] as? String ?? request.contentType.defaultProvider.rawValue
        return AIProviderResponse(
            jobId: job["id"] as? String ?? UUID().uuidString,
            provider: provider(from: rawProvider, fallback: request.contentType.defaultProvider),
            contentType: contentType(from: job["contentType"] as? String, fallback: request.contentType),
            status: status(from: job["status"] as? String),
            estimatedCostCredits: intValue(job["creditsCharged"]) + intValue(job["creditsReserved"]),
            outputUrl: outputUrlString.flatMap { URL(string: $0) },
            outputAssetId: outputAssetIds.first,
            providerRawResponse: compactStringDictionary(job)
        )
    }

    private func provider(from rawValue: String, fallback: PoplurAIProvider) -> PoplurAIProvider {
        switch rawValue {
        case "google_ai_studio": return .google
        default: return PoplurAIProvider(rawValue: rawValue) ?? fallback
        }
    }

    private func contentType(from rawValue: String?, fallback: PoplurAIContentType) -> PoplurAIContentType {
        switch rawValue {
        case "3d": return .threeDModel
        default: return rawValue.flatMap(PoplurAIContentType.init(rawValue:)) ?? fallback
        }
    }

    private func status(from rawValue: String?) -> PoplurAIGenerationStatus {
        switch rawValue {
        case "completed": return .completed
        case "failed", "refunded": return .failed
        case "cancelled": return .cancelled
        default: return .processing
        }
    }

    private func intValue(_ rawValue: Any?) -> Int {
        if let int = rawValue as? Int { return int }
        if let number = rawValue as? NSNumber { return number.intValue }
        if let double = rawValue as? Double { return Int(double) }
        if let string = rawValue as? String { return Int(string) ?? 0 }
        return 0
    }

    private func compactStringDictionary(_ dictionary: [String: Any]) -> [String: String] {
        dictionary.reduce(into: [:]) { partialResult, pair in
            switch pair.value {
            case let string as String:
                partialResult[pair.key] = string
            case let number as NSNumber:
                partialResult[pair.key] = number.stringValue
            default:
                break
            }
        }
    }
}

actor CreatorCreditLedger {
    private var balances: [String: CreatorCreditBalance]
    private(set) var transactions: [CreatorCreditTransaction]

    init(balances: [String: CreatorCreditBalance] = [:], transactions: [CreatorCreditTransaction] = []) {
        self.balances = balances
        self.transactions = transactions
    }

    func balance(for userId: String) -> CreatorCreditBalance {
        balances[userId] ?? CreatorCreditBalance(userId: userId, availableCredits: 0, reservedCredits: 0, updatedAt: Date())
    }

    func grant(userId: String, amount: Int, type: CreatorCreditTransactionType, metadata: [String: String] = [:]) throws {
        guard amount >= 0 else { throw AIStackError.negativeBalanceRejected }
        var balance = balance(for: userId)
        balance.availableCredits += amount
        balance.updatedAt = Date()
        balances[userId] = balance
        transactions.append(transaction(userId: userId, amount: amount, type: type, metadata: metadata))
    }

    func reserve(userId: String, amount: Int, jobId: String, provider: PoplurAIProvider, contentType: PoplurAIContentType) throws {
        guard amount >= 0 else { throw AIStackError.negativeBalanceRejected }
        var balance = balance(for: userId)
        guard balance.availableCredits >= amount else { throw AIStackError.insufficientCredits }
        balance.availableCredits -= amount
        balance.reservedCredits += amount
        balance.updatedAt = Date()
        balances[userId] = balance
        transactions.append(transaction(userId: userId, amount: -amount, type: .aiGenerationSpend, relatedJobId: jobId, provider: provider, contentType: contentType))
    }

    func completeReservation(userId: String, amount: Int) throws {
        var balance = balance(for: userId)
        guard balance.reservedCredits >= amount else { throw AIStackError.negativeBalanceRejected }
        balance.reservedCredits -= amount
        balance.updatedAt = Date()
        balances[userId] = balance
    }

    func refund(userId: String, amount: Int, relatedJobId: String? = nil) throws {
        var balance = balance(for: userId)
        guard balance.reservedCredits >= amount else { throw AIStackError.negativeBalanceRejected }
        balance.reservedCredits -= amount
        balance.availableCredits += amount
        balance.updatedAt = Date()
        balances[userId] = balance
        transactions.append(transaction(userId: userId, amount: amount, type: .refund, relatedJobId: relatedJobId))
    }

    func spendRadiusBoost(userId: String, postId: String, amount: Int, tier: RadiusBoostTier) throws {
        guard amount >= 0 else { throw AIStackError.negativeBalanceRejected }
        var balance = balance(for: userId)
        guard balance.availableCredits >= amount else { throw AIStackError.insufficientCredits }
        balance.availableCredits -= amount
        balance.updatedAt = Date()
        balances[userId] = balance
        transactions.append(transaction(userId: userId, amount: -amount, type: .radiusBoostSpend, relatedPostId: postId, metadata: ["tier": tier.rawValue]))
    }

    private func transaction(
        userId: String,
        amount: Int,
        type: CreatorCreditTransactionType,
        relatedJobId: String? = nil,
        relatedPostId: String? = nil,
        provider: PoplurAIProvider? = nil,
        contentType: PoplurAIContentType? = nil,
        metadata: [String: String] = [:]
    ) -> CreatorCreditTransaction {
        CreatorCreditTransaction(
            id: UUID().uuidString,
            userId: userId,
            amount: amount,
            type: type,
            relatedJobId: relatedJobId,
            relatedPostId: relatedPostId,
            provider: provider,
            contentType: contentType,
            createdAt: Date(),
            metadata: metadata
        )
    }
}

struct PoplurAIStackService: Sendable {
    var config: PoplurAIStackConfig
    var ledger: CreatorCreditLedger
    var backend: PoplurAIBackendClient

    init(
        config: PoplurAIStackConfig = .productionDefaults,
        ledger: CreatorCreditLedger = CreatorCreditLedger(),
        backend: PoplurAIBackendClient = PoplurAIBackendClient()
    ) {
        self.config = config
        self.ledger = ledger
        self.backend = backend
    }

    func validateGenerationRequest(_ request: AIGenerationRequest, balance: CreatorCreditBalance) throws -> Int {
        guard request.prompt.count <= config.maxPromptLength else { throw AIStackError.promptTooLong }
        guard request.plan.canGenerateAI(with: balance.availableCredits) else { throw AIStackError.aiLockedForPlan }
        let provider = request.contentType.defaultProvider
        guard config.providerEnabled[provider] == true else { throw AIStackError.providerDisabled(provider) }
        let cost = config.estimatedCost(for: request.contentType, campaignAssets: request.campaignAssetTypes)
        guard balance.availableCredits >= cost else { throw AIStackError.insufficientCredits }
        return cost
    }

    func startGeneration(_ request: AIGenerationRequest) async throws -> AIProviderResponse {
        let balance = await ledger.balance(for: request.userId)
        let cost = try validateGenerationRequest(request, balance: balance)
        let jobId = UUID().uuidString
        let provider = request.contentType.defaultProvider
        try await ledger.reserve(userId: request.userId, amount: cost, jobId: jobId, provider: provider, contentType: request.contentType)
        do {
            let response = try await backend.generate(request)
            if response.status == .failed || response.status == .cancelled {
                try await ledger.refund(userId: request.userId, amount: cost, relatedJobId: jobId)
            } else if response.status == .completed {
                try await ledger.completeReservation(userId: request.userId, amount: cost)
            }
            return response
        } catch {
            try await ledger.refund(userId: request.userId, amount: cost, relatedJobId: jobId)
            throw error
        }
    }

    func validatePublishMetadata(_ metadata: AIMapPublishMetadata) throws {
        guard (-90...90).contains(metadata.latitude),
              (-180...180).contains(metadata.longitude),
              metadata.radiusMeters > 0
        else { throw AIStackError.invalidLocation }
    }

    func applyRadiusBoost(post: AIMapPost, userId: String, tier: RadiusBoostTier) async throws -> AIMapPost {
        let cost = config.boostCostByTier[tier] ?? 0
        try await ledger.spendRadiusBoost(userId: userId, postId: post.id, amount: cost, tier: tier)
        var boosted = post
        boosted.boostedRadiusMeters = min(post.organicRadiusMeters + tier.additionalRadiusMeters, 100_000)
        boosted.boostExpiresAt = Date().addingTimeInterval(tier.duration)
        return boosted
    }
}
