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

        context.coordinator.attach(to: view, configuration: config)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private let motion = CMMotionManager()
        private let queue = OperationQueue()
        weak var modelEntity: ModelEntity?
        private weak var arView: ARView?
        private var configuration: ARWorldTrackingConfiguration?
        private var performanceRegistration: PoplurPerformanceRegistration?

        func attach(to view: ARView, configuration: ARWorldTrackingConfiguration) {
            arView = view
            self.configuration = configuration
            performanceRegistration = PoplurPerformanceManager.shared.registerRenderer(
                name: "USDZViewerAR",
                classification: .heavy,
                rateClass: .interactive,
                priority: 80,
                onPolicy: { [weak self] policy, granted in
                    self?.applyPerformance(policy, granted: granted)
                },
                onPurgeInactiveResources: { [weak view] in view?.session.pause() }
            )
            performanceRegistration?.setVisible(true)
        }

        private func startMotionUpdates(targetFPS: Int) {
            guard motion.isDeviceMotionAvailable else { return }
            motion.deviceMotionUpdateInterval = 1.0 / Double(max(10, targetFPS))
            guard !motion.isDeviceMotionActive else { return }
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

        private func applyPerformance(_ policy: PoplurPerformancePolicy, granted: Bool) {
            guard granted, let configuration else {
                motion.stopDeviceMotionUpdates()
                arView?.session.pause()
                return
            }
            arView?.session.run(configuration)
            startMotionUpdates(targetFPS: policy.targetFPS(for: .interactive))
        }

        func tearDown() {
            performanceRegistration?.setVisible(false)
            performanceRegistration?.invalidate()
            performanceRegistration = nil
            motion.stopDeviceMotionUpdates()
            arView?.session.pause()
            arView?.scene.anchors.removeAll()
            arView = nil
            configuration = nil
            modelEntity = nil
        }

        deinit { tearDown() }
    }
}
