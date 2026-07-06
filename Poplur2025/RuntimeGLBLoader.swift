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
    static func loadScene(from url: URL, label: String) -> SCNScene? {
        var decodedScene: SCNScene?
        do {
            try PLTryCatch.runCatchingException {
                let source = GLTFSceneSource(url: url, options: nil)
                decodedScene = source.scene()
            }
        } catch {
            print("[RuntimeGLBLoader] GLB decode raised an exception for \(label): \(error.localizedDescription)")
            return nil
        }

        guard let scene = decodedScene else {
            print("[RuntimeGLBLoader] Could not decode GLB: \(label) at \(url.path)")
            return nil
        }
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
        guard maxExtent > 0 else { return }

        let center = SCNVector3(
            (minBounds.x + maxBounds.x) / 2,
            (minBounds.y + maxBounds.y) / 2,
            (minBounds.z + maxBounds.z) / 2
        )
        let scale = targetExtent / maxExtent
        node.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
        node.scale = SCNVector3(scale, scale, scale)
    }

    static func bounds(for root: SCNNode) -> (min: SCNVector3, max: SCNVector3)? {
        var minBounds = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBounds = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var foundGeometry = false

        root.enumerateChildNodes { child, _ in
            guard child.geometry != nil else { return }
            foundGeometry = true
            let bounds = child.boundingBox
            let corners = [
                SCNVector3(bounds.min.x, bounds.min.y, bounds.min.z),
                SCNVector3(bounds.min.x, bounds.min.y, bounds.max.z),
                SCNVector3(bounds.min.x, bounds.max.y, bounds.min.z),
                SCNVector3(bounds.min.x, bounds.max.y, bounds.max.z),
                SCNVector3(bounds.max.x, bounds.min.y, bounds.min.z),
                SCNVector3(bounds.max.x, bounds.min.y, bounds.max.z),
                SCNVector3(bounds.max.x, bounds.max.y, bounds.min.z),
                SCNVector3(bounds.max.x, bounds.max.y, bounds.max.z)
            ]
            for corner in corners {
                let point = child.convertPosition(corner, to: root)
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
