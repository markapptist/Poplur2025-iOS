import Foundation

#if canImport(SceneKit)
import SceneKit
#endif

public final class SceneKitPrewarmer {
    private static var didPrewarm = false
    private static let lock = NSLock()
    
    public static func prewarmIfNeeded() async {
        #if canImport(SceneKit)
        let alreadyPrewarmed = lock.withLock { () -> Bool in
            let was = didPrewarm
            if !was { didPrewarm = true }
            return was
        }

        guard !alreadyPrewarmed else { return }

        await prewarmSceneKit()
        #else
        return
        #endif
    }

    #if canImport(SceneKit)
    @MainActor
    private static func prewarmSceneKit() async {
        let scnView = SCNView(frame: .zero)
        scnView.scene = SCNScene()
        scnView.isPlaying = false
        try? await Task.sleep(nanoseconds: 10_000_000)
        // Release scnView by going out of scope
    }
    #endif
}
