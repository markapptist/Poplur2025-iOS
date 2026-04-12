# PreviewSupport Framework Setup Guide

## ✅ What We've Created

You now have a **PreviewSupport framework** with three files:

1. **PreviewModels.swift** - Core models (Auth, Camera, Tab, Location, etc.)
2. **PreviewViews.swift** - Reusable UI components  
3. **PreviewHarness.swift** - Main preview harness

## 📋 Step-by-Step Setup (20 minutes)

### Step 1: Create the Framework Target (5 min)

1. **File** → **New** → **Target...**
2. Select **Framework** (iOS)
3. Configure:
   - Product Name: `PreviewSupport`
   - Organization: (same as your app)
   - Language: Swift
   - Include Tests: ❌ Unchecked
4. Click **Finish**
5. Click **Activate** (or activate later from scheme selector)

---

### Step 2: Add the Framework Files (3 min)

The files I created need to be added to Xcode:

1. **Right-click** on your project in Navigator
2. Select **Add Files to "Poplur2025"...**
3. Navigate to your project folder
4. Select these files (I created them, but Xcode may not see them yet):
   - `PreviewSupport/PreviewModels.swift`
   - `PreviewSupport/PreviewViews.swift`  
   - `PreviewSupport/PreviewHarness.swift`

5. In the dialog:
   - **Add to targets:** Check **PreviewSupport** ONLY
   - **Create folder references:** Selected
   - Click **Add**

**Alternative:** Create the files manually in Xcode:

1. Select **PreviewSupport** group in Navigator
2. **File** → **New** → **File...**
3. Choose **Swift File**
4. Name it (PreviewModels, PreviewViews, or PreviewHarness)
5. **Target membership:** Check **PreviewSupport** only
6. Copy the code from the files I created

---

### Step 3: Configure PreviewSupport Target (5 min)

1. Select **PreviewSupport** target
2. **General** tab:
   - **Deployment Target:** Match your app (iOS 17.0+)
   - **Supported Destinations:** iPhone, iPad

3. **Build Settings** tab:
   - Search: **Skip Install** → Set to **YES**
   - Search: **Build Libraries for Distribution** → Set to **NO**
   - Search: **Build Active Architecture Only** → Set to **YES** for Debug

4. **Frameworks and Libraries** section:
   - Should be **empty** (no dependencies!)
   - This is critical - don't add Firebase, Google Maps, etc.

---

### Step 4: Link Framework to Main App (3 min)

1. Select **Poplur2025** target (your main app)
2. **General** tab → **Frameworks, Libraries, and Embedded Content**
3. Click **+**
4. Select **PreviewSupport.framework**
5. Set to **Do Not Embed**

**Why "Do Not Embed"?**  
- Framework is only for previews
- Doesn't need to be in your app bundle
- Reduces app size
- Faster build times

---

### Step 5: Update AppSimulationPreview.swift (2 min)

The file is already partially updated. Just verify it looks like this:

```swift
#if DEBUG

import SwiftUI
import PreviewSupport  // ← This line is key

#Preview("App Simulation - Framework") {
    LightweightPreviewHarness()  // ← From PreviewSupport
}

#Preview("App Simulation - Dark Mode") {
    LightweightPreviewHarness()
        .preferredColorScheme(.dark)
}

#endif
```

**Delete or comment out** all the old code below (all the duplicated types).

---

### Step 6: Build and Test (2 min)

1. **Build the PreviewSupport framework first:**
   - Select **PreviewSupport** scheme from scheme selector
   - Press **⌘B** to build
   - Should succeed with no errors

2. **Switch back to your app:**
   - Select **Poplur2025** scheme
   - Press **⌘B**

3. **Open Preview:**
   - Open `AppSimulationPreview.swift`
   - Click Resume Preview (or **⌘⌥P**)
   - Should load in **< 5 seconds**

---

## 🎯 Expected Results

### Before Framework:
- Preview timeout: 30+ seconds
- Modules linked: 76
- Status: ❌ Failed

### After Framework:
- Preview load time: **2-5 seconds** ✅
- Modules linked: **1-3**
- Status: ✅ Working

---

## 🔧 Troubleshooting

### "Cannot find 'PreviewSupport' in scope"

**Solution:**
1. Build PreviewSupport framework first (⌘B with PreviewSupport scheme)
2. Clean build folder (**Shift+⌘K**)
3. Rebuild main app

---

### "No such module 'PreviewSupport'"

**Solution:**
1. Verify PreviewSupport is in **Frameworks and Libraries** (Step 4)
2. Set to **Do Not Embed**
3. Clean and rebuild

---

### Preview still times out

**Solution:**
1. Verify PreviewSupport target has **NO heavy dependencies**
2. Check Build Settings → **Skip Install** = YES
3. Make sure files are in **PreviewSupport target only**

---

### Cannot find 'LightweightPreviewHarness'

**Solution:**
1. Make sure types are marked `public` in framework files
2. Check that `PreviewHarness.swift` is in PreviewSupport target
3. Rebuild framework

---

## 📁 Final Project Structure

```
Poplur2025/
├── Poplur2025/ (Main App Target)
│   ├── AppSimulationPreview.swift  ← Minimal, imports PreviewSupport
│   ├── ... (your app code)
│   └── (76 heavy dependencies linked here)
│
└── PreviewSupport/ (Framework Target - No Dependencies!)
    ├── PreviewModels.swift
    ├── PreviewViews.swift
    └── PreviewHarness.swift
```

---

## 🚀 Benefits Achieved

✅ **Fast Previews** - Load in seconds, not minutes  
✅ **Reusable** - Use across multiple preview files  
✅ **Clean Separation** - Preview code isolated from production  
✅ **No Pollution** - Heavy dependencies stay in main app  
✅ **Professional** - Industry-standard approach  
✅ **Scalable** - Easy to add more preview helpers

---

## 💡 Next Steps

### Create More Preview Files:

```swift
// AnyOtherPreview.swift
import SwiftUI
import PreviewSupport

#Preview {
    // Use any public type from PreviewSupport
    PreviewMapView(coordinate: (37.7749, -122.4194))
}
```

### Add More Helpers to Framework:

1. Create new files in PreviewSupport
2. Mark types as `public`
3. Import and use in any preview

---

## ✨ You're Done!

Your previews should now load instantly. Enjoy fast iteration! 🎉

---

**Questions?** Check `PREVIEW_SOLUTIONS.md` for alternative approaches.
