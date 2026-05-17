# Cube Hold to Show Timeline Feature

## Overview
Holding the cube now reveals the Instagram-style timeline grid view, providing a quick way to browse all posts at once.

## How It Works

### User Experience
1. **Hold the cube** (any face) for ~0.5 seconds
2. Timeline view **animates in** with a spring animation
3. User can **browse the grid** of posts
4. **Tap any post** to return to fullscreen view at that post

### Technical Implementation

#### Long Press Duration
- **0.5 seconds** - Triggers timeline view and other hold features
- Recording (on Record tab) uses a separate countdown timer that starts at hold begin

#### Notification Flow
```
User holds cube for 0.5 seconds
    ↓
UILongPressGestureRecognizer fires (CubeTabView)
    ↓
Posts cubeHoldBegan + cameraCubeHoldBegan notifications
    ↓
FeedView receives cubeHoldBegan
    ↓
showTimelineView = true (with animation)
    ↓
Timeline grid displayed
```

#### Code Changes

**In `FeedView.swift`:**
```swift
.onReceive(NotificationCenter.default.publisher(for: .cubeHoldBegan)) { _ in
    // Show timeline view when cube is held
    guard !posts.isEmpty else { return }
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        showTimelineView = true
    }
    // Haptic feedback
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
}

.onReceive(NotificationCenter.default.publisher(for: .cubeHoldEnded)) { _ in
    // Timeline stays visible until user taps a post
}
```

#### Behavior Details
- **Only shows if posts exist** - Empty feed won't trigger timeline
- **Haptic feedback** - Medium impact when timeline appears
- **Spring animation** - Smooth 0.3s spring with 0.8 damping
- **Persistent view** - Timeline stays visible until user taps a post (doesn't auto-dismiss on hold end)

## Related Features

### Other Ways to Access Timeline
1. **Long press the grid button** (top right corner)
2. **"ToggleTimelineView" notification** (programmatic access)

### Timeline to Fullscreen Flow
When user taps a post in timeline:
```swift
onPostTapped: { index in
    currentIndex = index  // Jump to that post
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        showTimelineView = false  // Dismiss timeline
    }
}
```

## Design Rationale

### Why Cube Hold?
- **Natural gesture** - Holding the cube feels like "grabbing" to see everything
- **Non-destructive** - Doesn't interfere with rotation or navigation
- **Discoverable** - Users naturally hold objects to examine them
- **Consistent** - Matches other hold gestures in the app (radius bar, etc.)

### Why Keep Timeline Visible After Release?
- Prevents accidental dismissal if user's finger slips
- Allows user to take their time browsing
- Clear dismissal action (tap a post) is intuitive

## Testing

### Manual Testing Steps
1. Launch app and navigate to Feed tab
2. Hold any face of the cube for 0.5+ seconds
3. Verify timeline appears with spring animation
4. Verify haptic feedback fires
5. Release cube - timeline should stay visible
6. Tap any post in grid
7. Verify feed returns to fullscreen at selected post

### Edge Cases
- **Empty feed** - Timeline should NOT appear (guard prevents it)
- **Loading state** - Timeline shows whatever posts are currently loaded
- **Rapid hold/release** - Timeline should persist until user action

## Future Enhancements

### Potential Improvements
1. **Hold duration indicator** - Visual feedback while holding (progress ring on cube?)
2. **Preview on hover** - Show post preview when hovering over grid item
3. **Filters in timeline** - Quick filter by country/channel in grid view
4. **Pinch to zoom** - Zoom timeline grid to show more/fewer posts
5. **3D cube transition** - Cube could "unfold" into the grid

### Alternative Gestures to Consider
- **Double-tap cube** - Quicker access but less discoverable
- **Shake device** - Fun but might trigger accidentally
- **Swipe on cube** - Could conflict with rotation gestures

## Related Notifications

### Cube Gestures
- `cubeHoldBegan` - Cube hold started (triggers timeline)
- `cubeHoldEnded` - Cube hold ended (currently no action)
- `CubeGlobalTap` - Single tap on cube
- `CubeGlobalDragChanged` - Cube being rotated

### Timeline Control
- `ToggleTimelineView` - Toggle timeline visibility

## Implementation Notes

### Performance
- Timeline shows existing `posts` array - no additional loading
- Grid is lazy-loaded via `FeedTimelineView`
- Post thumbnails may need to be downloaded on first view

### State Management
- `showTimelineView` state controls visibility
- `currentIndex` tracks selected post when returning to fullscreen
- Posts array is shared between fullscreen and timeline views

## User Documentation

### Help Text for Users
> **💡 Tip:** Hold the cube to see all your posts in a grid view. Tap any post to jump right to it!

### Tutorial/Onboarding Suggestion
Add to first-time user experience:
1. Show cube with pulsing highlight
2. Overlay text: "Hold the cube to browse all posts"
3. After user tries it once, mark as completed
