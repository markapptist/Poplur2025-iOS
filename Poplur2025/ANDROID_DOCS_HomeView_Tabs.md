# Home View Tab System Documentation
## For Android Recreation

---

## Overview
The app uses a custom tab navigation system with 4 main tabs represented by a 3D cube interface. Each tab has distinct functionality and visual characteristics.

---

## Tab Structure

### Available Tabs (AppTab enum)
The app has 4 primary tabs accessible via the cube:

1. **Map** (`.map`)
2. **Record/Camera** (`.record`)
3. **Feed** (`.feed`)
4. **Profile** (`.profile`)

There's also a **Settings** tab (`.settings`) but it's not currently accessible through normal navigation.

### Default Tab
- **Default starting tab**: Feed (`.feed`)
- On app launch, the user sees the Feed tab first

---

## Tab Navigation Methods

### 1. Cube Face Rotation
- Each tab is represented as a face on a 3D cube
- Users can **swipe horizontally** on the cube area to rotate between tabs
- The cube physically rotates to show the different faces

### 2. Tab Rotation Order
The tabs are arranged in a circular order:
- **Map → Record → Feed → Profile → (back to Map)**
- **Swipe left** (on cube): Advances to next tab (clockwise rotation)
- **Swipe right** (on cube): Goes to previous tab (counter-clockwise rotation)

### 3. Tab-to-Yaw Mapping
Each tab has a specific rotation angle (yaw) on the cube:
- **Record**: 0° (front face)
- **Feed**: 90° (right face)
- **Profile**: 180° (back face)
- **Map**: 270° (left face)

---

## Individual Tab Functionality

### 1. MAP TAB

#### Primary Purpose
Shows an interactive 3D map with AI recommendations for nearby places to post content.

#### Key Features
- **Map Style**: Hybrid (satellite + roads) with 3D building elevation
- **Camera Configuration**: 
  - 60° pitch angle
  - 700m altitude
  - Optimized for realistic perspective
- **AI Recommendations**: Overlay showing suggested places to create content
- **Navigation Controls**:
  - Places list
  - Address search functionality
- **User Location**: Automatically requests and centers on user's location

#### User Interactions
- **Pan**: Drag to explore the map
- **Zoom**: Pinch to zoom in/out
- **Long-press on map**: Opens camera tab with that coordinate set for posting
- **Tap cube**: Centers map on user's current location
- **Tab switching**: Location services are requested when first accessing this tab

#### Location Flow
When user long-presses on the map:
1. Notification `OpenCameraAtCoordinate` is posted with latitude/longitude
2. App switches to Record tab
3. Camera opens with coordinate pre-set for the post

#### Technical Implementation (`MapViewProduction`)
- Uses Apple MapKit with custom camera positioning
- Lazy loads: Map is not initialized until first access
- Audio handling: Pauses all feed audio when entering map

---

### 2. RECORD/CAMERA TAB

#### Primary Purpose
Capture photos and videos with ML object detection and AR filters.

#### Key Features
- **Live Camera Preview**: Full-screen camera feed
- **ML Object Detection**: Real-time detection of objects and faces
- **User Recognition**: Face detection to identify known users
- **AR Filters**: Beauty filters and effects (Snapchat-style)
- **Flash Control**: Swipe gestures to toggle flashlight
- **Camera Flip**: Double-tap to switch front/back camera

#### User Interactions

##### Capture Controls
- **Tap cube**: Take a photo
- **Hold cube (2 seconds)**: Start 10-second video recording
  - Recording continues even after release
  - Countdown timer shows remaining time
  - Cube flashes/glows during recording
  - Recording stops automatically after 10 seconds

##### Gesture Controls
- **Swipe up**: Turn flashlight ON
- **Swipe down**: Turn flashlight OFF
- **Double-tap anywhere**: Flip camera (front ↔ back)
- **Long-press anywhere (0.5s)**: Show AR filters menu

##### AR Filters
- Appears at bottom when long-press is detected
- Horizontal scrollable list of filters
- Includes: None, Beauty, Smooth, Bright effects
- Filters applied in real-time to camera feed

#### ML Detection Overlay
- **Top of screen**: Shows detected objects with confidence percentage
- **User Recognition**: When a known user's face is detected:
  - Shows their username
  - Displays their radius stat
  - Updates global radius display
- **Generic Objects**: Shows emoji icons for detected items (dog 🐕, car 🚗, food 🍔, etc.)

#### Camera Roll Button
- **Position**: Bottom-left corner
- **Function**: Opens photo picker to select existing media
- **Visibility**: Only shown when NOT recording

#### Recording Countdown UI
- **Position**: Bottom-left, slightly above camera roll button
- **Shows**: 
  - Seconds remaining (10, 9, 8...)
  - User's post count
  - Radius trend indicator (↑↓)
- **Visibility**: Only shown during active recording

#### Post Creation Flow
1. User captures photo/video or selects from camera roll
2. App shows map to select posting location
3. User long-presses on map to choose location
4. Upload begins with status indicator at top
5. On success, app switches to Profile tab to show new post

#### Technical Implementation
- Uses `CameraKitController` for camera management
- `MLDetectionManager` for object detection
- `UserRecognitionManager` for face recognition
- `ARFilterManager` for beauty filter effects
- Authorization requested on first interaction

---

### 3. FEED TAB

#### Primary Purpose
Infinite vertical scroll of video posts from different countries and categories.

#### Key Features
- **Two-dimensional feed**:
  - **Vertical swipe**: Change category/channel
  - **Horizontal swipe**: Change country
- **Video playback**: Auto-plays current video
- **Categories**: Food, Fitness, Beauty, Sports, Modelling, Fashion, Music, Tech, News
- **Countries**: 50+ countries available (US, Canada, Mexico, UK, France, Germany, Japan, etc.)

#### User Interactions
- **Vertical scroll**: Switch between posts in current country/category
- **Horizontal swipe**: Switch to different country feed
- **Tap username/avatar**: Navigate to that user's profile
- **Long-press on post**: Show post location on map
- **Tap cube**: Scroll to top of feed or perform feed-specific action
- **Like**: Double-tap or tap heart icon
- **Comment**: Tap comment button to open comment section

#### Feed Structure
Each post displays:
- Video/photo content (full screen)
- Username (tappable to view profile)
- Radius stat (distance from posting location)
- Like count
- Comment count
- Caption/description

#### Audio Management
- **Auto-play**: Current video plays automatically
- **Pause on tab switch**: Audio pauses when leaving Feed tab
- **Resume**: Audio resumes when returning to Feed
- **Global pause**: Notification system to coordinate with other tabs

#### Country/Channel Navigation
- **Country indicator**: Flag emoji + country name at top
- **Channel indicator**: Category emoji + name
- **Swipe left/right**: Cycle through countries
- **Swipe up/down**: Cycle through channels
- Each combination (country × channel) has its own feed

#### Timeline View (Instagram-style)
- Toggle between single-post and grid timeline view
- Shows all posts in chronological order
- Tap any post to return to full-screen view

#### Technical Implementation
- Lazy loading with pagination (5 posts per page)
- Firebase Firestore for data
- AVPlayer for video playback
- Location-based filtering by country code

---

### 4. PROFILE TAB

#### Primary Purpose
Display user's posts in a grid layout with statistics and profile information.

#### Key Features
- **Profile header**:
  - Profile picture (3D head scan if available)
  - Username
  - Email
  - Average radius stat
  - Post count
  - Edit button (own profile only)
- **Post grid**: 3-column grid of user's photos/videos
- **Post detail view**: Tap any post to see full screen

#### User Interactions
- **Tap profile picture**: View/scan 3D head model
- **Tap edit**: Open profile editing screen
- **Tap post**: Open expanded view with all post details
- **Long-press cube**: Trigger profile-specific actions
- **Tap cube**: Scroll to top or perform profile action
- **Message button**: Navigate to messaging (if viewing another user)

#### Profile Types
##### Own Profile
- Shows edit button
- Can update profile picture, username, email
- Can delete posts
- Shows settings access

##### Other User's Profile
- Reached by tapping username in Feed
- Shows message button instead of edit
- Can view their posts and stats
- Cannot edit their information

#### Post Grid
- **Layout**: 3 columns, square aspect ratio
- **Pagination**: Loads 18 posts at a time
- **Infinite scroll**: Loads more as user scrolls down
- **Video indicator**: Play button overlay on video posts
- **Statistics per post**:
  - Radius
  - View count
  - Like count

#### Expanded Post View
When tapping a post:
- Full-screen media display
- All post metadata (location, timestamp, radius)
- Like/comment counts
- Option to view location on map (long-press)
- Delete option (own posts only)

#### Profile Context from Feed
When navigating from Feed by tapping username:
- Profile shows with context of tapped post's radius
- Radius bar animates to match that post's radius
- Helps maintain context of where user was in the world

#### Technical Implementation
- Firebase Firestore for post data
- Firebase Storage for media files
- Lazy image loading with caching
- Pagination with QueryDocumentSnapshot cursors

---

## Radius Bar System

### Overview
A global radius display appears on all tabs in the bottom-right corner.

### Functionality
- **Display**: Shows current radius in km or miles (based on locale)
- **Updates**: Animates when radius changes
- **Context-aware**:
  - **Map tab**: Shows AI-suggested radius for current location
  - **Camera tab**: Grows while recording (0 → 3,323 km over 10 seconds)
  - **Feed tab**: Shows radius of currently viewed post
  - **Profile tab**: Shows average radius or specific post radius

### Visual Design
- Card-style badge with:
  - Radius value (formatted with separators: "1,234 km")
  - Unit label
  - Subtle background (material effect)
  - Drop shadow

### Maximum Radius
- **Earth's radius**: 6,371 km (3,958 mi)
- This is the theoretical maximum distance represented

---

## Upload Status System

### Location
Top of screen, below status bar

### States
1. **Uploading**: Blue arrow.up.circle.fill icon, "Uploading your post..."
2. **Success**: Green checkmark.circle.fill icon, "Post uploaded successfully!"
3. **Failed**: Red xmark.circle.fill icon, error message

### Animation
- Slides in from top with spring animation
- Auto-dismisses after 2-3 seconds
- Success state triggers profile refresh

---

## Camera Roll Button

### Location
Bottom-left corner, aligned with radius display height

### Functionality
- Opens system photo picker
- Allows selecting existing photos/videos
- Selected media goes through same posting flow as captured content
- Only visible when on Record tab and NOT recording

---

## Tab Switching Notifications

### Audio Coordination
The app uses notifications to coordinate audio playback:
- `PauseGlobalFeedAudio`: Pauses all feed audio
- `ResumeFeedAudio`: Resumes audio when returning to feed
- `RecordTabBecameActive`: Camera tab becomes active

### Tab-Specific Notifications
- `LoadMapNow`: Lazy-loads map when first accessed
- `LoadFeedNow`: Lazy-loads feed when first accessed
- `LoadProfileNow`: Lazy-loads profile when first accessed
- `ResetTabToTop`: Scrolls content to top when switching tabs

### Cross-Tab Navigation
- `ShowUserProfile`: Navigate to profile tab with specific user ID
- `ShowLocationOnMap`: Navigate to map tab with specific coordinate
- `SwitchToFeedTab`, `SwitchToProfileTab`, `SwitchToMapTab`: Direct tab switching

---

## Performance Optimizations

### Lazy Loading
- **Map**: Not initialized until first access
- **Feed**: Not loaded until first access
- **Profile**: Not loaded until first access
- **Camera**: Pre-warmed at app launch but not started

### Audio Session Management
- Only one tab can play audio at a time
- Automatic pause/resume when switching tabs
- Ambient audio mixing with system audio

### Memory Management
- Images cached per view
- Videos unloaded when off-screen
- ML detection only active when camera tab visible
- AR filters only loaded when requested

---

## Gesture Conflict Resolution

### Cube Gestures vs Tab Content
The cube area (bottom 230pt) has gesture priority:
- Swipe gestures on cube rotate tabs
- Content gestures (scroll, zoom) work above cube
- Long-press on cube triggers recording
- Tap on cube has tab-specific actions

### Camera Tab Gestures
Camera gestures work anywhere on screen:
- Double-tap to flip camera (highest priority)
- Swipe up/down for flash (conflicts resolved by direction)
- Long-press for AR filters (requires 0.5s hold)
- Pan gestures for ML detection overlay (passive, no conflict)

---

## State Persistence

### What Persists
- Selected tab (returns to Feed on next launch)
- User login state
- Profile information
- Post cache

### What Resets
- Camera state (stops on background)
- Map position (recenters on user)
- Feed scroll position (returns to top)
- Radius bar value (resets to 0 on tab switch, except Profile)

---

## Accessibility Considerations

### Haptic Feedback
- Tab switch: Light impact
- Recording start: Medium impact
- Recording end: Success notification
- Cube rotation: Rigid impact during swipe

### Visual Feedback
- Tab transitions: Animated with 0.45s ease curve
- Cube rotation: Smooth 3D rotation with overshoot bounce
- Upload status: Color-coded (blue/green/red)
- Recording countdown: Large numerals, high contrast

---

## Error Handling

### Camera Permissions
- Request on first interaction
- Show guidance if denied
- Graceful degradation without camera access

### Location Permissions
- Request when accessing Map tab
- App functional without location (uses default coordinates)
- Background location not required

### Network Errors
- Upload retry mechanism
- Cached content for offline viewing
- Clear error messages in upload status

---

## Android-Specific Implementation Notes

### UI Framework Mapping
- SwiftUI views → Jetpack Compose composables
- UIKit camera → CameraX
- SceneKit cube → OpenGL ES or Jetpack Compose 3D graphics
- AVFoundation → ExoPlayer for video

### Permission System
- Request CAMERA permission for camera tab
- Request ACCESS_FINE_LOCATION for map tab
- Request READ_EXTERNAL_STORAGE for camera roll

### Architecture Recommendations
- ViewModel for each tab
- Single Activity with Fragment/Composable tabs
- Navigation component for cross-tab navigation
- WorkManager for background uploads

### Firebase Integration
- Same Firestore database structure
- Same Storage bucket paths
- Same Authentication flow
- Ensure real-time listener cleanup on tab switch

---

## Testing Checklist

### Tab Navigation
- ✓ Swipe left/right rotates cube between tabs
- ✓ Cube shows correct face for each tab
- ✓ Tab content loads correctly on first access
- ✓ Returning to tab restores state (except Feed/Map)

### Camera Tab
- ✓ Tap cube takes photo
- ✓ Hold cube 2s starts video recording
- ✓ Recording continues after release
- ✓ 10-second countdown works
- ✓ Flash toggle with swipe up/down
- ✓ Camera flip with double-tap
- ✓ AR filters show on long-press
- ✓ ML detection shows objects
- ✓ Face recognition works

### Feed Tab
- ✓ Vertical scroll changes posts
- ✓ Horizontal swipe changes countries
- ✓ Video auto-plays
- ✓ Audio pauses on tab switch
- ✓ Tap username navigates to profile
- ✓ Long-press shows location on map

### Profile Tab
- ✓ Shows own profile by default
- ✓ Can navigate to other profiles
- ✓ Edit works on own profile
- ✓ Post grid loads with pagination
- ✓ Tap post shows expanded view
- ✓ Long-press on post shows location

### Map Tab
- ✓ Centers on user location
- ✓ Shows 3D buildings
- ✓ AI recommendations display
- ✓ Long-press sets coordinate for posting
- ✓ Tap cube recenters on user

### Radius Bar
- ✓ Displays on all tabs
- ✓ Updates smoothly with animation
- ✓ Shows correct context per tab
- ✓ Formatting matches locale (km/mi)

### Upload Flow
- ✓ Capture → Map → Select location → Upload → Profile
- ✓ Status indicator shows progress
- ✓ Success message appears
- ✓ New post appears in profile grid
- ✓ Error handling for failed uploads

---

## Design Assets Needed

### Cube Faces
- Icon images for each tab:
  - Map: `map.fill` (system icon)
  - Record: `video.circle.fill` (system icon)
  - Feed: `list.bullet.rectangle.portrait.fill` (system icon)
  - Profile: `person.circle.fill` (system icon)
- Each face needs text label below icon

### Cube Material
- Base tint color: Indigo (#5856D6)
- Normal map texture: `CubeNormalMap` asset
- Environment map: `CubeEnv` asset for reflections
- Chamfered corners: 0.25 units radius

### UI Elements
- Upload status icons (arrow.up, checkmark, xmark in circles)
- Camera roll icon (photos.fill)
- AR filter thumbnails
- ML detection emoji icons
- Country flag emoji set
- Category emoji icons

---

## API Endpoints & Data Models

### Post Model
```swift
struct Post {
    let id: String
    let userID: String
    let latitude: Double
    let longitude: Double
    let mediaURL: String
    let radius: Double
    let viewCount: Int
    let likeCount: Int
    let timestamp: Date
    let caption: String?
}
```

### User Profile Model
```swift
struct UserProfile {
    let userID: String
    var username: String
    var email: String
    var profilePictureURL: String?
    var headModelURL: String?
    var averageRadius: Double
}
```

### Firebase Collections
- `posts` - All user posts
- `users` - User profiles
- `likes` - Post likes
- `comments` - Post comments

---

## Summary

The app's tab system provides four distinct experiences:
1. **Map** - Explore and select posting locations with AI suggestions
2. **Record** - Capture content with ML detection and AR filters
3. **Feed** - Discover content by country and category
4. **Profile** - Manage and display user's content

All tabs are unified by:
- 3D cube navigation interface
- Global radius display system
- Consistent audio management
- Cross-tab navigation flows

The cube interface is the central interaction paradigm, replacing traditional tab bars with a physical 3D object that users can rotate, tap, and hold.
