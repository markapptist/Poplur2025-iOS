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
    @State private var showScreenFlash: Bool = false
    @State private var isRecording: Bool = false
    @State private var flashPhase: Bool = false
    @State private var lastVideoURL: URL? = nil
    @State private var lastVideoThumbnail: UIImage? = nil
    @StateObject private var userRecognition = UserRecognitionManager()

    init(controller: CameraKitController, coordinate: CLLocationCoordinate2D?) {
        self.controller = controller
        self.coordinate = coordinate
    }

    var body: some View {
        ZStack {
            if isVisible {
                LazyCameraPreview(controller: controller, coordinate: coordinate)
                    .allowsHitTesting(!isRecording)
            } else {
                Color.black
            }

            // Screen flash overlay for front camera
            if showScreenFlash {
                Rectangle()
                    .fill(Color.white)
                    .ignoresSafeArea()
                    .blendMode(.screen)
                    .zIndex(10)
                    .transition(.opacity)
            }

            VStack {
                HStack {
                    Text(userRecognition.recognizedUser != nil ? "@\(userRecognition.recognizedUser!.profile.username)" : (userRecognition.isRecognizing ? "Scanning…" : "No user"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)
                Spacer()
            }
            .allowsHitTesting(false)
            .zIndex(5)

            // User recognition overlay
            UserRecognitionOverlay(recognitionManager: userRecognition)
                .allowsHitTesting(!isRecording) // Don't block camera gestures, disable when recording
                .zIndex(4)
                .padding(.top, 8)

            // Recording overlay: flashing cube with REC circle
            if isRecording {
                GeometryReader { geo in
                    ZStack {
                        // Transparent flashing cube (square) centered
                        let size = min(geo.size.width, geo.size.height) * 0.25
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.8), lineWidth: 2)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(flashPhase ? 0.15 : 0.05))
                            )
                            .frame(width: size, height: size)
                            .overlay(
                                // REC circle in the center
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: size * 0.25, height: size * 0.25)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: flashPhase)
                            .onAppear { flashPhase.toggle() }
                    }
                }
                .allowsHitTesting(false)
                .zIndex(6)
            }

            // Last capture thumbnail (video)
            if let url = lastVideoURL {
                VStack {
                    HStack {
                        ZStack {
                            Group {
                                if let thumb = lastVideoThumbnail {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Rectangle().fill(Color.black.opacity(0.4))
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipped()
                            .overlay(
                                Image(systemName: "video.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(.white)
                                    .shadow(radius: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
                            )
                            .shadow(radius: 2)
                            .opacity(isRecording ? 0.6 : 1)
                            .accessibilityLabel("Last video")
                        }
                        .onTapGesture {
                            if let url = lastVideoURL {
                                NotificationCenter.default.post(name: Notification.Name("PresentVideoPreviewRequested"), object: url)
                            }
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.leading, 16)
                .zIndex(7)
                .allowsHitTesting(!isRecording)
            }

            VStack {
                Spacer()
            }
            .padding(.top, 16)
        }
        .ignoresSafeArea()
        .onAppear {
            isVisible = true
            // Prewarm and ensure preview is ready when the tab first appears
            Task { @MainActor in
                // Connect user recognition to controller
                controller.userRecognitionManager = userRecognition
                
                await controller.prewarm()
                await controller.startPreview()
                controller.preparePreviewIfNeeded()
                
                // Start user recognition
                await userRecognition.startRecognitionSession()
                print("👤 [UserRecognition] Session started")
            }
        }
        .onDisappear {
            isVisible = false
            userRecognition.clearRecognition()
            controller.userRecognitionManager = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ScreenFlashOn"))) { _ in
            withAnimation(.easeIn(duration: 0.1)) {
                showScreenFlash = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ScreenFlashOff"))) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                showScreenFlash = false
            }
        }
        .onReceive(controller.$isRecording.removeDuplicates()) { rec in
            withAnimation(.easeInOut(duration: 0.2)) {
                isRecording = rec
            }
        }
        .onReceive(controller.$lastVideoURL) { url in
            lastVideoURL = url
            guard let url else { lastVideoThumbnail = nil; return }
            // Generate a thumbnail asynchronously
            Task { @MainActor in
                lastVideoThumbnail = await generateVideoThumbnail(from: url)
            }
        }
        .onChange(of: userRecognition.recognizedUser?.profile.username) { oldUsername, newUsername in
            if let user = userRecognition.recognizedUser {
                print("👤 [UserRecognition] Recognized user: @\(user.profile.username) (confidence: \(Int(user.confidence*100))%)")
            }
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

    private func generateVideoThumbnail(from url: URL) async -> UIImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                do {
                    let imageRef = try generator.copyCGImage(at: time, actualTime: nil)
                    let image = UIImage(cgImage: imageRef)
                    cont.resume(returning: image)
                } catch {
                    print("[Thumb] Failed to generate thumbnail: \(error)")
                    cont.resume(returning: nil)
                }
            }
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

