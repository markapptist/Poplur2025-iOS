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
        }
        .ignoresSafeArea()
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
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

