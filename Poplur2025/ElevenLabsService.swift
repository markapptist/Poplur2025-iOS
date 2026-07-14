import Foundation

// Shared ElevenLabs TTS service used by both the feed bumper and the map radio host.
// Free tier: 10,000 characters/month — sign up at https://elevenlabs.io, no card needed.
// Configuration comes from AppSecrets and is never embedded in source.
final class ElevenLabsService {
    static let shared = ElevenLabsService()

    private let cache = NSCache<NSString, NSData>()

    private var apiKey: String {
        let ud = UserDefaults.standard.string(forKey: "poplur_elevenlabs_key") ?? ""
        return ud.isEmpty ? AppSecrets.elevenLabsAPIKey : ud
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    enum Voice {
        case english
        case french

        var id: String {
            switch self {
            case .english: return AppSecrets.elevenLabsVoiceID
            case .french:
                let id = AppSecrets.elevenLabsFrenchVoiceID
                return id.isEmpty ? AppSecrets.elevenLabsVoiceID : id
            }
        }
    }

    func audioData(for text: String, voice: Voice = .english) async throws -> Data {
        let cacheKey = NSString(string: "\(voice.id)|\(text)")
        if let hit = cache.object(forKey: cacheKey) { return hit as Data }

        let voiceID = voice.id.isEmpty ? "21m00Tcm4TlvDq8ikWAM" : voice.id
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty else {
            throw ElevenLabsError.badResponse
        }

        cache.setObject(data as NSData, forKey: cacheKey)
        return data
    }

    enum ElevenLabsError: Error { case badResponse }
}
