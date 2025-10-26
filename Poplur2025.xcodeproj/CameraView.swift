import SwiftUI
import AVFoundation
import CoreLocation

// UIViewRepresentable for AVCaptureVideoPreviewLayer
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = UIScreen.main.bounds
        view.layer.addSublayer(layer)
        context.coordinator.previewLayer = layer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

struct CameraView: View {
    @StateObject private var camera = CameraSession()
    @State private var showPreview = false
    @State private var capturedImage: UIImage?
    @State private var capturedVideoURL: URL?
    @State private var isPressing = false

    // Location to tag uploads
    let coordinate: CLLocationCoordinate2D?

    var body: some View {
        ZStack {
            // Live camera
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            // Optional square overlay guide
            Rectangle()
                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                .frame(width: 280, height: 280)
                .opacity(0.9)
                .allowsHitTesting(false)

            // Bottom controls
            VStack {
                Spacer()

                HStack(spacing: 60) {
                    // Left thumbnail
                    Button {
                        if let img = camera.lastPhoto {
                            capturedImage = img
                            capturedVideoURL = nil
                            showPreview = true
                        } else if let url = camera.lastVideoURL {
                            capturedImage = nil
                            capturedVideoURL = url
                            showPreview = true
                        }
                    } label: {
                        ZStack {
                            if let img = camera.lastPhoto {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                            } else if let url = camera.lastVideoURL {
                                // Simple placeholder for video; could generate thumbnail
                                Image(systemName: "video.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(10)
                                    .foregroundColor(.white)
                                    .background(Color.black.opacity(0.3))
                            } else {
                                Image(systemName: "photo")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(10)
                                    .foregroundColor(.white)
                                    .background(Color.black.opacity(0.3))
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }

                    // Big capture button
                    captureButton
                        .frame(width: 84, height: 84)

                    // Flip camera
                    Button {
                        camera.switchCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(18)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.bottom, 20)

                // Mode selector
                HStack(spacing: 24) {
                    modeLabel("VIDEO", isActive: camera.mode == .video)
                        .onTapGesture { camera.mode = .video }
                    modeLabel("PHOTO", isActive: camera.mode == .photo)
                        .onTapGesture { camera.mode = .photo }
                }
                .padding(.bottom, 28)
            }
            .padding(.horizontal)
        }
        .onAppear {
            AVCaptureDevice.requestAccess(for: .video) { _ in
                // microphone only needed for video recording
            }
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .onChange(of: camera.lastPhoto) { img in
            guard let img else { return }
            capturedImage = img
            capturedVideoURL = nil
            showPreview = true
        }
        .onChange(of: camera.lastVideoURL) { url in
            guard let url else { return }
            capturedImage = nil
            capturedVideoURL = url
            showPreview = true
        }
        .sheet(isPresented: $showPreview) {
            CapturePreviewView(
                image: capturedImage,
                videoURL: capturedVideoURL,
                coordinate: coordinate
            )
        }
    }

    private var captureButton: some View {
        Button {
            switch camera.mode {
            case .photo:
                camera.takePhoto()
            case .video:
                // For video we’ll start on press and stop on release (long-press feel)
                // But Button doesn’t expose press states; use simultaneous gesture:
                break
            }
        } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.95))
                Circle().stroke(Color.white, lineWidth: 4)
                Circle()
                    .fill(camera.mode == .video ? Color.red : Color.white)
                    .padding(10)
                    .scaleEffect(camera.isRecording ? 0.9 : 1.0)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.05)
                .onChanged { _ in
                    guard camera.mode == .video, !camera.isRecording else { return }
                    camera.startRecording()
                    isPressing = true
                }
                .onEnded { _ in
                    guard camera.mode == .video else { return }
                    camera.stopRecording()
                    isPressing = false
                }
        )
    }

    private func modeLabel(_ text: String, isActive: Bool) -> some View {
        VStack(spacing: 6) {
            Text(text)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .kerning(0.5)
                .foregroundColor(isActive ? .white : .white.opacity(0.55))
            Rectangle()
                .fill(isActive ? Color.white : Color.clear)
                .frame(width: 24, height: 2)
        }
    }
}

// Simple preview/confirm uploader
private struct CapturePreviewView: View {
    let image: UIImage?
    let videoURL: URL?
    let coordinate: CLLocationCoordinate2D?

    @Environment(\.dismiss) private var dismiss
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                } else if let videoURL {
                    VideoPlayerView(url: videoURL)
                        .ignoresSafeArea()
                } else {
                    Text("Nothing captured").foregroundColor(.white)
                }

                if isUploading {
                    VStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Uploading…").foregroundColor(.white)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Retake") { dismiss() }
                        .tint(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use") { upload() }
                        .tint(.white)
                        .disabled(isUploading)
                }
            }
        }
    }

    private func upload() {
        guard !isUploading else { return }
        isUploading = true
        let coord = coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)

        // Use your existing MediaPickerView Firestore upload logic:
        if let image {
            UploadBridge.uploadImage(image: image, coordinate: coord) { success, err in
                isUploading = false
                if success { dismiss() } else { errorMessage = err }
            }
        } else if let url = videoURL {
            UploadBridge.uploadVideo(url: url, coordinate: coord) { success, err in
                isUploading = false
                if success { dismiss() } else { errorMessage = err }
            }
        } else {
            isUploading = false
        }
    }
}

// Minimal player for previewing captured video
import AVKit
private struct VideoPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player = AVPlayer(url: url); player?.play() }
            .onDisappear { player?.pause() }
    }
}

// Bridge that reuses your existing MediaPickerView upload code paths
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth

enum UploadBridge {
    static func uploadImage(image: UIImage, coordinate: CLLocationCoordinate2D, completion: @escaping (Bool, String?) -> Void) {
        let storageRef = Storage.storage().reference()
        let imageRef = storageRef.child("media/\(UUID().uuidString).jpg")
        guard let data = image.jpegData(compressionQuality: 0.75) else {
            completion(false, "Failed to encode image.")
            return
        }
        imageRef.putData(data, metadata: nil) { _, error in
            if let error = error { completion(false, error.localizedDescription); return }
            imageRef.downloadURL { url, error in
                if let error = error { completion(false, error.localizedDescription); return }
                guard let url else { completion(false, "No URL"); return }
                savePostToFirestore(mediaURL: url.absoluteString, coordinate: coordinate, completion: completion)
            }
        }
    }

    static func uploadVideo(url: URL, coordinate: CLLocationCoordinate2D, completion: @escaping (Bool, String?) -> Void) {
        let storageRef = Storage.storage().reference()
        let videoRef = storageRef.child("media/\(UUID().uuidString).mov")
        videoRef.putFile(from: url, metadata: nil) { _, error in
            if let error = error { completion(false, error.localizedDescription); return }
            videoRef.downloadURL { url, error in
                if let error = error { completion(false, error.localizedDescription); return }
                guard let url else { completion(false, "No URL"); return }
                savePostToFirestore(mediaURL: url.absoluteString, coordinate: coordinate, completion: completion)
            }
        }
    }

    private static func savePostToFirestore(mediaURL: String, coordinate: CLLocationCoordinate2D, completion: @escaping (Bool, String?) -> Void) {
        let db = Firestore.firestore()
        var post: [String: Any] = [
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "mediaURL": mediaURL,
            "radius": 5000,
            "viewCount": 0
        ]
        if let uid = Auth.auth().currentUser?.uid {
            post["userID"] = uid
        }
        db.collection("posts").addDocument(data: post) { error in
            if let error = error { completion(false, error.localizedDescription) }
            else { completion(true, nil) }
        }
    }
}
