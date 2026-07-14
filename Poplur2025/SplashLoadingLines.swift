import Foundation

/// Funny "what's loading" lines for the launch splash.
///
/// Strategy (per product decision): show a curated pool **instantly** on every launch
/// (offline, zero delay), and refresh the pool from Claude in the **background** so the
/// next launch gets fresh AI-written lines. The splash never waits on the network.
enum SplashLoadingLines {

    /// Curated offline pool — clay/map voice, whimsical.
    static let pool: [String] = [
        "Warming up the pinetrees", "Rolling out the clay roads", "Inflating the palm trees",
        "Teaching the pin to drop", "Buffing the city lights", "Sprinkling pink stars",
        "Kneading the little mountains", "Waking up the tugboat", "Charging the flip phone",
        "Tuning the clay TV", "Squishing fresh hearts", "Painting the dotted lines",
        "Polishing the big P", "Fluffing the clouds", "Wiring the tiny streetlamps",
        "Planting roadside bushes", "Smoothing the ocean", "Stacking the skyscrapers",
        "Greasing the map roads", "Feeding the stars some glitter", "Rounding the mountain edges",
        "Tucking rivers into valleys", "Handing out heart pins", "Booting the clay servers",
        "Shaping the coastline", "Coloring in the grass", "Warming the neon signs",
        "Shooing the thunderclouds away", "Counting nearby posts", "Measuring your radius",
        "Dusting off the globe", "Pinning the hotspots", "Untangling the roads",
        "Cranking the pink to eleven", "Baking a fresh batch of pins", "Aligning the constellations",
        "Reticulating clay splines", "Molding the mountains", "Whisking the clouds",
        "Rounding up the local legends", "Sanding the sidewalks", "Topping off the pink paint",
    ]

    private static let cacheKey = "poplur_splash_lines_ai"

    /// Lines to use for this launch: cached AI lines (if any) merged with the pool, shuffled.
    static func sessionLines() -> [String] {
        var lines = pool
        if let ai = UserDefaults.standard.stringArray(forKey: cacheKey), !ai.isEmpty {
            lines = ai + pool
        }
        return Array(Set(lines)).shuffled()
    }

    /// Final line shown when the bar completes, depending on where we're headed.
    static func destinationLine(loggedIn: Bool) -> String {
        loggedIn ? "Opening your feed" : "Rolling out the welcome mat"
    }

    /// Fire-and-forget: ask Claude for a fresh batch of lines and cache them for next launch.
    /// No-ops (silently) when there's no API key or the call fails — the pool always covers us.
    static func refreshFromClaudeInBackground() {
        let key = UserDefaults.standard.string(forKey: "poplur_claude_key") ?? Secrets.claudeAPIKey
        guard !key.isEmpty else { return }

        Task.detached(priority: .background) {
            let prompt = """
            Poplur is a playful social-map app with a claymation look: a pink clay world with roads, \
            a map pin, palm trees, a little city, a tugboat, hearts, a retro TV and flip phone, and pink stars.
            Write 14 very short, funny app "loading" status lines in that world's voice, like \
            "Warming up the pinetrees" or "Rolling out the clay roads". \
            Each 2–5 words, present-continuous, whimsical, no punctuation at the end, no emoji, no quotes. \
            Return ONLY a JSON array of strings.
            """
            guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "model": "claude-haiku-4-5-20251001",
                "max_tokens": 400,
                "messages": [["role": "user", "content": prompt]],
            ])

            guard let (data, response) = try? await URLSession.shared.data(for: req),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = ((json["content"] as? [[String: Any]])?.first?["text"] as? String)
            else { return }

            // Extract the JSON array from the response text.
            guard let start = text.firstIndex(of: "["),
                  let end = text.lastIndex(of: "]") else { return }
            let slice = String(text[start...end])
            guard let arr = try? JSONSerialization.jsonObject(with: Data(slice.utf8)) as? [String] else { return }

            let cleaned = arr
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count <= 34 }
            guard cleaned.count >= 6 else { return }

            UserDefaults.standard.set(Array(cleaned.prefix(20)), forKey: cacheKey)
        }
    }
}
