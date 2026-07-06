import Foundation
import SwiftUI

@MainActor
final class ProfileHeadCycler: ObservableObject {
    @Published private(set) var modelURL: URL? = nil
    @Published private(set) var is3DActive: Bool = false
    @Published private(set) var isGenerating: Bool = false

    private let supportedRuntimeExtensions: Set<String> = ["usdz", "scn", "dae", "glb", "gltf"]
    private var cycleTimer: Timer?
    private var generationTask: Task<Void, Never>?

    /// Call when a profile loads. Pass `localModelURL` (face-scan USDZ) to skip network generation.
    func start(profileImageURL: URL?, localModelURL: URL?, userID: String) {
        generationTask?.cancel()
        cycleTimer?.invalidate()
        withAnimation { is3DActive = false }
        modelURL = nil

        generationTask = Task {
            // Prefer locally-scanned USDZ
            if let local = localModelURL,
               self.isSupportedRuntimeModel(local),
               FileManager.default.fileExists(atPath: local.path) {
                self.modelURL = local
                self.startCycling()
                return
            }

            // Check disk cache
            for cached in self.cachedURLs(for: userID) {
                if self.isSupportedRuntimeModel(cached),
                   FileManager.default.fileExists(atPath: cached.path) {
                    self.modelURL = cached
                    self.startCycling()
                    return
                }
            }

            if let bundled = self.bundledFallbackModelURL() {
                self.modelURL = bundled
                self.startCycling()
                return
            }

            // External 3D head generation must run through Poplur's backend Meshy provider.
            // This client cycler only displays local scanned/cached runtime-safe models.
            _ = profileImageURL
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

    private func cachedURL(for userID: String, ext: String) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("poplur_head_\(userID).\(ext)")
    }

    private func cachedURLs(for userID: String) -> [URL] {
        supportedRuntimeExtensions.compactMap { cachedURL(for: userID, ext: $0) }
    }

    private func isSupportedRuntimeModel(_ url: URL) -> Bool {
        supportedRuntimeExtensions.contains(url.pathExtension.lowercased())
    }

    private func bundledFallbackModelURL() -> URL? {
        for candidate in [
            ("MarkHead_TalkingRig", "glb"),
            ("MarkHead", "scn"),
            ("MarkHead", "dae")
        ] {
            if let url = Bundle.main.url(forResource: candidate.0, withExtension: candidate.1) {
                return url
            }
        }
        return nil
    }

}
