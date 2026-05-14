# Troubleshooting: Post Location Map Feature

## How to Debug

### 1. **Enable Console Logging**
In Xcode, open the Console (⌘⇧C) to see debug output.

### 2. **Test the Feature**
1. Launch the app
2. Go to Feed tab
3. Long-press (0.5s) on any post
4. Watch console output

### 3. **Check Console Output**

You should see this sequence:

```
📍 [FeedView] Long press - showing post location: [lat], [lon]
   Username: [username], Profile URL: [url]
   Location: [city], [country] [flag]
   Radius: [radius]m
   
📍 [FeedView] Setting pending post location in MapStateManager

📍 [FeedView] Posting ShowLocationOnMap with coordinate: [lat], [lon]

🔄 [HomeView] Switching to map tab to show post location

🔔 [MapView] ShowLocationOnMap notification received!
✅ [MapView] ShowLocationOnMap: Using key -> coordinate (CLLocationCoordinate2D)
📍 [MapView] Received ShowLocationOnMap notification
   Target coordinate: [lat], [lon]
   Radius: [radius]m
   Username: [username]
   Location: [flag] [city], [country]
   
🔒 [MapView] Set 15-second lock/suppression windows IMMEDIATELY

💾 [MapView] Stored post location state:
   shownPostCoordinate: Optional([coordinate])
   shownPostRadius: Optional([radius])
   shownPostUsername: Optional("[username]")
   shownPostCityName: Optional("[city]")
   shownPostCountryName: Optional("[country]")
   shownPostCountryFlag: Optional("[flag]")
   
📸 [MapView] Camera snapped to target coordinate immediately

🎯 [navigateWithTourTransition] Starting transition
   Target: [lat], [lon]
   City: Post Location
   Post radius: [radius]m
   
🔍 [Step 1] Zooming out from current location (0.8s)
🚶 [Step 2] Panning to target location (1.5s)
🔎 [Step 3] Zooming in to target location (1.2s)
📏 [Step 4] Updating radius display to [radius]m

✅ [navigateWithTourTransition] Animation sequence complete

🟣 [MapView] Radius circle rendered: [radius]m at [lat], [lon]

📋 [MapView] Annotation card rendered with:
   Username: [username]
   Coordinates: [lat], [lon]
   City: [city]
   Country: [country]
   Flag: [flag]
   Radius: [radius]
```

## Common Issues

### ❌ Issue 1: Camera doesn't center on pin

**Symptoms:**
- Map shows user location instead of post location
- Pin appears off-screen

**Possible Causes:**
1. Lock windows not being set
2. User location update overriding camera
3. Tour mode interfering

**Check Console For:**
```
🔒 [MapView] Set 15-second lock/suppression windows IMMEDIATELY
⛔️ [MapView] CenterMapOnUser ignored during lockToPost window
```

**If you see:**
```
⛔️ [MapView] handleOnAppear ignored during lockToPost window
```
This is GOOD - it means locks are working.

**Fix:**
Ensure this appears in logs:
```
suppressUserCenteringUntil = Date().addingTimeInterval(15)
lockToPostUntil = Date().addingTimeInterval(15)
```

---

### ❌ Issue 2: Annotation callout not showing

**Symptoms:**
- Pin appears but no information card
- Only see purple dot, no text

**Possible Causes:**
1. `shownPostCoordinate` is nil
2. State not being set
3. View not re-rendering

**Check Console For:**
```
💾 [MapView] Stored post location state:
   shownPostCoordinate: Optional([coordinate])  ← Should NOT be nil
```

**If you see:**
```
shownPostCoordinate: nil
```

**Fix:**
Check that notification handler is running:
```swift
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowLocationOnMap")))
```

---

### ❌ Issue 3: Radius circle not visible

**Symptoms:**
- Pin shows but no purple circle
- Annotation appears but radius is missing

**Possible Causes:**
1. `shownPostRadius` is nil or 0
2. Radius too small/large to see at current zoom
3. Circle rendering before map is ready

**Check Console For:**
```
🟣 [MapView] Radius circle rendered: [radius]m at [lat], [lon]
```

**If this doesn't appear:**
Check for:
```
💾 [MapView] Stored post location state:
   shownPostRadius: Optional([radius])  ← Should have a value
```

**If radius is nil:**
Verify FeedView is passing radius in notification:
```swift
userInfo["radius"] = Double(post.radius)
```

---

### ❌ Issue 4: Missing city/country/flag

**Symptoms:**
- Annotation shows but no location info
- Only username and coordinates

**Possible Causes:**
1. Post doesn't have `cityName`, `countryName`, `countryFlag` set
2. Values not being passed in notification
3. Demo data generator not including location

**Check Console For:**
```
📍 [FeedView] Posting ShowLocationOnMap with coordinate: [lat], [lon]
   Location: [flag] [city], [country]  ← Should show actual values
```

**If location is missing:**
```
   Location: [city], [country]  ← No flag
```

**Fix:**
Ensure posts have location metadata:
```swift
let post = FeedPost(
    id: id,
    latitude: latitude,
    longitude: longitude,
    mediaURL: mediaURL,
    radius: radius,
    viewCount: viewCount,
    userID: userID,
    cityName: "Tokyo",          ← Must be set
    countryName: "Japan",       ← Must be set
    countryFlag: "🇯🇵"           ← Must be set
)
```

---

### ❌ Issue 5: Back button doesn't work

**Symptoms:**
- Button shows but tap does nothing
- Tap not responding

**Possible Causes:**
1. Button has `allowsHitTesting(false)`
2. Gesture conflict
3. Button not in correct view hierarchy

**Check Console For:**
```
📱 [MapView] Back to Feed tapped - clearing post location
```

**If this doesn't appear when tapping:**
Button tap is not being received.

**Fix:**
Ensure button has:
```swift
.buttonStyle(.plain)  ← Needed for custom button styling
```

And is NOT inside a view with:
```swift
.allowsHitTesting(false)
```

---

### ❌ Issue 6: Annotation card not rendering

**Symptoms:**
- No visual elements at all
- Pin location empty

**Check Console For:**
```
📋 [MapView] Annotation card rendered with:
```

**If this doesn't appear:**
Annotation view is not being created.

**Verify:**
1. `shownPostCoordinate` is not nil
2. MapView is using correct annotation syntax:
```swift
Annotation(shownPostUsername ?? "Post Location", coordinate: coord) {
    // VStack content
}
```

---

## Debugging Steps

### Step 1: Verify Notification is Posted
Add breakpoint or check console in `FeedView.swift`:
```swift
print("📍 [FeedView] Posting ShowLocationOnMap")
NotificationCenter.default.post(
    name: Notification.Name("ShowLocationOnMap"),
    object: nil,
    userInfo: userInfo
)
```

### Step 2: Verify Notification is Received
Check console for:
```
🔔 [MapView] ShowLocationOnMap notification received!
```

If NOT received:
- Notification name mismatch
- MapView not subscribed
- Notification posted before MapView loaded (should use pending location)

### Step 3: Verify State is Set
Check console for:
```
💾 [MapView] Stored post location state:
```

All values should be populated (except optional ones).

### Step 4: Verify Annotation Renders
Check console for:
```
📋 [MapView] Annotation card rendered with:
```

### Step 5: Verify Camera Navigation
Check console for navigation sequence:
```
🔍 [Step 1] Zooming out...
🚶 [Step 2] Panning...
🔎 [Step 3] Zooming in...
✅ Animation sequence complete
```

---

## Manual Test Checklist

- [ ] Long-press on post triggers haptic feedback
- [ ] Console shows notification posted
- [ ] Console shows notification received
- [ ] Map tab becomes active
- [ ] Camera animates smoothly (zoom out → pan → zoom in)
- [ ] Purple pin appears at coordinate
- [ ] Purple radius circle visible
- [ ] Annotation card appears above pin
- [ ] Username displayed
- [ ] Coordinates displayed (formatted)
- [ ] City and country displayed
- [ ] Flag emoji displayed
- [ ] Radius displayed (formatted as m or km)
- [ ] "Back to Feed" button visible
- [ ] Tapping button returns to feed
- [ ] Post location state clears after returning

---

## Quick Fixes

### Reset State
If stuck in bad state, add this to clear:
```swift
// In MapView
shownPostCoordinate = nil
shownPostRadius = nil
shownPostUsername = nil
shownPostCityName = nil
shownPostCountryName = nil
shownPostCountryFlag = nil
```

### Force Refresh
Rebuild and run:
```bash
# Clean build folder
⌘⇧K

# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData

# Rebuild
⌘B
```

### Check Xcode Version
Ensure using Xcode 15+ for latest SwiftUI features:
- `Annotation` API requires iOS 17+
- `MapCircle` requires iOS 17+

---

## Need More Help?

Please provide:
1. **Console output** from the moment you long-press
2. **Screenshot** of what you see on screen
3. **Xcode version** you're using
4. **iOS version** (device or simulator)
5. **Specific behavior** - what happens vs. what you expect

---

## Expected Console Output (Full Sequence)

```
📍 [FeedView] Long press - showing post location: 35.6762, 139.6503
   Username: food_user_0, Profile URL: nil
   Location: Tokyo, Japan 🇯🇵
   Radius: 500m
📍 [FeedView] Setting pending post location in MapStateManager
🗺️ [MapState] Setting pending post location: 35.6762, 139.6503
   Post radius: 500m
   Location: Tokyo, Japan
📍 [FeedView] Posting ShowLocationOnMap with coordinate: 35.6762, 139.6503
🔄 [HomeView] Switching to map tab to show post location
🔔 [MapView] ShowLocationOnMap notification received!
✅ [MapView] ShowLocationOnMap: Using key -> coordinate (CLLocationCoordinate2D)
📍 [MapView] Received ShowLocationOnMap notification
   Target coordinate: 35.6762, 139.6503
   Radius: 500m
   Username: food_user_0
   Location: 🇯🇵 Tokyo, Japan
   Current camera: 37.7749, -122.4194
   Tour active: false
🔒 [MapView] Set 15-second lock/suppression windows IMMEDIATELY
   Lock expires at: 2025-05-14 20:15:45 +0000
   Suppression expires at: 2025-05-14 20:15:45 +0000
🗺️ [MapState] Mode changed: browsing → showingPostLocation(coordinate: CLLocationCoordinate2D)
💾 [MapView] Stored post location state:
   shownPostCoordinate: Optional(CLLocationCoordinate2D(latitude: 35.676200000000003, longitude: 139.6503))
   shownPostRadius: Optional(500.0)
   shownPostUsername: Optional("food_user_0")
   shownPostCityName: Optional("Tokyo")
   shownPostCountryName: Optional("Japan")
   shownPostCountryFlag: Optional("🇯🇵")
📸 [MapView] Camera snapped to target coordinate immediately
🎯 [navigateWithTourTransition] Starting transition
   Target: 35.6762, 139.6503
   City: Post Location
   Post radius: 500.0m
   Current camera: 35.6762, 139.6503
   Zoom out distance: 100000.0m
🔍 [Step 1] Zooming out from current location (0.8s)
🚶 [Step 2] Panning to target location (1.5s)
🔎 [Step 3] Zooming in to target location (1.2s)
📏 [Step 4] Updating radius display to 500m
✅ [navigateWithTourTransition] Animation sequence complete
🟣 [MapView] Radius circle rendered: 500m at 35.6762, 139.6503
📋 [MapView] Annotation card rendered with:
   Username: food_user_0
   Coordinates: 35.6762, 139.6503
   City: Tokyo
   Country: Japan
   Flag: 🇯🇵
   Radius: 500.0
```

If your console output differs significantly from this, that's your clue to what's wrong!
