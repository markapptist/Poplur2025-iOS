# Long-Press Post → Map Tour Transition (Visual Flow)

```
┌──────────────────────────────────────────────────────────────────────────┐
│ USER INTERACTION                                                         │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Feed or Profile View                                                   │
│  ┌────────────────────────────┐                                        │
│  │  ┌──────────────────────┐  │                                        │
│  │  │                      │  │                                        │
│  │  │    📸 Post Image     │  │                                        │
│  │  │                      │  │   ← User long-presses (0.5s)         │
│  │  └──────────────────────┘  │     ⚡ Haptic feedback triggered      │
│  │  User: FOOD USER 0         │                                        │
│  │  Location: 37.7749,-122.41 │                                        │
│  └────────────────────────────┘                                        │
│                 │                                                        │
│                 ▼                                                        │
│  NotificationCenter.post(                                               │
│    name: "ShowLocationOnMap",                                           │
│    userInfo: ["coordinate": CLLocationCoordinate2D(...)]                │
│  )                                                                       │
└──────────────────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ TAB SWITCHING (HomeView.swift)                                          │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  .onReceive(...for: "SwitchToMapTab") { _ in                           │
│      selectedTab = .map  ← Switches to map tab                         │
│  }                                                                       │
│                                                                          │
│  Current Tab: Feed   →   Target Tab: Map                               │
│  ┌─────┬─────┬─────┬─────┬─────┐                                      │
│  │ Map │Feed │Cam  │Prof │Set  │                                      │
│  │  ✓  │  ○  │  ○  │  ○  │  ○  │                                      │
│  └─────┴─────┴─────┴─────┴─────┘                                      │
└──────────────────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ CINEMATIC TOUR TRANSITION (MapView.swift)                               │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  navigateWithTourTransition(to: coordinate, cityName: "Post Location")  │
│                                                                          │
│  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓    │
│  ┃ STAGE 1: ZOOM OUT (1.5 seconds)                                ┃    │
│  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛    │
│                                                                          │
│   Current Location (Street Level)                                       │
│        ↓ Zoom Out                                                       │
│   🏙️                                                                    │
│     ╲                                                                   │
│      ╲  Camera rises to 15km altitude                                  │
│       ╲                                                                 │
│   🗺️  Bird's Eye View                                                 │
│        (Can see entire region)                                          │
│                                                                          │
│  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓    │
│  ┃ STAGE 2: PAN TO POST LOCATION (3.0 seconds)                    ┃    │
│  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛    │
│                                                                          │
│   🗺️ Current Location        →  →  →  →       📍 Post Location       │
│      (15km altitude)                              (15km altitude)        │
│                                                                          │
│   Camera smoothly pans across the map while staying zoomed out          │
│   User can see geographic relationship and distance                     │
│                                                                          │
│  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓    │
│  ┃ STAGE 3: ZOOM IN (2.0 seconds)                                 ┃    │
│  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛    │
│                                                                          │
│   📍 Post Location (Bird's Eye)                                         │
│        ↓ Zoom In                                                        │
│       ╱                                                                 │
│      ╱  Camera descends to 700m                                         │
│     ╱   with 60° pitch angle                                            │
│   🏙️                                                                    │
│   Post Location (Street Level + 3D View)                                │
│                                                                          │
│  Total Duration: 6.5 seconds (1.5s + 3.0s + 2.0s)                      │
│                                                                          │
│  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓    │
│  ┃ AI RECOMMENDATION UPDATE (after tour completes)                ┃    │
│  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛    │
│                                                                          │
│   Task { @MainActor in                                                  │
│       try? await Task.sleep(nanoseconds: 6_500_000_000)                │
│       aiRecommendation = "📍 This is where the post was created!"      │
│   }                                                                      │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ FINAL MAP VIEW                                                           │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │  AI: 📍 This is where the post was created!                   │    │
│  ├────────────────────────────────────────────────────────────────┤    │
│  │                                                                 │    │
│  │                    🗺️ MAP VIEW                                │    │
│  │                                                                 │    │
│  │              📍 Post Location Marker                           │    │
│  │         (37.7749, -122.4194)                                   │    │
│  │                                                                 │    │
│  │        [Zoomed in with 60° pitch]                              │    │
│  │        [700m altitude]                                          │    │
│  │        [Centered on post coordinates]                           │    │
│  │                                                                 │    │
│  │                                                                 │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  User can now:                                                          │
│  - See exactly where the post was created                               │
│  - Explore the surrounding area                                         │
│  - Understand geographic context                                        │
│  - View other nearby posts (if any)                                     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## Key Animation Parameters

| Stage | Duration | Camera Distance | Camera Pitch | Purpose |
|-------|----------|----------------|--------------|---------|
| **Zoom Out** | 1.5s | 700m → 15,000m | 60° → 0° | Reveal broader geography |
| **Pan** | 3.0s | 15,000m | 0° | Travel to post location |
| **Zoom In** | 2.0s | 15,000m → 700m | 0° → 60° | Descend to post location |
| **Text Update** | 0.0s | 700m | 60° | Update AI recommendation |

## Why This Feels Better Than Simple Animation

### Simple Animation (1.2s direct cut)
```
Current Location  ──────────►  Post Location
     (instant)                  (abrupt)
```
- ❌ No sense of distance
- ❌ No geographic context
- ❌ Feels mechanical
- ❌ Doesn't leverage the beautiful 3D map

### Tour Transition (6.5s cinematic journey)
```
Current Location
    ↓ (zoom out - 1.5s)
Bird's Eye View of Current Area
    → → → (pan - 3.0s) → → →
Bird's Eye View of Post Area
    ↓ (zoom in - 2.0s)
Post Location (Beautiful 3D View)
```
- ✅ Shows geographic relationship
- ✅ Reveals distance traveled
- ✅ Creates memorable experience
- ✅ Feels premium and intentional
- ✅ Makes long-press feel special

## Code Flow Summary

```swift
// 1. User long-presses on post
.onLongPressGesture(minimumDuration: 0.5) {
    let coordinate = CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude)
    NotificationCenter.default.post(
        name: Notification.Name("ShowLocationOnMap"),
        userInfo: ["coordinate": coordinate]
    )
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
}

// 2. HomeView switches to map tab
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToMapTab"))) { _ in
    selectedTab = .map
}

// 3. MapView performs cinematic tour (FIXED: async to avoid recursive lock)
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowLocationOnMap"))) { notification in
    guard let coordinate = notification.userInfo?["coordinate"] as? CLLocationCoordinate2D else { return }
    
    // CRITICAL: Wrap in Task to avoid recursive lock crash
    Task { @MainActor in
        // Post tab switch notification
        NotificationCenter.default.post(name: Notification.Name("SwitchToMapTab"), object: nil)
        
        // Wait for tab switch to complete
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        // Start cinematic tour
        self.navigateWithTourTransition(to: coordinate, cityName: "Post Location")
        
        // Wait for tour to complete
        try? await Task.sleep(nanoseconds: 6_500_000_000) // 6.5s
        
        // Update AI text
        self.aiRecommendation = "📍 This is where the post was created!"
    }
}
```

## Important Threading Fix

**🔴 Critical:** The MapView notification handler **must** wrap all operations in `Task { @MainActor in ... }` to avoid a **recursive lock crash**.

**Why:** SwiftUI uses internal locks for view updates. If you post a notification that triggers view updates **while already handling a notification**, you'll try to acquire the same lock twice → crash.

**Solution:** The `Task` wrapper causes the notification handler to **return immediately**, releasing the lock. Then the Task executes on the **next event loop iteration** with a fresh lock acquisition.

See `RECURSIVE_LOCK_FIX.md` for detailed explanation.

Perfect implementation! 🎉
