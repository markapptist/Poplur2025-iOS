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
    /// Reuses the Vision pass already required by the native filter pipeline to
    /// anchor the transparent WebGL accessory layer. No second face detector.
    var onFaceTrack: ((CGRect?, Float, CGFloat, CGFloat) -> Void)?
    private var lastFaceTrackPublishTime: TimeInterval = 0
    
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

        /// What the rail calls it.
        ///
        /// SEPARATE FROM `rawValue` on purpose. Every one of these draws a
        /// costume on the face further down this file — `.sharpen` is the cyan
        /// visor at `case .sharpen` in the effect pass — so naming them after
        /// the colour grade told you nothing about what you were picking. But
        /// `rawValue` is also the wire value: it goes out in the
        /// `["filter": ...]` notification payload, so renaming the cases would
        /// change a contract to fix a caption. The label moves; the id does not.
        var displayName: String {
            switch self {
            case .none: return "None"
            case .faceSmoothing: return "Smooth"   // genuinely just a grade
            case .beautyFilter: return "Blush"
            case .brightening: return "Ring Light"
            case .glowingSkin: return "Halo"
            case .sharpen: return "Visor"
            case .warmth: return "Freckles"
            case .cool: return "Ice Crown"
            case .vintage: return "Round Specs"
            }
        }

        var icon: String {
            switch self {
            case .none: return "xmark.circle"
            case .faceSmoothing: return "sparkles"
            case .beautyFilter: return "face.smiling"
            case .brightening: return "circle.dashed"
            case .glowingSkin: return "sun.max"
            case .sharpen: return "eyeglasses"
            case .warmth: return "circle.grid.3x3.fill"
            case .cool: return "snowflake"
            case .vintage: return "camera.aperture"
            }
        }

        var thumbnailAsset: String {
            switch self {
            case .none: return "ar_filter_none"
            case .faceSmoothing: return "ar_filter_smooth"
            case .beautyFilter: return "ar_filter_beauty"
            case .brightening: return "ar_filter_brighten"
            case .glowingSkin: return "ar_filter_glow"
            case .sharpen: return "ar_filter_sharpen"
            case .warmth: return "ar_filter_warm"
            case .cool: return "ar_filter_cool"
            case .vintage: return "ar_filter_vintage"
            }
        }
        
        var description: String {
            switch self {
            // Lead with the costume, then the grade that comes with it.
            case .none: return "No Filter"
            case .faceSmoothing: return "Smooth skin, reduce wrinkles"
            case .beautyFilter: return "Rosy cheeks and sparkles"
            case .brightening: return "A ring of light around your face"
            case .glowingSkin: return "A golden halo overhead"
            case .sharpen: return "A cyan visor across your eyes"
            case .warmth: return "Freckles and a warm tone"
            case .cool: return "A crown of ice, on a cool tone"
            case .vintage: return "Round specs, on a vintage wash"
            }
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
        guard let faceObservation else { return image }
        
        var outputImage = image
        
        switch activeFilter {
        case .none:
            return image
            
        case .faceSmoothing:
            outputImage = applySmoothingFilter(to: outputImage)
            
        case .beautyFilter:
            // Combine multiple filters for beauty effect
            outputImage = applySmoothingFilter(to: outputImage)
            outputImage = applyBrighteningFilter(to: outputImage)
            outputImage = applyGlowFilter(to: outputImage)
            
        case .brightening:
            outputImage = applyBrighteningFilter(to: outputImage)
            
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
        
        let faceComposite = compositeFaceEffect(
            original: image,
            filtered: outputImage.cropped(to: image.extent),
            faceObservation: faceObservation
        )
        switch activeFilter {
        case .beautyFilter, .warmth:
            return applyTrackedFaceArtwork(
                filter: activeFilter,
                to: faceComposite,
                faceObservation: faceObservation
            )
        default:
            // Ring light, halo, visor, crown and glasses are real 3D meshes in
            // the transparent shared layer. Drawing these outlines too would
            // leave the old flat sticker underneath the model.
            return faceComposite
        }
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
        // Landmarks give the renderer stable eye positions. Bounding-box-only
        // effects looked like screen stickers and drifted whenever the user
        // turned their head.
        let request = VNDetectFaceLandmarksRequest { request, error in
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
                            print("   Frame will remain unchanged")
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
                        print("⚠️ [ARFilter] No face detected in frame - leaving frame unchanged")
                    }
                    #endif
                }
            }
            
            // Access main actor isolated methods safely
            Task { @MainActor in
                self.publishFaceTrack(faceObservation)
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

    private func publishFaceTrack(_ observation: VNFaceObservation?) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFaceTrackPublishTime >= 1.0 / 12.0 else { return }
        lastFaceTrackPublishTime = now
        onFaceTrack?(
            observation?.boundingBox,
            observation?.confidence ?? 0,
            CGFloat(observation?.roll?.doubleValue ?? 0),
            CGFloat(observation?.yaw?.doubleValue ?? 0)
        )
    }
    
    /// Create a pixel buffer from CIImage
    private func createPixelBuffer(from ciImage: CIImage) -> CVPixelBuffer? {
        let extent = ciImage.extent.integral
        guard extent.width > 0, extent.height > 0 else {
            return nil
        }

        let width = Int(extent.width)
        let height = Int(extent.height)
        
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
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

        let normalizedImage = ciImage.transformed(
            by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
        )
        let renderBounds = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        ciContext.render(
            normalizedImage,
            to: buffer,
            bounds: renderBounds,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return buffer
    }
    
    // MARK: - Filter Implementations
    
    /// Smoothing filter to reduce wrinkles and imperfections
    private func applySmoothingFilter(to image: CIImage) -> CIImage {
        // Use bilateral filter for edge-preserving smoothing
        guard let smoothingFilter = CIFilter(name: "CIMedianFilter") else {
            return image
        }
        
        smoothingFilter.setValue(image, forKey: kCIInputImageKey)
        
        guard let smoothed = smoothingFilter.outputImage else {
            return image
        }
        
        return smoothed
    }
    
    /// Brightening filter for face
    private func applyBrighteningFilter(to image: CIImage) -> CIImage {
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
    
    private func compositeFaceEffect(
        original: CIImage,
        filtered: CIImage,
        faceObservation: VNFaceObservation
    ) -> CIImage {
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return original }

        blendFilter.setValue(filtered, forKey: kCIInputImageKey)
        blendFilter.setValue(original, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(
            createFaceMask(from: faceObservation, imageExtent: original.extent),
            forKey: kCIInputMaskImageKey
        )

        return (blendFilter.outputImage ?? original).cropped(to: original.extent)
    }

    /// Create a soft mask around the detected face region.
    private func createFaceMask(from observation: VNFaceObservation, imageExtent: CGRect) -> CIImage {
        let bounds = observation.boundingBox
        
        // Vision and Core Image both use lower-left image coordinates.
        let x = imageExtent.minX + bounds.origin.x * imageExtent.width
        let y = imageExtent.minY + bounds.origin.y * imageExtent.height
        let width = bounds.width * imageExtent.width
        let height = bounds.height * imageExtent.height
        
        let faceRect = CGRect(x: x, y: y, width: width, height: height)
            .insetBy(dx: -width * 0.18, dy: -height * 0.22)
        
        // Create a radial gradient mask centered on face
        let centerX = faceRect.midX
        let centerY = faceRect.midY
        let radius = max(faceRect.width, faceRect.height) * 0.58
        
        guard let gradientFilter = CIFilter(name: "CIRadialGradient") else {
            return CIImage(color: CIColor.clear).cropped(to: imageExtent)
        }
        
        gradientFilter.setValue(CIVector(x: centerX, y: centerY), forKey: "inputCenter")
        gradientFilter.setValue(NSNumber(value: radius * 0.5), forKey: "inputRadius0")
        gradientFilter.setValue(NSNumber(value: radius * 1.2), forKey: "inputRadius1")
        gradientFilter.setValue(CIColor.white, forKey: "inputColor0")
        gradientFilter.setValue(CIColor.black, forKey: "inputColor1")
        
        let mask = gradientFilter.outputImage?.cropped(to: imageExtent)
        return mask ?? CIImage(color: CIColor.clear).cropped(to: imageExtent)
    }

    // MARK: - Face-anchored AR artwork

    private func applyTrackedFaceArtwork(
        filter: ARFilter,
        to image: CIImage,
        faceObservation: VNFaceObservation
    ) -> CIImage {
        guard filter != .none && filter != .faceSmoothing else { return image }

        let face = faceRect(for: faceObservation, imageExtent: image.extent)
        guard face.width > 1, face.height > 1 else { return image }
        let eyeLine = trackedEyeLine(for: faceObservation, faceRect: face)
        var output = image

        switch filter {
        case .none, .faceSmoothing:
            break

        case .beautyFilter:
            let cheekSize = face.width * 0.16
            output = sourceOver(
                softDot(center: CGPoint(x: face.minX + face.width * 0.25, y: face.minY + face.height * 0.42), radius: cheekSize, color: CIColor(red: 1, green: 0.18, blue: 0.48, alpha: 0.30), extent: image.extent),
                output
            )
            output = sourceOver(
                softDot(center: CGPoint(x: face.maxX - face.width * 0.25, y: face.minY + face.height * 0.42), radius: cheekSize, color: CIColor(red: 1, green: 0.18, blue: 0.48, alpha: 0.30), extent: image.extent),
                output
            )
        case .brightening:
            output = addRoundedOutline(
                rect: face.insetBy(dx: -face.width * 0.08, dy: -face.height * 0.08),
                width: max(3, face.width * 0.018),
                color: CIColor(red: 1, green: 0.93, blue: 0.55, alpha: 0.86),
                to: output
            )

        case .glowingSkin:
            let halo = CGRect(
                x: face.minX + face.width * 0.12,
                y: face.maxY + face.height * 0.08,
                width: face.width * 0.76,
                height: face.height * 0.13
            )
            output = addRoundedOutline(
                rect: halo,
                width: max(4, face.width * 0.025),
                color: CIColor(red: 1, green: 0.77, blue: 0.18, alpha: 0.95),
                to: output
            )
            output = addSparkles(to: output, around: face)

        case .sharpen:
            let visor = CGRect(
                x: face.minX - face.width * 0.03,
                y: eyeLine.y - face.height * 0.11,
                width: face.width * 1.06,
                height: face.height * 0.24
            )
            output = sourceOver(
                roundedRect(visor, radius: visor.height * 0.34, color: CIColor(red: 0.05, green: 0.85, blue: 1, alpha: 0.30), extent: image.extent),
                output
            )
            output = addRoundedOutline(
                rect: visor,
                width: max(3, face.width * 0.018),
                color: CIColor(red: 0.23, green: 0.95, blue: 1, alpha: 0.95),
                to: output
            )
            let bridge = CGRect(x: eyeLine.x - face.width * 0.012, y: visor.minY, width: face.width * 0.024, height: visor.height)
            output = sourceOver(roundedRect(bridge, radius: bridge.width * 0.5, color: CIColor(red: 0.8, green: 1, blue: 1, alpha: 0.8), extent: image.extent), output)

        case .warmth:
            let y = face.minY + face.height * 0.48
            for index in 0..<7 {
                let offset = CGFloat(index - 3) * face.width * 0.055
                let stagger = CGFloat(abs(index - 3)) * face.height * 0.012
                let center = CGPoint(x: face.midX + offset, y: y - stagger)
                output = sourceOver(
                    softDot(center: center, radius: face.width * 0.013, color: CIColor(red: 0.42, green: 0.16, blue: 0.06, alpha: 0.84), extent: image.extent),
                    output
                )
            }

        case .cool:
            let baseY = face.maxY + face.height * 0.01
            let heights: [CGFloat] = [0.16, 0.23, 0.31, 0.23, 0.16]
            for (index, heightScale) in heights.enumerated() {
                let crystalWidth = face.width * 0.12
                let crystalHeight = face.height * heightScale
                let crystal = CGRect(
                    x: face.minX + face.width * (0.16 + CGFloat(index) * 0.13),
                    y: baseY,
                    width: crystalWidth,
                    height: crystalHeight
                )
                output = sourceOver(
                    roundedRect(crystal, radius: crystalWidth * 0.28, color: CIColor(red: 0.35, green: 0.82, blue: 1, alpha: 0.86), extent: image.extent),
                    output
                )
            }

        case .vintage:
            let lensSize = CGSize(width: face.width * 0.42, height: face.height * 0.25)
            let left = CGRect(x: eyeLine.left.x - lensSize.width * 0.5, y: eyeLine.left.y - lensSize.height * 0.5, width: lensSize.width, height: lensSize.height)
            let right = CGRect(x: eyeLine.right.x - lensSize.width * 0.5, y: eyeLine.right.y - lensSize.height * 0.5, width: lensSize.width, height: lensSize.height)
            let frameColor = CIColor(red: 0.08, green: 0.035, blue: 0.02, alpha: 0.96)
            output = addRoundedOutline(rect: left, width: max(5, face.width * 0.035), color: frameColor, to: output)
            output = addRoundedOutline(rect: right, width: max(5, face.width * 0.035), color: frameColor, to: output)
            let bridge = CGRect(x: left.maxX, y: eyeLine.y - face.height * 0.015, width: max(1, right.minX - left.maxX), height: max(5, face.height * 0.03))
            output = sourceOver(roundedRect(bridge, radius: bridge.height * 0.5, color: frameColor, extent: image.extent), output)
        }

        return output.cropped(to: image.extent)
    }

    private func faceRect(for observation: VNFaceObservation, imageExtent: CGRect) -> CGRect {
        CGRect(
            x: imageExtent.minX + observation.boundingBox.minX * imageExtent.width,
            y: imageExtent.minY + observation.boundingBox.minY * imageExtent.height,
            width: observation.boundingBox.width * imageExtent.width,
            height: observation.boundingBox.height * imageExtent.height
        )
    }

    private func trackedEyeLine(for observation: VNFaceObservation, faceRect: CGRect) -> (left: CGPoint, right: CGPoint, x: CGFloat, y: CGFloat) {
        func center(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let region, !region.normalizedPoints.isEmpty else { return nil }
            let average = region.normalizedPoints.reduce(CGPoint.zero) { partial, point in
                CGPoint(x: partial.x + point.x, y: partial.y + point.y)
            }
            let count = CGFloat(region.normalizedPoints.count)
            return CGPoint(
                x: faceRect.minX + average.x / count * faceRect.width,
                y: faceRect.minY + average.y / count * faceRect.height
            )
        }

        let left = center(observation.landmarks?.leftEye)
            ?? CGPoint(x: faceRect.minX + faceRect.width * 0.32, y: faceRect.minY + faceRect.height * 0.62)
        let right = center(observation.landmarks?.rightEye)
            ?? CGPoint(x: faceRect.minX + faceRect.width * 0.68, y: faceRect.minY + faceRect.height * 0.62)
        return (left, right, (left.x + right.x) * 0.5, (left.y + right.y) * 0.5)
    }

    private func sourceOver(_ overlay: CIImage, _ background: CIImage) -> CIImage {
        overlay.composited(over: background)
    }

    private func roundedRect(_ rect: CGRect, radius: CGFloat, color: CIColor, extent: CGRect) -> CIImage {
        guard let generator = CIFilter(name: "CIRoundedRectangleGenerator") else {
            return CIImage(color: color).cropped(to: rect)
        }
        generator.setValue(CIVector(cgRect: rect), forKey: "inputExtent")
        generator.setValue(radius, forKey: "inputRadius")
        generator.setValue(color, forKey: "inputColor")
        return (generator.outputImage ?? CIImage(color: color).cropped(to: rect)).cropped(to: extent)
    }

    private func addRoundedOutline(rect: CGRect, width: CGFloat, color: CIColor, to image: CIImage) -> CIImage {
        let outer = roundedRect(rect, radius: min(rect.width, rect.height) * 0.48, color: color, extent: image.extent)
        let withOuter = sourceOver(outer, image)
        let innerRect = rect.insetBy(dx: width, dy: width)
        guard innerRect.width > 0, innerRect.height > 0 else { return withOuter }
        return sourceOver(image.cropped(to: innerRect), withOuter)
    }

    private func softDot(center: CGPoint, radius: CGFloat, color: CIColor, extent: CGRect) -> CIImage {
        guard let gradient = CIFilter(name: "CIRadialGradient") else {
            return CIImage(color: color).cropped(to: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        gradient.setValue(CIVector(cgPoint: center), forKey: "inputCenter")
        gradient.setValue(radius * 0.35, forKey: "inputRadius0")
        gradient.setValue(radius, forKey: "inputRadius1")
        gradient.setValue(color, forKey: "inputColor0")
        gradient.setValue(CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0), forKey: "inputColor1")
        return (gradient.outputImage ?? CIImage.empty()).cropped(to: extent)
    }

    private func addSparkles(to image: CIImage, around face: CGRect) -> CIImage {
        let points = [
            CGPoint(x: face.minX - face.width * 0.03, y: face.maxY - face.height * 0.18),
            CGPoint(x: face.maxX + face.width * 0.03, y: face.minY + face.height * 0.58),
            CGPoint(x: face.minX + face.width * 0.12, y: face.minY + face.height * 0.12)
        ]
        return points.reduce(image) { output, point in
            let size = face.width * 0.045
            let vertical = CGRect(x: point.x - size * 0.18, y: point.y - size, width: size * 0.36, height: size * 2)
            let horizontal = CGRect(x: point.x - size, y: point.y - size * 0.18, width: size * 2, height: size * 0.36)
            let color = CIColor(red: 1, green: 0.95, blue: 1, alpha: 0.94)
            let first = sourceOver(roundedRect(vertical, radius: size * 0.18, color: color, extent: image.extent), output)
            return sourceOver(roundedRect(horizontal, radius: size * 0.18, color: color, extent: image.extent), first)
        }
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
            guard let device = MTLCreateSystemDefaultDevice(),
                  let faceGeometry = ARSCNFaceGeometry(device: device) else { return }
            let faceNode = SCNNode(geometry: faceGeometry)
            node.addChildNode(faceNode)
            currentFaceNode = faceNode
        }
        
        if let faceGeometry = currentFaceNode?.geometry as? ARSCNFaceGeometry {
            faceGeometry.update(from: faceAnchor.geometry)
        }
    }
}
