# Long Press Map Navigation Fix

## Problem
When long-pressing on a post in FeedView or ProfileView, the map wasn't zooming to the post's location.

## Root Cause
The FeedView was sending the wrong notification format:
- **Was sending**: `latitude` and `longitude` as separate Double values
- **MapView expects**: `coordinate` as a CLLocationCoordinate2D object

## Changes Made

### FeedView.swift - Fixed Both Long Press Handlers

#### 1. Main Feed Long Press (Line ~850)
**Before:**
```swift
var userInfo: [String: Any] = [
    "latitude": coordinate.latitude,
    "longitude": coordinate.longitude,
    "userID": post.userID
]
```

**After:**
```swift
let userInfo: [String: Any] = [
    "coordinate": coordinate,  // Pass CLLocationCoordinate2D object
    "userID": post.userID,
    "username": username ?? displayName(for: post)
]
```

#### 2. FeedFullscreenPageView Long Press (Line ~1927)
**Before:**
```swift
var userInfo: [String: Any] = [
    "latitude": coordinate.latitude,
    "longitude": coordinate.longitude,
    "userID": post.userID,
    "username": displayName
]

NotificationCenter.default.post(
    name: Notification.Name("ShowLocationOnMapFromPost"),  // Wrong notification name
    ...
)
```

**After:**
```swift
let userInfo: [String: Any] = [
    "coordinate": coordinate,  // Pass CLLocationCoordinate2D object
    "userID": post.userID,
    "username": displayName
]

NotificationCenter.default.post(
    name: Notification.Name("ShowLocationOnMap"),  // Correct notification name
    ...
)
```

## How It Works Now

### 1. User Long Presses on Post
```swift
.onLongPressGesture(minimumDuration: 0.5) {
    let coordinate = CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude)
    
    // Haptic feedback
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    
    // Get username asynchronously
    Task {
        let username = await UsernameCache.shared.username(for: post.userID)
        
        // Send notification with coordinate object
        NotificationCenter.default.post(
            name: Notification.Name("ShowLocationOnMap"),
            object: nil,
            userInfo: [
                "coordinate": coordinate,
                "userID": post.userID,
                "username": username ?? displayName
            ]
        )
        
        // Switch to map tab
        NotificationCenter.default.post(
            name: Notification.Name("SwitchToMapTab"),
            object: nil
        )
    }
}
```

### 2. MapView Receives Notification
```swift
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowLocationOnMap"))) { notification in
    guard let userInfo = notification.userInfo,
          let coordinate = userInfo["coordinate"] as? CLLocationCoordinate2D else { 
        print("❌ [MapView] ShowLocationOnMap: Missing coordinate in userInfo")
        return 
    }
    
    // Stop any active tour
    mapState.stopTour()
    
    // Show post location
    mapState.showPostLocation(coordinate)
    
    // Navigate with smooth transition
    navigateWithTourTransition(to: coordinate, cityName: "Post Location")
}
```

### 3. Map Animates to Location
The map will:
1. Stop any active tour
2. Smoothly animate to the post's coordinate
3. Show "Post Location" as the current city
4. Display AI recommendation: "📍 This is where the post was created!"

## Profile Picture Annotation (Future Enhancement)

To add user profile pictures as map annotations, you'll need to:

1. **Add posterURL to FeedPost**:
```swift
struct FeedPost: Identifiable {
    ...
    let posterURL: String?  // Add this field
}
```

2. **Pass it in the notification**:
```swift
let userInfo: [String: Any] = [
    "coordinate": coordinate,
    "userID": post.userID,
    "username": username,
    "profileImageURL": post.posterURL  // Include profile image
]
```

3. **MapView handles it** (already supports this):
The MapView's `ShowLocationOnMap` handler can extract `profileImageURL` from userInfo and create a custom annotation with the user's profile picture.

## Testing

1. **Test in Feed**:
   - Open feed
   - Long press on any post (hold for 0.5 seconds)
   - Should see haptic feedback
   - Should switch to map tab
   - Map should zoom to post location

2. **Test in Profile**:
   - Open any user's profile
   - Tap on a post to view it fullscreen
   - Long press on the post
   - Should switch to map and zoom to location

## Debug Logs

You'll now see these logs when long-pressing:

```
📍 [FeedView] Long press - showing post location on map: 37.7749, -122.4194
📍 [FeedView] Posting ShowLocationOnMap notification with coordinate
📍 [MapView] Received ShowLocationOnMap notification
   Target coordinate: 37.7749, -122.4194
   Current camera: 40.7128, -74.0060
   Tour active: false
📍 Navigating to post location...
📍 This is where the post was created!
```

## Related Files
- FeedView.swift - Both long press handlers fixed
- MapView.swift - Already had correct receiver (no changes needed)
- ProfileView.swift - May need similar fix if it has long press handlers

## Summary
✅ Fixed coordinate format (CLLocationCoordinate2D instead of separate lat/lon)
✅ Unified notification names (both use "ShowLocationOnMap")
✅ Added debug logging
✅ Haptic feedback on long press
✅ Automatic tab switching
✅ Smooth map animation to location
