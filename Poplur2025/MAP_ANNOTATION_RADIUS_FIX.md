# Map Annotation & Radius Display Fix

## Issues Fixed

### 1. ✅ Annotation Not Showing
**Problem**: When navigating to a post location, the pin and radius circle weren't displaying on the map.

**Root Cause**: The `clearPendingPostLocation()` was being called BEFORE the display values (`shownPostCoordinate`, `shownPostRadius`, `shownPostUsername`) were set, causing them to be nil.

**Solution**: 
- Store pending values in local variables FIRST
- Clear the pending location
- THEN set the display values from the local variables

**Changed in MapView.swift**:
- `handleOnAppear()` - Fixed order of operations
- `SwitchToMapTab` receiver - Fixed order of operations  
- `ShowLocationOnMap` receiver - Now extracts and uses radius from notification

### 2. ✅ Radius Staying at 0
**Problem**: The radius bar showed 0 even when posts had valid radii.

**Root Cause**: 
1. ProfileView wasn't passing the radius value when setting pending post location
2. The notification `ShowLocationOnMap` didn't include radius in userInfo
3. MapView wasn't extracting or using the radius value

**Solution**:
- Updated ProfileView (both grid and list modes) to include `radius: Double(post.radius)` in:
  - `MapStateManager.shared.setPendingPostLocation()` call
  - `ShowLocationOnMap` notification userInfo
- Updated MapView to extract and use radius from notification
- Added debug logging to track radius values

**Changed in ProfileView.swift**:
```swift
// Grid mode long-press
MapStateManager.shared.setPendingPostLocation(
    coordinate,
    userID: post.userID,
    username: displayUsername,
    profileImageURL: profileURL,
    radius: Double(post.radius)  // ✅ NOW INCLUDED
)

var userInfo: [String: Any] = [
    "coordinate": coordinate,
    "userID": post.userID,
    "radius": Double(post.radius)  // ✅ NOW INCLUDED
]
```

**Changed in MapView.swift**:
```swift
// Extract radius from notification
let postRadius = userInfo["radius"] as? Double

// Pass radius to navigation function
navigateWithTourTransition(to: coordinate, cityName: "Post Location", postRadius: postRadius)

// Set display values AFTER clearing pending
shownPostCoordinate = postCoord
shownPostRadius = postRadius  // ✅ NOW SET
shownPostUsername = postUsername
```

### 3. ⚠️ Posts All From Same Location
**Problem**: All posts appear to come from the same two cities (SF and NY).

**Root Cause**: You're using **preview stub data** defined in `MapViewStubs.swift`:

```swift
func demoDominanceCities() -> [CityDominance] {
    return [
        CityDominance(city: "San Francisco", ...),
        CityDominance(city: "New York", ...)
    ]
}
```

**Solution Options**:

**Option A - Use Real Firebase Data (Recommended)**:
Replace the stub initialization in `MapViewProduction.init()`:
```swift
init() {
    // OLD: Using stubs
    // _dominance = State(initialValue: demoDominanceCities())
    
    // NEW: Load from Firebase
    _dominance = State(initialValue: [])
    // Then load real data in .onAppear or .task
}
```

Add a method to fetch real posts from Firestore:
```swift
private func loadPostsFromFirebase() async {
    // Query your "posts" collection
    // Group by location
    // Create annotations for each post
}
```

**Option B - Add More Diverse Demo Data**:
If you want to keep using stubs for development, add more cities:
```swift
init() {
    _dominance = State(initialValue: [
        PreviewCityDominance(city: "Tokyo", coordinate: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503), profileURL: nil),
        PreviewCityDominance(city: "London", coordinate: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278), profileURL: nil),
        PreviewCityDominance(city: "Paris", coordinate: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), profileURL: nil),
        PreviewCityDominance(city: "Sydney", coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093), profileURL: nil),
        PreviewCityDominance(city: "Dubai", coordinate: CLLocationCoordinate2D(latitude: 25.2048, longitude: 55.2708), profileURL: nil),
        PreviewCityDominance(city: "São Paulo", coordinate: CLLocationCoordinate2D(latitude: -23.5505, longitude: -46.6333), profileURL: nil),
        // ... existing SF and NY
    ])
}
```

**Option C - Fetch from Existing Feed Data**:
Reuse the post data that's already loaded in FeedView:
```swift
.onReceive(NotificationCenter.default.publisher(for: .PostsLoaded)) { notification in
    if let posts = notification.userInfo?["posts"] as? [Post] {
        // Convert to map annotations
        self.posts = posts.map { post in
            PreviewMapAnnotationPost(
                title: post.username ?? "User",
                coordinate: CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude),
                radius: CLLocationDistance(post.radius)
            )
        }
    }
}
```

## Testing the Fixes

1. **Test Annotation Display**:
   - Long-press any post in ProfileView
   - Switch to Map tab
   - ✅ Should see purple pin at post location
   - ✅ Should see purple radius circle around pin

2. **Test Radius Display**:
   - Check console logs for: `"📏 [MapView] Showing post with radius: XXXm"`
   - ✅ Radius bar should animate to match post's actual radius
   - ✅ AI text should show username

3. **Test Multiple Locations**:
   - Navigate to different posts with different locations
   - ✅ Map should fly to each unique coordinate
   - ✅ Each post should show its own radius

## Debug Logging Added

Look for these console messages:
```
📍 [ProfileView] Post radius: XXXm
📏 [MapView] Showing post with radius: XXXm
🔒 [MapView] Set 15-second locks for pending navigation
📸 [MapView] Camera snapped to pending coordinate
```

## Next Steps

To get scattered posts around the world:
1. Check your Firebase `posts` collection
2. Verify posts have diverse lat/lon coordinates
3. Implement real data loading (Option A above)
4. Or temporarily add diverse demo data (Option B)

---

## Additional Improvements (Latest Updates)

### ✅ Pin Visibility During Zoom Animation
**Problem**: Pin only appeared after zoom animation completed.

**Solution**: Pin now displays at the **start** of the zoom transition and remains visible throughout the entire 3.5-second animation sequence.

- ✅ Pin appears immediately when navigating to post
- ✅ Visible during zoom-out (0.8s)
- ✅ Visible during pan (1.5s)  
- ✅ Visible during zoom-in (1.2s)

See `PIN_AND_PARTICLE_FIX.md` for technical details.

### ✅ Cube Particle Effects Disabled
**Problem**: Particle effects on cube navigation button.

**Solution**: Completely disabled particle system on navigation cube.

- ✅ No more glowing particles around cube
- ✅ Cleaner visual appearance
- ✅ Potentially better performance

Original code preserved in comments for easy re-enabling if needed.
