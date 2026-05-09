package com.example.essential_flutter

import android.Manifest
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.location.Geocoder
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import com.example.essential_flutter.ai.GalleryLiteRtLmRequest
import com.example.essential_flutter.ai.GalleryLiteRtLmRuntime
import com.example.essential_flutter.service.EssentialNativeBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URLDecoder
import java.net.URL
import java.net.URLEncoder
import org.json.JSONObject
import java.util.Locale
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val screenCaptureRequestCode = 5207
    private val audioReadRequestCode = 5208
    private val notificationRequestCode = 5209
    private val batteryOptimizationRequestCode = 5210
    private val voiceLogTag = "EssentialVoice"
    private val genAiLogTag = "EssentialGenAI"
    private var speechRecognizer: SpeechRecognizer? = null
    private var speechResult: MethodChannel.Result? = null
    private var tts: TextToSpeech? = null
    private val nativeBridge by lazy { EssentialNativeBridge() }
    private val nativeTtsPlaybackLock = Object()
    private var nativeTtsTrack: AudioTrack? = null
    private var nativeTtsThread: Thread? = null
    @Volatile
    private var nativeTtsGeneration = 0
    private var ttsReady = false
    private var ttsInitializing = false
    @Volatile
    private var ttsSpeaking = false
    @Volatile
    private var activeTtsUtterances = 0
    @Volatile
    private var suppressSpeechUntilMs = 0L
    @Volatile
    private var preferredTtsLocaleTag = "ja-JP"
    private var mediaProjection: MediaProjection? = null
    private var pendingScreenCaptureResult: MethodChannel.Result? = null
    private var pendingAudioNormalizeRequest: PendingAudioNormalizeRequest? = null
    private lateinit var voiceEventsChannel: MethodChannel
    private lateinit var sharedIntentChannel: MethodChannel
    private var pendingHuggingFaceAuthResult: MethodChannel.Result? = null
    private var pendingHuggingFaceRedirectUri: String? = null
    private var pendingSharedText: String? = null
    private var batteryOptimizationPromptShown = false
    private data class PendingTtsRequest(
        val text: String,
        val result: MethodChannel.Result,
        val queueMode: Int,
        val languageTag: String,
    )

    private data class PendingAudioNormalizeRequest(
        val path: String,
        val maxDurationMs: Long?,
        val result: MethodChannel.Result,
    )

    private val pendingTtsRequests = ArrayDeque<PendingTtsRequest>()
    private val liteRtLmRuntime by lazy { GalleryLiteRtLmRuntime(applicationContext) }
    private lateinit var genAiChannel: MethodChannel
    @Volatile
    private var genAiCancelRequested = false
    @Volatile
    private var activeGenAiRequestId: String? = null

    private var internalAudioRecord: android.media.AudioRecord? = null
    @Volatile
    private var isRecordingInternalAudio = false
    private var internalAudioThread: Thread? = null
    private var internalAudioPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "essential/device_state",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSnapshot" -> result.success(buildSnapshot())
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "essential/native_voice",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "recognizeOnce" -> {
                    val language = call.argument<String>("language") ?: "ja-JP"
                    val preferOnDevice = call.argument<Boolean>("preferOnDevice") ?: true
                    val allowDuringTts = call.argument<Boolean>("allowDuringTts") ?: false
                    recognizeOnce(result, language, preferOnDevice, allowDuringTts)
                }
                "speak" -> {
                    val text = call.argument<String>("text").orEmpty()
                    val language = normalizeTtsLanguageTag(
                        call.argument<String>("language") ?: preferredTtsLocaleTag,
                    )
                    val enginePreference = call.argument<String>("engine").orEmpty()
                    speak(text, result, languageTag = language, enginePreference = enginePreference)
                }
                "speakChunk" -> {
                    val text = call.argument<String>("text").orEmpty()
                    val flush = call.argument<Boolean>("flush") ?: false
                    val language = normalizeTtsLanguageTag(
                        call.argument<String>("language") ?: preferredTtsLocaleTag,
                    )
                    val enginePreference = call.argument<String>("engine").orEmpty()
                    speakChunk(text, flush, result, language, enginePreference)
                }
                "prepareTts" -> {
                    val language = normalizeTtsLanguageTag(
                        call.argument<String>("language") ?: preferredTtsLocaleTag,
                    )
                    val enginePreference = call.argument<String>("engine").orEmpty()
                    prepareTts(result, language, enginePreference)
                }
                "finishSpeech" -> {
                    suppressSpeechUntilMs = System.currentTimeMillis() + 250L
                    result.success(null)
                }
                "getTtsState" -> result.success(buildTtsState())
                "getSpeechRecognizerState" -> result.success(buildSpeechRecognizerState())
                "openTtsSettings" -> {
                    openTtsSettings()
                    result.success(null)
                }
                "stopSpeaking" -> {
                    stopNativeTtsPlayback()
                    tts?.stop()
                    ttsSpeaking = false
                    activeTtsUtterances = 0
                    suppressSpeechUntilMs = System.currentTimeMillis() + 400L
                    pendingTtsRequests.clear()
                    result.success(null)
                }
                "stopRecognition" -> {
                    speechRecognizer?.cancel()
                    val pending = speechResult
                    speechResult = null
                    pending?.success("")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        voiceEventsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "essential/native_voice_events",
        )
        genAiChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "essential/genai",
        )
        genAiChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "generate" -> generateWithGenAi(call.arguments, result)
                "warmUp" -> warmUpGenAi(call.arguments, result)
                "discoverModels" -> result.success(discoverGenAiModels())
                "cancel" -> {
                    genAiCancelRequested = true
                    activeGenAiRequestId?.let { liteRtLmRuntime.cancel(it) }
                    result.success(null)
                }
                "releaseIdle" -> {
                    val args = call.arguments as? Map<*, *>
                    val keepModelPath = args?.get("keepModelPath") as? String
                    liteRtLmRuntime.releaseIdle(keepModelPath)
                    result.success(null)
                }
                "getRuntimeState" -> {
                    result.success(mapOf("cachedEngineCount" to liteRtLmRuntime.cachedEngineCount()))
                }
                "isAvailable" -> result.success(true)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "essential/web_research",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "search" -> {
                    val query = call.argument<String>("query").orEmpty()
                    val maxResults = call.argument<Int>("maxResults") ?: 3
                    searchWeb(query, maxResults, result)
                }
                "read" -> {
                    val url = call.argument<String>("url").orEmpty()
                    val maxChars = call.argument<Int>("maxChars") ?: 1800
                    readWebPage(url, maxChars, result)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "essential/connectivity",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isOnline" -> result.success(isNetworkOnline())
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "essential/location_context",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "reverseGeocode" -> {
                    val latitude = call.argument<Number>("latitude")?.toDouble()
                    val longitude = call.argument<Number>("longitude")?.toDouble()
                    reverseGeocode(latitude, longitude, result)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "essential/share",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendText" -> {
                    val text = call.argument<String>("text").orEmpty()
                    val title = call.argument<String>("title") ?: "送信先を選択"
                    shareText(text, title)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "essential/huggingface_auth",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "authorize" -> {
                    val url = call.argument<String>("url").orEmpty()
                    val redirectUri = call.argument<String>("redirectUri").orEmpty()
                    startHuggingFaceAuthorization(url, redirectUri, result)
                }
                "openUrl" -> {
                    val url = call.argument<String>("url").orEmpty()
                    openExternalUrl(url)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "essential/screen_capture",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestScreenCapturePermission(result)
                else -> result.notImplemented()
            }
        }
        sharedIntentChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "essential/shared_intent",
        )
        sharedIntentChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialText" -> {
                    val text = pendingSharedText ?: extractSharedText(intent)
                    pendingSharedText = null
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }
        handleSharedIntent(intent, deliverToFlutter = false)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "essential/internal_audio",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> startInternalAudio(result)
                "stop" -> stopInternalAudio(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "essential/audio_tools",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "normalizeToSpeechWav" -> {
                    val audioPath = call.argument<String>("path").orEmpty()
                    val maxDurationMs = call.argument<Number>("maxDurationMs")?.toLong()
                    normalizeToSpeechWav(audioPath, result, maxDurationMs)
                }
                "preprocessForMeeting" -> {
                    val audioPath = call.argument<String>("path").orEmpty()
                    preprocessForMeeting(audioPath, result)
                }
                "splitSpeechWav" -> {
                    val audioPath = call.argument<String>("path").orEmpty()
                    val chunkDurationMs = call.argument<Number>("chunkDurationMs")?.toLong()
                    splitSpeechWav(audioPath, result, chunkDurationMs)
                }
                "analyzeAudio" -> {
                    val audioPath = call.argument<String>("path").orEmpty()
                    analyzeAudio(audioPath, result)
                }
                "detectSilenceRegions" -> {
                    val audioPath = call.argument<String>("path").orEmpty()
                    detectSilenceRegions(audioPath, result)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "essential/meeting_processing",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    requestNotificationPermissionIfNeeded()
                    requestBatteryOptimizationExemptionIfNeeded()
                    MeetingProcessingService.start(
                        this,
                        call.argument<String>("stage").orEmpty(),
                        call.argument<String>("detail").orEmpty(),
                    )
                    result.success(null)
                }
                "stop" -> {
                    MeetingProcessingService.stop(this)
                    result.success(null)
                }
                "complete" -> {
                    MeetingProcessingService.showCompleted(
                        this,
                        call.argument<String>("title").orEmpty(),
                        call.argument<String>("sessionId").orEmpty(),
                    )
                    result.success(null)
                }
                "failed" -> {
                    MeetingProcessingService.showFailed(
                        this,
                        call.argument<String>("detail").orEmpty(),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isNetworkOnline(): Boolean {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        val network = manager.activeNetwork ?: return false
        val capabilities = manager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    private fun readWebPage(urlText: String, maxChars: Int, result: MethodChannel.Result) {
        if (urlText.isBlank()) {
            result.success(mapOf("url" to urlText, "text" to ""))
            return
        }
        thread(name = "essential-web-read", isDaemon = true) {
            try {
                val normalizedUrl = normalizeWebUrl(urlText)
                val html = try {
                    fetchText(normalizedUrl)
                } catch (error: Exception) {
                    Log.w(genAiLogTag, "web direct read failed url=$normalizedUrl", error)
                    fetchText("https://r.jina.ai/http://${normalizedUrl.removePrefix("https://").removePrefix("http://")}")
                }
                val title = Regex("<title[^>]*>(.*?)</title>", RegexOption.IGNORE_CASE)
                    .find(html)
                    ?.groupValues
                    ?.getOrNull(1)
                    ?.let(::cleanHtml)
                    .orEmpty()
                val text = extractReadableText(html).take(maxChars.coerceIn(200, 6000))
                Log.i(genAiLogTag, "web_read_ok url=$normalizedUrl chars=${text.length}")
                runOnUiThread {
                    result.success(mapOf("url" to normalizedUrl, "title" to title, "text" to text))
                }
            } catch (error: Exception) {
                Log.w(genAiLogTag, "web read failed", error)
                runOnUiThread {
                    result.error("web_read_failed", error.message ?: "Web read failed.", null)
                }
            }
        }
    }

    private fun reverseGeocode(latitude: Double?, longitude: Double?, result: MethodChannel.Result) {
        if (latitude == null || longitude == null) {
            result.error("invalid_location", "Latitude and longitude are required.", null)
            return
        }
        thread(name = "essential-reverse-geocode", isDaemon = true) {
            try {
                val geocoder = Geocoder(this, Locale.JAPAN)
                @Suppress("DEPRECATION")
                val rows = geocoder.getFromLocation(latitude, longitude, 1)
                val address = rows?.firstOrNull()
                val payload = if (address == null) {
                    emptyMap<String, String>()
                } else {
                    mapOf(
                        "addressLine" to (address.getAddressLine(0) ?: ""),
                        "locality" to (address.locality ?: ""),
                        "subAdminArea" to (address.subAdminArea ?: ""),
                        "adminArea" to (address.adminArea ?: ""),
                        "country" to (address.countryName ?: ""),
                        "postalCode" to (address.postalCode ?: ""),
                    )
                }
                runOnUiThread { result.success(payload) }
            } catch (error: Exception) {
                Log.w(genAiLogTag, "reverse geocode failed", error)
                runOnUiThread {
                    result.error("reverse_geocode_failed", error.message ?: "Reverse geocode failed.", null)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (handleHuggingFaceAuthRedirect(intent)) {
            return
        }
        handleSharedIntent(intent, deliverToFlutter = true)
    }

    private fun startHuggingFaceAuthorization(url: String, redirectUri: String, result: MethodChannel.Result) {
        if (url.isBlank()) {
            result.error("bad_args", "Missing Hugging Face authorization URL.", null)
            return
        }
        pendingHuggingFaceAuthResult?.success(null)
        pendingHuggingFaceAuthResult = result
        pendingHuggingFaceRedirectUri = redirectUri
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
            })
        } catch (error: Exception) {
            pendingHuggingFaceAuthResult = null
            pendingHuggingFaceRedirectUri = null
            result.error("open_auth_failed", error.message, null)
        }
    }

    private fun handleHuggingFaceAuthRedirect(intent: Intent?): Boolean {
        val uri = intent?.data ?: return false
        val pending = pendingHuggingFaceAuthResult ?: return false
        val redirectUri = pendingHuggingFaceRedirectUri.orEmpty()
        if (redirectUri.isNotBlank() && !uri.toString().startsWith(redirectUri)) {
            return false
        }
        pendingHuggingFaceAuthResult = null
        pendingHuggingFaceRedirectUri = null
        pending.success(uri.toString())
        return true
    }

    private fun openExternalUrl(url: String) {
        if (url.isBlank()) {
            return
        }
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
        })
    }

    private fun handleSharedIntent(intent: Intent?, deliverToFlutter: Boolean) {
        val text = extractSharedText(intent)?.trim()?.takeIf { it.isNotEmpty() } ?: return
        pendingSharedText = text
        if (deliverToFlutter && ::sharedIntentChannel.isInitialized) {
            sharedIntentChannel.invokeMethod("sharedText", text)
            pendingSharedText = null
        }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_SEND) {
            return null
        }
        val direct = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (!direct.isNullOrBlank()) {
            return direct
        }
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        return subject?.takeIf { it.isNotBlank() }
    }

    private fun shareText(text: String, title: String) {
        if (text.isBlank()) {
            return
        }
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        startActivity(Intent.createChooser(sendIntent, title))
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != screenCaptureRequestCode) {
            return
        }
        val pending = pendingScreenCaptureResult
        if (pending == null) {
            return
        }
        if (resultCode != RESULT_OK || data == null) {
            pendingScreenCaptureResult = null
            pending.error("screen_capture_denied", "Screen capture permission was denied.", null)
            return
        }
        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = manager.getMediaProjection(resultCode, data)
        pendingScreenCaptureResult = null
        pending.success(true)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationRequestCode) {
            return
        }
        if (requestCode != audioReadRequestCode) {
            return
        }
        val pending = pendingAudioNormalizeRequest ?: return
        pendingAudioNormalizeRequest = null
        if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
            normalizeToSpeechWav(pending.path, pending.result, pending.maxDurationMs)
        } else {
            pending.result.error(
                "audio_read_permission",
                "Audio read permission is required for Downloads audio files.",
                null,
            )
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationRequestCode)
    }

    private fun requestBatteryOptimizationExemptionIfNeeded() {
        if (batteryOptimizationPromptShown || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return
        }
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (powerManager.isIgnoringBatteryOptimizations(packageName)) {
            return
        }
        batteryOptimizationPromptShown = true
        val requestIntent = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName"),
        )
        val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        try {
            startActivityForResult(requestIntent, batteryOptimizationRequestCode)
        } catch (error: Exception) {
            Log.w(genAiLogTag, "battery optimization request failed; opening settings", error)
            try {
                startActivity(fallbackIntent)
            } catch (settingsError: Exception) {
                Log.w(genAiLogTag, "battery optimization settings unavailable", settingsError)
            }
        }
    }

    override fun onDestroy() {
        liteRtLmRuntime.close()
        speechRecognizer?.destroy()
        speechRecognizer = null
        stopNativeTtsPlayback()
        tts?.shutdown()
        tts = null
        mediaProjection?.stop()
        mediaProjection = null
        super.onDestroy()
    }

    private fun recognizeOnce(
        result: MethodChannel.Result,
        languageTag: String = "ja-JP",
        preferOnDevice: Boolean = true,
        allowDuringTts: Boolean = false,
    ) {
        if (ttsSpeaking || System.currentTimeMillis() < suppressSpeechUntilMs) {
            Log.i(voiceLogTag, "speech recognition skipped while tts is active allowDuringTts=$allowDuringTts")
            result.success("")
            return
        }
        val useOnDevice = preferOnDevice && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
        if (useOnDevice && !SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) {
            Log.w(voiceLogTag, "on-device speech recognition unavailable")
            result.error("speech_unavailable", "On-device speech recognition is unavailable.", null)
            return
        }
        if (!useOnDevice && !SpeechRecognizer.isRecognitionAvailable(this)) {
            Log.w(voiceLogTag, "speech recognition unavailable")
            result.error("speech_unavailable", "Speech recognition is unavailable.", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 4201)
            Log.w(voiceLogTag, "microphone permission missing")
            result.error("microphone_permission", "Microphone permission is required.", null)
            return
        }
        if (speechResult != null) {
            Log.w(voiceLogTag, "speech recognition busy")
            result.error("speech_busy", "Speech recognition is already running.", null)
            return
        }
        speechRecognizer?.destroy()
        val recognizer = if (useOnDevice) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
        } else {
            SpeechRecognizer.createSpeechRecognizer(this)
        }.also { speechRecognizer = it }
        speechResult = result
        recognizer.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                emitVoiceEvent("ready", mapOf("onDevice" to useOnDevice))
            }
            override fun onBeginningOfSpeech() {
                if (ttsSpeaking || System.currentTimeMillis() < suppressSpeechUntilMs) {
                    Log.i(voiceLogTag, "speech began while tts active; ignoring self-audio")
                    return
                }
                emitVoiceEvent("speechStart", null)
                Log.i(voiceLogTag, "speech began")
            }
            override fun onRmsChanged(rmsdB: Float) {
                val normalized = ((rmsdB + 2.0f) / 12.0f).coerceIn(0.0f, 1.0f)
                emitVoiceEvent("level", mapOf("level" to normalized))
            }
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() {
                emitVoiceEvent("speechEnd", null)
            }
            override fun onPartialResults(partialResults: Bundle?) = Unit
            override fun onEvent(eventType: Int, params: Bundle?) = Unit

            override fun onError(error: Int) {
                val pending = speechResult
                speechResult = null
                speechRecognizer?.destroy()
                speechRecognizer = null
                Log.w(voiceLogTag, "speech recognition error=$error")
                emitVoiceEvent("speechError", mapOf("error" to error))
                if (
                    error == SpeechRecognizer.ERROR_NO_MATCH ||
                    error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
                ) {
                    pending?.success("")
                } else {
                    pending?.error("speech_error", "Speech recognition failed: $error", null)
                }
            }

            override fun onResults(results: Bundle?) {
                val matches = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    .orEmpty()
                val pending = speechResult
                speechResult = null
                speechRecognizer?.destroy()
                speechRecognizer = null
                Log.i(voiceLogTag, "speech recognition results=${matches.size} onDevice=$useOnDevice")
                pending?.success(matches.firstOrNull().orEmpty())
            }
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, normalizeSpeechLanguageTag(languageTag))
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, useOnDevice)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 1600L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 2200L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1400L)
        }
        Log.i(voiceLogTag, "speech recognition start language=${normalizeSpeechLanguageTag(languageTag)} onDevice=$useOnDevice")
        recognizer.startListening(intent)
    }

    private fun emitVoiceEvent(method: String, payload: Map<String, Any?>?) {
        if (!::voiceEventsChannel.isInitialized) {
            return
        }
        runOnUiThread {
            voiceEventsChannel.invokeMethod(method, payload)
        }
    }

    private fun buildSpeechRecognizerState(): Map<String, Any?> {
        val apiLevel = Build.VERSION.SDK_INT
        val regularAvailable = SpeechRecognizer.isRecognitionAvailable(this)
        val onDeviceAvailable = apiLevel >= Build.VERSION_CODES.S &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
        val hasMicPermission = if (apiLevel >= Build.VERSION_CODES.M) {
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        return mapOf(
            "engine" to "android_speech_recognizer",
            "apiLevel" to apiLevel,
            "available" to regularAvailable,
            "onDeviceAvailable" to onDeviceAvailable,
            "microphonePermissionGranted" to hasMicPermission,
        )
    }

    private fun normalizeSpeechLanguageTag(languageTag: String): String {
        val normalized = languageTag.trim().lowercase(Locale.US)
        return if (normalized.startsWith("en")) "en-US" else "ja-JP"
    }

    private fun requestScreenCapturePermission(result: MethodChannel.Result) {
        if (pendingScreenCaptureResult != null) {
            result.error("screen_capture_busy", "Screen capture permission is already pending.", null)
            return
        }
        pendingScreenCaptureResult = object : MethodChannel.Result {
            override fun success(resultValue: Any?) {
                result.success(true)
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                result.error(errorCode, errorMessage, errorDetails)
            }

            override fun notImplemented() {
                result.notImplemented()
            }
        }
        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(manager.createScreenCaptureIntent(), screenCaptureRequestCode)
    }

    private fun speak(
        text: String,
        result: MethodChannel.Result,
        queueMode: Int = TextToSpeech.QUEUE_FLUSH,
        languageTag: String = preferredTtsLocaleTag,
        enginePreference: String = "",
    ) {
        if (text.isBlank()) {
            result.success(null)
            return
        }
        val normalizedLanguageTag = normalizeTtsLanguageTag(languageTag)
        preferredTtsLocaleTag = normalizedLanguageTag
        Log.i(voiceLogTag, "speak requested chars=${text.length} language=$normalizedLanguageTag queueMode=$queueMode enginePreference=$enginePreference")
        if (enginePreference == "melotts") {
            if (speakWithNativeMeloTts(text, result, normalizedLanguageTag, queueMode == TextToSpeech.QUEUE_FLUSH)) {
                return
            }
            result.error(
                "melotts_unavailable",
                "Native MeloTTS could not synthesize or play this utterance.",
                buildTtsState(),
            )
            return
        }
        val engine = tts
        if (engine != null && ttsReady) {
            val languageStatus = configureTts(engine, normalizedLanguageTag)
            if (languageStatus == TextToSpeech.LANG_MISSING_DATA || languageStatus == TextToSpeech.LANG_NOT_SUPPORTED) {
                result.error("tts_language_unavailable", "Japanese or English TTS voice data is missing or unsupported.", buildTtsState())
                return
            }
            speakWithReadyEngine(engine, text, result, queueMode)
            return
        }
        pendingTtsRequests.addLast(
            PendingTtsRequest(text, result, queueMode, normalizedLanguageTag),
        )
        if (ttsInitializing) {
            Log.i(voiceLogTag, "tts initializing; queued request count=${pendingTtsRequests.size}")
            return
        }
        ttsInitializing = true
        Log.i(voiceLogTag, "tts init start")
        tts = TextToSpeech(this) { status ->
            runOnUiThread {
                ttsInitializing = false
                val initializedEngine = tts
                if (status != TextToSpeech.SUCCESS || initializedEngine == null) {
                    ttsReady = false
                    Log.w(voiceLogTag, "tts init failed status=$status")
                    failPendingTts(
                        "tts_unavailable",
                        "Text to speech engine failed to initialize. Install or enable a TTS engine.",
                    )
                    return@runOnUiThread
                }
                val languageStatus = configureTts(initializedEngine, preferredTtsLocaleTag)
                if (
                    languageStatus == TextToSpeech.LANG_MISSING_DATA ||
                    languageStatus == TextToSpeech.LANG_NOT_SUPPORTED
                ) {
                    ttsReady = false
                    Log.w(voiceLogTag, "tts language unavailable status=$languageStatus tag=$preferredTtsLocaleTag")
                    failPendingTts(
                        "tts_language_unavailable",
                        "Text to speech voice data is missing or unsupported.",
                    )
                    openTtsSettings()
                    return@runOnUiThread
                }
                ttsReady = true
                Log.i(voiceLogTag, "tts initialized languageStatus=$languageStatus")
                val queuedRequests = pendingTtsRequests.toList()
                pendingTtsRequests.clear()
                queuedRequests.forEach { request ->
                    preferredTtsLocaleTag = request.languageTag
                    configureTts(initializedEngine, request.languageTag)
                    speakWithReadyEngine(
                        initializedEngine,
                        request.text,
                        request.result,
                        request.queueMode,
                    )
                }
            }
        }
    }

    private fun prepareTts(
        result: MethodChannel.Result,
        languageTag: String = preferredTtsLocaleTag,
        enginePreference: String = "",
    ) {
        val normalizedLanguageTag = normalizeTtsLanguageTag(languageTag)
        preferredTtsLocaleTag = normalizedLanguageTag
        if (enginePreference != "android_tts") {
            try {
                nativeBridge.nativeSynthesizeTtsPcm16(
                    "melotts-native-fallback",
                    "warmup",
                    1.08f,
                    0.0f,
                )
                result.success(buildTtsState())
                return
            } catch (error: Throwable) {
                Log.w(voiceLogTag, "native melotts prepare unavailable", error)
                result.error(
                    "melotts_unavailable",
                    "Native MeloTTS could not prepare.",
                    buildTtsState(),
                )
                return
            }
        }
        val engine = tts
        if (engine != null && ttsReady) {
            val languageStatus = configureTts(engine, normalizedLanguageTag)
            if (languageStatus == TextToSpeech.LANG_MISSING_DATA || languageStatus == TextToSpeech.LANG_NOT_SUPPORTED) {
                result.error("tts_language_unavailable", "Text to speech voice data is missing or unsupported.", buildTtsState())
                return
            }
            result.success(buildTtsState())
            return
        }
        if (ttsInitializing) {
            result.success(buildTtsState())
            return
        }
        ttsInitializing = true
        Log.i(voiceLogTag, "tts prepare start enginePreference=$enginePreference")
        tts = TextToSpeech(this) { status ->
            runOnUiThread {
                ttsInitializing = false
                val initializedEngine = tts
                if (status != TextToSpeech.SUCCESS || initializedEngine == null) {
                    ttsReady = false
                    Log.w(voiceLogTag, "tts prepare failed status=$status")
                    result.error("tts_unavailable", "Text to speech engine failed to initialize.", buildTtsState())
                    return@runOnUiThread
                }
                val languageStatus = configureTts(initializedEngine, normalizedLanguageTag)
                if (
                    languageStatus == TextToSpeech.LANG_MISSING_DATA ||
                    languageStatus == TextToSpeech.LANG_NOT_SUPPORTED
                ) {
                    ttsReady = false
                    result.error("tts_language_unavailable", "Text to speech voice data is missing or unsupported.", buildTtsState())
                    return@runOnUiThread
                }
                ttsReady = true
                Log.i(voiceLogTag, "tts prepared languageStatus=$languageStatus tag=$normalizedLanguageTag")
                result.success(buildTtsState())
            }
        }
    }

    private fun speakChunk(
        text: String,
        flush: Boolean,
        result: MethodChannel.Result,
        languageTag: String = preferredTtsLocaleTag,
        enginePreference: String = "",
    ) {
        if (text.isBlank()) {
            result.success(null)
            return
        }
        val normalizedLanguageTag = normalizeTtsLanguageTag(languageTag)
        preferredTtsLocaleTag = normalizedLanguageTag
        Log.i(voiceLogTag, "speakChunk requested chars=${text.length} language=$normalizedLanguageTag flush=$flush enginePreference=$enginePreference")
        if (enginePreference != "android_tts" &&
            speakWithNativeMeloTts(text, result, normalizedLanguageTag, flush)
        ) {
            return
        }
        if (enginePreference == "melotts") {
            result.error(
                "melotts_unavailable",
                "Native MeloTTS could not synthesize or play this chunk.",
                buildTtsState(),
            )
            return
        }
        val engine = tts
        if (engine != null && ttsReady) {
            val languageStatus = configureTts(engine, normalizedLanguageTag)
            if (languageStatus == TextToSpeech.LANG_MISSING_DATA || languageStatus == TextToSpeech.LANG_NOT_SUPPORTED) {
                result.error("tts_language_unavailable", "Japanese or English TTS voice data is missing or unsupported.", buildTtsState())
                return
            }
            Log.i(voiceLogTag, "speakChunk using android tts fallback chars=${text.length} language=$normalizedLanguageTag")
            speakWithReadyEngine(
                engine = engine,
                text = text,
                result = result,
                queueMode = if (flush) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD,
            )
            return
        }
        speak(
            text,
            result,
            if (flush) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD,
            normalizedLanguageTag,
            enginePreference,
        )
    }

    private fun speakWithNativeMeloTts(
        text: String,
        result: MethodChannel.Result,
        languageTag: String,
        flush: Boolean,
    ): Boolean {
        val speakableText = textForNativeTts(text, languageTag)
        if (speakableText.isBlank()) {
            return false
        }
        return try {
            val pcm = nativeBridge.nativeSynthesizeTtsPcm16(
                "melotts-native-fallback",
                speakableText,
                1.08f,
                if (languageTag.startsWith("ja")) 0.18f else 0.0f,
            )
            if (pcm.isEmpty()) {
                Log.w(voiceLogTag, "native melotts returned empty pcm chars=${speakableText.length} language=$languageTag")
                return false
            }
            if (flush) {
                stopNativeTtsPlayback()
            }
            Log.i(voiceLogTag, "native melotts synthesized pcm=${pcm.size} chars=${speakableText.length} language=$languageTag")
            playNativePcm(pcm, result)
            true
        } catch (error: Throwable) {
            Log.w(voiceLogTag, "native melotts playback unavailable; falling back to Android TTS", error)
            false
        }
    }

    private fun playNativePcm(pcm: ShortArray, result: MethodChannel.Result) {
        val generation = nativeTtsGeneration
        activeTtsUtterances += 1
        ttsSpeaking = true
        val sampleRate = 22050
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        @Suppress("DEPRECATION")
        audioManager.requestAudioFocus(
            null,
            AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
        )
        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        ).coerceAtLeast(pcm.size * 2)
        val track = AudioTrack(
            AudioManager.STREAM_MUSIC,
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            minBuffer,
            AudioTrack.MODE_STREAM,
        )
        val utteranceId = "essential-melotts-${UUID.randomUUID()}"
        nativeTtsThread = thread(name = "essential-melotts-playback") {
            try {
                synchronized(nativeTtsPlaybackLock) {
                    if (generation != nativeTtsGeneration) {
                        return@thread
                    }
                    nativeTtsTrack = track
                    Log.i(voiceLogTag, "melotts native utterance start id=$utteranceId chars=${pcm.size}")
                    track.play()
                    var offset = 0
                    while (offset < pcm.size && generation == nativeTtsGeneration) {
                        val written = track.write(pcm, offset, pcm.size - offset)
                        if (written <= 0) {
                            break
                        }
                        offset += written
                    }
                    val deadline = System.currentTimeMillis() +
                        ((offset * 1000L) / sampleRate).coerceAtLeast(80L) +
                        250L
                    while (
                        generation == nativeTtsGeneration &&
                        track.playState == AudioTrack.PLAYSTATE_PLAYING &&
                        track.playbackHeadPosition < offset &&
                        System.currentTimeMillis() < deadline
                    ) {
                        Thread.sleep(20L)
                    }
                    track.stop()
                    Log.i(
                        voiceLogTag,
                        "melotts native utterance done id=$utteranceId frames=$offset played=${track.playbackHeadPosition}",
                    )
                }
            } catch (error: Throwable) {
                Log.w(voiceLogTag, "melotts native playback failed id=$utteranceId", error)
            } finally {
                track.release()
                if (nativeTtsTrack === track) {
                    nativeTtsTrack = null
                }
                activeTtsUtterances = maxOf(0, activeTtsUtterances - 1)
                ttsSpeaking = activeTtsUtterances > 0
                suppressSpeechUntilMs = System.currentTimeMillis() + 300L
                if (!ttsSpeaking) {
                    @Suppress("DEPRECATION")
                    audioManager.abandonAudioFocus(null)
                }
            }
        }
        result.success(buildTtsState() + mapOf("utteranceId" to utteranceId))
    }

    private fun stopNativeTtsPlayback() {
        nativeTtsGeneration += 1
        nativeTtsTrack?.let { track ->
            try {
                track.pause()
                track.flush()
                track.stop()
            } catch (_: Throwable) {
            }
            try {
                track.release()
            } catch (_: Throwable) {
            }
        }
        nativeTtsTrack = null
        nativeTtsThread = null
    }

    private fun textForNativeTts(text: String, languageTag: String): String {
        val cleaned = text.replace(Regex("https?://\\S+"), " URL ")
            .replace(Regex("[\\*_`#>\\[\\](){}]+"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
        if (!languageTag.startsWith("ja")) {
            return cleaned
        }
        return japaneseToRomaji(cleaned)
    }

    private fun japaneseToRomaji(text: String): String {
        val map = mapOf(
            'あ' to "a", 'い' to "i", 'う' to "u", 'え' to "e", 'お' to "o",
            'か' to "ka", 'き' to "ki", 'く' to "ku", 'け' to "ke", 'こ' to "ko",
            'さ' to "sa", 'し' to "shi", 'す' to "su", 'せ' to "se", 'そ' to "so",
            'た' to "ta", 'ち' to "chi", 'つ' to "tsu", 'て' to "te", 'と' to "to",
            'な' to "na", 'に' to "ni", 'ぬ' to "nu", 'ね' to "ne", 'の' to "no",
            'は' to "ha", 'ひ' to "hi", 'ふ' to "fu", 'へ' to "he", 'ほ' to "ho",
            'ま' to "ma", 'み' to "mi", 'む' to "mu", 'め' to "me", 'も' to "mo",
            'や' to "ya", 'ゆ' to "yu", 'よ' to "yo",
            'ら' to "ra", 'り' to "ri", 'る' to "ru", 'れ' to "re", 'ろ' to "ro",
            'わ' to "wa", 'を' to "wo", 'ん' to "n",
            'が' to "ga", 'ぎ' to "gi", 'ぐ' to "gu", 'げ' to "ge", 'ご' to "go",
            'ざ' to "za", 'じ' to "ji", 'ず' to "zu", 'ぜ' to "ze", 'ぞ' to "zo",
            'だ' to "da", 'ぢ' to "ji", 'づ' to "zu", 'で' to "de", 'ど' to "do",
            'ば' to "ba", 'び' to "bi", 'ぶ' to "bu", 'べ' to "be", 'ぼ' to "bo",
            'ぱ' to "pa", 'ぴ' to "pi", 'ぷ' to "pu", 'ぺ' to "pe", 'ぽ' to "po",
            'ゃ' to "ya", 'ゅ' to "yu", 'ょ' to "yo", 'っ' to "", 'ー' to "",
            '。' to ". ", '、' to ", ", '！' to "! ", '？' to "? ",
        )
        val builder = StringBuilder()
        for (char in text) {
            val hira = if (char in 'ァ'..'ン') (char.code - 0x60).toChar() else char
            val mapped = map[hira]
            when {
                mapped != null -> builder.append(mapped).append(' ')
                char.code < 128 -> builder.append(char)
                Regex("[一-龯]").matches(char.toString()) -> builder.append(" ")
                else -> builder.append(" ")
            }
        }
        return builder.toString().replace(Regex("\\s+"), " ").trim()
    }

    private fun configureTts(engine: TextToSpeech, languageTag: String = preferredTtsLocaleTag): Int {
        engine.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
        )
        engine.setSpeechRate(1.12f)
        engine.setPitch(1.0f)
        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                ttsSpeaking = true
                activeTtsUtterances = maxOf(activeTtsUtterances, 1)
                Log.i(voiceLogTag, "tts utterance start id=$utteranceId")
            }

            override fun onDone(utteranceId: String?) {
                activeTtsUtterances = maxOf(0, activeTtsUtterances - 1)
                ttsSpeaking = activeTtsUtterances > 0 || engine.isSpeaking
                suppressSpeechUntilMs = System.currentTimeMillis() + 250L
                Log.i(voiceLogTag, "tts utterance done id=$utteranceId active=$activeTtsUtterances")
            }

            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                activeTtsUtterances = maxOf(0, activeTtsUtterances - 1)
                ttsSpeaking = activeTtsUtterances > 0 || engine.isSpeaking
                suppressSpeechUntilMs = System.currentTimeMillis() + 400L
                Log.w(voiceLogTag, "tts utterance error id=$utteranceId")
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                activeTtsUtterances = maxOf(0, activeTtsUtterances - 1)
                ttsSpeaking = activeTtsUtterances > 0 || engine.isSpeaking
                suppressSpeechUntilMs = System.currentTimeMillis() + 400L
                Log.w(voiceLogTag, "tts utterance error id=$utteranceId code=$errorCode")
            }
        })
        val requestedLocale = Locale.forLanguageTag(normalizeTtsLanguageTag(languageTag))
        val requestedStatus = engine.setLanguage(requestedLocale)
        if (
            requestedStatus != TextToSpeech.LANG_MISSING_DATA &&
            requestedStatus != TextToSpeech.LANG_NOT_SUPPORTED
        ) {
            return requestedStatus
        }
        return if (requestedLocale.language == Locale.ENGLISH.language) {
            engine.setLanguage(Locale.ENGLISH)
        } else {
            val japaneseStatus = engine.setLanguage(Locale.JAPAN)
            val finalStatus = if (
                japaneseStatus == TextToSpeech.LANG_MISSING_DATA ||
                japaneseStatus == TextToSpeech.LANG_NOT_SUPPORTED
            ) {
                engine.setLanguage(Locale.JAPANESE)
            } else {
                japaneseStatus
            }
            finalStatus
        }
    }

    private fun normalizeTtsLanguageTag(languageTag: String): String {
        val locale = Locale.forLanguageTag(languageTag)
        return if (locale.language == Locale.ENGLISH.language) {
            "en-US"
        } else {
            "ja-JP"
        }
    }

    private fun speakWithReadyEngine(
        engine: TextToSpeech,
        text: String,
        result: MethodChannel.Result,
        queueMode: Int = TextToSpeech.QUEUE_FLUSH,
    ) {
        val utteranceId = "essential-tts-${UUID.randomUUID()}"
        val status = engine.speak(text, queueMode, null, utteranceId)
        if (status == TextToSpeech.ERROR) {
            Log.w(voiceLogTag, "tts speak rejected")
            result.error("tts_speak_failed", "Text to speech rejected the utterance.", buildTtsState())
            return
        }
        activeTtsUtterances += 1
        ttsSpeaking = true
        Log.i(voiceLogTag, "tts speak accepted id=$utteranceId chars=${text.length}")
        result.success(buildTtsState() + mapOf("utteranceId" to utteranceId))
    }

    private fun failPendingTts(code: String, message: String) {
        val queuedRequests = pendingTtsRequests.toList()
        pendingTtsRequests.clear()
        queuedRequests.forEach { request ->
            request.result.error(code, message, buildTtsState())
        }
    }

    private fun buildTtsState(): Map<String, Any?> {
        val engine = tts
        val engineSpeaking = engine?.isSpeaking == true
        if (!engineSpeaking && activeTtsUtterances == 0 && !ttsInitializing) {
            ttsSpeaking = false
        }
        return mapOf(
            "available" to true,
            "initializing" to ttsInitializing,
            "speaking" to (ttsSpeaking || engineSpeaking || nativeTtsTrack != null),
            "activeUtterances" to activeTtsUtterances,
            "engine" to "melotts",
            "playbackEngine" to if (nativeTtsTrack != null) "melotts_native_audio" else "melotts_native_audio_or_android_tts_fallback",
            "melottsAssetsPresent" to File(filesDir, "melotts/manifest.json").exists(),
            "nativeMeloTtsAvailable" to true,
            "defaultEngine" to engine?.defaultEngine,
            "engineLanguage" to engine?.language?.toLanguageTag(),
            "preferredLanguage" to preferredTtsLocaleTag,
            "voices" to engine?.voices
                ?.filter { voice -> voice.locale.language == Locale.forLanguageTag(preferredTtsLocaleTag).language }
                ?.map { voice -> voice.name }
                ?.take(8)
                .orEmpty(),
        )
    }

    private fun openTtsSettings() {
        val intents = listOf(
            Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA),
            Intent("com.android.settings.TTS_SETTINGS"),
        )
        for (intent in intents) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                Log.i(voiceLogTag, "opened tts settings action=${intent.action}")
                return
            }
        }
        Log.w(voiceLogTag, "no tts settings activity available")
    }

    private fun searchWeb(query: String, maxResults: Int, result: MethodChannel.Result) {
        if (query.isBlank()) {
            result.success(emptyList<Map<String, String>>())
            return
        }
        thread(name = "essential-web-research", isDaemon = true) {
            try {
                val limit = maxResults.coerceIn(1, 8)
                val rows = mutableListOf<Map<String, String>>()
                Log.i(genAiLogTag, "web_search_start query=$query limit=$limit")
                if (looksLikeWeatherQuery(query)) {
                    Log.i(genAiLogTag, "web_search: weather query detected")
                    fetchWeatherResult(query)?.let(rows::add)
                }
                val yahooResults = searchYahooJapan(query, limit - rows.size)
                Log.i(genAiLogTag, "web_search: yahoo returned ${yahooResults.size} rows")
                rows.addAll(yahooResults)
                if (rows.size < limit) {
                    val ddgResults = searchDuckDuckGo(query, limit - rows.size)
                    Log.i(genAiLogTag, "web_search: duckduckgo returned ${ddgResults.size} rows")
                    rows.addAll(ddgResults)
                }
                if (rows.size < limit) {
                    val bingResults = searchBing(query, limit - rows.size)
                    Log.i(genAiLogTag, "web_search: bing returned ${bingResults.size} rows")
                    rows.addAll(bingResults)
                }
                if (rows.size < limit && looksLikeNewsQuery(query)) {
                    val newsResults = searchGoogleNews(query, limit - rows.size)
                    Log.i(genAiLogTag, "web_search: google news returned ${newsResults.size} rows")
                    rows.addAll(newsResults)
                }
                val uniqueRows = rows.distinctBy { it["url"].orEmpty().ifBlank { it["title"].orEmpty() } }
                    .take(limit)
                Log.i(genAiLogTag, "web_search_ok query=$query rows=${uniqueRows.size}")
                runOnUiThread { result.success(uniqueRows) }
            } catch (error: Exception) {
                Log.w(genAiLogTag, "web search failed", error)
                runOnUiThread {
                    result.error("web_search_failed", error.message ?: "Web search failed.", null)
                }
            }
        }
    }

    private fun searchDuckDuckGo(query: String, maxResults: Int): List<Map<String, String>> {
        if (maxResults <= 0) {
            return emptyList()
        }
        return try {
            val encoded = URLEncoder.encode(query, Charsets.UTF_8.name())
            val html = fetchText("https://duckduckgo.com/html/?q=$encoded")
            if (html.contains("anomaly-modal", ignoreCase = true)) {
                Log.w(genAiLogTag, "duckduckgo returned anomaly challenge")
                emptyList()
            } else {
                parseDuckDuckGoResults(html, maxResults)
            }
        } catch (error: Exception) {
            Log.w(genAiLogTag, "duckduckgo search failed", error)
            emptyList()
        }
    }

    private fun searchBing(query: String, maxResults: Int): List<Map<String, String>> {
        if (maxResults <= 0) {
            return emptyList()
        }
        return try {
            val encoded = URLEncoder.encode(query, Charsets.UTF_8.name())
            val html = fetchText("https://www.bing.com/search?q=$encoded&cc=jp&setlang=ja-JP")
            parseBingResults(html, maxResults)
        } catch (error: Exception) {
            Log.w(genAiLogTag, "bing search failed", error)
            emptyList()
        }
    }

    private fun searchYahooJapan(query: String, maxResults: Int): List<Map<String, String>> {
        if (maxResults <= 0) {
            return emptyList()
        }
        return try {
            val encoded = URLEncoder.encode(query, Charsets.UTF_8.name())
            val html = fetchText("https://search.yahoo.co.jp/search?p=$encoded&ei=UTF-8&x=wrt")
            parseYahooJapanResults(html, maxResults)
        } catch (error: Exception) {
            Log.w(genAiLogTag, "yahoo search failed", error)
            emptyList()
        }
    }

    private fun searchGoogleNews(query: String, maxResults: Int): List<Map<String, String>> {
        if (maxResults <= 0) {
            return emptyList()
        }
        return try {
            val encoded = URLEncoder.encode(query, Charsets.UTF_8.name())
            val xml = fetchText("https://news.google.com/rss/search?q=$encoded&hl=ja&gl=JP&ceid=JP:ja")
            parseGoogleNewsResults(xml, maxResults)
        } catch (error: Exception) {
            Log.w(genAiLogTag, "google news search failed", error)
            emptyList()
        }
    }

    private fun parseDuckDuckGoResults(html: String, maxResults: Int): List<Map<String, String>> {
        val rows = mutableListOf<Map<String, String>>()
        val resultRegex = Regex(
            "<a[^>]+class=\"result__a\"[^>]+href=\"([^\"]+)\"[^>]*>(.*?)</a>.*?<a[^>]+class=\"result__snippet\"[^>]*>(.*?)</a>",
            setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE),
        )
        for (match in resultRegex.findAll(html)) {
            val url = normalizeWebUrl(decodeHtml(match.groupValues[1]))
            val title = cleanHtml(match.groupValues[2])
            val snippet = cleanHtml(match.groupValues[3])
            if (title.isBlank() && snippet.isBlank()) {
                continue
            }
            rows.add(mapOf("title" to title, "url" to url, "snippet" to snippet))
            if (rows.size >= maxResults) {
                break
            }
        }
        return rows
    }

    private fun parseBingResults(html: String, maxResults: Int): List<Map<String, String>> {
        val rows = mutableListOf<Map<String, String>>()
        val resultRegex = Regex(
            "<li[^>]+class=\"b_algo\"[\\s\\S]*?<h2[^>]*>\\s*<a[^>]+href=\"([^\"]+)\"[^>]*>(.*?)</a>[\\s\\S]*?<p[^>]*>(.*?)</p>",
            setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE),
        )
        for (match in resultRegex.findAll(html)) {
            val url = normalizeWebUrl(decodeHtml(match.groupValues[1]))
            val title = cleanHtml(match.groupValues[2])
            val snippet = cleanHtml(match.groupValues[3])
            if (title.isBlank() && snippet.isBlank()) {
                continue
            }
            rows.add(mapOf("title" to title, "url" to url, "snippet" to snippet))
            if (rows.size >= maxResults) {
                break
            }
        }
        return rows
    }

    private fun parseYahooJapanResults(html: String, maxResults: Int): List<Map<String, String>> {
        val rows = mutableListOf<Map<String, String>>()
        val resultsBlock = Regex(
            "<div id=\"web\"[\\s\\S]*?<ol>([\\s\\S]*?)</ol>",
            setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE),
        ).find(html)?.groupValues?.getOrNull(1) ?: html
        val resultRegex = Regex(
            "<li>\\s*<a[^>]+href=\"([^\"]+)\"[^>]*>(.*?)</a>\\s*<div>(.*?)</div>",
            setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE),
        )
        for (match in resultRegex.findAll(resultsBlock)) {
            val url = normalizeWebUrl(decodeHtml(match.groupValues[1]))
            if (!isUsableSearchResultUrl(url)) {
                continue
            }
            val title = cleanHtml(match.groupValues[2])
            val snippet = cleanHtml(match.groupValues[3])
            if (title.isBlank() && snippet.isBlank()) {
                continue
            }
            rows.add(mapOf("title" to title, "url" to url, "snippet" to snippet))
            if (rows.size >= maxResults) {
                break
            }
        }
        return rows
    }

    private fun parseGoogleNewsResults(xml: String, maxResults: Int): List<Map<String, String>> {
        val rows = mutableListOf<Map<String, String>>()
        val itemRegex = Regex(
            "<item>([\\s\\S]*?)</item>",
            setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE),
        )
        for (item in itemRegex.findAll(xml)) {
            val block = item.groupValues[1]
            val title = cleanHtml(Regex("<title>([\\s\\S]*?)</title>", RegexOption.IGNORE_CASE)
                .find(block)?.groupValues?.getOrNull(1).orEmpty())
            val url = normalizeWebUrl(decodeHtml(Regex("<link>([\\s\\S]*?)</link>", RegexOption.IGNORE_CASE)
                .find(block)?.groupValues?.getOrNull(1).orEmpty()))
            val pubDate = cleanHtml(Regex("<pubDate>([\\s\\S]*?)</pubDate>", RegexOption.IGNORE_CASE)
                .find(block)?.groupValues?.getOrNull(1).orEmpty())
            val source = cleanHtml(Regex("<source[^>]*>([\\s\\S]*?)</source>", RegexOption.IGNORE_CASE)
                .find(block)?.groupValues?.getOrNull(1).orEmpty())
            val snippet = listOf(source, pubDate)
                .filter { it.isNotBlank() }
                .joinToString(" / ")
            if (title.isBlank() || url.isBlank()) {
                continue
            }
            rows.add(mapOf("title" to title, "url" to url, "snippet" to snippet))
            if (rows.size >= maxResults) {
                break
            }
        }
        return rows
    }

    private fun fetchWeatherResult(query: String): Map<String, String>? {
        return try {
            val location = weatherLocationFromQuery(query)
            val encodedLocation = URLEncoder.encode(location, Charsets.UTF_8.name())
            val url = "https://wttr.in/$encodedLocation?format=j1"
            val json = JSONObject(fetchText(url))
            val area = json.optJSONArray("nearest_area")
                ?.optJSONObject(0)
                ?.optJSONArray("areaName")
                ?.optJSONObject(0)
                ?.optString("value")
                ?.takeIf { it.isNotBlank() }
                ?: location
            val current = json.optJSONArray("current_condition")?.optJSONObject(0)
            val weather = json.optJSONArray("weather")
            val targetIndex = if (query.contains("明日") || query.contains("tomorrow", true)) 1 else 0
            val target = weather?.optJSONObject(targetIndex.coerceAtMost((weather.length() - 1).coerceAtLeast(0)))
            val hourly = target?.optJSONArray("hourly")?.optJSONObject(4)
            val desc = hourly?.optJSONArray("weatherDesc")?.optJSONObject(0)?.optString("value")
                ?: current?.optJSONArray("weatherDesc")?.optJSONObject(0)?.optString("value")
                ?: ""
            val date = target?.optString("date").orEmpty()
            val maxTemp = target?.optString("maxtempC").orEmpty()
            val minTemp = target?.optString("mintempC").orEmpty()
            val chanceOfRain = hourly?.optString("chanceofrain").orEmpty()
            val currentTemp = current?.optString("temp_C").orEmpty()
            val snippet = buildString {
                append("地点: $area")
                if (date.isNotBlank()) append(" / 日付: $date")
                if (desc.isNotBlank()) append(" / 天気: $desc")
                if (maxTemp.isNotBlank() || minTemp.isNotBlank()) append(" / 気温: ${minTemp}〜${maxTemp}℃")
                if (chanceOfRain.isNotBlank()) append(" / 降水確率目安: $chanceOfRain%")
                if (currentTemp.isNotBlank()) append(" / 現在気温: $currentTemp℃")
            }
            mapOf(
                "title" to "$location の天気予報",
                "url" to url,
                "snippet" to snippet,
            )
        } catch (error: Exception) {
            Log.w(genAiLogTag, "weather fetch failed", error)
            null
        }
    }

    private fun weatherLocationFromQuery(query: String): String {
        val cleaned = query
            .replace(Regex("(今日|明日|現在|最新|天気|予報|気温|降水確率|教えて|調べて|検索して|検索|して|ください|結果|の|を|について|today|tomorrow|weather|forecast)", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
        return cleaned.ifBlank { query.trim() }
    }

    private fun looksLikeWeatherQuery(query: String): Boolean {
        return Regex("(天気|予報|気温|降水確率|weather|forecast)", RegexOption.IGNORE_CASE)
            .containsMatchIn(query)
    }

    private fun looksLikeNewsQuery(query: String): Boolean {
        return Regex("(ニュース|最新|速報|news|latest|recent)", RegexOption.IGNORE_CASE)
            .containsMatchIn(query)
    }

    private fun isUsableSearchResultUrl(url: String): Boolean {
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            return false
        }
        return !Regex("(search\\.yahoo\\.co\\.jp|yahoo\\.co\\.jp/search|support\\.yahoo|rd\\.listing\\.yahoo)", RegexOption.IGNORE_CASE)
            .containsMatchIn(url)
    }

    private fun fetchText(urlText: String): String {
        // First try plain HTTP (faster, more reliable for search engines)
        try {
            val plain = fetchTextViaHttp(urlText)
            if (plain.length > 500) {
                Log.i(genAiLogTag, "fetchText via HTTP ok url=$urlText chars=${plain.length}")
                return plain
            }
        } catch (e: Exception) {
            Log.w(genAiLogTag, "fetchText via HTTP failed, falling back to WebView: $e")
        }

        var resultHtml = ""
        var exception: Exception? = null
        val latch = java.util.concurrent.CountDownLatch(1)
        var latchDone = false

        runOnUiThread {
            try {
                val webView = android.webkit.WebView(this@MainActivity)
                webView.settings.javaScriptEnabled = true
                webView.settings.domStorageEnabled = true
                webView.settings.userAgentString = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36"

                var pageFinished = false
                webView.webViewClient = object : android.webkit.WebViewClient() {
                    override fun onPageFinished(view: android.webkit.WebView?, url: String?) {
                        super.onPageFinished(view, url)
                        if (pageFinished) return
                        pageFinished = true

                        Handler(Looper.getMainLooper()).postDelayed({
                            try {
                                view?.evaluateJavascript(
                                    "(function() { return document.documentElement.outerHTML; })();"
                                ) { html ->
                                    resultHtml = html?.removePrefix("\"")?.removeSuffix("\"")
                                        ?.replace("\\u003C", "<")
                                        ?.replace("\\\"", "\"")
                                        ?.replace("\\n", "\n")
                                        ?.replace("\\r", "\r")
                                        ?.replace("\\t", "\t")
                                        ?.replace("\\\\", "\\") ?: ""
                                    if (!latchDone) { latchDone = true; latch.countDown() }
                                    view.destroy()
                                }
                            } catch (e: Exception) {
                                exception = e
                                if (!latchDone) { latchDone = true; latch.countDown() }
                                view?.destroy()
                            }
                        }, 2000)
                    }

                    override fun onReceivedError(view: android.webkit.WebView?, request: android.webkit.WebResourceRequest?, error: android.webkit.WebResourceError?) {
                        // Only fail on main frame errors
                        if (request?.isForMainFrame == true) {
                            Log.w(genAiLogTag, "WebView main frame error: ${error?.description} url=${request.url}")
                            exception = Exception("WebView error: ${error?.description}")
                            if (!latchDone) { latchDone = true; latch.countDown() }
                            view?.destroy()
                        }
                    }
                }
                webView.loadUrl(urlText)
            } catch (e: Exception) {
                exception = e
                if (!latchDone) { latchDone = true; latch.countDown() }
            }
        }

        val success = latch.await(15, java.util.concurrent.TimeUnit.SECONDS)
        if (!success) {
            throw Exception("WebView timeout fetching $urlText")
        }
        if (exception != null) {
            throw exception!!
        }
        return resultHtml
    }

    private fun fetchTextViaHttp(urlText: String): String {
        val url = URL(urlText)
        val conn = url.openConnection() as HttpURLConnection
        conn.connectTimeout = 8000
        conn.readTimeout = 8000
        conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36")
        conn.setRequestProperty("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
        conn.setRequestProperty("Accept-Language", "ja,en;q=0.8")
        conn.setRequestProperty("Accept-Encoding", "identity")
        conn.instanceFollowRedirects = true
        return try {
            conn.connect()
            val code = conn.responseCode
            Log.i(genAiLogTag, "fetchTextViaHttp url=$urlText status=$code")
            if (code in 200..299) {
                conn.inputStream.bufferedReader(Charsets.UTF_8).readText()
            } else {
                throw Exception("HTTP $code")
            }
        } finally {
            conn.disconnect()
        }
    }

    private fun normalizeWebUrl(rawUrl: String): String {
        val decoded = decodeHtml(rawUrl).trim()
        val absolute = when {
            decoded.startsWith("//") -> "https:$decoded"
            decoded.startsWith("/") -> "https://duckduckgo.com$decoded"
            decoded.startsWith("http://") || decoded.startsWith("https://") -> decoded
            else -> decoded
        }
        val parsed = runCatching { Uri.parse(absolute) }.getOrNull() ?: return absolute
        if (parsed.host?.contains("duckduckgo.com") == true && parsed.path?.startsWith("/l/") == true) {
            val uddg = parsed.getQueryParameter("uddg")
            if (!uddg.isNullOrBlank()) {
                return URLDecoder.decode(uddg, Charsets.UTF_8.name())
            }
        }
        return absolute
    }

    private fun cleanHtml(value: String): String {
        return decodeHtml(value.replace(Regex("<[^>]+>"), " "))
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun extractReadableText(html: String): String {
        val withoutScripts = html
            .replace(Regex("<script[\\s\\S]*?</script>", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("<style[\\s\\S]*?</style>", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("<nav[\\s\\S]*?</nav>", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("<footer[\\s\\S]*?</footer>", RegexOption.IGNORE_CASE), " ")
        return cleanHtml(withoutScripts)
    }

    private fun decodeHtml(value: String): String {
        return value
            .replace("&amp;", "&")
            .replace("&quot;", "\"")
            .replace("&#x27;", "'")
            .replace("&#39;", "'")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
    }

    private fun generateWithGenAi(arguments: Any?, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val args = arguments as? Map<String, Any?>
        val modelPath = args?.get("modelPath") as? String
        val prompt = args?.get("prompt") as? String ?: ""
        @Suppress("UNCHECKED_CAST")
        val imagePaths = args?.get("imagePaths") as? List<String> ?: emptyList()
        @Suppress("UNCHECKED_CAST")
        val audioPaths = args?.get("audioPaths") as? List<String> ?: emptyList()
        val maxTokens = (args?.get("maxTokens") as? Number)?.toInt() ?: 512
        val contextTokens = (args?.get("contextTokens") as? Number)?.toInt() ?: 4000
        val topK = (args?.get("topK") as? Number)?.toInt() ?: 64
        val topP = (args?.get("topP") as? Number)?.toDouble() ?: 0.95
        val temperature = (args?.get("temperature") as? Number)?.toFloat() ?: 1.0f
        val accelerator = args?.get("accelerator") as? String ?: "auto"
        val visionAccelerator = args?.get("visionAccelerator") as? String ?: "gpu"
        val enableThinking = args?.get("enableThinking") as? Boolean ?: false
        val systemInstruction = args?.get("systemInstruction") as? String ?: ""
        val requestId = args?.get("requestId") as? String ?: UUID.randomUUID().toString()
        if (modelPath.isNullOrBlank() || !File(modelPath).exists()) {
            result.error("model_not_found", "GenAI model path not found: $modelPath", null)
            return
        }
        if (prompt.isBlank() && imagePaths.isEmpty() && audioPaths.isEmpty()) {
            result.error("empty_request", "Prompt or multimodal input is required.", null)
            return
        }
        genAiCancelRequested = false
        thread(name = "essential-genai", isDaemon = true) {
            val startedAt = System.currentTimeMillis()
            try {
                val preparedModelPath = prepareGenAiModelPath(modelPath)
                if (preparedModelPath.lowercase(Locale.US).endsWith(".litertlm")) {
                    generateWithLiteRtLm(
                        modelPath = preparedModelPath,
                        prompt = prompt,
                        systemInstruction = systemInstruction,
                        imagePaths = imagePaths,
                        audioPaths = audioPaths,
                        maxTokens = maxTokens,
                        contextTokens = contextTokens,
                        topK = topK,
                        topP = topP,
                        temperature = temperature,
                        accelerator = accelerator,
                        visionAccelerator = visionAccelerator,
                        enableThinking = enableThinking,
                        requestId = requestId,
                        startedAt = startedAt,
                        result = result,
                    )
                    return@thread
                }
                throw IllegalArgumentException("Essential GenAI only supports LiteRT-LM .litertlm models.")
            } catch (error: Throwable) {
                Log.e(genAiLogTag, "generate_error", error)
                runOnUiThread {
                    result.error(
                        "genai_error",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            } finally {
                activeGenAiRequestId = null
            }
        }
    }

    private fun warmUpGenAi(arguments: Any?, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val args = arguments as? Map<String, Any?>
        val modelPath = args?.get("modelPath") as? String
        val maxTokens = (args?.get("maxTokens") as? Number)?.toInt() ?: 512
        val contextTokens = (args?.get("contextTokens") as? Number)?.toInt() ?: 4000
        val topK = (args?.get("topK") as? Number)?.toInt() ?: 64
        val topP = (args?.get("topP") as? Number)?.toDouble() ?: 0.95
        val temperature = (args?.get("temperature") as? Number)?.toFloat() ?: 1.0f
        val accelerator = args?.get("accelerator") as? String ?: "gpu"
        val visionAccelerator = args?.get("visionAccelerator") as? String ?: "gpu"
        val requestId = args?.get("requestId") as? String ?: "warm-${UUID.randomUUID()}"
        if (modelPath.isNullOrBlank() || !File(modelPath).exists()) {
            result.error("model_not_found", "GenAI model path not found: $modelPath", null)
            return
        }
        thread(name = "essential-genai-warmup", isDaemon = true) {
            try {
                val preparedModelPath = prepareGenAiModelPath(modelPath)
                if (!preparedModelPath.lowercase(Locale.US).endsWith(".litertlm")) {
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "modelPath" to preparedModelPath,
                                "loadAndSetupMs" to 0,
                                "accelerator" to accelerator,
                                "visionAccelerator" to visionAccelerator,
                                "contextTokens" to contextTokens,
                            ),
                        )
                    }
                    return@thread
                }
                val warmup = liteRtLmRuntime.warmUp(
                    GalleryLiteRtLmRequest(
                        requestId = requestId,
                        modelPath = preparedModelPath,
                        prompt = "warmup",
                        systemInstruction = "",
                        maxTokens = maxTokens,
                        contextTokens = contextTokens,
                        topK = topK,
                        topP = topP,
                        temperature = temperature.toDouble(),
                        accelerator = accelerator,
                        visionAccelerator = visionAccelerator,
                    ),
                )
                runOnUiThread {
                    result.success(
                        mapOf(
                            "modelPath" to warmup.modelPath,
                            "loadAndSetupMs" to warmup.loadAndSetupMs,
                            "accelerator" to warmup.accelerator,
                            "visionAccelerator" to warmup.visionAccelerator,
                            "contextTokens" to warmup.contextTokens,
                        ),
                    )
                }
            } catch (error: Throwable) {
                Log.e(genAiLogTag, "warmup_error", error)
                runOnUiThread {
                    result.error(
                        "genai_warmup_error",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
        }
    }

    private fun discoverGenAiModels(): List<Map<String, Any?>> {
        val candidates = linkedMapOf<String, File>()
        val roots = listOfNotNull(
            File(applicationContext.filesDir, "genai_models"),
            File(applicationContext.cacheDir, "genai_models"),
            applicationContext.getExternalFilesDir(null)?.let {
                File(it, "genai_models")
            },
            File("/data/local/tmp/essential_genai_seed"),
        )
        for (root in roots) {
            if (!root.exists() || !root.isDirectory) {
                continue
            }
            root.listFiles { file ->
                file.isFile && file.canRead() &&
                    file.name.lowercase(Locale.US).endsWith(".litertlm")
            }
                .orEmpty()
                .sortedBy { it.name }
                .forEach { file ->
                    candidates.putIfAbsent(file.canonicalPath, file)
                }
        }
        return candidates.values.map { file ->
            mapOf(
                "id" to "local-genai:${file.name}",
                "title" to file.nameWithoutExtension
                    .replace('_', ' ')
                    .replace('-', ' '),
                "path" to file.absolutePath,
                "sizeBytes" to file.length(),
            )
        }
    }

    private fun generateWithLiteRtLm(
        modelPath: String,
        prompt: String,
        systemInstruction: String,
        imagePaths: List<String>,
        audioPaths: List<String>,
        maxTokens: Int,
        contextTokens: Int,
        topK: Int,
        topP: Double,
        temperature: Float,
        accelerator: String,
        visionAccelerator: String,
        enableThinking: Boolean,
        requestId: String,
        startedAt: Long,
        result: MethodChannel.Result,
    ) {
        activeGenAiRequestId = requestId
        val baseRequest = GalleryLiteRtLmRequest(
            requestId = requestId,
            modelPath = modelPath,
            prompt = prompt,
            systemInstruction = systemInstruction,
            imagePaths = imagePaths,
            audioPaths = audioPaths,
            maxTokens = maxTokens,
            contextTokens = contextTokens,
            topK = topK,
            topP = topP,
            temperature = temperature.toDouble(),
            accelerator = accelerator,
            visionAccelerator = visionAccelerator,
            enableThinking = enableThinking,
        )
        val tokenCallback: (String) -> Unit = { token ->
            runOnUiThread {
                genAiChannel.invokeMethod(
                    "token",
                    mapOf(
                        "requestId" to requestId,
                        "token" to token,
                    ),
                )
            }
        }
        val output = try {
            liteRtLmRuntime.generateBlocking(baseRequest, onToken = tokenCallback)
        } catch (error: Throwable) {
            if (!shouldRetryGenAiOnCpu(accelerator, error)) {
                throw error
            }
            Log.w(
                genAiLogTag,
                "litertlm_accelerator_fallback accelerator=$accelerator model=${File(modelPath).name}",
                error,
            )
            liteRtLmRuntime.releaseIdle()
            liteRtLmRuntime.generateBlocking(
                baseRequest.copy(
                    accelerator = "cpu",
                    visionAccelerator = if (imagePaths.isEmpty()) visionAccelerator else "cpu",
                ),
                onToken = tokenCallback,
            )
        }
        Log.i(
            genAiLogTag,
            "litertlm_generate_ok model=${File(modelPath).name} load_and_setup_ms=${output.loadAndSetupMs} generation_ms=${output.generationMs} chars=${output.text.length}",
        )
        runOnUiThread {
            result.success(
                mapOf(
                    "text" to output.text,
                    "modelPath" to output.modelPath,
                    "latencyMs" to (System.currentTimeMillis() - startedAt),
                    "generationMs" to output.generationMs,
                    "loadAndSetupMs" to output.loadAndSetupMs,
                    "firstTokenMs" to output.firstTokenMs,
                    "accelerator" to output.accelerator,
                    "visionAccelerator" to output.visionAccelerator,
                ),
            )
        }
    }

    private fun shouldRetryGenAiOnCpu(accelerator: String, error: Throwable): Boolean {
        if (accelerator.equals("cpu", ignoreCase = true)) {
            return false
        }
        val message = generateSequence(error) { it.cause }
            .joinToString(" ") { it.message.orEmpty() }
            .lowercase(Locale.US)
        return message.contains("opencl") ||
            message.contains("gpu") ||
            message.contains("accelerator") ||
            message.contains("delegate")
    }

    private fun prepareGenAiModelPath(modelPath: String): String {
        val source = File(modelPath)
        val appRoot = applicationContext.filesDir.canonicalFile
        val sourceCanonical = source.canonicalFile
        if (
            sourceCanonical.path.startsWith(appRoot.path) ||
                sourceCanonical.path.startsWith("/data/local/tmp/essential_genai_seed/")
        ) {
            return sourceCanonical.path
        }
        val targetDir = File(applicationContext.cacheDir, "genai_models")
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            throw IllegalStateException("Unable to create GenAI cache directory.")
        }
        val safeName = source.name.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val target = File(
            targetDir,
            "${sourceCanonical.path.hashCode().toString(16)}_${source.length()}_$safeName",
        )
        if (!target.exists() || target.length() != source.length()) {
            source.inputStream().use { input ->
                target.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
        }
        Log.i(genAiLogTag, "prepared_model source=$modelPath target=${target.path}")
        return target.path
    }

    private fun buildSnapshot(): Map<String, Any?> {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)

        val batteryIntent = registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        )
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val batteryLevel =
            if (level >= 0 && scale > 0) level.toDouble() / scale.toDouble() else null
        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val temperatureTenths =
            batteryIntent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
                ?: Int.MIN_VALUE

        return mapOf(
            "platform" to "android",
            "totalRamMb" to (memoryInfo.totalMem / (1024 * 1024)).toInt(),
            "availableRamMb" to (memoryInfo.availMem / (1024 * 1024)).toInt(),
            "lowRamDevice" to activityManager.isLowRamDevice,
            "isLowPowerMode" to powerManager.isPowerSaveMode,
            "batteryLevel" to batteryLevel,
            "isCharging" to (
                status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
                ),
            "temperatureC" to (
                if (temperatureTenths == Int.MIN_VALUE) null else temperatureTenths / 10.0
                ),
            "thermalState" to thermalState(powerManager),
        )
    }

    private fun thermalState(powerManager: PowerManager): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return "unknown"
        }
        return when (powerManager.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> "nominal"
            PowerManager.THERMAL_STATUS_LIGHT -> "fair"
            PowerManager.THERMAL_STATUS_MODERATE -> "fair"
            PowerManager.THERMAL_STATUS_SEVERE -> "serious"
            PowerManager.THERMAL_STATUS_CRITICAL -> "critical"
            PowerManager.THERMAL_STATUS_EMERGENCY -> "critical"
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "critical"
            else -> "unknown"
        }
    }

    private fun normalizeToSpeechWav(
        audioPath: String,
        result: MethodChannel.Result,
        maxDurationMs: Long? = null,
    ) {
        if (audioPath.isBlank()) {
            result.error("invalid_audio_path", "Audio path is empty.", null)
            return
        }
        if (needsExternalAudioPermission(audioPath) && !hasExternalAudioPermission()) {
            if (pendingAudioNormalizeRequest != null) {
                result.error(
                    "audio_permission_busy",
                    "Another audio permission request is already pending.",
                    null,
                )
                return
            }
            pendingAudioNormalizeRequest = PendingAudioNormalizeRequest(
                audioPath,
                maxDurationMs,
                result,
            )
            requestPermissions(arrayOf(externalAudioPermission()), audioReadRequestCode)
            return
        }
        thread(name = "essential-audio-normalize", isDaemon = true) {
            try {
                val source = File(audioPath)
                if (!source.exists() || source.length() <= 0L) {
                    throw IllegalArgumentException("Audio file does not exist: $audioPath")
                }
                if (isRiffWavePcm(source)) {
                    runOnUiThread { result.success(source.absolutePath) }
                    return@thread
                }
                val normalizedDir = File(cacheDir, "normalized_audio").also { it.mkdirs() }
                val wavFile = File(
                    normalizedDir,
                    "audio-${source.name.hashCode()}-${source.length()}-${source.lastModified()}-${maxDurationMs ?: 0}.wav",
                )
                if (isRiffWavePcm(wavFile)) {
                    runOnUiThread { result.success(wavFile.absolutePath) }
                    return@thread
                }
                File(wavFile.parentFile, "${wavFile.name}.pcm").delete()
                if (wavFile.exists() && !isRiffWavePcm(wavFile)) {
                    wavFile.delete()
                }
                decodeCompressedAudioToWav(source, wavFile, maxDurationMs)
                runOnUiThread { result.success(wavFile.absolutePath) }
            } catch (error: Exception) {
                Log.w(genAiLogTag, "audio normalize failed", error)
                runOnUiThread {
                    result.error(
                        "audio_normalize_failed",
                        error.message ?: "Audio normalization failed.",
                        null,
                    )
                }
            }
        }
    }

    private fun needsExternalAudioPermission(audioPath: String): Boolean {
        return audioPath.startsWith("/sdcard/") ||
            audioPath.startsWith("/storage/emulated/")
    }

    private fun externalAudioPermission(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
    }

    private fun hasExternalAudioPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        return checkSelfPermission(externalAudioPermission()) == PackageManager.PERMISSION_GRANTED
    }

    private fun isRiffWavePcm(file: File): Boolean {
        if (!file.exists() || file.length() <= 44L) {
            return false
        }
        return try {
            val header = ByteArray(44)
            file.inputStream().use { input ->
                if (input.read(header) < header.size) {
                    return false
                }
            }
            String(header, 0, 4, Charsets.US_ASCII) == "RIFF" &&
                String(header, 8, 4, Charsets.US_ASCII) == "WAVE" &&
                header[20].toInt() == 1 &&
                header[34].toInt() == 16
        } catch (_: Exception) {
            false
        }
    }

    private fun preprocessForMeeting(audioPath: String, result: MethodChannel.Result) {
        if (audioPath.isBlank()) {
            result.error("invalid_audio_path", "Audio path is empty.", null)
            return
        }
        // The first practical implementation keeps the canonical 16 kHz WAV and
        // exposes the preprocessing stage to Dart. Heavy denoise models can be
        // added later without changing the Flutter contract.
        result.success(audioPath)
    }

    private fun splitSpeechWav(
        audioPath: String,
        result: MethodChannel.Result,
        chunkDurationMs: Long?,
    ) {
        if (audioPath.isBlank()) {
            result.error("invalid_audio_path", "Audio path is empty.", null)
            return
        }
        thread(name = "essential-audio-split", isDaemon = true) {
            try {
                val source = File(audioPath)
                if (!isRiffWavePcm(source)) {
                    throw IllegalArgumentException("Expected PCM16 WAV: $audioPath")
                }
                val info = readWavInfo(source)
                val blockAlign = info.channels * 2
                val bytesPerMs = info.sampleRate.toLong() * blockAlign / 1000L
                val targetBytes = ((chunkDurationMs ?: 300_000L) * bytesPerMs)
                    .coerceAtLeast(info.sampleRate.toLong() * blockAlign * 30L)
                val maxChunkBytes = (targetBytes / blockAlign * blockAlign).coerceAtLeast(blockAlign.toLong())
                if (info.dataSize <= maxChunkBytes) {
                    runOnUiThread { result.success(listOf(source.absolutePath)) }
                    return@thread
                }
                val directory = File(cacheDir, "meeting_audio_chunks").also { it.mkdirs() }
                val chunks = mutableListOf<String>()
                RandomAccessFile(source, "r").use { input ->
                    input.seek(info.dataOffset.toLong())
                    var remaining = info.dataSize.toLong()
                    var index = 0
                    val buffer = ByteArray(64 * 1024)
                    while (remaining > 0L) {
                        val pcmFile = File(directory, "${source.nameWithoutExtension}-chunk-$index.pcm")
                        val wavFile = File(directory, "${source.nameWithoutExtension}-chunk-$index.wav")
                        var written = 0L
                        pcmFile.outputStream().use { output ->
                            while (written < maxChunkBytes && remaining > 0L) {
                                val toRead = kotlin.math.min(
                                    buffer.size.toLong(),
                                    kotlin.math.min(maxChunkBytes - written, remaining),
                                ).toInt()
                                val read = input.read(buffer, 0, toRead)
                                if (read <= 0) {
                                    remaining = 0L
                                    break
                                }
                                output.write(buffer, 0, read)
                                written += read
                                remaining -= read
                            }
                        }
                        if (written > 0L) {
                            writeWavHeader(pcmFile, wavFile, info.sampleRate, info.channels, 16)
                            chunks.add(wavFile.absolutePath)
                        }
                        pcmFile.delete()
                        index++
                    }
                }
                runOnUiThread { result.success(chunks) }
            } catch (error: Exception) {
                Log.w(genAiLogTag, "audio split failed", error)
                runOnUiThread {
                    result.error(
                        "audio_split_failed",
                        error.message ?: "Audio split failed.",
                        null,
                    )
                }
            }
        }
    }

    private fun analyzeAudio(audioPath: String, result: MethodChannel.Result) {
        thread(name = "essential-audio-analyze", isDaemon = true) {
            try {
                val file = File(audioPath)
                val stats = readPcm16Stats(file)
                runOnUiThread {
                    result.success(
                        mapOf(
                            "duration_seconds" to stats.durationSeconds,
                            "rms" to stats.rms,
                            "peak" to stats.peak,
                            "speech_ratio" to stats.speechRatio,
                        ),
                    )
                }
            } catch (error: Exception) {
                Log.w(genAiLogTag, "audio analyze failed", error)
                runOnUiThread {
                    result.error(
                        "audio_analyze_failed",
                        error.message ?: "Audio analysis failed.",
                        null,
                    )
                }
            }
        }
    }

    private fun detectSilenceRegions(audioPath: String, result: MethodChannel.Result) {
        thread(name = "essential-audio-silence", isDaemon = true) {
            try {
                val file = File(audioPath)
                val regions = readSilenceRegions(file)
                runOnUiThread { result.success(regions) }
            } catch (error: Exception) {
                Log.w(genAiLogTag, "audio silence detection failed", error)
                runOnUiThread {
                    result.error(
                        "audio_silence_failed",
                        error.message ?: "Audio silence detection failed.",
                        null,
                    )
                }
            }
        }
    }

    private data class Pcm16Stats(
        val durationSeconds: Double,
        val rms: Double,
        val peak: Double,
        val speechRatio: Double,
    )

    private fun readPcm16Stats(file: File): Pcm16Stats {
        val wav = readWavPcm16(file)
        var sumSquares = 0.0
        var peak = 0
        var speechSamples = 0
        for (sample in wav.samples) {
            val abs = kotlin.math.abs(sample.toInt())
            peak = kotlin.math.max(peak, abs)
            sumSquares += abs.toDouble() * abs.toDouble()
            if (abs > 650) {
                speechSamples++
            }
        }
        val sampleCount = wav.samples.size.coerceAtLeast(1)
        val rms = kotlin.math.sqrt(sumSquares / sampleCount) / Short.MAX_VALUE
        return Pcm16Stats(
            durationSeconds = sampleCount.toDouble() / wav.sampleRate,
            rms = rms.coerceIn(0.0, 1.0),
            peak = (peak.toDouble() / Short.MAX_VALUE).coerceIn(0.0, 1.0),
            speechRatio = (speechSamples.toDouble() / sampleCount).coerceIn(0.0, 1.0),
        )
    }

    private fun readSilenceRegions(file: File): List<Map<String, Any>> {
        val wav = readWavPcm16(file)
        val window = (wav.sampleRate / 4).coerceAtLeast(1)
        val regions = mutableListOf<Map<String, Any>>()
        var silenceStart: Double? = null
        var offset = 0
        while (offset < wav.samples.size) {
            val end = kotlin.math.min(wav.samples.size, offset + window)
            var sum = 0.0
            for (index in offset until end) {
                sum += kotlin.math.abs(wav.samples[index].toInt()).toDouble()
            }
            val avg = sum / (end - offset).coerceAtLeast(1)
            val isSilent = avg < 420.0
            val startSeconds = offset.toDouble() / wav.sampleRate
            val endSeconds = end.toDouble() / wav.sampleRate
            if (isSilent && silenceStart == null) {
                silenceStart = startSeconds
            } else if (!isSilent && silenceStart != null) {
                if (startSeconds - silenceStart >= 0.7) {
                    regions.add(mapOf("start_seconds" to silenceStart, "end_seconds" to startSeconds))
                }
                silenceStart = null
            }
            if (end >= wav.samples.size && silenceStart != null && endSeconds - silenceStart >= 0.7) {
                regions.add(mapOf("start_seconds" to silenceStart, "end_seconds" to endSeconds))
            }
            offset = end
        }
        return regions
    }

    private data class WavPcm16(val sampleRate: Int, val samples: ShortArray)
    private data class WavInfo(
        val sampleRate: Int,
        val channels: Int,
        val dataOffset: Int,
        val dataSize: Int,
    )

    private fun readWavInfo(file: File): WavInfo {
        RandomAccessFile(file, "r").use { input ->
            if (input.length() < 44L) {
                throw IllegalArgumentException("WAV file is too small.")
            }
            val header = ByteArray(12)
            input.readFully(header)
            if (
                String(header, 0, 4, Charsets.US_ASCII) != "RIFF" ||
                String(header, 8, 4, Charsets.US_ASCII) != "WAVE"
            ) {
                throw IllegalArgumentException("Expected RIFF WAVE.")
            }
            var sampleRate = 16000
            var channels = 1
            var dataOffset = -1
            var dataSize = 0
            val chunkHeader = ByteArray(8)
            while (input.filePointer + 8 <= input.length()) {
                input.readFully(chunkHeader)
                val chunkId = String(chunkHeader, 0, 4, Charsets.US_ASCII)
                val chunkSize = readLittleEndianInt(chunkHeader, 4)
                val chunkStart = input.filePointer
                if (chunkId == "fmt " && chunkSize >= 16) {
                    val fmt = ByteArray(chunkSize.coerceAtMost(32))
                    input.readFully(fmt)
                    val format = readLittleEndianShort(fmt, 0)
                    channels = readLittleEndianShort(fmt, 2).coerceAtLeast(1)
                    sampleRate = readLittleEndianInt(fmt, 4).coerceAtLeast(1)
                    val bitDepth = readLittleEndianShort(fmt, 14)
                    if (format != 1 || bitDepth != 16) {
                        throw IllegalArgumentException("Expected PCM16 WAV.")
                    }
                } else if (chunkId == "data") {
                    dataOffset = chunkStart.toInt()
                    dataSize = chunkSize.coerceAtMost((input.length() - chunkStart).toInt())
                    break
                }
                input.seek(chunkStart + chunkSize + (chunkSize and 1))
            }
            if (dataOffset < 0 || dataSize <= 0) {
                throw IllegalArgumentException("WAV data chunk was not found.")
            }
            return WavInfo(sampleRate, channels, dataOffset, dataSize)
        }
    }

    private fun readWavPcm16(file: File): WavPcm16 {
        if (!isRiffWavePcm(file)) {
            throw IllegalArgumentException("Expected PCM16 WAV: ${file.absolutePath}")
        }
        val bytes = file.readBytes()
        var cursor = 12
        var sampleRate = 16000
        var dataOffset = -1
        var dataSize = 0
        while (cursor + 8 <= bytes.size) {
            val chunkId = String(bytes, cursor, 4, Charsets.US_ASCII)
            val chunkSize = readLittleEndianInt(bytes, cursor + 4)
            val chunkStart = cursor + 8
            if (chunkId == "fmt " && chunkStart + 16 <= bytes.size) {
                sampleRate = readLittleEndianInt(bytes, chunkStart + 4)
            } else if (chunkId == "data") {
                dataOffset = chunkStart
                dataSize = kotlin.math.min(chunkSize, bytes.size - chunkStart)
                break
            }
            cursor = chunkStart + chunkSize + (chunkSize and 1)
        }
        if (dataOffset < 0 || dataSize <= 0) {
            throw IllegalArgumentException("WAV data chunk was not found.")
        }
        val samples = ShortArray(dataSize / 2)
        var index = 0
        var byteIndex = dataOffset
        while (index < samples.size && byteIndex + 1 < bytes.size) {
            val lo = bytes[byteIndex].toInt() and 0xff
            val hi = bytes[byteIndex + 1].toInt()
            samples[index] = ((hi shl 8) or lo).toShort()
            index++
            byteIndex += 2
        }
        return WavPcm16(sampleRate, samples)
    }

    private fun readLittleEndianInt(bytes: ByteArray, offset: Int): Int {
        if (offset + 3 >= bytes.size) return 0
        return (bytes[offset].toInt() and 0xff) or
            ((bytes[offset + 1].toInt() and 0xff) shl 8) or
            ((bytes[offset + 2].toInt() and 0xff) shl 16) or
            ((bytes[offset + 3].toInt() and 0xff) shl 24)
    }

    private fun readLittleEndianShort(bytes: ByteArray, offset: Int): Int {
        if (offset + 1 >= bytes.size) return 0
        return (bytes[offset].toInt() and 0xff) or
            ((bytes[offset + 1].toInt() and 0xff) shl 8)
    }

    private fun decodeCompressedAudioToWav(
        source: File,
        wavFile: File,
        maxDurationMs: Long? = null,
    ) {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        val pcmFile = File(wavFile.parentFile, "${wavFile.name}.pcm")
        var sampleRate = 16000
        var channels = 1
        val maxDurationUs = maxDurationMs?.takeIf { it > 0L }?.times(1000L)
        try {
            extractor.setDataSource(source.absolutePath)
            var audioTrackIndex = -1
            var inputFormat: MediaFormat? = null
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME).orEmpty()
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = index
                    inputFormat = format
                    sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    break
                }
            }
            if (audioTrackIndex < 0 || inputFormat == null) {
                throw IllegalArgumentException("No audio track found.")
            }
            extractor.selectTrack(audioTrackIndex)
            val mime = inputFormat.getString(MediaFormat.KEY_MIME).orEmpty()
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(inputFormat, null, null, 0)
            codec.start()

            val bufferInfo = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            pcmFile.outputStream().use { pcmOutput ->
                while (!outputDone) {
                    if (!inputDone) {
                        val inputBufferIndex = codec.dequeueInputBuffer(10_000)
                        if (inputBufferIndex >= 0) {
                            val inputBuffer = codec.getInputBuffer(inputBufferIndex)
                            val sampleSize = if (inputBuffer == null) {
                                -1
                            } else {
                                extractor.readSampleData(inputBuffer, 0)
                            }
                            if (
                                sampleSize < 0 ||
                                    (maxDurationUs != null && extractor.sampleTime >= maxDurationUs)
                            ) {
                                codec.queueInputBuffer(
                                    inputBufferIndex,
                                    0,
                                    0,
                                    0L,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                )
                                inputDone = true
                            } else {
                                codec.queueInputBuffer(
                                    inputBufferIndex,
                                    0,
                                    sampleSize,
                                    extractor.sampleTime,
                                    0,
                                )
                                extractor.advance()
                            }
                        }
                    }

                    when (val outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)) {
                        MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            val outputFormat = codec.outputFormat
                            sampleRate = outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                            channels = outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                            val encoding = if (
                                outputFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)
                            ) {
                                outputFormat.getInteger(MediaFormat.KEY_PCM_ENCODING)
                            } else {
                                android.media.AudioFormat.ENCODING_PCM_16BIT
                            }
                            if (encoding != android.media.AudioFormat.ENCODING_PCM_16BIT) {
                                throw IllegalStateException(
                                    "Unsupported decoded PCM encoding: $encoding",
                                )
                            }
                        }
                        else -> {
                            if (outputBufferIndex >= 0) {
                                val outputBuffer = codec.getOutputBuffer(outputBufferIndex)
                                if (
                                    outputBuffer != null &&
                                        bufferInfo.size > 0 &&
                                        (
                                            maxDurationUs == null ||
                                                bufferInfo.presentationTimeUs <= maxDurationUs
                                            )
                                ) {
                                    val chunk = ByteArray(bufferInfo.size)
                                    outputBuffer.position(bufferInfo.offset)
                                    outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                                    outputBuffer.get(chunk)
                                    pcmOutput.write(chunk)
                                }
                                outputDone =
                                    bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0 ||
                                    (maxDurationUs != null &&
                                        bufferInfo.presentationTimeUs >= maxDurationUs)
                                codec.releaseOutputBuffer(outputBufferIndex, false)
                            }
                        }
                    }
                }
            }
            writeWavHeader(pcmFile, wavFile, sampleRate, channels, 16)
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            try {
                codec?.release()
            } catch (_: Exception) {
            }
            extractor.release()
            pcmFile.delete()
        }
    }

    private fun startInternalAudio(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("unsupported", "Internal audio capture requires Android 10+", null)
            return
        }
        val projection = mediaProjection
        if (projection == null) {
            result.error("no_permission", "Screen capture permission is required first.", null)
            return
        }
        if (isRecordingInternalAudio) {
            result.error("already_running", "Internal audio recording is already running.", null)
            return
        }

        try {
            val config = android.media.AudioPlaybackCaptureConfiguration.Builder(projection)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .build()

            val format = android.media.AudioFormat.Builder()
                .setEncoding(android.media.AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(16000)
                .setChannelMask(android.media.AudioFormat.CHANNEL_IN_MONO)
                .build()

            val bufferSize = android.media.AudioRecord.getMinBufferSize(16000, android.media.AudioFormat.CHANNEL_IN_MONO, android.media.AudioFormat.ENCODING_PCM_16BIT)
            val audioRecord = android.media.AudioRecord.Builder()
                .setAudioFormat(format)
                .setAudioPlaybackCaptureConfig(config)
                .setBufferSizeInBytes(bufferSize)
                .build()

            internalAudioRecord = audioRecord
            val directory = File(cacheDir, "internal_audio").also { it.mkdirs() }
            val file = File(directory, "audio-${System.currentTimeMillis()}.wav")
            internalAudioPath = file.absolutePath

            audioRecord.startRecording()
            isRecordingInternalAudio = true

            internalAudioThread = thread(name = "essential-internal-audio", isDaemon = true) {
                val pcmFile = File(directory, "temp_pcm-${System.currentTimeMillis()}.raw")
                pcmFile.outputStream().use { output ->
                    val buffer = ByteArray(bufferSize)
                    while (isRecordingInternalAudio) {
                        val read = audioRecord.read(buffer, 0, buffer.size)
                        if (read > 0) {
                            output.write(buffer, 0, read)
                        }
                    }
                }

                writeWavHeader(pcmFile, file, 16000, 1, 16)
                pcmFile.delete()
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("recording_failed", e.message, null)
        }
    }

    private fun stopInternalAudio(result: MethodChannel.Result) {
        if (!isRecordingInternalAudio) {
            result.success(null)
            return
        }
        isRecordingInternalAudio = false
        internalAudioRecord?.stop()
        internalAudioRecord?.release()
        internalAudioRecord = null
        internalAudioThread?.join()

        result.success(internalAudioPath)
    }

    private fun writeWavHeader(pcmFile: File, wavFile: File, sampleRate: Int, channels: Int, bitDepth: Int) {
        val pcmDataLength = pcmFile.length()
        val totalDataLength = pcmDataLength + 36
        val byteRate = sampleRate * channels * bitDepth / 8
        val blockAlign = channels * bitDepth / 8

        val header = ByteArray(44)
        header[0] = 'R'.code.toByte()
        header[1] = 'I'.code.toByte()
        header[2] = 'F'.code.toByte()
        header[3] = 'F'.code.toByte()
        header[4] = (totalDataLength and 0xff).toByte()
        header[5] = ((totalDataLength shr 8) and 0xff).toByte()
        header[6] = ((totalDataLength shr 16) and 0xff).toByte()
        header[7] = ((totalDataLength shr 24) and 0xff).toByte()
        header[8] = 'W'.code.toByte()
        header[9] = 'A'.code.toByte()
        header[10] = 'V'.code.toByte()
        header[11] = 'E'.code.toByte()
        header[12] = 'f'.code.toByte()
        header[13] = 'm'.code.toByte()
        header[14] = 't'.code.toByte()
        header[15] = ' '.code.toByte()
        header[16] = 16
        header[17] = 0
        header[18] = 0
        header[19] = 0
        header[20] = 1
        header[21] = 0
        header[22] = channels.toByte()
        header[23] = 0
        header[24] = (sampleRate and 0xff).toByte()
        header[25] = ((sampleRate shr 8) and 0xff).toByte()
        header[26] = ((sampleRate shr 16) and 0xff).toByte()
        header[27] = ((sampleRate shr 24) and 0xff).toByte()
        header[28] = (byteRate and 0xff).toByte()
        header[29] = ((byteRate shr 8) and 0xff).toByte()
        header[30] = ((byteRate shr 16) and 0xff).toByte()
        header[31] = ((byteRate shr 24) and 0xff).toByte()
        header[32] = blockAlign.toByte()
        header[33] = 0
        header[34] = bitDepth.toByte()
        header[35] = 0
        header[36] = 'd'.code.toByte()
        header[37] = 'a'.code.toByte()
        header[38] = 't'.code.toByte()
        header[39] = 'a'.code.toByte()
        header[40] = (pcmDataLength and 0xff).toByte()
        header[41] = ((pcmDataLength shr 8) and 0xff).toByte()
        header[42] = ((pcmDataLength shr 16) and 0xff).toByte()
        header[43] = ((pcmDataLength shr 24) and 0xff).toByte()

        wavFile.outputStream().use { output ->
            output.write(header, 0, 44)
            pcmFile.inputStream().use { input ->
                input.copyTo(output)
            }
        }
    }
}
