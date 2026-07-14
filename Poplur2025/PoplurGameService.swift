import Foundation

final class PoplurGameService {
    static let shared = PoplurGameService()
    private init() {}

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-haiku-4-5-20251001"

    private let systemPrompt = """
    You generate game session configs for Poplur, a mobile game app. Return ONLY valid JSON — no markdown, no code fences.

    Available game keys: stella_blast
    Available character ids: pop, zyla, blip, rex, stella, glitch

    Return exactly this JSON shape:
    {
      "game": "<game_key>",
      "character": "<character_id>",
      "gameName": "<creative 2-4 word title>",
      "theme": "<one word: Jungle|Space|Neon|Arctic|Lava|Ocean|Cyber|Ancient|Dream|Toxic>",
      "skyColor": "<hex #RRGGBB>",
      "groundColor": "<hex #RRGGBB>",
      "accentColor": "<hex #RRGGBB>",
      "difficulty": "<easy|medium|hard>",
      "speed": <integer 200-380>,
      "powerUps": ["<name>", "<name>"],
      "enemyType": "<creative enemy name>",
      "specialMechanic": "<one short phrase>"
    }

    Generate a polished arcade-shooter session that feels closer to a real console game than a toy mini-game.
    Use stella_blast, choose cinematic space/neon colors, and make the mechanics sound skill-based.
    """

    // System prompt for user-authored games — all four game types are available and the
    // AI should honour the player's description when choosing type, theme and mechanics.
    private let makerSystemPrompt = """
    You generate game session configs for Poplur, a mobile game app, from a user's description.
    Return ONLY valid JSON — no markdown, no code fences.

    Available game keys: pop_runner (side-scroller), stella_blast (arcade shooter), zyla_quest (action/adventure), rex_hoops (sports)
    Available character ids: pop, zyla, blip, rex, stella, glitch

    Return exactly this JSON shape:
    {
      "game": "<game_key>",
      "character": "<character_id>",
      "gameName": "<creative 2-4 word title>",
      "theme": "<one word: Jungle|Space|Neon|Arctic|Lava|Ocean|Cyber|Ancient|Dream|Toxic>",
      "skyColor": "<hex #RRGGBB>",
      "groundColor": "<hex #RRGGBB>",
      "accentColor": "<hex #RRGGBB>",
      "difficulty": "<easy|medium|hard>",
      "speed": <integer 200-380>,
      "powerUps": ["<name>", "<name>"],
      "enemyType": "<creative enemy name>",
      "specialMechanic": "<one short phrase>"
    }

    Choose the game key that best fits the user's description. Pick colours and mechanics that
    match their theme. Make it sound like a polished console game, not a toy mini-game.
    """

    /// Generate a game from the player's own description (used by the Game Maker).
    func generateConfig(userPrompt: String) async -> PoplurGameConfig {
        let trimmed = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = trimmed.isEmpty
            ? "Generate a fresh, surprising game config now."
            : "Create a game based on this idea: \(trimmed)"
        return await request(system: makerSystemPrompt, userMessage: message)
    }

    func generateConfig() async -> PoplurGameConfig {
        return await request(system: systemPrompt, userMessage: "Generate a fresh game config now.")
    }

    private func request(system: String, userMessage: String) async -> PoplurGameConfig {
        guard let key = apiKey(), !key.isEmpty else { return .fallback }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 280,
            "system": system,
            "messages": [["role": "user", "content": userMessage]]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return .fallback }
        req.httpBody = bodyData

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let content = (json["content"] as? [[String: Any]])?.first,
                let text = content["text"] as? String,
                let cfgData = text.data(using: .utf8)
            else { return .fallback }
            return (try? JSONDecoder().decode(PoplurGameConfig.self, from: cfgData)) ?? .fallback
        } catch {
            return .fallback
        }
    }

    private func apiKey() -> String? {
        AppSecrets.claudeAPIKey
    }
}
