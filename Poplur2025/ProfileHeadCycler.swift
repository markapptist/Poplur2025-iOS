import Foundation
import SwiftUI

// To enable AI 3D head generation, set your Replicate API key:
//   UserDefaults.standard.set("<your_key>", forKey: "poplur_replicate_key")
// Sign up at replicate.com → Account → API tokens.
// Model used: lucataco/instant-mesh (single-image → GLB mesh).
// Without a key the cycler still works with locally scanned USDZ models.

@MainActor
final class ProfileHeadCycler: ObservableObject {
    @Published private(set) var modelURL: URL? = nil
    @Published private(set) var is3DActive: Bool = false
    @Published private(set) var isGenerating: Bool = false

    private var cycleTimer: Timer?
    private var generationTask: Task<Void, Never>?

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "poplur_replicate_key") ?? ""
    }

    /// Call when a profile loads. Pass `localModelURL` (face-scan USDZ) to skip network generation.
    func start(profileImageURL: URL?, localModelURL: URL?, userID: String) {
        generationTask?.cancel()
        cycleTimer?.invalidate()
        withAnimation { is3DActive = false }
        modelURL = nil

        generationTask = Task {
            // Prefer locally-scanned USDZ
            if let local = localModelURL, FileManager.default.fileExists(atPath: local.path) {
                self.modelURL = local
                self.startCycling()
                return
            }

            // Check disk cache
            if let cached = self.cachedURL(for: userID),
               FileManager.default.fileExists(atPath: cached.path) {
                self.modelURL = cached
                self.startCycling()
                return
            }

            // Generate via Replicate (requires API key + public image URL)
            guard let imageURL = profileImageURL, !self.apiKey.isEmpty else { return }
            guard !Task.isCancelled else { return }

            self.isGenerating = true
            do {
                let meshURL = try await self.callReplicate(imageURL: imageURL)
                guard !Task.isCancelled else { return }
                let ext = meshURL.pathExtension.isEmpty ? "glb" : meshURL.pathExtension
                let dest = self.cachedURL(for: userID, ext: ext)!
                let (tmp, _) = try await URLSession.shared.download(from: meshURL)
                guard !Task.isCancelled else { return }
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                self.modelURL = dest
                self.startCycling()
            } catch {
                if !(error is CancellationError) {
                    print("[ProfileHeadCycler] generation error: \(error.localizedDescription)")
                }
            }
            self.isGenerating = false
        }
    }

    func stop() {
        generationTask?.cancel()
        generationTask = nil
        cycleTimer?.invalidate()
        cycleTimer = nil
        withAnimation { is3DActive = false }
    }

    // MARK: - Cycling

    private func startCycling() {
        cycleTimer?.invalidate()
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                withAnimation(.easeInOut(duration: 0.7)) {
                    self?.is3DActive.toggle()
                }
            }
        }
    }

    // MARK: - Cache

    private func cachedURL(for userID: String, ext: String = "glb") -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("poplur_head_\(userID).\(ext)")
    }

    // MARK: - Replicate API (lucataco/instant-mesh)

    private func callReplicate(imageURL: URL) async throws -> URL {
        guard let endpoint = URL(string: "https://api.replicate.com/v1/models/lucataco/instant-mesh/predictions") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "input": [
                "image_path": imageURL.absoluteString,
                "do_remove_background": true,
                "sample_steps": 75,
                "num_multiview_images": 4
            ] as [String: Any]
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return try await pollReplicate(id: id)
    }

    private func pollReplicate(id: String) async throws -> URL {
        guard let url = URL(string: "https://api.replicate.com/v1/predictions/\(id)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        for _ in 0..<90 { // max 4.5 min
            try await Task.sleep(nanoseconds: 3_000_000_000) // poll every 3s
            try Task.checkCancellation()

            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            switch json["status"] as? String {
            case "succeeded":
                // Output may be dict {"mesh": url} or array [url]
                if let out = json["output"] as? [String: Any] {
                    let s = out["mesh"] as? String ?? out["glb"] as? String
                    if let s, let u = URL(string: s) { return u }
                }
                if let arr = json["output"] as? [String], let s = arr.first, let u = URL(string: s) {
                    return u
                }
                throw URLError(.cannotParseResponse)
            case "failed", "canceled":
                let msg = json["error"] as? String ?? "Prediction failed"
                throw NSError(domain: "Replicate", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
            default:
                continue
            }
        }
        throw NSError(domain: "Replicate", code: -2, userInfo: [NSLocalizedDescriptionKey: "Timed out after 4.5 min"])
    }
}
