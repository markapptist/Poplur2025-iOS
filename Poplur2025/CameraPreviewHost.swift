import SwiftUI
import AVFoundation
import CoreLocation
import UIKit

struct CameraPreviewHost: View {
    let controller: CameraKitController
    let coordinate: CLLocationCoordinate2D?
    
    init(controller: CameraKitController, coordinate: CLLocationCoordinate2D?) {
        self.controller = controller
        self.coordinate = coordinate
    }
    
    var body: some View {
        ControllerPreviewView(controller: controller)
    }
}

struct ControllerPreviewView: UIViewControllerRepresentable {
    let controller: CameraKitController
    
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
        // Final fallback placeholder: black background, no label
        let vc = UIViewController()
        vc.view.backgroundColor = .black
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // no-op
    }
    
    static func buildFallbackController() -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .black
        return vc
    }
}

#if DEBUG
@available(iOS 15.0, *)
struct CameraPreviewHost_Previews: PreviewProvider {
    static var previews: some View {
        CameraPreviewHost(controller: CameraKitController(), coordinate: nil)
            .ignoresSafeArea()
    }
}
#endif

