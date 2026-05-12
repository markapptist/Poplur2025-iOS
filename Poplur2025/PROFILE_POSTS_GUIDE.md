# Profile Posts Display Guide

## Overview

When you tap on a user's profile from the feed, the ProfileView should automatically display **all posts created by that user**, including the current post you were viewing in the feed.

## How It Works

### 1. **Feed to Profile Navigation**

When you tap on a user in FeedView:

```swift
onUserTapped: { uid in
    print("👤 [FeedView] User tapped - userID: '\(uid)'")
    selectedUserID = uid
    navigateToProfile = true
}
```

The `userID` from the current post is captured and passed to ProfileView.

### 2. **ProfileView Query**

ProfileView queries Firestore for all posts matching the userID:

```swift
db.collection("posts")
    .whereField("userID", isEqualTo: uid)
    .order(by: "createdAt", descending: true)
    .limit(to: pageSize)
```

This query will return **all posts** where the `userID` field matches, including:
- The post you were viewing in the feed
- All other posts by the same user

### 3. **Data Structure Requirements**

For this to work correctly, each post in Firestore must have:

```json
{
  "id": "unique-post-id",
  "userID": "user-123",              // Must match exactly
  "latitude": 37.7749,
  "longitude": -122.4194,
  "mediaURL": "https://...",
  "radius": 5000,
  "viewCount": 42,
  "createdAt": "2024-01-15T10:30:00Z"  // Optional but recommended
}
```

## Troubleshooting

### Posts Not Appearing on Profile

If you don't see posts on a user's profile, check these items:

#### 1. **Verify userID Field**

The most common issue is a mismatch in the `userID` field.

**Check the Xcode console for these debug logs:**

```
🔍 [ProfileView] Fetching posts for userID: 'user-123'
📊 [ProfileView] Received 5 documents from Firebase
✅ [ProfileView] Found 5 documents, mapping to Post objects...
   - Sample post ID: abc123
   - Sample userID: 'user-123'
```

If you see:
```
⚠️ [ProfileView] No documents found for userID: 'user-123'
```

**Possible causes:**
- The field is named `userId` instead of `userID` (case-sensitive)
- The userID value has extra whitespace or special characters
- The userID is empty or missing from the post

**Solution:** Check your Firestore console and verify:
1. Field name is exactly `userID` (capital I, capital D)
2. The value matches exactly (no trailing spaces)

#### 2. **Empty userID**

If you see this warning:
```
⚠️ [FeedView] Cannot navigate to profile - userID is empty
```

The post's userID field is empty. Make sure when creating posts, you always set a valid userID:

```swift
// When creating a post
let data: [String: Any] = [
    "userID": Auth.auth().currentUser?.uid ?? "",  // ❌ Could be empty
    // ... other fields
]
```

**Better approach:**
```swift
// Validate before creating
guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
    print("❌ Cannot create post - no user logged in")
    return
}

let data: [String: Any] = [
    "userID": uid,  // ✅ Guaranteed non-empty
    // ... other fields
]
```

#### 3. **Field Name Case Sensitivity**

Firestore field names are **case-sensitive**:
- `userID` ≠ `userId` ≠ `userid` ≠ `UserID`

The code expects exactly `userID` (camelCase with capital I and D).

**To fix mismatched field names:**

Option A: Update Firestore documents to use `userID`
Option B: Update the code to match your Firestore field name

```swift
// In ProfileView.swift, search for:
.whereField("userID", isEqualTo: uid)

// Change to match your field name:
.whereField("userId", isEqualTo: uid)  // if your field is "userId"
```

#### 4. **Posts Collection Name**

The code queries the `posts` collection. If your collection has a different name, update:

```swift
// In ProfileView.swift, search for:
db.collection("posts")

// Change to your collection name:
db.collection("user_posts")  // or whatever your collection is named
```

#### 5. **Firestore Indexes**

If you see an error about missing indexes:
```
❌ [ProfileView] Error fetching posts: FAILED_PRECONDITION: The query requires an index...
```

The query falls back to a simpler query without ordering. Your posts will still load, but may not be in chronological order.

**To add the index:**
1. Open the Firebase Console
2. Go to Firestore → Indexes
3. Click the link in the error message (it will auto-create the index)
4. Wait 1-2 minutes for the index to build

Or create manually:
- Collection: `posts`
- Fields to index: `userID` (Ascending), `createdAt` (Descending)

## Expected Behavior

### When Viewing Your Own Profile
1. Shows all your posts
2. Can delete posts
3. Can edit profile
4. Cube interactions work (hold for messages, tap for settings)

### When Viewing Another User's Profile
1. Shows all their posts
2. Cannot delete their posts
3. Cannot edit their profile
4. Cube interactions disabled

## Demo Data

If you're using demo/fake posts (from `FakePostService`), they use userIDs like:
- `fake_user_1`, `fake_user_2`, etc.
- `na_user_ca_0001`, `na_user_us_0002`, etc.
- `world_user_0001`, etc.

These should all work correctly as long as the `userID` field is properly set when creating the demo posts.

## Debugging Steps

1. **Enable detailed logging**: The code already includes extensive logging. Check Xcode console when:
   - Tapping a user in the feed
   - ProfileView loading
   - Posts being fetched

2. **Check FeedView logs**:
   ```
   👤 [FeedView] User tapped - userID: 'abc123'
   ```

3. **Check ProfileView logs**:
   ```
   🔍 [ProfileView] Fetching posts for userID: 'abc123'
   📊 [ProfileView] Received 3 documents from Firebase
   ```

4. **Verify in Firestore Console**:
   - Open Firebase Console → Firestore
   - Find the `posts` collection
   - Look at a post document
   - Verify the `userID` field exists and has the correct value

5. **Test with a known post**:
   - Create a test post with a known userID
   - Navigate to that user's profile
   - Verify the post appears

## Code References

### Where userID is set in FeedView:
- Line ~814: `selectedUserID = uid`
- Line ~887: `ProfileView(userID: userId)`

### Where posts are queried in ProfileView:
- Line ~767: `db.collection("posts").whereField("userID", isEqualTo: uid)`

### Where posts are created:
- Check your post creation code (CameraView, RecordView, etc.)
- Ensure `userID` field is always set with current user's UID

## Additional Notes

- **Pagination**: ProfileView loads posts in pages (18 at a time by default)
- **Caching**: Posts are cached locally for faster loading
- **Pull to refresh**: Pull down on the profile to refresh posts
- **Real-time updates**: Currently not enabled - refresh manually to see new posts
