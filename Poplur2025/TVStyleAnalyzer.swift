import Foundation
import UIKit
import AVFoundation

// MARK: - Data model

struct TVStyleMetadata: Codable {
    let channel: String        // food | fitness | sports | beauty | fashion | music | tech | news | city | entertainment
    let tvFormat: String       // commercial | highlight_reel | cooking_show | documentary | talk_show | music_video | news_segment
    let adConcept: String      // e.g. "protein supplement commercial" or "teeth whitening ad"
    let caption: String        // punchy ALL-CAPS headline, ≤5 words
    let tagline: String        // one motivational brand sentence
    let broadcastName: String  // e.g. "POPLUR FITNESS" or "POPLUR EATS"
}

// MARK: - Analyzer

actor TVStyleAnalyzer {
    static let shared = TVStyleAnalyzer()
    private init() {}

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model    = "claude-haiku-4-5-20251001"

    func analyze(image: UIImage) async throws -> TVStyleMetadata {
        let jpeg = resized(image).jpegData(compressionQuality: 0.72) ?? Data()
        return try await callClaude(imageData: jpeg)
    }

    func analyze(videoURL: URL) async throws -> TVStyleMetadata {
        let frame = try firstFrame(of: videoURL)
        let jpeg  = resized(frame).jpegData(compressionQuality: 0.72) ?? Data()
        return try await callClaude(imageData: jpeg)
    }

    // MARK: - Private helpers

    private func firstFrame(of url: URL) throws -> UIImage {
        let asset = AVURLAsset(url: url)
        let gen   = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        let cgImage = try gen.copyCGImage(at: .zero, actualTime: nil)
        return UIImage(cgImage: cgImage)
    }

    private func resized(_ image: UIImage, maxDimension: CGFloat = 512) -> UIImage {
        let s = CGFloat(1) / max(image.size.width, image.size.height) * maxDimension
        let newSize = CGSize(width: image.size.width * min(s, 1),
                             height: image.size.height * min(s, 1))
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func callClaude(imageData: Data) async throws -> TVStyleMetadata {
        let key = UserDefaults.standard.string(forKey: "poplur_claude_key") ?? ""
        guard !key.isEmpty else { throw TVAnalyzerError.noAPIKey }

        let prompt = """
You are a TV broadcast classifier for Poplur TV, a social platform where every post is a TV broadcast.
Analyze this image and respond ONLY with a JSON object — no extra text, no markdown:
{"channel":"<food|fitness|sports|beauty|fashion|music|tech|news|city|entertainment>","tvFormat":"<commercial|highlight_reel|cooking_show|documentary|talk_show|music_video|news_segment>","adConcept":"<what this would be as a TV ad or show in under 8 words>","caption":"<PUNCHY ALL-CAPS HEADLINE MAX 5 WORDS>","tagline":"<one compelling motivational sentence>","broadcastName":"<POPLUR CHANNEL e.g. POPLUR FITNESS>"}
"""

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 300,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": imageData.base64EncodedString()
                    ]],
                    ["type": "text", "text": prompt]
                ]
            ]]
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(key,           forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",  forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 20

        let (data, _) = try await URLSession.shared.data(for: req)

        guard
            let outer    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content  = (outer["content"] as? [[String: Any]])?.first,
            let text     = content["text"] as? String,
            let jsonData = text.data(using: .utf8)
        else { throw TVAnalyzerError.parseError }

        return try JSONDecoder().decode(TVStyleMetadata.self, from: jsonData)
    }
}

enum TVAnalyzerError: Error {
    case noAPIKey
    case parseError
}
