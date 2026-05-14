# FeedView Debug Guide

## Issues Fixed

### 1. Added FeedPost Model Definition
**Problem**: The `FeedPost` struct was referenced but never defined, causing compilation errors and runtime crashes.

**Fix**: Added the struct definition at the top of FeedView.swift:
```swift
struct FeedPost: Identifiable, Equatable {
    let id: String
    let latitude: Double
    let longitude: Double
    let mediaURL: String
    let radius: Double
    let viewCount: Int
    let userID: String
}
```

### 2. Enhanced Error Visibility
**Problem**: Posts were black/empty with no indication why they failed to load.

**Fixes**:
- Added debug logging throughout the rendering pipeline
- Added visible error states for failed images with error messages
- Added loading indicators for images
- Added fallback UI when media URLs are invalid

### 3. Improved Logging
**Problem**: Hard to debug why posts weren't showing or profile posts weren't loading.

**Fixes**:
- Added comprehensive logging to `DemoPostStore`
- Added logging to post generation functions
- Added logging to image/video rendering
- Added logging to reload functions

## How to Debug

### Step 1: Check Console Logs

Run the app and watch for these log patterns:

#### On App Launch:
```
📡 [Feed] reload completed:
   - Posts loaded: 5
   - Country: US
   - Channel: food
   - First post ID: us_food_demo_0
   - First post mediaURL: https://picsum.photos/...
   - Feed ready: true
```

#### When Posts Render:
```
🎬 [FeedFullscreenPageView] Rendering post us_food_demo_0
   mediaURL: https://picsum.photos/800/1400?random=1234
   isVideo: false
   directVideoURL: nil
🖼️ [FeedFullscreenPageView] Showing image: https://picsum.photos/...
```

#### For Images Loading:
```
📸 [Feed] Loading image: https://picsum.photos/800/1400?random=1234
✅ [Feed] Image loaded successfully: https://picsum.photos/...
```

#### For Failed Images:
```
❌ [Feed] Image load failed: https://picsum.photos/..., error: <description>
```

#### When Tapping User Profile:
```
👤 [FeedView] User tapped - userID: 'food_user_0'
👤 [DemoPostStore] Found 8 posts for userID: food_user_0
```

### Step 2: Common Issues and Solutions

#### Issue: Black Screen with No Posts
**Check for**: 
```
📡 [Feed] reload completed:
   - Posts loaded: 0
```

**Solution**: Posts aren't being generated. Check:
1. `selectedCountryIndex` and `selectedChannelIndex` are valid
2. `generateDemoPostsForCountryAndChannel` is being called
3. No errors in post generation logic

#### Issue: Posts Generate But Don't Display
**Check for**:
```
🎬 [FeedFullscreenPageView] Rendering post <id>
   mediaURL: <url>
   isVideo: <bool>
⚠️ [FeedFullscreenPageView] Invalid URL for post...
```

**Solution**: Media URLs are invalid. Check:
1. URLs are well-formed
2. Network connection is available
3. picsum.photos is accessible

#### Issue: Images Show Loading Indicator Forever
**Check for**:
```
📸 [Feed] Loading image: <url>
(but no success or failure log follows)
```

**Solution**: Network issue or invalid URL. Check:
1. Device has internet connection
2. URL is accessible in Safari
3. No firewall/VPN blocking requests

#### Issue: Profile Posts Don't Load
**Check for**:
```
👤 [FeedView] User tapped - userID: 'food_user_0'
👤 [DemoPostStore] Found 0 posts for userID: food_user_0
```

**Solution**: Posts aren't in DemoPostStore. Check:
1. Posts were stored during generation:
   ```
   📦 [DemoPostStore] Stored 5 new posts (total: 15)
   ```
2. UserID matches exactly (case-sensitive)
3. Additional profile posts were generated

### Step 3: Verify Post Generation

Add this temporary test in your code:
```swift
// In FeedView.onAppear
Task {
    await reload()
    
    // Verify posts were generated
    print("DEBUG: Total posts: \(posts.count)")
    if let first = posts.first {
        print("DEBUG: First post: \(first)")
    }
    
    // Verify DemoPostStore has posts
    let allPosts = DemoPostStore.shared.allPosts()
    print("DEBUG: DemoPostStore total: \(allPosts.count)")
    let allUsers = DemoPostStore.shared.allUsers()
    print("DEBUG: DemoPostStore users: \(allUsers)")
}
```

### Step 4: Test Profile Navigation

Add this temporary test:
```swift
// Test profile post loading
let testUserID = "food_user_0"
let userPosts = DemoPostStore.shared.posts(for: testUserID)
print("DEBUG: Posts for \(testUserID): \(userPosts.count)")
for post in userPosts {
    print("  - \(post.id): \(post.mediaURL)")
}
```

## Expected Behavior

### Feed View:
1. On launch, should see 5 posts generated
2. Each post should show either an image or video
3. Images should load within 1-2 seconds
4. Videos should start playing automatically

### Profile View:
1. Tapping a user should navigate to their profile
2. Profile should show 8-13 posts total (3 from feed + 5-10 generated)
3. All posts should be for the same userID
4. Posts should load and display correctly

## Missing Dependencies to Add

You may need to create stubs for these if they don't exist:

1. **LocationProvider**: Location services wrapper
2. **UsernameCache**: Cache for user display names
3. **RadiusBarAnimator**: Animates the radius indicator
4. **FeedAudioManager**: Manages audio playback
5. **VideoLoadingIndicator**: Loading overlay
6. **AdManager**: Ad display manager

Create stub implementations if needed:
```swift
// Stub for missing dependencies
class LocationProvider: ObservableObject {
    @Published var coordinate: CLLocationCoordinate2D?
    init() {
        coordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    }
}

actor UsernameCache {
    static let shared = UsernameCache()
    func username(for uid: String) async -> String? {
        return uid.replacingOccurrences(of: "_", with: " ").capitalized
    }
    func prefetch(uids: [String]) async {}
}

class RadiusBarAnimator {
    static func showPostRadius(_ radius: Double, duration: Double) {
        print("📏 RadiusBarAnimator: \(radius)m")
    }
}

class FeedAudioManager {
    static let shared = FeedAudioManager()
    func playExclusively(_ player: AVPlayer) { player.play() }
    func register(_ player: AVPlayer) {}
}

struct VideoLoadingIndicator: View {
    @Binding var isLoading: Bool
    let logoName: String
    var body: some View {
        EmptyView()
    }
}

class AdManager {
    static let shared = AdManager()
    func presentInterstitial(from: UIViewController) {}
}
```

## Next Steps

1. Run the app and collect console logs
2. Look for the specific log patterns above
3. Identify which stage is failing
4. Apply the appropriate solution
5. Verify posts are being stored in DemoPostStore
6. Test profile navigation to ensure posts load
