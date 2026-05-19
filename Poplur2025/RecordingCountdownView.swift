//
//  RecordingCountdownView.swift
//  Poplur2025
//
//  Multi-purpose counter view for recording countdown and post count display
//

import SwiftUI
import Photos

/// Multi-purpose counter shown in bottom-left corner (level with radius bar)
/// - On Record tab: Shows camera roll button with preview thumbnail (when not recording)
/// - On Record tab (recording): Shows recording countdown timer (10s → 0s)
/// - On other tabs: Shows user's current post count with radius trend indicator
/// This view is visible across ALL tabs
struct RecordingCountdownView: View {
    @Binding var isRecording: Bool
    @Binding var secondsRemaining: Int
    @Binding var postCount: Int
    @Binding var selectedTab: AppTab
    @Binding var radiusTrend: HomeView.RadiusTrend
    
    @State private var pulseAnimation: Bool = false
    @State private var latestPhoto: UIImage? = nil
    @State private var showPhotoPicker: Bool = false
    @State private var arrowAnimation: Bool = false
    
    // Animation state for toggling between TRENDING/arrow and LIKES/number
    @State private var showLikesMode: Bool = false
    @State private var likesCount: Int = 0
    
    private var shouldShowRecording: Bool {
        isRecording && selectedTab == .record
    }
    
    private var shouldShowCameraRoll: Bool {
        !isRecording && selectedTab == .record
    }
    
    private var shouldShowPostCount: Bool {
        !isRecording && [AppTab.map, .feed, .profile].contains(selectedTab)
    }
    
    var body: some View {
        Group {
            if shouldShowRecording {
                // Recording countdown mode
                recordingCountdownBadge
                    .allowsHitTesting(false)
            } else if shouldShowCameraRoll {
                // Camera roll button mode
                cameraRollButton
                    .allowsHitTesting(true)
            } else if shouldShowPostCount {
                // Post count mode - align baseline with radius display
                postCountBadge
                    .allowsHitTesting(false)
            }
        }
        .opacity((shouldShowRecording || shouldShowPostCount || shouldShowCameraRoll) ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: shouldShowRecording)
        .animation(.easeInOut(duration: 0.3), value: shouldShowPostCount)
        .animation(.easeInOut(duration: 0.3), value: shouldShowCameraRoll)
        .onAppear {
            pulseAnimation = true
            arrowAnimation = true
            if shouldShowCameraRoll {
                fetchLatestPhoto()
            }
            // Start animation timer for likes/trending toggle
            startLikesAnimation()
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == .record && !isRecording {
                fetchLatestPhoto()
            }
        }
        .onChange(of: radiusTrend) { newTrend in
            // Restart animation when trend changes
            print("🎯 [RecordingCountdownView] Radius trend changed to: \(newTrend)")
            arrowAnimation = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                arrowAnimation = true
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(
                onImageSelected: { image in
                    handleSelectedImage(image)
                },
                onVideoSelected: { url in
                    handleSelectedVideo(url)
                }
            )
        }
    }
    
    // MARK: - Recording Countdown Badge
    
    @ViewBuilder
    private var recordingCountdownBadge: some View {
        HStack(spacing: 8) {
            // Recording indicator (pulsing red dot)
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                .opacity(pulseAnimation ? 0.6 : 1.0)
                .animation(
                    .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true),
                    value: pulseAnimation
                )
            
            if secondsRemaining > 0 {
                // Countdown timer
                Text("\(secondsRemaining)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                
                Text("s")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                // Recording complete indicator
                Text("RECORDING")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
            }
        }
    }
    
    // MARK: - Post Count Badge
    
    @ViewBuilder
    private var postCountBadge: some View {
        VStack(alignment: .leading, spacing: 4) {
            // "TRENDING" or "LIKES" label at the top
            Text(showLikesMode ? "LIKES" : "TRENDING")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                .kerning(1.2)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            
            // Arrow or likes number (directly below label)
            Group {
                if showLikesMode {
                    Text("\(likesCount)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.red)
                        .monospacedDigit()
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else if radiusTrend != .neutral {
                    Image(systemName: radiusTrend == .up ? "arrow.up" : "arrow.down")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(radiusTrend == .up ? Color.green : Color.red)
                        .scaleEffect(arrowAnimation ? 1.0 : 0.85)
                        .opacity(arrowAnimation ? 1.0 : 0.7)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true),
                            value: arrowAnimation
                        )
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else {
                    Text("")
                        .font(.system(size: 40, weight: .bold))
                }
            }
            
            // White line separator
            Rectangle()
                .fill(.white)
                .frame(width: 100, height: 2)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            
            // Post count number
            Text("\(postCount)")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
            
            // "posts" label
            Text(postCount == 1 ? "post" : "posts")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Camera Roll Button
    
    @ViewBuilder
    private var cameraRollButton: some View {
        Button(action: {
            showPhotoPicker = true
        }) {
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
        print("[RecordingCountdownView] Image selected from camera roll")
        NotificationCenter.default.post(
            name: Notification.Name("CameraRollImageSelected"),
            object: image
        )
    }
    
    private func handleSelectedVideo(_ url: URL) {
        print("[RecordingCountdownView] Video selected from camera roll: \(url)")
        NotificationCenter.default.post(
            name: Notification.Name("CameraRollVideoSelected"),
            object: url
        )
    }
    
    // MARK: - Likes Animation
    
    private func startLikesAnimation() {
        // Generate random likes count
        likesCount = Int.random(in: 50...500)
        
        // Animate between TRENDING/arrow and LIKES/number every 3 seconds
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showLikesMode.toggle()
            }
            
            // Generate new likes count when switching to likes mode
            if showLikesMode {
                likesCount = Int.random(in: 50...500)
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

// MARK: - Photo Picker View

struct PhotoPickerView: UIViewControllerRepresentable {
    let onImageSelected: (UIImage) -> Void
    let onVideoSelected: (URL) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
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
            dismiss: { dismiss() }
        )
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageSelected: (UIImage) -> Void
        let onVideoSelected: (URL) -> Void
        let dismiss: () -> Void
        
        init(onImageSelected: @escaping (UIImage) -> Void, onVideoSelected: @escaping (URL) -> Void, dismiss: @escaping () -> Void) {
            self.onImageSelected = onImageSelected
            self.onVideoSelected = onVideoSelected
            self.dismiss = dismiss
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImageSelected(image)
            } else if let videoURL = info[.mediaURL] as? URL {
                onVideoSelected(videoURL)
            }
            dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

// MARK: - Preview
#if DEBUG
struct RecordingCountdownView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Camera roll button preview (Record tab, not recording)
            ZStack {
                Color.black.ignoresSafeArea()
                RecordingCountdownView(
                    isRecording: .constant(false),
                    secondsRemaining: .constant(10),
                    postCount: .constant(42),
                    selectedTab: .constant(.record),
                    radiusTrend: .constant(.neutral)
                )
            }
            .previewDisplayName("Camera Roll Button")
            
            // Recording countdown preview
            ZStack {
                Color.black.ignoresSafeArea()
                RecordingCountdownView(
                    isRecording: .constant(true),
                    secondsRemaining: .constant(7),
                    postCount: .constant(42),
                    selectedTab: .constant(.record),
                    radiusTrend: .constant(.neutral)
                )
            }
            .previewDisplayName("Recording Countdown")
            
            // Recording complete preview
            ZStack {
                Color.black.ignoresSafeArea()
                RecordingCountdownView(
                    isRecording: .constant(true),
                    secondsRemaining: .constant(0),
                    postCount: .constant(42),
                    selectedTab: .constant(.record),
                    radiusTrend: .constant(.neutral)
                )
            }
            .previewDisplayName("Recording Complete")
            
            // Post count preview with upward trend (Map tab)
            ZStack {
                Color.black.ignoresSafeArea()
                RecordingCountdownView(
                    isRecording: .constant(false),
                    secondsRemaining: .constant(10),
                    postCount: .constant(42),
                    selectedTab: .constant(.map),
                    radiusTrend: .constant(.up)
                )
            }
            .previewDisplayName("Post Count - Radius Up ⬆️")
            
            // Post count preview with downward trend (Feed tab)
            ZStack {
                Color.black.ignoresSafeArea()
                RecordingCountdownView(
                    isRecording: .constant(false),
                    secondsRemaining: .constant(10),
                    postCount: .constant(128),
                    selectedTab: .constant(.feed),
                    radiusTrend: .constant(.down)
                )
            }
            .previewDisplayName("Post Count - Radius Down ⬇️")
            
            // Single post preview (neutral)
            ZStack {
                Color.black.ignoresSafeArea()
                RecordingCountdownView(
                    isRecording: .constant(false),
                    secondsRemaining: .constant(10),
                    postCount: .constant(1),
                    selectedTab: .constant(.profile),
                    radiusTrend: .constant(.neutral)
                )
            }
            .previewDisplayName("Post Count - Neutral")
        }
    }
}
#endif
