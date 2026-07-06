import Foundation
import FirebaseAuth
import UIKit

enum FaceAdGenerationService {
    static func generateImage(faceImage: UIImage, prompt: String) async throws -> UIImage {
        guard faceImage.jpegData(compressionQuality: 0.84) != nil else { throw FaceAdError.encodingFailed }
        let response = try await PoplurAIBackendClient().generate(
            request(contentType: .edit, prompt: prompt, metadata: ["hasFaceImage": "true"])
        )
        guard let url = response.outputUrl else { throw FaceAdError.invalidResponse }
        let (data, httpResponse) = try await URLSession.shared.data(from: url)
        guard (httpResponse as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data)
        else {
            throw FaceAdError.downloadFailed
        }
        return image
    }

    static func generateVideo(faceImage: UIImage, prompt: String) async throws -> URL {
        guard faceImage.jpegData(compressionQuality: 0.84) != nil else { throw FaceAdError.encodingFailed }
        let response = try await PoplurAIBackendClient().generate(
            request(contentType: .video, prompt: prompt, metadata: ["hasFaceImage": "true"])
        )
        guard let url = response.outputUrl else { throw FaceAdError.invalidResponse }
        return url
    }

    private static func request(
        contentType: PoplurAIContentType,
        prompt: String,
        metadata: [String: String]
    ) throws -> AIGenerationRequest {
        guard let uid = Auth.auth().currentUser?.uid else { throw FaceAdError.providerMustRunOnBackend }
        return AIGenerationRequest(
            userId: uid,
            plan: .creator,
            contentType: contentType,
            prompt: prompt,
            inputAssetIds: [],
            publishMetadata: nil,
            campaignAssetTypes: [],
            metadata: metadata
        )
    }
}

enum FaceAdError: LocalizedError {
    case providerMustRunOnBackend
    case encodingFailed
    case invalidResponse
    case generationFailed
    case downloadFailed
    case timeout

    var errorDescription: String? {
        switch self {
        case .providerMustRunOnBackend:
            return "Poplur AI generation must run through the backend so provider keys stay server-side."
        case .encodingFailed:
            return "Could not encode image."
        case .invalidResponse:
            return "Unexpected API response."
        case .generationFailed:
            return "AI generation failed."
        case .downloadFailed:
            return "Could not download result."
        case .timeout:
            return "Generation timed out."
        }
    }
}
