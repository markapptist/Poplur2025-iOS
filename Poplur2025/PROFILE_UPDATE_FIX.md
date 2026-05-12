# Profile View Update Fix

## Problem
When navigating to a user's profile from the feed view by tapping on their username, the ProfileView would not update its data when switching to a different user. The view would continue showing the previous user's posts, username, and other details. Additionally, demo users in the feed didn't have matching posts or usernames when their profiles were viewed.

## Root Causes
The `ProfileView.onChange(of: routedUserID)` handler was only reloading posts if the new userID was different from the current one, but it wasn't clearing the cached state for the previous user. This meant:

1. `displayUsername` would still show the old user's name
2. `userProfile` would still contain the old user's data
3. `profileImage` would still show the old user's avatar
4. Posts would not reload properly
5. The radius bar would show stale data

**Additionally**, there were data consistency issues:
- Demo users didn't have pre-generated profile posts, so their profiles appeared empty
- Each feed post generated a unique userID, so users didn't share posts
- Usernames weren't being prefetched, causing display delays

## Solution
The fix involves **five key changes** across three files:

### 1. Enhanced `.onChange(of: routedUserID)` Handler
**File:** `ProfileView.swift`

The handler now:
- Clears ALL cached state when switching users
- Resets the radius bar to 0 before loading new data
- Reloads posts for the new user
- Fetches the username for the new user
- Only loads profile images for own profile
- Updates the radius bar with the new user's total radius

```swift
.onChange(of: routedUserID) { newUserID in
    print("🔄 [ProfileView] routedUserID changed to: \(newUserID ?? "nil")")
    // Clear all state and reload everything when viewing a different user
    displayUsername = nil
    userProfile = nil
    profileImage = nil
    profileImageURL = nil
    myPosts = []
    loadedImages = [:]
    hasLoadedOnce = false
    
    // Reset radius bar to 0 when switching users
    RadiusBarAnimator.animate(to: 0, duration: 0.3)
    
    Task {
        // Reload posts for the new user
        await loadMyPosts()
        
        // Fetch username for the new user
        if let uid = effectiveUserID {
            displayUsername = await UsernameCache.shared.username(for: uid)
        }
        
        // Only load profile image for own profile
        if isOwnProfile {
            await loadPersistedProfileImageIfNeeded()
        }
        
        // Update radius bar with new user's total radius
        await MainActor.run {
            self.averageRadius = Double(self.averagePostRadius())
            if self.averageRadius > 0 {
                RadiusBarAnimator.animate(to: self.averageRadius, duration: 1.2)
            }
        }
    }
}
```

### 2. Reactive Username Row
**File:** `ProfileView.swift`

Changed the `.task` modifier to use `id: effectiveUserID` so it re-runs whenever the user changes:

```swift
private var usernameRow: some View {
    Text(displayUsername ?? ...)
        .font(.system(size: 22, weight: .heavy, design: .rounded))
        .foregroundColor(.black.opacity(0.95))
        .padding(.top, 4)
        .task(id: effectiveUserID) {  // ← Added id parameter
            if let uid = effectiveUserID ?? Auth.auth().currentUser?.uid {
                displayUsername = await UsernameCache.shared.username(for: uid)
            }
        }
}
```

### 3. Debug Logging in viewID
**File:** `ProfileView.swift`

Added debug logging to verify view recreation is happening:

```swift
private var viewID: String {
    let id = effectiveUserID ?? "own-profile"
    print("🆔 [ProfileView] viewID computed as: '\(id)'")
    return id
}
```

### 4. Improved Demo Post Generation with Profile Posts
**File:** `FeedView.swift`

**Key improvements:**
- Create **stable userIDs** so multiple posts share the same user (every 3 posts = 1 user)
- Pre-generate **5-10 additional profile posts** for each unique user
- Store these posts in `DemoPostStore` **immediately** so they're available when you click on a profile

```swift
private static func generateDemoPostsForCountryAndChannel(...) -> [FeedPost] {
    // ... generate feed posts with stable userIDs (every 3 posts share a user)
    
    // CRITICAL: Pre-generate additional posts for each unique user
    var postsPerUser: [String: [FeedPost]] = [:]
    for post in result {
        postsPerUser[post.userID, default: []].append(post)
    }
    
    // Generate 5-10 additional posts per user for their profile
    for (userID, existingPosts) in postsPerUser {
        let additionalCount = Int.random(in: 5...10)
        for j in 0..<additionalCount {
            // ... create additional posts with same userID
            DemoPostStore.shared.store([additionalPost])
        }
    }
    
    return result
}
```

### 5. Enhanced Username Cache with Demo Support & Prefetching
**File:** `UsernameCache.swift`

**Key improvements:**
- **Detect demo users** automatically (by userID pattern)
- **Generate readable usernames** for demo users (e.g., "FOOD USER 0")
- **Prefetch method** to load all usernames in background when posts load

```swift
actor UsernameCache {
    func username(for uid: String) async -> String? {
        // Check if this is a demo user and generate a readable username
        if isDemoUser(uid) {
            let generatedName = generateDemoUsername(for: uid)
            await store(username: generatedName, for: uid)
            return generatedName
        }
        
        // ... existing Firebase fetch logic
    }
    
    /// Prefetch usernames for an array of UIDs (call this when posts load)
    func prefetch(uids: [String]) async {
        let uncached = uids.filter { /* not cached */ }
        await withTaskGroup(of: Void.self) { group in
            for uid in uncached {
                group.addTask { _ = await self.username(for: uid) }
            }
        }
    }
    
    private func isDemoUser(_ uid: String) -> Bool {
        return uid.contains("_user_") || uid.hasPrefix("food_") // ...
    }
    
    private func generateDemoUsername(for uid: String) -> String {
        // "food_user_0" -> "FOOD USER 0"
        let components = uid.split(separator: "_")
        if components.count >= 2 {
            let channelName = String(components[0]).uppercased()
            let userNum = components.count > 2 ? String(components[2]) : "0"
            return "\(channelName) USER \(userNum)"
        }
        return "DEMO USER"
    }
}
```

## How It Works

### Data Flow
1. User opens feed → posts generate with **stable userIDs** (every 3 posts share a user)
2. Post generation **pre-creates 5-10 profile posts** per user in `DemoPostStore`
3. Feed calls `UsernameCache.prefetch()` to load all usernames in background
4. User taps on a username in `FeedView`
5. `FeedView` posts `ShowUserProfile` notification with the userID
6. `TabBarControllerHost` receives notification and:
   - Sets `routedUserID` state to the new userID
   - Switches to profile tab
7. Profile tab has `.environment(\.routedUserID, routedUserID)` modifier
8. `ProfileView` receives new `routedUserID` via environment
9. View's `.onChange(of: routedUserID)` triggers:
   - Clears all cached state
   - Reloads posts from `DemoPostStore` (which now has the pre-generated posts!)
   - Fetches username from cache (already loaded!)
10. View's `.id(viewID)` causes SwiftUI to recreate the view with fresh state

### State Management
The ProfileView now properly manages three different states:

1. **Own Profile** - When viewing your own posts
   - Uses `Auth.auth().currentUser?.uid`
   - Shows settings button and profile customization
   - Loads saved profile photo

2. **Other User's Profile** - When viewing from feed
   - Uses `routedUserID` from environment
   - Shows back-to-feed navigation
   - Doesn't load profile customization
   - **Loads pre-generated posts from DemoPostStore**

3. **Explicit UserID** - When passed as parameter
   - Uses the `userID` parameter
   - Falls back to current user if nil

## Testing Scenarios

### Test Case 1: Navigate to Different Users
1. Open feed view
2. Tap on first post's username → Profile should show that user's posts (5-10+ posts)
3. Verify username matches what was shown in feed
4. Tap back to feed
5. Tap on different post's username → Profile should update with new user's posts
6. Verify username updates immediately
7. Verify post count changes (different users have different numbers of posts)
8. Verify radius bar updates

### Test Case 2: Same User Across Multiple Posts
1. Scroll through feed
2. Notice that every 3 posts share the same username
3. Tap on any of these posts' usernames
4. Verify the profile shows **all posts from that user** (not just the one you tapped)
5. Verify the username is consistent

### Test Case 3: Switch Between Own and Other Profiles
1. View your own profile
2. Switch to feed
3. Tap on another user's profile
4. Verify "Your Profile" changes to "User Profile"
5. Verify settings button disappears
6. Verify back button appears
7. Switch back to profile tab → Should show your own profile again

### Test Case 4: Rapid User Switching
1. In feed, quickly tap on multiple different users
2. Verify profile updates for each one
3. Verify no stale data shows between switches
4. Verify radius bar animates correctly
5. Verify usernames display immediately (no loading delay)

### Test Case 5: Username Consistency
1. Open feed and note the username on a post
2. Tap on that username
3. Verify the profile page shows the **exact same username**
4. Verify the posts on the profile all belong to that user

## Debug Output
You should see console logs like:
```
📊 [FeedView] Generated 5 feed posts with 2 unique users, pre-generated profile posts
🔔 [TabBarController] Received ShowUserProfile for userID: 'food_user_0'
🔄 [ProfileView] routedUserID changed to: food_user_0
🆔 [ProfileView] viewID computed as: 'food_user_0'
📊 [ProfileView] onAppear - setting radius to 0
📊 [ProfileView] onAppear - reloading posts for userID: food_user_0
🔍 [ProfileView] About to query posts for userID: 'food_user_0'
🎭 [ProfileView] Demo user detected, loading from DemoPostStore
🎭 [ProfileView] Found 8 demo posts for userID: 'food_user_0'
✅ [ProfileView] Successfully mapped 8 posts
```

## Related Files
- `ProfileView.swift` - Main profile view implementation
- `TabBarControllerHost.swift` - Manages routing between tabs
- `FeedView.swift` - Sends ShowUserProfile notifications, generates demo posts
- `UsernameCache.swift` - Caches usernames globally, supports demo users

## Notes
- The view uses `.id(viewID)` to force complete recreation when userID changes
- Demo users (with "_user_" in their ID) load from `DemoPostStore` instead of Firebase
- Demo usernames are automatically generated in format "CHANNEL USER #"
- Profile images only load for own profile, not other users
- The radius bar always resets to 0 when switching users, then animates to the total
- **UserIDs are now stable** - every 3 feed posts share the same user
- **Profile posts are pre-generated** - each user has 5-10 posts ready to view
- **Usernames are prefetched** - no loading delay when switching between users
