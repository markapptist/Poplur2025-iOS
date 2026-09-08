import AVFoundation
import CryptoKit
import Foundation

/// A disposable display derivative, never a replacement for the user's profile video.
enum PoplurMapSelfieVideo {
    @MainActor private static var pending: (id: String, task: Task<Void, Never>)?
    private static let maximumBytes = 12_000_000
    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MapSelfieVideo-v1", isDirectory: true)
    }

    static func item(for path: String) -> URL? {
        guard path.hasPrefix("/map-selfie/"), path.hasSuffix(".mp4") else { return nil }
        let name = String(path.dropFirst("/map-selfie/".count).dropLast(4))
        guard name.count == 64, name.allSatisfy({ $0.isHexDigit }) else { return nil }
        let file = directory.appendingPathComponent(name + ".mp4")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    @MainActor static func cancel(_ requestId: String) {
        guard pending?.id == requestId else { return }
        pending?.task.cancel()
        pending = nil
    }

    @MainActor static func prepare(source: String, requestId: String, completion: @escaping (String?) -> Void) {
        pending?.task.cancel()
        let task = Task {
            defer { if pending?.id == requestId { pending = nil } }
            do {
                let result = try await makeDerivative(source: source)
                try Task.checkCancellation()
                completion(result)
            } catch {
                if !Task.isCancelled {
                    PoplurDiagLog.append("[MapSelfie] derivative unavailable: \(error.localizedDescription)")
                    completion(nil)
                }
            }
        }
        pending = (requestId, task)
    }

    private static func makeDerivative(source: String) async throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let input: URL
        let temporary: Bool
        let fingerprint: String
        if let url = URL(string: source), url.scheme == PoplurClayWebMap.scheme,
           url.host == PoplurClayWebMap.host, let stored = PoplurProfileSelfieStore.item(for: url.path) {
            input = stored.url
            temporary = false
            let values = try input.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            fingerprint = source + ":\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        } else {
            let data: Data
            if source.hasPrefix("data:video/"), source.utf8.count < maximumBytes * 2,
               let comma = source.firstIndex(of: ","),
               source[..<comma].hasSuffix(";base64"),
               let decoded = Data(base64Encoded: String(source[source.index(after: comma)...])) {
                data = decoded
            } else if let url = URL(string: source), url.scheme == "https" {
                var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30)
                request.httpMethod = "GET"
                let (download, response) = try await URLSession.shared.download(for: request)
                defer { try? FileManager.default.removeItem(at: download) }
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      (try download.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= maximumBytes else {
                    throw URLError(.badServerResponse)
                }
                data = try Data(contentsOf: download, options: .mappedIfSafe)
            } else {
                throw URLError(.unsupportedURL)
            }
            guard !data.isEmpty, data.count <= maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
            fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            input = directory.appendingPathComponent(UUID().uuidString + ".input")
            temporary = true
            try data.write(to: input, options: .atomic)
        }
        defer { if temporary { try? FileManager.default.removeItem(at: input) } }
        try Task.checkCancellation()
        let key = SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
        let output = directory.appendingPathComponent(key + ".mp4")
        if !FileManager.default.fileExists(atPath: output.path) {
            // Export into a separate file so cancellation cannot leave a cache hit.
            let staging = directory.appendingPathComponent(UUID().uuidString + ".mp4")
            defer { try? FileManager.default.removeItem(at: staging) }
            try await export(input, to: staging)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: staging, to: output)
            PoplurDiagLog.append("[MapSelfie] cached 320x320 silent clip (\((try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) bytes)")
        }
        // Keep one previous derivative through a profile update, and bound disk use.
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let older = files.filter { $0 != output && $0.pathExtension == "mp4" && $0.deletingPathExtension().lastPathComponent.count == 64 }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for stale in older.dropFirst() { try? FileManager.default.removeItem(at: stale) }
        return "\(PoplurClayWebMap.scheme)://\(PoplurClayWebMap.host)/map-selfie/\(key).mp4"
    }

    private static func export(_ input: URL, to output: URL) async throws {
        let asset = AVURLAsset(url: input)
        guard let source = try await asset.loadTracks(withMediaType: .video).first else { throw URLError(.cannotDecodeContentData) }
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration.seconds > 0 else { throw URLError(.cannotDecodeContentData) }
        let size = try await source.load(.naturalSize)
        let orientation = try await source.load(.preferredTransform)
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw URLError(.cannotCreateFile) }
        let range = CMTimeRange(start: .zero, duration: min(duration, CMTime(seconds: 10, preferredTimescale: 600)))
        try track.insertTimeRange(range, of: source, at: .zero)
        let bounds = CGRect(origin: .zero, size: size).applying(orientation)
        guard bounds.width > 0, bounds.height > 0 else { throw URLError(.cannotDecodeContentData) }
        let scale = max(320 / bounds.width, 320 / bounds.height)
        let transform = orientation
            .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (320 - bounds.width * scale) / 2, y: (320 - bounds.height * scale) / 2))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = range
        instruction.layerInstructions = [layer]
        let video = AVMutableVideoComposition()
        video.renderSize = CGSize(width: 320, height: 320)
        video.frameDuration = CMTime(value: 1, timescale: 30)
        video.instructions = [instruction]
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw URLError(.cannotCreateFile) }
        exporter.videoComposition = video
        exporter.shouldOptimizeForNetworkUse = true
        try Task.checkCancellation()
        // The async export observes Task cancellation and releases its reader/writer.
        try await exporter.export(to: output, as: .mp4)
        try Task.checkCancellation()
    }
}
