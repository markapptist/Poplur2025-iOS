# AR Face Filters Integration Guide

## Overview
This implements Snapchat-style AR face filters that appear on long-press in the camera view. Features include face smoothing, beauty filters, and various visual effects.

## Files Created

### 1. **ARFilterManager.swift**
Manages AR face tracking and filter application using:
- **ARKit** for face tracking
- **Core Image** for filter effects
- **Vision** for face detection

### 2. **ARFilterSelector.swift**
SwiftUI UI for filter selection with horizontal scrolling filter buttons.

## Available Filters

1. **None** - No filter applied
2. **Smooth** - Face smoothing to reduce wrinkles (main feature)
3. **Beauty** - All-in-one beauty enhancement (smooth + brighten + glow)
4. **Brighten** - Brightens the face
5. **Glow** - Glowing, radiant skin effect
6. **Sharpen** - Sharpen facial details
7. **Warm** - Warm orange/golden tones
8. **Cool** - Cool blue tones
9. **Vintage** - Sepia + vignette effect

## Integration with Camera

### Step 1: Add to HomeView or Camera View

```swift
import SwiftUI

struct CameraViewWithFilters: View {
    @StateObject private var filterManager = ARFilterManager()
    @State private var showFilters = false
    
    var body: some View {
        ZStack {
            // Your existing camera view
            CameraView()
            
            // AR Filter overlay
            if showFilters {
                VStack {
                    Spacer()
                    ARFilterSelector(
                        filterManager: filterManager,
                        isPresented: $showFilters
                    )
                }
                .transition(.move(edge: .bottom))
            }
        }
        // Long press gesture to show filters
        .onLongPressGesture(minimumDuration: 0.5) {
            withAnimation(.spring()) {
                showFilters.toggle()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }
}
```

### Step 2: Apply Filters to Camera Output

In your camera capture delegate or frame processing:

```swift
// When processing camera frames
func captureOutput(_ output: AVCaptureOutput, 
                   didOutput sampleBuffer: CMSampleBuffer, 
                   from connection: AVCaptureConnection) {
    
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    
    // Detect face for better filter application
    var faceObservation: VNFaceObservation?
    let faceRequest = VNDetectFaceRectanglesRequest { request, error in
        if let results = request.results as? [VNFaceObservation],
           let firstFace = results.first {
            faceObservation = firstFace
        }
    }
    
    try? VNImageRequestHandler(ciImage: ciImage).perform([faceRequest])
    
    // Apply active filter
    if let filteredImage = filterManager.applyFilter(to: ciImage, faceObservation: faceObservation) {
        // Display filtered image
        // Convert back to CVPixelBuffer or UIImage as needed
    }
}
```

### Step 3: AR Face Tracking (Optional - for 3D effects)

For advanced 3D AR effects like face masks:

```swift
// In your view
ARSCNView()
    .onAppear {
        filterManager.setupARSession(in: arSceneView)
    }
    .onDisappear {
        filterManager.stopARSession()
    }
```

## Filter Details

### Face Smoothing (Wrinkle Reduction)
```swift
case .faceSmoothing:
    // Uses median filter for edge-preserving smoothing
    // Creates face mask to apply effect only to face region
    // Intensity controlled by filterIntensity (0.7 default)
```

**How it works:**
1. Detects face region using Vision
2. Creates radial gradient mask around face
3. Applies bilateral/median filter to smooth skin
4. Blends with original based on intensity
5. Preserves edges (eyes, lips) while smoothing wrinkles

### Beauty Filter (All-in-One)
```swift
case .beautyFilter:
    // Combines:
    // 1. Face smoothing
    // 2. Brightening (increased brightness + contrast)
    // 3. Glow effect (subtle bloom)
```

### Glow Filter
```swift
case .glowingSkin:
    // Uses CIBloom filter
    // Creates soft, radiant skin appearance
    // Intensity: 0.3 * filterIntensity
```

## Customization

### Adjust Filter Intensity

```swift
// Global intensity (affects all filters)
filterManager.setIntensity(0.8) // 0.0 - 1.0

// Per-filter intensity (modify in ARFilterManager.swift)
private var filterIntensity: Float = 0.7 // Change this value
```

### Add Custom Filter

```swift
// In ARFilterManager.swift

enum ARFilter {
    // ... existing filters
    case customFilter = "Custom"
}

// Add implementation
private func applyCustomFilter(to image: CIImage) -> CIImage {
    guard let filter = CIFilter(name: "YourCIFilterName") else {
        return image
    }
    
    filter.setValue(image, forKey: kCIInputImageKey)
    // Configure filter parameters
    
    return filter.outputImage ?? image
}

// Add to switch statement in applyFilter()
case .customFilter:
    outputImage = applyCustomFilter(to: outputImage)
```

## Performance Optimization

### Tips for smooth 30fps:

1. **Reduce filter complexity** - Some filters are more expensive
2. **Lower resolution** - Process at lower resolution, upscale result
3. **Frame skipping** - Apply filters every 2-3 frames
4. **Metal acceleration** - Use MTLDevice for GPU processing

```swift
// Process at half resolution
let scale: CGFloat = 0.5
let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
let filtered = applyFilter(to: scaledImage)
let result = filtered?.transformed(by: CGAffineTransform(scaleX: 1/scale, y: 1/scale))
```

## UI/UX Flow

1. **User long-presses camera view**
2. **Filter selector slides up from bottom**
3. **User scrolls horizontally to see filters**
4. **Tap filter to apply (instant preview)**
5. **Selected filter highlighted with blue circle**
6. **Description shows at bottom**
7. **Tap X or anywhere to dismiss**

## Example Integration in Existing Code

If you have an existing CameraKit setup:

```swift
struct CameraTab: View {
    @StateObject private var filterManager = ARFilterManager()
    @State private var showFilters = false
    
    var body: some View {
        ZStack {
            // Existing CameraKit view
            CameraKitView(cameraController: cameraController)
            
            // Filter UI overlay
            if showFilters {
                VStack {
                    Spacer()
                    ARFilterSelector(
                        filterManager: filterManager,
                        isPresented: $showFilters
                    )
                }
                .zIndex(100)
            }
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showFilters.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
        )
    }
}
```

## Testing

1. **Long press** on camera view (hold for 0.5 seconds)
2. **Filter selector appears** from bottom
3. **Scroll** through filters horizontally
4. **Tap "Smooth"** to see wrinkle reduction
5. **Tap "Beauty"** for all-in-one enhancement
6. **Compare** with "None" to see difference

## Notes

- Face smoothing works best with good lighting
- AR Face Tracking requires iPhone X or later (TrueDepth camera)
- Image-based filters work on all devices
- Filters apply in real-time to camera feed
- Performance optimized for 30fps

## Future Enhancements

- **Face masks** (3D virtual accessories)
- **Makeup effects** (lipstick, eyeshadow)
- **Background blur** (portrait mode)
- **Color grading** presets
- **User-created filters**
- **Filter favorites**
- **Before/after slider**
