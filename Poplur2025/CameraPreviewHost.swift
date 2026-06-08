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
            .id(controller.isReady)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenCameraAtCoordinate"))) { note in
                if let coord = note.userInfo?["coordinate"] as? CLLocationCoordinate2D {
                    NotificationCenter.default.post(
                        name: Notification.Name("SetCameraCoordinate"),
                        object: nil,
                        userInfo: [
                            "latitude": coord.latitude,
                            "longitude": coord.longitude
                        ]
                    )
                } else if
                    let lat = note.userInfo?["latitude"] as? Double,
                    let lon = note.userInfo?["longitude"] as? Double {
                    NotificationCenter.default.post(
                        name: Notification.Name("SetCameraCoordinate"),
                        object: nil,
                        userInfo: [
                            "latitude": lat,
                            "longitude": lon
                        ]
                    )
                }
            }
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
private struct RecordTabPreview: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.07),
                    Color(red: 0.12, green: 0.16, blue: 0.19)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 0)
                .fill(.black.opacity(0.18))
                .ignoresSafeArea()
                .overlay {
                    VStack(spacing: 14) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 54, weight: .semibold))
                        Text("Record Preview")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.72))
                }

            VStack(spacing: 10) {
                Text("Hold to capture")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.42), in: Capsule())

                Spacer()

                Circle()
                    .strokeBorder(.white, lineWidth: 5)
                    .background(Circle().fill(.white.opacity(0.16)))
                    .frame(width: 86, height: 86)
                    .padding(.bottom, 36)
            }
            .padding(.top, 62)
            .allowsHitTesting(false)
        }
        .background(Color.black)
    }
}

struct RecordTab_Previews: PreviewProvider {
    static var previews: some View {
        LayoutAdjustmentCanvas(tab: .record)
            .ignoresSafeArea()
            .previewDisplayName("Record Layout")
    }
}
#endif
