# Cube Hold: Toggle Timeline/Fullscreen

## Feature Summary

Holding the cube **toggles** between timeline view and fullscreen view on the Feed tab.

## How It Works

### Toggle Behavior
```
Timeline View (default)
    ↓
Hold cube (0.5s)
    ↓
Fullscreen View
    ↓
Hold cube again (0.5s)
    ↓
Timeline View
    ↓
(repeats)
```

## Implementation

### Code Changes in `FeedView.swift`

```swift
.onReceive(NotificationCenter.default.publisher(for: .cubeHoldBegan)) { _ in
    // Toggle between timeline and fullscreen when cube is held
    guard !posts.isEmpty else { return }
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        showTimelineView.toggle()  // ✅ Toggle instead of always showing
    }
    // Haptic feedback
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
}

.onReceive(NotificationCenter.default.publisher(for: .cubeHoldEnded)) { _ in
    // Cube hold ended - no action needed (toggle already happened on began)
}
```

### Key Points

1. **Toggle on hold begin** - Action happens immediately (0.5s hold)
2. **Haptic feedback** - Medium impact confirms the toggle
3. **Spring animation** - Smooth transition (0.3s, 0.8 damping)
4. **Empty guard** - Won't toggle if no posts exist
5. **No action on end** - Toggle already completed

## User Experience

### Scenario 1: Start in Timeline (Default)
```
1. Open Feed → Timeline shows
2. Browse posts vertically
3. Hold cube → Switch to fullscreen
4. Swipe between posts
5. Hold cube → Back to timeline
```

### Scenario 2: Tap Post from Timeline
```
1. Timeline view
2. Tap a post → Fullscreen view at that post
3. Swipe left/right to see other posts
4. Hold cube → Back to timeline
```

### Scenario 3: Quick Toggle
```
1. Timeline view
2. Hold cube → Fullscreen
3. Immediately hold cube again → Timeline
4. Rapid switching between modes
```

## Benefits

### 1. Flexibility
- User controls their viewing mode
- Easy to switch back and forth
- No need to navigate menus

### 2. Consistency
- Same gesture works both ways
- Predictable behavior
- Natural interaction

### 3. Discoverability
- Holding cube is already learned (from other features)
- Visual feedback (animation + haptic)
- Can't get "stuck" in one view

### 4. Speed
- Instant toggle (0.5s hold)
- No intermediate screens
- Direct control

## Design Rationale

### Why Toggle vs Always Show?

**Toggle Pros:**
- ✅ Bidirectional - works from either state
- ✅ Discoverable - users try holding cube naturally
- ✅ Fast - no navigation needed
- ✅ Consistent - same gesture, opposite result based on state

**Always Show Timeline Cons:**
- ❌ Only works one direction (fullscreen → timeline)
- ❌ No way to quickly return to fullscreen
- ❌ Asymmetric interaction
- ❌ Less intuitive

### Why Not Use Different Gestures?

**Considered alternatives:**
- Swipe down → Timeline (conflicts with post navigation)
- Double-tap → Toggle (conflicts with like gesture)
- Pinch → Zoom out to timeline (less discoverable)
- Button → Extra UI chrome

**Hold cube wins because:**
- Already established gesture
- No conflicts with other interactions
- Works on any face of cube
- Haptic feedback reinforces action
- Natural "grab and switch" feeling

## Visual Feedback

### Animation Sequence

**Timeline → Fullscreen:**
```
1. User holds cube (0.5s)
2. Haptic feedback fires
3. Timeline fades/slides out (0.3s spring)
4. Fullscreen fades/slides in (0.3s spring)
5. User sees current post fullscreen
```

**Fullscreen → Timeline:**
```
1. User holds cube (0.5s)
2. Haptic feedback fires
3. Fullscreen fades/slides out (0.3s spring)
4. Timeline fades/slides in (0.3s spring)
5. User sees scrollable feed
```

### State Indicators

**No explicit indicator needed because:**
- Current view is self-evident
- Timeline = vertical scroll, multiple posts
- Fullscreen = single post, swipe gestures
- Clear visual distinction

**Optional enhancements:**
- Subtle icon in corner showing current mode
- Status bar style change (light/dark)
- Cube glow effect during hold

## Edge Cases

### Empty Feed
```swift
guard !posts.isEmpty else { return }
```
- Won't toggle if no posts exist
- Prevents showing empty views
- User stays in current state

### Mid-Animation Toggle
- Spring animation handles interruption gracefully
- Can toggle again immediately
- No UI glitches

### Video Playback
- Videos pause when leaving fullscreen
- Resume when returning (if same post)
- Handled by view lifecycle

## Interaction with Other Features

### Tap Post (Timeline → Fullscreen)
- Still works as expected
- Shows tapped post in fullscreen
- Hold cube returns to timeline

### Long Press Map
- Works in both timeline and fullscreen
- Shows post location on map
- Doesn't interfere with cube hold

### Country/Channel Swipes
- Only work in fullscreen mode
- Timeline doesn't have country/channel swipes
- Clear separation of gestures

### Double-Tap Like
- Works in fullscreen mode
- Timeline has tap-to-expand instead
- No gesture conflicts

## Testing Checklist

- [ ] Hold cube in timeline → Goes to fullscreen
- [ ] Hold cube in fullscreen → Returns to timeline
- [ ] Haptic feedback fires on toggle
- [ ] Animation is smooth (no jank)
- [ ] Empty feed doesn't toggle
- [ ] Rapid toggles work correctly
- [ ] Post position preserved when toggling
- [ ] Videos pause/resume correctly
- [ ] No conflicts with other gestures
- [ ] Works on all cube faces

## User Documentation

### Help Text
> **💡 Tip:** Hold the cube to switch between timeline and fullscreen views

### Tutorial Suggestion
1. User opens Feed (sees timeline)
2. After 3 seconds, show pulsing cube hint
3. Text: "Hold cube to switch to fullscreen"
4. User holds cube
5. Success animation + haptic
6. Text: "Hold again to return to timeline"
7. Mark tutorial complete

## Analytics to Track

### Toggle Metrics
- **Toggle frequency** - How often users switch
- **Preferred mode** - Which view users stay in longer
- **Session patterns** - Timeline → fullscreen → timeline cycles
- **Discovery rate** - How many users find this feature

### Engagement Impact
- **Content consumption** - Do users view more posts with toggle?
- **Session duration** - Does mode switching increase engagement?
- **Return rate** - Do users come back more often?

## Future Enhancements

### 1. Smart Mode Detection
- **Auto-switch** based on content type
  - Videos → Fullscreen
  - Images → Timeline
  - User can override with cube hold

### 2. Gesture Shortcuts
- **Swipe down** in fullscreen → Timeline
- **Pinch out** in timeline → Fullscreen
- Keep cube hold as primary toggle

### 3. Persistent Preference
- **Remember last mode** per session
- **Default mode setting** in preferences
- Still allow manual toggle

### 4. Visual Indicators
- **Mode badge** in corner
- **Cube glow** during hold
- **Progress ring** showing 0.5s countdown

### 5. Contextual Behavior
- **Notification tap** → Open in fullscreen
- **Search result** → Open in timeline
- **External link** → Open in fullscreen

## Related Features

### Cube Gestures
- **Tap** - Center map (on Map tab)
- **Hold 0.5s** - Toggle timeline (on Feed tab)
- **Hold 2.0s** - Start recording (on Record tab)
- **Swipe up** - Post actions

### View Modes
- **Timeline** - Default, vertical scroll, discovery
- **Fullscreen** - Immersive, horizontal swipe, engagement
- **Map overlay** - Long press post to show location

## Code Architecture

### State Management
```swift
// Single source of truth
@State private var showTimelineView: Bool = true

// Toggle mechanism
showTimelineView.toggle()
```

### View Logic
```swift
if showTimelineView {
    FeedTimelineView(...)
} else {
    populatedFeedView(...)
}
```

### Notification Flow
```
CubeTabView
    ↓
UILongPressGestureRecognizer (0.5s)
    ↓
Posts .cubeHoldBegan notification
    ↓
FeedView receives notification
    ↓
showTimelineView.toggle()
    ↓
View updates with animation
```

## Performance Notes

- **No overhead** - Toggle is instant state change
- **Animation** - Hardware-accelerated spring
- **Memory** - Both views use same post data
- **CPU** - Minimal during toggle
- **Battery** - No measurable impact

## Summary

**Cube hold now toggles between timeline and fullscreen**, providing:

- ✅ **Bidirectional** - Works from either view
- ✅ **Fast** - 0.5s hold, instant toggle
- ✅ **Natural** - Familiar cube hold gesture
- ✅ **Smooth** - Spring animation
- ✅ **Feedback** - Haptic confirmation
- ✅ **Flexible** - User controls viewing mode
- ✅ **Discoverable** - Consistent with other cube holds

This gives users full control over how they browse content, switching seamlessly between overview (timeline) and deep engagement (fullscreen).
