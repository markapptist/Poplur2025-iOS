import SwiftUI
import RealityKit

/// Compact inline 3D head renderer using RealityKit in non-AR mode.
/// No camera access required — purely virtual scene.
struct HeadPreviewView: UIViewRepresentable {
    let modelURL: URL

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.backgroundColor = .black
        arView.environment.background = .color(.black)

        // Place a perspective camera 0.4 m behind origin
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 58
        let camAnchor = AnchorEntity(world: .zero)
        camAnchor.position = [0, 0, 0.4]
        camAnchor.addChild(camera)
        arView.scene.addAnchor(camAnchor)

        Task {
            do {
                let entity = try await Entity.load(contentsOf: modelURL)

                // Normalize so largest dimension fits in 0.25 m
                let bounds = entity.visualBounds(relativeTo: nil)
                let maxExtent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
                let scale: Float = maxExtent > 0 ? 0.25 / maxExtent : 1
                entity.scale = .init(repeating: scale)
                // Re-center on bounding box midpoint after scaling
                entity.position = -(bounds.center * scale)

                let pivot = AnchorEntity(world: .zero)
                pivot.addChild(entity)

                await MainActor.run {
                    arView.scene.addAnchor(pivot)
                    context.coordinator.beginRotating(pivot: pivot)
                }
            } catch {
                print("[HeadPreviewView] model load error: \(error.localizedDescription)")
            }
        }
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var link: CADisplayLink?
        private var angle: Float = 0
        private weak var pivot: AnchorEntity?

        func beginRotating(pivot: AnchorEntity) {
            self.pivot = pivot
            link = CADisplayLink(target: self, selector: #selector(tick))
            link?.add(to: .main, forMode: .default)
        }

        @objc private func tick() {
            angle += 0.009 // ~0.5 rpm
            pivot?.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
        }

        deinit { link?.invalidate() }
    }
}
