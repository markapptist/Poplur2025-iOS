# Instagram Stories-Style Timeline Design

## Overview
The timeline view uses Instagram Stories format with fullscreen posts, profile headers, and swipeable carousel navigation.

## Visual Design

### Layout Structure
```
┌─────────────────────────────────┐
│ ▬▬▬▬ ▬▬▬ ▬▬▬ ▬▬▬ ▬▬▬          │ ← Progress bars
│                                 │
│ 👤 alexisfawxlive ✓  Follow •••│ ← Profile header
│    South Beach Miami            │
│                                 │
│                                 │
│                                 │
│        FULLSCREEN MEDIA         │ ← Photo/Video
│                                 │
│                                 │
│                                 │
│ ♡ 7,264  💬 255  ✈️ 35  📍 127 🔖│ ← Engagement
│                                 │
│ alexisfawxlive Which is your... │ ← Caption
│ 7 hours ago        🔵 5.0k m    │ ← Time + Radius
└─────────────────────────────────┘
```

## Key Components

### 1. Progress Indicators (Top)
- **White horizontal bars** showing position in feed
- **Current post** = solid white
- **Other posts** = 30% opacity
- **Spacing**: 4pt between bars
- **Height**: 3pt

### 2. Profile Header
**Avatar** (40x40pt):
- Gradient stroke ring (purple → pink → orange)
- Gray circle background
- Person icon placeholder
- 2pt stroke width

**Username**:
- 15pt semibold
- White color
- Verified badge (blue checkmark) if applicable

**Location**:
- City, Country name OR coordinates
- 13pt regular (city) / 11pt monospace (coords)
- 90% white opacity

**Follow Button**:
- "Follow" text
- 14pt semibold
- White on 20% white background
- 8pt padding vertical, 16pt horizontal
- 8pt corner radius

**More Menu** (•••):
- Ellipsis icon
- 18pt size
- White color

### 3. Fullscreen Media

**Images**:
- AspectRatio: fill
- Frame: full screen size
- Clipped to bounds
- Loading spinner while loading

**Videos**:
- AVPlayer with looping
- Starts muted (like Instagram)
- Auto-plays on appear
- Loops seamlessly
- Controls disabled

**Gradients**:
- **Top**: Black 70% → 30% → transparent (200pt)
- **Bottom**: Transparent → 30% → black 80% (300pt)

### 4. Engagement Bar

**Icons** (26pt):
- Heart (likes)
- Message bubble (comments)  
- Paperplane (shares)
- Location pin (sends)
- Bookmark (save)

**Counts**:
- 14pt semibold
- Format: 1,000 → 1.0k, 1,000,000 → 1.0M
- 6pt spacing between icon and count

**Layout**:
- 24pt spacing between groups
- Left-aligned (except bookmark on right)

### 5. Caption Area

**Username**: 14pt semibold white

**Caption Text**: 14pt regular 90% white

**"more" link**: 14pt regular 50% white

**Timestamp**:
- "X hours ago" format
- 12pt regular
- 50% white opacity

**Radius Indicator**:
- Blue filled circle (8pt)
- Distance text (12pt medium)
- 80% white opacity
- Right-aligned

## Interactions

### Gestures

**Swipe Left/Right**:
- Navigate between posts
- TabView with page style
- No index dots (custom progress bars instead)

**Tap Anywhere**:
- Dismiss timeline
- Return to fullscreen feed at current post
- Spring animation (0.3s, 0.8 damping)

**Long Press Profile**:
- Could show user profile (future enhancement)

### Animations

**Appearance**:
- Spring animation from FeedView
- 0.3s response, 0.8 damping

**Page Transition**:
- Native TabView page curl
- Smooth horizontal scrolling

**Video Playback**:
- Starts immediately on appear
- Pauses on disappear
- Loops seamlessly at end

## Implementation Details

### File Structure
```swift
FeedTimelineView
├── Body
│   ├── Progress Bars (HStack of Capsules)
│   ├── TabView (paging through posts)
│   │   └── StoriesStylePostView (for each post)
│   │       ├── Background Media
│   │       ├── Gradient Overlays
│   │       ├── Profile Header
│   │       ├── Engagement Bar
│   │       └── Caption Area
│   └── Tap Gesture (dismiss)
```

### Key State
- `currentIndex` - Tracks visible post
- `player` - AVPlayer for video posts
- `dragOffset` - For custom swipe tracking (if needed)

### Performance Optimizations
- **Lazy loading**: Only load visible post's media
- **Video cleanup**: Pause and nil player on disappear
- **Image caching**: AsyncImage handles caching
- **Gradient reuse**: Shared gradient views

## Differences from Grid Timeline

### Old Design (Grid)
- 3-column grid
- Small thumbnails
- Tap to view fullscreen
- Static layout
- No engagement metrics visible

### New Design (Stories)
- Fullscreen carousel
- One post at a time
- Swipe to navigate
- Rich profile info
- Full engagement display

## User Flow

```
Hold Cube (0.5s)
    ↓
Timeline appears (first post)
    ↓
┌────────────────────────────────┐
│ Swipe Right → Previous Post    │
│ Swipe Left → Next Post         │
│ Tap → Back to Feed             │
└────────────────────────────────┘
    ↓
Returns to fullscreen feed
(at selected post index)
```

## Accessibility

### VoiceOver Support
- Progress bars: "Post X of Y"
- Profile header: "User [name], location [location], follow button"
- Media: "Video" or "Image" with description
- Engagement: "Likes [count], Comments [count]..."
- Dismiss: "Tap to return to feed"

### Dynamic Type
- All text scales with user's text size preference
- Minimum size: 11pt
- Maximum size: 28pt (headers)

### Haptic Feedback
- Medium impact when timeline appears
- Light impact when swiping between posts (optional)
- Success haptic when dismissing

## Future Enhancements

1. **Story-like progress bars**
   - Auto-advance timer for images (5s)
   - Pause on touch hold
   - Videos play full duration before advancing

2. **Interactive elements**
   - Like button (double-tap or tap heart)
   - Comment button (show comments sheet)
   - Share button (native share sheet)
   - Profile button (navigate to user profile)

3. **Rich captions**
   - Expandable "more" link
   - @mentions and #hashtags
   - Link detection

4. **Video controls**
   - Tap to pause/play
   - Volume control
   - Scrubber bar (optional)

5. **3D effects**
   - Parallax on scroll
   - Depth blur on edges
   - Zoom on double-tap

## Testing Checklist

- [ ] Progress bars update as you swipe
- [ ] Videos autoplay and loop
- [ ] Images load correctly
- [ ] Tap anywhere dismisses to feed
- [ ] Swipe left/right navigates posts
- [ ] Profile info displays correctly
- [ ] Engagement counts format properly
- [ ] Radius indicator shows correct units
- [ ] Gradients are readable
- [ ] No memory leaks from video players

## Design Assets

### Colors
- Background: `Color.black`
- Text primary: `Color.white`
- Text secondary: `Color.white.opacity(0.9)`
- Text tertiary: `Color.white.opacity(0.5)`
- Accent (verified): `Color.blue`
- Accent (radius): `Color.blue`

### Typography
- Username: System Semibold 15pt
- Location: System Regular 13pt
- Engagement: System Semibold 14pt
- Caption: System Regular 14pt
- Timestamp: System Regular 12pt

### Spacing
- Screen padding: 16pt horizontal
- Element spacing: 6-24pt (contextual)
- Top offset: 60pt (below progress bars)
- Bottom offset: 100pt (above tab bar)
