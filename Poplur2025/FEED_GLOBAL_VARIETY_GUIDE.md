# Feed Global Variety & Enhanced Map Navigation

## Changes Made

### 1. ✅ Global Cities - Posts from Around the World

**Problem**: All posts came from a small area (SF Bay Area), making the feed feel repetitive and local-only.

**Solution**: Expanded to **43 global cities** across all continents with diverse coordinates.

#### Cities Added (by continent):
- **Asia** (10): Tokyo, Seoul, Shanghai, Hong Kong, Singapore, Bangkok, Mumbai, Dubai, Delhi, Osaka
- **Europe** (10): London, Paris, Rome, Barcelona, Amsterdam, Berlin, Prague, Istanbul, Madrid, Vienna  
- **North America** (10): New York, San Francisco, LA, Chicago, Miami, Toronto, Vancouver, Mexico City, Seattle, Austin
- **South America** (5): São Paulo, Rio de Janeiro, Buenos Aires, Lima, Bogotá
- **Oceania** (3): Sydney, Melbourne, Auckland
- **Africa** (5): Cape Town, Cairo, Lagos, Nairobi, Marrakech

**Code Changes in `FeedView.swift` - `generateDemoPostsForCountryAndChannel()`**:

```swift
// Before: Limited to SF Bay Area
let baseLat = 37.3349 + variation
let baseLon = -122.0090 - variation

// After: Global cities array
let globalCities: [(name: String, lat: Double, lon: Double, country: String, flag: String)] = [
    ("Tokyo", 35.6762, 139.6503, "Japan", "🇯🇵"),
    ("London", 51.5074, -0.1278, "United Kingdom", "🇬🇧"),
    // ... 41 more cities
]

// Use cycling through cities
let city = globalCities[i % globalCities.count]
let latitude = city.lat + Double.random(in: -0.05...0.05)
let longitude = city.lon + Double.random(in: -0.05...0.05)
```

### 2. ✅ Expanded Radius Range - From Local to Near-Global

**Problem**: Radii were limited to 50m-5km, all posts felt very local.

**Solution**: Expanded range from **100m to 20,000km** (near Earth's circumference)!

#### Radius Distribution:
- **Local** (100m - 10km): 50% of posts - neighborhoods and cities
- **Regional** (25km - 1,000km): 35% of posts - regions and countries  
- **Continental to Near-Global** (2.5M - 20M): 15% of posts - continents and world

**Code Changes**:

```swift
// Before: Small range
let radius = [50, 100, 250, 500, 1000, 5000].randomElement() ?? 250

// After: Expanded range with weighted distribution
let radiusOptions: [Double] = [
    100, 250, 500, 1_000,              // Local (neighborhood)
    2_500, 5_000, 10_000,              // City/region
    25_000, 50_000, 100_000,           // Country
    250_000, 500_000, 1_000_000,       // Continental
    2_500_000, 5_000_000, 10_000_000,  // Multi-continental
    15_000_000, 20_000_000             // Near-global (Earth diameter ~12,742km)
]

// Weighted distribution
let radius: Double
let roll = Double.random(in: 0...1)
if roll < 0.5 {
    radius = radiusOptions.prefix(7).randomElement() ?? 5_000  // 50% local
} else if roll < 0.85 {
    radius = Array(radiusOptions[7...12]).randomElement() ?? 100_000  // 35% regional
} else {
    radius = Array(radiusOptions[13...]).randomElement() ?? 5_000_000  // 15% global
}
```

### 3. ⚠️ Enhanced Map Text - Needs Additional Changes

**Required**: When long-pressing from feed to map, display:
- ✅ Coordinates (lat/lon)
- ✅ Country flag 🇯🇵
- ✅ City name
- ✅ Username from uploader

**Current Status**: Data structures updated to include city/country info, but need to:
1. Add properties to FeedPost model
2. Update MapView to display enhanced information

#### Step 1: Update FeedPost Model

FeedPost needs these additional optional properties:

```swift
// Add to FeedPost definition (find where it's defined - likely in a Models file or typealias)
struct FeedPost: Identifiable, Hashable {
    let id: String
    let latitude: Double
    let longitude: Double
    let mediaURL: String
    let radius: Double
    let viewCount: Int
    let userID: String
    
    // ✅ NEW: Add these properties
    let cityName: String?
    let countryName: String?
    let countryFlag: String?
    
    // If FeedPost is actually a typealias for Post, add these to Post model instead
}
```

#### Step 2: Update Feed Long-Press Handler

In `FeedView.swift` - Update the `onLongPressGesture` notification to include city info:

```swift
.onLongPressGesture(minimumDuration: 0.5) {
    if let post = posts[safe: currentIndex] {
        let coordinate = CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude)
        
        Task {
            let username = await UsernameCache.shared.username(for: post.userID)
            
            // ✅ NEW: Include city and country information
            var userInfo: [String: Any] = [
                "coordinate": coordinate,
                "userID": post.userID,
                "username": username ?? displayName(for: post),
                "radius": Double(post.radius)
            ]
            
            // Add location metadata if available
            if let cityName = post.cityName {
                userInfo["cityName"] = cityName
            }
            if let countryName = post.countryName {
                userInfo["countryName"] = countryName
            }
            if let countryFlag = post.countryFlag {
                userInfo["countryFlag"] = countryFlag
            }
            
            // Store in MapStateManager
            MapStateManager.shared.setPendingPostLocation(
                coordinate,
                userID: post.userID,
                username: username ?? displayName(for: post),
                profileImageURL: profileImageURL,
                radius: Double(post.radius),
                cityName: post.cityName,      // ✅ NEW
                countryName: post.countryName, // ✅ NEW
                countryFlag: post.countryFlag  // ✅ NEW
            )
            
            // Post notification
            NotificationCenter.default.post(
                name: Notification.Name("ShowLocationOnMap"),
                object: nil,
                userInfo: userInfo
            )
        }
    }
}
```

#### Step 3: Update MapStateManager

Add city/country properties to `MapStateManager.swift`:

```swift
@Published var pendingPostCityName: String? = nil
@Published var pendingPostCountryName: String? = nil
@Published var pendingPostCountryFlag: String? = nil

func setPendingPostLocation(
    _ coordinate: CLLocationCoordinate2D,
    userID: String? = nil,
    username: String? = nil,
    profileImageURL: String? = nil,
    radius: Double? = nil,
    cityName: String? = nil,      // ✅ NEW
    countryName: String? = nil,   // ✅ NEW
    countryFlag: String? = nil    // ✅ NEW
) {
    // ... existing code ...
    pendingPostCityName = cityName
    pendingPostCountryName = countryName
    pendingPostCountryFlag = countryFlag
}
```

#### Step 4: Update MapView AI Text Display

In `MapView.swift` - Update the AI recommendation text when showing post location:

```swift
// In navigateWithTourTransition or ShowLocationOnMap handler:
if cityName == "Post Location" {
    // Extract location info from MapStateManager or notification
    let city = mapState.pendingPostCityName ?? "Unknown"
    let country = mapState.pendingPostCountryName ?? ""
    let flag = mapState.pendingPostCountryFlag ?? ""
    let username = mapState.pendingPostUsername ?? "User"
    let lat = String(format: "%.4f", coordinate.latitude)
    let lon = String(format: "%.4f", coordinate.longitude)
    
    // ✅ Enhanced AI text with all info
    currentCity = "\(flag) \(city), \(country)"
    aiRecommendation = "📍 \(lat)°, \(lon)° — \(username)'s post location"
}
```

Or format it in multiple lines:

```swift
// Alternative multi-line format:
currentCity = "\(flag) \(city)"
aiRecommendation = """
\(country) • \(username)
📍 \(lat)°, \(lon)°
Radius: \(Int(radius))m
"""
```

## Testing

### Test Global Variety:
1. Open Feed tab
2. Swipe through posts
3. ✅ Should see posts from Tokyo, Paris, Sydney, Cairo, etc.
4. ✅ Each post should have different coordinates
5. ✅ Console should log: "🌍 Generated GLOBAL feed posts from 43 cities"

### Test Radius Variety:
1. Watch radius bar as you scroll feed
2. ✅ Should see radii from 100m (local) to 20,000km (near-global)
3. ✅ Most posts should be 100m-10km (local feel)
4. ✅ Some posts should have huge radii (continental/global)
5. Check console: "Radius range: 100m to 20,000km"

### Test Enhanced Map Text (after completing steps above):
1. Long-press any post in feed
2. Map should open showing:
   - ✅ Country flag (e.g., 🇯🇵)
   - ✅ City name (e.g., "Tokyo")
   - ✅ Country name (e.g., "Japan")
   - ✅ Coordinates (e.g., "35.6762°, 139.6503°")
   - ✅ Username (e.g., "@username")
   - ✅ Radius (e.g., "5,000m")

## Next Steps

**To complete the enhanced map text feature**:

1. **Find FeedPost model definition** - Search project for where FeedPost/Post is defined
2. **Add new properties** - `cityName`, `countryName`, `countryFlag` (all optional String?)
3. **Update MapStateManager** - Add pending properties for city/country info  
4. **Update MapView** - Format AI text to show all location details
5. **Test end-to-end** - Long-press feed post → see enhanced map info

## Summary

✅ **Completed**:
- Global cities (43 locations across 6 continents)
- Expanded radius range (100m to 20,000km)
- Updated post generation with city metadata

⚠️ **Needs Completion**:
- FeedPost model update (add 3 properties)
- MapStateManager update (add 3 properties)
- MapView AI text formatting (use new location data)
- Feed long-press handler update (pass city data)

The foundation is in place - posts now come from around the world with diverse radii. The final step is wiring up the location metadata to display in the map view!
