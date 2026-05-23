# AR Filters Live Processing + Cube Glow - Implementation Guide

## Issue 1: AR Filters Don't Apply to Face in Real-Time

### The Problem
AR filters are selected but don't visually change your face on camera BEFORE you take a picture (like Snapchat does).

### Why This Happens
Your camera uses `AVCaptureVideoPreviewLayer` which shows the **RAW camera feed directly from hardware**. This layer bypasses all processing - it's a direct pass-through from the camera sensor to the screen.

**The filter processing code exists and works**, but the filtered frames aren't being displayed because:
1. No video output delegate is connected
2. Preview layer shows raw feed, not processed feed
3. Need to replace preview layer with a display layer that shows filtered buffers

### The Fix (3 Options)

#### Option A: AVSampleBufferDisplayLayer (Recommended - Easiest)

Replace the preview layer with a display layer that can show processed frames.

**Step 1**: In `CameraPreviewViewController.swift`, replace the preview layer:

```swift
// REMOVE THIS:
// private let previewLayer: AVCaptureVideoPreviewLayer

// ADD THIS:
private let displayLayer: AVSampleBufferDisplayLayer = {
    let layer = AVSampleBufferDisplayLayer()
    layer.videoGravity = .resizeAspectFill
    return layer
}()
```

**Step 2**: In `init`, remove preview layer setup and use display layer:

```swift
init(session: AVCaptureSession) {
    self.session = session
    // REMOVE: self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
    super.init(nibName: nil, bundle: nil)
}
```

**Step 3**: In `viewDidLoad`, add display layer instead of preview layer:

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    
    // Add display layer instead of preview layer
    view.layer.insertSublayer(displayLayer, at: 0)
    
    // ... rest of setup
}
```

**Step 4**: In `viewDidLayoutSubviews`, update display layer frame:

```swift
override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    displayLayer.frame = view.bounds
    CATransaction.commit()
    
    // ... rest of layout code
}
```

**Step 5**: Add video output to your `CameraKitController` (you'll need to find this file):

```swift
// In CameraKitController class
private var videoDataOutput: AVCaptureVideoDataOutput?
private let videoQueue = DispatchQueue(label: "camera.video", qos: .userInitiated)
private var arFilterManager: ARFilterManager?
private weak var displayLayer: AVSampleBufferDisplayLayer?

func setupARFilters(filterManager: ARFilterManager, displayLayer: AVSampleBufferDisplayLayer) {
    self.arFilterManager = filterManager
    self.displayLayer = displayLayer
    
    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    output.setSampleBufferDelegate(self, queue: videoQueue)
    
    session.beginConfiguration()
    if session.canAddOutput(output) {
        session.addOutput(output)
        videoDataOutput = output
        print("✅ [ARFilter] Video output configured")
    }
    session.commitConfiguration()
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraKitController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // If no filter active, just display raw frame
        guard let filterManager = arFilterManager,
              filterManager.activeFilter != .none else {
            DispatchQueue.main.async { [weak self] in
                self?.displayLayer?.enqueue(sampleBuffer)
            }
            return
        }
        
        // Apply filter and display filtered frame
        filterManager.applyFilterToVideoFrame(sampleBuffer) { [weak self] filteredBuffer in
            if let buffer = filteredBuffer {
                DispatchQueue.main.async {
                    self?.displayLayer?.enqueue(buffer)
                }
            } else {
                // If filter failed, show original
                DispatchQueue.main.async {
                    self?.displayLayer?.enqueue(sampleBuffer)
                }
            }
        }
    }
}
```

**Step 6**: Call setup from `HomeView.swift`:

```swift
.onAppear {
    Task { @MainActor in
        guard selectedTab == .record else { return }
        // ... existing camera setup code ...
        
        // NEW: Setup AR filters with display layer
        if let previewVC = cameraController.recordPreviewViewController as? CameraPreviewViewController {
            cameraController.setupARFilters(
                filterManager: arFilterManager,
                displayLayer: previewVC.displayLayer
            )
        }
    }
}
```

#### Option B: Use CIImage with UIView (Simpler but Lower Performance)

Create a custom view that renders CIImage frames using Core Image.

#### Option C: Metal Rendering (Best Performance but Most Complex)

Use MetalKit for GPU-accelerated real-time rendering of filtered frames.

### Why Option A is Recommended

✅ Native Apple API (AVSampleBufferDisplayLayer)
✅ Good performance (hardware-accelerated)
✅ Relatively simple to implement
✅ Works with existing filter code
✅ Same approach Snapchat and Instagram use

## Issue 2: Make Cube Glow When Flash is On

### The Fix (Already Applied)

I've added notifications when torch state changes. Now you need to make the cube listen and respond.

**Step 1**: ✅ Already done - Notifications sent when torch changes:

```swift
// In CameraPreviewViewController.setTorch()
NotificationCenter.default.post(
    name: Notification.Name("TorchStateChanged"),
    object: nil,
    userInfo: ["isOn": true/false]
)
```

**Step 2**: Make cube glow by adding this to `CubeTabView.swift` Coordinator:

```swift
class Coordinator: NSObject, UIGestureRecognizerDelegate {
    // ... existing properties ...
    
    private var torchObserver: NSObjectProtocol?
    
    init(_ parent: CubeSceneView) {
        self.parent = parent
        super.init()
        
        // ... existing setup ...
        
        // Listen for torch state changes
        torchObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("TorchStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let isOn = notification.userInfo?["isOn"] as? Bool,
                  let scnView = self.view,
                  let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else {
                return
            }
            
            if isOn {
                // Make cube glow bright
                self.animateCubeGlow(cube, intensity: 2.0)
            } else {
                // Return to normal
                self.animateCubeGlow(cube, intensity: 0.5)
            }
        }
    }
    
    deinit {
        if let obs = torchObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        // ... existing cleanup ...
    }
    
    private func animateCubeGlow(_ cube: SCNNode, intensity: CGFloat) {
        guard let box = cube.geometry as? SCNBox else { return }
        
        // Animate emission intensity change
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.3
        
        for material in box.materials {
            material.emission.intensity = intensity
        }
        
        SCNTransaction.commit()
        
        print("💡 [Cube] Glow intensity set to \(intensity)")
    }
}
```

### Expected Behavior

**When you swipe up (flash ON)**:
1. Console: `💡 Swipe UP detected - turning torch ON`
2. Console: `Torch turned ON`
3. Console: `💡 [Cube] Glow intensity set to 2.0`
4. Cube glows brighter (emission intensity increases)

**When you swipe down (flash OFF)**:
1. Console: `💡 Swipe DOWN detected - turning torch OFF`
2. Console: `Torch turned OFF`
3. Console: `💡 [Cube] Glow intensity set to 0.5`
4. Cube returns to normal glow

## Summary of Changes Needed

### For AR Filters to Work:

| File | Action | Status |
|------|--------|--------|
| `CameraPreviewViewController.swift` | Replace `AVCaptureVideoPreviewLayer` with `AVSampleBufferDisplayLayer` | TODO |
| `CameraKitController.swift` | Add video output delegate | TODO |
| `CameraKitController.swift` | Implement `AVCaptureVideoDataOutputSampleBufferDelegate` | TODO |
| `HomeView.swift` | Call `setupARFilters()` on camera controller | TODO |

### For Cube Glow:

| File | Action | Status |
|------|--------|--------|
| `CameraPreviewViewController.swift` | ✅ Send torch state notifications | DONE |
| `CubeTabView.swift` | Add torch observer to Coordinator | TODO |
| `CubeTabView.swift` | Implement `animateCubeGlow()` method | TODO |

## Testing

### AR Filters:
1. Implement Option A above
2. Long-press to open AR filters
3. Select "Smooth" or "Beauty"
4. **You should see your face change in real-time** (like Snapchat)
5. Take photo - photo should have filter applied

### Cube Glow:
1. Swipe up for flash
2. Watch cube - should glow brighter
3. Swipe down to turn off flash
4. Cube should return to normal brightness

## Why AR Filters Are Hard

Unlike simple gestures, AR filters require:
1. **Real-time video processing** (30-60fps)
2. **Face detection** on every frame
3. **Filter application** on every frame
4. **Custom rendering** (can't use standard preview layer)
5. **Performance optimization** (to maintain smooth framerate)

This is why apps like Snapchat/Instagram are impressive - they do all this in real-time!

## Recommendation

**Start with Option A** for AR filters - it's the most straightforward and uses native Apple APIs. Once you see it working, you can optimize if needed.

**Cube glow is easy** - just add the observer and animate method to the Coordinator.

Both features will significantly enhance your app's feel!
