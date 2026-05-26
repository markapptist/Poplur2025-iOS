//
//  UserRecognitionOverlay.swift
//  Real-time user recognition display for camera
//

import SwiftUI

/// Overlay that displays recognized user information in the camera view
struct UserRecognitionOverlay: View {
    @ObservedObject var recognitionManager: UserRecognitionManager
    
    var body: some View {
        VStack {
            if let user = recognitionManager.recognizedUser {
                recognizedUserView(user)
                    .transition(.opacity)
            } else {
                scanningView
                    .transition(.opacity)
            }
            Spacer()
        }
        .onReceive(recognitionManager.$recognizedUser) { newValue in
            if let u = newValue {
                print("👤 [UserRecognition] Recognized user (overlay): @\(u.profile.username) confidence: \(Int(u.confidence*100))%")
            }
        }
        .padding(.top, 48)
    }
    
    // MARK: - Recognized User View
    
    @ViewBuilder
    private func recognizedUserView(_ user: RecognizedUser) -> some View {
        HStack(spacing: 12) {
            // Profile picture or icon
            if let profileURL = user.profile.profilePictureURL {
                AsyncImage(url: profileURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    case .failure, .empty:
                        defaultProfileIcon
                    @unknown default:
                        defaultProfileIcon
                    }
                }
            } else {
                defaultProfileIcon
            }
            
            // User info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("@\(user.profile.username)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    // Verified checkmark
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
                
                // Confidence and radius
                HStack(spacing: 8) {
                    // Confidence indicator
                    HStack(spacing: 4) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 12))
                        Text("\(Int(user.confidence * 100))%")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.green)
                    
                    // Separator
                    Circle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 3, height: 3)
                    
                    // Radius
                    HStack(spacing: 4) {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 12))
                        Text(user.formattedRadius)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.orange)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green.opacity(0.6), lineWidth: 2)
                )
        )
        .padding(.horizontal, 16)
        .shadow(color: .green.opacity(0.3), radius: 10, x: 0, y: 4)
        .onAppear { print("👤 [UserRecognitionOverlay] Showing recognized user: @\(user.profile.username)") }
    }
    
    private var defaultProfileIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
            
            Image(systemName: "person.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Scanning View
    
    private var scanningView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)
            
            Text("Scanning...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Preview

#if DEBUG
struct UserRecognitionOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Sample recognized user
            UserRecognitionOverlay(
                recognitionManager: {
                    let manager = UserRecognitionManager()
                    manager.recognizedUser = RecognizedUser(
                        profile: UserProfile(
                            id: "123",
                            username: "john_doe",
                            email: "john@example.com",
                            profilePictureURL: nil
                        ),
                        detectedAt: Date(),
                        confidence: 0.95,
                        radiusMeters: 5000
                    )
                    return manager
                }()
            )
        }
        .previewDisplayName("Recognized User")
        
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Scanning state
            UserRecognitionOverlay(
                recognitionManager: {
                    let manager = UserRecognitionManager()
                    manager.isRecognizing = true
                    return manager
                }()
            )
        }
        .previewDisplayName("Scanning")
        
        ZStack {
            Color.black.ignoresSafeArea()
            
            // No detection
            UserRecognitionOverlay(
                recognitionManager: UserRecognitionManager()
            )
        }
        .previewDisplayName("No Detection")
    }
}
#endif

