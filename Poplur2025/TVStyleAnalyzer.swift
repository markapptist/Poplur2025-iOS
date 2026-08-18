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

    // The Claude classification runs on Poplur's backend (POST /tv/style);
    // the device only ships the reduced JPEG and decodes the JSON reply.
    private func callClaude(imageData: Data) async throws -> TVStyleMetadata {
        let payload: [String: Any]
        do {
            payload = try await PoplurAIBackendClient()
                .tvStyleMetadata(imageBase64: imageData.base64EncodedString())
        } catch let error as AIStackError {
            if case .backendError(let status) = error {
                print("🎬 [TVStyleAnalyzer] backend HTTP \(status)")
                throw TVAnalyzerError.httpError(status)
            }
            throw TVAnalyzerError.parseError
        }
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(TVStyleMetadata.self, from: jsonData)
    }
}

enum TVAnalyzerError: Error {
    case parseError
    case httpError(Int)
}
