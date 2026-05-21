# Fix "Cannot find type 'CameraViewController' in scope" Errors

## 🔴 Problem

You're seeing these errors in `CameraViewWithML.swift`:
```
error: Cannot find type 'CameraViewController' in scope
error: Type 'CameraViewWithML' does not conform to protocol 'UIViewControllerRepresentable'
```

## ✅ Root Cause

These files are in **different targets** or the **build order is wrong**:
- `CameraViewController.swift`
- `CameraViewWithML.swift`
- `SimplifiedMLDetection.swift`

Swift cannot see `CameraViewController` when compiling `CameraViewWithML.swift` because they're not in the same compilation unit.

## 🔧 Solution: Fix Target Membership in Xcode

### Step 1: Check Current Target Membership

#### For `CameraViewController.swift`:
1. Open **Project Navigator** (⌘1)
2. **Click** on `CameraViewController.swift`
3. Open **File Inspector** (⌥⌘1 or View → Inspectors → File Inspector)
4. Look at the **"Target Membership"** section
5. **Write down** which targets are checked (probably `Poplur2025`)

#### For `CameraViewWithML.swift`:
1. **Click** on `CameraViewWithML.swift` in Project Navigator
2. Open **File Inspector** (⌥⌘1)
3. Check the **"Target Membership"** section
4. **Write down** which targets are checked

#### For `SimplifiedMLDetection.swift`:
1. **Click** on `SimplifiedMLDetection.swift`
2. Open **File Inspector** (⌥⌘1)
3. Check **"Target Membership"**
4. **Write down** which targets are checked

---

### Step 2: Make All Three Files Use the Same Target

All three files **MUST** be in your main app target (`Poplur2025`).

#### For each file:
1. Select the file in Project Navigator
2. In File Inspector, under **"Target Membership"**:
   - ☑️ **Check** `Poplur2025` (your main app target)
   - ☐ **Uncheck** any other targets (like PreviewSupport, tests, etc.)

**After fixing, your Target Membership should look like:**
```
CameraViewController.swift:
  ☑ Poplur2025
  ☐ Poplur2025Tests
  ☐ PreviewSupport
  
CameraViewWithML.swift:
  ☑ Poplur2025
  ☐ Poplur2025Tests
  ☐ PreviewSupport
  
SimplifiedMLDetection.swift:
  ☑ Poplur2025
  ☐ Poplur2025Tests
  ☐ PreviewSupport
```

---

### Step 3: Clean and Rebuild

1. **Clean Build Folder**
   - Menu: Product → Clean Build Folder
   - Or: Press ⇧⌘K

2. **(Optional) Delete Derived Data**
   - Xcode → Settings (or Preferences)
   - **Locations** tab
   - Click the **→** arrow next to "Derived Data" path
   - Find your project folder
   - Move it to Trash
   - Close Xcode Settings

3. **Rebuild**
   - Menu: Product → Build
   - Or: Press ⌘B

4. **Verify Errors Are Gone**
   - Open `CameraViewWithML.swift`
   - Errors should be gone ✅

---

## 📋 Quick Verification Checklist

- [ ] `CameraViewController.swift` is in `Poplur2025` target
- [ ] `CameraViewWithML.swift` is in `Poplur2025` target  
- [ ] `SimplifiedMLDetection.swift` is in `Poplur2025` target
- [ ] All three files are in the **SAME** target
- [ ] No other targets are checked for these files
- [ ] Cleaned build folder (⇧⌘K)
- [ ] Rebuilt project (⌘B)
- [ ] Errors are gone ✅

---

## 🚫 Common Mistakes

### ❌ Files in Different Targets
**Problem:** `CameraViewController.swift` is in `Poplur2025` but `CameraViewWithML.swift` is in `PreviewSupport`

**Fix:** Put both in `Poplur2025`

---

### ❌ Files in Test Target
**Problem:** One of the files is checked for `Poplur2025Tests` only

**Fix:** Uncheck test target, check main app target

---

### ❌ Forgot to Clean Build
**Problem:** Fixed targets but didn't clean

**Fix:** Press ⇧⌘K to clean, then ⌘B to rebuild

---

## 🎯 Expected Result

After following these steps, you should be able to:

1. **Compile without errors** ✅
2. **Use CameraViewWithML in SwiftUI** ✅
3. **Enable ML detection** ✅

### Test with this code:

```swift
import SwiftUI

struct TestCameraView: View {
    var body: some View {
        CameraViewWithML(
            mlDetectionEnabled: true,
            confidenceThreshold: 0.2,
            frameSkipInterval: 5,
            maxResults: 3
        ) { objects in
            print("Detected: \(objects.map { $0.identifier }.joined(separator: ", "))")
        }
    }
}

#Preview {
    TestCameraView()
}
```

---

## 🆘 Still Not Working?

### Check Build Phases

If errors persist after fixing target membership:

1. Select **Poplur2025** target
2. Go to **Build Phases** tab
3. Expand **"Compile Sources"**
4. Verify all three files are listed:
   - `CameraViewController.swift`
   - `CameraViewWithML.swift`
   - `SimplifiedMLDetection.swift`

If any are missing:
- Click **+** button
- Add the missing file(s)
- Rebuild

---

### Check Import Statements

In `CameraViewWithML.swift`, verify these imports:
```swift
import SwiftUI
import AVFoundation
import UIKit
import SCSDKCameraKit
```

In `SimplifiedMLDetection.swift`, verify these imports:
```swift
import Foundation
import Vision
import AVFoundation
import UIKit
import SCSDKCameraKit
import ObjectiveC
```

---

### Still Stuck?

1. **Restart Xcode** (sometimes helps with indexing issues)
2. **Check for Xcode Updates** (old Xcode versions have bugs)
3. **Verify Swift Version** (should be Swift 5.x)
4. **Check Deployment Target** (iOS 15.0+ recommended)

---

## 📸 Visual Guide

### Target Membership Location:

```
┌─────────────────────────────────────┐
│  File Inspector                  ⓧ │
├─────────────────────────────────────┤
│  CameraViewWithML.swift             │
│  Type: Swift Source                 │
│  Location: Poplur2025/              │
│                                     │
│  ▼ Target Membership                │
│     ☑ Poplur2025          <------ ✅│
│     ☐ Poplur2025Tests               │
│     ☐ PreviewSupport                │
│                                     │
│  Text Settings                      │
│     Indent: 4 spaces                │
└─────────────────────────────────────┘
```

---

## ✨ Summary

**The fix is simple:**
1. Put all three files in `Poplur2025` target
2. Clean (⇧⌘K)
3. Build (⌘B)
4. Done! ✅

**This is not a code problem** - it's a project configuration issue that can only be fixed in Xcode's UI.

---

**Last Updated:** May 21, 2026
