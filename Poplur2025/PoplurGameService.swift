import Foundation

final class PoplurGameService {
    static let shared = PoplurGameService()
    private init() {}

    /// Generate a game from the player's own description (used by the Game Maker).
    func generateConfig(userPrompt: String) async -> PoplurGameConfig {
        let trimmed = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return await request(mode: "maker", prompt: trimmed.isEmpty ? nil : trimmed)
    }

    func generateConfig() async -> PoplurGameConfig {
        return await request(mode: "arcade", prompt: nil)
    }

    // The system prompts and Claude call live on the backend (POST /games/config);
    // the device only names the mode and forwards the player's idea.
    private func request(mode: String, prompt: String?) async -> PoplurGameConfig {
        do {
            let cfgData = try await PoplurAIBackendClient().gameConfig(mode: mode, prompt: prompt)
            return (try? JSONDecoder().decode(PoplurGameConfig.self, from: cfgData)) ?? .fallback
        } catch {
            return .fallback
        }
    }
}
