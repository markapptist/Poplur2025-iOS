# Development Assets - Preview Optimization

## Problem
SwiftUI Previews timeout when trying to link 76+ modules including:
- Firebase (Auth, Firestore, Database, Storage)
- Google Maps 3D
- Snap Camera Kit  
- Google Mobile Ads
- And many other heavy frameworks

## Solution
This directory contains preview-only files that are:
1. **NOT** included in any build target
2. Only used by Xcode Previews
3. Compiled independently without linking main app dependencies

## How to Use

### Step 1: Move AppSimulationPreview.swift here
1. Drag `AppSimulationPreview.swift` into this `DevelopmentAssets` folder
2. When prompted, choose "Create folder references" (yellow folder, not blue)
3. In the dialog, **UNCHECK** "Add to targets"

### Step 2: Verify Target Membership
1. Select `AppSimulationPreview.swift`
2. Open File Inspector (⌥⌘1)
3. Under "Target Membership", ensure **nothing** is checked
4. The file should show "No target membership"

### Step 3: Use Previews
- Previews will load in ~2-3 seconds instead of timing out
- The file won't be included in your app binary
- You can still develop and test UI components

## Alternative: Keep in Main Target

If you want to keep the file in your main target:

1. Remove ALL imports except `SwiftUI` and `UIKit`
2. Don't reference any types from your main app module
3. Use only Foundation/SwiftUI types
4. Accept that it will still link some dependencies

## Why This Works

Files without target membership are compiled by Xcode's preview system in isolation.
They don't trigger the full dependency graph resolution that causes 30+ second timeouts.
