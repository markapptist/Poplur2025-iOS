# IMMEDIATE FIX: Duplicate Notification Errors

## TL;DR - Quick Fix

**The errors you're seeing mean these notifications are defined in TWO files.**

Run this in Terminal from your project folder:

```bash
grep -rn "static let LoadFeedNow\|static let ResetTabToTop\|static let ShowUserProfile" . --include="*.swift"
```

You'll see output like:
```
./Notifications+Names.swift:9:    static let LoadFeedNow
./Notifications+Names.swift:14:    static let ResetTabToTop  
./Notifications+Names.swift:16:    static let ShowUserProfile
./SomeOtherFile.swift:42:    static let LoadFeedNow        ← DELETE FROM THIS FILE
./SomeOtherFile.swift:43:    static let ResetTabToTop      ← DELETE FROM THIS FILE
./SomeOtherFile.swift:44:    static let ShowUserProfile    ← DELETE FROM THIS FILE
```

**Delete the duplicate definitions from any file that ISN'T `Notifications+Names.swift`.**

## In Xcode (Visual Method)

1. Press **Cmd + Shift + F** (Find in Workspace)
2. Type: `static let LoadFeedNow`
3. You'll see 2+ results
4. One will be in `Notifications+Names.swift` (keep it)
5. The other will be in a different file (delete it)

## What to Delete

When you find the duplicate file, delete the ENTIRE extension block:

```swift
// DELETE THIS ENTIRE BLOCK from the duplicate file:
extension Notification.Name {
    static let LoadFeedNow = Notification.Name("LoadFeedNow")
    static let ResetTabToTop = Notification.Name("ResetTabToTop")
    static let ShowUserProfile = Notification.Name("ShowUserProfile")
    // ... possibly more
}
```

## After Deleting

1. Clean: **Shift + Cmd + K**
2. Delete derived data: **Cmd + Shift + K** (hold Option for Clean Build Folder)
3. Rebuild: **Cmd + B**

## Status

✅ `Notifications+Names.swift` is CORRECT - keep this file as-is
❌ Another file has duplicates - find and remove them

Your `Notifications+Names.swift` file is properly structured and has no internal duplicates. The compiler is complaining because it sees these same notifications defined in a DIFFERENT file somewhere in your project.
