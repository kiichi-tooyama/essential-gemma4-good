package com.example.essential_flutter.ai

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.ExperimentalApi
import com.google.ai.edge.litertlm.ExperimentalFlags
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.SamplerConfig
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

private const val TAG = "EssentialGalleryRT"
private const val DEFAULT_ENGINE_CONTEXT_TOKENS = 4000
private const val HEAVY_TEXT_ENGINE_CONTEXT_TOKENS = 2048
private const val MAX_ENGINE_CONTEXT_TOKENS = 4096

data class GalleryLiteRtLmRequest(
    val requestId: String,
    val modelPath: String,
    val prompt: String,
    val systemInstruction: String = "",
    val imagePaths: List<String> = emptyList(),
    val audioPaths: List<String> = emptyList(),
    val maxTokens: Int = 1024,
    val contextTokens: Int = DEFAULT_ENGINE_CONTEXT_TOKENS,
    val topK: Int = 64,
    val topP: Double = 0.95,
    val temperature: Double = 1.0,
    val accelerator: String = "gpu",
    val visionAccelerator: String = "gpu",
    val enableThinking: Boolean = false,
)

data class GalleryLiteRtLmResult(
    val text: String,
    val modelPath: String,
    val latencyMs: Long,
    val loadAndSetupMs: Long,
    val generationMs: Long,
    val firstTokenMs: Long?,
    val accelerator: String,
    val visionAccelerator: String?,
    val supportsImage: Boolean,
    val supportsAudio: Boolean,
)

data class GalleryLiteRtLmWarmupResult(
    val modelPath: String,
    val loadAndSetupMs: Long,
    val accelerator: String,
    val visionAccelerator: String?,
    val contextTokens: Int,
)

@OptIn(ExperimentalApi::class)
class GalleryLiteRtLmRuntime(private val context: Context) {
    private val activeConversations = ConcurrentHashMap<String, Conversation>()
    private val engineCache = ConcurrentHashMap<EngineKey, Engine>()
    private val engineLock = Any()
    private val generationLock = Any()

    fun generateBlocking(
        request: GalleryLiteRtLmRequest,
        onToken: ((String) -> Unit)? = null,
    ): GalleryLiteRtLmResult {
        val startedAt = System.currentTimeMillis()
        val modelFile = File(request.modelPath)
        require(modelFile.exists() && modelFile.isFile) {
            "LiteRT-LM model not found: ${request.modelPath}"
        }
        require(
            request.prompt.isNotBlank() ||
                request.imagePaths.isNotEmpty() ||
                request.audioPaths.isNotEmpty(),
        ) {
            "Prompt, image, or audio input is required."
        }

        val backend = backendFor(request.accelerator, preferCpuForAuto = false)
        val visionBackend = if (request.imagePaths.isNotEmpty()) {
            backendFor(request.visionAccelerator, preferCpuForAuto = false)
        } else {
            null
        }
        val audioBackend = if (request.audioPaths.isNotEmpty()) Backend.CPU() else null
        val engineMaxTokens = engineContextTokensFor(request)
        val engineKey = EngineKey(
            modelPath = modelFile.absolutePath,
            backend = backendLabel(backend),
            visionBackend = visionBackend?.let { backendLabel(it) },
            audioBackend = audioBackend?.let { backendLabel(it) },
            contextTokens = engineMaxTokens,
        )

        synchronized(generationLock) {
            var conversation: Conversation? = null
            try {
            val engineStartedAt = System.currentTimeMillis()
            val engine = engineFor(
                key = engineKey,
                config = EngineConfig(
                    modelPath = modelFile.absolutePath,
                    backend = backend,
                    visionBackend = visionBackend,
                    audioBackend = audioBackend,
                    maxNumTokens = engineMaxTokens,
                    cacheDir = cacheDirFor(modelFile.absolutePath),
                ),
            )
            val engineReadyAt = System.currentTimeMillis()
            ExperimentalFlags.enableConversationConstrainedDecoding = false
            conversation = engine.createConversation(
                ConversationConfig(
                    samplerConfig = samplerConfigFor(backend, request),
                    systemInstruction = request.systemInstruction
                        .takeIf { it.isNotBlank() }
                        ?.let { Contents.of(it) },
                ),
            )
            val activeConversation = conversation
                ?: throw IllegalStateException("LiteRT-LM conversation was not created.")
            activeConversations[request.requestId] = activeConversation

            val contents = mutableListOf<Content>()
            request.imagePaths.take(10).forEach { path ->
                val bitmap = BitmapFactory.decodeFile(path)
                    ?: throw IllegalArgumentException("Unable to decode image: $path")
                contents.add(Content.ImageBytes(bitmap.toPngByteArray()))
            }
            request.audioPaths.forEach { path ->
                contents.add(Content.AudioBytes(File(path).readBytes()))
            }
            if (request.prompt.isNotBlank()) {
                contents.add(Content.Text(request.prompt))
            }

            val inferenceStartedAt = System.currentTimeMillis()
            val latch = CountDownLatch(1)
            val output = StringBuilder()
            var callbackError: Throwable? = null
            var firstTokenMs: Long? = null
            var emittedTokens = 0
            var stoppedAtBudget = false
            val extraContext =
                if (request.enableThinking) mapOf("enable_thinking" to "true") else emptyMap()
            activeConversation.sendMessageAsync(
                Contents.of(contents),
                object : MessageCallback {
                    override fun onMessage(message: Message) {
                        if (firstTokenMs == null) {
                            firstTokenMs = System.currentTimeMillis() - inferenceStartedAt
                        }
                        val token = message.toString()
                        output.append(token)
                        onToken?.invoke(token)
                        emittedTokens += 1
                        if (emittedTokens >= request.maxTokens) {
                            stoppedAtBudget = true
                            activeConversation.cancelProcess()
                            latch.countDown()
                        }
                    }

                    override fun onDone() {
                        latch.countDown()
                    }

                    override fun onError(throwable: Throwable) {
                        callbackError = throwable
                        latch.countDown()
                    }
                },
                extraContext,
            )
            if (!latch.await(10, TimeUnit.MINUTES)) {
                activeConversation.cancelProcess()
                throw IllegalStateException("LiteRT-LM generation timed out.")
            }
            if (!stoppedAtBudget) {
                callbackError?.let { throw it }
            }
            val finishedAt = System.currentTimeMillis()
            Log.i(
                TAG,
                "litertlm_ok request=${request.requestId} model=${modelFile.name} context_tokens=$engineMaxTokens load_and_setup_ms=${inferenceStartedAt - startedAt} first_token_ms=$firstTokenMs generation_ms=${finishedAt - inferenceStartedAt} chars=${output.length}",
            )
            return GalleryLiteRtLmResult(
                text = output.toString(),
                modelPath = modelFile.absolutePath,
                latencyMs = finishedAt - startedAt,
                loadAndSetupMs = engineReadyAt - engineStartedAt,
                generationMs = finishedAt - inferenceStartedAt,
                firstTokenMs = firstTokenMs,
                accelerator = backendLabel(backend),
                visionAccelerator = visionBackend?.let { backendLabel(it) },
                supportsImage = request.imagePaths.isNotEmpty(),
                supportsAudio = request.audioPaths.isNotEmpty(),
            )
            } finally {
                activeConversations.remove(request.requestId)
                try {
                    conversation?.close()
                } catch (error: Throwable) {
                    Log.w(TAG, "conversation_close_error", error)
                }
            }
        }
    }

    fun warmUp(request: GalleryLiteRtLmRequest): GalleryLiteRtLmWarmupResult {
        val modelFile = File(request.modelPath)
        require(modelFile.exists() && modelFile.isFile) {
            "LiteRT-LM model not found: ${request.modelPath}"
        }
        val backend = backendFor(request.accelerator, preferCpuForAuto = false)
        val visionBackend = if (request.imagePaths.isNotEmpty()) {
            backendFor(request.visionAccelerator, preferCpuForAuto = false)
        } else {
            null
        }
        val engineMaxTokens = engineContextTokensFor(request)
        val key = EngineKey(
            modelPath = modelFile.absolutePath,
            backend = backendLabel(backend),
            visionBackend = visionBackend?.let { backendLabel(it) },
            audioBackend = null,
            contextTokens = engineMaxTokens,
        )
        val startedAt = System.currentTimeMillis()
        engineFor(
            key = key,
            config = EngineConfig(
                modelPath = modelFile.absolutePath,
                backend = backend,
                visionBackend = visionBackend,
                audioBackend = null,
                maxNumTokens = engineMaxTokens,
                cacheDir = cacheDirFor(modelFile.absolutePath),
            ),
        )
        val elapsed = System.currentTimeMillis() - startedAt
        Log.i(
            TAG,
            "litertlm_warmup_ok model=${modelFile.name} context_tokens=$engineMaxTokens load_and_setup_ms=$elapsed accelerator=${backendLabel(backend)}",
        )
        return GalleryLiteRtLmWarmupResult(
            modelPath = modelFile.absolutePath,
            loadAndSetupMs = elapsed,
            accelerator = backendLabel(backend),
            visionAccelerator = visionBackend?.let { backendLabel(it) },
            contextTokens = engineMaxTokens,
        )
    }

    fun cancel(requestId: String): Boolean {
        return activeConversations[requestId]?.let {
            it.cancelProcess()
            true
        } ?: false
    }

    fun close() {
        activeConversations.values.forEach { conversation ->
            runCatching { conversation.cancelProcess() }
            runCatching { conversation.close() }
        }
        activeConversations.clear()
        engineCache.values.forEach { engine ->
            runCatching { engine.close() }
                .onFailure { Log.w(TAG, "engine_close_error", it) }
        }
        engineCache.clear()
    }

    fun releaseIdle(keepModelPath: String? = null) {
        synchronized(engineLock) {
            val keep = keepModelPath?.let { File(it).absolutePath }
            engineCache.entries.removeIf { (cachedKey, cachedEngine) ->
                val shouldClose = keep == null || cachedKey.modelPath != keep
                if (shouldClose) {
                    runCatching { cachedEngine.close() }
                        .onFailure { Log.w(TAG, "engine_close_error", it) }
                }
                shouldClose
            }
        }
    }

    fun cachedEngineCount(): Int = engineCache.size

    private fun engineFor(key: EngineKey, config: EngineConfig): Engine {
        engineCache[key]?.let { return it }
        synchronized(engineLock) {
            engineCache[key]?.let { return it }
            engineCache.entries.removeIf { (cachedKey, cachedEngine) ->
                if (cachedKey == key) {
                    false
                } else {
                    runCatching { cachedEngine.close() }
                        .onFailure { Log.w(TAG, "engine_close_error", it) }
                    true
                }
            }
            val engine = Engine(config)
            engine.initialize()
            engineCache[key] = engine
            return engine
        }
    }

    private fun samplerConfigFor(backend: Backend, request: GalleryLiteRtLmRequest): SamplerConfig? {
        return if (backend is Backend.NPU) {
            null
        } else {
            SamplerConfig(
                topK = request.topK.coerceIn(1, 64),
                topP = request.topP.coerceIn(0.0, 1.0),
                temperature = request.temperature.coerceIn(0.0, 2.0),
            )
        }
    }

    private fun engineContextTokensFor(request: GalleryLiteRtLmRequest): Int {
        val minimum = when {
            request.audioPaths.isNotEmpty() -> 512
            request.imagePaths.isNotEmpty() -> 512
            else -> 256
        }
        val requested = maxOf(request.contextTokens, request.maxTokens, minimum)
        val upperLimit = if (
            request.imagePaths.isEmpty() &&
                request.audioPaths.isEmpty() &&
                isMemoryHeavyTextModel(request.modelPath)
        ) {
            HEAVY_TEXT_ENGINE_CONTEXT_TOKENS
        } else {
            MAX_ENGINE_CONTEXT_TOKENS
        }
        return requested.coerceIn(minimum, upperLimit)
    }

    private fun isMemoryHeavyTextModel(modelPath: String): Boolean {
        val value = modelPath.lowercase(Locale.US)
        return value.contains("e4b") && value.endsWith(".litertlm")
    }

    private fun backendFor(label: String, preferCpuForAuto: Boolean): Backend {
        return when (label.lowercase(Locale.US)) {
            "cpu" -> Backend.CPU()
            "gpu" -> Backend.GPU()
            "npu", "tpu" -> Backend.NPU(nativeLibraryDir = context.applicationInfo.nativeLibraryDir)
            else -> if (preferCpuForAuto) Backend.CPU() else Backend.GPU()
        }
    }

    private fun cacheDirFor(modelPath: String): String? {
        return if (modelPath.startsWith("/data/local/tmp")) {
            context.getExternalFilesDir(null)?.absolutePath
        } else {
            null
        }
    }

    private fun backendLabel(backend: Backend): String {
        return when (backend) {
            is Backend.CPU -> "cpu"
            is Backend.GPU -> "gpu"
            is Backend.NPU -> "npu"
            else -> backend.javaClass.simpleName.lowercase(Locale.US)
        }
    }

    private fun Bitmap.toPngByteArray(): ByteArray {
        val stream = ByteArrayOutputStream()
        compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }

    private data class EngineKey(
        val modelPath: String,
        val backend: String,
        val visionBackend: String?,
        val audioBackend: String?,
        val contextTokens: Int,
    )
}
