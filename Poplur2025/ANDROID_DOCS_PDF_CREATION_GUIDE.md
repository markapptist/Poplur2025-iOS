# Android Documentation - PDF Creation Guide

## Overview
This guide explains how to create professional PDF documents with screenshots and diagrams for the Android development team.

---

## Required Documents

### 1. Home View Tab System PDF
**Filename**: `HomeView_Tabs_Specification.pdf`

**Required Screenshots**:
- [ ] Each tab face of the 3D cube (Map, Record, Feed, Profile)
- [ ] Cube rotation animation sequence (4-5 frames)
- [ ] Swipe gesture directions with arrows
- [ ] Tab content for each view

**Required Diagrams**:
- [ ] Cube face mapping diagram showing yaw angles (0°, 90°, 180°, 270°)
- [ ] Tab rotation order flowchart
- [ ] Gesture interaction flowchart

---

### 2. Cube 3D Navigation PDF  
**Filename**: `Cube_3D_Navigation_Specification.pdf`

**Required Screenshots**:
- [ ] Cube in neutral state
- [ ] Cube during rotation (motion blur/transition)
- [ ] Cube with each face highlighted
- [ ] Cube showing glow effects
- [ ] Cube showing normal maps and lighting
- [ ] Cube showing materials and textures

**Required Diagrams**:
- [ ] 3D coordinate system showing pitch, yaw, roll
- [ ] Cube geometry with dimensions (1.3 x 1.3 x 1.3, chamfer 0.25)
- [ ] Face texture layout (diffuse, emission, normal maps)
- [ ] Lighting setup diagram (directional, omni, ambient)
- [ ] Material layer breakdown (diffuse → multiply → emission → normal)

---

## Recommended Tools

### Option 1: Pages (macOS) - **RECOMMENDED**
**Why**: Native Apple tool with excellent template support

**Steps**:
1. Create new Pages document from template
2. Insert screenshots using Simulator → Cmd+Shift+4
3. Add annotations with built-in shapes/arrows
4. Export as PDF: File → Export To → PDF

**Benefits**:
- Professional templates
- Easy annotation tools
- Vector graphics support
- Perfect for technical docs

---

### Option 2: Keynote (macOS) → PDF
**Why**: Great for visual, image-heavy documentation

**Steps**:
1. Create presentation with one section per topic
2. Add screenshots to slides with annotations
3. Use shapes and arrows to explain interactions
4. Export as PDF: File → Export To → PDF

**Benefits**:
- Easy layout control
- Professional appearance
- Animation can show transitions
- Great for showing sequences

---

### Option 3: Xcode Playground with Markup → PDF
**Why**: Code examples with visual output

**Steps**:
1. Create Xcode Playground
2. Use markup comments for documentation
3. Add QuickLook results for visual examples
4. Print → Save as PDF

**Benefits**:
- Executable code examples
- Live SwiftUI previews
- Can show actual rendering

---

### Option 4: Markdown → PDF via Pandoc
**Why**: Automated conversion from existing markdown

**Command**:
```bash
# Install pandoc first: brew install pandoc
pandoc ANDROID_DOCS_HomeView_Tabs.md -o HomeView_Tabs_Specification.pdf \
  --pdf-engine=xelatex \
  --toc \
  --toc-depth=3 \
  --variable=geometry:margin=1in \
  --variable=fontsize:11pt \
  --variable=mainfont:"SF Pro Text"
```

**Benefits**:
- Automated conversion
- Table of contents
- Consistent formatting
- Can embed images via markdown

---

## Screenshot Capture Strategy

### 1. Use iOS Simulator
```bash
# Launch specific device
xcrun simctl boot "iPhone 15 Pro"

# Open in Simulator app
open -a Simulator

# Run your app
xcodebuild -project Poplur2025.xcodeproj -scheme Poplur2025 \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' run
```

### 2. Capture Screenshots
**Method A**: Simulator menu → Device → Screenshot (Cmd+S)
**Method B**: Command line:
```bash
xcrun simctl io booted screenshot screenshot.png
```

### 3. Record Video for Animations
```bash
# Start recording
xcrun simctl io booted recordVideo --codec=h264 cube_rotation.mov

# Stop recording (Ctrl+C)
# Convert to GIF for documentation
ffmpeg -i cube_rotation.mov -vf "fps=10,scale=320:-1:flags=lanczos" cube_rotation.gif
```

---

## Screenshot Checklist

### Home View Screenshots
- [ ] Feed tab showing vertical feed
- [ ] Record tab showing camera preview
- [ ] Profile tab showing post grid
- [ ] Map tab showing 3D map view
- [ ] Cube showing Map face (270°)
- [ ] Cube showing Record face (0°)
- [ ] Cube showing Feed face (90°)
- [ ] Cube showing Profile face (180°)
- [ ] Radius bar at 0km
- [ ] Radius bar at 1,000km
- [ ] Radius bar at 3,323km (max)
- [ ] Upload status overlay (uploading)
- [ ] Upload status overlay (success)
- [ ] Upload status overlay (error)

### Camera/Record Tab Screenshots
- [ ] Camera preview with ML detection overlay
- [ ] AR filter selector (horizontal strip at bottom)
- [ ] Recording countdown UI (10, 9, 8... seconds)
- [ ] Camera roll button (bottom-left)
- [ ] Flash ON indicator
- [ ] Flash OFF indicator
- [ ] Face detection with user recognition
- [ ] Object detection with emoji icons

### Feed Tab Screenshots
- [ ] Single post in feed
- [ ] Country indicator (flag + name)
- [ ] Channel indicator (category emoji)
- [ ] Post with username, radius, likes, comments
- [ ] Timeline/grid view
- [ ] Horizontal swipe transition (country change)
- [ ] Vertical swipe transition (post change)
- [ ] White Feed launch loading screen with centered animated Poplur logo
- [ ] Mixed image/video/sponsored-ad first page
- [ ] Feed custom volume bars after hardware volume up/down

### Profile Tab Screenshots
- [ ] Own profile header (with edit button)
- [ ] Other user profile (with message button)
- [ ] Post grid (3 columns)
- [ ] Expanded post view
- [ ] Profile statistics (radius, post count)

### Map Tab Screenshots
- [ ] Hybrid map style with 3D buildings
- [ ] AI recommendations overlay
- [ ] User location marker
- [ ] Long-press location selection
- [ ] Map camera at 60° pitch, 700m altitude

### Cube 3D Detail Screenshots
- [ ] Cube wireframe overlay
- [ ] Cube with normal map (bumpy surface)
- [ ] Cube with emission glow
- [ ] Cube chamfered corners closeup
- [ ] Cube rotation motion blur
- [ ] Cube lighting setup (multiple angles)

---

## Diagram Creation

### Use SF Symbols for Icons
All icons reference SF Symbols, which Android team can map to Material Icons:

| iOS (SF Symbol) | Android (Material Icon) |
|----------------|------------------------|
| `map.fill` | `map` |
| `video.circle.fill` | `videocam` |
| `list.bullet.rectangle.portrait.fill` | `view_list` |
| `person.circle.fill` | `account_circle` |

### Create Architecture Diagrams
**Tool**: Omnigraffle, Sketch, Figma, or Draw.io

**Diagrams Needed**:
1. **App Navigation Flow**
   - Start → Login → HomeView → Tabs
   - Tab switching logic
   - Cross-tab navigation (e.g., Feed username tap → Profile)

2. **Cube State Machine**
   - States: Idle, Rotating, Settling
   - Transitions: Swipe, Tap, Hold
   - Animations per state

3. **Recording Flow**
   - Tap cube → Take photo → Select location → Upload → Profile
   - Hold cube (2s) → Record video (10s) → Select location → Upload → Profile

4. **ML Detection Pipeline**
   - Camera frame → Vision → CoreML → Detection → UI overlay
   - User recognition → Face detection → Firestore lookup → Radius display

5. **Radius Bar State Machine**
   - States: Idle, Growing, Draining, Animating
   - Events: Hold began, Hold ended, Tab changed, Post changed

---

## Annotation Guide

### Use Consistent Annotation Style
**Colors**:
- **Red**: User interaction points (tap, swipe, hold)
- **Blue**: Data flow / Information display
- **Green**: Success states / Completion
- **Yellow**: Warnings / Important notes
- **Orange**: Time-based actions (countdown, recording)

**Shapes**:
- **Circle**: Tap targets
- **Arrow**: Direction of motion/flow
- **Rectangle**: UI regions / Hit areas
- **Dashed line**: Optional / Conditional paths

---

## PDF Structure Template

### Document 1: HomeView Tabs

```
Cover Page
- Title: "Home View Tab System Specification"
- Subtitle: "For Android Recreation"
- Date
- Version

Table of Contents

1. Overview
   1.1 Tab Structure
   1.2 Navigation Methods
   1.3 Default State

2. Cube Interface
   2.1 3D Geometry
   2.2 Face Mapping
   2.3 Rotation Mechanics
   2.4 Visual Effects

3. Tab Details
   3.1 Map Tab
   3.2 Record Tab
   3.3 Feed Tab
   3.4 Profile Tab

4. Shared Components
   4.1 Radius Bar
   4.2 Upload Status
   4.3 Camera Roll Button

5. Interactions
   5.1 Gestures
   5.2 Notifications
   5.3 State Management

6. Implementation Notes
   6.1 Android Architecture
   6.2 Framework Mapping
   6.3 Firebase Integration

Appendix A: Data Models
Appendix B: API Endpoints
Appendix C: Asset List
```

### Document 2: Cube Specification

```
Cover Page
- Title: "3D Cube Navigation Specification"
- Subtitle: "Geometry, Materials, and Animations"
- Date
- Version

Table of Contents

1. Overview
   1.1 Purpose
   1.2 Technical Requirements

2. Geometry
   2.1 Dimensions
   2.2 Chamfered Edges
   2.3 Face Layout

3. Materials
   3.1 Diffuse Layer
   3.2 Emission Layer
   3.3 Normal Map
   3.4 Tint/Multiply Layer

4. Lighting
   4.1 Directional Light
   4.2 Omni Light
   4.3 Ambient Light
   4.4 IBL Environment

5. Animations
   5.1 Rotation Curves
   5.2 Pop/Scale Effect
   5.3 Glow Particles
   5.4 Motion Response

6. Android Implementation
   6.1 OpenGL ES Setup
   6.2 Material Shaders
   6.3 Animation Controllers
   6.4 Gesture Handlers

Appendix A: Texture Assets
Appendix B: Shader Code
Appendix C: Animation Curves
```

---

## Asset Export

### Export All Visual Assets

Create an `android_assets/` folder with:

```
android_assets/
├── screenshots/
│   ├── home/
│   │   ├── tab_map.png
│   │   ├── tab_record.png
│   │   ├── tab_feed.png
│   │   ├── tab_profile.png
│   │   ├── radius_bar_0km.png
│   │   ├── radius_bar_1000km.png
│   │   └── radius_bar_max.png
│   ├── cube/
│   │   ├── face_map.png
│   │   ├── face_record.png
│   │   ├── face_feed.png
│   │   ├── face_profile.png
│   │   ├── rotation_sequence/
│   │   │   ├── frame_001.png
│   │   │   ├── frame_002.png
│   │   │   └── ...
│   │   └── effects/
│   │       ├── normal_map.png
│   │       ├── emission.png
│   │       └── glow.png
│   ├── camera/
│   │   ├── ml_detection.png
│   │   ├── ar_filters.png
│   │   ├── recording_countdown.png
│   │   └── flash_indicators.png
│   └── ui_components/
│       ├── upload_status_uploading.png
│       ├── upload_status_success.png
│       └── upload_status_error.png
├── diagrams/
│   ├── cube_face_mapping.pdf
│   ├── navigation_flow.pdf
│   ├── recording_flow.pdf
│   └── architecture.pdf
└── textures/
    ├── CubeNormalMap.png
    ├── CubeEnv.png
    └── earth_day.png
```

---

## Final PDF Assembly

### Combine Everything in Pages

1. **Import markdown content** as structured text
2. **Add screenshots** at relevant sections
3. **Embed diagrams** inline
4. **Add code blocks** with syntax highlighting
5. **Include asset references** with thumbnails
6. **Export as PDF** with table of contents

### Quality Checklist
- [ ] All images at 2x resolution (Retina)
- [ ] Consistent margins (1 inch)
- [ ] Readable code font (SF Mono, 10pt minimum)
- [ ] Page numbers
- [ ] Hyperlinked table of contents
- [ ] Bookmarks for major sections
- [ ] Embedded fonts for consistency

---

## Distribution

### Share with Android Team

**Option 1**: Add PDFs to project repo
```bash
git add ANDROID_DOCS_HomeView_Tabs.pdf
git add ANDROID_DOCS_Cube_Specification.pdf
git add android_assets/
git commit -m "Add Android documentation with visuals"
git push
```

**Option 2**: Host on shared drive (Google Drive, Dropbox)

**Option 3**: Create Confluence/Notion pages with embedded PDFs

---

## Maintenance

### Keep Docs Updated
- Update PDFs when UI changes
- Version PDFs (v1.0, v1.1, etc.)
- Track changes in CHANGELOG
- Regular review cycles with Android team

---

## Contact

For questions about this documentation:
- iOS Lead: [Your Name]
- Android Lead: [Their Name]
- Design Lead: [Designer Name]

Last Updated: June 1, 2026
