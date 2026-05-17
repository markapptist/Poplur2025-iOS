# How to Find Duplicate Notification Definitions

## The Problem
You're getting these errors:
```
error: Invalid redeclaration of 'LoadFeedNow'
error: Invalid redeclaration of 'ResetTabToTop'  
error: Invalid redeclaration of 'ShowUserProfile'
```

This means **these three notifications are defined in TWO places** in your project.

## Step 1: Use Xcode's Find Feature

1. Press **Cmd + Shift + F** (Find in Project)
2. Search for: `static let LoadFeedNow`
3. You should see **at least 2 results**:
   - ✅ One in `Notifications+Names.swift` (line 9) - **KEEP THIS ONE**
   - ❌ One in another file - **DELETE THAT ONE**

4. Repeat for `static let ResetTabToTop` and `static let ShowUserProfile`

## Step 2: Common Places to Check

The duplicate definitions are likely in one of these files:

### Check these files FIRST:
- `AppDelegate.swift`
- `SceneDelegate.swift`  
- `App.swift` (your main app file)
- Any file with "Notifications" in the name
- Any file with "Extensions" in the name
- `Constants.swift` or `Globals.swift`

### Also check:
- Files in a "Utilities" or "Helpers" folder
- Files in an "Extensions" folder
- Any file that was created early in the project

## Step 3: What to Look For

You're looking for code that looks like this:

```swift
extension Notification.Name {
    static let LoadFeedNow = Notification.Name("LoadFeedNow")
    static let ResetTabToTop = Notification.Name("ResetTabToTop")
    static let ShowUserProfile = Notification.Name("ShowUserProfile")
}
```

**DELETE the entire extension block** from any file that's NOT `Notifications+Names.swift`.

## Step 4: Alternative - Use Terminal

Run this command from your project root:

```bash
grep -rn "static let LoadFeedNow" . --include="*.swift"
```

This will show you EVERY file and line number where `LoadFeedNow` is defined.

Expected output:
```
./Notifications+Names.swift:9:    static let LoadFeedNow = Notification.Name("LoadFeedNow")
./SomeOtherFile.swift:42:    static let LoadFeedNow = Notification.Name("LoadFeedNow")  ← DELETE THIS
```

## Step 5: After Finding the Duplicate

Once you find the file with the duplicate:

1. **Delete the duplicate extension** from that file
2. **Add this import** at the top if it's not there:
   ```swift
   import Foundation
   ```
3. **Clean build folder**: Press **Shift + Cmd + K**
4. **Rebuild**: Press **Cmd + B**

## Still Getting Errors?

If you still see the errors after removing duplicates:

### Try this diagnostic approach:

1. **Temporarily comment out the duplicates** in `Notifications+Names.swift`:
   ```swift
   // static let LoadFeedNow = Notification.Name("LoadFeedNow")
   // static let ResetTabToTop = Notification.Name("ResetTabToTop")
   // static let ShowUserProfile = Notification.Name("ShowUserProfile")
   ```

2. **Build the project** (Cmd + B)

3. **Look at the new errors** - they will show you which files are trying to USE these notifications

4. **Follow the error back** to find where they're DEFINED

5. **Uncomment** the lines in `Notifications+Names.swift` after you find the duplicate

## Example of What You're Looking For

### ❌ BAD - File has duplicate definitions:

```swift
// In SomeRandomFile.swift
import Foundation

extension Notification.Name {
    static let LoadFeedNow = Notification.Name("LoadFeedNow")  // ← DELETE THIS
    static let ResetTabToTop = Notification.Name("ResetTabToTop")  // ← DELETE THIS
    static let ShowUserProfile = Notification.Name("ShowUserProfile")  // ← DELETE THIS
}

class MyViewController: UIViewController {
    // ... rest of file
}
```

### ✅ GOOD - File only USES the notifications:

```swift
// In SomeRandomFile.swift
import Foundation

class MyViewController: UIViewController {
    func someMethod() {
        NotificationCenter.default.post(name: .LoadFeedNow, object: nil)  // ✅ This is fine
    }
}
```

## Quick Fix Script

Save this as `find_duplicates.sh` and run it:

```bash
#!/bin/bash
echo "Searching for LoadFeedNow..."
grep -rn "static let LoadFeedNow" . --include="*.swift"
echo ""
echo "Searching for ResetTabToTop..."
grep -rn "static let ResetTabToTop" . --include="*.swift"
echo ""
echo "Searching for ShowUserProfile..."
grep -rn "static let ShowUserProfile" . --include="*.swift"
```

Run with:
```bash
chmod +x find_duplicates.sh
./find_duplicates.sh
```

## Most Likely Culprit

Based on common patterns, check if you have a file like:

- `Notification+Extensions.swift`
- `NotificationNames.swift` (without the +)
- `AppNotifications.swift`
- Early setup files from when the project started

These files often contain the duplicate definitions.
