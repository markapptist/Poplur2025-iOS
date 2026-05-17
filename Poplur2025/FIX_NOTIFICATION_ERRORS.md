# Fix for "Invalid redeclaration" Notification Errors

## The Errors
```
error: Invalid redeclaration of 'LoadFeedNow'
error: Invalid redeclaration of 'ResetTabToTop'  
error: Invalid redeclaration of 'ShowUserProfile'
```

## Root Cause
These errors typically occur when:
1. **Build cache is stale** - Xcode hasn't recognized that duplicate definitions were removed
2. **Multiple files define the same notifications** - Check for hidden or generated files
3. **Module visibility conflicts** - Using `public` can sometimes cause issues across targets

## Solution Steps

### Step 1: Clean Build Folder
**In Xcode:**
1. Go to **Product** menu → **Clean Build Folder** (Shift + Cmd + K)
2. Or hold **Option** key → **Product** → **Clean Build Folder**

### Step 2: Clear Derived Data
**In Xcode:**
1. Go to **Window** → **Organizer** → **Derived Data** tab
2. Find your project and click **Delete**

**Or via command line:**
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
```

### Step 3: Verify No Duplicate Definitions Exist

Search your entire project for these patterns:
```bash
# In Terminal, from your project root:
grep -r "static let LoadFeedNow" . --include="*.swift"
grep -r "static let ResetTabToTop" . --include="*.swift"  
grep -r "static let ShowUserProfile" . --include="*.swift"
```

**Expected result:** Each notification should appear **exactly twice**:
- Once in `Notifications+Names.swift` (definition)
- Once or more in other files (usage)

**If you find extra definitions:**
- Remove them from those files
- Reference `Notifications+Names.swift` instead

### Step 4: Check for Hidden Issues

Look for:
- **Objective-C bridging headers** that might define these
- **Swift files in different targets** (app, tests, extensions)
- **Generated code** from tools like SwiftGen or Sourcery
- **Package dependencies** that might export similar names

### Step 5: Rebuild
1. Clean the build folder again (**Shift + Cmd + K**)
2. Build the project (**Cmd + B**)

## Files That Were Updated

✅ **Notifications+Names.swift**
- Changed from `public extension` to `extension` 
- All notifications defined in one place
- Added radius bar notifications

✅ **IsometricRadiusBar.swift**  
- Removed all duplicate `extension Notification.Name` blocks
- Now references centralized definitions

## If Errors Persist

If you still see errors after cleaning:

### Option 1: Check for Multiple Notification Files
Look for files like:
- `NotificationNames.swift` (without the +)
- `AppNotifications.swift`
- `Notification+Extensions.swift`  
- Any file with `Notification.Name` extensions

### Option 2: Verify Target Membership
1. Select `Notifications+Names.swift` in Xcode
2. Open **File Inspector** (Cmd + Option + 1)
3. Under **Target Membership**, ensure it's only in your main app target
4. Uncheck test targets or extension targets if checked

### Option 3: Use Explicit File References
In files that reference these notifications, try adding an explicit import:
```swift
import Foundation  // Ensures Notification.Name is available
```

### Option 4: Last Resort - Rename the File
Sometimes Xcode gets confused about file identities:
1. Rename `Notifications+Names.swift` to `NotificationDefinitions.swift`
2. Clean and rebuild
3. This forces Xcode to re-index everything

## Prevention

To avoid this in the future:
1. ✅ **Only define notifications in `Notifications+Names.swift`**
2. ✅ **Mark the file clearly with "DO NOT DUPLICATE" comments**
3. ✅ **Use grep/search before adding new notification names**
4. ✅ **Code review checklist: Check for notification duplicates**

## Quick Reference: All Notification Names

These are defined in `Notifications+Names.swift` and should ONLY be referenced elsewhere:

### Loading
- `LoadFeedNow`, `LoadMapNow`, `LoadProfileNow`

### Navigation  
- `ResetTabToTop`, `RecordTabBecameActive`, `ShowUserProfile`

### Cube
- `CubeMotionUpdate`, `CubeGlobalDragChanged`, `CubeGlobalDragEnded`
- `CubeGlobalTap`, `cubeHoldBegan`, `cubeHoldEnded`
- `cameraCubeHoldBegan`, `cameraCubeHoldEnded`, `cameraCubeTabViewTapped`
- `CubeStartFlashing`, `CubeStopFlashing`, `CenterMapOnUser`

### Feed & Audio
- `FeedReady`, `PauseFeedAudio`, `ResumeFeedAudio`, `PauseGlobalFeedAudio`

### Map & Location
- `CenterMapOnUserLocation`, `SharedRadiusDidChange`, `MapSuggestedRadius`

### Settings & UI
- `OpenSettingsRequested`, `OpenDMsRequested`

### Stats
- `UserPostCountDidChange`

### Camera
- `CameraRollImageSelected`, `CameraRollVideoSelected`

### Radius Bar
- `currentPostRadiusDidChange`, `showCapturedPreviewRequested`
- `capturePreviewDidDismiss`, `radiusBarGlobeTap`
- `radiusBarHoldBegan`, `radiusBarHoldEnded`, `animateRadiusBarToValue`
