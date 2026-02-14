import SwiftUI
import CoreLocation
import AVFoundation

public protocol RecordPreviewViewControllerProviding {
    var recordPreviewViewController: UIViewController? { get }
}

public protocol RecordPreviewViewProviding {
    var recordPreviewView: UIView? { get }
}

public protocol PreviewViewControllerProviding {
    var previewViewController: UIViewController? { get }
}

public protocol PreviewViewProviding {
    var previewView: UIView? { get }
}

struct CameraKitView: View {
    @ObservedObject var controller: CameraKitController
    let coordinate: CLLocationCoordinate2D?
    @State private var isVisible: Bool = false
    @State private var isTorchOn: Bool = false

    init(controller: CameraKitController, coordinate: CLLocationCoordinate2D?) {
        self.controller = controller
        self.coordinate = coordinate
    }

    var body: some View {
        ZStack {
            if isVisible {
                LazyCameraPreview(controller: controller, coordinate: coordinate)
            } else {
                Color.black
            }

            // Top-right camera controls
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Button {
                            // Flip front/back camera
                            if let flip = controllerFlipAction() { flip() }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.35), in: Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button {
                            // Toggle torch/flash
                            if let toggled = controllerToggleTorch() {
                                isTorchOn = toggled
                            } else {
                                isTorchOn.toggle()
                            }
                        } label: {
                            Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(isTorchOn ? .yellow : .white)
                                .padding(10)
                                .background(Color.black.opacity(0.35), in: Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 12)
                    .padding(.top, 8)
                }
                Spacer()
            }
        }
        .ignoresSafeArea()
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
    }
    
    // Attempt to call a flip/toggle method if the controller implements it.
    private func controllerFlipAction() -> (() -> Void)? {
        // Common method name
        if controller.responds(to: Selector(("flipCamera"))) {
            return { _ = (controller as AnyObject).perform(Selector(("flipCamera"))) }
        }
        // Alternate names
        if controller.responds(to: Selector(("switchCamera"))) {
            return { _ = (controller as AnyObject).perform(Selector(("switchCamera"))) }
        }
        return nil
    }

    private func controllerToggleTorch() -> Bool? {
        // Try common method signature returning Bool indicating new state
        if controller.responds(to: Selector(("toggleTorch"))) {
            let _ = (controller as AnyObject).perform(Selector(("toggleTorch")))
            // If your controller publishes torch state, consider reading it here instead
            return nil
        }
        // Try explicit on/off methods
        if controller.responds(to: Selector(("toggleFlash"))) {
            let _ = (controller as AnyObject).perform(Selector(("toggleFlash")))
            return nil
        }
        return nil
    }

    private struct LazyCameraPreview: View {
        @ObservedObject var controller: CameraKitController
        let coordinate: CLLocationCoordinate2D?
        @State private var mounted: Bool = false

        var body: some View {
            Group {
                if mounted {
                    RecordPreviewContainer(controller: controller)
                        .ignoresSafeArea()
                } else {
                    EmptyView()
                }
            }
            .onAppear {
                mounted = true
            }
            .onDisappear {
                mounted = false
            }
        }
    }
}

extension CameraKitView {
    struct RecordPreviewContainer: UIViewControllerRepresentable {
        @ObservedObject var controller: CameraKitController

        func makeUIViewController(context: Context) -> UIViewController {
            // Prefer a dedicated RECORD preview view controller if available
            if let provider = controller as? RecordPreviewViewControllerProviding,
               let previewVC = provider.recordPreviewViewController {
                return previewVC
            }
            // Otherwise, wrap a dedicated RECORD preview view if available
            if let viewProvider = controller as? RecordPreviewViewProviding,
               let previewView = viewProvider.recordPreviewView {
                let wrapper = UIViewController()
                previewView.translatesAutoresizingMaskIntoConstraints = false
                wrapper.view.addSubview(previewView)
                NSLayoutConstraint.activate([
                    previewView.topAnchor.constraint(equalTo: wrapper.view.topAnchor),
                    previewView.bottomAnchor.constraint(equalTo: wrapper.view.bottomAnchor),
                    previewView.leadingAnchor.constraint(equalTo: wrapper.view.leadingAnchor),
                    previewView.trailingAnchor.constraint(equalTo: wrapper.view.trailingAnchor)
                ])
                return wrapper
            }
            // Fallback to generic preview if record-specific preview isn't available
            if let genericVCProvider = controller as? PreviewViewControllerProviding,
               let genericVC = genericVCProvider.previewViewController {
                return genericVC
            }
            if let genericViewProvider = controller as? PreviewViewProviding,
               let genericView = genericViewProvider.previewView {
                let wrapper = UIViewController()
                genericView.translatesAutoresizingMaskIntoConstraints = false
                wrapper.view.addSubview(genericView)
                NSLayoutConstraint.activate([
                    genericView.topAnchor.constraint(equalTo: wrapper.view.topAnchor),
                    genericView.bottomAnchor.constraint(equalTo: wrapper.view.bottomAnchor),
                    genericView.leadingAnchor.constraint(equalTo: wrapper.view.leadingAnchor),
                    genericView.trailingAnchor.constraint(equalTo: wrapper.view.trailingAnchor)
                ])
                return wrapper
            }
            // Final fallback placeholder
            let vc = UIViewController()
            vc.view.backgroundColor = .black
            return vc
        }

        func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
            // No-op
        }
    }
}

#Preview {
    CameraKitView(controller: CameraKitController(), coordinate: nil)
        .ignoresSafeArea()
}

