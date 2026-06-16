# Android Notifications Implementation
## Daily Device + In-App Radius Notifications

### Goal
Android must match iOS notification behavior:
- Send one generated notification per user per day.
- Show the same notification on the device and inside the Profile notifications list.
- Generate randomized AI-style copy based on radius growth, radius decline, strongest area, and area takeover momentum.
- For test builds, schedule the first daily notification shortly after app launch so QA can see it on a physical Android phone.

---

## Data Model

```kotlin
enum class PoplurNotificationKind {
    RADIUS_GROWTH,
    RADIUS_DIP,
    AREA_TAKEOVER,
    DAILY_INSIGHT
}

data class PoplurNotification(
    val id: String,
    val kind: PoplurNotificationKind,
    val title: String,
    val detail: String,
    val createdAtMillis: Long,
    val isUnread: Boolean = true
)

data class NotificationPostSignal(
    val id: String,
    val latitude: Double,
    val longitude: Double,
    val radiusMeters: Int,
    val viewCount: Int
)
```

Persist notifications locally with Room or DataStore. Mirror server-delivered FCM notifications into the same local store.

---

## Firestore Inputs

Query the current user's posts:

```kotlin
Firebase.firestore
    .collection("posts")
    .whereEqualTo("userID", currentUserId)
    .limit(30)
```

Read:
- `latitude`
- `longitude`
- `radius`
- `viewCount`
- `userID`

Store a local day stamp, such as `yyyy-MM-dd`, to prevent duplicate daily notifications.

---

## AI-Style Generator

```kotlin
class RadiusNotificationGenerator {
    fun generate(
        posts: List<NotificationPostSignal>,
        previousTotalRadius: Int,
        nowMillis: Long = System.currentTimeMillis()
    ): PoplurNotification {
        val totalRadius = posts.sumOf { it.radiusMeters.coerceAtLeast(0) }
        val strongest = strongestArea(posts)
        val id = "daily-${dayStamp(nowMillis)}"

        return when {
            strongest != null && strongest.score >= 3 -> PoplurNotification(
                id = id,
                kind = PoplurNotificationKind.AREA_TAKEOVER,
                title = "You are taking over ${strongest.name}",
                detail = "Your posts are clustering hard around ${strongest.name}. AI says your radius there is becoming the signal to beat.",
                createdAtMillis = nowMillis
            )

            previousTotalRadius > 0 && totalRadius > previousTotalRadius -> {
                val delta = totalRadius - previousTotalRadius
                PoplurNotification(
                    id = id,
                    kind = PoplurNotificationKind.RADIUS_GROWTH,
                    title = "Your radius is climbing",
                    detail = "AI check-in: you gained ${formatRadius(delta)} since the last scan. Keep posting where reach is already pulling.",
                    createdAtMillis = nowMillis
                )
            }

            previousTotalRadius > 0 && totalRadius < previousTotalRadius -> {
                val delta = previousTotalRadius - totalRadius
                PoplurNotification(
                    id = id,
                    kind = PoplurNotificationKind.RADIUS_DIP,
                    title = "Your radius cooled off",
                    detail = "AI noticed a ${formatRadius(delta)} dip. A fresh post near your strongest area can help recover momentum today.",
                    createdAtMillis = nowMillis
                )
            }

            else -> {
                val copy = listOf(
                    "AI scan complete: your radius is ready for a push. Post near an active area and watch what catches.",
                    "Today’s radius read is steady. One strong local post could turn this into a takeover.",
                    "Your map has room to grow today. AI is watching for the next area where your reach starts stacking."
                ).random()
                PoplurNotification(
                    id = id,
                    kind = PoplurNotificationKind.DAILY_INSIGHT,
                    title = "Daily radius report",
                    detail = strongest?.let { "$copy Current strongest area: ${it.name}." } ?: copy,
                    createdAtMillis = nowMillis
                )
            }
        }
    }
}
```

Use nearest-city scoring similar to iOS:
- Count every post in the nearest known area.
- Add score for radius size.
- Add score for view count.
- If one area wins clearly, generate an area takeover notification.

---

## Local Notification Delivery

Create a notification channel on Android 8+:

```kotlin
val channel = NotificationChannel(
    "daily_radius",
    "Daily Radius",
    NotificationManager.IMPORTANCE_DEFAULT
)
notificationManager.createNotificationChannel(channel)
```

Post the notification:

```kotlin
NotificationCompat.Builder(context, "daily_radius")
    .setSmallIcon(R.drawable.ic_notification)
    .setContentTitle(item.title)
    .setContentText(item.detail)
    .setStyle(NotificationCompat.BigTextStyle().bigText(item.detail))
    .setAutoCancel(true)
    .build()
```

Also insert the same `PoplurNotification` into the in-app notifications repository before or after posting the system notification.

---

## Daily Test Worker

Use WorkManager for the test path:

```kotlin
class DailyRadiusNotificationWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val uid = Firebase.auth.currentUser?.uid ?: return Result.success()
        val repo = PoplurNotificationRepository(applicationContext)
        repo.generateAndDeliverDailyNotification(uid)
        return Result.success()
    }
}
```

For QA builds, enqueue an immediate one-time work request with a short delay:

```kotlin
val request = OneTimeWorkRequestBuilder<DailyRadiusNotificationWorker>()
    .setInitialDelay(15, TimeUnit.SECONDS)
    .build()

WorkManager.getInstance(context)
    .enqueueUniqueWork(
        "daily-radius-test",
        ExistingWorkPolicy.KEEP,
        request
    )
```

For production, use periodic work as a local fallback, but prefer backend/FCM for reliable daily delivery when the app is not opened.

---

## FCM Production Path

Add `FirebaseMessagingService`:

```kotlin
class PoplurMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val item = PoplurNotification(
            id = message.data["id"] ?: UUID.randomUUID().toString(),
            kind = PoplurNotificationKind.valueOf(message.data["kind"] ?: "DAILY_INSIGHT"),
            title = message.data["title"].orEmpty(),
            detail = message.data["detail"].orEmpty(),
            createdAtMillis = System.currentTimeMillis()
        )

        PoplurNotificationRepository(applicationContext).saveAndDisplay(item)
    }
}
```

The backend should generate the same AI/radius payload daily and send it through FCM. Local WorkManager is acceptable for test builds and as a fallback, but FCM is required for dependable delivery when the app is not running.

---

## Profile In-App List

The Profile notifications button should read from the local notification repository and show:
- Title
- Detail
- Icon/color based on kind
- Unread badge

Opening the notifications screen should mark all local notifications as read.

---

## QA Acceptance

- Install on a real Android device.
- Sign in.
- Allow notification permission on Android 13+.
- Launch app.
- Within 15 seconds in test builds, see a device notification.
- Open Profile notifications and confirm the same notification appears in-app.
- Relaunch app the same day and confirm it does not duplicate.
- Seed posts in one area and confirm takeover language appears.
- Change total radius up/down and confirm growth/dip copy appears.
