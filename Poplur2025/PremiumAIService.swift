import Combine
import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

enum PremiumAIAction: String, CaseIterable, Identifiable {
    case generateCaption = "generate_caption"
    case suggestPostIdea = "suggest_post_idea"
    case businessPromo = "business_promo"
    case translateCaption = "translate_caption"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generateCaption: return "Generate Caption"
        case .suggestPostIdea: return "Suggest Post Idea"
        case .businessPromo: return "Business Promo"
        case .translateCaption: return "Translate Caption"
        }
    }

    var systemImage: String {
        switch self {
        case .generateCaption: return "text.bubble.fill"
        case .suggestPostIdea: return "lightbulb.fill"
        case .businessPromo: return "megaphone.fill"
        case .translateCaption: return "globe"
        }
    }
}

struct PremiumAIEntitlement: Equatable {
    var isPremium: Bool
    var premiumTier: String?
    var monthlyLimit: Int
    var usedThisMonth: Int
    var month: String

    var remaining: Int {
        max(monthlyLimit - usedThisMonth, 0)
    }

    static var signedOut: PremiumAIEntitlement {
        PremiumAIEntitlement(
            isPremium: false,
            premiumTier: nil,
            monthlyLimit: 0,
            usedThisMonth: 0,
            month: PremiumAIService.currentUsageMonth
        )
    }
}

struct PremiumAIResult {
    var action: PremiumAIAction
    var output: [String: String]
    var usage: PremiumAIEntitlement

    var editableText: String {
        switch action {
        case .generateCaption:
            return [
                output["title"],
                output["caption"],
                output["hashtags"],
                output["radiusTip"].map { "Radius tip: \($0)" }
            ]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: "\n\n")
        case .suggestPostIdea:
            return [
                output["postIdea"],
                output["suggestedCaption"],
                output["bestTimeToPost"].map { "Best time: \($0)" },
                output["radiusStrategy"].map { "Radius: \($0)" }
            ]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: "\n\n")
        case .businessPromo:
            return [
                output["promoTitle"],
                output["promoCaption"],
                output["couponText"],
                output["callToAction"]
            ]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: "\n\n")
        case .translateCaption:
            return output["translatedText"] ?? ""
        }
    }
}

enum PremiumAIServiceError: LocalizedError {
    case signedOut
    case invalidResponse
    case backend(String)

    var errorDescription: String? {
        switch self {
        case .signedOut:
            return "Sign in to use Poplur AI."
        case .invalidResponse:
            return "Poplur AI returned an unexpected response."
        case .backend(let message):
            return message
        }
    }
}

final class PremiumAIService {
    static let shared = PremiumAIService()
    static let currentUsageMonth = String(Date().ISO8601Format().prefix(7))

    private let auth: Auth
    private let db: Firestore
    private let functions: Functions

    init(
        auth: Auth = .auth(),
        db: Firestore = .firestore(),
        functions: Functions = Functions.functions(region: "us-central1")
    ) {
        self.auth = auth
        self.db = db
        self.functions = functions
    }

    func fetchEntitlement() async throws -> PremiumAIEntitlement {
        guard let uid = auth.currentUser?.uid else {
            return .signedOut
        }

        let snapshot: DocumentSnapshot = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DocumentSnapshot, Error>) in
            db.collection("users").document(uid).getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: PremiumAIServiceError.invalidResponse)
                }
            }
        }

        let data = snapshot.data() ?? [:]
        let tier = data["premiumTier"] as? String
        let defaultLimit = tier?.lowercased() == "business" ? 500 : 100
        let month = data["aiUsageMonth"] as? String ?? Self.currentUsageMonth
        let used = month == Self.currentUsageMonth ? Self.intValue(data["aiUsedThisMonth"]) : 0
        let limit = max(Self.intValue(data["aiMonthlyLimit"], fallback: defaultLimit), 0)

        return PremiumAIEntitlement(
            isPremium: data["isPremium"] as? Bool == true,
            premiumTier: tier,
            monthlyLimit: limit,
            usedThisMonth: used,
            month: Self.currentUsageMonth
        )
    }

    func run(action: PremiumAIAction, input: [String: Any]) async throws -> PremiumAIResult {
        guard auth.currentUser != nil else {
            throw PremiumAIServiceError.signedOut
        }

        let payload: [String: Any] = [
            "action": action.rawValue,
            "input": input
        ]

        let callable = functions.httpsCallable("premiumAiAssist")
        let response: HTTPSCallableResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPSCallableResult, Error>) in
            callable.call(payload) { result, error in
                if let error {
                    continuation.resume(throwing: PremiumAIServiceError.backend(error.localizedDescription))
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: PremiumAIServiceError.invalidResponse)
                }
            }
        }

        guard let data = response.data as? [String: Any] else {
            throw PremiumAIServiceError.invalidResponse
        }

        let output = Self.normalizedOutput(data["output"])
        let usage = Self.entitlement(from: data["usage"])
        return PremiumAIResult(action: action, output: output, usage: usage)
    }

    private static func entitlement(from rawUsage: Any?) -> PremiumAIEntitlement {
        let usage = rawUsage as? [String: Any] ?? [:]
        return PremiumAIEntitlement(
            isPremium: true,
            premiumTier: usage["premiumTier"] as? String,
            monthlyLimit: intValue(usage["monthlyLimit"]),
            usedThisMonth: intValue(usage["usedThisMonth"]),
            month: usage["month"] as? String ?? currentUsageMonth
        )
    }

    private static func normalizedOutput(_ rawOutput: Any?) -> [String: String] {
        guard let dictionary = rawOutput as? [String: Any] else { return [:] }

        return dictionary.reduce(into: [String: String]()) { partialResult, pair in
            switch pair.value {
            case let string as String:
                partialResult[pair.key] = string
            case let strings as [String]:
                partialResult[pair.key] = strings.joined(separator: " ")
            case let values as [Any]:
                partialResult[pair.key] = values.map { String(describing: $0) }.joined(separator: " ")
            default:
                partialResult[pair.key] = String(describing: pair.value)
            }
        }
    }

    private static func intValue(_ rawValue: Any?, fallback: Int = 0) -> Int {
        if let int = rawValue as? Int { return int }
        if let double = rawValue as? Double { return Int(double) }
        if let number = rawValue as? NSNumber { return number.intValue }
        if let string = rawValue as? String, let int = Int(string) { return int }
        return fallback
    }
}

@MainActor
final class PremiumAIViewModel: ObservableObject {
    @Published var entitlement: PremiumAIEntitlement?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var generatedText = ""

    private let service: PremiumAIService

    init(service: PremiumAIService = .shared) {
        self.service = service
    }

    func loadEntitlement() async {
        do {
            entitlement = try await service.fetchEntitlement()
        } catch {
            entitlement = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    func run(action: PremiumAIAction, input: [String: Any]) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let result = try await service.run(action: action, input: input)
            entitlement = result.usage
            generatedText = result.editableText
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
