# 3D Cube Navigation Specification
## For Android Recreation

---

## Overview

The app uses a **3D rotating cube** as the primary navigation interface, replacing traditional bottom tab bars. Each face of the cube represents a different tab, and users rotate the cube via gestures to switch between views.

### Key Characteristics
- **Geometry**: Chamfered box (rounded edges) with 6 faces
- **Materials**: Multi-layer with diffuse, emission, normal maps, and tint
- **Lighting**: Physically-based rendering with multiple light sources
- **Animations**: Smooth rotation with overshoot/settle physics
- **Interactions**: Pan (rotate), tap (action), hold (record)

---

## Cube Geometry

### Dimensions
```swift
SCNBox(
    width: 1.3,      // X axis (scene units)
    height: 1.3,     // Y axis (scene units)
    length: 1.3,     // Z axis (scene units)
    chamferRadius: 0.25  // Rounded corner radius
)
```

**Chamfer Settings**:
- **Segment Count**: 8 (determines smoothness of rounded corners)
- **Effect**: Soft, rounded edges instead of sharp 90° corners

### Coordinate System (SceneKit)
- **+X**: Right
- **+Y**: Up
- **+Z**: Toward viewer
- **Rotation**: Euler angles in radians

### Pivot Point
- **Location**: Center of cube (0, 0, 0)
- **Effect**: Rotation happens around the geometric center

---

## Face Layout & Mapping

The cube has 6 faces, but we only use 4 for tab navigation:

| Face | Axis | Tab | Yaw Angle | Icon SF Symbol |
|------|------|-----|-----------|----------------|
| Front | +Z | Record | 0° | `video.circle.fill` |
| Right | +X | Feed | 90° | `list.bullet.rectangle.portrait.fill` |
| Back | -Z | Profile | 180° | `person.circle.fill` |
| Left | -X | Map | 270° | `map.fill` |
| Top | +Y | (unused) | N/A | — |
| Bottom | -Y | (unused) | N/A | — |

### Face Content
Each face displays:
1. **Icon**: Large SF Symbol (80pt, bold weight)
2. **Title**: Tab name below icon (24pt, heavy weight)
3. **Background**: Rounded rectangle with 24pt corner radius
4. **Glow**: Soft white halo behind icon (for depth)

### Face Generation
Faces are **procedurally generated** using `UIGraphicsImageRenderer`:
```swift
// Pseudo-code for face generation
let size = CGSize(width: 300, height: 300)
let icon = UIImage(systemName: "map.fill", pointSize: 80, weight: .bold)
let title = "Map"

// Draw:
// 1. Rounded rect background (white)
// 2. Glow layer (white @ 25% opacity)
// 3. Icon (white, centered)
// 4. Title text (white, 24pt heavy, centered below icon)
```

---

## Material Layers

The cube uses **multi-channel materials** for rich appearance:

### Layer 1: Diffuse (Base Geometry)
- **Content**: Face image with white background and icon/text
- **Purpose**: Defines the visible shape and form
- **Intensity**: 1.0 (full opacity)

### Layer 2: Multiply (Tint Color)
- **Content**: Solid color (UIColor)
- **Purpose**: Applies color tint to the entire face
- **Default**: Indigo (`#5856D6`)
- **Intensity**: 0.75
- **Effect**: Multiplies with diffuse, tinting white to indigo

### Layer 3: Emission (Self-Illumination)
- **Content**: Face image with ONLY icon and text (no background)
- **Purpose**: Makes icon/text glow from within
- **Intensity**: 0.5 (production), 0.4 (preview)
- **Effect**: Adds light without requiring external lights

### Layer 4: Normal Map (Surface Detail)
- **Content**: Tangent-space normal map texture (`CubeNormalMap`)
- **Purpose**: Simulates bumpy/textured surface without geometry
- **Intensity**: 0.6 (production), 2.0 (preview)
- **Effect**: Creates illusion of depth and surface variation

### Additional Properties
- **Metalness**: 0.15 (slight metallic reflection)
- **Roughness**: 0.8 (mostly matte, not shiny)
- **Double-sided**: false (only front faces visible)
- **Specular**: White @ 20% opacity (subtle highlights)
- **Shininess**: 0.3 (low glossiness)

---

## Lighting Setup

### Light 1: Directional (Key Light)
```swift
type: .directional
intensity: 80
eulerAngles: (30° pitch, -45° yaw, 0° roll)
castsShadow: false
```
**Purpose**: Primary lighting from top-left

### Light 2: Omni (Fill Light)
```swift
type: .omni
intensity: 40
position: (-2, 1.5, 3) // Left-forward-up
castsShadow: false
```
**Purpose**: Soften shadows, fill dark areas

### Light 3: Image-Based Lighting (IBL)
```swift
scene.lightingEnvironment.contents: UIImage(named: "CubeEnv")
scene.lightingEnvironment.intensity: 0.35 (preview), 0.30 (PBR), 0.15 (Blinn/Lambert)
```
**Purpose**: Reflections and ambient lighting from environment map

### Camera
```swift
type: SCNCamera
position: (0, 0, 5.0) // Pull back to reduce distortion
fieldOfView: 40° // Narrower FOV for less fisheye
projection: Perspective (not orthographic)
```

---

## Rotation Mechanics

### Yaw-Only Rotation
The cube rotates **only around the Y-axis (yaw)**, not pitch or roll. This keeps faces always "upright" and square to the screen.

### Rotation Angles per Tab
```swift
func yawForTab(_ tab: AppTab) -> Double {
    switch tab {
    case .record: return 0.0
    case .feed: return 90.0
    case .profile: return 180.0
    case .map: return 270.0
    }
}
```

### Animation Curve
**Type**: Timing curve (cubic Bézier)
```swift
Animation.timingCurve(
    0.2, 0.8, // Control point 1 (ease in)
    0.2, 1.0, // Control point 2 (ease out)
    duration: 0.45
)
```

### Overshoot/Bounce
When user releases pan gesture, cube snaps to nearest face with bounce:
```swift
// Overshoot by 12% past target
let overshoot: CGFloat = 0.12
// Animate to target + overshoot (duration: 0.18s)
// Then animate back to target (duration: 0.22s)
```

### Continuous Rotation from Pan
During pan gesture:
```swift
// User drags horizontally
let deltaX = gesture.translation.width
let radiansPerPoint: Float = Float.pi / 360 // ~0.5° per point

// Update yaw continuously
currentYaw += deltaX * radiansPerPoint
cube.eulerAngles.y = currentYaw
```

---

## Gesture Handling

### Gesture 1: Pan (Rotate)
**Type**: `UIPanGestureRecognizer`
**Trigger**: Drag left/right on cube area
**Effect**: Rotate cube proportionally to drag distance
**Snap**: On `.ended`, snap to nearest face (45° increments)

**Sensitivity**:
- `panThreshold`: 10 points (minimum distance to start)
- `radiansPerPoint`: π/360 ≈ 0.0087 radians/point

### Gesture 2: Tap (Action)
**Type**: `UITapGestureRecognizer`
**Trigger**: Single tap on cube
**Effect**: Execute tab-specific action:
- **Record tab**: Take photo
- **Map tab**: Center on user location
- **Feed tab**: Scroll to top
- **Profile tab**: Scroll to top

### Gesture 3: Long Press (Hold)
**Type**: `UILongPressGestureRecognizer`
**Trigger**: Hold cube for 0.5 seconds
**Effect**: 
- **Record tab**: Start recording video + countdown
- **Other tabs**: Timeline/context menu

**Phases**:
- `.began`: Start recording, trigger haptic, start animation
- `.changed`: Continue recording
- `.ended`: Stop recording (or continue if countdown active)

### Gesture 4: Swipe Up
**Type**: `UISwipeGestureRecognizer (direction: .up)`
**Trigger**: Swipe up on cube
**Effect**: 
- **Record tab**: Toggle flashlight ON
- **Other tabs**: Context action

---

## Visual Effects

### Effect 1: Pop Animation (Hold Response)
When user holds cube (long press), it pulses to indicate recording:
```swift
// Scale up to 112% over 1.2 seconds (ease in-out)
SCNAction.scale(to: 1.12, duration: 1.2)
// Hold at peak for 0.12 seconds
SCNAction.wait(duration: 0.12)
// Scale back down to 100% over 0.9 seconds
SCNAction.scale(to: 1.0, duration: 0.9)
// Rest for 0.35 seconds
SCNAction.wait(duration: 0.35)
// Repeat forever until hold ends
```

**Audio**: Pop sound at peak (from `pop.mp3` in bundle)

### Effect 2: Glow Particles (DISABLED)
**Status**: Currently disabled in code (see line marked `PARTICLE EFFECTS DISABLED`)

**Original Intent**:
- Soft flame-like particles around cube
- Birth rate: 90 particles/second
- Lifetime: 1.2 seconds
- Particle size: 0.06 units
- Blend mode: Additive (glowing)
- Color: Orange (`glowColor` binding)

**Why Disabled**: Performance optimization for 120fps target

### Effect 3: Flash/Torch Illumination
When flashlight is ON (camera tab), cube glows brighter:
```swift
// Boost emission intensity
material.emission.intensity = 2.5

// Pulse animation
let brighten = SCNAction.customAction(duration: 1.2) { node, elapsed in
    let intensity = 2.5 + sin(elapsed / 1.2 * .pi * 2) * 0.5
    material.emission.intensity = intensity
}
```

### Effect 4: Motion Tilt (Device Motion)
**Status**: Currently disabled (yaw-only mode)

**Original Intent**: Cube tilts slightly based on device accelerometer
- Roll: Cube tilts left/right as device tilts
- Pitch: Cube tilts forward/back as device tilts
- **Currently**: All tilt set to zero to keep faces square

---

## Performance Optimization

### Frame Rate Targets
- **Production**: 120 FPS (preferred)
- **Preview**: 60 FPS (reduced for Xcode canvas)
- **Fallback**: 60 FPS (if device can't sustain 120)

### Antialiasing
```swift
sceneView.antialiasingMode = .multisampling4X
```
**4X MSAA**: Good balance between quality and performance

### Scene Initialization
**Strategy**: Fast first frame, defer quality
```swift
// Initial setup (minimal):
sceneView.scene = SCNScene() // empty
sceneView.preferredFramesPerSecond = 60
sceneView.antialiasingMode = .none

// Deferred (next runloop):
DispatchQueue.main.async {
    sceneView.scene = makeScene() // full scene
    sceneView.preferredFramesPerSecond = 120
    sceneView.antialiasingMode = .multisampling4X
}
```

### Material Caching
Face textures are generated once and cached:
```swift
private enum CubeFaceImageCache {
    private static var cache: [String: UIImage] = [:]
    static func image(for key: String, builder: () -> UIImage) -> UIImage {
        if let img = cache[key] { return img }
        let img = builder()
        cache[key] = img
        return img
    }
}
```

---

## Android Implementation Guide

### 1. Choose 3D Framework

**Option A: OpenGL ES** (Lower-level, more control)
- Direct access to GPU
- Manual vertex/fragment shaders
- More complex, but highest performance

**Option B: SceneForm / Filament** (Higher-level, easier)
- Scene graph like SceneKit
- Material system
- Easier to port iOS concepts

**Recommendation**: Start with Filament, optimize with OpenGL ES if needed

### 1b. Opaque Surface Setup (critical — do this before anything else)

The GL surface **must be opaque**. If left at the default translucent config the cube will appear semi-transparent and bleed into content behind it.

**OpenGL ES / GLSurfaceView:**
```kotlin
glSurfaceView.apply {
    // Opaque pixel format — no alpha channel in the surface
    holder.setFormat(PixelFormat.OPAQUE)
    // Keep below other views (not on top of window)
    setZOrderOnTop(false)
    setEGLConfigChooser(8, 8, 8, 0, 16, 0) // RGB, no alpha, depth 16
}

// In your Renderer.onSurfaceCreated:
GLES20.glClearColor(0f, 0f, 0f, 1f)  // alpha = 1.0, never 0
GLES20.glDisable(GLES20.GL_BLEND)     // disable blending so nothing bleeds through
```

**Filament / SurfaceView:**
```kotlin
// In your Filament setup, clear to a solid color (match app background)
renderer.clearOptions = Renderer.ClearOptions().apply {
    clear = true
    clearColor = floatArrayOf(0.04f, 0.06f, 0.04f, 1.0f) // fully opaque
}
```

**In Compose (AndroidView wrapper):**
```kotlin
AndroidView(
    factory = { ctx ->
        CubeGLSurfaceView(ctx).apply {
            // Solid background behind the GL view — prevents see-through flash
            setBackgroundColor(android.graphics.Color.BLACK)
        }
    },
    modifier = Modifier
        .size(115.dp)
        .clip(RoundedCornerShape(16.dp)) // optional: round the container corners
)
```

### 2. Geometry Creation

```kotlin
// Pseudo-code for Filament
val box = Box.Builder()
    .setSize(1.3f, 1.3f, 1.3f)
    .setChamferRadius(0.25f)
    .build()
```

**Android Note**: May need to manually generate chamfered geometry, as not all frameworks support it directly.

### 3. Material Setup

```kotlin
// Pseudo-code for Filament
val material = Material.Builder()
    .setDiffuse(faceTexture)      // Layer 1
    .setMultiply(tintColor)        // Layer 2
    .setEmissive(emissionTexture)  // Layer 3
    .setNormalMap(normalTexture)   // Layer 4
    .setMetallic(0.15f)
    .setRoughness(0.8f)
    .build()
```

### 4. Lighting

```kotlin
// Directional light
val keyLight = Light.Builder(Light.Type.DIRECTIONAL)
    .setIntensity(80.0f)
    .setDirection(Vector3(-1f, -2f, -1f).normalized())
    .build()

// Omni light
val fillLight = Light.Builder(Light.Type.POINT)
    .setIntensity(40.0f)
    .setPosition(Vector3(-2f, 1.5f, 3f))
    .build()

// IBL
scene.setIndirectLight(iblTexture, 0.35f)
```

### 5. Rotation Animation

```kotlin
// Kotlin with property animators
val animator = ValueAnimator.ofFloat(currentYaw, targetYaw)
animator.duration = 450 // 0.45 seconds
animator.interpolator = PathInterpolator(0.2f, 0.8f, 0.2f, 1.0f)
animator.addUpdateListener { animation ->
    val yaw = animation.animatedValue as Float
    cubeNode.setRotation(Quaternion.fromEulerAngles(0f, yaw, 0f))
}
animator.start()
```

### 6. Gesture Handling

```kotlin
// Pan gesture for rotation
cubeView.setOnTouchListener { v, event ->
    when (event.action) {
        MotionEvent.ACTION_DOWN -> {
            panStartX = event.x
            panStartYaw = currentYaw
        }
        MotionEvent.ACTION_MOVE -> {
            val deltaX = event.x - panStartX
            val radiansPerPixel = Math.PI.toFloat() / 360f
            currentYaw = panStartYaw + deltaX * radiansPerPixel
            updateCubeRotation()
        }
        MotionEvent.ACTION_UP -> {
            snapToNearestFace()
        }
    }
    true
}
```

### 7. Face Texture Generation

```kotlin
// Generate face texture programmatically
fun generateFaceTexture(tab: AppTab): Bitmap {
    val width = 300
    val height = 300
    // RGB_565 has no alpha channel — guaranteed opaque, smaller memory footprint
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565)
    val canvas = Canvas(bitmap)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    // 0. Fill entire canvas with the face background color (no transparent corners)
    canvas.drawColor(Color.parseColor("#5856D6")) // indigo tint — matches iOS default

    // 1. Draw rounded rect (the white card)
    val rect = RectF(8f, 8f, width - 8f, height - 8f)
    paint.color = Color.WHITE
    canvas.drawRoundRect(rect, 24f, 24f, paint)

    // 2. Draw icon (use vector drawable)
    val icon = getIconForTab(tab) // Material Icon
    icon.setBounds(105, 70, 195, 160)
    icon.draw(canvas)

    // 3. Draw title text
    paint.color = Color.parseColor("#5856D6")
    paint.textSize = 24f
    paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    paint.textAlign = Paint.Align.CENTER
    canvas.drawText(tab.title, width / 2f, 200f, paint)

    return bitmap
}
```

---

## Asset Requirements

### Textures Needed
1. **CubeNormalMap.png** (or .jpg)
   - Size: 512x512 or 1024x1024
   - Format: Tangent-space normal map (RGB)
   - Channels:
     - R: X tangent
     - G: Y tangent
     - B: Z normal

2. **CubeEnv.png** (or .hdr)
   - Size: 1024x512 (equirectangular)
   - Format: HDR preferred, LDR acceptable
   - Purpose: Environment reflections

3. **Pop.mp3** (or .wav, .ogg)
   - Duration: ~0.1 seconds
   - Format: Short "pop" or "click" sound
   - Volume: Pre-normalized to 0.9

### Icons (Material Design)
Map iOS SF Symbols to Material Icons:

| iOS | Android Material Icon |
|-----|----------------------|
| `map.fill` | `ic_map` |
| `video.circle.fill` | `ic_videocam` or custom |
| `list.bullet.rectangle.portrait.fill` | `ic_view_list` |
| `person.circle.fill` | `ic_account_circle` |

---

## Testing Checklist

### Visual Tests
- [ ] Cube renders with all 4 tab faces
- [ ] Rounded corners (chamfer) visible
- [ ] Normal map adds surface texture
- [ ] Emission makes icons glow
- [ ] Tint color applies correctly
- [ ] Lighting shows depth and form

### Interaction Tests
- [ ] Pan left rotates cube right (next tab)
- [ ] Pan right rotates cube left (previous tab)
- [ ] Snap to face after pan release
- [ ] Overshoot/bounce animation on snap
- [ ] Tap triggers tab-specific action
- [ ] Long-press starts recording (record tab)

### Animation Tests
- [ ] Smooth 60 FPS minimum during rotation
- [ ] No jitter or stuttering
- [ ] Rotation respects touch velocity
- [ ] Snap animation completes before next gesture
- [ ] Pop animation scales cube during hold

### Performance Tests
- [ ] Maintains 60+ FPS during interaction
- [ ] No memory leaks after repeated rotations
- [ ] Texture memory usage stays constant
- [ ] GPU usage remains reasonable (<30% on mid-range device)

---

## Known Issues & Limitations

### iOS Limitations (to address in Android)
1. **Particle effects disabled**: May want to implement in Android with lower particle count
2. **Motion tilt disabled**: Could be enabled for dynamic effect
3. **Only 4 faces used**: Could expand to 6 faces for more tabs

### Android-Specific Considerations
1. **Fragment shaders**: May need custom shaders for emission blend
2. **Gesture conflicts**: Ensure cube gestures don't conflict with parent scrolling
3. **Device variation**: Test on multiple screen sizes and densities
4. **Performance**: May need to reduce quality on low-end devices

---

## Appendix A: Euler Angles vs Quaternions

### iOS (SceneKit)
Uses **Euler angles** for rotation:
```swift
node.eulerAngles = SCNVector3(pitch, yaw, roll) // radians
```

### Android (Filament/SceneForm)
Prefers **quaternions** for rotation:
```kotlin
node.setRotation(Quaternion.fromEulerAngles(pitch, yaw, roll))
```

**Conversion**:
```kotlin
fun eulerToQuaternion(pitch: Float, yaw: Float, roll: Float): Quaternion {
    val cy = cos(yaw * 0.5f)
    val sy = sin(yaw * 0.5f)
    val cp = cos(pitch * 0.5f)
    val sp = sin(pitch * 0.5f)
    val cr = cos(roll * 0.5f)
    val sr = sin(roll * 0.5f)

    return Quaternion(
        w = cr * cp * cy + sr * sp * sy,
        x = sr * cp * cy - cr * sp * sy,
        y = cr * sp * cy + sr * cp * sy,
        z = cr * cp * sy - sr * sp * cy
    )
}
```

---

## Appendix B: Material Shader Pseudo-Code

### Vertex Shader (GLSL ES 3.0)
```glsl
#version 300 es
precision highp float;

// Inputs
in vec3 aPosition;
in vec3 aNormal;
in vec2 aTexCoord;
in vec3 aTangent;

// Outputs
out vec3 vPosition;
out vec3 vNormal;
out vec2 vTexCoord;
out mat3 vTBN;

// Uniforms
uniform mat4 uModelMatrix;
uniform mat4 uViewMatrix;
uniform mat4 uProjectionMatrix;
uniform mat3 uNormalMatrix;

void main() {
    // Transform position
    vec4 worldPos = uModelMatrix * vec4(aPosition, 1.0);
    vPosition = worldPos.xyz;
    gl_Position = uProjectionMatrix * uViewMatrix * worldPos;
    
    // Transform normal
    vNormal = normalize(uNormalMatrix * aNormal);
    
    // Pass through texture coordinates
    vTexCoord = aTexCoord;
    
    // Compute TBN matrix for normal mapping
    vec3 T = normalize(uNormalMatrix * aTangent);
    vec3 N = vNormal;
    vec3 B = cross(N, T);
    vTBN = mat3(T, B, N);
}
```

### Fragment Shader (GLSL ES 3.0)
```glsl
#version 300 es
precision highp float;

// Inputs
in vec3 vPosition;
in vec3 vNormal;
in vec2 vTexCoord;
in mat3 vTBN;

// Outputs
out vec4 fragColor;

// Uniforms
uniform sampler2D uDiffuseTexture;
uniform sampler2D uEmissionTexture;
uniform sampler2D uNormalTexture;
uniform vec3 uTintColor;
uniform vec3 uLightDirection;
uniform vec3 uLightColor;
uniform vec3 uViewPosition;
uniform float uMetallic;
uniform float uRoughness;

vec3 getNormalFromMap() {
    // Sample normal map
    vec3 tangentNormal = texture(uNormalTexture, vTexCoord).xyz;
    tangentNormal = tangentNormal * 2.0 - 1.0; // Unpack from [0,1] to [-1,1]
    
    // Transform to world space using TBN matrix
    return normalize(vTBN * tangentNormal);
}

float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    
    float nom = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = 3.14159265359 * denom * denom;
    
    return nom / max(denom, 0.001);
}

void main() {
    // Sample textures
    vec4 diffuse = texture(uDiffuseTexture, vTexCoord);
    vec3 emission = texture(uEmissionTexture, vTexCoord).rgb;
    vec3 N = getNormalFromMap();
    
    // Apply tint color (multiply blend)
    vec3 baseColor = diffuse.rgb * uTintColor;
    
    // Basic lighting calculation
    vec3 L = normalize(-uLightDirection);
    vec3 V = normalize(uViewPosition - vPosition);
    vec3 H = normalize(L + V);
    
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);
    
    // Simple PBR approximation
    float D = DistributionGGX(N, H, uRoughness);
    vec3 diffuseComponent = baseColor * NdotL;
    vec3 specularComponent = vec3(D * 0.1) * uMetallic;
    
    // Add emission (self-illumination)
    vec3 finalColor = diffuseComponent + specularComponent + emission * 0.5;
    
    fragColor = vec4(finalColor, diffuse.a);
}
```

---

## Appendix C: SceneKit to Filament Mapping

| SceneKit | Filament | Notes |
|----------|----------|-------|
| `SCNScene` | `Scene` | Top-level container |
| `SCNNode` | `Entity` | Scene graph node |
| `SCNBox` | `Box` or custom mesh | Geometry primitive |
| `SCNMaterial` | `MaterialInstance` | Material properties |
| `SCNLight` | `Light` | Light source |
| `SCNCamera` | `Camera` | View camera |
| `SCNAction` | `Animator` | Keyframe animation |
| `SCNTransaction` | Manual timing | State changes |
| `UIGraphicsImageRenderer` | `Canvas` | Texture generation |

---

## Contact & Support

For questions about cube implementation:
- **iOS Lead**: [Your Name/Email]
- **Android Lead**: [Their Name/Email]
- **3D Graphics Expert**: [Expert Name/Email]

**Revision History**:
- v1.0 (2026-06-01): Initial specification
- v1.1 (TBD): Performance optimizations
- v1.2 (TBD): Additional visual effects

---

**END OF DOCUMENT**
