import Foundation
import SceneKit
import GLTFSceneKit

/// Shared, exception-safe GLB decoding used by any runtime (non-bundled-as-.scn) cube model.
///
/// GLTFSceneKit can raise an Objective-C exception while decoding malformed GLB data, which
/// Swift's do/try/catch cannot intercept on its own — decoding is wrapped in the PLTryCatch
/// Objective-C @try/@catch shim. Note this does NOT protect against a native segfault inside
/// Apple's own SceneKit framework (no in-process exception handling can); each caller is
/// responsible for verifying its specific asset doesn't trigger that before shipping it.
enum RuntimeGLBLoader {
    // GLB binary magic: ASCII "glTF"
    private static let glbMagic: [UInt8] = [0x67, 0x6C, 0x54, 0x46]

    /// Returns false when the file at `url` is NOT a real GLB binary (e.g. a Git LFS pointer stub).
    /// GLTFSceneSource will SIGSEGV on non-GLB content — this guard prevents that crash.
    private static func isValidGLB(at url: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        let header = fh.readData(ofLength: 4)
        guard header.count == 4 else { return false }
        return header.elementsEqual(glbMagic)
    }

    /// Caches decoded scenes by file path so a hot asset is not repeatedly run through
    /// GLTFSceneKit. The shared cache is byte/count bounded and can evict this scene under
    /// pressure; unlike the old dictionary it cannot retain every decoded model forever.
    ///
    /// Callers MUST NOT mutate the returned scene's node graph in place — clone the nodes they
    /// need (see `CubeTabView.makeRuntimeCubeModelNode`). Main-thread only (SceneKit affinity);
    /// the cache and SceneKit access are guarded by the main-thread caller contract.

    static func loadScene(from url: URL, label: String) -> SCNScene? {
        let key = "RuntimeGLB:\(url.standardizedFileURL.path)"
        if let cached = PoplurAssetCache.shared.asset(forKey: key, category: .scene, as: SCNScene.self) {
            return cached
        }

        guard isValidGLB(at: url) else {
            print("[RuntimeGLBLoader] Skipping \(label) — file is not a valid GLB binary (LFS stub or corrupt)")
            return nil
        }

        var decodedScene: SCNScene?
        do {
            try PLTryCatch.runCatchingException {
                let source = GLTFSceneSource(url: url, options: nil)
                decodedScene = source.scene()
            }
        } catch {
            print("[RuntimeGLBLoader] GLB decode raised an exception for \(label) at \(url.path): \(error.localizedDescription)")
            return nil
        }

        guard let scene = decodedScene else {
            print("[RuntimeGLBLoader] Could not decode GLB: \(label) at \(url.path)")
            return nil
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileBytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        // Binary size understates decoded geometry/material memory. Four times the
        // source size is a conservative accounting estimate, with a 1 MB floor.
        _ = PoplurAssetCache.shared.insert(
            scene,
            forKey: key,
            category: .scene,
            estimatedByteCost: max(1_048_576, fileBytes * 4)
        )
        return scene
    }

    /// Centers and scales a model's geometry so its largest extent equals `targetExtent`.
    static func normalize(_ node: SCNNode, targetExtent: Float = 1.3) {
        guard let bounds = bounds(for: node) else { return }
        let minBounds = bounds.min
        let maxBounds = bounds.max

        let width = maxBounds.x - minBounds.x
        let height = maxBounds.y - minBounds.y
        let depth = maxBounds.z - minBounds.z
        let maxExtent = max(width, max(height, depth))
        guard maxExtent.isFinite, maxExtent > 0 else { return }

        let center = SCNVector3(
            (minBounds.x + maxBounds.x) / 2,
            (minBounds.y + maxBounds.y) / 2,
            (minBounds.z + maxBounds.z) / 2
        )
        let scale = targetExtent / maxExtent
        guard scale.isFinite else { return }
        node.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
        node.scale = SCNVector3(scale, scale, scale)
    }

    static func bounds(for root: SCNNode) -> (min: SCNVector3, max: SCNVector3)? {
        var minBounds = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBounds = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var foundGeometry = false

        root.enumerateChildNodes { child, _ in
            guard child.geometry != nil else { return } // skip nodes without geometry
            foundGeometry = true
            let bounds = child.boundingBox

            let minBB = bounds.min
            let maxBB = bounds.max
            // Validate bounding box values; skip degenerate or non-finite boxes
            if !(minBB.x.isFinite && minBB.y.isFinite && minBB.z.isFinite && maxBB.x.isFinite && maxBB.y.isFinite && maxBB.z.isFinite) {
                return
            }
            if (minBB.x == maxBB.x) && (minBB.y == maxBB.y) && (minBB.z == maxBB.z) { // degenerate box
                return
            }

            let corners = [
                SCNVector3(minBB.x, minBB.y, minBB.z),
                SCNVector3(minBB.x, minBB.y, maxBB.z),
                SCNVector3(minBB.x, maxBB.y, minBB.z),
                SCNVector3(minBB.x, maxBB.y, maxBB.z),
                SCNVector3(maxBB.x, minBB.y, minBB.z),
                SCNVector3(maxBB.x, minBB.y, maxBB.z),
                SCNVector3(maxBB.x, maxBB.y, minBB.z),
                SCNVector3(maxBB.x, maxBB.y, maxBB.z)
            ]
            for corner in corners {
                let point = child.convertPosition(corner, to: root)
                guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { continue }
                minBounds.x = min(minBounds.x, point.x)
                minBounds.y = min(minBounds.y, point.y)
                minBounds.z = min(minBounds.z, point.z)
                maxBounds.x = max(maxBounds.x, point.x)
                maxBounds.y = max(maxBounds.y, point.y)
                maxBounds.z = max(maxBounds.z, point.z)
            }
        }

        guard foundGeometry else { return nil }
        return (minBounds, maxBounds)
    }

    /// Looks up a bundled GLB by name, trying each candidate subdirectory (in case Xcode
    /// flattens nested synchronized-group folders), then falling back to the bundle root.
    static func bundledURL(named assetName: String, candidateSubdirectories: [String]) -> URL? {
        for subdirectory in candidateSubdirectories {
            if let url = Bundle.main.url(forResource: assetName, withExtension: "glb", subdirectory: subdirectory) {
                return url
            }
        }
        return Bundle.main.url(forResource: assetName, withExtension: "glb")
    }
}
