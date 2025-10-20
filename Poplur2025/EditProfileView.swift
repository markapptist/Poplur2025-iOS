//
//  EditProfileView.swift
//  Poplur2025
//
//  Created by Apptist Inc. on 2025-08-03.
//


import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var user: UserProfile?  // Binding to the user profile from the parent view
    @State private var newUsername: String
    @State private var newEmail: String
    @State private var selectedImage: UIImage?
    @State private var selectedVideoURL: URL?
    @State private var showImagePicker = false
    @State private var isImageChanged = false
    @State private var isSaving = false
    
    init(user: Binding<UserProfile?>) {
        _user = user
        _newUsername = State(initialValue: user.wrappedValue?.username ?? "")
        _newEmail = State(initialValue: user.wrappedValue?.email ?? "")
    }
    
    var body: some View {
        VStack {
            Text("Edit Profile")
                .font(.title)
                .padding()
            
            // Profile Picture
            if let selectedImage = selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 150)
                    .clipShape(Circle())
                    .padding()
            } else {
                if let imageUrl = user?.profilePictureURL {
                    AsyncImage(url: imageUrl) { image in
                        image.resizable()
                             .scaledToFill()
                             .frame(width: 150, height: 150)
                             .clipShape(Circle())
                    } placeholder: {
                        ProgressView()
                    }
                    .padding()
                } else {
                    Circle()
                        .frame(width: 150, height: 150)
                        .foregroundColor(.gray)
                        .padding()
                }
            }
            
            Button("Change Profile Picture") {
                showImagePicker.toggle()
            }
            .padding()
            
            // Username and Email Fields
            TextField("Username", text: $newUsername)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("Email", text: $newEmail)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.emailAddress)
            
            // Save Button
            Button(action: saveProfile) {
                if isSaving {
                    ProgressView()
                } else {
                    Text("Save Changes")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
            }
            .padding()
            .disabled(isSaving)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(selectedImage: $selectedImage, selectedVideoURL: $selectedVideoURL)
        }
        .padding()
    }
    
    // Save changes to Firestore and Firebase Storage
    func saveProfile() {
        isSaving = true
        
        // Get the current user
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Update username and email in Firestore
        let db = Firestore.firestore()
        var updates: [String: Any] = [
            "username": newUsername,
            "email": newEmail
        ]
        
        // If a new profile picture is selected, upload it
        if let selectedImage = selectedImage {
            uploadProfilePicture(image: selectedImage) { imageUrl in
                if let imageUrl = imageUrl {
                    updates["profilePictureURL"] = imageUrl
                    updateUserProfile(userId: userId, updates: updates)
                }
            }
        } else {
            updateUserProfile(userId: userId, updates: updates)
        }
    }
    
    // Upload profile picture to Firebase Storage
    func uploadProfilePicture(image: UIImage, completion: @escaping (URL?) -> Void) {
        let storageRef = Storage.storage().reference()
        let profilePicRef = storageRef.child("profile_pictures/\(UUID().uuidString).jpg")
        
        if let imageData = image.jpegData(compressionQuality: 0.75) {
            profilePicRef.putData(imageData, metadata: nil) { metadata, error in
                if let error = error {
                    print("Error uploading profile picture: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                
                profilePicRef.downloadURL { url, error in
                    if let url = url {
                        completion(url)
                    } else {
                        print("Error getting download URL: \(error?.localizedDescription ?? "Unknown error")")
                        completion(nil)
                    }
                }
            }
        }
    }
    
    // Update user profile in Firestore
    func updateUserProfile(userId: String, updates: [String: Any]) {
        let db = Firestore.firestore()
        
        db.collection("users").document(userId).updateData(updates) { error in
            if let error = error {
                print("Error updating profile: \(error.localizedDescription)")
            } else {
                // Successfully updated the profile, dismiss the edit view
                user?.username = newUsername
                user?.email = newEmail
                dismiss()
            }
            isSaving = false
        }
    }
}

struct EditProfileView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock user for preview purposes
        EditProfileView(user: .constant(UserProfile(username: "John Doe", email: "john.doe@example.com", profilePictureURL: nil)))
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
