# AR Filters Gesture Conflict Fix

## Problems Fixed

1. **Long-press gesture not working** - SwiftUI gesture was being blocked by UIKit gestures
2. **Pictures still being taken** - UIKit gestures in CameraPreviewViewController were still active

## Root Cause

The `CameraPreviewViewController` has multiple UIKit gesture recognizers:
- Long-press (2s) for video recording
- Pan for navigation
- Swipe up/down for torch control  
- Double-tap for camera flip

These UIKit gestures were competing with and blocking the SwiftUI `LongPressGesture` that should open the AR filter selector.

## Solution

### 1. Store Gesture Recognizers (CameraPreviewViewController.swift)
```swift
// Store gesture recognizers so we can disable them
private var longPressGesture: UILongPressGestureRecognizer?
private var panGesture: UIPanGestureRecognizer?
private var swipeUpGesture: UISwipeGestureRecognizer?
private var swipeDownGesture: UISwipeGestureRecognizer?
private var doubleTapGesture: UITapGestureRecognizer?
```

### 2. Listen for AR Filter State (CameraPreviewViewController.swift)
```swift
// Added notification observer
NotificationCenter.default.addObserver(
    self, 
    selector: #selector(handleARFiltersStateChanged), 
    name: Notification.Name("ARFiltersStateChanged"), 
    object: nil
)

@objc private func handleARFiltersStateChanged(_ notification: Notification) {
    guard let isShown = notification.userInfo?["isShown"] as? Bool else { return }
    setGesturesEnabled(!isShown)
}

private func setGesturesEnabled(_ enabled: Bool) {
    longPressGesture?.isEnabled = enabled
    panGesture?.isEnabled = enabled
    swipeUpGesture?.isEnabled = enabled
    swipeDownGesture?.isEnabled = enabled
    doubleTapGesture?.isEnabled = enabled
}
```

### 3. Notify When AR Filters Toggle (HomeView.swift)
```swift
.gesture(
    LongPressGesture(minimumDuration: 0.5)
        .onEnded { _ in
            showARFilters.toggle()
            UserDefaults.standard.set(showARFilters, forKey: "ARFiltersShown")
            
            // Notify CameraPreviewVC to disable/enable gestures
            NotificationCenter.default.post(
                name: Notification.Name("ARFiltersStateChanged"),
                object: nil,
                userInfo: ["isShown": showARFilters]
            )
        }
)
```

### 4. Notify When Filters Close (ARFilterSelector.swift)
```swift
// When X button tapped or view disappears
NotificationCenter.default.post(
    name: Notification.Name("ARFiltersStateChanged"),
    object: nil,
    userInfo: ["isShown": false]
)
```

## How It Works

### Opening AR Filters:
1. User long-presses camera view (0.5s)
2. SwiftUI gesture triggers
3. `showARFilters` = `true`
4. Post notification: `ARFiltersStateChanged(isShown: true)`
5. CameraPreviewVC disables all UIKit gestures ✅
6. AR filter UI appears, clean interface ✅

### Closing AR Filters:
1. User taps X button or navigates away
2. `showARFilters` = `false`
3. Post notification: `ARFiltersStateChanged(isShown: false)`
4. CameraPreviewVC re-enables all UIKit gestures ✅
5. Normal camera functionality restored ✅

## Gestures Disabled When AR Filters Active

| Gesture | Purpose | State When Filters Active |
|---------|---------|---------------------------|
| Long Press (2s) | Video recording | ❌ Disabled |
| Pan (horizontal) | Tab navigation | ❌ Disabled |
| Swipe Up | Turn torch ON | ❌ Disabled |
| Swipe Down | Turn torch OFF | ❌ Disabled |
| Double Tap | Flip camera | ❌ Disabled |
| Cube Tap | Take photo | ❌ Disabled (via UserDefaults check) |

## User Experience

### Before Fix:
- ❌ Long-press doesn't work (blocked by UIKit gestures)
- ❌ Can still accidentally trigger video recording
- ❌ Can still swipe/pan while viewing filters
- ❌ Confusing interaction

### After Fix:
- ✅ Long-press opens AR filters smoothly
- ✅ All camera gestures disabled when browsing filters
- ✅ Clean, focused filter selection experience
- ✅ Gestures re-enable automatically when closing filters
- ✅ Only cube and filters visible (all UI hidden)

## Technical Details

**Notification Flow:**
```
HomeView (SwiftUI) 
  ↓ Long Press Detected
  ↓ Toggle showARFilters
  ↓ Post "ARFiltersStateChanged"
  ↓
CameraPreviewViewController (UIKit)
  ↓ Receive notification
  ↓ Call setGesturesEnabled(false)
  ↓ Disable all UIKit gestures
  ↓
User browses filters without interference ✅
```

**Restoration Flow:**
```
ARFilterSelector (SwiftUI)
  ↓ X button tapped / view disappears
  ↓ Post "ARFiltersStateChanged(false)"
  ↓
CameraPreviewViewController (UIKit)
  ↓ Receive notification
  ↓ Call setGesturesEnabled(true)
  ↓ Re-enable all UIKit gestures
  ↓
Normal camera functionality restored ✅
```

## Files Modified

1. **CameraPreviewViewController.swift**
   - Added gesture recognizer storage
   - Added `handleARFiltersStateChanged` notification handler
   - Added `setGesturesEnabled()` method
   - Gesture recognizers now stored in properties

2. **HomeView.swift**
   - Post `ARFiltersStateChanged` notification on toggle
   - Enable hit testing on camera preview host
   - Hide all UI overlays when filters shown

3. **ARFilterSelector.swift**
   - Post `ARFiltersStateChanged(false)` on close
   - Post notification in `.onDisappear`
   - Clear UserDefaults flag

## Benefits

✅ **No gesture conflicts** - UIKit gestures disabled when needed  
✅ **Clean interface** - Only camera + cube + filters visible  
✅ **Smooth interactions** - Long-press works reliably  
✅ **Automatic restoration** - Gestures re-enable on close  
✅ **Snapchat-like UX** - Professional filter browsing experience  
