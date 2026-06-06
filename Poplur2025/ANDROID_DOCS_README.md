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

---

## 🎯 Quick Start for Android Team

### Step 1: Read the Documentation
1. Start with **ANDROID_DOCS_HomeView_Tabs.md** to understand overall architecture
2. Deep dive into **ANDROID_DOCS_Cube_Specification.md** for 3D rendering details
3. Reference **ANDROID_DOCS_PDF_CREATION_GUIDE.md** if you need visual PDFs

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
   - Video playback → ExoPlayer
   - Country/channel navigation
   - Like/comment actions

6. **ProfileView** (Profile tab)
   - Post grid → RecyclerView with GridLayoutManager
   - Profile header
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
```

### Storage
```
/profile_pictures/{userID}.jpg
/posts/{postID}/media.{jpg|mp4}
/head_scans/{userID}.usdz
```

### Authentication
Both apps use **Firebase Authentication** with email/password

---

## 🧪 Testing Strategy

### Unit Tests
- [ ] Tab state management
- [ ] Cube rotation angle calculations
- [ ] Radius value formatting
- [ ] Coordinate transformations

### UI Tests (Espresso)
- [ ] Tab navigation (swipe left/right on cube)
- [ ] Camera capture flow
- [ ] Feed scrolling and video playback
- [ ] Profile grid interaction
- [ ] Map location selection

### Integration Tests
- [ ] Firebase read/write
- [ ] Image/video upload
- [ ] User authentication
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
   - ExoPlayer for video playback
   - Like/comment actions
   
2. **Profile Tab**:
   - Post grid with RecyclerView
   - Profile header with stats
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
- [ ] Camera captures photos and 10-second videos
- [ ] Feed plays videos with country/channel navigation
- [ ] Profile shows posts in grid with stats
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
