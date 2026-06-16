# PopularPhone Android Implementation
## Constructed, Aspect-Fit Phone UI

**Purpose**: Recreate the iOS `PopularPhone`/`PhoneScene` experience on Android without using a stretched static phone bitmap.

---

## Goal

Build the retro candybar phone as Android-rendered UI. The phone should mimic the reference image, but every major part must be drawn and laid out by the app:

- Black rounded body
- Dark worn faceplate
- Side rails
- Recessed green/yellow screen well
- Dynamic green LCD screen
- Navigation keys
- Full numeric keypad with yellow labels
- DTMF tones and haptics
- Optional Snake mini-game inside the screen

Do not stretch a full-phone image to the device screen. Use a fixed phone aspect ratio and aspect-fit the constructed phone inside the available viewport.

---

## Recommended Android Stack

- Jetpack Compose
- `Canvas` for phone body, screen, buttons, and wear texture
- `Box`/pointer input overlay for hit testing
- `ToneGenerator` or generated PCM for DTMF tones
- `HapticFeedback` for key taps

Avoid using a full-size `Image` for the phone body. Small noise/scratch textures are acceptable if they are overlaid and clipped to the drawn phone, but the geometry must be app-built.

---

## Layout Contract

Use one fitted phone rectangle and place all parts with normalized coordinates.

```kotlin
private const val PHONE_ASPECT_RATIO = 0.47f // width / height

data class PhoneRect(
    val left: Float,
    val top: Float,
    val width: Float,
    val height: Float
) {
    val right: Float get() = left + width
    val bottom: Float get() = top + height
}

fun fittedPhoneRect(size: Size): PhoneRect {
    val paddingX = size.width * 0.035f
    val paddingY = size.height * 0.035f
    val availableWidth = size.width - paddingX * 2f
    val availableHeight = size.height - paddingY * 2f

    var phoneWidth = availableWidth
    var phoneHeight = phoneWidth / PHONE_ASPECT_RATIO

    if (phoneHeight > availableHeight) {
        phoneHeight = availableHeight
        phoneWidth = phoneHeight * PHONE_ASPECT_RATIO
    }

    return PhoneRect(
        left = (size.width - phoneWidth) / 2f,
        top = (size.height - phoneHeight) / 2f,
        width = phoneWidth,
        height = phoneHeight
    )
}

fun PhoneRect.rectFromTop(
    x: Float,
    y: Float,
    width: Float,
    height: Float
): Rect {
    return Rect(
        left = left + this.width * x,
        top = top + this.height * y,
        right = left + this.width * (x + width),
        bottom = top + this.height * (y + height)
    )
}
```

This keeps the phone proportional on every Android screen size and orientation.

---

## Normalized Geometry

Use these same normalized positions as iOS:

| Element | x | y from top | width | height |
|---|---:|---:|---:|---:|
| Faceplate | 0.09 | 0.05 | 0.82 | 0.88 |
| Left rail | 0.045 | 0.035 | 0.075 | 0.91 |
| Right rail | 0.88 | 0.035 | 0.075 | 0.91 |
| Screen well | 0.11 | 0.075 | 0.78 | 0.335 |
| Yellow glow/backlight | 0.155 | 0.105 | 0.69 | 0.294 |
| Active LCD screen | 0.135 | 0.122 | 0.73 | 0.258 |
| Left nav key | 0.15 | 0.455 | 0.17 | 0.083 |
| Center nav key | 0.335 | 0.452 | 0.33 | 0.09 |
| Right nav key | 0.68 | 0.43 | 0.18 | 0.15 |

Keypad button centers:

```kotlin
val keyX = listOf(0.265f, 0.50f, 0.735f)
val keyYFromTop = listOf(0.594f, 0.681f, 0.768f, 0.855f)
val keyWidth = phone.width * 0.245f
val keyHeight = phone.height * 0.064f
```

Key labels:

```kotlin
val keyLabels = mapOf(
    "1" to "1∞",
    "2" to "2abc",
    "3" to "3def",
    "4" to "4ghi",
    "5" to "5jkl",
    "6" to "6mno",
    "7" to "7pqrs",
    "8" to "8tuv",
    "9" to "9wxyz",
    "*" to "* +",
    "0" to "0.-",
    "#" to "⇧ #"
)
```

---

## Compose Skeleton

```kotlin
@Composable
fun PopularPhoneScreen(
    modifier: Modifier = Modifier,
    onDismiss: () -> Unit = {}
) {
    var dialedNumber by rememberSaveable { mutableStateOf("") }
    var snakeActive by rememberSaveable { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val tonePlayer = remember { AndroidDialTonePlayer() }

    DisposableEffect(Unit) {
        onDispose { tonePlayer.release() }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    detectTapGestures { offset ->
                        val phone = fittedPhoneRect(size.toSize())
                        val key = hitTestPhoneKey(offset, phone)
                        if (key != null) {
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            tonePlayer.play(key)

                            if (snakeActive) {
                                // Route 2/4/6/8/5/* to snake controls.
                            } else if (key == "#") {
                                snakeActive = true
                            } else if (dialedNumber.length < 24) {
                                dialedNumber += key
                            }
                        }
                    }
                }
        ) {
            val phone = fittedPhoneRect(size)
            drawConstructedPhone(phone)
            drawPhoneScreen(phone, dialedNumber, snakeActive)
            drawPhoneKeypad(phone)
        }
    }
}
```

---

## Drawing Notes

`drawConstructedPhone(phone)` should draw:

- Outer body as a dark rounded rect with radius `phone.width * 0.105`
- Inner faceplate as a slightly lighter rounded rect
- Left/right rails as tall rounded rects
- Screen well as a recessed black rounded rect
- Yellow backlight rect behind the LCD
- Navigation keys and green center dash
- Deterministic tiny speckles/scratches clipped to the phone rect

Use colors close to:

```kotlin
val PhoneBlack = Color(0xFF0E0F0E)
val FacePlate = Color(0xFF25251F)
val KeyGray = Color(0xFF6E6960)
val LcdGreen = Color(0xFF738A54)
val LcdDark = Color(0xFF14210D)
val PhoneYellow = Color(0xFFE8F50A)
val CallGreen = Color(0xFF058522)
```

The LCD screen should be a real dynamic drawing area. Do not bake text, Snake, or number display into a background image.

---

## Touch Mapping

Hit testing must use the same fitted phone rectangle:

```kotlin
fun hitTestPhoneKey(offset: Offset, phone: PhoneRect): String? {
    val rows = listOf(
        listOf("1", "2", "3"),
        listOf("4", "5", "6"),
        listOf("7", "8", "9"),
        listOf("*", "0", "#")
    )
    val keyX = listOf(0.265f, 0.50f, 0.735f)
    val keyY = listOf(0.594f, 0.681f, 0.768f, 0.855f)
    val keyWidth = phone.width * 0.245f
    val keyHeight = phone.height * 0.064f

    rows.forEachIndexed { rowIndex, row ->
        row.forEachIndexed { colIndex, key ->
            val cx = phone.left + phone.width * keyX[colIndex]
            val cy = phone.top + phone.height * keyY[rowIndex]
            val rect = Rect(
                cx - keyWidth / 2f,
                cy - keyHeight / 2f,
                cx + keyWidth / 2f,
                cy + keyHeight / 2f
            )
            if (rect.contains(offset)) return key
        }
    }
    return null
}
```

---

## Audio

For a lightweight Android equivalent:

```kotlin
class AndroidDialTonePlayer {
    private val toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, 80)

    fun play(key: String) {
        val tone = when (key) {
            "1" -> ToneGenerator.TONE_DTMF_1
            "2" -> ToneGenerator.TONE_DTMF_2
            "3" -> ToneGenerator.TONE_DTMF_3
            "4" -> ToneGenerator.TONE_DTMF_4
            "5" -> ToneGenerator.TONE_DTMF_5
            "6" -> ToneGenerator.TONE_DTMF_6
            "7" -> ToneGenerator.TONE_DTMF_7
            "8" -> ToneGenerator.TONE_DTMF_8
            "9" -> ToneGenerator.TONE_DTMF_9
            "0" -> ToneGenerator.TONE_DTMF_0
            "*" -> ToneGenerator.TONE_DTMF_S
            "#" -> ToneGenerator.TONE_DTMF_P
            else -> ToneGenerator.TONE_PROP_BEEP
        }
        toneGenerator.startTone(tone, 180)
    }

    fun release() {
        toneGenerator.release()
    }
}
```

---

## Acceptance Criteria

- The Android phone is drawn with Compose/Canvas or an equivalent app-rendered system.
- A full-phone bitmap is not stretched to the device viewport.
- The phone keeps its aspect ratio on small phones, large phones, foldables, and tablets.
- The active LCD screen is a real content area and can render dialed numbers or Snake without distortion.
- Key hit testing uses the same normalized layout as the visuals.
- DTMF tones and haptics fire for all numeric keys.
- The result visually matches the iOS constructed phone closely enough for side-by-side QA.
