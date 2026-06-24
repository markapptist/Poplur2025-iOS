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

### 4. Persistent Cube Visibility
- Keep the cube visible on every main-tab screen and every child screen opened from a main tab, including Feed TV Guide, Profile mail, settings, phone, notifications, store, scanner, and post detail routes.
- Child routes may hide secondary bottom chrome such as counters, upload status, radius bars, and volume bars, but they must not unmount or visually cover the cube.
- Render the cube from the root tab container as a persistent overlay with a higher z-order/elevation than tab content and child routes.
- Limit any expanded/invisible cube hit target to main tab content only so child route controls remain tappable; the visible cube itself remains interactive everywhere.

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

#### Map Launch Audio Contract
- The first Map launch has no visible AI voice/radio button. Narration is automatic only.
- Android should request natural speech audio from the same TTS backend/OpenAI speech endpoint used by iOS, with a warm human British presenter style. Keep Android `TextToSpeech(Locale.UK)` only as an offline fallback.
- Use a single audio coordinator with three channels: voice, weather ambience, and music. Do not let independent composables/services call `setVolume` or replace players during launch.
- Launch order: reveal/zoom map, fetch weather, fade weather ambience from 0 to its target, duck weather under the voice, play the Poplur voice once, then unduck weather and fade music from 0 to full.
- Resolve/cache the music source while the voice is playing. Do not start fallback music and then swap to another track; that creates the audible pop/restart.
- Treat music `preparing` and `buffering` as active so location updates cannot restart the same city soundtrack.
- Do not loop short preview tracks forever. Play the queue once or advance to the next unique source; stop cleanly at the end.
- Release any launch-cover/cube pop sound loops on screen disposal so a pop SFX cannot bleed into the Map launch.
- Recommended Android stack: Media3/ExoPlayer players per channel, one mixer/coordinator state machine (`preparing -> speaking -> crossfadingToMusic -> playing`), and 300-1800 ms volume ramps for ducking/crossfades.

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
Infinite vertical scroll of mixed media posts from different countries and categories.

#### Key Features
- **Two-dimensional feed**:
  - **Vertical swipe**: Advance to the next/previous post in the current country/category
  - **Horizontal swipe**: Change country
- **Video playback**: Auto-plays current video
- **Mixed media**: Feed must include a balanced rotation of photos, videos, and sponsored ads
- **Launch loading**: Feed opens behind a white loading screen with the animated Poplur logo centered
- **Categories**: Food, Fitness, Beauty, Sports, Modelling, Fashion, Music, Tech, News
- **Countries**: 50+ countries available (US, Canada, Mexico, UK, France, Germany, Japan, etc.)

#### User Interactions
- **Vertical scroll**: Switch between posts in current country/category
- **Horizontal swipe**: Switch to different country feed
- **Tap username/avatar**: Navigate to that user's profile
- **Long-press on post**: Show post location on map
- **Tap cube**: Scroll to top of feed or perform feed-specific action
- **Hold cube / TV Guide action**: Show the TV Guide above the whole Feed
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

#### Launch Loading Contract
- On iOS and Android, the Feed must never launch as a black screen.
- All Feed UI should start at its final on-screen position. If UI needs to appear gradually, animate opacity only; do not animate controls from a corner or from an incorrect layout position.
- Show a full-screen white loading layer with the Poplur logo animated in the center while the first Feed item prepares.
- Dismiss the loading layer with a dissolve/fade only after the first visible media item has rendered:
  - For images, wait for the image loader success callback and first composition/draw.
  - For videos, wait for ExoPlayer/Media3 `onRenderedFirstFrame` or an equivalent ready-to-display signal, not merely `STATE_READY`.
- Do not show the custom volume bars while this loading layer is active.

#### Media Mix and Ads
- The demo/offline Feed must not load only videos or only pictures.
- Use a deterministic first-page pattern so QA can verify the mix:
  - Index `0`: image
  - Index `1`: video
  - Index `2`: sponsored ad
  - Index `3`: image
  - Index `4`: video
- Repeat this pattern with `index % 5`; ads appear at `index % 5 == 2`.
- Sponsored ad cells should use the same full-screen presentation shell as posts, with clear sponsored identity in metadata.
- Production feeds should preserve the same balance target when server data allows it: interleave videos, photos, and sponsored ads instead of grouping one type.

#### Audio Management
- **Auto-play**: Current video plays automatically
- **Pause on tab switch**: Audio pauses when leaving Feed tab
- **Resume**: Audio resumes when returning to Feed
- **Global pause**: Notification system to coordinate with other tabs
- **Volume bars**: The custom green volume meter appears on hardware volume up and volume down while Feed is visible, but never while Feed launch loading is active

#### TV Guide Contract
- The TV Guide is a full-screen Feed overlay above Feed chrome, counters, and volume bars, while the persistent cube remains visible and interactive above the guide.
- Opening the TV Guide must not pause or tear down the current Feed player; the current video should keep playing audibly in the background like live TV.
- Use a PiP-style current-channel panel inside the guide so the user can see the tuned channel context while browsing rows.
- Channel numbers are green in the guide and in the Feed header.
- While the guide is open, animate the Feed username label into the current channel number, and animate the coordinate subtext into the channel station/category.
- On phones, the guide uses the full screen with the PiP panel above the channel rows.
- On tablets, include a hamburger button that toggles a channel rail/menu alongside the guide.
- Selecting a guide row tunes the Feed to that category/channel and then dismisses the guide.

#### Country/Channel Navigation
- **Country indicator**: Flag emoji + country name at top
- **Channel indicator**: Category emoji + name
- **Swipe left/right**: Cycle through countries
- **Swipe up/down inside populated Feed**: Move between posts
- **Channel changes**: Trigger from the channel selector/cube action, not from the populated vertical post swipe
- Each combination (country × channel) has its own feed

#### Default TV Static Tune Transition
- Use this as the default Feed transition for post advances, country changes, and channel/TV Guide tuning.
- Render it as a full-screen top layer above Feed and above the TV Guide during row selection.
- Visual: generated black-and-white TV snow/static at 24-30 fps, horizontal scan lines, and a few short glitch bands. Do not use color bars for this transition.
- Audio: play a generated white-noise static burst for about 0.6 seconds. Mix it with existing app audio; do not pause or rebuild the active Feed player just for the transition.
- Center the Poplur logo on the static.
- Under the logo, show the destination channel as `CH ###` and the destination category in uppercase using the same green TV font/color as the Feed header (`#4DFF40` / rounded bold TV label).
- Trigger the transition with the target channel metadata before mutating/reloading Feed state. For post and country changes, use the current channel; for channel changes and TV Guide row selection, use the destination channel.
- Timing should match iOS: show instantly, hold roughly 340 ms, then fade out over roughly 220 ms.

#### Timeline View (Instagram-style)
- Toggle between single-post and grid timeline view
- Shows all posts in chronological order
- Tap any post to return to full-screen view

#### Technical Implementation
- Lazy loading with pagination (5 posts per page)
- Firebase Firestore for data
- AVPlayer for video playback
- Location-based filtering by country code
- Android should use Media3/ExoPlayer for video and Coil/Glide for images
- Release or pause visible video players on Activity/Composable `onStop`, and rebuild/resume the current player on `onStart`/Feed return so videos do not stay blank after backgrounding
- Keep the image/video/ad decision in the Feed view model so pagination cannot accidentally request a single media type for every item

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
- **Stats trophy room**:
  - The Profile Stats route includes a gamified Trophy Room area.
  - Render it as a real 3D showcase, not a flat image: room/floor/wall, shelves, lights, trophy meshes, and camera orbit/pan.
  - Show all trophies in the room. Unlocked trophies use bright metallic materials; locked trophies stay matte gray.
  - Current unlock inputs: post count, accumulated radius, max single-post radius, total views, unique posting areas, and dominated zones.
  - Keep trophy IDs stable so Android can later sync server-persisted achievements with iOS.
- **Cube submenu**:
  - Remove the old fixed top action icons from the profile screen
  - Push the profile header upward to use the reclaimed vertical space
  - Long-press/hold the cube to show a reusable rainbow menu wheel above the cube
  - The background behind the cube dims with translucent white while the wheel is open
  - The wheel cycles through the icon actions while the user keeps holding the cube
  - Play a short pop sound and tick haptic each time the focused menu item changes
  - Releasing the cube closes the wheel with animation and activates the currently focused item
  - Wheel items contain icon-only actions: mail, settings, phone, notifications, and store
  - Keep this component screen-agnostic so other tabs can provide their own submenu items later
- **PopularPhone**:
  - The phone submenu action opens the retro phone screen
  - Android must construct the phone using Compose/Canvas or equivalent app-rendered geometry
  - Do not stretch a full-phone bitmap to fit the viewport
  - Use a fixed phone aspect ratio and normalized coordinates so the phone fits every Android screen without distortion
  - The LCD screen is a real dynamic content area for dialed numbers and mini-game content
- **Post grid**: 3-column grid of user's photos/videos
- **Post detail view**: Tap any post to see full screen

#### User Interactions
- **Tap profile picture**: View/scan 3D head model
- **Tap edit**: Open profile editing screen
- **Tap post**: Open expanded view with all post details
- **Long-press cube**: Open the profile bubble submenu
- **Tap cube while submenu is open**: Close the submenu
- **Tap cube while submenu is closed**: Perform the default profile action
- **Message button**: Navigate to messaging (if viewing another user)

#### Profile Types
##### Own Profile
- Shows edit button
- Can update profile picture, username, email
- Can delete posts
- Shows settings, mail, phone, notifications, and store through the hold-cube menu wheel
- Phone action opens the constructed, aspect-fit PopularPhone screen described in `ANDROID_DOCS_PopularPhone.md`

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
- Stats Trophy Room: use Filament, SceneView, or OpenGL/Compose 3D primitives. Avoid stretching a bitmap trophy room. Locked trophies must be rendered from the same mesh with gray material.

---

## Radius Store

### Purpose
Sell consumable radius boosts that expand a user's reach.

### Products
- Starter Radius: +5 km, product ID `com.apptist.Poplur2025.radius.starter`
- City Boost: +25 km, product ID `com.apptist.Poplur2025.radius.city`
- World Push: +100 km, product ID `com.apptist.Poplur2025.radius.world`

### Payment Requirements
- iOS must use StoreKit In-App Purchase. Do not use a fake local grant.
- Android must use Google Play Billing Library consumable products. Google Pay-backed cards can be used through Play checkout, but radius should not be sold through an off-store payment button.
- Disable purchase buttons until products are loaded from the platform store.
- Grant radius only after the platform returns a verified/purchased transaction.
- Record every delivered purchase in Firestore at `users/{userID}/radiusPurchases/{purchaseID}` and increment `users/{userID}.purchasedRadiusMeters`.
- Use the store transaction ID or Play purchase token as the ledger document ID so duplicate delivery does not double-credit radius.

### Android Implementation Notes
- Query products with `BillingClient.queryProductDetailsAsync`.
- Launch checkout with `BillingClient.launchBillingFlow`.
- On `Purchase.PurchaseState.PURCHASED`, verify the purchase token server-side when backend support is available.
- Write the Firestore ledger and increment only after verification succeeds.
- Acknowledge/consume the purchase after successful delivery so repeat consumable purchases work correctly.

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

## Notifications System

### Purpose
Send the same notification content to both:
- The user's device notification tray
- The in-app Profile notifications list

### Daily Test Notification
- Send at most one generated notification per user per day.
- For test builds, schedule the first daily notification shortly after app launch so QA can verify it on a physical phone.
- Store a last-sent day stamp locally or in Firestore to avoid duplicate same-day sends.

### Notification Content
- Notifications should be randomized from several templates so they do not feel repetitive.
- Some notifications should be AI-style radius insights based on current user post data:
  - Radius increasing
  - Radius decreasing
  - Strongest area/city
  - Area takeover momentum
- If one area has the user's strongest concentration of posts/views/radius, generate copy such as: "You are taking over Tokyo" and explain that their radius is becoming dominant there.

### Android Implementation Notes
- Use Firebase Cloud Messaging for production server-driven notifications.
- Use Android local notifications/WorkManager for the daily test notification path.
- Mirror every delivered notification into the in-app notification list.
- Foreground notifications should still render in-app immediately.
- Notification generation should use the same Firestore post fields as iOS: `latitude`, `longitude`, `radius`, `viewCount`, and `userID`.

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
- `FeedLaunchLoadingDidStart`: Feed launch loading overlay became visible
- `FeedLaunchLoadingDidFinish`: First Feed media rendered and launch loading overlay faded out

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
- Feed custom volume bars are event-driven by real system volume changes only; do not preview them during loading or tab entry

### Memory Management
- Images cached per view
- Videos unloaded when off-screen
- Visible Feed media is recreated after app foregrounding if its player/view was released in the background
- ML detection only active when camera tab visible
- AR filters only loaded when requested

---

## Gesture Conflict Resolution

### Cube Position
The cube is pinned to the **bottom center** of the screen at all times, on every tab and every child route.

```kotlin
// Compose layout — cube always at bottom
Box(Modifier.fillMaxSize()) {
    // Tab content fills the full screen behind the cube
    tabContent()

    // Cube pinned to bottom, 24dp above nav bar / home indicator
    CubeNavView(
        modifier = Modifier
            .align(Alignment.BottomCenter)
            .padding(bottom = 24.dp)
            .height(230.dp)
    )
}
```

- `Alignment.BottomCenter` — horizontally centered, at the screen bottom
- `padding(bottom = 24.dp)` — clears the home indicator / navigation bar
- The cube height is always **230dp** regardless of tab or child route — matches iOS exactly

#### Cube Clipping Fix (GL viewport must match view size)

If the 3D cube overflows its bounds, the GL viewport is not being set correctly. In your `GLSurfaceView.Renderer`:

```kotlin
override fun onSurfaceChanged(gl: GL10, width: Int, height: Int) {
    // Lock the viewport to exactly the view dimensions — nothing renders outside this
    GLES20.glViewport(0, 0, width, height)
    // Update projection matrix to match new aspect ratio
    val ratio = width.toFloat() / height.toFloat()
    Matrix.frustumM(projectionMatrix, 0, -ratio, ratio, -1f, 1f, 2f, 12f)
}
```

Do **not** set `setZOrderOnTop(true)` without also setting `holder.setFormat(PixelFormat.OPAQUE)` — the combination causes the GL surface to ignore its bounds. Keep the GL surface below other views (`setZOrderOnTop(false)`) and let the Compose layout clip it naturally.

### Cube Gestures vs Tab Content
The cube area (bottom 230dp) has gesture priority:
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

### Android Feed Parity Requirements

#### Loading Overlay Dismissal — CRITICAL

**The overlay must always dismiss.** The most common cause of a stuck screen is a deadlock — see anti-patterns below before implementing.

##### THE DEADLOCK (most common bug)

```
// ❌ WRONG — classic deadlock
if (showOverlay) {
    LoadingOverlay()        // overlay shows, waiting for a frame...
} else {
    FeedContent()           // ...but feed never starts because overlay is showing
}
```

The overlay waits for `onRenderedFirstFrame` / image `onSuccess`. If the feed content is not rendered and the player not started while the overlay is visible, those callbacks never fire. The overlay never dismisses. **Always render the feed behind the overlay, never after.**

##### Correct implementation

```kotlin
class FeedViewModel : ViewModel() {
    private val _showLaunchOverlay = MutableStateFlow(true)
    val showLaunchOverlay: StateFlow<Boolean> = _showLaunchOverlay

    // Minimum display time so the loading animation is actually seen (matches iOS 1.5 s).
    private val overlayShownAt = System.currentTimeMillis()

    init {
        // Safety-net: force-dismiss after 3 s regardless of media state.
        // If this is your only dismissal path, you have a bug — fix paths 1 & 2 below.
        viewModelScope.launch {
            delay(3_000)
            dismissOverlay()
        }
    }

    fun onFirstMediaReady() {
        // Enforce minimum 1.5 s display time so the animation is visible.
        val elapsed = System.currentTimeMillis() - overlayShownAt
        val remaining = maxOf(0L, 1_500L - elapsed)
        if (remaining > 0) {
            viewModelScope.launch {
                delay(remaining)
                dismissOverlay()
            }
        } else {
            dismissOverlay()
        }
    }

    private fun dismissOverlay() {
        _showLaunchOverlay.value = false
    }
}

// Loading logo — matches iOS: UIImage(named: "logo"), 200×200pt, centered on white
// The asset must be named exactly `logo` in res/drawable (logo.png or logo.xml).
// Do NOT use the app icon, a text wordmark, or any other asset — the "logo" drawable only.
@Composable
fun PoplurLogoAnimation() {
    val scale = remember { Animatable(0.85f) }
    val alpha = remember { Animatable(0f) }

    LaunchedEffect(Unit) {
        // Fade in + pop scale — mirrors iOS UIView.animate + CAKeyframeAnimation
        launch { alpha.animateTo(1f, animationSpec = tween(350)) }
        launch {
            scale.animateTo(1.08f, animationSpec = tween(300, easing = FastOutSlowInEasing))
            scale.animateTo(0.96f, animationSpec = tween(120))
            scale.animateTo(1.00f, animationSpec = tween(100))
        }
    }

    Image(
        painter = painterResource(id = R.drawable.logo),
        contentDescription = "Poplur",
        modifier = Modifier
            .size(200.dp)                       // matches iOS 200×200pt
            .graphicsLayer {
                scaleX = scale.value
                scaleY = scale.value
                this.alpha = alpha.value
            }
            .clip(RoundedCornerShape(36.dp))    // matches iOS clipsToBounds on logoImageView
    )
}

// Composable — overlay is always on top; feed always renders underneath
@Composable
fun FeedScreen(viewModel: FeedViewModel = hiltViewModel()) {
    val showOverlay by viewModel.showLaunchOverlay.collectAsState()

    Box(Modifier.fillMaxSize()) {
        // ✅ Feed content renders immediately, ALWAYS — never conditional on showOverlay
        FeedContent(
            onFirstVideoFrame = { viewModel.onFirstMediaReady() },
            onFirstImageLoaded = { viewModel.onFirstMediaReady() }
        )

        // Overlay sits on top and fades away — feed is already playing underneath
        AnimatedVisibility(
            visible = showOverlay,
            exit = fadeOut(animationSpec = tween(450))
        ) {
            Box(
                Modifier.fillMaxSize().background(Color.White),
                contentAlignment = Alignment.Center
            ) {
                PoplurLogoAnimation()
            }
        }
    }
}
```

##### Dismissal paths — implement all three

1. **Video first item** — wire `Player.Listener.onRenderedFirstFrame()` → `viewModel.onFirstMediaReady()`. Do NOT use `STATE_READY` — player ready ≠ frame on screen.
2. **Image first item** — wire Coil `AsyncImage` `onSuccess` or Glide `into(object : CustomTarget)` success → `viewModel.onFirstMediaReady()`. The image-type post never triggers an ExoPlayer callback.
3. **Safety timeout** — `delay(3_000)` in `init` (above). This is the last resort; if it's the only path firing, debug paths 1 and 2.

##### Common mistakes that cause permanent stuck state

| Mistake | Why it sticks |
|---|---|
| `if (showOverlay) Overlay() else FeedContent()` | Feed never renders → no callbacks → deadlock |
| Player started inside `LaunchedEffect(!showOverlay)` | Player waits for overlay to dismiss first → deadlock |
| Only wiring `onRenderedFirstFrame`, no image path | Image-first posts never fire the callback |
| No safety timeout | Any failure leaves the screen stuck forever |
| `viewModel` scoped to the composable (not NavGraph/Activity) | ViewModel recreated on recompose, `_showLaunchOverlay` resets to `true` |
| Safety timeout in `lifecycleScope` | Cancelled if app backgrounds before 3 s, never fires on return |

**Without all three paths, the overlay will get stuck** if:
- The first post is an image (ExoPlayer `onRenderedFirstFrame` never fires for images)
- Media fails to load (network error — neither callback fires)
- Feed returns zero items (no media to signal ready at all)

Additional rules:
- Use `AnimatedVisibility` with `fadeOut` only — no slide or scale exit
- Feed controls must be laid out at their final positions from the first frame; only their opacity changes
- Do not show the custom volume bars while `showLaunchOverlay == true`
- On `Lifecycle.Event.ON_STOP`, pause/release active Feed players
- On `Lifecycle.Event.ON_START`, recreate the active player and call `prepare()`/`play()` so videos load after returning to the app
- Do not show a play icon over auto-playing Feed videos
- Feed pagination should request or synthesize a balanced mix:
  - `index % 5 == 0`: image
  - `index % 5 == 1`: video
  - `index % 5 == 2`: sponsored ad
  - `index % 5 == 3`: image
  - `index % 5 == 4`: video
- Hardware volume handling:
  - Listen for both `KEYCODE_VOLUME_UP` and `KEYCODE_VOLUME_DOWN`, or observe `AudioManager.STREAM_MUSIC` volume changes.
  - Show the custom Feed volume bars for either direction.
  - Suppress them while the Feed launch overlay is visible.
  - Keep the bars in their final bottom-left Feed position and fade in/out; do not slide them from another position.

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
- ✓ Auto-playing videos do not show a play icon overlay
- ✓ First page includes images, videos, and sponsored ads
- ✓ White Poplur-logo loading screen dissolves only after first media render
- ✓ Feed UI starts in final positions and fades only
- ✓ Videos reload/resume after app background and foreground
- ✓ Volume bars appear for hardware volume up and volume down, but not during launch loading
- ✓ Full-screen TV Guide covers Feed chrome, keeps video audio playing, uses PiP layout, and uses green channel numbers
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
- ✓ Hold-cube menu wheel opens above the cube, dims the background with translucent white, cycles with pop sounds, release-selects the focused item, and opens the constructed phone from the phone item

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
