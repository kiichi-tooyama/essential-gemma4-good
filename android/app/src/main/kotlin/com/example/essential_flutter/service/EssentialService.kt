package com.example.essential_flutter.service

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.speech.tts.TextToSpeech
import android.util.Log
import com.example.essential_flutter.MainActivity
import com.example.essential_flutter.ai.GalleryLiteRtLmRequest
import com.example.essential_flutter.ai.GalleryLiteRtLmRuntime
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class EssentialService : Service() {
    private companion object {
        const val TAG = "EssentialService"
        const val MAX_MEDIA_COPY_BYTES = 64L * 1024L * 1024L
        const val FOREGROUND_NOTIFICATION_ID = 4104
        const val FOREGROUND_CHANNEL_ID = "essential_sdk_inference"
        const val MAX_INTERNAL_WEB_RESULTS = 4
    }

    private val liteRtLmRuntime by lazy { GalleryLiteRtLmRuntime(applicationContext) }
    private val executor = Executors.newCachedThreadPool()
    private val attachedAdapters = ConcurrentHashMap<String, String>()
    private val activeInferenceCount = java.util.concurrent.atomic.AtomicInteger(0)
    private var tts: TextToSpeech? = null
    @Volatile
    private var ttsReady = false

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        executor.shutdownNow()
        liteRtLmRuntime.close()
        tts?.shutdown()
        tts = null
        stopInferenceForeground(force = true)
        super.onDestroy()
    }

    private val binder = object : IEssentialService.Stub() {
        override fun listModels(): String {
            val models = JSONArray()
            val localModels = discoverInstalledModels()
            Log.i(TAG, "listModels discovered=${localModels.size} models=${localModels.map { it.modelId }}")

            localModels.forEach { model ->
                models.put(
                    JSONObject()
                        .put("modelId", model.modelId)
                        .put("family", "llm")
                        .put("path", model.path)
                        .put("sizeBytes", model.sizeBytes)
                        .put("route", model.route)
                        .put("runtimeFamily", model.runtimeFamily)
                        .put("supportsImage", model.supportsImage)
                        .put("supportsAudio", model.supportsAudio),
                )
            }
            return JSONObject().put("models", models).toString()
        }

        override fun listAdapters(callerPackage: String?, modelId: String?): String {
            return JSONObject().put("adapters", JSONArray()).toString()
        }

        override fun runInference(requestJson: String): String {
            startInferenceForeground()
            val request = JSONObject(requestJson)
            val requestId = request.optString("requestId").ifBlank { UUID.randomUUID().toString() }
            return try {
                val taskType = request.taskType()
                Log.i(TAG, "runInference start requestId=$requestId taskType=$taskType")
                if (taskType == "stt") {
                    return completedResponse(
                        requestId,
                        "stt",
                        request.audioTranscriptFallback(),
                        "android-speechrecognizer",
                        JSONObject()
                            .put("mode", "speech_to_text")
                            .put("engine", "android_speech_recognizer")
                            .put("input", "provided_transcript"),
                    )
                }
                if (taskType == "tts") {
                    val prompt = request.prompt()
                    val playback = speak(prompt)
                    return completedResponse(
                        requestId,
                        "tts",
                        prompt,
                        "android_tts",
                        JSONObject()
                            .put("mode", "text_to_speech")
                            .put("engine", "android_tts")
                            .put("playbackEngine", "android_tts")
                            .put("audioPlaybackStatus", playback),
                    )
                }
                val prompt = request.promptForTask()
                val modelRequirement = request.optJSONObject("modelRequirement")
                val modelPath = resolveModelPath(modelRequirement)
                    ?.takeIf { it.isNotBlank() && it != "null" }

                if (modelPath == null) {
                    val requestedModelId = modelRequirement?.optString("modelId")
                    Log.i(TAG, "runInference missing_model requestId=$requestId model=$requestedModelId")
                    return errorResponse(
                        requestId,
                        "MODEL_NOT_INSTALLED",
                        "LiteRT-LM model is not installed.",
                    )
                }

                val params = request.optJSONObject("generationParams") ?: JSONObject()
                Log.i(TAG, "runInference native requestId=$requestId modelPath=$modelPath")
                if (!modelPath.endsWith(".litertlm", ignoreCase = true)) {
                    return errorResponse(
                        requestId,
                        "MODEL_INCOMPATIBLE",
                        "Essential service only supports LiteRT-LM .litertlm models.",
                    )
                }
                val media = request.mediaPaths(requestId)
                val output = generateBlockingWithMediaFallback(
                    requestId = requestId,
                    modelPath = modelPath,
                    prompt = prompt,
                    systemInstruction = request.optString("systemInstruction"),
                    media = media,
                    params = params,
                )
                val metadata = request.taskMetadata()
                    .put("route", "litertlm")
                    .put("runtimeFamily", "google-ai-edge-litertlm")
                    .put("latencyMs", output.latencyMs)
                    .put("loadAndSetupMs", output.loadAndSetupMs)
                    .put("generationMs", output.generationMs)
                    .put("accelerator", output.accelerator)
                    .put("visionAccelerator", output.visionAccelerator)
                    .put("supportsImage", output.supportsImage)
                    .put("supportsAudio", output.supportsAudio)
                    .put("imagePathCount", media.imagePaths.size)
                    .put("audioPathCount", media.audioPaths.size)
                val finalText = if (taskType == "voice_conversation") {
                    val playback = speak(output.text)
                    metadata.put("audioPlaybackStatus", playback)
                    output.text
                } else {
                    output.text
                }
                return completedResponse(
                    requestId,
                    taskType,
                    finalText,
                    File(modelPath).nameWithoutExtension,
                    metadata,
                )
            } catch (throwable: Throwable) {
                Log.e(TAG, "runInference failed requestId=$requestId", throwable)
                return errorResponse(
                    requestId,
                    "RUNTIME_UNAVAILABLE",
                    throwable.message ?: "Essential inference failed.",
                )
            } finally {
                liteRtLmRuntime.releaseIdle()
                stopInferenceForeground()
            }
        }

        override fun streamInference(requestJson: String, callback: IEssentialStreamCallback) {
            startInferenceForeground()
            executor.execute {
                val request = JSONObject(requestJson)
                val requestId = request.optString("requestId").ifBlank { UUID.randomUUID().toString() }
                runCatching {
                    val taskType = request.taskType()
                    val prompt = request.promptForTask()
                    val modelRequirement = request.optJSONObject("modelRequirement")
                    val modelPath = resolveModelPath(modelRequirement)
                        ?.takeIf { it.isNotBlank() && it != "null" }

                    if (modelPath == null) {
                        callback.onError(requestId, "MODEL_NOT_INSTALLED", "LiteRT-LM model is not installed.")
                        return@execute
                    }

                    val params = request.optJSONObject("generationParams") ?: JSONObject()
                    if (!modelPath.endsWith(".litertlm", ignoreCase = true)) {
                        callback.onError(
                            requestId,
                            "MODEL_INCOMPATIBLE",
                            "Essential service only supports LiteRT-LM .litertlm models.",
                        )
                        return@execute
                    }
                    val media = request.mediaPaths(requestId)
                    val output = generateBlockingWithMediaFallback(
                        requestId = requestId,
                        modelPath = modelPath,
                        prompt = prompt,
                        systemInstruction = request.optString("systemInstruction"),
                        media = media,
                        params = params,
                    ) { token ->
                        callback.onChunk(
                            requestId,
                            chunkResponse(requestId, token, File(modelPath).nameWithoutExtension),
                        )
                    }
                    val metadata = request.taskMetadata()
                        .put("route", "litertlm")
                        .put("runtimeFamily", "google-ai-edge-litertlm")
                        .put("latencyMs", output.latencyMs)
                        .put("loadAndSetupMs", output.loadAndSetupMs)
                        .put("generationMs", output.generationMs)
                        .put("accelerator", output.accelerator)
                        .put("visionAccelerator", output.visionAccelerator)
                        .put("supportsImage", output.supportsImage)
                        .put("supportsAudio", output.supportsAudio)
                        .put("imagePathCount", media.imagePaths.size)
                        .put("audioPathCount", media.audioPaths.size)
                    if (taskType == "voice_conversation") {
                        metadata.put("audioPlaybackStatus", speak(output.text))
                    }
                    callback.onComplete(
                        requestId,
                        completedResponse(
                            requestId,
                            taskType,
                            output.text,
                            File(modelPath).nameWithoutExtension,
                            metadata,
                        ),
                    )
                }.onFailure { throwable ->
                    callback.onError(requestId, "RUNTIME_UNAVAILABLE", throwable.message ?: "Inference failed.")
                }.also {
                    liteRtLmRuntime.releaseIdle()
                    stopInferenceForeground()
                }
            }
        }

        override fun attachAdapter(sessionId: String, adapterId: String, callerPackage: String?): Boolean {
            attachedAdapters[sessionId] = adapterId
            return true
        }

        override fun detachAdapter(sessionId: String, callerPackage: String?): Boolean {
            attachedAdapters.remove(sessionId)
            return true
        }

        override fun cancel(requestId: String): Boolean {
            return liteRtLmRuntime.cancel(requestId)
        }
    }

    private fun generateBlockingWithMediaFallback(
        requestId: String,
        modelPath: String,
        prompt: String,
        systemInstruction: String,
        media: MediaPaths,
        params: JSONObject,
        onToken: ((String) -> Unit)? = null,
    ): com.example.essential_flutter.ai.GalleryLiteRtLmResult {
        val baseRequest = GalleryLiteRtLmRequest(
            requestId = requestId,
            modelPath = modelPath,
            prompt = prompt,
            systemInstruction = systemInstruction,
            imagePaths = media.imagePaths,
            audioPaths = media.audioPaths,
            maxTokens = params.optInt("maxTokens", 1024),
            topK = params.optInt("topK", 64),
            topP = params.optDouble("topP", 0.95),
            temperature = params.optDouble("temperature", 1.0),
            accelerator = params.optString("accelerator", "auto"),
            visionAccelerator = params.optString("visionAccelerator", "gpu"),
            enableThinking = params.optBoolean("enableThinking", false),
        )
        return try {
            liteRtLmRuntime.generateBlocking(baseRequest, onToken)
        } catch (error: Throwable) {
            if (media.imagePaths.isEmpty() && media.audioPaths.isEmpty()) {
                throw error
            }
            Log.w(
                TAG,
                "media inference failed; retrying text-only requestId=$requestId images=${media.imagePaths.size} audio=${media.audioPaths.size}",
                error,
            )
            liteRtLmRuntime.generateBlocking(
                baseRequest.copy(
                    prompt = prompt.withMediaFallbackNote(media),
                    imagePaths = emptyList(),
                    audioPaths = emptyList(),
                    visionAccelerator = "cpu",
                ),
                onToken,
            )
        }
    }

    private fun discoverInstalledModels(): List<LocalModel> {
        ensureBundledLiteRtLmModelsImported()
        val roots = listOf(
            File(filesDir, "essential_models"),
            File(getExternalFilesDir(null), "essential_models"),
            File(filesDir, "genai_models"),
            File(cacheDir, "genai_models"),
            File(getExternalFilesDir(null), "genai_models"),
        )
        val metadataModels = roots
            .filter { it.exists() && it.isDirectory }
            .flatMap { root -> modelsFromMetadata(File(root, "metadata.json")) }
        val scannedModels = roots
            .filter { it.exists() && it.isDirectory }
            .flatMap { root ->
                root.walkTopDown()
                    .filter {
                        it.isFile && it.extension.equals("litertlm", ignoreCase = true)
                    }
                    .toList()
            }
            .map { file ->
                LocalModel(
                    modelId = inferModelId(file),
                    path = file.absolutePath,
                    sizeBytes = file.length(),
                    route = "litertlm",
                    runtimeFamily = "google-ai-edge-litertlm",
                    supportsImage = inferSupportsImage(file),
                    supportsAudio = inferSupportsAudio(file),
                )
            }
        return (metadataModels + scannedModels)
            .distinctBy { it.modelId }
            .sortedWith(compareBy<LocalModel> { modelPriority(it.modelId) }.thenBy { it.modelId })
    }

    private fun ensureBundledLiteRtLmModelsImported() {
        val assetNames = runCatching {
            assets.list("")?.filter { it.endsWith(".litertlm", ignoreCase = true) }.orEmpty()
        }.getOrElse { error ->
            Log.w(TAG, "Unable to list bundled model assets", error)
            emptyList()
        }
        if (assetNames.isEmpty()) {
            return
        }
        val outputDir = File(filesDir, "genai_models/bundled").apply { mkdirs() }
        assetNames.forEach { assetName ->
            val output = File(outputDir, assetName)
            if (output.exists() && output.length() > 0L) {
                return@forEach
            }
            runCatching {
                assets.open(assetName).use { input ->
                    output.outputStream().use { target ->
                        input.copyTo(target)
                    }
                }
                Log.i(TAG, "Imported bundled LiteRT-LM model asset=$assetName path=${output.absolutePath} size=${output.length()}")
            }.onFailure { error ->
                output.delete()
                Log.w(TAG, "Failed to import bundled LiteRT-LM model asset=$assetName", error)
            }
        }
    }

    private fun modelsFromMetadata(metadataFile: File): List<LocalModel> {
        if (!metadataFile.exists() || !metadataFile.isFile) {
            return emptyList()
        }
        return runCatching {
            val metadata = JSONObject(metadataFile.readText())
            val rows = listOf(
                metadata.optJSONArray("installations") ?: JSONArray(),
                metadata.optJSONArray("bundle_components") ?: JSONArray(),
            )
            buildList {
                rows.forEach { array ->
                    for (index in 0 until array.length()) {
                        val item = array.optJSONObject(index) ?: continue
                        val modelId = item.optString("model_id").takeIf { it.isNotBlank() }
                            ?: continue
                        val activePath = item.optString("active_path").takeIf { it.isNotBlank() }
                            ?: continue
                        val file = File(activePath)
                        Log.i(
                            TAG,
                            "metadata model=$modelId path=${file.absolutePath} exists=${file.exists()} size=${file.length()}",
                        )
                        if (
                            file.exists() &&
                                file.isFile &&
                                file.extension.equals("litertlm", ignoreCase = true)
                        ) {
                            add(
                                LocalModel(
                                    modelId = modelId,
                                    path = file.absolutePath,
                                    sizeBytes = item.optLong("size_bytes", file.length()),
                                    route = "litertlm",
                                    runtimeFamily = "google-ai-edge-litertlm",
                                    supportsImage = item.optBoolean("supports_image", inferSupportsImage(file)),
                                    supportsAudio = item.optBoolean("supports_audio", inferSupportsAudio(file)),
                                ),
                            )
                        }
                    }
                }
            }
        }.getOrElse { error ->
            Log.w(TAG, "Failed to read model metadata ${metadataFile.absolutePath}", error)
            emptyList()
        }
    }

    private fun inferModelId(file: File): String {
        val normalized = file.nameWithoutExtension.lowercase()
        return when {
            normalized.contains("gemma-4-e4b-it") -> "gemma-4-e4b-it"
            normalized.contains("gemma-4-e2b-it") -> "gemma-4-e2b-it"
            normalized.contains("gemma-3n-e4b") -> "gemma-3n-e4b-it"
            normalized.contains("gemma-3n-e2b") -> "gemma-3n-e2b-it"
            normalized.contains("gemma3-1b") -> "gemma3-1b-it"
            normalized.contains("tinyllama") -> "essential-mini"
            else -> file.nameWithoutExtension
        }
    }

    private fun modelPriority(modelId: String): Int {
        return when (modelId) {
            "gemma-4-e4b-it" -> 0
            "gemma-4-e2b-it" -> 1
            "gemma-3n-e4b-it" -> 2
            "gemma-3n-e2b-it" -> 3
            "essential-mini" -> 2
            else -> 10
        }
    }

    private fun inferSupportsImage(file: File): Boolean {
        val normalized = file.name.lowercase(Locale.US)
        return normalized.contains("gemma-4") || normalized.contains("gemma-3n")
    }

    private fun inferSupportsAudio(file: File): Boolean {
        val normalized = file.name.lowercase(Locale.US)
        return normalized.contains("gemma-4") || normalized.contains("gemma-3n")
    }

    private fun resolveModelPath(modelRequirement: JSONObject?): String? {
        val explicit = modelRequirement?.optString("modelPath")
            ?.takeIf { it.isNotBlank() && it != "null" }
        if (explicit != null) {
            return explicit
        }
        val requestedModelId = modelRequirement?.optString("modelId")
            ?.takeIf { it.isNotBlank() && it != "null" }
            ?: return null
        return discoverInstalledModels().firstOrNull { it.modelId == requestedModelId }?.path
    }

    private fun JSONObject.prompt(): String {
        return optJSONObject("input")?.optString("prompt")?.takeIf { it.isNotBlank() }
            ?: optString("prompt")
    }

    private fun JSONObject.taskType(): String {
        return optString("taskType").ifBlank { "text_generation" }
    }

    private fun JSONObject.attachments(): JSONArray {
        return optJSONObject("input")?.optJSONArray("attachments") ?: JSONArray()
    }

    private fun JSONObject.referenceDocuments(): JSONArray {
        return optJSONObject("input")?.optJSONArray("referenceDocuments") ?: JSONArray()
    }

    private fun JSONObject.runtimeOptions(): JSONObject {
        return optJSONObject("runtimeOptions") ?: JSONObject()
    }

    private fun JSONObject.mediaPaths(requestId: String): MediaPaths {
        val attachments = attachments()
        val imagePaths = mutableListOf<String>()
        val audioPaths = mutableListOf<String>()
        for (index in 0 until attachments.length()) {
            val item = attachments.optJSONObject(index) ?: continue
            val kind = item.optString("kind").lowercase(Locale.US)
            val mimeType = item.optString("mimeType").lowercase(Locale.US)
            val path = item.optString("filePath")
                .takeIf { it.isNotBlank() && it != "null" }
                ?: item.optString("path").takeIf { it.isNotBlank() && it != "null" }
                ?: item.optString("uri")
                    .takeIf { it.isNotBlank() && it != "null" }
                    ?.let { cacheMediaUri(it, requestId, index, mimeType) }
                ?: continue
            if (!File(path).exists()) {
                Log.w(TAG, "media attachment missing path=$path")
                continue
            }
            when {
                kind == "image" || mimeType.startsWith("image/") -> imagePaths.add(path)
                kind == "audio" || mimeType.startsWith("audio/") -> audioPaths.add(path)
            }
        }
        return MediaPaths(imagePaths = imagePaths, audioPaths = audioPaths)
    }

    private fun cacheMediaUri(uriString: String, requestId: String, index: Int, mimeType: String): String? {
        val uri = runCatching { Uri.parse(uriString) }.getOrNull() ?: return null
        val extension = when {
            mimeType.contains("png") -> "png"
            mimeType.contains("webp") -> "webp"
            mimeType.contains("wav") -> "wav"
            mimeType.contains("mpeg") || mimeType.contains("mp3") -> "mp3"
            mimeType.startsWith("audio/") -> "wav"
            mimeType.startsWith("image/") -> "jpg"
            else -> "bin"
        }
        val outputDir = File(cacheDir, "sdk_media/$requestId").apply { mkdirs() }
        val outputFile = File(outputDir, "attachment_$index.$extension")
        return runCatching {
            contentResolver.openInputStream(uri)?.use { input ->
                outputFile.outputStream().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var copied = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) {
                            break
                        }
                        copied += read
                        if (copied > MAX_MEDIA_COPY_BYTES) {
                            throw IllegalArgumentException("Media attachment is too large.")
                        }
                        output.write(buffer, 0, read)
                    }
                }
            } ?: return null
            Log.i(TAG, "cached media uri=$uriString path=${outputFile.absolutePath} size=${outputFile.length()}")
            outputFile.absolutePath
        }.getOrElse { error ->
            Log.w(TAG, "failed to cache media uri=$uriString", error)
            null
        }
    }

    private fun startInferenceForeground() {
        val count = activeInferenceCount.incrementAndGet()
        if (count != 1) {
            return
        }
        runCatching {
            ensureNotificationChannel()
            startForeground(FOREGROUND_NOTIFICATION_ID, inferenceNotification())
            Log.i(TAG, "foreground inference started")
        }.onFailure { error ->
            Log.w(TAG, "Unable to start foreground inference service", error)
        }
    }

    private fun stopInferenceForeground(force: Boolean = false) {
        val count = if (force) {
            activeInferenceCount.set(0)
            0
        } else {
            activeInferenceCount.decrementAndGet().coerceAtLeast(0)
        }
        if (count > 0) {
            return
        }
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(FOREGROUND_CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    FOREGROUND_CHANNEL_ID,
                    "Essential SDK inference",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
    }

    private fun inferenceNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, FOREGROUND_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentTitle("Essential SDK")
            .setContentText("外部アプリのAI推論を実行中")
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun JSONObject.promptForTask(): String {
        val prompt = prompt()
        val taskType = taskType()
        val attachments = attachments()
        val references = referenceDocuments()
        val runtimeContext = runtimePromptContext()
        val internalApiContext = internalApiPromptContext(prompt)
        if (attachments.length() == 0 && references.length() == 0) {
            return listOf(runtimeContext, internalApiContext, prompt)
                .filter { it.isNotBlank() }
                .joinToString("\n\n")
        }
        val mediaSummary = buildString {
            for (index in 0 until attachments.length()) {
                val item = attachments.optJSONObject(index) ?: continue
                append("\n- ")
                append(item.optString("kind", "media"))
                item.optString("mimeType").takeIf { it.isNotBlank() && it != "null" }?.let {
                    append(" mime=").append(it)
                }
                item.optString("filePath").takeIf { it.isNotBlank() && it != "null" }?.let {
                    append(" file=").append(File(it).name)
                }
                item.optString("uri").takeIf { it.isNotBlank() && it != "null" }?.let {
                    append(" uri=").append(it)
                }
            }
        }
        val referenceSummary = buildString {
            for (index in 0 until references.length()) {
                val item = references.optJSONObject(index) ?: continue
                append("\n## ")
                append(item.optString("title", "Reference ${index + 1}"))
                item.optString("uri").takeIf { it.isNotBlank() && it != "null" }?.let {
                    append("\nURL: ").append(it)
                }
                item.optString("filePath").takeIf { it.isNotBlank() && it != "null" }?.let {
                    append("\nFile: ").append(File(it).name)
                }
                item.optString("text").takeIf { it.isNotBlank() && it != "null" }?.let {
                    append("\n").append(it.take(6000))
                }
                append("\n")
            }
        }
        val taskPrompt = when (taskType) {
            "plant_identification" -> """
                あなたは植物判定アシスタントです。添付画像の内容を前提に、植物名の候補、根拠、説明、育て方の注意点を日本語で返してください。
                画像を直接解析できないランタイムの場合は、その制約を明記し、ユーザーに葉・花・実・樹形の追加情報を求めてください。
                添付情報:$mediaSummary
                参照資料:$referenceSummary

                ユーザー依頼: $prompt
            """.trimIndent()
            "multimodal_chat", "image_caption" -> """
                添付メディアや参照資料を含む相談です。画像や音声の内容を利用できる場合は回答に反映してください。
                参照資料がある場合は、参照資料を優先し、資料にない内容は推測として明記してください。
                直接解析できないランタイムの場合は、利用できる情報と不足情報を分けて説明してください。
                添付情報:$mediaSummary
                参照資料:$referenceSummary

                ユーザー依頼: $prompt
            """.trimIndent()
            else -> prompt
        }
        return listOf(runtimeContext, internalApiContext, taskPrompt)
            .filter { it.isNotBlank() }
            .joinToString("\n\n")
    }

    private fun JSONObject.internalApiPromptContext(prompt: String): String {
        val options = runtimeOptions()
        val parts = mutableListOf<String>()
        if (options.optBoolean("locationEnabled", false)) {
            currentLocationContext()?.let { parts.add(it) }
        }
        if (options.optBoolean("webSearchEnabled", false)) {
            val webContext = internalWebSearchContext(prompt)
            if (webContext.isNotBlank()) {
                parts.add(webContext)
            }
        }
        return parts.joinToString("\n\n")
    }

    private fun currentLocationContext(): String? {
        if (
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED
        ) {
            return "Internal API location context: location permission is not granted to Essential."
        }
        val manager = getSystemService(LocationManager::class.java) ?: return null
        val location = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER,
        ).mapNotNull { provider ->
            runCatching {
                if (manager.isProviderEnabled(provider)) {
                    manager.getLastKnownLocation(provider)
                } else {
                    null
                }
            }.getOrNull()
        }.maxByOrNull { it.time }
        return location?.toLocationPromptContext()
    }

    private fun Location.toLocationPromptContext(): String {
        return "Internal API location context: latitude=${"%.6f".format(Locale.US, latitude)}, " +
            "longitude=${"%.6f".format(Locale.US, longitude)}, " +
            "accuracyMeters=${"%.0f".format(Locale.US, accuracy)}, provider=$provider."
    }

    private fun internalWebSearchContext(prompt: String): String {
        val query = internalApiSearchQuery(prompt)
        if (query.length < 4 || !isNetworkOnlineForService()) {
            return ""
        }
        val rows = internalWebSearch(query, MAX_INTERNAL_WEB_RESULTS)
        Log.i(
            TAG,
            "Internal API web search query=${query.take(120)} rows=${rows.size} urls=${rows.joinToString { it.url.take(80) }}",
        )
        if (rows.isEmpty()) {
            return "Internal API web search was enabled, but no usable web results were returned for: $query"
        }
        val buffer = StringBuilder(
            "Internal API web search results fetched now for: $query\n" +
                "Use these results as the web search evidence for this answer. Cite the URLs when relevant.",
        )
        rows.forEachIndexed { index, row ->
            buffer.append("\n")
            buffer.append("${index + 1}. ${row.title}")
            if (row.snippet.isNotBlank()) {
                buffer.append("\n   Snippet: ${row.snippet}")
            }
            if (row.url.isNotBlank()) {
                buffer.append("\n   URL: ${row.url}")
            }
        }
        return buffer.toString()
    }

    private fun internalApiSearchQuery(prompt: String): String {
        val normalized = prompt
            .replace(Regex("\\s+"), " ")
            .trim()
        val explicitQuestion = Regex("Question:\\s*(.+)$", RegexOption.IGNORE_CASE)
            .find(normalized)
            ?.groupValues
            ?.getOrNull(1)
            ?.trim()
        return (explicitQuestion ?: normalized)
            .removePrefix("Question:")
            .trim()
            .take(180)
    }

    private fun JSONObject.runtimePromptContext(): String {
        val options = runtimeOptions()
        val webEnabled = options.optBoolean("webSearchEnabled", false)
        val locationEnabled = options.optBoolean("locationEnabled", false)
        val memoryLegacy = options.optBoolean("sharedMemoryEnabled", false)
        val memoryRead = options.optBoolean("sharedMemoryReadEnabled", memoryLegacy)
        val memoryWrite = options.optBoolean("sharedMemoryWriteEnabled", memoryLegacy)
        if (!webEnabled && !locationEnabled && !memoryRead && !memoryWrite) {
            return ""
        }
        return buildString {
            appendLine("Runtime options from the calling app:")
            appendLine("- Web search: ${if (webEnabled) "enabled" else "disabled"}")
            appendLine("- Location context: ${if (locationEnabled) "enabled" else "disabled"}")
            appendLine("- Shared memory read: ${if (memoryRead) "enabled" else "disabled"}")
            appendLine("- Shared memory write: ${if (memoryWrite) "enabled" else "disabled"}")
            if (webEnabled) {
                appendLine("The caller allows web grounding. When web results, URLs, product pages, or snippets are supplied in the prompt or references, use them as available current information and do not say that web search is unavailable.")
            }
            if (locationEnabled) {
                appendLine("The caller allows location-aware context. When current-location information is supplied, treat it as the user's current location and answer location/weather questions from that context.")
            }
            appendLine("Shared memory is optional past context only. It is not the current user message, not an opening greeting, and must be ignored unless directly relevant.")
            if (!memoryRead) {
                appendLine("For this request, do not use shared memory as input.")
            }
            if (!memoryWrite) {
                appendLine("For this request, do not write new shared memory.")
            }
        }.trim()
    }

    private fun isNetworkOnlineForService(): Boolean {
        val manager = getSystemService(android.net.ConnectivityManager::class.java) ?: return false
        val network = manager.activeNetwork ?: return false
        val capabilities = manager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    private fun internalWebSearch(query: String, maxResults: Int): List<WebRow> {
        val limit = maxResults.coerceIn(1, 6)
        val rows = mutableListOf<WebRow>()
        val encoded = URLEncoder.encode(query, Charsets.UTF_8.name())
        rows.addAll(internalDirectWebRows(query, limit))
        val targets = listOf(
            "https://www.bing.com/search?q=$encoded&cc=jp&setlang=ja-JP",
            "https://search.yahoo.co.jp/search?p=$encoded&ei=UTF-8&x=wrt",
            "https://duckduckgo.com/html/?q=$encoded",
        )
        for (target in targets) {
            if (rows.size >= limit) {
                break
            }
            runCatching {
                val html = fetchTextViaHttp(target)
                rows.addAll(parseSearchRows(target, html, limit - rows.size))
            }.onFailure { error ->
                Log.w(TAG, "Internal API web search failed url=$target", error)
            }
        }
        return rows
            .filter { it.title.isNotBlank() || it.snippet.isNotBlank() }
            .filter { row -> isRelevantWebRow(query, row) }
            .distinctBy { it.url.ifBlank { it.title } }
            .take(limit)
    }

    private fun internalDirectWebRows(query: String, maxResults: Int): List<WebRow> {
        val lower = query.lowercase(Locale.US)
        if (!lower.contains("pixel") || !lower.contains("update")) {
            return emptyList()
        }
        val urls = listOf(
            "https://source.android.com/docs/security/bulletin/pixel",
            "https://support.google.com/pixelphone/answer/7680439?hl=en",
            "https://support.google.com/pixelphone/answer/4457705?hl=en",
        )
        return urls.mapNotNull { url ->
            runCatching {
                parseDocumentRow(url, fetchTextViaHttp(url))
            }.onFailure { error ->
                Log.w(TAG, "Internal API direct web fetch failed url=$url", error)
            }.getOrNull()
        }.take(maxResults)
    }

    private fun parseDocumentRow(url: String, html: String): WebRow {
        val title = Regex("<title[^>]*>(.*?)</title>", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
            .find(html)
            ?.groupValues
            ?.getOrNull(1)
            ?.let(::cleanHtml)
            .orEmpty()
        val description = Regex(
            "<meta[^>]+(?:name|property)=[\"'](?:description|og:description)[\"'][^>]+content=[\"']([^\"']+)[\"'][^>]*>",
            RegexOption.IGNORE_CASE,
        ).find(html)
            ?.groupValues
            ?.getOrNull(1)
            ?.let(::cleanHtml)
            .orEmpty()
        val fallback = cleanHtml(
            Regex("<p[^>]*>(.*?)</p>", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
                .find(html)
                ?.groupValues
                ?.getOrNull(1)
                .orEmpty(),
        )
        return WebRow(
            title = title.ifBlank { Uri.parse(url).host.orEmpty() },
            url = url,
            snippet = description.ifBlank { fallback }.take(320),
        )
    }

    private fun isRelevantWebRow(query: String, row: WebRow): Boolean {
        val lower = query.lowercase(Locale.US)
        if (!lower.contains("pixel") || !lower.contains("update")) {
            return true
        }
        val haystack = "${row.title} ${row.snippet} ${row.url}".lowercase(Locale.US)
        return haystack.contains("pixel") ||
            haystack.contains("android") ||
            haystack.contains("google") ||
            haystack.contains("update")
    }

    private fun parseSearchRows(sourceUrl: String, html: String, maxResults: Int): List<WebRow> {
        return when {
            sourceUrl.contains("duckduckgo.com") -> parseDuckDuckGoRows(html, maxResults)
            sourceUrl.contains("bing.com") -> parseBingRows(html, maxResults)
            else -> parseYahooRows(html, maxResults)
        }
    }

    private fun parseDuckDuckGoRows(html: String, maxResults: Int): List<WebRow> {
        val regex = Regex(
            "<a[^>]+class=\"result__a\"[^>]+href=\"([^\"]+)\"[^>]*>(.*?)</a>.*?<a[^>]+class=\"result__snippet\"[^>]*>(.*?)</a>",
            setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE),
        )
        return regex.findAll(html).map {
            WebRow(
                title = cleanHtml(it.groupValues[2]),
                url = normalizeSearchUrl(it.groupValues[1]),
                snippet = cleanHtml(it.groupValues[3]),
            )
        }.take(maxResults).toList()
    }

    private fun parseBingRows(html: String, maxResults: Int): List<WebRow> {
        val regex = Regex(
            "<li[^>]+class=\"b_algo\"[\\s\\S]*?<a[^>]+href=\"([^\"]+)\"[^>]*>\\s*<h2[^>]*>(.*?)</h2>\\s*</a>[\\s\\S]*?<p[^>]*>(.*?)</p>",
            setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE),
        )
        return regex.findAll(html).map {
            WebRow(
                title = cleanHtml(it.groupValues[2]),
                url = normalizeSearchUrl(it.groupValues[1]),
                snippet = cleanHtml(it.groupValues[3]),
            )
        }.take(maxResults).toList()
    }

    private fun parseYahooRows(html: String, maxResults: Int): List<WebRow> {
        val block = Regex(
            "<div id=\"web\"[\\s\\S]*?<ol>([\\s\\S]*?)</ol>",
            setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE),
        ).find(html)?.groupValues?.getOrNull(1) ?: html
        val regex = Regex(
            "<li>\\s*<a[^>]+href=\"([^\"]+)\"[^>]*>(.*?)</a>\\s*<div>(.*?)</div>",
            setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE),
        )
        return regex.findAll(block).map {
            WebRow(
                title = cleanHtml(it.groupValues[2]),
                url = normalizeSearchUrl(it.groupValues[1]),
                snippet = cleanHtml(it.groupValues[3]),
            )
        }.filter {
            !it.url.contains("search.yahoo.co.jp", ignoreCase = true)
        }.take(maxResults).toList()
    }

    private fun fetchTextViaHttp(urlText: String): String {
        val connection = (URL(urlText).openConnection() as HttpURLConnection).apply {
            connectTimeout = 5000
            readTimeout = 5000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36")
            setRequestProperty("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            setRequestProperty("Accept-Language", "ja,en;q=0.8")
            setRequestProperty("Accept-Encoding", "identity")
        }
        return try {
            connection.connect()
            val code = connection.responseCode
            if (code !in 200..299) {
                throw IllegalStateException("HTTP $code")
            }
            connection.inputStream.bufferedReader(Charsets.UTF_8).readText()
        } finally {
            connection.disconnect()
        }
    }

    private fun normalizeSearchUrl(raw: String): String {
        val decoded = decodeHtml(raw).trim()
        val absolute = when {
            decoded.startsWith("//") -> "https:$decoded"
            decoded.startsWith("/") -> "https://duckduckgo.com$decoded"
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

    private fun decodeHtml(value: String): String {
        return value
            .replace("&amp;", "&")
            .replace("&quot;", "\"")
            .replace("&#x27;", "'")
            .replace("&#39;", "'")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&nbsp;", " ")
    }

    private fun JSONObject.audioTranscriptFallback(): String {
        val attachments = attachments()
        if (attachments.length() == 0) {
            return ""
        }
        val first = attachments.optJSONObject(0)
        return first?.optJSONObject("metadata")?.optString("transcript").orEmpty()
    }

    private fun JSONObject.taskMetadata(): JSONObject {
        val options = runtimeOptions()
        val memoryLegacy = options.optBoolean("sharedMemoryEnabled", false)
        return JSONObject()
            .put("taskType", taskType())
            .put("attachmentCount", attachments().length().toString())
            .put("webSearchEnabled", options.optBoolean("webSearchEnabled", false))
            .put("locationEnabled", options.optBoolean("locationEnabled", false))
            .put("sharedMemoryReadEnabled", options.optBoolean("sharedMemoryReadEnabled", memoryLegacy))
            .put("sharedMemoryWriteEnabled", options.optBoolean("sharedMemoryWriteEnabled", memoryLegacy))
    }

    private fun speak(text: String): String {
        if (text.isBlank()) {
            return "skipped_empty"
        }
        val engine = tts
        if (engine == null) {
            tts = TextToSpeech(applicationContext) { status ->
                ttsReady = status == TextToSpeech.SUCCESS
                if (ttsReady) {
                    tts?.language = Locale.JAPANESE
                    tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "essential-sdk-tts")
                } else {
                    Log.w(TAG, "tts init failed status=$status")
                }
            }
            return "initializing"
        }
        if (!ttsReady) {
            return "not_ready"
        }
        engine.language = Locale.JAPANESE
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "essential-sdk-tts")
        return "playing"
    }

    private fun completedResponse(
        requestId: String,
        taskType: String,
        output: String,
        modelUsed: String,
        metadata: JSONObject = JSONObject(),
    ): String {
        return JSONObject()
            .put("requestId", requestId)
            .put("taskType", taskType)
            .put("status", "completed")
            .put("output", output)
            .put("modelUsed", modelUsed)
            .put("finishReason", "completed")
            .put("metadata", metadata)
            .toString()
    }

    private fun errorResponse(requestId: String, code: String, message: String): String {
        return JSONObject()
            .put("requestId", requestId)
            .put("status", "failed")
            .put("errorCode", code)
            .put("message", message)
            .toString()
    }

    private fun chunkResponse(requestId: String, delta: String, modelUsed: String): String {
        return JSONObject()
            .put("requestId", requestId)
            .put("delta", delta)
            .put("modelUsed", modelUsed)
            .toString()
    }

    private fun String.withMediaFallbackNote(media: MediaPaths): String {
        val note = buildString {
            appendLine("Attachment handling note:")
            appendLine("- The caller attached ${media.imagePaths.size} image(s) and ${media.audioPaths.size} audio item(s).")
            appendLine("- Direct media decoding was not available for this local model request, so answer from the user's question, the attachment summary, and any reference documents already included in the prompt.")
            appendLine("- If the screenshot content is required but not described in text, ask for the visible screen text or a clearer description instead of failing.")
        }.trim()
        return listOf(this, note)
            .filter { it.isNotBlank() }
            .joinToString("\n\n")
    }

    private data class LocalModel(
        val modelId: String,
        val path: String,
        val sizeBytes: Long,
        val route: String = "litertlm",
        val runtimeFamily: String = "google-ai-edge-litertlm",
        val supportsImage: Boolean = false,
        val supportsAudio: Boolean = false,
    )

    private data class MediaPaths(
        val imagePaths: List<String>,
        val audioPaths: List<String>,
    )

    private data class WebRow(
        val title: String,
        val url: String,
        val snippet: String,
    )
}
