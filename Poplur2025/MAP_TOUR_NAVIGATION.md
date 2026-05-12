# Map Tour Navigation from Feed/Profile Long-Press

## Feature Overview
When you **long-press on a post** in the Feed or Profile view, the app automatically switches to the Map tab and performs a **cinematic tour-style transition** to show exactly where that post was created.

## Implementation

### 1. User Interaction Flow

```
User long-presses on post
    ↓
Haptic feedback (medium impact)
    ↓
FeedView/ProfileView posts "ShowLocationOnMap" notification
    ↓
HomeView receives notification → switches to Map tab
    ↓
MapView receives notification → initiates tour transition
    ↓
Map performs cinematic tour:
  1. Zoom out from current location (1.5s)
  2. Pan to post location while zoomed out (3.0s)
  3. Zoom in to post location (2.0s)
    ↓
AI recommendation updates: "📍 This is where the post was created!"
```

### 2. Files Modified

#### **FeedView.swift** (Already implemented)
The long-press gesture is already set up on both the fullscreen post view and list/grid posts in ProfileView:

```swift
.onLongPressGesture(minimumDuration: 0.5) {
    if let post = posts[safe: currentIndex] {
        let coordinate = CLLocationCoordinate2D(
            latitude: post.latitude, 
            longitude: post.longitude
        )
        print("📍 [FeedView] Long press - showing post location on map: \(coordinate.latitude), \(coordinate.longitude)")
        NotificationCenter.default.post(
            name: Notification.Name("ShowLocationOnMap"),
            object: nil,
            userInfo: ["coordinate": coordinate]
        )
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
```

#### **MapView.swift** (Updated)
The notification handler now uses the tour transition mechanic instead of a simple animation:

**Before:**
```swift
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowLocationOnMap"))) { notification in
    guard let userInfo = notification.userInfo,
          let coordinate = userInfo["coordinate"] as? CLLocationCoordinate2D else { return }
    
    isTourActive = false
    
    // Simple animation (boring!)
    withAnimation(.easeInOut(duration: 1.2)) {
        camera = .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: 500,
                heading: 0,
                pitch: 60
            )
        )
    }
    
    aiRecommendation = "📍 Viewing post location"
}
```

**After:**
```swift
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowLocationOnMap"))) { notification in
    guard let userInfo = notification.userInfo,
          let coordinate = userInfo["coordinate"] as? CLLocationCoordinate2D else { return }
    
    print("📍 [MapView] Received ShowLocationOnMap notification - navigating with tour transition to: \(coordinate.latitude), \(coordinate.longitude)")
    
    // Switch to map tab first
    NotificationCenter.default.post(name: Notification.Name("SwitchToMapTab"), object: nil)
    
    // Use tour-style transition to navigate to the post location
    let locationName = "Post Location"
    navigateWithTourTransition(to: coordinate, cityName: locationName)
    
    // Update AI recommendation after tour completes
    Task { @MainActor in
        // Wait for tour transition to complete before updating text
        try? await Task.sleep(nanoseconds: 6_500_000_000) // 6.5s total
        aiRecommendation = "📍 This is where the post was created!"
    }
}
```

#### **HomeView.swift** (Updated)
Added notification handler to switch to map tab when requested:

```swift
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToMapTab"))) { _ in
    // Switch to map tab (used when long-pressing on post in feed/profile)
    print("🔄 [HomeView] Switching to map tab to show post location")
    selectedTab = .map
}
```

### 3. Tour Transition Mechanics

The `navigateWithTourTransition` function in MapView performs a **three-stage cinematic camera movement**:

#### Stage 1: Zoom Out (1.5 seconds)
```swift
withAnimation(.easeInOut(duration: 1.5)) {
    camera = .camera(
        MapCamera(
            centerCoordinate: currentCoord,      // Stay at current location
            distance: tourZoomOutDistance,       // Zoom way out (15,000m)
            heading: 0,                          // Reset heading
            pitch: 0                             // Top-down view
        )
    )
}
```

#### Stage 2: Pan While Zoomed Out (3.0 seconds)
```swift
Task { @MainActor in
    try? await Task.sleep(nanoseconds: 1_500_000_000)  // Wait for zoom out
    
    withAnimation(.easeInOut(duration: 3.0)) {
        camera = .camera(
            MapCamera(
                centerCoordinate: coordinate,     // Move to post location
                distance: tourZoomOutDistance,    // Stay zoomed out
                heading: 0,
                pitch: 0
            )
        )
    }
}
```

#### Stage 3: Zoom In (2.0 seconds)
```swift
Task { @MainActor in
    try? await Task.sleep(nanoseconds: 4_500_000_000)  // Wait for pan (1.5s + 3.0s)
    
    withAnimation(.easeInOut(duration: 2.0)) {
        camera = .camera(
            MapCamera(
                centerCoordinate: coordinate,     // Stay at post location
                distance: fixedDistanceAlt,       // Zoom back in (700m)
                heading: 0,
                pitch: fixedPitchAlt             // 60° viewing angle
            )
        )
    }
}
```

### 4. Configuration Values

These constants control the tour behavior (defined in MapView):

```swift
private let tourZoomOutDistance: CLLocationDistance = 15_000  // 15km altitude for "bird's eye" view
private let fixedDistanceAlt: CLLocationDistance = 700        // Normal viewing distance (700m)
private let fixedPitchAlt: CGFloat = 60                       // 3D viewing angle
```

## User Experience

### Visual Journey
1. **User is viewing feed** → sees interesting post
2. **User long-presses** → feels haptic feedback
3. **App switches to map tab** → shows current location
4. **Camera zooms out** → reveals broader geography (1.5s)
5. **Camera pans across map** → travels to post location while zoomed out (3.0s)
6. **Camera zooms in** → descends to post location with nice 3D angle (2.0s)
7. **AI recommendation updates** → "📍 This is where the post was created!"

### Total Duration
- **6.5 seconds** for complete tour transition
- Feels cinematic and intentional (not abrupt)
- Gives geographic context (zoomed-out pan shows distance traveled)

## Benefits Over Simple Animation

**Before (simple animation):**
- ❌ Just "cuts" to location with 1.2s animation
- ❌ No sense of geographic context or distance
- ❌ Feels abrupt and mechanical
- ❌ Doesn't leverage the beautiful map tour system

**After (tour transition):**
- ✅ Cinematic 3-stage camera movement
- ✅ Shows geographic relationship between current location and post
- ✅ Matches the existing tour aesthetic used throughout the map
- ✅ Creates a memorable, premium experience
- ✅ Makes long-press feel like a special action

## Testing

### Test Cases

1. **Long-press in Feed View**
   ```
   1. Open feed
   2. Long-press on any post
   3. Verify haptic feedback
   4. Verify app switches to map tab
   5. Verify camera zooms out → pans → zooms in
   6. Verify AI text updates to "📍 This is where the post was created!"
   ```

2. **Long-press in Profile View (Grid Mode)**
   ```
   1. Open profile
   2. Select grid mode
   3. Long-press on any grid post thumbnail
   4. Verify tour transition to post location
   ```

3. **Long-press in Profile View (List Mode)**
   ```
   1. Open profile
   2. Select list mode
   3. Long-press on any list card
   4. Verify tour transition to post location
   ```

4. **Long-press on Other User's Profile**
   ```
   1. Tap username in feed to view another user's profile
   2. Long-press on any of their posts
   3. Verify tour works correctly
   ```

5. **Multiple Sequential Long-Presses**
   ```
   1. Long-press on post A
   2. Wait for tour to complete
   3. Switch back to feed
   4. Long-press on post B (different location)
   5. Verify tour starts from post A location and pans to post B
   ```

6. **Long-press During Active Map Tour**
   ```
   1. Let map auto-tour play for a few seconds
   2. Switch to feed while tour is active
   3. Long-press on a post
   4. Verify:
      - Tour stops immediately
      - New tour starts from current camera position
      - Pans to post location smoothly
   ```

### Expected Console Output

```
📍 [FeedView] Long press - showing post location on map: 37.7749, -122.4194
📍 [MapView] Received ShowLocationOnMap notification - navigating with tour transition to: 37.7749, -122.4194
🔄 [HomeView] Switching to map tab to show post location
```

## Future Enhancements

### Potential Improvements
1. **Show post preview on map** - Display post thumbnail/video at the location marker
2. **Multiple posts clustering** - If multiple posts at similar location, show cluster marker
3. **Post trail visualization** - Draw path between multiple post locations for same user
4. **AR transition** - On supported devices, transition from map to AR view at post location
5. **Time-of-day lighting** - Adjust map lighting to match when post was created
6. **Distance indicator** - Show distance traveled during pan phase ("2.4 km traveled")

## Related Features

### Works With
- **Feed View** - Long-press on fullscreen post
- **Profile View** - Long-press on grid/list post thumbnails
- **Map Tour System** - Uses same `navigateWithTourTransition` function
- **AI Recommendations** - Updates context text to match post location

### Complements
- **Map Search** - Both use tour transitions for navigation
- **Favorite Locations** - Same cinematic camera movement
- **User Location** - "Center on User" also uses tour transition

## Code Reusability

The `navigateWithTourTransition` function is a **reusable component** that can be called from anywhere:

```swift
// Navigate to any coordinate with tour transition
navigateWithTourTransition(
    to: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
    cityName: "New York City"
)
```

**Current uses:**
1. Long-press on posts (Feed/Profile)
2. Search result selection (Map search overlay)
3. Favorite location selection
4. Center on user location
5. Custom navigation requests

This creates a **consistent navigation language** across the app! 🎉
