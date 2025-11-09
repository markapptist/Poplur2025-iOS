import SwiftUI
import UIKit
import FirebaseStorage
import FirebaseFirestore
import CoreLocation
import FirebaseAuth
import AVFoundation

struct MediaPickerView: View {
    @Environment(\.dismiss) private var dismiss  // To go back to previous view
    @State private var selectedImage: UIImage?
    @State private var selectedVideoURL: URL?
    @State private var showImagePicker = false
    @State private var mediaSourceType: UIImagePickerController.SourceType = .photoLibrary

    // Permission / error handling
    @State private var showPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var location: CLLocationCoordinate2D

    var body: some View {
        VStack(spacing: 16) {
            if let selectedImage = selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
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

            HStack(spacing: 16) {
                Button {
                    handleCameraTapped()
                } label: {
                    Label("Camera", systemImage: "camera")
                }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                Button {
                    mediaSourceType = .photoLibrary
                    showImagePicker = true
                } label: {
                    Label("Library", systemImage: "photo.on.rectangle")
                }
            }
            .padding(.top)

            Button {
                uploadMedia()
            } label: {
                Label("Post", systemImage: "paperplane.fill")
                    .font(.headline)
            }
            .disabled(selectedImage == nil && selectedVideoURL == nil)
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

    func uploadMedia() {
        if let selectedImage = selectedImage {
            uploadImage(image: selectedImage)
        } else if let selectedVideoURL = selectedVideoURL {
            uploadVideo(url: selectedVideoURL)
        }
    }

    func uploadImage(image: UIImage) {
        let storageRef = Storage.storage().reference()
        let imageRef = storageRef.child("media/\(UUID().uuidString).jpg")

        if let imageData = image.jpegData(compressionQuality: 0.75) {
            imageRef.putData(imageData, metadata: nil) { metadata, error in
                if let error = error {
                    errorMessage = "Error uploading image: \(error.localizedDescription)"
                    print(errorMessage)
                    showErrorAlert = true
                    return
                }

                imageRef.downloadURL { url, error in
                    if let error = error {
                        errorMessage = "Error getting image URL: \(error.localizedDescription)"
                        print(errorMessage)
                        showErrorAlert = true
                        return
                    }
                    if let mediaURL = url {
                        savePostToFirestore(mediaURL: mediaURL.absoluteString)
                    }
                }
            }
        } else {
            errorMessage = "Failed to encode image."
            print(errorMessage)
            showErrorAlert = true
        }
    }

    func uploadVideo(url: URL) {
        let storageRef = Storage.storage().reference()
        let videoRef = storageRef.child("media/\(UUID().uuidString).mov")

        videoRef.putFile(from: url, metadata: nil) { metadata, error in
            if let error = error {
                errorMessage = "Error uploading video: \(error.localizedDescription)"
                print(errorMessage)
                showErrorAlert = true
                return
            }

            videoRef.downloadURL { url, error in
                if let error = error {
                    errorMessage = "Error getting video URL: \(error.localizedDescription)"
                    print(errorMessage)
                    showErrorAlert = true
                    return
                }
                if let mediaURL = url {
                    savePostToFirestore(mediaURL: mediaURL.absoluteString)
                }
            }
        }
    }

    func savePostToFirestore(mediaURL: String) {
        let db = Firestore.firestore()
        var post: [String: Any] = [
            "latitude": location.latitude,
            "longitude": location.longitude,
            "mediaURL": mediaURL,
            "radius": 5000, // Initial 5km radius
            "viewCount": 0,
            // Add createdAt so ProfileView/MapView order queries work
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let uid = Auth.auth().currentUser?.uid {
            post["userID"] = uid
        }

        db.collection("posts").addDocument(data: post) { error in
            if let error = error {
                errorMessage = "Error saving post: \(error.localizedDescription)"
                print(errorMessage)
                showErrorAlert = true
            } else {
                dismiss()
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

struct MediaPickerView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock location for preview
        MediaPickerView(location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
