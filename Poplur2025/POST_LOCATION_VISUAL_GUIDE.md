# Post Location Map Feature - Visual Guide

## 📱 User Experience Flow

```
┌─────────────────────────────────────────────────────────┐
│                    FEED VIEW                            │
│  ┌─────────────────────────────────────────────────┐   │
│  │                                                   │   │
│  │         [Post Video/Image]                       │   │
│  │                                                   │   │
│  │  👆 User long-presses on post                    │   │
│  │     (0.5 second hold)                            │   │
│  │                                                   │   │
│  │  💚 Haptic feedback fires                        │   │
│  │                                                   │   │
│  │  Username: @traveler_tokyo                       │   │
│  │  📍 35.6762, 139.6503                            │   │
│  │                                                   │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                        ⬇️
          Notification: ShowLocationOnMap
                        ⬇️
┌─────────────────────────────────────────────────────────┐
│              TRANSITION TO MAP                          │
│                                                          │
│  ⚡️ Smooth cross-dissolve animation                    │
│  🎬 Camera begins tour-style transition:               │
│     1️⃣ Zoom out from current location                  │
│     2️⃣ Pan to post coordinate                          │
│     3️⃣ Zoom in to post location                        │
│                                                          │
└─────────────────────────────────────────────────────────┘
                        ⬇️
┌─────────────────────────────────────────────────────────┐
│                     MAP VIEW                            │
│  ┌─────────────────────────────────────────────────┐   │
│  │                                                   │   │
│  │        🗺️ Map centered on post location         │   │
│  │                                                   │   │
│  │         ┌───────────────────────────┐            │   │
│  │         │  @traveler_tokyo          │            │   │
│  │         │  35.6762, 139.6503        │            │   │
│  │         │  🇯🇵 Tokyo, Japan          │            │   │
│  │         │  📏 Radius: 5.0 km        │            │   │
│  │         │                           │            │   │
│  │         │  ┌───────────────────┐   │            │   │
│  │         │  │ ⬅️ Back to Feed   │   │            │   │
│  │         │  └───────────────────┘   │            │   │
│  │         └───────────────────────────┘            │   │
│  │                     │                             │   │
│  │                     ▼                             │   │
│  │              ╭─────────────╮                      │   │
│  │              │  🟣 Purple  │                      │   │
│  │              │     Pin     │                      │   │
│  │              ╰─────────────╯                      │   │
│  │                                                   │   │
│  │         ⭕️ Purple radius circle                  │   │
│  │            (5km visualization)                    │   │
│  │                                                   │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## 🎨 Annotation Callout Design

```
┌──────────────────────────────────────┐
│                                      │  ← Ultra-thin material background
│  @traveler_tokyo                     │  ← Username (bold, 16pt, rounded)
│  35.6762, 139.6503                   │  ← Coordinates (13pt, monospaced)
│  🇯🇵 Tokyo, Japan                     │  ← Location (13pt with flag emoji)
│  📏 Radius: 5.0 km                   │  ← Radius (13pt, purple)
│                                      │
│  ┌──────────────────────────────┐   │
│  │ ⬅️ Back to Feed              │   │  ← Button (14pt, white on purple)
│  └──────────────────────────────┘   │
│                                      │
└──────────────────────────────────────┘
            │
            ▼
     ╭─────────────╮
     │     🟣      │  ← Purple pin marker (44pt)
     │   Pin Icon  │
     ╰─────────────╯
```

## 🎯 Map Elements

### 1. **Radius Circle**
```
⭕️ MapCircle Properties:
   - Center: Post coordinate
   - Radius: Post radius in meters
   - Fill: Purple with 15% opacity
   - Stroke: Purple with 50% opacity, 2pt width
   - Scales automatically with zoom
```

### 2. **Pin Marker**
```
📍 Pin Design:
   ┌─────────────┐
   │   ⚪️ Halo   │  60pt diameter, purple 30% opacity
   │    ├─┤      │
   │   │ 🟣 │    │  mappin.circle.fill, 44pt
   │    └─┘      │  Purple foreground, white background
   └─────────────┘  3pt shadow radius
```

### 3. **Information Card**
```
📋 Card Layout:
   ┌──────────────────────────────┐
   │ Padding: 12pt all sides      │
   │ Corner radius: 16pt          │
   │ Material: .ultraThinMaterial │
   │ Shadow: 8pt blur, 4pt y      │
   │                              │
   │ Stack spacing: 8pt vertical  │
   └──────────────────────────────┘
```

## 🔄 State Flow Diagram

```
┌─────────────────┐
│   FeedView      │
│  (Long Press)   │
└────────┬────────┘
         │
         │ Gather metadata:
         │ • coordinate (CLLocationCoordinate2D)
         │ • username (String)
         │ • radius (Double)
         │ • cityName (String?)
         │ • countryName (String?)
         │ • countryFlag (String?)
         │
         ▼
┌─────────────────────────────┐
│  MapStateManager            │
│  .setPendingPostLocation()  │
└──────────┬──────────────────┘
           │
           │ Store for later if
           │ MapView not loaded
           │
           ▼
┌─────────────────────────────┐
│  NotificationCenter         │
│  Post: ShowLocationOnMap    │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  MapView                    │
│  .onReceive(...)            │
└──────────┬──────────────────┘
           │
           ├─► Set lock windows (15s)
           ├─► Store post metadata
           ├─► Enter showingPostLocation mode
           ├─► Navigate with tour transition
           └─► Display annotation
```

## 📊 Metadata Structure

```swift
// Notification userInfo dictionary
[
    "coordinate": CLLocationCoordinate2D,  // Required
    "userID": String,                      // Required
    "username": String,                    // Required
    "radius": Double,                      // Required
    "cityName": String?,                   // Optional
    "countryName": String?,                // Optional
    "countryFlag": String?,                // Optional (emoji)
    "profileImageURL": String?             // Optional
]

// MapView state
shownPostCoordinate: CLLocationCoordinate2D?
shownPostRadius: Double?
shownPostUsername: String?
shownPostCityName: String?
shownPostCountryName: String?
shownPostCountryFlag: String?

// MapStateManager pending state
pendingPostLocation: CLLocationCoordinate2D?
pendingPostUserID: String?
pendingPostUsername: String?
pendingPostProfileImageURL: String?
pendingPostRadius: Double?
pendingPostCityName: String?
pendingPostCountryName: String?
pendingPostCountryFlag: String?
```

## 🎬 Animation Timeline

```
Time  │ Action
──────┼─────────────────────────────────────────────
0.0s  │ Long press gesture completes
      │ ↓ Haptic feedback
      │ ↓ Notification posted
──────┼─────────────────────────────────────────────
0.15s │ Tab switch animation begins
      │ ↓ Cross-dissolve to map tab
──────┼─────────────────────────────────────────────
0.3s  │ Map view appears
      │ ↓ Camera starts zoom-out
──────┼─────────────────────────────────────────────
1.1s  │ Zoom-out completes (0.8s duration)
      │ ↓ Pan starts
──────┼─────────────────────────────────────────────
2.6s  │ Pan completes (1.5s duration)
      │ ↓ Zoom-in starts
──────┼─────────────────────────────────────────────
3.8s  │ Zoom-in completes (1.2s duration)
      │ ↓ Annotation visible
      │ ↓ Radius circle visible
      │ ↓ Pin marker centered
──────┼─────────────────────────────────────────────
4.1s  │ Radius updates smoothly (0.3s delay)
      │ ✅ Navigation complete
──────┼─────────────────────────────────────────────
```

## 🔒 Lock Windows

```
┌────────────────────────────────────────────────┐
│  When navigating to post location:            │
│                                                │
│  suppressUserCenteringUntil = now + 15s       │
│  ├─► Prevents auto-centering on user         │
│  └─► Checked by all location update handlers │
│                                                │
│  lockToPostUntil = now + 15s                  │
│  ├─► Prevents camera resets                  │
│  └─► Checked by onAppear, tab switch, etc.   │
│                                                │
│  Result: User sees post location uninterrupted│
└────────────────────────────────────────────────┘
```

## 🎯 Button Actions

### Back to Feed Button
```
┌──────────────────────────────────┐
│ User taps "Back to Feed"         │
└────────┬─────────────────────────┘
         │
         ├─► Clear shownPostCoordinate
         ├─► Clear shownPostRadius
         ├─► Clear shownPostUsername
         ├─► Clear shownPostCityName
         ├─► Clear shownPostCountryName
         ├─► Clear shownPostCountryFlag
         │
         ├─► mapState.cancelCurrentOperation()
         │   └─► Returns to .browsing mode
         │
         └─► Post: SwitchToFeedTab notification
             └─► HomeView switches selectedTab = .feed
```

## 🎨 Color Palette

```
🟣 Purple Theme:
   - Primary: Color.purple
   - Pin background: purple.opacity(0.3)
   - Circle fill: purple.opacity(0.15)
   - Circle stroke: purple.opacity(0.5)
   - Button background: Color.purple (solid)
   - Text accent: .purple

⚪️ Neutral Colors:
   - Pin icon: White
   - Button text: White
   - Card background: .ultraThinMaterial
   - Primary text: .primary (system)
   - Secondary text: .secondary (system)
```

## 📐 Dimensions Reference

```
Pin Marker:
  • Halo circle: 60pt diameter
  • Icon size: 44pt
  • Shadow radius: 3pt

Information Card:
  • Corner radius: 16pt
  • Padding: 12pt
  • Shadow blur: 8pt
  • Shadow offset: (0, 4)
  • Vertical spacing: 8pt

Text Sizes:
  • Username: 16pt bold
  • Coordinates: 13pt medium
  • Location: 13pt medium
  • Radius: 13pt medium
  • Button: 14pt semibold
  • Button icon: 13pt

Button:
  • Horizontal padding: 14pt
  • Vertical padding: 8pt
  • Shape: Capsule
  • Icon spacing: 6pt
```

## ✅ Feature Checklist

- [x] Long press on post triggers navigation
- [x] Haptic feedback on long press
- [x] Smooth camera transition (zoom out → pan → zoom in)
- [x] Purple pin marker at exact coordinate
- [x] Radius circle visualization
- [x] Rich annotation callout with:
  - [x] Username
  - [x] Coordinates (formatted)
  - [x] City and country with flag emoji
  - [x] Radius (formatted as m or km)
- [x] "Back to Feed" button
- [x] 15-second lock windows prevent interruption
- [x] Works from both feed tab and when map not loaded
- [x] Clears state when returning to feed
- [x] Respects dark/light mode (material backgrounds)
- [x] Accessible (proper labels and button roles)

---

**This implementation provides a polished, production-ready map navigation feature!** 🎉
