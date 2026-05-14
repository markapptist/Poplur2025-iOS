//
//  CapturePreviewOverlay.swift
//  Poplur2025
//
//  Created for camera capture preview with posting flows
//

import SwiftUI
import AVKit
import CoreLocation

/// Preview overlay shown after capturing photo or video
/// Handles both posting flows:
/// - Flow 1 (Map → Camera): User selected location first, preview auto-uploads
/// - Flow 2 (Camera → Map): User captures first, preview opens map for location selection
struct CapturePreviewOverlay: View {
    let image: UIImage?
    let videoURL: URL?
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flowManager = CaptureFlowManager.shared
    
    @State private var isProcessing = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Media Preview
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else if let videoURL = videoURL {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .ignoresSafeArea()
            }
            
            // Buttons Overlay
            VStack {
                Spacer()
                
                HStack(spacing: 24) {
                    // Retake button
                    Button {
                        dismiss()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 44, weight: .regular))
                                .foregroundColor(.white)
                            Text("Retake")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(isProcessing)
                    .opacity(isProcessing ? 0.5 : 1.0)
                    
                    Spacer()
                    
                    // Use button
                    Button {
                        handleUseButton()
                    } label: {
                        VStack(spacing: 8) {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                    .frame(width: 44, height: 44)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 44, weight: .regular))
                                    .foregroundColor(.green)
                            }
                            Text(isProcessing ? "Posting..." : "Use")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(isProcessing)
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            print("📸 [CapturePreview] Appeared - Flow: \(flowManager.currentFlow.map { flow -> String in flow.isMapFirst ? "Map→Camera" : flow.isCameraFirst ? "Camera→Map" : "None" } ?? "None")")
        }
    }
    
    private func handleUseButton() {
        guard !isProcessing else { return }
        isProcessing = true
        
        // Check current flow
        if let flow = flowManager.currentFlow, flow.isMapFirst {
            // Flow 1: Map → Camera - Auto-upload to preselected coordinate
            handleMapToCameraFlow()
        } else {
            // Flow 2: Camera → Map - Open map to select location
            handleCameraToMapFlow()
        }
    }
    
    /// Flow 1: Map first - user already selected coordinate, auto-upload
    private func handleMapToCameraFlow() {
        guard let coordinate = flowManager.currentFlow?.preselectedCoordinate else {
            print("❌ [CapturePreview] No preselected coordinate for map-first flow")
            isProcessing = false
            return
        }
        
        print("📍 [CapturePreview] Map→Camera flow: Auto-uploading to \(coordinate.latitude), \(coordinate.longitude)")
        
        // Set the coordinate for upload
        NotificationCenter.default.post(
            name: Notification.Name("SetCameraCoordinate"),
            object: nil,
            userInfo: [
                "latitude": coordinate.latitude,
                "longitude": coordinate.longitude
            ]
        )
        
        // Upload the media
        if let image = image {
            NotificationCenter.default.post(
                name: Notification.Name("UploadImageToCurrentCoordinate"),
                object: image
            )
        } else if let videoURL = videoURL {
            NotificationCenter.default.post(
                name: Notification.Name("UploadVideoToCurrentCoordinate"),
                object: videoURL
            )
        }
        
        // Complete the flow
        flowManager.completeFlow(finalCoordinate: coordinate)
        
        // Dismiss preview after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
            
            // Navigate to profile to see the new post
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(
                    name: Notification.Name("SwitchToProfileTab"),
                    object: nil
                )
            }
        }
    }
    
    /// Flow 2: Camera first - open map to select location
    private func handleCameraToMapFlow() {
        print("📸 [CapturePreview] Camera→Map flow: Opening map for location selection")
        
        // Start camera-to-map flow with captured media
        flowManager.startCameraToMapFlow(image: image, videoURL: videoURL)
        
        // Dismiss preview
        dismiss()
        
        // Open map tab for location selection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: Notification.Name("OpenMapToSelectPostLocation"),
                object: nil,
                userInfo: [
                    "image": image as Any,
                    "videoURL": videoURL as Any
                ]
            )
        }
    }
}

// MARK: - Preview
#if DEBUG
struct CapturePreviewOverlay_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Preview with image
            CapturePreviewOverlay(
                image: UIImage(systemName: "photo")!,
                videoURL: nil
            )
            .previewDisplayName("Photo Preview")
            
            // Preview with video
            CapturePreviewOverlay(
                image: nil,
                videoURL: Bundle.main.url(forResource: "sample", withExtension: "mp4")
            )
            .previewDisplayName("Video Preview")
        }
    }
}
#endif
