import Foundation
import UIKit

// Face-preserving AI generation via Replicate.
// Image ads: zsxkib/instant-id  — generates a styled portrait that looks like you.
// Video ads: wan-ai/wan2.1-i2v-480p — animates your face image into a video.
enum FaceAdGenerationService {

    static func generateImage(faceImage: UIImage, prompt: String) async throws -> UIImage {
        let apiKey = UserDefaults.standard.string(forKey: "poplur_replicate_key") ?? ""
        guard !apiKey.isEmpty else { throw FaceAdError.noAPIKey }

        let dataURI = try encodeImage(faceImage)

        var req = try makeRequest(
            url: "https://api.replicate.com/v1/models/zsxkib/instant-id/predictions",
            apiKey: apiKey,
            body: [
                "input": [
                    "image": dataURI,
                    "prompt": prompt,
                    "negative_prompt": "low quality, blurry, bad anatomy, multiple people, text, watermark",
                    "width": 1024,
                    "height": 1024,
                    "num_inference_steps": 30,
                    "guidance_scale": 5.0,
                    "style_strength_ratio": 20,
                    "enhance_face_region": true
                ] as [String: Any]
            ]
        )
        req.timeoutInterval = 30

        let id = try await startPrediction(req)
        let outputURL = try await poll(id: id, apiKey: apiKey)
        let (imgData, _) = try await URLSession.shared.data(from: outputURL)
        guard let image = UIImage(data: imgData) else { throw FaceAdError.downloadFailed }
        return image
    }

    static func generateVideo(faceImage: UIImage, prompt: String) async throws -> URL {
        let apiKey = UserDefaults.standard.string(forKey: "poplur_replicate_key") ?? ""
        guard !apiKey.isEmpty else { throw FaceAdError.noAPIKey }

        let dataURI = try encodeImage(faceImage)

        var req = try makeRequest(
            url: "https://api.replicate.com/v1/models/wan-ai/wan2.1-i2v-480p/predictions",
            apiKey: apiKey,
            body: [
                "input": [
                    "image": dataURI,
                    "prompt": prompt,
                    "num_frames": 81
                ] as [String: Any]
            ]
        )
        req.timeoutInterval = 30

        let id = try await startPrediction(req)
        return try await poll(id: id, apiKey: apiKey)
    }

    // MARK: - Private helpers

    private static func encodeImage(_ image: UIImage) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.82) else { throw FaceAdError.encodingFailed }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    private static func makeRequest(url: String, apiKey: String, body: [String: Any]) throws -> URLRequest {
        guard let endpoint = URL(string: url) else { throw FaceAdError.networkFailed }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private static func startPrediction(_ req: URLRequest) async throws -> String {
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String
        else { throw FaceAdError.invalidResponse }
        return id
    }

    private static func poll(id: String, apiKey: String) async throws -> URL {
        guard let url = URL(string: "https://api.replicate.com/v1/predictions/\(id)") else {
            throw FaceAdError.networkFailed
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        for _ in 0..<90 {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            try Task.checkCancellation()
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            switch json["status"] as? String {
            case "succeeded":
                if let arr = json["output"] as? [String], let s = arr.first, let u = URL(string: s) { return u }
                if let s = json["output"] as? String, let u = URL(string: s) { return u }
                throw FaceAdError.invalidResponse
            case "failed", "canceled":
                throw FaceAdError.generationFailed
            default: continue
            }
        }
        throw FaceAdError.timeout
    }
}

enum FaceAdError: LocalizedError {
    case noAPIKey, encodingFailed, networkFailed, invalidResponse, generationFailed, downloadFailed, timeout

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Replicate API key missing."
        case .encodingFailed: return "Could not encode image."
        case .networkFailed: return "Network error."
        case .invalidResponse: return "Unexpected API response."
        case .generationFailed: return "AI generation failed."
        case .downloadFailed: return "Could not download result."
        case .timeout: return "Generation timed out after 4.5 min."
        }
    }
}
