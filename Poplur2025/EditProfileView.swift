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

protocol EditableUserProfile {
    var username: String { get set }
    var email: String { get set }
    var profilePictureURL: URL? { get }
    var accountType: PoplurAccountType { get }
    var businessProfile: BusinessProfile? { get set }
}

// Use a type-erased box to allow binding without referring to the ambiguous concrete type
struct AnyEditableUserProfile: EditableUserProfile {
    var getUsername: () -> String
    var setUsername: (String) -> Void
    var getEmail: () -> String
    var setEmail: (String) -> Void
    var getProfilePictureURL: () -> URL?
    var getAccountType: () -> PoplurAccountType
    var getBusinessProfile: () -> BusinessProfile?
    var setBusinessProfile: (BusinessProfile?) -> Void

    var username: String {
        get { getUsername() }
        set { setUsername(newValue) }
    }
    var email: String {
        get { getEmail() }
        set { setEmail(newValue) }
    }
    var profilePictureURL: URL? { get { getProfilePictureURL() } }
    var accountType: PoplurAccountType { getAccountType() }
    var businessProfile: BusinessProfile? {
        get { getBusinessProfile() }
        set { setBusinessProfile(newValue) }
    }
}

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var user: AnyEditableUserProfile?  // Binding to the user profile from the parent view
    var onDone: (() -> Void)?
    @State private var newUsername: String
    @State private var newEmail: String
    @State private var selectedImage: UIImage?
    @State private var selectedVideoURL: URL?
    @State private var showImagePicker = false
    @State private var isImageChanged = false
    @State private var isSaving = false
    @State private var businessName: String
    @State private var businessCategory: String
    @State private var businessDescription: String
    @State private var businessAddress: String
    @State private var businessLatitude: String
    @State private var businessLongitude: String
    @State private var businessContactEmail: String
    @State private var businessContactPhone: String
    @State private var businessWebsite: String
    @State private var businessLogoPhotoNotes: String

    init(user: Binding<AnyEditableUserProfile?>, onDone: (() -> Void)? = nil) {
        _user = user
        self.onDone = onDone
        _newUsername = State(initialValue: user.wrappedValue?.username ?? "")
        _newEmail = State(initialValue: user.wrappedValue?.email ?? "")
        let business = user.wrappedValue?.businessProfile
        _businessName = State(initialValue: business?.businessName ?? "")
        _businessCategory = State(initialValue: business?.category ?? "")
        _businessDescription = State(initialValue: business?.description ?? "")
        _businessAddress = State(initialValue: business?.address ?? "")
        _businessLatitude = State(initialValue: String(business?.latitude ?? BusinessProfile.empty.latitude))
        _businessLongitude = State(initialValue: String(business?.longitude ?? BusinessProfile.empty.longitude))
        _businessContactEmail = State(initialValue: business?.contactEmail ?? "")
        _businessContactPhone = State(initialValue: business?.contactPhone ?? "")
        _businessWebsite = State(initialValue: business?.website ?? "")
        _businessLogoPhotoNotes = State(initialValue: business?.logoPhotoNotes ?? "")
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

            if user?.accountType == .business {
                businessEditor
            }

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

    private var businessEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Business Profile")
                .font(.headline)
                .padding(.top, 8)
            Text("Changing business name or address sends the profile back to verification review.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("Business name", text: $businessName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            TextField("Business category", text: $businessCategory)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            TextField("Business description", text: $businessDescription, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            TextField("Business address", text: $businessAddress)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            HStack {
                TextField("Latitude", text: $businessLatitude)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Longitude", text: $businessLongitude)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            TextField("Contact email", text: $businessContactEmail)
                .keyboardType(.emailAddress)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            TextField("Contact phone", text: $businessContactPhone)
                .keyboardType(.phonePad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            TextField("Website", text: $businessWebsite)
                .keyboardType(.URL)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            TextField("Logo/photo notes", text: $businessLogoPhotoNotes, axis: .vertical)
                .lineLimit(2, reservesSpace: true)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .padding(.vertical, 8)
    }

    // MARK: - Save changes to Firestore and Firebase Storage

    func saveProfile() {
        isSaving = true

        // Get the current user
        guard let userId = Auth.auth().currentUser?.uid else { return }

        // Update username and email in Firestore
        var updates: [String: Any] = [
            "username": newUsername,
            "email": newEmail
        ]
        let updatedBusinessProfile = buildUpdatedBusinessProfile()
        if let updatedBusinessProfile {
            updates["accountType"] = PoplurAccountType.business.rawValue
            updates["displayName"] = updatedBusinessProfile.businessName
            updates["businessProfile"] = updatedBusinessProfile.toDictionary()
            updates["businessName"] = updatedBusinessProfile.businessName
            updates["businessCategory"] = updatedBusinessProfile.category
            updates["businessAddress"] = updatedBusinessProfile.address
            updates["businessLocation"] = updatedBusinessProfile.mapLocation
            updates["isBusinessAccount"] = true
            updates["isVerifiedBusiness"] = updatedBusinessProfile.verificationStatus == .verified
            updates["requiresReverification"] = updatedBusinessProfile.requiresReverification
        }

        // If a new profile picture is selected, upload it
        if let selectedImage = selectedImage {
            uploadProfilePicture(image: selectedImage) { imageUrl in
                if let imageUrl = imageUrl {
                    updates["profilePictureURL"] = imageUrl
                    updateUserProfile(userId: userId, updates: updates, businessProfile: updatedBusinessProfile)
                } else {
                    updateUserProfile(userId: userId, updates: updates, businessProfile: updatedBusinessProfile)
                }
            }
        } else {
            updateUserProfile(userId: userId, updates: updates, businessProfile: updatedBusinessProfile)
        }
    }

    private func buildUpdatedBusinessProfile() -> BusinessProfile? {
        guard user?.accountType == .business else { return nil }
        let existing = user?.businessProfile ?? .empty
        let majorChange = businessName.trimmedForEdit != existing.businessName.trimmedForEdit ||
            businessAddress.trimmedForEdit != existing.address.trimmedForEdit
        let status: BusinessVerificationStatus = majorChange ? .pendingReview : existing.verificationStatus
        return BusinessProfile(
            businessName: businessName.trimmedForEdit,
            category: businessCategory.trimmedForEdit,
            description: businessDescription.trimmedForEdit,
            address: businessAddress.trimmedForEdit,
            latitude: Double(businessLatitude.trimmedForEdit) ?? existing.latitude,
            longitude: Double(businessLongitude.trimmedForEdit) ?? existing.longitude,
            contactEmail: businessContactEmail.trimmedForEdit,
            contactPhone: businessContactPhone.trimmedForEdit,
            website: businessWebsite.trimmedForEdit,
            logoPhotoNotes: businessLogoPhotoNotes.trimmedForEdit,
            verificationStatus: status,
            verificationMethods: existing.verificationMethods,
            proofSummary: existing.proofSummary,
            rejectionReason: existing.rejectionReason,
            requiresReverification: majorChange || existing.requiresReverification
        )
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
        } else {
            completion(nil)
        }
    }

    // Update user profile in Firestore
    func updateUserProfile(userId: String, updates: [String: Any], businessProfile: BusinessProfile?) {
        let db = Firestore.firestore()

        db.collection("users").document(userId).updateData(updates) { error in
            if let error = error {
                print("Error updating profile: \(error.localizedDescription)")
                isSaving = false
            } else {
                if let businessProfile {
                    Task {
                        do {
                            try await BusinessAccountService.updateBusinessProfile(uid: userId, businessProfile: businessProfile)
                            await finishProfileUpdate(businessProfile: businessProfile)
                        } catch {
                            print("Error updating business profile: \(error.localizedDescription)")
                            await MainActor.run {
                                isSaving = false
                            }
                        }
                    }
                } else {
                    Task { await finishProfileUpdate(businessProfile: nil) }
                }
            }
        }
    }

    @MainActor
    private func finishProfileUpdate(businessProfile: BusinessProfile?) {
        user?.username = newUsername
        user?.email = newEmail
        if let businessProfile {
            user?.businessProfile = businessProfile
        }
        isSaving = false
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }
}

private extension String {
    var trimmedForEdit: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct EditProfileView_Previews: PreviewProvider {
    static var previews: some View {
        EditProfileView(user: .constant(nil))
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
