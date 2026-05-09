# Capture Flow Guide

This document explains the two different post capture flows in the Poplur app and how they're implemented.

## Overview

The app supports two distinct capture flows, managed by the `CaptureFlowManager` enum and observable class:

1. **Map → Camera Flow**: User selects a location first, then captures media to post there
2. **Camera → Map Flow**: User captures media first, then selects where to post it

## Flow 1: Map → Camera → Post

### User Journey
1. User opens Map tab
2. User taps a coordinate on the map
3. AI text shows: "📍 37.7749°, -122.4194° — Want to post here?"
4. "Post Here" button appears with camera icon
5. User taps "Post Here"
6. App switches to Camera tab with preselected coordinate
7. User captures photo/video
8. Preview overlay shows the capture
9. User confirms in preview
10. **Post automatically uploads to the preselected coordinate**
11. User sees success message
12. App returns to Profile tab

### Implementation Details

**MapView.swift:**
- User taps coordinate → `clickedCoordinate` is set
- "Post Here" button calls `flowManager.startMapToCameraFlow(coordinate: coordinate)`
- Posts `OpenCameraAtCoordinate` notification with coordinate
- Button shows camera icon

**CaptureFlowManager.swift:**
- `currentFlow` is set to `.mapToCamera(coordinate: CLLocationCoordinate2D)`
- Stores the preselected coordinate

**HomeView.swift:**
- Receives `OpenCameraAtCoordinate` notification
- Switches to `.record` tab
- Camera opens with coordinate pre-set

**Camera/Preview:**
- User captures media
- Posts `CaptureComplete` notification with image/video

**MapView.swift (notification handler):**
- Receives `CaptureComplete` notification
- Checks if `flow.isMapFirst` is true
- Gets `preselectedCoordinate` from flow
- Stores captured media in flow manager
- Calls `flowManager.completeFlow(finalCoordinate: preselectedCoordinate)`
- **Automatically uploads without requiring map interaction**

**CaptureFlowManager.swift:**
- `completeFlow()` posts `UploadPostToCoordinate` notification
- Resets flow state

**HomeView.swift:**
- Receives `UploadPostToCoordinate`
- Handles upload through CameraKitController
- Switches to Profile tab

---

## Flow 2: Camera → Map → Post

### User Journey
1. User opens Camera tab (or is already there)
2. User captures photo/video
3. Preview overlay shows the capture
4. User confirms but needs to select location
5. App switches to Map tab
6. AI text shows: "Select Post Location" / "Tap where you want to post your capture"
7. User taps a coordinate on the map
8. AI text shows: "📍 37.7749°, -122.4194° — Post your capture here?"
9. "Confirm & Post" button appears with checkmark icon
10. User taps "Confirm & Post"
11. **Post uploads to the selected coordinate**
12. App shows success message
13. App returns to Feed tab

### Implementation Details

**Camera/Preview:**
- User captures media
- User confirms in preview
- Posts `OpenMapToSelectPostLocation` notification with image/video in userInfo

**HomeView.swift:**
- Receives `OpenMapToSelectPostLocation` notification
- Switches to `.map` tab
- Forwards notification to MapView

**MapView.swift:**
- Receives `OpenMapToSelectPostLocation` notification
- Calls `flowManager.startCameraToMapFlow(image: image, videoURL: videoURL)`
- Updates AI text to "Select Post Location"
- Shows X button to cancel

**CaptureFlowManager.swift:**
- `currentFlow` is set to `.cameraToMap`
- Stores captured image/video

**MapView.swift (user interaction):**
- User taps coordinate → `clickedCoordinate` is set
- AI text updates with coordinate and "Post your capture here?"
- "Confirm & Post" button appears with checkmark icon

**MapView.swift ("Confirm & Post" button):**
- Detects `flow.isCameraFirst` is true
- Calls `flowManager.completeFlow(finalCoordinate: coordinate)`
- Shows success message
- Posts `SwitchToFeedTab` notification after delay

**CaptureFlowManager.swift:**
- `completeFlow()` posts `UploadPostToCoordinate` notification with stored media
- Resets flow state

**HomeView.swift:**
- Receives `UploadPostToCoordinate`
- Handles upload through CameraKitController
- Later receives `SwitchToFeedTab` and switches to Feed tab

---

## Key Components

### CaptureFlowManager.swift

**Enum:**
```swift
enum CaptureFlow {
    case mapToCamera(coordinate: CLLocationCoordinate2D)
    case cameraToMap
}
```

**Properties:**
- `isMapFirst: Bool` - True if Flow 1 (Map → Camera)
- `isCameraFirst: Bool` - True if Flow 2 (Camera → Map)
- `preselectedCoordinate: CLLocationCoordinate2D?` - Only populated in Flow 1

**Observable Class:**
```swift
class CaptureFlowManager: ObservableObject {
    @Published var currentFlow: CaptureFlow?
    @Published var capturedImage: UIImage?
    @Published var capturedVideoURL: URL?
}
```

**Methods:**
- `startMapToCameraFlow(coordinate:)` - Initiates Flow 1
- `startCameraToMapFlow(image:videoURL:)` - Initiates Flow 2
- `completeFlow(finalCoordinate:)` - Finalizes upload and resets state
- `cancelFlow()` - Cancels current flow

### Visual Indicators

**Map Marker Icons:**
- Flow 1 (Map → Camera): Blue camera icon
- Flow 2 (Camera → Map): Blue checkmark icon

**Button Text:**
- Flow 1: "Post Here" with camera icon
- Flow 2: "Confirm & Post" with checkmark icon

**AI Text:**
- Flow 1 after coordinate selection: "Want to post here?"
- Flow 2 when entering map: "Tap where you want to post your capture"
- Flow 2 after coordinate selection: "Post your capture here?"

### Notifications

**Used in Both Flows:**
- `UploadPostToCoordinate` - Triggers actual upload with coordinate and media

**Flow 1 Specific:**
- `OpenCameraAtCoordinate` - Opens camera with preselected coordinate
- `CaptureComplete` - Signals capture is done (auto-uploads in Flow 1)

**Flow 2 Specific:**
- `OpenMapToSelectPostLocation` - Opens map in location selection mode
- `SwitchToFeedTab` - Returns user to feed after successful upload

---

## Benefits of This Design

1. **Single Source of Truth**: `CaptureFlowManager.shared` tracks flow state globally
2. **Clear Separation**: Enum makes it impossible to have ambiguous state
3. **Minimal Views**: Reuses existing MapView and Camera without duplication
4. **User-Friendly**: Different flows for different use cases:
   - Explore-first users (Map → Camera)
   - Capture-first users (Camera → Map)
5. **Visual Clarity**: Icons and text adapt to current flow
6. **Easy to Extend**: Adding new flows just requires new enum cases
7. **Testable**: Flow logic is centralized and can be unit tested

---

## State Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                       IDLE STATE                            │
│                    (No active flow)                         │
└──────────────┬─────────────────────────┬───────────────────┘
               │                          │
               │ User taps                │ User captures
               │ coordinate               │ in camera
               │ on map                   │
               ↓                          ↓
┌──────────────────────────┐  ┌──────────────────────────┐
│   FLOW 1: Map→Camera     │  │   FLOW 2: Camera→Map     │
│                          │  │                          │
│ 1. Coordinate stored     │  │ 1. Media stored          │
│ 2. Switch to camera      │  │ 2. Switch to map         │
│ 3. Capture media         │  │ 3. Select coordinate     │
│ 4. AUTO-UPLOAD           │  │ 4. User confirms         │
│ 5. Return to profile     │  │ 5. Upload                │
│                          │  │ 6. Return to feed        │
└──────────────┬───────────┘  └─────────────┬────────────┘
               │                            │
               │ Upload complete            │ Upload complete
               │                            │
               ↓                            ↓
┌─────────────────────────────────────────────────────────────┐
│                       IDLE STATE                            │
│                    (Flow reset)                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Error Handling

**Flow Cancellation:**
- User can tap X button in map to cancel Camera → Map flow
- Tapping cube button also clears any active prompts
- Canceling resets `CaptureFlowManager` state

**Edge Cases:**
- If capture completes but no coordinate selected: Media stored in flow manager, waits for selection
- If user switches tabs mid-flow: Flow state preserved until completion or cancellation
- If upload fails: Error handled by CameraKitController, flow still resets

---

## Testing the Flows

### Testing Flow 1 (Map → Camera)
1. Open app to Map tab
2. Tap any coordinate
3. Verify "📍 lat, lon — Want to post here?" appears
4. Verify "Post Here" button with camera icon appears
5. Tap "Post Here"
6. Verify switch to Camera tab
7. Capture photo/video
8. Verify auto-upload without map interaction
9. Verify return to Profile tab

### Testing Flow 2 (Camera → Map)
1. Open app to Camera tab
2. Capture photo/video
3. In preview, trigger map selection
4. Verify switch to Map tab
5. Verify "Select Post Location" title
6. Verify X button appears
7. Tap any coordinate
8. Verify "📍 lat, lon — Post your capture here?" appears
9. Verify "Confirm & Post" button with checkmark appears
10. Tap "Confirm & Post"
11. Verify upload
12. Verify return to Feed tab

---

## Future Enhancements

Possible additions to the flow system:

1. **Batch Posting**: Select multiple photos, then pick locations for each
2. **Saved Locations**: Quick-select from favorite posting spots
3. **Radius Selection**: Let user adjust post radius during flow
4. **Preview Before Upload**: Show map preview of how post will appear
5. **Offline Queue**: Store flow state if offline, complete when online
6. **Flow Analytics**: Track which flow users prefer
