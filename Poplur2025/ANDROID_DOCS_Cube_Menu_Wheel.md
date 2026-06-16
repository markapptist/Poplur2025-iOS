# Cube Menu Wheel Android Implementation
## Hold-Driven Rainbow Submenu

**Purpose**: Match the iOS cube submenu refactor with an Android reusable menu wheel.

---

## Interaction Contract

The cube submenu is no longer a tap-to-open bubble menu.

Behavior:

- User long-presses/holds the cube.
- A white translucent focus dim appears over the screen behind the cube.
- A rainbow-style wheel/arc opens above the cube with menu icons arranged like an old phone dial.
- While the user keeps holding, the wheel revolves through the menu items on a fixed tick.
- Each tick changes the focused item and plays a short pop sound.
- When the user lets go, the wheel animates closed.
- Releasing the hold activates the currently focused item.
- Tapping the cube while the wheel is visible should close it without activation if the platform gesture path allows it.

Profile items:

- Mail
- Settings
- Phone
- Notifications
- Store

The component must be reusable so other screens can provide different wheel items later.

---

## State Holder

Use a dedicated class/state holder rather than storing all wheel timing inside the Profile composable.

```kotlin
data class CubeMenuWheelItem(
    val id: String,
    val label: String,
    val icon: ImageVector,
    val color: Color,
    val action: () -> Unit
)

class CubeMenuWheelController(
    private val scope: CoroutineScope,
    private val popPlayer: CubeMenuPopPlayer
) {
    var items by mutableStateOf<List<CubeMenuWheelItem>>(emptyList())
        private set

    var selectedIndex by mutableIntStateOf(0)
        private set

    var visible by mutableStateOf(false)
        private set

    var closing by mutableStateOf(false)
        private set

    val onScreen: Boolean
        get() = visible || closing

    private var tickJob: Job? = null

    fun beginHold(nextItems: List<CubeMenuWheelItem>) {
        if (nextItems.isEmpty()) return
        tickJob?.cancel()
        items = nextItems
        selectedIndex = 0
        closing = false
        visible = true
        popPlayer.play()

        tickJob = scope.launch {
            while (isActive) {
                delay(620)
                selectedIndex = (selectedIndex + 1) % items.size
                popPlayer.play()
            }
        }
    }

    fun endHold(activateSelected: Boolean) {
        tickJob?.cancel()
        tickJob = null

        val selectedAction = if (activateSelected) {
            items.getOrNull(selectedIndex)?.action
        } else {
            null
        }

        visible = false
        closing = true
        scope.launch {
            delay(180)
            closing = false
            selectedAction?.invoke()
        }
    }
}
```

---

## Pop Sound

Use a tiny bundled `pop.wav` with `SoundPool` for the best feel. Fallback to haptics and a short `ToneGenerator` beep if no asset is available.

```kotlin
class CubeMenuPopPlayer(context: Context) {
    private val soundPool = SoundPool.Builder().setMaxStreams(2).build()
    private val soundId = soundPool.load(context, R.raw.pop, 1)
    private val haptics = context.getSystemService(Vibrator::class.java)

    fun play() {
        soundPool.play(soundId, 0.55f, 0.55f, 1, 0, 1.0f)
        haptics?.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
    }

    fun release() {
        soundPool.release()
    }
}
```

---

## Compose Overlay

```kotlin
@Composable
fun CubeMenuWheelOverlay(
    controller: CubeMenuWheelController,
    modifier: Modifier = Modifier
) {
    val transition = updateTransition(targetState = controller.visible, label = "cubeWheel")
    val dimAlpha by transition.animateFloat(label = "dim") { visible ->
        if (visible) 0.56f else 0f
    }
    val wheelScale by transition.animateFloat(label = "scale") { visible ->
        if (visible) 1f else 0.82f
    }

    if (!controller.onScreen) return

    Canvas(modifier = modifier.fillMaxSize()) {
        drawRect(Color.White.copy(alpha = dimAlpha))

        val cubeCenter = Offset(
            x = size.width / 2f,
            y = size.height - (size.height * 0.16f).coerceIn(158f, 210f)
        )
        val radius = (size.width * 0.31f).coerceIn(126f, 178f) * wheelScale

        drawArc(
            brush = Brush.sweepGradient(
                listOf(Color.Green, Color.Cyan, Color(0xFF6875FF), Color(0xFFFF8A1A), Color.Green),
                center = cubeCenter
            ),
            startAngle = 214f,
            sweepAngle = 112f,
            useCenter = false,
            topLeft = Offset(cubeCenter.x - radius, cubeCenter.y - radius),
            size = Size(radius * 2f, radius * 2f),
            style = Stroke(width = 7.dp.toPx(), cap = StrokeCap.Round)
        )

        controller.items.forEachIndexed { index, item ->
            val slot = wheelSlot(index, controller.selectedIndex, controller.items.size)
            val angle = Math.toRadians((214f + 112f * slot / max(1, controller.items.lastIndex)).toDouble())
            val center = Offset(
                x = cubeCenter.x + cos(angle).toFloat() * radius,
                y = cubeCenter.y + sin(angle).toFloat() * radius
            )
            val selected = index == controller.selectedIndex
            drawCircle(
                color = Color.Black.copy(alpha = 0.96f),
                radius = if (selected) 41.dp.toPx() else 34.dp.toPx(),
                center = center
            )
            drawCircle(
                color = item.color,
                radius = if (selected) 43.dp.toPx() else 36.dp.toPx(),
                center = center,
                style = Stroke(width = if (selected) 5.dp.toPx() else 3.dp.toPx())
            )
        }
    }

    // Draw icons with normal Compose Icon composables above the Canvas if crisp vector icons are required.
}

private fun wheelSlot(index: Int, selectedIndex: Int, count: Int): Int {
    if (count == 0) return 0
    val centerSlot = count / 2
    return (index - selectedIndex + centerSlot + count * 4) % count
}
```

---

## Profile Wiring

When the Profile tab receives cube long-press start:

```kotlin
wheelController.beginHold(profileWheelItems)
```

When the cube hold ends:

```kotlin
wheelController.endHold(activateSelected = true)
```

Profile wheel item actions:

```kotlin
val profileWheelItems = listOf(
    CubeMenuWheelItem("mail", "Mail", Icons.Filled.Email, Color(0xFF6BFF54)) { openMail() },
    CubeMenuWheelItem("settings", "Settings", Icons.Filled.Settings, Color(0xFF6875FF)) { openSettings() },
    CubeMenuWheelItem("phone", "Phone", Icons.Filled.Phone, Color(0xFF00DDEB)) { openPopularPhone() },
    CubeMenuWheelItem("notifications", "Notifications", Icons.Filled.Notifications, Color(0xFFFF8A1A)) { openNotifications() },
    CubeMenuWheelItem("store", "Store", Icons.Filled.ShoppingCart, Color(0xFFFF8A1A)) { openStore() }
)
```

---

## Acceptance Criteria

- Long-pressing the cube opens an animated rainbow wheel above the cube.
- The rest of the screen dims with translucent white while the wheel is open.
- The wheel cycles through items while the hold continues.
- A pop sound and tick haptic play every time the focused item changes.
- Releasing the hold closes the wheel with animation and activates the focused item.
- The wheel is reusable and receives its menu items from the current screen.
- The Profile screen supplies mail, settings, phone, notifications, and store items.
