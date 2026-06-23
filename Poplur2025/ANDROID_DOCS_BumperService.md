# Android Implementation Guide — Poplur Bumper Service

**Feature**: AI voice "bumpers" that play before each feed post — a Poplur-branded animated screen speaks a channel-aware intro using ElevenLabs TTS.  
**Stack**: ElevenLabs TTS (voice) + Claude API (script) — both free tiers, no payment required.  
**Languages**: English, French (extendable to Spanish)  
**Last Updated**: 2026-06-22

---

## Overview

Before each post in the vertical feed, Poplur shows a full-screen branded "Up Next" screen with animated equalizer bars and an ElevenLabs voice reading a short AI-generated intro about the upcoming content.

### User Flow
1. User scrolls to post N
2. If bumper for post N+1 is ready → show animated bumper screen full-screen, voice plays
3. User listens or taps Skip → main post N+1 begins
4. In background: pre-generate bumpers for N+2, N+3

### Why not video avatars?
Video avatar services (HeyGen etc.) require paid plans. ElevenLabs has a genuine free tier (10,000 characters/month, no card needed). The branded animated screen gives the same "TV presenter" feel at zero cost.

---

## Setup

### 1. Add API keys to secrets

In `local.properties` (gitignored) or your CI secrets:

```
ELEVENLABS_API_KEY=your_key_here
ELEVENLABS_VOICE_ID=21m00Tcm4TlvDq8ikWAM
ELEVENLABS_VOICE_ID_FRENCH=g5CIjZEefAph4nQFvHAz
CLAUDE_API_KEY=your_anthropic_key
```

Get your ElevenLabs key: **elevenlabs.io** → Profile → API Key (free signup, no card).  
Default voice IDs are pre-filled: **Rachel** (English) and **Freya** (French). Browse more at **elevenlabs.io/voice-library**.  
Get your Claude key: **console.anthropic.com** → API Keys (optional — fallback scripts work without it).

### 2. Expose keys via BuildConfig

In `build.gradle.kts` (app module):

```kotlin
android {
    defaultConfig {
        buildConfigField("String", "ELEVENLABS_API_KEY",
            "\"${properties["ELEVENLABS_API_KEY"] ?: ""}\"")
        buildConfigField("String", "ELEVENLABS_VOICE_ID",
            "\"${properties["ELEVENLABS_VOICE_ID"] ?: "21m00Tcm4TlvDq8ikWAM"}\"")
        buildConfigField("String", "ELEVENLABS_VOICE_ID_FRENCH",
            "\"${properties["ELEVENLABS_VOICE_ID_FRENCH"] ?: ""}\"")
        buildConfigField("String", "CLAUDE_API_KEY",
            "\"${properties["CLAUDE_API_KEY"] ?: ""}\"")
    }
}
```

No extra dependencies needed — audio playback uses Android's built-in `MediaPlayer`.

---

## Data Layer

### BumperState.kt

```kotlin
sealed class BumperState {
    object Idle       : BumperState()
    object Generating : BumperState()
    data class Ready(val audioBytes: ByteArray) : BumperState()
    object Failed     : BumperState()
}
```

### ElevenLabsService.kt

```kotlin
import android.util.LruCache
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

object ElevenLabsService {

    private val apiKey         = BuildConfig.ELEVENLABS_API_KEY
    private val voiceIdEnglish = BuildConfig.ELEVENLABS_VOICE_ID
        .ifBlank { "21m00Tcm4TlvDq8ikWAM" } // Rachel fallback
    private val voiceIdFrench  = BuildConfig.ELEVENLABS_VOICE_ID_FRENCH
        .ifBlank { voiceIdEnglish }

    val isConfigured: Boolean get() = apiKey.isNotEmpty()

    private val cache = object : LruCache<String, ByteArray>(20) {}

    enum class Voice { ENGLISH, FRENCH }

    private fun voiceId(voice: Voice) = when (voice) {
        Voice.FRENCH  -> voiceIdFrench
        Voice.ENGLISH -> voiceIdEnglish
    }

    suspend fun audioBytes(text: String, voice: Voice = Voice.ENGLISH): ByteArray {
        val cacheKey = "${voiceId(voice)}|$text"
        cache[cacheKey]?.let { return it }

        val url = URL("https://api.elevenlabs.io/v1/text-to-speech/${voiceId(voice)}")
        val conn = url.openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.setRequestProperty("xi-api-key", apiKey)
        conn.setRequestProperty("Content-Type", "application/json")
        conn.connectTimeout = 20_000
        conn.readTimeout    = 20_000
        conn.doOutput = true

        val body = JSONObject().apply {
            put("text", text)
            put("model_id", "eleven_multilingual_v2")
            put("voice_settings", JSONObject().apply {
                put("stability", 0.5)
                put("similarity_boost", 0.75)
            })
        }
        conn.outputStream.write(body.toString().toByteArray())

        check(conn.responseCode in 200..299) { "ElevenLabs error ${conn.responseCode}" }

        val bytes = conn.inputStream.readBytes()
        cache.put(cacheKey, bytes)
        return bytes
    }
}
```

---

## Script Generation

### Language.kt

```kotlin
enum class PoplurLanguage(val code: String) {
    ENGLISH("en"),
    FRENCH("fr"),
    SPANISH("es");

    companion object {
        fun fromChannelId(channelId: String) = when (channelId) {
            "french"  -> FRENCH
            "spanish" -> SPANISH
            else      -> ENGLISH
        }
        fun fromCode(code: String) = values().firstOrNull { it.code == code } ?: ENGLISH
    }
}
```

### BumperScriptBuilder.kt

```kotlin
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

object BumperScriptBuilder {

    fun resolveLanguage(post: FeedPost, channelId: String): PoplurLanguage {
        val fromPost = PoplurLanguage.fromCode(post.sourceLanguageCode)
        return if (fromPost != PoplurLanguage.ENGLISH) fromPost
        else PoplurLanguage.fromChannelId(channelId)
    }

    suspend fun build(
        post: FeedPost,
        channelName: String,
        channelId: String,
        claudeApiKey: String
    ): Pair<String, PoplurLanguage> {
        val language = resolveLanguage(post, channelId)
        val script = if (claudeApiKey.isNotEmpty()) {
            generateWithClaude(post, channelName, language, claudeApiKey)
                ?: fallback(post, channelName, language)
        } else {
            fallback(post, channelName, language)
        }
        return script to language
    }

    private suspend fun generateWithClaude(
        post: FeedPost,
        channelName: String,
        language: PoplurLanguage,
        apiKey: String
    ): String? {
        val parts = listOfNotNull(post.cityName, post.countryName)
        val location = parts.joinToString(", ").ifBlank { null }

        var context = "Channel: $channelName"
        location?.let    { context += "\nLocation: $it" }
        if (post.isLiveStream)     context += "\nThis is a LIVE broadcast."
        if (post.viewCount > 100)  context += "\nTrending: ${post.viewCount} views."
        post.adHeadline?.let { context += "\nVideo headline: $it" }

        val languageInstruction = when (language) {
            PoplurLanguage.FRENCH  -> "Write the sentence in French (français). Sound like a natural French TV presenter."
            PoplurLanguage.SPANISH -> "Write the sentence in Spanish (español). Sound like a natural Spanish TV presenter."
            else                   -> "Write the sentence in English. Sound like a natural English-speaking TV presenter."
        }

        val prompt = """
            You are a charismatic TV host for Poplur, a social video app.
            Using the details below, write ONE natural spoken sentence (12–22 words) that a host
            would say live on air to introduce the next video.
            Reference the channel type and location naturally — don't just list them.
            Be warm, specific, and engaging. Vary your phrasing.
            $languageInstruction
            Return ONLY the spoken sentence — no quotes, no labels, no extra text.

            $context
        """.trimIndent()

        return runCatching {
            val url = URL("https://api.anthropic.com/v1/messages")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("x-api-key", apiKey)
            conn.setRequestProperty("anthropic-version", "2023-06-01")
            conn.setRequestProperty("content-type", "application/json")
            conn.connectTimeout = 15_000
            conn.readTimeout    = 15_000
            conn.doOutput = true

            val body = JSONObject().apply {
                put("model", "claude-haiku-4-5-20251001")
                put("max_tokens", 80)
                put("messages", JSONArray().put(JSONObject().apply {
                    put("role", "user")
                    put("content", prompt)
                }))
            }
            conn.outputStream.write(body.toString().toByteArray())

            JSONObject(conn.inputStream.bufferedReader().readText())
                .getJSONArray("content")
                .getJSONObject(0)
                .getString("text")
                .trim()
        }.getOrNull()
    }

    fun fallback(post: FeedPost, channelName: String, language: PoplurLanguage): String {
        val location = listOfNotNull(post.cityName, post.countryName).joinToString(", ")
        return when (language) {
            PoplurLanguage.FRENCH -> when {
                location.isNotBlank() && post.isLiveStream ->
                    "En direct depuis $location sur la chaîne $channelName — ne bougez pas."
                location.isNotBlank() ->
                    "Juste après, sur la chaîne $channelName — une vidéo en provenance de $location."
                else -> "La prochaine vidéo arrive sur Poplur $channelName — restez avec nous."
            }
            PoplurLanguage.SPANISH -> when {
                location.isNotBlank() && post.isLiveStream ->
                    "En vivo desde $location en el canal $channelName — no te vayas."
                location.isNotBlank() ->
                    "A continuación en $channelName — contenido llegando desde $location."
                else -> "El próximo video ya viene en Poplur $channelName — quédate."
            }
            else -> when {
                location.isNotBlank() && post.isLiveStream ->
                    "Coming up — a live ${channelName.lowercase()} broadcast from $location. Stay right here."
                location.isNotBlank() ->
                    "Next up on $channelName — fresh content just in from $location."
                else -> "Coming up on $channelName — the next video is on its way. Don't go anywhere."
            }
        }
    }
}
```

---

## ViewModel

### BumperViewModel.kt

```kotlin
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class BumperViewModel : ViewModel() {

    private val _bumpers = MutableStateFlow<Map<String, BumperState>>(emptyMap())
    val bumpers: StateFlow<Map<String, BumperState>> = _bumpers

    private val inFlight = mutableSetOf<String>()

    val isConfigured: Boolean get() = ElevenLabsService.isConfigured

    fun prefetch(post: FeedPost, channelName: String = "General", channelId: String = "") {
        if (!isConfigured) return
        if (_bumpers.value[post.id] != null) return
        if (inFlight.contains(post.id)) return

        inFlight.add(post.id)
        updateBumper(post.id, BumperState.Generating)

        viewModelScope.launch {
            runCatching {
                val (script, language) = BumperScriptBuilder.build(
                    post, channelName, channelId, BuildConfig.CLAUDE_API_KEY
                )
                val voice = if (language == PoplurLanguage.FRENCH)
                    ElevenLabsService.Voice.FRENCH
                else
                    ElevenLabsService.Voice.ENGLISH
                ElevenLabsService.audioBytes(script, voice)
            }.onSuccess { bytes ->
                updateBumper(post.id, BumperState.Ready(bytes))
            }.onFailure {
                updateBumper(post.id, BumperState.Failed)
            }
            inFlight.remove(post.id)
        }
    }

    fun bumperForPost(postId: String): BumperState =
        _bumpers.value[postId] ?: BumperState.Idle

    private fun updateBumper(postId: String, state: BumperState) {
        _bumpers.value = _bumpers.value + (postId to state)
    }
}
```

---

## UI — Compose

### FeedBumperScreen.kt

Full-screen Poplur-branded animated screen with voice playback. Uses Android's built-in `MediaPlayer` — no extra dependencies needed.

```kotlin
import android.media.MediaPlayer
import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import java.io.File

private val PoplurGreen = Color(0xFF8BE05C)
private val PoplurDark  = Color(0xFF0A0F07)

@Composable
fun FeedBumperScreen(
    audioBytes: ByteArray,
    onFinished: () -> Unit
) {
    val context = LocalContext.current
    var showSkip by remember { mutableStateOf(false) }
    var isPlaying by remember { mutableStateOf(false) }

    // Animated equalizer bars
    val barCount = 7
    val barHeights = remember { List(barCount) { Animatable(0.3f) } }

    LaunchedEffect(isPlaying) {
        if (isPlaying) {
            barHeights.forEach { bar ->
                launch {
                    while (isPlaying) {
                        bar.animateTo(
                            (0.1f + Math.random() * 0.9f).toFloat(),
                            animationSpec = tween(140, easing = LinearEasing)
                        )
                    }
                }
            }
        } else {
            barHeights.forEach { it.snapTo(0.3f) }
        }
    }

    // Audio playback via temp file
    DisposableEffect(audioBytes) {
        val tmpFile = File(context.cacheDir, "bumper_${System.currentTimeMillis()}.mp3")
            .also { it.writeBytes(audioBytes) }

        val player = MediaPlayer().apply {
            setDataSource(tmpFile.absolutePath)
            setOnPreparedListener {
                isPlaying = true
                start()
            }
            setOnCompletionListener {
                isPlaying = false
                tmpFile.delete()
                onFinished()
            }
            prepareAsync()
        }

        onDispose {
            player.release()
            tmpFile.delete()
        }
    }

    LaunchedEffect(Unit) {
        delay(2_000)
        showSkip = true
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(PoplurDark)
    ) {
        // Top bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(top = 60.dp)
                .align(Alignment.TopStart),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("POPLUR", color = PoplurGreen, fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Black, fontSize = 11.sp, letterSpacing = 3.sp)
            Text("UP NEXT", color = Color.White.copy(alpha = 0.4f),
                fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold,
                fontSize = 9.sp, letterSpacing = 2.sp)
        }

        // Center: P logo + label + equalizer
        Column(
            modifier = Modifier.align(Alignment.Center),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(28.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(110.dp)
                    .clip(CircleShape)
                    .background(PoplurGreen.copy(alpha = 0.08f)),
                contentAlignment = Alignment.Center
            ) {
                Text("P", color = PoplurGreen, fontSize = 54.sp,
                    fontWeight = FontWeight.Black)
            }

            Text("UP NEXT", color = Color.White.copy(alpha = 0.55f),
                fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold,
                fontSize = 13.sp, letterSpacing = 4.sp)

            Canvas(
                modifier = Modifier
                    .width(72.dp)
                    .height(56.dp)
            ) {
                val barW = 4.dp.toPx()
                val gap  = 5.dp.toPx()
                val maxH = size.height
                barHeights.forEachIndexed { i, anim ->
                    val barH = maxH * anim.value
                    drawRoundRect(
                        color = PoplurGreen.copy(alpha = if (isPlaying) 0.7f + anim.value * 0.3f else 0.3f),
                        topLeft = Offset(i * (barW + gap), maxH - barH),
                        size = Size(barW, barH),
                        cornerRadius = CornerRadius(2.dp.toPx())
                    )
                }
            }
        }

        // Bottom row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 52.dp)
                .align(Alignment.BottomStart),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color.White.copy(alpha = 0.06f))
                    .padding(horizontal = 10.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp)
            ) {
                Box(modifier = Modifier.size(6.dp).clip(CircleShape).background(PoplurGreen))
                Text("POPLUR", color = PoplurGreen, fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Black, fontSize = 9.sp, letterSpacing = 1.5.sp)
            }

            if (showSkip) {
                TextButton(onClick = onFinished) {
                    Text("SKIP ▶", color = Color.White, fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.Bold, fontSize = 12.sp, letterSpacing = 1.5.sp)
                }
            }
        }
    }
}
```

---

## Feed Integration

```kotlin
@Composable
fun FeedScreen(
    posts: List<FeedPost>,
    channelName: String = "General",
    channelId: String = "",
    bumperViewModel: BumperViewModel = viewModel()
) {
    val bumpers by bumperViewModel.bumpers.collectAsState()
    var activeBumperBytes by remember { mutableStateOf<ByteArray?>(null) }
    var currentIndex by remember { mutableIntStateOf(0) }

    LaunchedEffect(currentIndex) {
        val post = posts.getOrNull(currentIndex) ?: return@LaunchedEffect
        val state = bumperViewModel.bumperForPost(post.id)
        if (state is BumperState.Ready) activeBumperBytes = state.audioBytes
        posts.getOrNull(currentIndex + 1)?.let { bumperViewModel.prefetch(it, channelName, channelId) }
        posts.getOrNull(currentIndex + 2)?.let { bumperViewModel.prefetch(it, channelName, channelId) }
    }

    Box(Modifier.fillMaxSize()) {
        FeedPager(
            posts = posts,
            currentIndex = currentIndex,
            onIndexChanged = { currentIndex = it }
        )

        activeBumperBytes?.let { bytes ->
            FeedBumperScreen(
                audioBytes = bytes,
                onFinished = { activeBumperBytes = null }
            )
        }
    }
}
```

---

## Caching Strategy

- **In-memory**: `BumperViewModel` holds `Map<postId, BumperState>` for the session lifetime.
- `ElevenLabsService` has its own `LruCache<String, ByteArray>` (20 entries) keyed by voice+text, so scrolling back never re-downloads.
- **Disk cache (optional)**: Write audio bytes to `context.cacheDir` named by a hash of the script; reload on next launch.

---

## Configuration Reference

| Parameter | Where to set | Notes |
|-----------|-------------|-------|
| `ELEVENLABS_API_KEY` | `local.properties` / CI secret | Free at elevenlabs.io — never commit |
| `ELEVENLABS_VOICE_ID` | `local.properties` | Default: Rachel (`21m00Tcm4TlvDq8ikWAM`) |
| `ELEVENLABS_VOICE_ID_FRENCH` | `local.properties` | Default: Freya; falls back to English voice if blank |
| `CLAUDE_API_KEY` | `local.properties` / CI secret | Optional — fallback scripts work without it |
| Bumper trigger offset | `FeedScreen` | Pre-fetch N+1, N+2 |

---

## Error Handling

| Scenario | Behaviour |
|----------|-----------|
| ElevenLabs not configured | `prefetch()` is a no-op; bumpers never show |
| API call fails | `BumperState.Failed`; bumper skipped silently, post plays directly |
| Network offline | Exception caught by `runCatching` → Failed |
| Claude unavailable | Falls back to template script; ElevenLabs still speaks it |
| User taps Skip | `activeBumperBytes = null`; main post begins immediately |

---

## Notes

- Free tier gives 10,000 characters/month — roughly 600–800 bumper intros at ~15 words each.
- ElevenLabs `eleven_multilingual_v2` handles English, French, and Spanish from a single model.
- No ExoPlayer or video dependencies needed — `MediaPlayer` is built into Android.
- Generation typically takes **2–5 seconds** (vs 30–90s for HeyGen video). Pre-fetching 2 posts ahead is enough runway.
