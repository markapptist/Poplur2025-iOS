import SwiftUI
import RealityKit
import ARKit
import CoreMotion

struct USDZViewerView: View {
    let usdzURL: URL

    var body: some View {
        USDZViewerRepresentable(usdzURL: usdzURL)
            .ignoresSafeArea()
            .navigationTitle("Head Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
    }
}

private struct USDZViewerRepresentable: UIViewRepresentable {
    let usdzURL: URL

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false

        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic
        view.session.run(config)

        // Load model entity
        do {
            let entity = try ModelEntity.loadModel(contentsOf: usdzURL)
            entity.generateCollisionShapes(recursive: true)

            // Center and scale to a reasonable size
            let bounds = entity.visualBounds(relativeTo: nil)
            let maxExtent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
            let scale: Float = maxExtent > 0 ? (0.25 / maxExtent) : 1.0
            entity.scale = SIMD3<Float>(repeating: scale)

            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(entity)
            view.scene.addAnchor(anchor)

            // Save ref for rotation updates
            context.coordinator.modelEntity = entity
        } catch {
            // If loading fails, leave empty scene
        }

        // Start motion
        context.coordinator.startMotionUpdates()
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private let motion = CMMotionManager()
        private let queue = OperationQueue()
        weak var modelEntity: ModelEntity?

        func startMotionUpdates() {
            guard motion.isDeviceMotionAvailable else { return }
            motion.deviceMotionUpdateInterval = 1.0 / 60.0
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, _ in
                guard let self, let motion else { return }
                // Map attitude (roll/pitch) to model rotations similar to a cube tilt
                let pitch = Float(motion.attitude.pitch)  // x rotation
                let roll  = Float(motion.attitude.roll)   // z rotation like cube tilt

                // Dampen for a comfortable viewing range
                let damp: Float = 0.6
                let rx = -pitch * damp
                let rz = -roll  * damp

                let rotation = simd_mul(simd_quatf(angle: rx, axis: [1,0,0]), simd_quatf(angle: rz, axis: [0,0,1]))
                DispatchQueue.main.async {
                    self.modelEntity?.orientation = rotation
                }
            }
        }

        deinit {
            motion.stopDeviceMotionUpdates()
        }
    }
}
