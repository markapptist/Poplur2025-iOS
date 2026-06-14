//
//  ARFilterManager.swift
//  AR Face Filters and Effects
//

import Foundation
import ARKit
import SceneKit
import CoreImage
@preconcurrency import Vision
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

/// Manages AR face filters and effects
@MainActor
class ARFilterManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    /// Currently active filter
    @Published var activeFilter: ARFilter = .none
    
    /// Whether AR session is running
    @Published var isARActive: Bool = false
    
    /// Available filters
    @Published var availableFilters: [ARFilter] = ARFilter.allCases
    
    // MARK: - Private Properties
    
    private var arSession: ARSession?
    private var sceneView: ARSCNView?
    private var currentFaceNode: SCNNode?
    private let ciContext = CIContext()
    
    // Filter intensity (0.0 - 1.0)
    private var filterIntensity: Float = 0.7
    
    // MARK: - AR Filters
    
    enum ARFilter: String, CaseIterable, Identifiable {
        case none = "None"
        case faceSmoothing = "Smooth"
        case beautyFilter = "Beauty"
        case brightening = "Brighten"
        case glowingSkin = "Glow"
        case sharpen = "Sharpen"
        case warmth = "Warm"
        case cool = "Cool"
        case vintage = "Vintage"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .none: return "xmark.circle"
            case .faceSmoothing: return "sparkles"
            case .beautyFilter: return "face.smiling"
            case .brightening: return "sun.max"
            case .glowingSkin: return "glow"
            case .sharpen: return "square.grid.3x3"
            case .warmth: return "flame"
            case .cool: return "snowflake"
            case .vintage: return "camera.aperture"
            }
        }
        
        var description: String {
            switch self {
            case .none: return "No Filter"
            case .faceSmoothing: return "Smooth skin, reduce wrinkles"
            case .beautyFilter: return "All-in-one beauty enhancement"
            case .brightening: return "Brighten face"
            case .glowingSkin: return "Glowing, radiant skin"
            case .sharpen: return "Sharpen details"
            case .warmth: return "Warm tone"
            case .cool: return "Cool tone"
            case .vintage: return "Vintage look"
            }
        }
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        Task { @MainActor in
            self.activeFilter = .beautyFilter
        }
    }
    
    // MARK: - Public Methods
    
    /// Setup AR session with face tracking
    func setupARSession(in view: ARSCNView) {
        guard ARFaceTrackingConfiguration.isSupported else {
            print("❌ Face tracking not supported on this device")
            return
        }
        
        self.sceneView = view
        self.arSession = view.session
        
        // Configure AR session for face tracking
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        configuration.maximumNumberOfTrackedFaces = 1
        
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        view.delegate = self
        
        isARActive = true
        print("✅ AR Face Tracking session started")
    }
    
    /// Stop AR session
    func stopARSession() {
        arSession?.pause()
        sceneView?.session.pause()
        isARActive = false
        currentFaceNode?.removeFromParentNode()
        currentFaceNode = nil
    }
    
    /// Apply filter to image
    func applyFilter(to image: CIImage, faceObservation: VNFaceObservation?) -> CIImage? {
        guard activeFilter != .none else { return image }
        // Whole-view mode: if no faceObservation or mask, filters apply to entire frame.
        
        var outputImage = image
        
        switch activeFilter {
        case .none:
            return image
            
        case .faceSmoothing:
            outputImage = applySmoothingFilter(to: outputImage, faceObservation: faceObservation)
            
        case .beautyFilter:
            // Combine multiple filters for beauty effect
            outputImage = applySmoothingFilter(to: outputImage, faceObservation: faceObservation)
            outputImage = applyBrighteningFilter(to: outputImage, faceObservation: faceObservation)
            outputImage = applyGlowFilter(to: outputImage)
            
        case .brightening:
            outputImage = applyBrighteningFilter(to: outputImage, faceObservation: faceObservation)
            
        case .glowingSkin:
            outputImage = applyGlowFilter(to: outputImage)
            
        case .sharpen:
            outputImage = applySharpenFilter(to: outputImage)
            
        case .warmth:
            outputImage = applyWarmthFilter(to: outputImage)
            
        case .cool:
            outputImage = applyCoolFilter(to: outputImage)
            
        case .vintage:
            outputImage = applyVintageFilter(to: outputImage)
        }
        
        return outputImage
    }
    
    /// Set filter intensity
    func setIntensity(_ value: Float) {
        filterIntensity = max(0.0, min(1.0, value))
    }
    
    /// Apply filter to a captured video frame (called from camera delegate)
    /// This method is nonisolated to allow calling from background video processing queue
    nonisolated func applyFilterToVideoFrame(_ sampleBuffer: CMSampleBuffer, completion: @escaping (CMSampleBuffer?) -> Void) {
        // Capture weak reference and current filter to avoid blocking
        weak var weakSelf = self
        DispatchQueue.main.async {
            guard let self = weakSelf else {
                completion(sampleBuffer)
                return
            }
            let currentFilter = self.activeFilter
            
            guard currentFilter != .none else {
                completion(sampleBuffer)
                return
            }
            
            self.processFrameWithFilter(sampleBuffer, filter: currentFilter, completion: completion)
        }
    }
    
    /// Internal method to process frame with a specific filter
    private nonisolated func processFrameWithFilter(_ sampleBuffer: CMSampleBuffer, filter: ARFilter, completion: @escaping (CMSampleBuffer?) -> Void) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("❌ [ARFilter] Failed to get pixel buffer from sample buffer")
            completion(sampleBuffer)
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Detect face in frame for better filter application
        let request = VNDetectFaceRectanglesRequest { request, error in
            if let error = error {
                print("❌ [ARFilter] Face detection error: \(error.localizedDescription)")
            }
            
            let faceObservation = (request.results as? [VNFaceObservation])?.first
            
            // Log face detection status occasionally (every 60 frames ~2 seconds at 30fps)
            let shouldLog = Int.random(in: 0..<60) == 0
            if shouldLog {
                // Get current user info on main thread
                Task { @MainActor in
                    #if canImport(FirebaseAuth)
                    if let user = Auth.auth().currentUser {
                        let username = user.displayName ?? user.email ?? "Unknown"
                        let uid = user.uid
                        
                        if let face = faceObservation {
                            print("✅ [ARFilter] Face detected! User: \(username) (UID: \(uid))")
                            print("   Bounds: \(face.boundingBox), confidence: \(face.confidence)")
                        } else {
                            print("⚠️ [ARFilter] No face detected - User: \(username) (UID: \(uid))")
                            print("   Filter will apply to entire image")
                        }
                    } else {
                        if let face = faceObservation {
                            print("✅ [ARFilter] Face detected! User: Not authenticated")
                            print("   Bounds: \(face.boundingBox), confidence: \(face.confidence)")
                        } else {
                            print("⚠️ [ARFilter] No face detected - User: Not authenticated")
                        }
                    }
                    #else
                    if let face = faceObservation {
                        print("✅ [ARFilter] Face detected! Bounds: \(face.boundingBox), confidence: \(face.confidence)")
                    } else {
                        print("⚠️ [ARFilter] No face detected in frame - applying filter to entire image")
                    }
                    #endif
                }
            }
            
            // Access main actor isolated methods safely
            Task { @MainActor in
                // Apply filter with face observation
                guard let filteredImage = self.applyFilter(to: ciImage, faceObservation: faceObservation) else {
                    print("❌ [ARFilter] Failed to apply filter")
                    completion(sampleBuffer)
                    return
                }
                
                // Render filtered image back to pixel buffer
                if let outputPixelBuffer = self.createPixelBuffer(from: filteredImage) {
                    var timingInfo = CMSampleTimingInfo()
                    CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo)
                    
                    var formatDescription: CMFormatDescription?
                    CMVideoFormatDescriptionCreateForImageBuffer(
                        allocator: kCFAllocatorDefault,
                        imageBuffer: outputPixelBuffer,
                        formatDescriptionOut: &formatDescription
                    )
                    
                    guard let formatDesc = formatDescription else {
                        print("❌ [ARFilter] Failed to create format description")
                        completion(sampleBuffer)
                        return
                    }
                    
                    var newSampleBuffer: CMSampleBuffer?
                    CMSampleBufferCreateReadyWithImageBuffer(
                        allocator: kCFAllocatorDefault,
                        imageBuffer: outputPixelBuffer,
                        formatDescription: formatDesc,
                        sampleTiming: &timingInfo,
                        sampleBufferOut: &newSampleBuffer
                    )
                    
                    completion(newSampleBuffer)
                } else {
                    print("❌ [ARFilter] Failed to create output pixel buffer")
                    completion(sampleBuffer)
                }
            }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("❌ [ARFilter] Failed to perform face detection: \(error)")
                completion(sampleBuffer)
            }
        }
    }
    
    /// Create a pixel buffer from CIImage
    private func createPixelBuffer(from ciImage: CIImage) -> CVPixelBuffer? {
        let width = Int(ciImage.extent.width)
        let height = Int(ciImage.extent.height)
        
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ] as [CFString: Any]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        ciContext.render(ciImage, to: buffer)
        return buffer
    }
    
    // MARK: - Filter Implementations
    
    /// Smoothing filter to reduce wrinkles and imperfections
    private func applySmoothingFilter(to image: CIImage, faceObservation: VNFaceObservation?) -> CIImage {
        // Use bilateral filter for edge-preserving smoothing
        guard let smoothingFilter = CIFilter(name: "CIMedianFilter") else {
            return image
        }
        
        smoothingFilter.setValue(image, forKey: kCIInputImageKey)
        
        guard let smoothed = smoothingFilter.outputImage else {
            return image
        }
        
        // Blend original and smoothed based on intensity
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return smoothed
        }
        
        // Create a mask - if we have face observation, apply smoothing only to face area
        let mask: CIImage
        if let faceObservation = faceObservation {
            mask = createFaceMask(from: faceObservation, imageSize: image.extent.size)
        } else {
            // Apply to entire image with reduced intensity
            mask = CIImage(color: CIColor(red: CGFloat(filterIntensity * 0.5), green: 0, blue: 0, alpha: 1))
                .cropped(to: image.extent)
        }
        
        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(smoothed, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)
        
        return blendFilter.outputImage ?? image
    }
    
    /// Brightening filter for face
    private func applyBrighteningFilter(to image: CIImage, faceObservation: VNFaceObservation?) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else {
            return image
        }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(NSNumber(value: 1.0 + (0.2 * filterIntensity)), forKey: kCIInputBrightnessKey)
        filter.setValue(NSNumber(value: 1.0 + (0.1 * filterIntensity)), forKey: kCIInputContrastKey)
        
        return filter.outputImage ?? image
    }
    
    /// Glow filter for radiant skin
    private func applyGlowFilter(to image: CIImage) -> CIImage {
        guard let bloomFilter = CIFilter(name: "CIBloom") else {
            return image
        }
        
        bloomFilter.setValue(image, forKey: kCIInputImageKey)
        bloomFilter.setValue(NSNumber(value: 0.3 * filterIntensity), forKey: kCIInputIntensityKey)
        bloomFilter.setValue(NSNumber(value: 10.0), forKey: kCIInputRadiusKey)
        
        guard let bloom = bloomFilter.outputImage else {
            return image
        }
        
        // Blend with original
        guard let blendFilter = CIFilter(name: "CISourceOverCompositing") else {
            return bloom
        }
        
        blendFilter.setValue(bloom, forKey: kCIInputImageKey)
        blendFilter.setValue(image, forKey: kCIInputBackgroundImageKey)
        
        return blendFilter.outputImage ?? image
    }
    
    /// Sharpen filter
    private func applySharpenFilter(to image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CISharpenLuminance") else {
            return image
        }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(NSNumber(value: 0.8 * filterIntensity), forKey: kCIInputSharpnessKey)
        
        return filter.outputImage ?? image
    }
    
    /// Warmth filter (orange/golden tones)
    private func applyWarmthFilter(to image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CITemperatureAndTint") else {
            return image
        }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 6500 + (1000 * CGFloat(filterIntensity)), y: 0), forKey: "inputNeutral")
        filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
        
        return filter.outputImage ?? image
    }
    
    /// Cool filter (blue tones)
    private func applyCoolFilter(to image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CITemperatureAndTint") else {
            return image
        }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 6500 - (1000 * CGFloat(filterIntensity)), y: 0), forKey: "inputNeutral")
        filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
        
        return filter.outputImage ?? image
    }
    
    /// Vintage filter
    private func applyVintageFilter(to image: CIImage) -> CIImage {
        guard let sepiaFilter = CIFilter(name: "CISepiaTone") else {
            return image
        }
        
        sepiaFilter.setValue(image, forKey: kCIInputImageKey)
        sepiaFilter.setValue(NSNumber(value: 0.7 * filterIntensity), forKey: kCIInputIntensityKey)
        
        guard let sepia = sepiaFilter.outputImage else {
            return image
        }
        
        // Add vignette
        guard let vignetteFilter = CIFilter(name: "CIVignette") else {
            return sepia
        }
        
        vignetteFilter.setValue(sepia, forKey: kCIInputImageKey)
        vignetteFilter.setValue(NSNumber(value: 1.5 * filterIntensity), forKey: kCIInputIntensityKey)
        vignetteFilter.setValue(NSNumber(value: 2.0), forKey: kCIInputRadiusKey)
        
        return vignetteFilter.outputImage ?? sepia
    }
    
    // MARK: - Helper Methods
    
    /// Create a mask for the face region
    private func createFaceMask(from observation: VNFaceObservation, imageSize: CGSize) -> CIImage {
        let bounds = observation.boundingBox
        
        // Convert normalized coordinates to image coordinates
        let x = bounds.origin.x * imageSize.width
        let y = (1 - bounds.origin.y - bounds.height) * imageSize.height
        let width = bounds.width * imageSize.width
        let height = bounds.height * imageSize.height
        
        let faceRect = CGRect(x: x, y: y, width: width, height: height)
        
        // Create a radial gradient mask centered on face
        let centerX = faceRect.midX
        let centerY = faceRect.midY
        let radius = max(width, height) / 2
        
        guard let gradientFilter = CIFilter(name: "CIRadialGradient") else {
            return CIImage(color: CIColor.white).cropped(to: CGRect(origin: .zero, size: imageSize))
        }
        
        gradientFilter.setValue(CIVector(x: centerX, y: centerY), forKey: "inputCenter")
        gradientFilter.setValue(NSNumber(value: radius * 0.5), forKey: "inputRadius0")
        gradientFilter.setValue(NSNumber(value: radius * 1.2), forKey: "inputRadius1")
        gradientFilter.setValue(CIColor.white, forKey: "inputColor0")
        gradientFilter.setValue(CIColor.black, forKey: "inputColor1")
        
        let mask = gradientFilter.outputImage?.cropped(to: CGRect(origin: .zero, size: imageSize))
        return mask ?? CIImage(color: CIColor.white).cropped(to: CGRect(origin: .zero, size: imageSize))
    }
    
    // MARK: - Additional Public Methods
    
    /// Set a simple live tint filter color for demo
    public func setLiveTint(color: CIColor?) {
        // When a color is provided, switch to vintage as base and adjust warmth/cool accordingly
        if let color = color {
            // Simple mapping: warm if red > blue, cool otherwise
            if color.red > color.blue {
                self.activeFilter = .warmth
            } else {
                self.activeFilter = .cool
            }
        } else {
            self.activeFilter = .none
        }
    }
}

// MARK: - ARSCNViewDelegate

extension ARFilterManager: ARSCNViewDelegate {
    
    nonisolated func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        
        Task { @MainActor in
            updateFaceNode(node: node, faceAnchor: faceAnchor)
        }
    }
    
    nonisolated func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        
        Task { @MainActor in
            updateFaceNode(node: node, faceAnchor: faceAnchor)
        }
    }
    
    private func updateFaceNode(node: SCNNode, faceAnchor: ARFaceAnchor) {
        if currentFaceNode == nil {
            let faceGeometry = ARSCNFaceGeometry(device: MTLCreateSystemDefaultDevice()!)
            let faceNode = SCNNode(geometry: faceGeometry)
            node.addChildNode(faceNode)
            currentFaceNode = faceNode
        }
        
        if let faceGeometry = currentFaceNode?.geometry as? ARSCNFaceGeometry {
            faceGeometry.update(from: faceAnchor.geometry)
        }
    }
}
