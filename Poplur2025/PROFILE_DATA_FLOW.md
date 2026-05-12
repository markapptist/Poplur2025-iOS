# Profile Data Flow Diagram

## Complete Data Flow from Feed to Profile

```
┌─────────────────────────────────────────────────────────────────────┐
│ 1. Feed Posts Generation (FeedView.swift)                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  generateDemoPostsForCountryAndChannel(...)                        │
│    ├─ Create stable userIDs (every 3 posts = 1 user)              │
│    │  Example: posts 0,1,2 → "food_user_0"                        │
│    │           posts 3,4,5 → "food_user_1"                        │
│    │                                                                │
│    ├─ Generate 5 feed posts                                        │
│    │  [Post(userID: "food_user_0"), ...]                          │
│    │                                                                │
│    └─ FOR EACH unique user:                                        │
│         ├─ Generate 5-10 additional profile posts                  │
│         └─ Store immediately in DemoPostStore                      │
│                                                                     │
│  Result: DemoPostStore now contains ~50 posts total                │
│          - 5 shown in feed                                         │
│          - 45 hidden in profiles (9 posts × 5 users)               │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 2. Username Prefetching (FeedView.swift)                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  prefetchVisibleUsernames()                                        │
│    ├─ Extract all userIDs from posts                              │
│    │  ["food_user_0", "food_user_0", "food_user_0",              │
│    │   "food_user_1", "food_user_1", ...]                        │
│    │                                                                │
│    └─ Call UsernameCache.shared.prefetch(uids)                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 3. Username Cache Processing (UsernameCache.swift)                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  FOR EACH userID:                                                  │
│    ├─ Check if already cached → return immediately                │
│    │                                                                │
│    ├─ Detect if demo user (contains "_user_")                     │
│    │   └─ Generate readable name:                                 │
│    │      "food_user_0" → "FOOD USER 0"                          │
│    │      "fitness_user_1" → "FITNESS USER 1"                    │
│    │                                                                │
│    └─ Store in cache for instant retrieval                        │
│                                                                     │
│  Cache now contains:                                               │
│    { "food_user_0": "FOOD USER 0",                                │
│      "food_user_1": "FOOD USER 1", ... }                          │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 4. User Interaction (Feed → Profile)                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  User sees post in feed:                                           │
│    Username: "FOOD USER 0" ← fetched from cache                   │
│    Post content: [image/video]                                     │
│                                                                     │
│  User taps on "FOOD USER 0"                                        │
│    ├─ FeedView posts notification:                                │
│    │  NotificationCenter.post(                                     │
│    │    name: .ShowUserProfile,                                   │
│    │    object: "food_user_0"                                     │
│    │  )                                                             │
│    │                                                                │
│    └─ TabBarControllerHost receives notification                  │
│         ├─ Sets routedUserID = "food_user_0"                      │
│         └─ Switches to .profile tab                               │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 5. Profile View Update (ProfileView.swift)                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  .onChange(of: routedUserID) triggers:                            │
│    ├─ CLEAR ALL STATE:                                            │
│    │  displayUsername = nil                                       │
│    │  userProfile = nil                                           │
│    │  myPosts = []                                                │
│    │  loadedImages = [:]                                          │
│    │                                                                │
│    ├─ Reset radius bar to 0                                       │
│    │                                                                │
│    └─ Task {                                                       │
│         ├─ loadMyPosts()                                          │
│         │  ├─ Detect demo user: "food_user_0"                    │
│         │  ├─ Query DemoPostStore.posts(for: "food_user_0")      │
│         │  └─ Returns 8 posts (3 from feed + 5 profile posts)    │
│         │                                                           │
│         ├─ Fetch username from cache                              │
│         │  UsernameCache.username(for: "food_user_0")            │
│         │  → Returns "FOOD USER 0" (instant, already cached!)     │
│         │                                                           │
│         └─ Update radius bar with total radius                    │
│       }                                                             │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 6. Profile Display (ProfileView.swift)                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Profile view shows:                                               │
│    ┌─────────────────────────────────────┐                        │
│    │ ← Feed        FOOD USER 0           │ ← From cache           │
│    ├─────────────────────────────────────┤                        │
│    │ [Avatar placeholder]                │                        │
│    │                                      │                        │
│    │ Grid of 8 posts:                    │ ← From DemoPostStore   │
│    │  ┌────┬────┬────┐                   │                        │
│    │  │ 1  │ 2  │ 3  │ ← feed posts      │                        │
│    │  ├────┼────┼────┤                   │                        │
│    │  │ 4  │ 5  │ 6  │ ← profile posts   │                        │
│    │  ├────┼────┼────┤                   │                        │
│    │  │ 7  │ 8  │    │                   │                        │
│    │  └────┴────┴────┘                   │                        │
│    └─────────────────────────────────────┘                        │
│                                                                     │
│  ALL DATA MATCHES because:                                         │
│    ✓ Posts pre-generated with correct userID                      │
│    ✓ Username pre-cached from feed                                │
│    ✓ Profile posts stored in DemoPostStore before user clicks     │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Insights

### Why Posts Match Now
**Before:** Each feed post had a unique userID like `"food_user_0"`, `"food_user_1"`, `"food_user_2"`, etc.
- When you clicked on a profile, DemoPostStore only had that ONE post
- Profile appeared empty or had just 1 post

**After:** Every 3 feed posts share the same userID (`"food_user_0"`)
- Post 0, 1, 2 → all have `userID = "food_user_0"`
- When generating posts, we ALSO create 5-10 additional posts with the same userID
- DemoPostStore now has 8+ posts for `"food_user_0"` BEFORE you click
- Profile shows all posts belonging to that user

### Why Usernames Match Now
**Before:** Usernames were fetched lazily only when needed
- Feed shows "User abc123" (partial userID)
- Click profile → fetches from Firebase → might fail → shows different name

**After:** Usernames are prefetched and cached
- Feed loads → immediately calls `UsernameCache.prefetch()` with all userIDs
- Demo users get auto-generated names: `"food_user_0"` → `"FOOD USER 0"`
- Cache stores: `{ "food_user_0": "FOOD USER 0" }`
- Feed displays: "FOOD USER 0" ← from cache
- Click profile → fetches from cache → "FOOD USER 0" ← SAME NAME!

### Why Profile Updates Immediately
**Before:** `.onChange(of: routedUserID)` only reloaded if different from current
- State wasn't cleared between users
- Old data remained visible

**After:** `.onChange(of: routedUserID)` ALWAYS clears state
- Sets everything to nil/empty
- Forces complete reload
- Fetches fresh data from DemoPostStore
- Updates UI with correct information

## Data Consistency Guarantees

1. **Feed Post Generation** → Creates stable userIDs (every 3 posts = 1 user)
2. **Profile Post Generation** → Pre-creates 5-10 posts per user with same userID
3. **DemoPostStore** → Stores ALL posts (feed + profile) before user interaction
4. **Username Cache** → Pre-generates names for ALL demo users
5. **Profile View** → Queries DemoPostStore by userID → gets ALL matching posts
6. **Display** → Shows cached username + all user's posts

Result: **Perfect data consistency** between feed and profile! 🎉
