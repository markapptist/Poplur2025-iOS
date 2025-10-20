import SwiftUI
import UIKit
import FirebaseStorage
import FirebaseFirestore
import CoreLocation

struct MediaPickerView: View {
    @Environment(\.dismiss) private var dismiss  // To go back to MapView
    @State private var selectedImage: UIImage?
    @State private var selectedVideoURL: URL?
    @State private var showImagePicker = false
    @State private var mediaSourceType: UIImagePickerController.SourceType = .photoLibrary
    
    var location: CLLocationCoordinate2D
    
    var body: some View {
        VStack {
            if let selectedImage = selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
            } else {
                Text("Select Media")
                    .font(.headline)
                    .padding()
            }
            
            Button("Pick Image or Video") {
                self.showImagePicker.toggle()
            }
            .padding()
            
            Button("Post") {
                uploadMedia()
            }
            .padding()
        }
        .onAppear {
            // Initialize the media picker
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(selectedImage: $selectedImage, selectedVideoURL: $selectedVideoURL)
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
                    print("Error uploading image: \(error)")
                    return
                }
                
                imageRef.downloadURL { url, error in
                    if let mediaURL = url {
                        savePostToFirestore(mediaURL: mediaURL.absoluteString)
                    }
                }
            }
        }
    }
    
    func uploadVideo(url: URL) {
        let storageRef = Storage.storage().reference()
        let videoRef = storageRef.child("media/\(UUID().uuidString).mov")
        
        videoRef.putFile(from: url, metadata: nil) { metadata, error in
            if let error = error {
                print("Error uploading video: \(error)")
                return
            }
            
            videoRef.downloadURL { url, error in
                if let mediaURL = url {
                    savePostToFirestore(mediaURL: mediaURL.absoluteString)
                }
            }
        }
    }
    
    func savePostToFirestore(mediaURL: String) {
        let db = Firestore.firestore()
        let post = [
            "latitude": location.latitude,
            "longitude": location.longitude,
            "mediaURL": mediaURL,
            "radius": 5000, // Initial 5km radius
            "viewCount": 0
        ] as [String: Any]
        
        db.collection("posts").addDocument(data: post) { error in
            if let error = error {
                print("Error saving post: \(error.localizedDescription)")
            } else {
                // Dismiss the MediaPickerView to go back to the MapView after post is added
                dismiss()
            }
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
