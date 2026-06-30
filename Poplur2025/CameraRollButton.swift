//
//  CameraRollButton.swift
//  Poplur2025
//
//  Camera roll preview button with thumbnail and photo picker
//

import SwiftUI
import UIKit
import Photos
import PhotosUI
import UniformTypeIdentifiers

/// Camera roll button showing latest photo thumbnail
/// Tapping opens photo picker to select image or video to upload
struct CameraRollButton: View {
    @State private var latestPhoto: UIImage? = nil
    
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .showCameraRollWindow, object: nil)
        } label: {
            ZStack {
                // Background with photo preview or placeholder
                if let photo = latestPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(0.6))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "photo.on.rectangle.angled")
                        .poplurIconShader()
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                
                // Border overlay
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.4), lineWidth: 2)
                    .frame(width: 60, height: 60)
            }
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(CameraRollButtonStyle())
        .onAppear {
            fetchLatestPhoto()
        }
    }
    
    // MARK: - Photo Fetching
    
    private func fetchLatestPhoto() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        guard let asset = fetchResult.firstObject else {
            latestPhoto = nil
            return
        }
        
        let imageManager = PHImageManager.default()
        let targetSize = CGSize(width: 120, height: 120)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        
        imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            DispatchQueue.main.async {
                self.latestPhoto = image
            }
        }
    }
}

// MARK: - Camera Roll Button Style

struct CameraRollButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Camera Roll Window

struct CameraRollWindowOverlay: View {
    let onDismiss: () -> Void

    @State private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let safe = proxy.safeAreaInsets
            let width = min(max(proxy.size.width - 28, 290), 470)
            let height = min(max(proxy.size.height - safe.top - safe.bottom - 72, 420), 720)

            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                VStack(spacing: 0) {
                    header
                        .gesture(windowDragGesture)

                    CameraRollPickerRepresentable(
                        onImageSelected: { image in
                            onDismiss()
                            CameraRollSelectionDispatcher.showPreview(image: image)
                        },
                        onVideoSelected: { url in
                            onDismiss()
                            CameraRollSelectionDispatcher.showPreview(videoURL: url)
                        },
                        onCancel: onDismiss
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .frame(width: width, height: height)
                .background(windowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.5),
                                    .green.opacity(0.58),
                                    .purple.opacity(0.55),
                                    .white.opacity(0.24)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.62), radius: 24, x: 0, y: 16)
                .shadow(color: .green.opacity(0.22), radius: 18, x: 0, y: 0)
                .offset(dragOffset)
                .simultaneousGesture(swipeDownToCloseGesture)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(.white.opacity(0.58))
                .frame(width: 42, height: 5)

            Text("Camera Roll")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .poplurTextShader(intensity: 0.8)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .poplurIconShader()
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var windowBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.03, blue: 0.03).opacity(0.98),
                    Color(red: 0.05, green: 0.02, blue: 0.08).opacity(0.96),
                    Color(red: 0.01, green: 0.08, blue: 0.06).opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.18)
        }
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                if shouldClose(for: value) {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private var swipeDownToCloseGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .global)
            .onEnded { value in
                if shouldClose(for: value) {
                    onDismiss()
                }
            }
    }

    private func shouldClose(for value: DragGesture.Value) -> Bool {
        let downPull = value.translation.height > 130 && abs(value.translation.width) < 150
        let downFling = value.predictedEndTranslation.height > 240 && value.translation.height > 60
        return downPull || downFling
    }
}

// MARK: - Photo Picker Representable

private struct CameraRollPickerRepresentable: UIViewControllerRepresentable {
    let onImageSelected: (UIImage) -> Void
    let onVideoSelected: (URL) -> Void
    let onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            onImageSelected: onImageSelected,
            onVideoSelected: onVideoSelected,
            onCancel: onCancel
        )
    }
    
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImageSelected: (UIImage) -> Void
        let onVideoSelected: (URL) -> Void
        let onCancel: () -> Void
        
        init(onImageSelected: @escaping (UIImage) -> Void, onVideoSelected: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onImageSelected = onImageSelected
            self.onVideoSelected = onVideoSelected
            self.onCancel = onCancel
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                onCancel()
                return
            }

            if let videoType = firstSupportedVideoType(for: provider) {
                loadVideo(from: provider, typeIdentifier: videoType)
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [onImageSelected, onCancel] object, error in
                    DispatchQueue.main.async {
                        if let image = object as? UIImage {
                            onImageSelected(image)
                        } else {
                            if let error {
                                print("[CameraRollButton] Failed to load selected image: \(error)")
                            }
                            onCancel()
                        }
                    }
                }
            } else {
                onCancel()
            }
        }

        private func firstSupportedVideoType(for provider: NSItemProvider) -> String? {
            [
                UTType.movie.identifier,
                UTType.video.identifier,
                UTType.mpeg4Movie.identifier,
                "com.apple.quicktime-movie"
            ]
            .first { provider.hasItemConformingToTypeIdentifier($0) }
        }

        private func loadVideo(from provider: NSItemProvider, typeIdentifier: String) {
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [onVideoSelected, onCancel] url, error in
                guard let url else {
                    DispatchQueue.main.async {
                        if let error {
                            print("[CameraRollButton] Failed to load selected video: \(error)")
                        }
                        onCancel()
                    }
                    return
                }

                let fileExtension = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("camera-roll-\(UUID().uuidString)")
                    .appendingPathExtension(fileExtension)

                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                    DispatchQueue.main.async {
                        onVideoSelected(destination)
                    }
                } catch {
                    DispatchQueue.main.async {
                        print("[CameraRollButton] Failed to copy selected video: \(error)")
                        onCancel()
                    }
                }
            }
        }
    }
}

private enum CameraRollSelectionDispatcher {
    static func showPreview(image: UIImage) {
        print("[CameraRollButton] Image selected from camera roll")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NotificationCenter.default.post(
                name: Notification.Name("ShowCapturePreviewOverlay"),
                object: image
            )
        }
    }

    static func showPreview(videoURL: URL) {
        print("[CameraRollButton] Video selected from camera roll: \(videoURL)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NotificationCenter.default.post(
                name: Notification.Name("ShowCapturePreviewOverlay"),
                object: videoURL
            )
        }
    }
}

// MARK: - Preview
#if DEBUG
struct CameraRollButton_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraRollButton()
        }
        .previewDisplayName("Camera Roll Button")
    }
}
#endif
