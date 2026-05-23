# AR Filters Not Applying - How to Fix

## Problem
AR filters menu works, you can select filters, but they don't actually change your face on camera.

## Why This Happens
The AR filter processing code exists in `ARFilterManager.swift`, but it's **not connected to the camera's video stream**. 

The filters need to process each video frame as it comes from the camera, but currently nothing is calling `ARFilterManager.applyFilterToVideoFrame()`.

## What You Need to Do

You need to add an `AVCaptureVideoDataOutput` to your camera session and implement the delegate to process frames.

### Step 1: Find Your CameraKitController

You have a `CameraKitController` class somewhere in your project. Find this file.

### Step 2: Add Video Output Properties

Add these properties to your `CameraKitController` class:

```swift
class CameraKitController: ObservableObject {
    // ... existing properties ...
    
    // NEW: Add these for AR filter support
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private let videoOutputQueue = DispatchQueue(label: "camera.video.filter", qos: .userInitiated)
    private var arFilterManager: ARFilterManager?
    
    // ... rest of class ...
}
```

### Step 3: Setup Video Output Method

Add this method to `CameraKitController`:

```swift
func setupARFilterSupport(filterManager: ARFilterManager) {
    self.arFilterManager = filterManager
    
    // Create video data output
    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    output.setSampleBufferDelegate(self, queue: videoOutputQueue)
    
    // Add to session
    session.beginConfiguration()
    if session.canAddOutput(output) {
        session.addOutput(output)
        videoDataOutput = output
        print("✅ [ARFilter] Video output configured for filter processing")
    } else {
        print("❌ [ARFilter] Cannot add video output to session")
    }
    session.commitConfiguration()
}
```

### Step 4: Implement Delegate

Add the `AVCaptureVideoDataOutputSampleBufferDelegate` conformance:

```swift
extension CameraKitController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Let ARFilterManager process this frame
        arFilterManager?.applyFilterToVideoFrame(sampleBuffer) { filteredBuffer in
            // The filtered buffer is created but not displayed yet
            // For basic implementation, the filter processing happens in background
            // The preview layer automatically shows the camera feed
            
            // NOTE: To actually DISPLAY the filtered output, you would need to:
            // 1. Replace the preview layer with a custom layer that renders the filtered buffer
            // 2. OR use an AVCaptureVideoPreviewLayer subclass that processes buffers
            // 3. OR use Metal/OpenGL to render filtered frames
            
            // For now, this processes frames and the debug logs will show if it's working
            if filteredBuffer != nil {
                // Frame was successfully filtered
            }
        }
    }
}
```

### Step 5: Call Setup from HomeView

In `HomeView.swift`, when the Record tab appears, call the setup:

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
            
            // NEW: Setup AR filter support
            cameraController.setupARFilterSupport(filterManager: arFilterManager)
            
            // Enable ML detection...
            // ... rest of code ...
        }
    }
}
```

## Why Filters Still Won't Show Up Visually

Even after implementing the above, **you still won't see the filters on screen** because:

1. The `AVCaptureVideoPreviewLayer` displays the RAW camera feed directly from hardware
2. Our filtered frames are created but not used for display
3. The preview layer bypasses our filter processing

### To Actually Display Filtered Video

You need to replace the preview layer with custom rendering. Here are your options:

#### Option A: Use AVCaptureVideoDataOutput for Display (Recommended)

Replace `AVCaptureVideoPreviewLayer` with a custom view that renders filtered frames:

```swift
// In CameraPreviewViewController
private var displayLayer: AVSampleBufferDisplayLayer?

// Instead of previewLayer, use:
let displayLayer = AVSampleBufferDisplayLayer()
displayLayer.videoGravity = .resizeAspectFill
view.layer.insertSublayer(displayLayer, at: 0)
self.displayLayer = displayLayer

// In captureOutput delegate:
func captureOutput(...) {
    arFilterManager?.applyFilterToVideoFrame(sampleBuffer) { filteredBuffer in
        if let buffer = filteredBuffer {
            // Display the filtered frame
            DispatchQueue.main.async {
                self.displayLayer?.enqueue(buffer)
            }
        }
    }
}
```

#### Option B: Use Metal for Real-Time Rendering

Use MetalKit to render filtered frames with GPU acceleration (more complex but better performance).

#### Option C: Use CIImageView

Create a UIView subclass that renders CIImage frames using Core Image.

## Quick Test to See If Filter Processing Works

Even without visual display, you can verify filter processing is working:

### Test 1: Check Console Logs

After implementing Steps 1-5, select an AR filter and check console:

```
✅ [ARFilter] Video output configured for filter processing
🎨 [ARFilter] Processing frame with filter: Smooth
✅ [ARFilter] Face detected at bounds: (0.2, 0.3, 0.6, 0.8)
✅ [ARFilter] Filter applied successfully
✅ [ARFilter] Sample buffer created with filtered image
```

If you see these logs, **filter processing is working** - you just can't see it because the preview layer shows raw camera feed.

### Test 2: Capture a Photo While Filter Active

If your photo capture uses the filtered buffer instead of raw camera, the photo will have the filter applied even if live preview doesn't show it.

## Summary

### What's Working Now:
✅ AR filter menu appears
✅ You can select filters
✅ Filter processing code exists
✅ Face detection code exists

### What's NOT Working:
❌ Filter processing not called (no video output delegate)
❌ Filtered frames not displayed (preview layer shows raw feed)

### To Fix:
1. **Immediate**: Implement Steps 1-5 to connect filter processing to camera
2. **To see results**: Implement Option A, B, or C to display filtered frames

### Files You Need to Modify:
- `CameraKitController.swift` (or whatever your camera controller is called)
- `HomeView.swift` (call setup method)
- `CameraPreviewViewController.swift` (optional: replace preview layer with display layer)

## The Easiest Path Forward

1. **Find your camera controller class** (search for `AVCaptureSession`)
2. **Add Steps 1-4** from above
3. **Call setup from HomeView** (Step 5)
4. **Check console logs** to verify filter processing works
5. **Replace preview layer with display layer** (Option A) to see results

The filter processing pipeline is ready - it just needs to be wired up to your camera!
