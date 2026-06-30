//
//  CameraViewWithML.swift
//  SwiftUI wrapper for CameraKitController with ML detection
//

import SwiftUI
import AVFoundation
import UIKit

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
    /// Called when the primary detected object's name updates
    var onNameUpdate: ((String) -> Void)?
    
    // MARK: - State
    
    @State private var detectedObjects: [DetectedObject] = []
    @State private var lastDetectedName: String? = nil
    @State private var isCubeEnabled: Bool = true
    @State private var scannedUserName: String? = nil
    
    // MARK: - Initializer
    
    init(
        controller: CameraKitController,
        mlDetectionEnabled: Bool = true,
        confidenceThreshold: Float = 0.2,
        frameSkipInterval: Int = 5,
        maxResults: Int = 3,
        onDetection: (([DetectedObject]) -> Void)? = nil,
        onNameUpdate: ((String) -> Void)? = nil
    ) {
        self.controller = controller
        self.mlDetectionEnabled = mlDetectionEnabled
        self.confidenceThreshold = confidenceThreshold
        self.frameSkipInterval = frameSkipInterval
        self.maxResults = maxResults
        self.onDetection = onDetection
        self.onNameUpdate = onNameUpdate
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Use the existing CameraKitView
            CameraKitView(controller: controller, coordinate: nil)
            
            // Overlay ML detection badge if enabled
            if mlDetectionEnabled && !detectedObjects.isEmpty {
                VStack {
                    if let name = lastDetectedName {
                        Text(name.capitalized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .poplurTextShader(intensity: 0.85)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Capsule())
                            .padding(.bottom, 6)
                    }
                    MLDetectionBadgeViewWrapper(objects: detectedObjects)
                        .frame(maxWidth: 280)
                    Spacer()
                }
                .padding(.top, 16)
            }
            
            // Instructions / Scanned user name overlay (replaces scanning label)
            VStack {
                if let name = scannedUserName, !name.isEmpty {
                    Text(name)
                        .font(.headline)
                        .foregroundColor(.white)
                        .poplurTextShader(intensity: 0.9)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                        .padding(.top, 12)
                }
                Spacer()
            }
        }
        .onAppear {
            if mlDetectionEnabled {
                setupMLDetection()
            }
            NotificationCenter.default.addObserver(forName: Notification.Name("CubeInteractionDisabled"), object: nil, queue: .main) { _ in
                isCubeEnabled = false
            }
            NotificationCenter.default.addObserver(forName: Notification.Name("CubeInteractionEnabled"), object: nil, queue: .main) { _ in
                isCubeEnabled = true
            }
            NotificationCenter.default.addObserver(forName: Notification.Name("RegisteredUserNameUpdated"), object: nil, queue: .main) { note in
                if let name = note.userInfo?["name"] as? String {
                    scannedUserName = name
                }
            }
        }
        .onDisappear {
            controller.disableMLDetection()
            detectedObjects = []
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MLObjectsDetected"))) { notification in
            guard let objects = notification.userInfo?["objects"] as? [DetectedObject] else { return }
            detectedObjects = objects
            onDetection?(objects)
            if let primary = objects.first?.identifier {
                lastDetectedName = primary
                onNameUpdate?(primary)
            } else {
                lastDetectedName = nil
            }
        }
        // Note: Bind any cube button in this view hierarchy to .disabled(!isCubeEnabled) to prevent taps during recording.
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
            if let primary = objects.first?.identifier {
                lastDetectedName = primary
                onNameUpdate?(primary)
            } else {
                lastDetectedName = nil
            }
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
            } onNameUpdate: { name in
                // Example: print or log the primary detected name
                print("Primary detected: \(name)")
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
                            .poplurTextShader(intensity: 0.9)
                        
                        ForEach(detectedObjects.indices, id: \.self) { index in
                            HStack {
                                Text(detectedObjects[index].identifier.capitalized)
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .poplurTextShader(intensity: 0.85)
                                Spacer()
                                Text("\(detectedObjects[index].confidencePercentage)%")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                    .poplurTextShader(intensity: 0.7)
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
                            .poplurIconShader()
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
                            .poplurIconShader()
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, 30)
            }
                if showSettings {
                    Color.black.opacity(0.58)
                        .ignoresSafeArea()
                        .overlay(alignment: .bottom) {
                            MLSettingsView(isEnabled: $isMLEnabled)
                                .frame(maxHeight: 520)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .padding(.horizontal, 16)
                                .padding(.bottom, 18)
                        }
                        .transition(.opacity)
                        .zIndex(30)
                }
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
                Section(header: Text("Detection Settings").poplurTextShader(intensity: 0.75)) {
                    Toggle(isOn: $isEnabled) {
                        Text("Enable ML Detection")
                            .poplurTextShader(intensity: 0.75)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Confidence Threshold: \(Int(confidenceThreshold * 100))%")
                            .poplurTextShader(intensity: 0.75)
                        Slider(value: $confidenceThreshold, in: 0.1...0.9, step: 0.05)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Frame Skip: Every \(Int(frameSkip)) frames")
                            .poplurTextShader(intensity: 0.75)
                        Slider(value: $frameSkip, in: 1...15, step: 1)
                    }
                }
                
                Section(header: Text("Performance").poplurTextShader(intensity: 0.75)) {
                    HStack {
                        Text("Battery Impact")
                            .poplurTextShader(intensity: 0.7)
                        Spacer()
                        Text(batteryImpact)
                            .foregroundColor(batteryImpactColor)
                            .poplurTextShader(intensity: 0.75)
                    }
                    
                    HStack {
                        Text("Responsiveness")
                            .poplurTextShader(intensity: 0.7)
                        Spacer()
                        Text(responsiveness)
                            .foregroundColor(responsivenessColor)
                            .poplurTextShader(intensity: 0.75)
                    }
                }
                
                Section(header: Text("Info").poplurTextShader(intensity: 0.75)) {
                    Text("ML detection uses Apple's Vision framework to identify objects in real-time from the camera feed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .poplurTextShader(intensity: 0.55)
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
