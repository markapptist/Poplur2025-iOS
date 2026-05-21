//
//  CameraViewWithML.swift
//  SwiftUI wrapper for CameraKitController with ML detection
//

import SwiftUI
import AVFoundation
import UIKit
import SCSDKCameraKit

/// SwiftUI view that displays the camera with ML detection enabled
struct CameraViewWithML: View {
    
    // MARK: - Configuration
    
    /// Reference to the camera controller
    @ObservedObject var controller: CameraKitController
    
    /// Whether ML detection should be enabled
    var mlDetectionEnabled: Bool = true
    
    /// Confidence threshold for detections (0.0 - 1.0)
    var confidenceThreshold: Float = 0.2
    
    /// Frame skip interval (higher = better performance)
    var frameSkipInterval: Int = 5
    
    /// Maximum number of results to show
    var maxResults: Int = 3
    
    // MARK: - Callbacks
    
    /// Called when objects are detected
    var onDetection: (([DetectedObject]) -> Void)?
    
    // MARK: - State
    
    @State private var detectedObjects: [DetectedObject] = []
    
    // MARK: - Initializer
    
    init(
        controller: CameraKitController,
        mlDetectionEnabled: Bool = true,
        confidenceThreshold: Float = 0.2,
        frameSkipInterval: Int = 5,
        maxResults: Int = 3,
        onDetection: (([DetectedObject]) -> Void)? = nil
    ) {
        self.controller = controller
        self.mlDetectionEnabled = mlDetectionEnabled
        self.confidenceThreshold = confidenceThreshold
        self.frameSkipInterval = frameSkipInterval
        self.maxResults = maxResults
        self.onDetection = onDetection
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Use the existing CameraKitView
            CameraKitView(controller: controller, coordinate: nil)
            
            // Overlay ML detection badge if enabled
            if mlDetectionEnabled && !detectedObjects.isEmpty {
                VStack {
                    MLDetectionBadgeViewWrapper(objects: detectedObjects)
                        .frame(maxWidth: 280)
                    Spacer()
                }
                .padding(.top, 16)
            }
        }
        .onAppear {
            if mlDetectionEnabled {
                setupMLDetection()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MLObjectsDetected"))) { notification in
            if let objects = notification.userInfo?["objects"] as? [DetectedObject] {
                detectedObjects = objects
                onDetection?(objects)
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func setupMLDetection() {
        // Enable ML detection on the controller
        controller.enableMLDetection()
        
        // Configure detection settings
        controller.mlDetectionManager?.confidenceThreshold = confidenceThreshold
        controller.mlDetectionManager?.frameSkipInterval = frameSkipInterval
        controller.mlDetectionManager?.maxResults = maxResults
        
        // Setup callback
        controller.mlDetectionManager?.onDetection = { objects in
            detectedObjects = objects
            onDetection?(objects)
        }
    }
}

// MARK: - SwiftUI Wrapper for MLDetectionBadgeView

/// SwiftUI wrapper for the UIKit MLDetectionBadgeView
struct MLDetectionBadgeViewWrapper: UIViewRepresentable {
    let objects: [DetectedObject]
    
    func makeUIView(context: Context) -> MLDetectionBadgeView {
        let view = MLDetectionBadgeView()
        return view
    }
    
    func updateUIView(_ uiView: MLDetectionBadgeView, context: Context) {
        uiView.updateDetections(objects)
    }
}

// MARK: - SwiftUI Preview

#if DEBUG
struct CameraViewWithML_Previews: PreviewProvider {
    static var previews: some View {
        CameraViewWithMLExample()
    }
}

/// Example SwiftUI view showing how to use CameraViewWithML
struct CameraViewWithMLExample: View {
    @StateObject private var cameraController = CameraKitController()
    @State private var detectedObjects: [DetectedObject] = []
    @State private var isMLEnabled: Bool = true
    @State private var showSettings: Bool = false
    
    var body: some View {
        ZStack {
            // Camera with ML detection
            CameraViewWithML(
                controller: cameraController,
                mlDetectionEnabled: isMLEnabled,
                confidenceThreshold: 0.2,
                frameSkipInterval: 5,
                maxResults: 3
            ) { objects in
                // Handle detected objects
                detectedObjects = objects
                print("🔍 Detected: \(objects.map { $0.identifier }.joined(separator: ", "))")
            }
            .ignoresSafeArea()
            
            // Controls overlay
            VStack {
                Spacer()
                
                // Detection status card
                if !detectedObjects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🔍 Currently Detecting")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        ForEach(detectedObjects.indices, id: \.self) { index in
                            HStack {
                                Text(detectedObjects[index].identifier.capitalized)
                                    .font(.body)
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(detectedObjects[index].confidencePercentage)%")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
                
                // Toggle ML button
                HStack(spacing: 20) {
                    Button(action: {
                        isMLEnabled.toggle()
                    }) {
                        Image(systemName: isMLEnabled ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        showSettings.toggle()
                    }) {
                        Image(systemName: "gear")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showSettings) {
            MLSettingsView(isEnabled: $isMLEnabled)
        }
    }
}

/// Settings view for ML detection
struct MLSettingsView: View {
    @Binding var isEnabled: Bool
    @State private var confidenceThreshold: Double = 0.2
    @State private var frameSkip: Double = 5
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Detection Settings")) {
                    Toggle("Enable ML Detection", isOn: $isEnabled)
                    
                    VStack(alignment: .leading) {
                        Text("Confidence Threshold: \(Int(confidenceThreshold * 100))%")
                        Slider(value: $confidenceThreshold, in: 0.1...0.9, step: 0.05)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Frame Skip: Every \(Int(frameSkip)) frames")
                        Slider(value: $frameSkip, in: 1...15, step: 1)
                    }
                }
                
                Section(header: Text("Performance")) {
                    HStack {
                        Text("Battery Impact")
                        Spacer()
                        Text(batteryImpact)
                            .foregroundColor(batteryImpactColor)
                    }
                    
                    HStack {
                        Text("Responsiveness")
                        Spacer()
                        Text(responsiveness)
                            .foregroundColor(responsivenessColor)
                    }
                }
                
                Section(header: Text("Info")) {
                    Text("ML detection uses Apple's Vision framework to identify objects in real-time from the camera feed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("ML Detection")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var batteryImpact: String {
        switch frameSkip {
        case 1...3: return "High"
        case 4...7: return "Medium"
        default: return "Low"
        }
    }
    
    private var batteryImpactColor: Color {
        switch frameSkip {
        case 1...3: return .red
        case 4...7: return .orange
        default: return .green
        }
    }
    
    private var responsiveness: String {
        switch frameSkip {
        case 1...3: return "High"
        case 4...7: return "Medium"
        default: return "Low"
        }
    }
    
    private var responsivenessColor: Color {
        switch frameSkip {
        case 1...3: return .green
        case 4...7: return .orange
        default: return .red
        }
    }
}
#endif
