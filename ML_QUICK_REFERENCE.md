# 🎯 ML Detection - Quick Reference Card

## ⚡️ Enable Detection (One Line)

```swift
// In CameraViewController.swift line 68:
enableMLDetection() // ✅ Uncomment this!
```

---

## 🎨 What Users See

```
┌──────────────────────┐
│        🐕           │  ← Emoji icon
│  Golden Retriever   │  ← Object name
│  87% • Also: Tree   │  ← Confidence + others
└──────────────────────┘
```

---

## ⚙️ Quick Settings

```swift
// Balanced (Default)
mlManager.frameSkipInterval = 5
mlManager.confidenceThreshold = 0.2
mlManager.maxResults = 3

// High Performance
mlManager.frameSkipInterval = 3
mlManager.confidenceThreshold = 0.15

// Battery Saving
mlManager.frameSkipInterval = 10
mlManager.confidenceThreshold = 0.3
```

---

## 🔍 Detects 1000+ Objects

Common categories:
- 👤 People & faces
- 🐕 Animals (dogs, cats, birds)
- 🚗 Vehicles
- 🏢 Buildings
- 🌳 Nature
- 📱 Electronics
- 🍔 Food & drink
- ⚽️ Sports

---

## 📊 Integration Examples

### Auto-Tag Posts
```swift
mlManager.onDetection = { objects in
    let tags = objects.map { "#\($0.identifier)" }
    // Add tags to post
}
```

### Update AI Recommendations
```swift
mlManager.onDetection = { objects in
    if objects.contains(where: { $0.identifier.contains("food") }) {
        updateAI("Food posts trending here!")
    }
}
```

### Smart Captions
```swift
let caption: String
if objects.contains("beach") {
    caption = "Beautiful beach day! 🏖"
} else if objects.contains("food") {
    caption = "Great food spot! 🍽"
}
```

---

## 🔔 Listen for Detections

```swift
NotificationCenter.default.addObserver(
    forName: NSNotification.Name("MLObjectsDetected"),
    object: nil,
    queue: .main
) { notification in
    // Handle detected objects
}
```

---

## 🐛 Troubleshooting

| Problem | Solution |
|---------|----------|
| No detections | Lower threshold to 0.1 |
| Too slow | Increase frameSkip to 10 |
| Battery drain | Increase frameSkip to 15 |
| Too many results | Reduce maxResults to 1 |

---

## 📁 Key Files

| File | Purpose |
|------|---------|
| `SimplifiedMLDetection.swift` | Main implementation ⭐ |
| `ML_DETECTION_GUIDE.md` | Full documentation |
| `MLDetectionUseCases.swift` | 7 practical examples |
| `CameraViewWithML.swift` | SwiftUI wrapper |

---

## 💡 Pro Tips

1. ✅ Test on real device (not simulator)
2. ✅ Point at clear, well-lit objects
3. ✅ Wait 1-2 seconds for detection
4. ✅ Combine with location data
5. ✅ Use for post tagging
6. ✅ Feed into AI recommendations

---

## 🎓 Learn More

- 📄 Read: `ML_DETECTION_GUIDE.md`
- 💻 Check: `MLDetectionUseCases.swift`
- 🎨 Try: `CameraViewWithML.swift`

---

## ✨ One-Line Integration

```swift
// UIKit
enableMLDetection()

// SwiftUI
CameraViewWithML(mlDetectionEnabled: true)
```

That's it! 🚀
