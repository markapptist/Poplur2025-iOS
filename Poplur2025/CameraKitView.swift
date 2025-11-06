import SwiftUI
import AVFoundation
import AVKit
import CoreLocation
import SCSDKCameraKit

@MainActor
struct CameraKitView: View {
    // Injected controller (stateful, owns Camera Kit session)
    @StateObject private var controller = CameraKitController()

    // Optional location tagging for uploads
    let coordinate: CLLocationCoordinate2D?

    // Local UI state for previewing captured media
    @State private var showPreview = false
    @State private var capturedImage: UIImage?
    @State private var capturedVideoURL: URL?
    @State private var isPressing = false

    // Match HomeView/controls spacing
    private let tabBarHeight: CGFloat = 88

    var body: some View {
        ZStack {
            // Live camera preview via Camera Kit PreviewView
            CameraKitPreviewContainer(controller: controller)
                .ignoresSafeArea()
                .background(Color.clear)

            // Bottom controls
            VStack {
                Spacer()

                HStack(spacing: 60) {
                    // Left thumbnail
                    Button {
                        if let img = controller.lastPhoto {
                            capturedImage = img
                            capturedVideoURL = nil
                            showPreview = true
                        } else if let url = controller.lastVideoURL {
                            capturedImage = nil
                            capturedVideoURL = url
                            showPreview = true
                        }
                    } label: {
                        ZStack {
                            if let img = controller.lastPhoto {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                            } else if controller.lastVideoURL != nil {
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
                        controller.switchCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(18)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.bottom, tabBarHeight)

                // Mode selector
                HStack(spacing: 24) {
                    modeLabel("VIDEO", isActive: controller.mode == .video)
                        .onTapGesture { controller.mode = .video }
                    modeLabel("PHOTO", isActive: controller.mode == .photo)
                        .onTapGesture { controller.mode = .photo }
                }
                .padding(.bottom, 28 + tabBarHeight)
            }
            .padding(.horizontal)
        }
        .background(Color.clear)
        .onAppear {
            Task { await controller.start() }
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: controller.lastPhoto) { img in
            guard let img else { return }
            capturedImage = img
            capturedVideoURL = nil
            showPreview = true
        }
        .onChange(of: controller.lastVideoURL) { url in
            guard let url else { return }
            capturedImage = nil
            capturedVideoURL = url
            showPreview = true
        }
        .sheet(isPresented: $showPreview) {
            CameraKitCapturePreviewView(
                image: capturedImage,
                videoURL: capturedVideoURL,
                coordinate: coordinate
            )
        }
    }

    private var captureButton: some View {
        Button {
            switch controller.mode {
            case .photo:
                controller.takePhoto()
            case .video:
                break
            }
        } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.95))
                Circle().stroke(Color.white, lineWidth: 4)
                Circle()
                    .fill(controller.mode == .video ? Color.red : Color.white)
                    .padding(10)
                    .scaleEffect(controller.isRecording ? 0.9 : 1.0)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.05)
                .onChanged { _ in
                    guard controller.mode == .video, !controller.isRecording else { return }
                    controller.startRecording()
                    isPressing = true
                }
                .onEnded { _ in
                    guard controller.mode == .video else { return }
                    controller.stopRecording()
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

// UIKit wrapper for SCSDKCameraKit.PreviewView inside SwiftUI
private struct CameraKitPreviewContainer: UIViewRepresentable {
    let controller: CameraKitController

    func makeUIView(context: Context) -> UIView {
        let view = controller.makePreviewView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// Local copy of the capture preview (mirrors CameraView’s behavior)
private struct CameraKitCapturePreviewView: View {
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
                    VideoPlayer(player: AVPlayer(url: videoURL))
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
