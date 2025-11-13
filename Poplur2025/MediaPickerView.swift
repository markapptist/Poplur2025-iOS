import SwiftUI
import UIKit
import FirebaseStorage
import FirebaseFirestore
import CoreLocation
import FirebaseAuth
import AVFoundation

struct MediaPickerView: View {
    @Environment(\.dismiss) private var dismiss  // To go back to previous view

    // Original selections
    @State private var selectedImage: UIImage?
    @State private var selectedVideoURL: URL?

    // Lightweight preview to avoid rendering full-res in SwiftUI
    @State private var previewImage: UIImage?

    // Processed (downscaled/compressed) data to upload
    @State private var preparedImageData: Data?
    @State private var preparedVideoURL: URL?          // MP4 after transcode if video
    @State private var preparedPosterJPEG: Data?       // poster for video

    @State private var showImagePicker = false
    @State private var mediaSourceType: UIImagePickerController.SourceType = .photoLibrary

    // Permission / error handling
    @State private var showPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    // Upload state
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0

    // Cancellable preparation task
    @State private var prepTask: Task<Void, Never>?

    var location: CLLocationCoordinate2D

    var body: some View {
        VStack(spacing: 16) {
            // Preview area
            if let previewImage = previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .interpolation(.low) // reduce sampling cost during debug/preview
                    .scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 300)
                    .cornerRadius(10)
            } else if selectedVideoURL != nil {
                Text("Video selected")
                    .font(.subheadline)
            } else {
                Text("Pick an image or video")
                    .font(.headline)
                    .padding(.top)
            }

            // Progress UI
            if isUploading {
                VStack(spacing: 8) {
                    ProgressView(value: uploadProgress)
                        .progressViewStyle(.linear)
                    Text(String(format: "Uploading… %.0f%%", uploadProgress * 100))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            HStack(spacing: 16) {
                Button {
                    handleCameraTapped()
                } label: {
                    Label("Camera", systemImage: "camera")
                }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera) || isUploading)

                Button {
                    mediaSourceType = .photoLibrary
                    showImagePicker = true
                } label: {
                    Label("Library", systemImage: "photo.on.rectangle")
                }
                .disabled(isUploading)
            }
            .padding(.top)

            Button {
                Task { await uploadMedia() }
            } label: {
                Label(isUploading ? "Posting…" : "Post", systemImage: "paperplane.fill")
                    .font(.headline)
            }
            .disabled((preparedImageData == nil && preparedVideoURL == nil) || isUploading)
            .padding(.top, 8)

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showImagePicker) {
            LegacyPickerWrapper(
                selectedImage: $selectedImage,
                selectedVideoURL: $selectedVideoURL,
                sourceType: mediaSourceType
            )
            .onDisappear {
                // Prepare media off-main after picker closes
                startPreparation()
            }
        }
        .alert("Camera Access Needed", isPresented: $showPermissionAlert, actions: {
            Button("OK", role: .cancel) { }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        }, message: {
            Text(permissionAlertMessage)
        })
        .alert("Error", isPresented: $showErrorAlert, actions: {
            Button("OK", role: .cancel) { }
        }, message: {
            Text(errorMessage)
        })
        .onChange(of: selectedImage) { _ in
            startPreparation()
        }
        .onChange(of: selectedVideoURL) { _ in
            startPreparation()
        }
        .onDisappear {
            // Cancel any ongoing preparation when leaving
            prepTask?.cancel()
            prepTask = nil
        }
    }

    private func handleCameraTapped() {
        // Ensure camera is available first
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            permissionAlertMessage = "Camera is not available on this device."
            showPermissionAlert = true
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            mediaSourceType = .camera
            showImagePicker = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        mediaSourceType = .camera
                        showImagePicker = true
                    } else {
                        permissionAlertMessage = "Camera access is required to capture photos or videos. You can enable it in Settings."
                        showPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            permissionAlertMessage = "Camera access is disabled. Please enable it in Settings to use the camera."
            showPermissionAlert = true
        @unknown default:
            permissionAlertMessage = "Unknown camera permission state."
            showPermissionAlert = true
        }
    }

    // MARK: - Preparation (cancellable) to reduce lag/overlap

    @MainActor
    private func clearPreparation() {
        preparedImageData = nil
        preparedVideoURL = nil
        preparedPosterJPEG = nil
        uploadProgress = 0
    }

    private func startPreparation() {
        // Cancel any ongoing preparation
        prepTask?.cancel()
        prepTask = Task {
            await prepareSelectedMedia()
        }
    }

    private func prepareSelectedMedia() async {
        await MainActor.run {
            // Reset prepared outputs
            clearPreparation()
            uploadProgress = 0
        }

        // Early exit if task was cancelled
        if Task.isCancelled { return }

        if let image = selectedImage {
            // Create preview and upload-sized JPEG off-main
            let targetUploadMaxDimension: CGFloat = 1600   // good balance quality/size
            let previewMaxDimension: CGFloat = 600         // light for UI

            let (preview, uploadData) = await withCheckedContinuation { (continuation: CheckedContinuation<(UIImage?, Data?), Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    if Task.isCancelled {
                        continuation.resume(returning: (nil, nil))
                        return
                    }
                    let preview = image.resized(maxDimension: previewMaxDimension)
                    if Task.isCancelled {
                        continuation.resume(returning: (nil, nil))
                        return
                    }
                    let uploadImage = image.resized(maxDimension: targetUploadMaxDimension)
                    let data = uploadImage?.jpegData(compressionQuality: 0.75)
                    continuation.resume(returning: (preview, data))
                }
            }

            if Task.isCancelled { return }

            await MainActor.run {
                self.previewImage = preview
                self.preparedImageData = uploadData
                self.selectedVideoURL = nil // ensure only one media type active
            }
        } else if let videoURL = selectedVideoURL {
            // Transcode to MP4 (fast start) and create poster image off-main
            do {
                let (mp4URL, posterData) = try await transcodeToMP4AndPoster(from: videoURL)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.previewImage = posterData.flatMap { UIImage(data: $0) }
                    self.preparedVideoURL = mp4URL
                    self.preparedPosterJPEG = posterData
                    self.selectedImage = nil
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.previewImage = nil
                    self.preparedVideoURL = nil
                    self.preparedPosterJPEG = nil
                    self.errorMessage = "Video preparation failed: \(error.localizedDescription)"
                    self.showErrorAlert = true
                }
            }
        } else {
            await MainActor.run {
                self.previewImage = nil
            }
        }
    }

    // MARK: - Upload

    private func uploadMedia() async {
        guard !isUploading else { return }
        await MainActor.run {
            isUploading = true
            uploadProgress = 0
        }

        do {
            if let data = preparedImageData {
                let urlString = try await uploadImageData(data)
                try await savePostToFirestore(mediaURL: urlString, posterURL: nil)
            } else if let fileURL = preparedVideoURL {
                let (mediaURL, posterURL) = try await uploadVideoFile(fileURL, posterJPEG: preparedPosterJPEG)
                try await savePostToFirestore(mediaURL: mediaURL, posterURL: posterURL)
            }
            await MainActor.run {
                isUploading = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                isUploading = false
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func uploadImageData(_ data: Data) async throws -> String {
        let storageRef = Storage.storage().reference()
        let imageRef = storageRef.child("media/\(UUID().uuidString).jpg")

        // Put data with progress
        return try await withCheckedThrowingContinuation { continuation in
            let task = imageRef.putData(data, metadata: nil) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                imageRef.downloadURL { url, err in
                    if let err = err {
                        continuation.resume(throwing: err)
                    } else if let url = url {
                        continuation.resume(returning: url.absoluteString)
                    } else {
                        continuation.resume(throwing: NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing download URL"]))
                    }
                }
            }

            task.observe(.progress) { snapshot in
                if let fraction = snapshot.progress?.fractionCompleted {
                    Task { @MainActor in
                        self.uploadProgress = fraction
                    }
                }
            }
        }
    }

    private func uploadVideoFile(_ fileURL: URL, posterJPEG: Data?) async throws -> (mediaURL: String, posterURL: String?) {
        let storageRef = Storage.storage().reference()
        let id = UUID().uuidString
        let videoRef = storageRef.child("media/\(id).mp4")
        let posterRef = storageRef.child("media/\(id)_poster.jpg")

        // Upload video
        let mediaURL: String = try await withCheckedThrowingContinuation { continuation in
            let task = videoRef.putFile(from: fileURL, metadata: nil) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                videoRef.downloadURL { url, err in
                    if let err = err {
                        continuation.resume(throwing: err)
                    } else if let url = url {
                        continuation.resume(returning: url.absoluteString)
                    } else {
                        continuation.resume(throwing: NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing download URL"]))
                    }
                }
            }

            task.observe(.progress) { snapshot in
                if let fraction = snapshot.progress?.fractionCompleted {
                    Task { @MainActor in
                        self.uploadProgress = fraction
                    }
                }
            }
        }

        // Upload poster if available
        var posterURLString: String? = nil
        if let posterJPEG, !posterJPEG.isEmpty {
            posterURLString = try await withCheckedThrowingContinuation { continuation in
                let task = posterRef.putData(posterJPEG, metadata: nil) { _, error in
                    if let error = error {
                        // Non-fatal: still return mediaURL
                        print("Poster upload failed: \(error.localizedDescription)")
                        continuation.resume(returning: nil)
                        return
                    }
                    posterRef.downloadURL { url, err in
                        if let err = err {
                            print("Poster download URL failed: \(err.localizedDescription)")
                            continuation.resume(returning: nil)
                        } else {
                            continuation.resume(returning: url?.absoluteString)
                        }
                    }
                }
                task.observe(.progress) { _ in
                    // Optional: you could combine progress, but we’ll leave primary progress as video.
                }
            }
        }

        return (mediaURL, posterURLString)
    }

    private func savePostToFirestore(mediaURL: String, posterURL: String?) async throws {
        let db = Firestore.firestore()
        var post: [String: Any] = [
            "latitude": location.latitude,
            "longitude": location.longitude,
            "mediaURL": mediaURL,
            "radius": 5000, // Initial 5km radius
            "viewCount": 0,
            "createdAt": FieldValue.serverTimestamp(),
            "createdAtMillis": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let uid = Auth.auth().currentUser?.uid {
            post["userID"] = uid
        }
        if let posterURL, !posterURL.isEmpty {
            post["posterURL"] = posterURL
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("posts").addDocument(data: post) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

// A thin wrapper to pass sourceType into UIImagePickerController-based picker
private struct LegacyPickerWrapper: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var selectedVideoURL: URL?
    let sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.mediaTypes = ["public.image", "public.movie"]
        picker.allowsEditing = false
        picker.sourceType = sourceType
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: LegacyPickerWrapper
        init(parent: LegacyPickerWrapper) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            // Reset the other media type to avoid both being set
            if let image = info[.originalImage] as? UIImage {
                parent.selectedVideoURL = nil
                parent.selectedImage = image
            } else if let videoURL = info[.mediaURL] as? URL {
                parent.selectedImage = nil
                parent.selectedVideoURL = videoURL
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Image resize helper

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage? {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        // Use UIGraphicsImageRenderer for performance and color management
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1 // we are controlling pixel size directly
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Video transcode + poster

private extension MediaPickerView {
    func transcodeToMP4AndPoster(from originalURL: URL) async throws -> (mp4URL: URL, posterJPEG: Data?) {
        // Build asset
        let asset = AVURLAsset(url: originalURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])

        // Pick a good preset; prefer highest compatible, fall back to 1280x720 for speed/size
        let preset: String
        if AVAssetExportSession.exportPresets(compatibleWith: asset).contains(AVAssetExportPresetHighestQuality) {
            preset = AVAssetExportPresetHighestQuality
        } else if AVAssetExportSession.exportPresets(compatibleWith: asset).contains(AVAssetExportPreset1280x720) {
            preset = AVAssetExportPreset1280x720
        } else {
            preset = AVAssetExportPresetPassthrough // last resort
        }

        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        // Export
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
                cont.resume(throwing: NSError(domain: "Transcode", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot create exporter"]))
                return
            }
            exporter.outputURL = outURL
            exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse = true // move moov atom to front
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    cont.resume()
                case .failed, .cancelled:
                    let err = exporter.error ?? NSError(domain: "Transcode", code: -2, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
                    cont.resume(throwing: err)
                default:
                    // Unknown or waiting; treat as failure to be safe
                    let err = exporter.error ?? NSError(domain: "Transcode", code: -3, userInfo: [NSLocalizedDescriptionKey: "Export did not complete"])
                    cont.resume(throwing: err)
                }
            }
        }

        // Generate poster at ~1 second or mid-duration if shorter
        var posterData: Data? = nil
        do {
            let duration = try await asset.load(.duration)
            let totalSeconds = CMTimeGetSeconds(duration)
            let captureTime = CMTime(seconds: min(max(0.5, totalSeconds * 0.25), max(1.0, totalSeconds - 0.5)), preferredTimescale: 600)

            if Task.isCancelled { return (outURL, nil) }

            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 800, height: 800) // modest size
            let cg = try gen.copyCGImage(at: captureTime, actualTime: nil)
            let ui = UIImage(cgImage: cg)
            posterData = ui.jpegData(compressionQuality: 0.7)
        } catch {
            // Non-fatal; continue without poster
            posterData = nil
        }

        return (outURL, posterData)
    }
}

struct MediaPickerView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock location for preview
        MediaPickerView(location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
