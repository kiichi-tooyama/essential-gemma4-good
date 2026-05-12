package io.essential.sdk.android

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.Uri
import android.os.IBinder
import android.os.RemoteException
import com.example.essential_flutter.service.IEssentialService
import com.example.essential_flutter.service.IEssentialStreamCallback
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine

class EssentialClient private constructor(
    context: Context,
    private val configuration: EssentialServiceConfiguration,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : Closeable {
    val models = EssentialModelsNamespace(this)
    val adapters = EssentialAdaptersNamespace(this)

    private val appContext = context.applicationContext
    private val serviceMutex = Mutex()
    private val blockingCallScope = CoroutineScope(SupervisorJob() + ioDispatcher)
    private var service: IEssentialService? = null
    private var serviceConnection: ServiceConnection? = null

    companion object {
        suspend fun connect(
            context: Context,
            configuration: EssentialServiceConfiguration,
        ): EssentialClient {
            val client = EssentialClient(context = context, configuration = configuration)
            client.requireService()
            return client
        }
    }

    suspend fun generate(request: EssentialGenerateRequest): EssentialGenerateResult {
        val requestId = request.id ?: nextRequestId()
        val resolvedRequest = prepareRequest(request.withRequestId(requestId))
        return try {
            grantAttachmentUriPermissions(resolvedRequest.attachments)
            val responseJson = runWithTimeout(requestId, resolvedRequest.timeoutMs) {
                callService {
                    it.runInference(
                        resolvedRequest.toRequestJson(
                            callerPackage = configuration.callerPackage,
                            stream = false,
                        ),
                    )
                }
            }
            parseGenerateResult(JSONObject(responseJson))
        } catch (exception: EssentialException) {
            throw exception
        } catch (throwable: Throwable) {
            throw mapThrowable(throwable)
        }
    }

    suspend fun runTask(request: EssentialTaskRequest): EssentialTaskResult {
        val requestId = request.id ?: nextRequestId()
        val resolvedRequest = prepareTaskRequest(request.withRequestId(requestId))
        return try {
            grantAttachmentUriPermissions(resolvedRequest.attachments)
            val responseJson = runWithTimeout(requestId, resolvedRequest.timeoutMs) {
                callService {
                    it.runInference(
                        resolvedRequest.toTaskRequestJson(
                            callerPackage = configuration.callerPackage,
                            stream = false,
                        ),
                    )
                }
            }
            parseTaskResult(JSONObject(responseJson), resolvedRequest.taskType)
        } catch (exception: EssentialException) {
            throw exception
        } catch (throwable: Throwable) {
            throw mapThrowable(throwable)
        }
    }

    fun streamTask(request: EssentialTaskRequest): Flow<EssentialTaskChunk> = callbackFlow {
        val requestId = request.id ?: nextRequestId()
        val timedOut = AtomicBoolean(false)
        val resolvedRequest = try {
            prepareTaskRequest(request.withRequestId(requestId))
        } catch (throwable: Throwable) {
            close(mapThrowable(throwable))
            return@callbackFlow
        }
        grantAttachmentUriPermissions(resolvedRequest.attachments)
        val accumulator = StringBuffer()
        val callback = object : IEssentialStreamCallback.Stub() {
            override fun onChunk(requestId: String, chunkJson: String) {
                val chunk = JSONObject(chunkJson)
                val delta = chunk.optString("delta")
                accumulator.append(delta)
                trySend(
                    EssentialTaskChunk(
                        requestId = requestId,
                        taskType = resolvedRequest.taskType,
                        delta = delta,
                        accumulatedText = accumulator.toString(),
                        modelUsed = chunk.optString("modelUsed"),
                    ),
                )
            }

            override fun onComplete(requestId: String, responseJson: String) {
                close()
            }

            override fun onError(requestId: String, errorCode: String, message: String) {
                close(
                    EssentialException(
                        code = if (timedOut.get()) {
                            EssentialErrorCode.REQUEST_TIMED_OUT
                        } else {
                            errorCode.toEssentialErrorCode()
                        },
                        message = message.ifBlank { "Task request failed." },
                    ),
                )
            }
        }

        val timeoutMs = resolvedRequest.timeoutMs
        val timeoutThread = if (timeoutMs != null && timeoutMs > 0) {
            thread(start = true, isDaemon = true) {
                try {
                    Thread.sleep(timeoutMs)
                    timedOut.set(true)
                    cancelBestEffort(requestId)
                } catch (_: InterruptedException) {
                }
            }
        } else {
            null
        }

        try {
            callService {
                it.streamInference(
                    resolvedRequest.toTaskRequestJson(
                        callerPackage = configuration.callerPackage,
                        stream = true,
                    ),
                    callback,
                )
            }
        } catch (throwable: Throwable) {
            timeoutThread?.interrupt()
            close(mapThrowable(throwable))
            return@callbackFlow
        }

        awaitClose {
            timeoutThread?.interrupt()
            cancelBestEffort(requestId)
        }
    }

    fun generateStream(request: EssentialGenerateRequest): Flow<EssentialGenerateChunk> = callbackFlow {
        val requestId = request.id ?: nextRequestId()
        val timedOut = AtomicBoolean(false)
        val resolvedRequest = try {
            prepareRequest(request.withRequestId(requestId))
        } catch (throwable: Throwable) {
            close(mapThrowable(throwable))
            return@callbackFlow
        }
        grantAttachmentUriPermissions(resolvedRequest.attachments)
        val accumulator = StringBuffer()
        val callback = object : IEssentialStreamCallback.Stub() {
            override fun onChunk(requestId: String, chunkJson: String) {
                val chunk = JSONObject(chunkJson)
                val delta = chunk.optString("delta")
                accumulator.append(delta)
                trySend(
                    EssentialGenerateChunk(
                        requestId = requestId,
                        delta = delta,
                        accumulatedText = accumulator.toString(),
                        modelUsed = chunk.optString("modelUsed"),
                    ),
                )
            }

            override fun onComplete(requestId: String, responseJson: String) {
                close()
            }

            override fun onError(requestId: String, errorCode: String, message: String) {
                val exception = if (timedOut.get()) {
                    EssentialException(
                        code = EssentialErrorCode.REQUEST_TIMED_OUT,
                        message = message.ifBlank { "Inference request timed out." },
                    )
                } else {
                    EssentialException(
                        code = errorCode.toEssentialErrorCode(),
                        message = message,
                    )
                }
                close(exception)
            }
        }

        val timeoutMs = resolvedRequest.timeoutMs
        val timeoutThread = if (timeoutMs != null && timeoutMs > 0) {
            thread(start = true, isDaemon = true) {
                try {
                    Thread.sleep(timeoutMs)
                    timedOut.set(true)
                    cancelBestEffort(requestId)
                } catch (_: InterruptedException) {
                }
            }
        } else {
            null
        }

        try {
            callService {
                it.streamInference(
                    resolvedRequest.toRequestJson(
                        callerPackage = configuration.callerPackage,
                        stream = true,
                    ),
                    callback,
                )
            }
        } catch (throwable: Throwable) {
            timeoutThread?.interrupt()
            close(mapThrowable(throwable))
            return@callbackFlow
        }

        awaitClose {
            timeoutThread?.interrupt()
            cancelBestEffort(requestId)
        }
    }

    suspend fun cancel(requestId: String): Boolean {
        return try {
            callService { it.cancel(requestId) }
        } catch (throwable: Throwable) {
            throw mapThrowable(throwable)
        }
    }

    override fun close() {
        serviceConnection?.let { connection ->
            runCatching { appContext.unbindService(connection) }
        }
        serviceConnection = null
        service = null
        blockingCallScope.cancel()
    }

    private fun cancelBestEffort(requestId: String) {
        runCatching { service?.cancel(requestId) }
    }

    internal suspend fun listModels(): List<EssentialModelDescriptor> {
        return try {
            val payload = callService { it.listModels() }
            parseModels(JSONObject(payload).optJSONArray("models") ?: JSONArray())
        } catch (throwable: Throwable) {
            throw mapThrowable(throwable)
        }
    }

    internal suspend fun ensureModelInstalled(requirement: EssentialModelRequirement): EssentialModelDescriptor {
        val resolved = resolveModel(requirement)
        return when {
            resolved.modelPath != null -> {
                if (!resolved.modelPath.endsWith(".litertlm", ignoreCase = true)) {
                    throw EssentialException(
                        code = EssentialErrorCode.MODEL_INCOMPATIBLE,
                        message = "Essential Android SDK only supports LiteRT-LM .litertlm models.",
                    )
                }
                EssentialModelDescriptor(
                    modelId = resolved.modelId ?: File(resolved.modelPath).nameWithoutExtension,
                    family = requirement.family,
                    path = resolved.modelPath,
                    sizeBytes = File(resolved.modelPath).takeIf { it.exists() }?.length() ?: 0,
                    route = "litertlm",
                    runtimeFamily = "google-ai-edge-litertlm",
                    supportsImage = resolved.modelPath.supportsLiteRtMultimodal(),
                    supportsAudio = resolved.modelPath.supportsLiteRtMultimodal(),
                )
            }

            resolved.modelId != null -> {
                listModels().first { it.modelId == resolved.modelId }
            }

            else -> throw EssentialException(
                code = EssentialErrorCode.MODEL_NOT_INSTALLED,
                message = "No installed model matched the request.",
            )
        }
    }

    internal suspend fun listAdapters(modelId: String): List<EssentialAdapterDescriptor> {
        return try {
            val payload = callService {
                it.listAdapters(configuration.callerPackage.orEmpty(), modelId)
            }
            parseAdapters(JSONObject(payload).optJSONArray("adapters") ?: JSONArray())
        } catch (throwable: Throwable) {
            throw mapThrowable(throwable)
        }
    }

    internal suspend fun attachAdapter(sessionId: String, adapterId: String): Boolean {
        return try {
            callService {
                it.attachAdapter(sessionId, adapterId, configuration.callerPackage.orEmpty())
            }
        } catch (throwable: Throwable) {
            throw mapThrowable(throwable)
        }
    }

    internal suspend fun detachAdapter(sessionId: String): Boolean {
        return try {
            callService {
                it.detachAdapter(sessionId, configuration.callerPackage.orEmpty())
            }
        } catch (throwable: Throwable) {
            throw mapThrowable(throwable)
        }
    }

    private suspend fun prepareRequest(request: EssentialGenerateRequest): EssentialGenerateRequest {
        val requirement = request.modelRequirement.withRuntimePreferredModel(request.runtimeOptions)
        val resolvedModel = resolveModel(requirement)
        return request.copy(
            modelRequirement = requirement.copy(
                modelId = resolvedModel.modelId ?: requirement.modelId,
                explicitModelPath = resolvedModel.modelPath ?: requirement.explicitModelPath,
            ),
        )
    }

    private suspend fun prepareTaskRequest(request: EssentialTaskRequest): EssentialTaskRequest {
        if (request.taskType == EssentialTaskType.STT || request.taskType == EssentialTaskType.TTS) {
            return request
        }
        val requirement = request.modelRequirement.withRuntimePreferredModel(request.runtimeOptions)
        val resolvedModel = resolveModel(requirement)
        return request.copy(
            modelRequirement = requirement.copy(
                modelId = resolvedModel.modelId ?: requirement.modelId,
                explicitModelPath = resolvedModel.modelPath ?: requirement.explicitModelPath,
            ),
        )
    }

    private suspend fun resolveModel(requirement: EssentialModelRequirement): ResolvedModel {
        requirement.explicitModelPath?.let { explicitPath ->
            val file = File(explicitPath)
            if (!file.exists()) {
                throw EssentialException(
                    code = EssentialErrorCode.MODEL_NOT_INSTALLED,
                    message = "Model path not found: $explicitPath",
                )
            }
            return ResolvedModel(
                modelId = requirement.modelId ?: file.nameWithoutExtension,
                modelPath = explicitPath,
            )
        }

        val installedModels = listModels().filter { it.isInstalled }
        if (installedModels.isEmpty()) {
            throw EssentialException(
                code = EssentialErrorCode.MODEL_NOT_INSTALLED,
                message = "No installed model matched the request.",
            )
        }

        requirement.modelId?.let { requestedId ->
            val exact = installedModels.firstOrNull { it.modelId == requestedId }
            if (exact != null) {
                return ResolvedModel(modelId = exact.modelId, modelPath = exact.path)
            }
            if (!requirement.allowFallback) {
                throw EssentialException(
                    code = EssentialErrorCode.MODEL_NOT_INSTALLED,
                    message = "Requested model is unavailable: $requestedId",
                )
            }
        }

        configuration.defaultModelId?.let { defaultId ->
            installedModels.firstOrNull { it.modelId == defaultId }?.let { preferred ->
                return ResolvedModel(modelId = preferred.modelId, modelPath = preferred.path)
            }
        }

        val fallback = installedModels.firstOrNull()
            ?: throw EssentialException(
                code = EssentialErrorCode.MODEL_NOT_INSTALLED,
                message = "No installed model matched the request.",
            )
        return ResolvedModel(modelId = fallback.modelId, modelPath = fallback.path)
    }

    private suspend fun <T> callService(block: suspend (IEssentialService) -> T): T {
        return withContext(ioDispatcher) {
            val boundService = requireService()
            block(boundService)
        }
    }

    private suspend fun requireService(): IEssentialService {
        service?.let { return it }
        return serviceMutex.withLock {
            service?.let { return@withLock it }
            bindService()
        }
    }

    private suspend fun bindService(): IEssentialService {
        return suspendCancellableCoroutine { continuation ->
            val intent = Intent().setComponent(
                ComponentName(configuration.servicePackage, configuration.serviceClassName),
            )
            val connection = object : ServiceConnection {
                override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                    val boundService = IEssentialService.Stub.asInterface(binder)
                    if (boundService == null) {
                        if (continuation.isActive) {
                            continuation.resumeWithException(
                                EssentialException(
                                    code = EssentialErrorCode.RUNTIME_UNAVAILABLE,
                                    message = "Failed to obtain Essential service binder.",
                                ),
                            )
                        }
                        return
                    }
                    serviceConnection = this
                    service = boundService
                    if (continuation.isActive) {
                        continuation.resume(boundService)
                    }
                }

                override fun onServiceDisconnected(name: ComponentName?) {
                    if (serviceConnection === this) {
                        service = null
                    }
                }
            }
            val bound = appContext.bindService(intent, connection, Context.BIND_AUTO_CREATE)
            if (!bound) {
                continuation.resumeWithException(
                    EssentialException(
                        code = EssentialErrorCode.INVALID_CONFIGURATION,
                        message = "Failed to bind Essential service ${configuration.serviceClassName}.",
                    ),
                )
                return@suspendCancellableCoroutine
            }
            continuation.invokeOnCancellation {
                runCatching { appContext.unbindService(connection) }
            }
        }
    }

    private suspend fun <T> runWithTimeout(
        requestId: String,
        timeoutMs: Long?,
        block: suspend () -> T,
    ): T {
        if (timeoutMs == null || timeoutMs <= 0) {
            return block()
        }
        val task = blockingCallScope.async {
            block()
        }
        return try {
            withTimeout(timeoutMs) {
                task.await()
            }
        } catch (throwable: Throwable) {
            if (throwable is kotlinx.coroutines.TimeoutCancellationException) {
                task.cancel()
                cancelBestEffort(requestId)
                throw EssentialException(
                    code = EssentialErrorCode.REQUEST_TIMED_OUT,
                    message = "Inference request timed out after ${timeoutMs}ms.",
                    cause = throwable,
                )
            }
            throw throwable
        }
    }

    private fun parseModels(array: JSONArray): List<EssentialModelDescriptor> {
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)
                add(
                    EssentialModelDescriptor(
                        modelId = item.optString("modelId"),
                        family = item.optString("family").takeIf { it.isNotBlank() },
                        path = item.optString("path").takeIf { it.isNotBlank() && it != "null" },
                        sizeBytes = item.optLong("sizeBytes"),
                        route = item.optString("route"),
                        runtimeFamily = item.optString("runtimeFamily").ifBlank { item.optString("route") },
                        supportsImage = item.optBoolean("supportsImage", false),
                        supportsAudio = item.optBoolean("supportsAudio", false),
                    ),
                )
            }
        }
    }

    private fun String.supportsLiteRtMultimodal(): Boolean {
        val normalized = File(this).name.lowercase()
        return endsWith(".litertlm", ignoreCase = true) &&
            (normalized.contains("gemma-4") || normalized.contains("gemma-3n"))
    }

    private fun parseAdapters(array: JSONArray): List<EssentialAdapterDescriptor> {
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)
                add(
                    EssentialAdapterDescriptor(
                        adapterId = item.optString("adapterId"),
                        baseModelId = item.optString("baseModelId"),
                    ),
                )
            }
        }
    }

    private fun parseGenerateResult(json: JSONObject): EssentialGenerateResult {
        throwIfFailed(json)
        return EssentialGenerateResult(
            requestId = json.optString("requestId"),
            text = json.optString("output"),
            modelUsed = json.optString("modelUsed"),
            finishReason = json.optString("finishReason").ifBlank { "completed" },
        )
    }

    private fun parseTaskResult(json: JSONObject, fallbackType: EssentialTaskType): EssentialTaskResult {
        throwIfFailed(json)
        val metadataJson = json.optJSONObject("metadata") ?: JSONObject()
        val metadata = buildMap {
            metadataJson.keys().forEach { key -> put(key, metadataJson.optString(key)) }
        }
        return EssentialTaskResult(
            requestId = json.optString("requestId"),
            taskType = json.optString("taskType").toEssentialTaskType() ?: fallbackType,
            status = json.optString("status").ifBlank { "completed" },
            text = json.optString("output"),
            modelUsed = json.optString("modelUsed"),
            finishReason = json.optString("finishReason").ifBlank { "completed" },
            metadata = metadata,
        )
    }

    private fun mapThrowable(throwable: Throwable): EssentialException {
        if (throwable is EssentialException) {
            return throwable
        }
        if (throwable is SecurityException) {
            return EssentialException(
                code = EssentialErrorCode.PERMISSION_DENIED,
                message = throwable.message ?: "Permission denied.",
                cause = throwable,
            )
        }
        if (throwable is RemoteException) {
            return EssentialException(
                code = EssentialErrorCode.RUNTIME_UNAVAILABLE,
                message = throwable.message ?: "Essential service is unavailable.",
                cause = throwable,
            )
        }
        return EssentialException(
            code = EssentialErrorCode.RUNTIME_UNAVAILABLE,
            message = throwable.message ?: "Unexpected Essential SDK failure.",
            cause = throwable,
        )
    }

    private fun grantAttachmentUriPermissions(attachments: List<EssentialMediaAttachment>) {
        attachments.forEach { attachment ->
            val uri = attachment.uri?.takeIf { it.isNotBlank() && it != "null" } ?: return@forEach
            runCatching {
                appContext.grantUriPermission(
                    configuration.servicePackage,
                    Uri.parse(uri),
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
        }
    }

    private fun throwIfFailed(json: JSONObject) {
        val status = json.optString("status")
        if (status == "failed" || json.has("errorCode")) {
            throw EssentialException(
                code = json.optString("errorCode").toEssentialErrorCode(),
                message = json.optString("message").ifBlank { "Essential request failed." },
            )
        }
    }
}

class EssentialModelsNamespace internal constructor(
    private val client: EssentialClient,
) {
    suspend fun list(): List<EssentialModelDescriptor> = client.listModels()

    suspend fun ensureInstalled(requirement: EssentialModelRequirement): EssentialModelDescriptor {
        return client.ensureModelInstalled(requirement)
    }
}

class EssentialAdaptersNamespace internal constructor(
    private val client: EssentialClient,
) {
    suspend fun list(modelId: String): List<EssentialAdapterDescriptor> = client.listAdapters(modelId)

    suspend fun attach(sessionId: String, adapterId: String): Boolean {
        return client.attachAdapter(sessionId, adapterId)
    }

    suspend fun detach(sessionId: String): Boolean = client.detachAdapter(sessionId)
}

private fun EssentialGenerateRequest.toRequestJson(
    callerPackage: String?,
    stream: Boolean,
): String {
    val attachmentsJson = attachments.toAttachmentJsonArray()
    val referencesJson = referenceDocuments.toReferenceJsonArray()
    val root = JSONObject()
        .put("requestId", id)
        .put("prompt", prompt)
        .put("stream", stream)
        .put("timeoutMs", timeoutMs ?: 0L)
        .put(
            "input",
            JSONObject()
                .put("prompt", prompt)
                .put("attachments", attachmentsJson)
                .put("referenceDocuments", referencesJson),
        )
        .put("systemInstruction", systemInstruction)
        .put(
            "generationParams",
            JSONObject()
                .put("maxTokens", maxTokens)
                .put("topK", topK)
                .put("topP", topP)
                .put("temperature", temperature)
                .put("seed", seed),
        )
        .put(
            "modelRequirement",
            JSONObject()
                .put("modelId", modelRequirement.modelId)
                .put("family", modelRequirement.family)
                .put("capability", modelRequirement.capability)
                .put("minContextWindow", modelRequirement.minContextWindow ?: 2048)
                .put("maxLatencyMs", modelRequirement.maxLatencyMs ?: JSONObject.NULL)
                .put("allowFallback", modelRequirement.allowFallback)
                .put("modelPath", modelRequirement.explicitModelPath),
        )
        .put("runtimeOptions", runtimeOptions.toRuntimeOptionsJson())
    sessionId?.let { root.put("sessionId", it) }
    adapterId?.let { root.put("adapterId", it) }
    callerPackage?.takeIf { it.isNotBlank() }?.let { root.put("callerPackage", it) }
    return root.toString()
}

private fun EssentialTaskRequest.toTaskRequestJson(
    callerPackage: String?,
    stream: Boolean,
): String {
    val attachmentsJson = attachments.toAttachmentJsonArray()
    val referencesJson = referenceDocuments.toReferenceJsonArray()
    val metadataJson = JSONObject()
    metadata.forEach { (key, value) -> metadataJson.put(key, value) }
    val root = JSONObject()
        .put("requestId", id)
        .put("taskType", taskType.wireName)
        .put("prompt", prompt ?: "")
        .put("stream", stream)
        .put("timeoutMs", timeoutMs ?: 0L)
        .put(
            "input",
            JSONObject()
                .put("prompt", prompt ?: "")
                .put("attachments", attachmentsJson)
                .put("referenceDocuments", referencesJson),
        )
        .put("systemInstruction", systemInstruction)
        .put("metadata", metadataJson)
        .put(
            "generationParams",
            JSONObject()
                .put("maxTokens", maxTokens)
                .put("topK", topK)
                .put("topP", topP)
                .put("temperature", temperature)
                .put("seed", seed),
        )
        .put(
            "modelRequirement",
            JSONObject()
                .put("modelId", modelRequirement.modelId)
                .put("family", modelRequirement.family)
                .put("capability", modelRequirement.capability)
                .put("minContextWindow", modelRequirement.minContextWindow ?: 2048)
                .put("maxLatencyMs", modelRequirement.maxLatencyMs ?: JSONObject.NULL)
                .put("allowFallback", modelRequirement.allowFallback)
                .put("modelPath", modelRequirement.explicitModelPath),
        )
        .put("runtimeOptions", runtimeOptions.toRuntimeOptionsJson())
    sessionId?.let { root.put("sessionId", it) }
    callerPackage?.takeIf { it.isNotBlank() }?.let { root.put("callerPackage", it) }
    return root.toString()
}

private fun List<EssentialMediaAttachment>.toAttachmentJsonArray(): JSONArray {
    val attachmentsJson = JSONArray()
    forEach { attachment ->
        val metadataJson = JSONObject()
        attachment.metadata.forEach { (key, value) -> metadataJson.put(key, value) }
        attachmentsJson.put(
            JSONObject()
                .put("kind", attachment.kind.wireName)
                .put("uri", attachment.uri ?: JSONObject.NULL)
                .put("filePath", attachment.filePath ?: JSONObject.NULL)
                .put("mimeType", attachment.mimeType ?: JSONObject.NULL)
                .put("width", attachment.width ?: JSONObject.NULL)
                .put("height", attachment.height ?: JSONObject.NULL)
                .put("durationMs", attachment.durationMs ?: JSONObject.NULL)
                .put("metadata", metadataJson),
        )
    }
    return attachmentsJson
}

private fun EssentialRuntimeOptions.toRuntimeOptionsJson(): JSONObject {
    val legacySharedMemoryEnabled = sharedMemoryReadEnabled && sharedMemoryWriteEnabled
    return JSONObject()
        .put("preferredModelId", preferredModelId ?: JSONObject.NULL)
        .put("webSearchEnabled", webSearchEnabled)
        .put("locationEnabled", locationEnabled)
        .put("sharedMemoryEnabled", legacySharedMemoryEnabled)
        .put("sharedMemoryReadEnabled", sharedMemoryReadEnabled)
        .put("sharedMemoryWriteEnabled", sharedMemoryWriteEnabled)
        .put("spokenOutputEnabled", spokenOutputEnabled)
}

private fun EssentialModelRequirement.withRuntimePreferredModel(
    options: EssentialRuntimeOptions,
): EssentialModelRequirement {
    val preferred = options.preferredModelId?.trim().orEmpty()
    if (preferred.isEmpty() || preferred == modelId) {
        return this
    }
    return copy(modelId = preferred, allowFallback = true)
}

private fun List<EssentialReferenceDocument>.toReferenceJsonArray(): JSONArray {
    val referencesJson = JSONArray()
    forEach { document ->
        val metadataJson = JSONObject()
        document.metadata.forEach { (key, value) -> metadataJson.put(key, value) }
        referencesJson.put(
            JSONObject()
                .put("title", document.title)
                .put("text", document.text)
                .put("uri", document.uri ?: JSONObject.NULL)
                .put("filePath", document.filePath ?: JSONObject.NULL)
                .put("mimeType", document.mimeType)
                .put("metadata", metadataJson),
        )
    }
    return referencesJson
}

private fun String.toEssentialErrorCode(): EssentialErrorCode {
    return runCatching { EssentialErrorCode.valueOf(this) }
        .getOrDefault(EssentialErrorCode.RUNTIME_UNAVAILABLE)
}

private fun String.toEssentialTaskType(): EssentialTaskType? {
    return EssentialTaskType.entries.firstOrNull { it.wireName == this }
}
