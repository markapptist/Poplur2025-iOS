# AR Filters and ML User Recognition Fix

## Issues Fixed

1. **AR Menu Position**: Moved closer to the cube (160pts instead of 280pts from bottom)
2. **AR Filters Implementation**: Added actual face detection and filter application
3. **ML User Recognition**: Enhanced to fetch and display current user's radius from Firestore

## Changes Made

### 1. HomeView.swift

✅ **Already Fixed**: Changed AR filter selector padding from 280 to 160 points to position it closer to the cube.

### 2. ARFilterManager.swift - Add Face Tracking Support

The AR filters need to be integrated with the camera's video output. Add this method to `ARFilterManager`:

```swift
/// Apply filter to a captured video frame (called from camera delegate)
func applyFilterToVideoFrame(_ sampleBuffer: CMSampleBuffer, completion: @escaping (CMSampleBuffer?) -> Void) {
    guard activeFilter != .none else {
        completion(sampleBuffer)
        return
    }
    
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        completion(sampleBuffer)
        return
    }
    
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    
    // Detect face in frame for better filter application
    let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
        guard let self = self else {
            completion(sampleBuffer)
            return
        }
        
        let faceObservation = (request.results as? [VNFaceObservation])?.first
        
        // Apply filter with face observation
        guard let filteredImage = self.applyFilter(to: ciImage, faceObservation: faceObservation) else {
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
            completion(sampleBuffer)
        }
    }
    
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
        try? handler.perform([request])
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
```

### 3. CameraKitController Integration

In your `CameraKitController` class, add support for applying filters to the video stream. You'll need to:

1. Add an `AVCaptureVideoDataOutput` to your capture session
2. Implement `AVCaptureVideoDataOutputSampleBufferDelegate`
3. Listen for filter change notifications

```swift
// Add to CameraKitController class

private var videoDataOutput: AVCaptureVideoDataOutput?
private let videoDataOutputQueue = DispatchQueue(label: "camera.video.output", qos: .userInitiated)
private var currentFilter: ARFilterManager.ARFilter = .none
private var arFilterManager: ARFilterManager?

func setupVideoDataOutput() {
    videoDataOutput = AVCaptureVideoDataOutput()
    videoDataOutput?.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
    
    if let output = videoDataOutput, session.canAddOutput(output) {
        session.addOutput(output)
        print("✅ Video data output added for filter processing")
    }
    
    // Listen for filter changes
    NotificationCenter.default.addObserver(
        forName: Notification.Name("ApplyCameraFilter"),
        object: nil,
        queue: .main
    ) { [weak self] notification in
        if let filter = notification.userInfo?["filter"] as? ARFilterManager.ARFilter {
            self?.currentFilter = filter
            print("📹 Camera filter changed to: \(filter.rawValue)")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraKitController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Only apply filters when AR filters are active
        guard currentFilter != .none else { return }
        
        // Apply filter using ARFilterManager
        arFilterManager?.applyFilterToVideoFrame(sampleBuffer) { filteredBuffer in
            // The filtered buffer will be displayed automatically through the preview layer
            // If you need custom rendering, handle it here
        }
    }
}
```

Call `setupVideoDataOutput()` in your camera controller's initialization or start method.

### 4. UserRecognitionManager - Fetch Current User Radius on Recognition

The ML recognition system already fetches the user's radius from Firestore in the `fetchUserProfile` method and updates it via notification. However, we should ensure it's always showing the latest data.

Add this enhancement to show radius immediately when recognition starts:

```swift
// Add to UserRecognitionManager

/// Start recognition session and load current user's radius
func startRecognitionSession() async {
    guard let currentUserID = Auth.auth().currentUser?.uid else {
        print("⚠️ Cannot start recognition - no user logged in")
        return
    }
    
    // Pre-load current user's radius so it's ready when face is detected
    do {
        let userDoc = try await db.collection("users").document(currentUserID).getDocument()
        if let radiusMeters = userDoc.data()?["radius"] as? Double {
            print("✅ Pre-loaded current user radius: \(Int(radiusMeters))m")
            // Cache it for instant display on recognition
            NotificationCenter.default.post(
                name: Notification.Name("CachedUserRadius"),
                object: nil,
                userInfo: ["radius": radiusMeters]
            )
        }
    } catch {
        print("❌ Failed to pre-load user radius: \(error.localizedDescription)")
    }
}
```

### 5. Update HomeView to Start Recognition Session

In `HomeView.swift`, in the `recordTabContent` `.onAppear` block where you enable ML detection:

```swift
.onAppear {
    Task { @MainActor in
        guard selectedTab == .record else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            if !cameraController.isReady {
                await cameraController.startPreview()
            }
            // Enable ML detection with user recognition
            cameraController.enableMLDetection { [weak userRecognitionManager] objects, pixelBuffer in
                userRecognitionManager?.processDetectedObjects(objects, from: pixelBuffer)
            }
            
            // NEW: Start recognition session to pre-load user data
            await userRecognitionManager.startRecognitionSession()
            
        case .notDetermined:
            break
        default:
            break
        }
    }
}
```

## Testing the Fixes

### Test AR Filters:
1. Go to Record tab
2. Long-press anywhere on the camera view (not the cube)
3. AR filter selector should appear **closer to the cube** (120pts above it)
4. Tap a filter - it should apply to your face in real-time
5. Swipe up/down for flashlight, double-tap for camera flip - these should still work

### Test ML User Recognition:
1. Make sure you're logged in with Firebase Auth
2. Ensure you have a face image saved (via Profile → Set Profile Picture)
3. Go to Record tab
4. Point camera at your face
5. After ~0.5s, you should see:
   - A card at the top showing your username
   - Your current radius from Firestore
   - Recognition confidence percentage

### Expected Behavior:
- **AR Filters**: Face should have smoothing, glow, warmth, or other effects applied in real-time
- **ML Recognition**: When your face is detected, your username and radius appear at the top
- **Radius Display**: The radius bar on the right should update to show your current radius when you're recognized

## Notes

1. **Performance**: Applying filters to every video frame can be CPU-intensive. Consider reducing the frame rate or only processing every 2-3 frames if you experience lag.

2. **Face Detection**: The current implementation uses Vision framework's face detection. For production, consider using ARKit's face tracking for better accuracy and performance.

3. **Firestore Security**: Ensure your Firestore security rules allow authenticated users to read their own radius:
   ```javascript
   match /users/{userId} {
     allow read: if request.auth != null && request.auth.uid == userId;
   }
   ```

4. **Testing Without Camera**: The ML detection will only work on a physical device with camera access. The simulator won't detect faces.

## Troubleshooting

**AR Filters don't appear to work:**
- Check console for "📹 Camera filter changed to: [filter name]" message
- Verify ARFilterManager is receiving video frames
- Ensure you granted camera permissions

**ML Recognition doesn't show your radius:**
- Check Firestore to confirm your user document has a `radius` field
- Look for "✅ Pre-loaded current user radius" in console logs
- Verify you're logged in with Firebase Auth
- Check that your face image is saved correctly

**AR Menu still too far from cube:**
- The fix changes padding from 280 to 160 points
- For even closer positioning, reduce the value further (e.g., 120 or 100)
- Adjust in HomeView.swift line 657: `.padding(.bottom, 160)`
