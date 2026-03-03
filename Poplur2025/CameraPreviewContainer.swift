import SwiftUI
import AVFoundation

struct CameraPreviewContainer: UIViewControllerRepresentable {
    let session: AVCaptureSession
    var onShutter: (() -> Void)?
    var onStartVideo: (() -> Void)?
    var onStopVideo: (() -> Void)?
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?
    var onRadiusChanged: ((Double) -> Void)?

    func makeUIViewController(context: Context) -> HostVC {
        let host = HostVC()
        let cameraVC = CameraPreviewViewController(session: session)
        cameraVC.onShutter = onShutter
        cameraVC.onStartVideo = onStartVideo
        cameraVC.onStopVideo = onStopVideo
        cameraVC.onSwipeLeft = onSwipeLeft
        cameraVC.onSwipeRight = onSwipeRight
        cameraVC.onRadiusChanged = onRadiusChanged
        cameraVC.autoManageSession = true
        host.embed(child: cameraVC)
        context.coordinator.cameraVC = cameraVC
        return host
    }

    func updateUIViewController(_ uiViewController: HostVC, context: Context) {
        if let cameraVC = context.coordinator.cameraVC {
            cameraVC.onShutter = onShutter
            cameraVC.onStartVideo = onStartVideo
            cameraVC.onStopVideo = onStopVideo
            cameraVC.onSwipeLeft = onSwipeLeft
            cameraVC.onSwipeRight = onSwipeRight
            cameraVC.onRadiusChanged = onRadiusChanged
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var cameraVC: CameraPreviewViewController?
    }

    final class HostVC: UIViewController {
        private weak var childVC: UIViewController?

        func embed(child: UIViewController) {
            // Remove old child if present
            if let existing = childVC {
                existing.willMove(toParent: nil)
                existing.view.removeFromSuperview()
                existing.removeFromParent()
            }
            addChild(child)
            view.addSubview(child.view)
            child.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                child.view.topAnchor.constraint(equalTo: view.topAnchor),
                child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            child.didMove(toParent: self)
            childVC = child
        }
    }
}
#if DEBUG
private final class _PreviewSessionFactory {
    static func makeSession() -> AVCaptureSession {
        // Create a lightweight session suitable for previews. This won't actually run in previews,
        // but provides a non-optional session for initialization.
        let session = AVCaptureSession()
        session.beginConfiguration()
        // Keep it minimal to avoid requiring camera access in previews.
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }
        session.commitConfiguration()
        return session
    }
}

#Preview("CameraPreviewContainer") {
    // Provide a minimal session; callbacks are left nil for preview.
    CameraPreviewContainer(session: _PreviewSessionFactory.makeSession())
        .ignoresSafeArea()
}
#endif

