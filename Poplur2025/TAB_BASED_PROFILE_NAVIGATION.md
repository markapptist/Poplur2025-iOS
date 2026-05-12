# Tab-Based Profile Navigation - Implementation Summary

## Overview

When you tap on a user in the Feed, the app now **switches to the Profile tab** (staying within the TabBarController) and displays that user's profile, rather than pushing a NavigationLink. This ensures:

✅ The home view (cube) remains visible  
✅ The radius bar shows the user's accumulated radius  
✅ The countdown view shows the user's post count  
✅ No "0 posts" badge appears (since navigation only happens from a post)

## How It Works

### 1. **FeedView** - Sending the Navigation Request

When a user taps on a username in the feed:

```swift
// FeedView.swift
onUserTapped: { uid in
    print("👤 [FeedView] User tapped - userID: '\(uid)'")
    // Post notification to switch to profile tab with this userID
    NotificationCenter.default.post(
        name: Notification.Name("ShowUserProfile"),
        object: uid  // The user's ID is passed as the object
    )
}
```

### 2. **TabBarControllerHost** - Handling the Navigation

The TabBarController listens for this notification:

```swift
// TabBarControllerHost.swift
.onReceive(NotificationCenter.default.publisher(for: .ShowUserProfile)) { note in
    if let uid = note.object as? String {
        print("🔔 [TabBarController] Received ShowUserProfile for userID: '\(uid)'")
        routedUserID = uid  // Store the userID
        selection = .profile  // Switch to profile tab
    }
}
```

The `routedUserID` is injected into the environment:

```swift
profile()
    .environment(\.routedUserID, routedUserID)
    .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage) }
    .tag(AppTab.profile)
```

### 3. **ProfileView** - Displaying the Correct Profile

ProfileView reads the `routedUserID` from the environment:

```swift
// ProfileView.swift
@Environment(\.routedUserID) private var routedUserID

// The effective userID: routedUserID takes precedence
private var effectiveUserID: String? {
    if let routed = routedUserID, !routed.isEmpty {
        return routed  // User from feed
    }
    return userID  // Fallback to userID parameter
}
```

When loading posts:

```swift
let targetUID: String
if let effective = effectiveUserID, !effective.isEmpty {
    targetUID = effective
    print("🔑 [ProfileView] Using effectiveUserID: \(targetUID)")
} else if let current = Auth.auth().currentUser?.uid {
    targetUID = current  // Own profile
    print("🔑 [ProfileView] Using current user's UID: \(targetUID)")
}

// Query Firestore for this user's posts
db.collection("posts")
    .whereField("userID", isEqualTo: targetUID)
```

### 4. **Clearing Routed State** - Manual Tab Switches

When the user manually switches away from the profile tab, the routed state is cleared:

```swift
// TabBarControllerHost.swift
.onChange(of: selection) { newTab in
    if newTab != .profile && routedUserID != nil {
        print("🔔 [TabBarController] Clearing routedUserID")
        routedUserID = nil
    }
}
```

This ensures that when you return to the profile tab later (by tapping the tab bar), it shows YOUR profile, not the user you were viewing.

## Key Changes Made

### FeedView.swift
- ❌ Removed `@State private var selectedUserID` and `navigateToProfile`
- ❌ Removed `profileNavigationLink` NavigationLink
- ✅ Changed user tap handler to post notification instead
- ✅ Uses `Notification.Name("ShowUserProfile")` with userID as object

### ProfileView.swift
- ✅ Added `@Environment(\.routedUserID)` to receive routed userID
- ✅ Added `effectiveUserID` computed property (routedUserID takes priority)
- ✅ Updated `isOwnProfile` to use `effectiveUserID`
- ✅ Updated `loadMyPosts()` to use `effectiveUserID`
- ✅ Updated `loadNextPage()` to use `effectiveUserID`
- ✅ Updated `usernameRow` task to use `effectiveUserID`
- ✅ Updated `viewID` to use `effectiveUserID`
- ❌ Removed "X posts" badge (no longer needed since we only navigate from posts)

### TabBarControllerHost.swift
- ✅ Added `extension Notification.Name` with notification constants
- ✅ Added `@State private var routedUserID: String?`
- ✅ Added `.onReceive` for `.ShowUserProfile` notification
- ✅ Added `.onChange(of: selection)` to clear routedUserID when switching tabs
- ✅ Injects `routedUserID` into profile's environment

## Flow Diagram

```
User taps username in Feed
         ↓
FeedView posts ShowUserProfile notification with userID
         ↓
TabBarController receives notification
         ↓
TabBarController stores userID in routedUserID
         ↓
TabBarController switches selection to .profile
         ↓
ProfileView receives routedUserID via environment
         ↓
ProfileView uses routedUserID as effectiveUserID
         ↓
ProfileView queries Firestore for posts by effectiveUserID
         ↓
User sees the clicked user's profile
         ↓
[User switches to another tab manually]
         ↓
TabBarController clears routedUserID
         ↓
[User returns to Profile tab later]
         ↓
ProfileView shows own profile (no routedUserID)
```

## Benefits

1. **Home View Always Visible**: The cube, radius bar, and countdown remain visible while viewing any profile
2. **Radius Display**: The isometric radius bar shows the accumulated radius of the user being viewed
3. **Post Count**: The countdown view shows how many posts the user has
4. **No "0 Posts" Badge**: Since navigation only happens from a post, we know the user has at least that post
5. **Consistent Navigation**: All profile views use the same tab-based interface
6. **Cleaner State Management**: No NavigationLink state, just notifications

## Debugging

### Check if Navigation is Working

Look for these logs in Xcode console:

```
👤 [FeedView] User tapped - userID: 'abc123'
🔔 [TabBarController] Received ShowUserProfile for userID: 'abc123'
🔑 [ProfileView] Using effectiveUserID: abc123 (viewing other profile)
🔍 [ProfileView] About to query posts for userID: 'abc123'
📊 [ProfileView] Received 5 documents from Firebase
```

### If Profile Shows Wrong User

1. Check the `routedUserID` value in TabBarController
2. Verify `effectiveUserID` in ProfileView
3. Make sure the notification object contains the correct userID

### If Profile Shows Empty

1. Verify the userID is not empty when posting notification
2. Check Firestore to ensure posts exist for that userID
3. Look for error logs in the console

## Testing

### Test Case 1: Navigate to Another User's Profile
1. Open feed
2. Tap on a username
3. ✅ Should switch to Profile tab
4. ✅ Should show that user's posts
5. ✅ Radius bar should show their accumulated radius
6. ✅ No "0 posts" badge should appear

### Test Case 2: Return to Own Profile
1. From another user's profile
2. Tap Map or Feed tab
3. Tap Profile tab again
4. ✅ Should show YOUR profile, not the other user's

### Test Case 3: Multiple User Navigation
1. View User A's profile from feed
2. Switch to Feed tab
3. View User B's profile from feed
4. ✅ Should show User B's profile (not User A's)

## Notes

- The notification uses the object field to pass the userID (not userInfo dictionary)
- The routedUserID is cleared automatically when switching tabs manually
- The ProfileView's `viewID` forces recreation when the effectiveUserID changes
- All existing profile functionality (grid/list modes, delete, fullscreen) remains unchanged
