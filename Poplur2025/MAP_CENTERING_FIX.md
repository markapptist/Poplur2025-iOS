# Fix for Map Always Centering on Current Location

## Problem
When long-pressing on a post in the feed/profile to view its location on the map, the map would immediately snap back to the user's current location instead of staying on the post's location.

## Root Causes (Updated After Testing)

### **CRITICAL: ProfileView Timing Issue** ⚠️
- **ProfileView was sending both notifications simultaneously** (no delay)
- `ShowLocationOnMap` and `SwitchToMapTab` fired at the exact same time
- When the tab switched, MapView wasn't ready to receive `ShowLocationOnMap`
- Result: MapView never received the coordinate, so it centered on user location by default

### 1. **Lock Duration Too Short**
- The `SwitchToMapTab` notification was setting a 6-second lock (now 10s)
- The `ShowLocationOnMap` notification was setting an 8-second lock (now 15s)
- The tour-style navigation animation takes ~6.5 seconds to complete
- By the time the animation finished, the lock had already expired!

### 2. **Tab Switch Overwrites Lock**
- When switching to the map tab, `SwitchToMapTab` would unconditionally set new lock windows
- This would overwrite the longer locks set by `ShowLocationOnMap`
- Need to preserve existing locks if they're still active

### 3. **onAppear Resets Camera**
- When the map view appears (e.g., when switching to map tab), `handleOnAppear()` would reset the camera
- This would center on the current camera position (which was still at user's location) before the `ShowLocationOnMap` notification was fully processed
- `handleOnAppear()` was not respecting the lock windows

## Solutions Implemented

### **1. Fixed ProfileView Notification Timing** ✨ (MOST IMPORTANT)
```swift
// ProfileView.swift - Grid & List long-press handlers

// BEFORE (BROKEN):
NotificationCenter.default.post(name: Notification.Name("ShowLocationOnMap"), ...)
NotificationCenter.default.post(name: Notification.Name("SwitchToMapTab"), ...)
// Both fired at same time - race condition!

// AFTER (FIXED):
// First, send location to map
NotificationCenter.default.post(name: Notification.Name("ShowLocationOnMap"), ...)

// Wait for map to process location before switching tabs
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
    NotificationCenter.default.post(name: Notification.Name("SwitchToMapTab"), ...)
}
```

### 2. Increased Lock Duration in ShowLocationOnMap Handler
```swift
// MapView.swift - ShowLocationOnMap handler
// Set locks FIRST before any other operations
suppressUserCenteringUntil = Date().addingTimeInterval(15)  // Increased from 12s
lockToPostUntil = Date().addingTimeInterval(15)  // Increased from 12s
hasSetInitialLocation = true
```
- Increased from 12 seconds to 15 seconds
- Provides plenty of buffer for the 6.5-second animation sequence plus navigation overhead
- **Locks are set BEFORE camera operations** to prevent race conditions

### 3. Smart Lock Preservation in SwitchToMapTab
```swift
// Only set suppression if not already set or if existing one has expired
if suppressUserCenteringUntil == nil || suppressUserCenteringUntil! < Date() {
    suppressUserCenteringUntil = Date().addingTimeInterval(10)
} else {
    print("🗺️ Keeping existing suppression window")
}
```
- Now checks if a lock is already active before overwriting
- Preserves the longer 12-second lock from `ShowLocationOnMap`
- Only sets new 10-second lock if no lock exists or existing one has expired

### 3. Respect Lock in handleOnAppear
```swift
private func handleOnAppear() {
    // Respect the lock - don't reset camera when navigating to a post location
    if let until = lockToPostUntil, until > Date() {
        print("⛔️ handleOnAppear ignored during lockToPost window")
        return
    }
    
    // Also don't reset if we're showing a post location
    if shownPostLocation != nil {
        print("⛔️ handleOnAppear ignored - showing post location")
        return
    }
    
    // ... rest of function
}
```
- Added two safety checks before resetting camera
- First checks the time-based lock
- Second checks if we're actively showing a post location (state-based lock)

## Flow Timeline (Fixed)

### When User Long-Presses Post in Feed:

**T+0.00s**: User long-presses
- Feed sends `ShowLocationOnMap` notification
- Map receives notification and:
  - Sets `lockToPostUntil` = now + 12s
  - Sets `suppressUserCenteringUntil` = now + 12s
  - Stores post location, username, profile image
  - Immediately snaps camera to target (no animation)
  - Starts tour-style transition

**T+0.15s**: Feed sends `SwitchToMapTab` notification
- Map receives notification and:
  - Checks existing locks (both active, expiring at T+12s)
  - **Preserves existing locks** instead of overwriting
  - Stops any active tour

**T+0.15s**: HomeView switches to map tab
- Map view's `onAppear` fires
- `handleOnAppear()` is called
- Checks lock (active until T+12s) → **SKIPS camera reset**
- Checks `shownPostLocation` (set to post coordinate) → **SKIPS camera reset**

**T+1.65s**: Zoom-out animation completes (1.5s duration)

**T+4.65s**: Pan animation completes (3.0s duration)

**T+6.65s**: Zoom-in animation completes (2.0s duration)
- **Camera now showing post location with user profile pin**
- Locks still active for another 5.35 seconds

**T+7.00s**: AI text updates to show post creator's name

**T+12.00s**: Locks expire
- User is free to navigate, locks won't interfere anymore

## Key Improvements

✅ **Lock duration covers full animation** (12s > 6.5s + overhead)  
✅ **Tab switching preserves locks** (doesn't overwrite active locks)  
✅ **onAppear respects locks** (won't reset camera during navigation)  
✅ **State-based safety** (checks `shownPostLocation` as backup)  
✅ **Better logging** for debugging timing issues

## Testing Checklist

- [x] Long-press on feed post → navigates to post location
- [x] Long-press on profile post (grid) → navigates to post location  
- [x] Long-press on profile post (list) → navigates to post location
- [x] Animation completes without interruption
- [x] Profile picture pin shows at post location
- [x] Username displays correctly
- [x] Centering on user location still works (after lock expires)
- [x] Locks don't interfere with normal navigation after expiry

## Files Modified

- `MapView.swift`:
  - Increased lock duration in `ShowLocationOnMap` handler (8s → 12s)
  - Smart lock preservation in `SwitchToMapTab` handler
  - Added lock checks in `handleOnAppear()`
  - Added state-based check for `shownPostLocation`
