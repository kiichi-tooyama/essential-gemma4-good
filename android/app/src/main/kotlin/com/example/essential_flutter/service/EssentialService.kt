package com.example.essential_flutter.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
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
                val output = liteRtLmRuntime.generateBlocking(
                    GalleryLiteRtLmRequest(
                        requestId = requestId,
                        modelPath = modelPath,
                        prompt = prompt,
                        systemInstruction = request.optString("systemInstruction"),
                        imagePaths = media.imagePaths,
                        audioPaths = media.audioPaths,
                        maxTokens = params.optInt("maxTokens", 1024),
                        topK = params.optInt("topK", 64),
                        topP = params.optDouble("topP", 0.95),
                        temperature = params.optDouble("temperature", 1.0),
                        accelerator = params.optString("accelerator", "auto"),
                        visionAccelerator = params.optString("visionAccelerator", "gpu"),
                        enableThinking = params.optBoolean("enableThinking", false),
                    ),
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
                    val output = liteRtLmRuntime.generateBlocking(
                        GalleryLiteRtLmRequest(
                            requestId = requestId,
                            modelPath = modelPath,
                            prompt = prompt,
                            systemInstruction = request.optString("systemInstruction"),
                            imagePaths = media.imagePaths,
                            audioPaths = media.audioPaths,
                            maxTokens = params.optInt("maxTokens", 1024),
                            topK = params.optInt("topK", 64),
                            topP = params.optDouble("topP", 0.95),
                            temperature = params.optDouble("temperature", 1.0),
                            accelerator = params.optString("accelerator", "auto"),
                            visionAccelerator = params.optString("visionAccelerator", "gpu"),
                            enableThinking = params.optBoolean("enableThinking", false),
                        ),
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
        if (attachments.length() == 0 && references.length() == 0) {
            return listOf(runtimeContext, prompt)
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
        return listOf(runtimeContext, taskPrompt)
            .filter { it.isNotBlank() }
            .joinToString("\n\n")
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
}
