# Notification Name Ambiguity Fix

## Problem
The compiler was reporting ambiguous use of notification names like:
- `ResetTabToTop`
- `LoadFeedNow`
- `ShowUserProfile`

This was causing errors across multiple files including:
- `AppSettingsView.swift`
- `FeedView.swift`
- Other view files

## Root Cause
Notification names were being defined in **multiple locations**:
1. `Notifications+Names.swift` (centralized definitions)
2. `IsometricRadiusBar.swift` (duplicate definitions for radius bar notifications)

When Swift encountered multiple definitions of the same static property, it couldn't determine which one to use, leading to ambiguity errors.

## Solution
**Consolidated all notification definitions into a single file: `Notifications+Names.swift`**

### Changes Made

#### 1. Enhanced `Notifications+Names.swift`
- Made the extension `public` for better visibility across modules
- Added all radius bar notification names that were previously in `IsometricRadiusBar.swift`:
  - `currentPostRadiusDidChange`
  - `showCapturedPreviewRequested`
  - `capturePreviewDidDismiss`
  - `radiusBarGlobeTap`
  - `radiusBarHoldBegan`
  - `radiusBarHoldEnded`
  - `animateRadiusBarToValue`
- Organized with clear section markers for better maintainability

#### 2. Cleaned up `IsometricRadiusBar.swift`
- Removed all duplicate `extension Notification.Name` blocks
- Added a clear comment explaining that notification names are centralized
- The file now only imports what it needs and references centralized notifications

## Benefits
1. ✅ **No more ambiguity**: Each notification name is defined exactly once
2. ✅ **Better maintainability**: All notifications in one place
3. ✅ **Easier to find**: Developers know exactly where to look for notification names
4. ✅ **Prevents future issues**: Clear documentation discourages duplicate definitions

## Best Practices Going Forward
1. **Always check `Notifications+Names.swift` first** before creating a new notification
2. **Never define notifications inline** in view or controller files
3. **Use descriptive section markers** (MARK) to organize related notifications
4. **Document notification purposes** in comments when the usage isn't obvious

## Verification
The fix resolves all compilation errors related to:
- `error: Ambiguous use of 'ResetTabToTop'`
- `error: Ambiguous use of 'LoadFeedNow'`
- `error: Ambiguous use of 'ShowUserProfile'`
- `error: Invalid redeclaration of ...`

All files can now unambiguously reference notification names using `.ResetTabToTop`, `.LoadFeedNow`, etc.
