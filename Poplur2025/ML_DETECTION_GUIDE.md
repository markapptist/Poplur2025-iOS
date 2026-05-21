# ML Object Detection Integration Guide

This guide explains how to add real-time object detection to your camera view using Apple's Vision framework.

## 🚀 Quick Start

### Option 1: Simplified Detection (Recommended)

The easiest way to enable ML detection - just one line of code!

```swift
// In your CameraViewController setup:
override func viewDidLoad() {
    super.viewDidLoad()
    setup()
    
    // 🎯 Enable ML detection with one line!
    enableMLDetection()
}
```

That's it! The camera will now:
- ✅ Detect objects in real-time
- ✅ Show a beautiful badge at the top with detected objects
- ✅ Display confidence percentages
- ✅ Show multiple objects (e.g., "Cat • Also: Dog, Tree")
- ✅ Use emoji icons for common objects
- ✅ Automatically optimize performance (processes every 5th frame)

### Option 2: Custom Detection Manager

For more control, use the full detection manager:

```swift
// Create and configure the manager
let detectionManager = SimplifiedMLDetectionManager()
detectionManager.confidenceThreshold = 0.2  // 20% minimum confidence
detectionManager.frameSkipInterval = 3      // Process every 3rd frame
detectionManager.maxResults = 5             // Show top 5 objects

// Setup callbacks
detectionManager.onDetection = { objects in
    // Handle detected objects
    for object in objects {
        print("Found: \(object.identifier) at \(object.confidencePercentage)%")
    }
}

detectionManager.onError = { error in
    print("Detection error: \(error)")
}

// Process frames (in AVCaptureVideoDataOutputSampleBufferDelegate)
func captureOutput(_ output: AVCaptureOutput, 
                   didOutput sampleBuffer: CMSampleBuffer,
                   from connection: AVCaptureConnection) {
    detectionManager.processFrame(sampleBuffer)
}
```

## 📱 UI Components

### MLDetectionBadgeView

A beautiful, ready-to-use UI component that displays detections:

```swift
let badge = MLDetectionBadgeView()
view.addSubview(badge)

// Update with detections
badge.updateDetections(detectedObjects)

// Hide badge
badge.clear()
```

Features:
- 🎨 Blur background with dark style
- 📊 Shows top object with emoji icon
- 🔢 Displays confidence percentage
- 📋 Lists additional detected objects
- ✨ Smooth fade in/out animations
- 💓 Pulse animation for high-confidence detections

## 🎛 Configuration Options

### Performance Tuning

```swift
// Process fewer frames for better performance
detectionManager.frameSkipInterval = 10  // Only process every 10th frame

// Reduce number of results
detectionManager.maxResults = 1  // Only show top result

// Increase confidence threshold
detectionManager.confidenceThreshold = 0.3  // Only show 30%+ confidence
```

### Typical Frame Skip Values:
- `3` - Very responsive, higher CPU usage (recommended for powerful devices)
- `5` - Balanced (default)
- `10` - Performance mode (recommended for older devices)
- `15` - Maximum battery saving

## 🎯 What Can It Detect?

The Vision framework can detect **1000+ object categories**, including:

### Common Objects:
- 👤 People, faces, body parts
- 🐕 Animals (dogs, cats, birds, etc.)
- 🚗 Vehicles (cars, bikes, trucks, planes)
- 🏢 Buildings and architecture
- 🌳 Nature (trees, plants, flowers)
- 📱 Electronics (phones, laptops, TVs)
- 🍔 Food and drinks
- ⚽️ Sports equipment
- 🎨 Art and decor
- 📚 Books and documents

### Example Detection Results:
```
"golden retriever, 87%"
"smartphone, 64%"
"coffee cup, 52%"
"person, 91% • Also: laptop, desk"
```

## 🔧 Advanced Usage

### Custom Object Detection Model

To use a custom CoreML model instead of Vision's built-in classifier:

1. **Add your CoreML model** to the project (e.g., `YOLOv3.mlmodel`)
2. **Update MLObjectDetectionManager.swift**:

```swift
private func createObjectDetectionModel(configuration: MLModelConfiguration) -> MLModel {
    // Replace with your custom model
    guard let model = try? YOLOv3(configuration: configuration).model else {
        fatalError("Failed to load model")
    }
    return model
}
```

3. **Download models from Apple**:
   - [Apple CoreML Models](https://developer.apple.com/machine-learning/models/)
   - Popular options: YOLOv3, MobileNet, SqueezeNet

### Real-Time Bounding Boxes

To show bounding boxes around detected objects (requires custom CoreML model with object detection):

```swift
// Add the overlay view
let overlayView = DetectionOverlayView(frame: cameraView.bounds)
overlayView.boxColor = .systemGreen
overlayView.showLabels = true
cameraView.addSubview(overlayView)

// Update with detections
overlayView.detections = recognizedObjects
```

## 📊 Performance Considerations

### Battery Impact:
- ✅ Low impact with `frameSkipInterval = 5` or higher
- ⚠️ Medium impact with `frameSkipInterval = 3`
- ❌ High impact with `frameSkipInterval = 1`

### CPU Usage:
- Vision framework is optimized for Apple's Neural Engine
- Automatically uses GPU when available
- Minimal impact on camera preview performance

### Tips:
1. **Use frame skipping** - Don't process every frame
2. **Limit results** - Only show top 3-5 objects
3. **Higher threshold** - Filter out low-confidence detections
4. **Disable when not needed** - Turn off during video recording

## 🔔 Notifications

Listen for detection events anywhere in your app:

```swift
NotificationCenter.default.addObserver(
    forName: NSNotification.Name("MLObjectsDetected"),
    object: nil,
    queue: .main
) { notification in
    if let objects = notification.userInfo?["objects"] as? [DetectedObject] {
        // Handle detected objects
        print("Detected \(objects.count) objects")
    }
}
```

## 🎨 UI Customization

### Custom Badge Appearance:

```swift
// Access the badge view
if let badge = cameraViewController.mlDetectionBadge {
    // Customize appearance (modify MLDetectionBadgeView.swift)
    badge.layer.cornerRadius = 20
    badge.backgroundColor = .systemPurple.withAlphaComponent(0.3)
}
```

## 🐛 Troubleshooting

### "No objects detected"
- ✅ Check `confidenceThreshold` - try lowering to 0.1
- ✅ Ensure good lighting
- ✅ Point camera at recognizable objects

### "Detection is slow"
- ✅ Increase `frameSkipInterval`
- ✅ Reduce `maxResults`
- ✅ Check device performance

### "App crashes on startup"
- ✅ Ensure camera permissions are granted
- ✅ Check video output configuration
- ✅ Verify CoreML model is included in bundle (if using custom model)

## 📝 Example: Complete Integration

Here's a complete example showing how to integrate ML detection:

```swift
import UIKit
import AVFoundation

class MyCameraViewController: CameraViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        
        // Enable ML detection
        enableMLDetection()
        
        // Optional: Customize settings
        mlDetectionManager?.confidenceThreshold = 0.2
        mlDetectionManager?.frameSkipInterval = 5
        mlDetectionManager?.maxResults = 3
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Start detection when view appears
        mlDetectionManager?.isEnabled = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause detection to save battery
        mlDetectionManager?.isEnabled = false
    }
}
```

## 🎓 Learn More

- [Apple Vision Framework Documentation](https://developer.apple.com/documentation/vision)
- [CoreML Models Gallery](https://developer.apple.com/machine-learning/models/)
- [Object Detection Best Practices](https://developer.apple.com/videos/play/wwdc2020/10673/)

## 📄 License

This ML detection implementation uses Apple's Vision framework and follows iOS development best practices.
