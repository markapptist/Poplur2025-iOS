# PreviewSupport Framework - Quick Reference

## ⚡ Quick Setup Checklist

- [ ] Create **PreviewSupport** framework target
- [ ] Add 3 Swift files to framework (Models, Views, Harness)
- [ ] Configure: Skip Install = YES, Build for Distribution = NO
- [ ] Link to main app as "Do Not Embed"
- [ ] Update AppSimulationPreview.swift to import PreviewSupport
- [ ] Build framework, then build app
- [ ] Test preview - should load in < 5 seconds

## 📦 What's in the Framework

### PreviewModels.swift
- `PreviewAppTab` - Tab enum (map, record, feed, profile)
- `PreviewAuthViewModel` - Authentication state
- `PreviewCameraKitController` - Camera mock
- `PreviewIsometricBarSettings` - Settings mock
- `PreviewLocationProvider` - Location provider
- `Notification.Name` extensions - All preview notifications

### PreviewViews.swift  
- `PreviewFeedView` - Feed placeholder
- `PreviewMapView` - Map with coordinates
- `PreviewProfileView` - Profile placeholder
- `VisualEffectBlur` - Blur effect view
- `UIViewControllerRepresentableWrapper` - UIKit wrapper

### PreviewHarness.swift
- `LightweightPreviewHarness` - Main preview container
- Camera controller shim
- Home view stub
- Control panel UI

## 🎯 Usage in Previews

```swift
import SwiftUI
import PreviewSupport

#Preview("My Preview") {
    LightweightPreviewHarness()
}

#Preview("Custom View") {
    NavigationStack {
        PreviewFeedView()
    }
}

#Preview("Map") {
    PreviewMapView(coordinate: (37.7749, -122.4194))
}
```

## 🛠 Common Commands

### Build Framework Only
```
⌘B (with PreviewSupport scheme selected)
```

### Clean Build
```
Shift+⌘K then ⌘B
```

### Resume Preview
```
⌘⌥P (in preview file)
```

## ⚠️ Important Notes

1. **DO NOT** add dependencies to PreviewSupport
   - No Firebase
   - No Google Maps
   - No Snap Kit
   - Keep it lightweight!

2. **Always use `public`** for framework types
   ```swift
   public struct MyPreviewView: View { ... }
   public class MyViewModel: ObservableObject { ... }
   ```

3. **Framework is Debug-only**
   - Not embedded in release builds
   - Only used for Xcode Previews

4. **If preview fails**, check:
   - [ ] Framework built successfully?
   - [ ] Linked as "Do Not Embed"?
   - [ ] Types marked `public`?
   - [ ] No heavy dependencies added?

## 📊 Performance

| Metric | Before | After |
|--------|--------|-------|
| Load Time | 30s+ timeout | 2-5s ✅ |
| Modules | 76 | 1-3 |
| Build Time | Slow | Fast |

## 🔗 Related Files

- `FRAMEWORK_SETUP_GUIDE.md` - Detailed setup instructions
- `PREVIEW_SOLUTIONS.md` - Alternative solutions
- `FastPreviewShim.swift` - Standalone preview option
