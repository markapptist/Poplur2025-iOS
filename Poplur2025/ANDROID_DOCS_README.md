# Android Documentation Package
## Complete Recreation Guide for Android Development Team

**Last Updated**: June 1, 2026  
**Version**: 1.0  
**Purpose**: Provide comprehensive documentation to recreate this iOS app on Android

---

## 📚 Documentation Files

This package contains all necessary documentation for Android recreation:

### 1. **ANDROID_DOCS_HomeView_Tabs.md** ✅ COMPLETE
   - **What**: Comprehensive guide to all 4 tabs and cube navigation
   - **Content**: 
     - Tab structure and functionality
     - Cube rotation mechanics
     - Gesture handling
     - Cross-tab navigation flows
     - UI components (radius bar, upload status, etc.)
   - **Status**: Markdown complete, ready for PDF conversion
   - **Size**: ~80KB, ~1,500 lines

### 2. **ANDROID_DOCS_Cube_Specification.md** ✅ COMPLETE
   - **What**: Deep dive into 3D cube geometry, materials, and rendering
   - **Content**:
     - Detailed geometry specs (dimensions, chamfer)
     - Material layers (diffuse, emission, normal maps)
     - Lighting setup (directional, omni, IBL)
     - Animation curves and timing
     - Shader pseudo-code
     - SceneKit → Filament mapping
   - **Status**: Markdown complete, ready for PDF conversion
   - **Size**: ~40KB, ~800 lines

### 3. **ANDROID_DOCS_PDF_CREATION_GUIDE.md** ✅ COMPLETE
   - **What**: Step-by-step guide for creating professional PDFs with visuals
   - **Content**:
     - Tool recommendations (Pages, Keynote, Pandoc)
     - Screenshot capture strategies
     - Diagram creation workflow
     - Asset export checklist
     - PDF structure templates
   - **Status**: Complete guide, follow steps to generate PDFs
   - **Size**: ~20KB, ~600 lines

### 4. **ANDROID_DOCS_Notifications_Implementation.md** ✅ COMPLETE
   - **What**: Kotlin implementation guide for daily device + in-app radius notifications
   - **Content**:
     - Data models and local persistence
     - Firestore post/radius inputs
     - AI-style radius notification generation
     - Local notification channel
     - WorkManager daily test worker
     - Firebase Cloud Messaging production path
     - Profile in-app notification mirror
   - **Status**: Complete guide, ready for Android implementation

### 5. **ANDROID_DOCS_PopularPhone.md** ✅ COMPLETE
   - **What**: Kotlin/Compose guide for reconstructing the retro phone UI without stretching a bitmap
   - **Content**:
     - Aspect-fit phone rectangle
     - Normalized body, screen, navigation key, and keypad geometry
     - Compose Canvas skeleton
     - Dynamic LCD screen area
     - Key hit testing
     - DTMF tone mapping
   - **Status**: Complete guide, ready for Android implementation

### 6. **ANDROID_DOCS_Cube_Menu_Wheel.md** ✅ COMPLETE
   - **What**: Kotlin/Compose guide for the hold-driven cube submenu wheel
   - **Content**:
     - Reusable menu wheel controller
     - Rainbow arc overlay above the cube
     - White translucent focus dim
     - Hold-to-cycle selection
     - Pop sound and haptic ticks
     - Release-to-select behavior
   - **Status**: Complete guide, ready for Android implementation

---

## 🎯 Quick Start for Android Team

### Step 1: Read the Documentation
1. Start with **ANDROID_DOCS_HomeView_Tabs.md** to understand overall architecture
2. Deep dive into **ANDROID_DOCS_Cube_Specification.md** for 3D rendering details
3. Use **ANDROID_DOCS_Notifications_Implementation.md** for device + in-app radius notifications
4. Use **ANDROID_DOCS_PopularPhone.md** for the constructed, aspect-fit retro phone
5. Use **ANDROID_DOCS_Cube_Menu_Wheel.md** for the reusable hold-cube submenu wheel
6. Reference **ANDROID_DOCS_PDF_CREATION_GUIDE.md** if you need visual PDFs

### Step 2: Generate PDFs (Optional but Recommended)
```bash
# Install Pandoc for PDF generation
brew install pandoc

# Convert HomeView tabs document to PDF
pandoc ANDROID_DOCS_HomeView_Tabs.md \
  -o HomeView_Tabs_Specification.pdf \
  --pdf-engine=xelatex \
  --toc --toc-depth=3 \
  --variable=geometry:margin=1in

# Convert Cube spec document to PDF
pandoc ANDROID_DOCS_Cube_Specification.md \
  -o Cube_3D_Navigation_Specification.pdf \
  --pdf-engine=xelatex \
  --toc --toc-depth=3 \
  --variable=geometry:margin=1in
```

### Step 3: Capture Screenshots
Follow the guide in **ANDROID_DOCS_PDF_CREATION_GUIDE.md** section "Screenshot Checklist"

**Quick command**:
```bash
# Run app in simulator
xcodebuild -scheme Poplur2025 \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' run

# Capture screenshot
xcrun simctl io booted screenshot homeview_feed.png
```

### Step 4: Set Up Android Project
See "Android-Specific Implementation Notes" sections in each doc

---

## 🏗️ Architecture Overview

### Core Components to Recreate

1. **HomeView** (Main container)
   - Tab state management
   - Cube rotation controller
   - Persistent cube overlay that remains visible above all main-tab child screens
   - Global radius bar
   - Upload status overlay

2. **CubeTabView** (3D navigation cube)
   - SceneKit 3D scene → OpenGL ES / Filament
   - Gesture recognizers → Touch handlers
   - Material system → Shaders
   - Animation system → Property animators

3. **MapView** (Map tab)
   - MapKit → Google Maps / Mapbox
   - 3D buildings, hybrid style
   - AI recommendations overlay
   - Long-press coordinate selection

4. **CameraView** (Record tab)
   - AVFoundation → CameraX
   - ML object detection → ML Kit
   - AR filters → Face detection + OpenCV
   - Recording countdown UI

5. **FeedView** (Feed tab)
   - Vertical scrolling feed → RecyclerView
   - Mixed photos/videos/sponsored ads
   - Video playback → Media3/ExoPlayer
   - White launch loading screen with animated centered Poplur logo
   - Custom volume bars on hardware volume up/down after Feed loading completes
   - Country/channel navigation
   - Full-screen TV Guide overlay with PiP layout; videos keep playing audibly behind it
   - Like/comment actions

6. **ProfileView** (Profile tab)
   - Post grid → RecyclerView with GridLayoutManager
   - Profile header pushed up after removing fixed top action icons
   - Reusable hold-cube rainbow menu wheel for mail, settings, phone, notifications, and store
   - PopularPhone opens from the phone submenu action as a constructed, aspect-fit Compose/Canvas phone
   - Statistics display
   - Navigation to other profiles

7. **IsometricRadiusBar** (Global UI component)
   - SceneKit 3D bar → OpenGL ES custom view
   - Number formatting
   - Animation system

---

## 📐 Framework Mapping

| iOS | Android | Notes |
|-----|---------|-------|
| **SwiftUI** | **Jetpack Compose** | Declarative UI |
| **UIKit** | **Android Views** | Imperative UI fallback |
| **SceneKit** | **Filament** or **OpenGL ES** | 3D rendering |
| **AVFoundation (Camera)** | **CameraX** | Camera capture |
| **AVFoundation (Video)** | **ExoPlayer** | Video playback |
| **MapKit** | **Google Maps SDK** | Maps |
| **CoreML** | **ML Kit** | Machine learning |
| **Vision** | **ML Kit Vision** | Object detection |
| **CoreLocation** | **Google Play Location** | GPS |
| **Firebase (iOS)** | **Firebase (Android)** | Backend (same) |
| **Combine** | **Kotlin Flow** | Reactive streams |
| **Swift Concurrency** | **Kotlin Coroutines** | Async/await |

---

## 🎨 Design System

### Colors (Material Theme)
```kotlin
// Primary color (indigo)
val Indigo = Color(0xFF5856D6)

// Tab-specific tints
val MapTint = Color(0xFF34C759)     // Green
val RecordTint = Color(0xFF5856D6)  // Indigo
val FeedTint = Color(0xFF5AC8FA)    // Teal
val ProfileTint = Color(0xFFFF2D55) // Pink
```

### Typography
```kotlin
// System font equivalent
val SystemFont = FontFamily(
    Font(R.font.roboto_regular, FontWeight.Normal),
    Font(R.font.roboto_bold, FontWeight.Bold),
    Font(R.font.roboto_black, FontWeight.Black)
)

// Code font (for radius display)
val MonoFont = FontFamily(
    Font(R.font.roboto_mono, FontWeight.Normal)
)
```

### Icon Mapping
See **ANDROID_DOCS_Cube_Specification.md** Appendix for full SF Symbol → Material Icon mapping

---

## 🔥 Firebase Setup (Shared Backend)

The iOS and Android apps **share the same Firebase project**:

### Collections
```
/users/{userID}
  - username: String
  - email: String
  - profilePictureURL: String?
  - averageRadius: Double

/posts/{postID}
  - userID: String
  - latitude: Double
  - longitude: Double
  - mediaURL: String
  - radius: Double
  - viewCount: Int
  - likeCount: Int
  - timestamp: Timestamp

/likes/{likeID}
  - postID: String
  - userID: String

/comments/{commentID}
  - postID: String
  - userID: String
  - text: String
  - timestamp: Timestamp

/users/{userID}/radiusPurchases/{purchaseID}
  - productID: String
  - title: String
  - radiusMeters: Int
  - storeTransactionID: String
  - purchasedAt: Timestamp
  - platform: String ("ios" or "android")
```

### Storage
```
/profile_pictures/{userID}.jpg
/posts/{postID}/media.{jpg|mp4}
/head_scans/{userID}.usdz
```

### Authentication
Both apps use **Firebase Authentication** with email/password

### Radius Purchases
- Radius is a digital app benefit and must use the platform store checkout.
- iOS uses StoreKit In-App Purchase consumables; Android must use Google Play Billing consumable products.
- Android product IDs must match the iOS package meanings:
  - `com.apptist.Poplur2025.radius.starter`: +5 km
  - `com.apptist.Poplur2025.radius.city`: +25 km
  - `com.apptist.Poplur2025.radius.world`: +100 km
- The app must not grant radius from a local button tap. Grant only after Google Play returns a purchased state and the purchase token is verified/recorded.
- After purchase, write a `radiusPurchases` ledger document and increment `users/{userID}.purchasedRadiusMeters`.

---

## 🧪 Testing Strategy

### Unit Tests
- [ ] Tab state management
- [ ] Cube rotation angle calculations
- [ ] Radius value formatting
- [ ] Coordinate transformations

### UI Tests (Espresso)
- [ ] Tab navigation (swipe left/right on cube)
- [ ] Cube remains visible and interactive on every main-tab child screen, with higher z-order/elevation than tab content
- [ ] Camera capture flow
- [ ] Feed scrolling and video playback
- [ ] Feed launch uses white Poplur-logo loading screen, not black
- [ ] Feed UI starts in final positions and fades only; no corner-to-position animation
- [ ] Feed first page includes images, videos, and sponsored ads
- [ ] Feed volume bars appear on volume up and volume down, and stay hidden during launch loading
- [ ] Feed videos resume/reload after app background and foreground
- [ ] TV Guide covers the whole Feed UI, keeps Feed video audio playing behind it, uses green channel numbers, and uses a tablet hamburger channel rail
- [ ] Profile grid interaction
- [ ] Map location selection
- [ ] Daily notification appears on device and in the in-app notifications list
- [ ] AI radius notification describes growth, decline, strongest area, or area takeover

### Integration Tests
- [ ] Firebase read/write
- [ ] Image/video upload
- [ ] User authentication
- [ ] Google Play Billing radius purchase uses real checkout and grants only after verified purchase
- [ ] Radius purchase ledger writes to Firestore and survives app restart
- [ ] FCM/local notification pipeline mirrors delivered notifications in app
- [ ] Real-time updates

### Performance Tests
- [ ] 60 FPS during cube rotation
- [ ] Smooth video playback in feed
- [ ] Memory usage under 200MB
- [ ] Network efficiency (image caching)

---

## 📦 Asset Checklist

### Textures (from iOS app)
- [ ] `CubeNormalMap.png` (512×512 normal map)
- [ ] `CubeEnv.png` (1024×512 HDR environment map)
- [ ] `earth_day.png` (8K Earth texture for globe)
- [ ] `8k_Earth_normal_map.png` (8K Earth normal map)

### Audio
- [ ] `pop.mp3` (cube tap sound, ~0.1s)

### Icons
All icons are **SF Symbols** on iOS. Map to **Material Icons** on Android:
- See **ANDROID_DOCS_Cube_Specification.md** for full table

### Fonts
- **iOS**: SF Pro (system font)
- **Android**: Roboto (system font)
- **Monospace**: SF Mono → Roboto Mono

---

## 🚀 Implementation Order (Recommended)

### Phase 1: Core Structure (Week 1-2)
1. Set up Android project with Compose
2. Implement basic HomeView with 4 placeholder tabs
3. Create bottom navigation with Material tabs (temporary)
4. Set up Firebase integration
5. Implement authentication flow

### Phase 2: Tab Content (Week 3-4)
1. **Feed Tab**:
   - RecyclerView with vertical scrolling
   - Media3/ExoPlayer for video playback
   - Balanced image/video/sponsored-ad pagination
   - White Poplur-logo launch loading overlay that fades after first media render
   - Hardware volume up/down custom volume bars, suppressed during launch loading
   - Full-screen TV Guide with PiP-style current channel panel; selecting a row tunes the Feed category
   - Like/comment actions
   
2. **Profile Tab**:
   - Post grid with RecyclerView
   - Profile header with stats
   - Constructed PopularPhone screen for the phone action
   - Navigation to other profiles
   
3. **Map Tab**:
   - Google Maps with 3D buildings
   - Location selection with long-press
   - AI recommendations (placeholder)
   
4. **Camera Tab**:
   - CameraX basic capture
   - Photo/video preview
   - Upload flow

### Phase 3: 3D Cube Navigation (Week 5-6)
1. Set up Filament or OpenGL ES
2. Create cube geometry with chamfered edges
3. Implement material system (diffuse, emission, normal maps)
4. Add lighting (directional, omni, IBL)
5. Implement rotation with pan gestures
6. Add tap/long-press actions
7. Replace bottom navigation with cube

### Phase 4: Advanced Features (Week 7-8)
1. **Radius Bar**:
   - 3D bar with globe
   - Number display
   - Animation system
   
2. **ML Detection**:
   - ML Kit object detection
   - User face recognition
   - Overlay UI
   
3. **AR Filters**:
   - Face detection
   - Beauty filter effects
   - Snapchat-style selector
   
4. **Recording**:
   - 10-second video recording
   - Countdown UI
   - Cube flash effect

### Phase 5: Polish & Optimization (Week 9-10)
1. Performance tuning (60+ FPS)
2. Animation refinement
3. Haptic feedback
4. Error handling
5. Loading states
6. Offline mode

---

## 🐛 Known Issues & Gotchas

### Issue 1: Cube Rotation Performance
**Problem**: SceneKit maintains 120 FPS easily, but OpenGL ES may struggle  
**Solution**: Use Filament for better performance, or reduce antialiasing/lighting quality

### Issue 2: Normal Map Intensity
**Problem**: Normal maps are very subtle on iOS (0.6 intensity)  
**Solution**: May need to boost intensity to 1.0-1.5 on Android for same visual effect

### Issue 3: Video Playback in Feed
**Problem**: AVPlayer has superior performance vs ExoPlayer for short clips  
**Solution**: Implement aggressive video preloading and caching

### Issue 4: AR Filter Lag
**Problem**: Real-time face filter processing can drop frames  
**Solution**: Reduce camera resolution to 720p during filter mode

### Issue 5: Firebase Costs
**Problem**: High-resolution images can generate large storage costs  
**Solution**: Compress images to max 2048×2048 before upload

---

## 📞 Support & Contact

### Documentation Questions
- **Primary Contact**: iOS Lead [your-email@company.com]
- **Response Time**: Within 1 business day

### Technical Implementation Questions
- **3D Graphics**: [graphics-expert@company.com]
- **Camera/ML**: [ml-expert@company.com]
- **Firebase**: [backend-lead@company.com]

### Bug Reports
- **Repository**: GitHub Issues on this repo
- **Slack**: #android-ios-sync channel
- **Email**: [dev-team@company.com]

---

## 📝 Changelog

### v1.0 (2026-06-01)
- Initial documentation package
- HomeView tabs specification complete
- Cube 3D specification complete
- PDF creation guide complete

### v1.1 (TBD)
- Add visual PDFs with screenshots
- Add animated GIFs for interactions
- Add Figma design file links

### v1.2 (TBD)
- Add code examples for Android
- Add working sample project
- Add video walkthroughs

---

## 🎓 Learning Resources

### 3D Graphics on Android
- [Filament Documentation](https://google.github.io/filament/)
- [OpenGL ES 3.0 Programming Guide](https://www.khronos.org/opengles/)
- [Learn OpenGL (with GLSL shaders)](https://learnopengl.com/)

### Jetpack Compose
- [Official Compose Tutorial](https://developer.android.com/jetpack/compose/tutorial)
- [Compose Animation](https://developer.android.com/jetpack/compose/animation)
- [Compose Gestures](https://developer.android.com/jetpack/compose/gestures)

### CameraX
- [CameraX Overview](https://developer.android.com/training/camerax)
- [CameraX Video Capture](https://developer.android.com/training/camerax/video-capture)

### ML Kit
- [ML Kit Object Detection](https://developers.google.com/ml-kit/vision/object-detection)
- [ML Kit Face Detection](https://developers.google.com/ml-kit/vision/face-detection)

### ExoPlayer
- [ExoPlayer Guide](https://exoplayer.dev/)
- [ExoPlayer Playlist](https://exoplayer.dev/playlists.html)

---

## ✅ Acceptance Criteria

The Android app should match iOS when:

### Functional Parity
- [ ] All 4 tabs work identically
- [ ] Cube rotates smoothly with gestures
- [ ] Cube remains visible on every main-tab and child-route screen
- [ ] Camera captures photos and 10-second videos
- [ ] Feed plays videos with country/channel navigation
- [ ] Profile shows posts in grid with stats
- [ ] Profile top action icons are removed; holding the cube opens the reusable rainbow menu wheel, cycles with pop sounds, and release selects the focused item
- [ ] PopularPhone is rendered from Android UI geometry, aspect-fits to the screen, and does not stretch a phone bitmap
- [ ] Map allows location selection for posts
- [ ] Radius bar displays and animates correctly
- [ ] Upload flow works end-to-end

### Visual Parity
- [ ] Cube looks identical (geometry, materials, lighting)
- [ ] Colors match exactly (use hex codes provided)
- [ ] Typography is equivalent (Roboto ≈ SF Pro)
- [ ] Animations feel the same (timing, easing)
- [ ] Layout matches (spacing, alignment)

### Performance Parity
- [ ] Maintains 60+ FPS during cube rotation
- [ ] Video playback is smooth (no stuttering)
- [ ] Camera preview has low latency
- [ ] App launch is fast (<2 seconds)
- [ ] Memory usage is reasonable (<300MB)

### Feature Parity
- [ ] ML object detection works
- [ ] AR face filters work
- [ ] User recognition works
- [ ] Push notifications work
- [ ] Daily AI radius notification appears on device and in Profile notifications
- [ ] Offline mode works (cached content)

---

## 🏁 Next Steps

1. **Read all documentation files** (2-3 hours)
2. **Review with Android team** (1 meeting, 1 hour)
3. **Generate PDFs with screenshots** (2-3 hours) — **optional but helpful**
4. **Set up Android project** (1 day)
5. **Start Phase 1 implementation** (see Implementation Order above)
6. **Weekly syncs with iOS team** (ongoing)

---

## 📄 License & Usage

These documentation files are **proprietary** to [Company Name]. Intended for internal use only by the Android development team for recreating the iOS app functionality.

**Do not distribute** outside the company.

---

**END OF README**

*Generated on 2026-06-01 by iOS Development Team*
