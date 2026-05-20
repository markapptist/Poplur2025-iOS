# Zoom Slider Implementation Guide

## Visual Overview

```
                                    ┌───────┐
                                    │   ⊕   │  ← Zoom In Button
                                    └───────┘     (100m step)
                                        ┃
                                        ┃ 
                     Vertical Slider    ┃         ← Rotated 90°
                     (200pt tall)       ┃            (smooth control)
                                        ┃
                                        ┃
                                    ┌───────┐
                                    │   ⊖   │  ← Zoom Out Button
                                    └───────┘     (100m step)
```

## How It Works

### 1. State Management
```swift
@State private var zoomLevel: Double = 300  // Current zoom in meters
```

The `zoomLevel` state variable:
- Tracks current camera distance (100m - 20km)
- Updates when slider moves
- Syncs with pinch-to-zoom gestures
- Initializes to 300m (close view)

### 2. Bidirectional Sync

**Slider → Camera:**
```swift
.onChange(of: zoomLevel) { _, newValue in
    updateCameraDistance(newValue)
}
```

**Camera → Slider:**
```swift
// In cameraBinding
if let distance = newValue.camera?.distance {
    zoomLevel = distance
}
```

This means:
- ✅ Slider updates camera position
- ✅ Pinch-to-zoom updates slider
- ✅ Pan gestures update slider
- ✅ Always in sync

### 3. Button Actions

**Zoom In (+):**
```swift
zoomLevel = max(100, zoomLevel - 100)
// Prevents going below minimum (100m)
```

**Zoom Out (-):**
```swift
zoomLevel = min(20_000, zoomLevel + 100)
// Prevents exceeding maximum (20km)
```

### 4. Smooth Animations

All zoom changes use:
```swift
withAnimation(.easeInOut(duration: 0.3)) {
    // Update camera position
}
```

This creates smooth, professional transitions.

## Zoom Levels Reference

| Distance | View Type | Use Case |
|----------|-----------|----------|
| 50-200m  | Building  | Individual rooms/floors |
| 200-500m | Street    | Neighborhoods, blocks |
| 500-2km  | District  | City districts, parks |
| 2-5km    | City      | Entire city overview |
| 5-20km   | Region    | Multiple cities |

## Customization Examples

### Example 1: Different Zoom Ranges for Different Modes

```swift
// Add computed property
private var zoomRange: ClosedRange<Double> {
    if isPostPlacementMode {
        return 50...1000  // Fine control for placement
    } else if mapState.isInTourMode {
        return 1000...50_000  // Wide range for tour
    } else {
        return 100...20_000  // Normal browsing
    }
}

// Update slider
Slider(value: $zoomLevel, in: zoomRange, step: 50)
```

### Example 2: Preset Zoom Buttons

```swift
HStack(spacing: 8) {
    Button("Building") {
        withAnimation { zoomLevel = 200 }
    }
    Button("Street") {
        withAnimation { zoomLevel = 500 }
    }
    Button("City") {
        withAnimation { zoomLevel = 5000 }
    }
}
.buttonStyle(.bordered)
```

### Example 3: Haptic Feedback

```swift
.onChange(of: zoomLevel) { old, new in
    // Trigger haptic at zoom level transitions
    if (old < 500 && new >= 500) || (old >= 500 && new < 500) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    updateCameraDistance(new)
}
```

### Example 4: Show Current Zoom Level

```swift
// Add text indicator
Text(zoomLevelText)
    .font(.caption2)
    .monospacedDigit()
    .foregroundStyle(.secondary)
    .padding(4)
    .background(.ultraThinMaterial, in: Capsule())

private var zoomLevelText: String {
    if zoomLevel < 1000 {
        return "\(Int(zoomLevel))m"
    } else {
        return String(format: "%.1fkm", zoomLevel / 1000)
    }
}
```

## Troubleshooting

### Slider not updating when pinching?
Make sure `cameraBinding` includes the sync code:
```swift
if let distance = newValue.camera?.distance {
    zoomLevel = distance
}
```

### Slider jumping around?
Check that you're not fighting with tour animations:
```swift
// Only update zoomLevel when NOT in tour mode
if !mapState.isInTourMode {
    zoomLevel = distance
}
```

### Buttons not working?
Verify the `max()`/`min()` logic:
```swift
// Zoom in: decrease distance, but not below minimum
zoomLevel = max(100, zoomLevel - 100)

// Zoom out: increase distance, but not above maximum  
zoomLevel = min(20_000, zoomLevel + 100)
```

### Animation choppy?
Increase animation duration:
```swift
withAnimation(.easeInOut(duration: 0.5)) {  // Was 0.3
    // ...
}
```

## Advanced: Logarithmic Zoom Scale

For more natural zoom feel (like Google Maps):

```swift
// Convert linear slider to logarithmic scale
private func linearToLog(_ linear: Double) -> Double {
    let minLog = log10(100)
    let maxLog = log10(20_000)
    let scale = (maxLog - minLog) / (20_000 - 100)
    let logValue = minLog + (linear - 100) * scale
    return pow(10, logValue)
}

// In slider onChange:
.onChange(of: zoomLevel) { _, newValue in
    let logZoom = linearToLog(newValue)
    updateCameraDistance(logZoom)
}
```

This makes:
- Close zoom: slower, more precise
- Far zoom: faster, covers more ground

## Integration Checklist

- [x] Zoom slider positioned on right edge
- [x] Plus/minus buttons work correctly
- [x] Slider syncs with pinch-to-zoom
- [x] Smooth animations (0.3s)
- [x] Proper min/max constraints
- [x] Glassmorphic styling matches app
- [x] No text backgrounds on annotations
- [x] Enhanced 3D beacon markers visible

## What's Next?

Consider adding:
1. **Compass**: Rotation indicator/control
2. **2D/3D toggle**: Switch between flat and pitched views
3. **Follow mode**: Camera follows user location
4. **Zoom presets**: Quick buttons for common views
5. **Gesture indicators**: Show zoom gestures to new users

---

Your zoom slider is production-ready! 🎚️
