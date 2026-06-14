//
//  CameraRollButton.swift
//  Poplur2025
//
//  Camera roll preview button with thumbnail and photo picker
//

import SwiftUI
import Photos

/// Camera roll button showing latest photo thumbnail
/// Tapping opens photo picker to select image or video to upload
struct CameraRollButton: View {
    @State private var latestPhoto: UIImage? = nil
    @State private var previewImage: UIImage? = nil
    @State private var previewVideoURL: URL? = nil
    @State private var showCapturePreview: Bool = false
    
    var body: some View {
        NavigationLink(destination: PhotoPickerNavigationView(
            onImageSelected: { image in
                handleSelectedImage(image)
            },
            onVideoSelected: { url in
                handleSelectedVideo(url)
            }
        )) {
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
        .fullScreenCover(isPresented: $showCapturePreview, onDismiss: {
            previewImage = nil
            previewVideoURL = nil
        }) {
            CapturePreviewOverlay(image: previewImage, videoURL: previewVideoURL)
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
    
    // MARK: - Media Handling
    
    private func handleSelectedImage(_ image: UIImage) {
        print("[CameraRollButton] Image selected from camera roll")
        previewImage = image
        previewVideoURL = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showCapturePreview = true
        }
    }
    
    private func handleSelectedVideo(_ url: URL) {
        print("[CameraRollButton] Video selected from camera roll: \(url)")
        previewImage = nil
        previewVideoURL = copyVideoToTemporaryFileIfNeeded(url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showCapturePreview = true
        }
    }

    private func copyVideoToTemporaryFileIfNeeded(_ url: URL) -> URL {
        guard url.isFileURL else { return url }

        let fileExtension = url.pathExtension.isEmpty ? "mov" : url.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("camera-roll-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            print("[CameraRollButton] Failed to copy selected video: \(error)")
            return url
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

// MARK: - Photo Picker Navigation View

/// Navigation wrapper for photo picker - shows picker in navigation stack instead of sheet
struct PhotoPickerNavigationView: View {
    let onImageSelected: (UIImage) -> Void
    let onVideoSelected: (URL) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        PhotoPickerRepresentable(
            onImageSelected: { image in
                onImageSelected(image)
                dismiss()
            },
            onVideoSelected: { url in
                onVideoSelected(url)
                dismiss()
            },
            onCancel: {
                dismiss()
            }
        )
        .navigationTitle("Camera Roll")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea()
    }
}

// MARK: - Photo Picker Representable

struct PhotoPickerRepresentable: UIViewControllerRepresentable {
    let onImageSelected: (UIImage) -> Void
    let onVideoSelected: (URL) -> Void
    let onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image", "public.movie"]
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            onImageSelected: onImageSelected,
            onVideoSelected: onVideoSelected,
            onCancel: onCancel
        )
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageSelected: (UIImage) -> Void
        let onVideoSelected: (URL) -> Void
        let onCancel: () -> Void
        
        init(onImageSelected: @escaping (UIImage) -> Void, onVideoSelected: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onImageSelected = onImageSelected
            self.onVideoSelected = onVideoSelected
            self.onCancel = onCancel
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImageSelected(image)
            } else if let videoURL = info[.mediaURL] as? URL {
                onVideoSelected(videoURL)
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
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
