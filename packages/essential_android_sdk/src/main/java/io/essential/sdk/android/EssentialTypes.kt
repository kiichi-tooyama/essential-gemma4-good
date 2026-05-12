package io.essential.sdk.android

import java.io.File
import java.util.UUID

data class EssentialServiceConfiguration(
    val servicePackage: String,
    val serviceClassName: String,
    val callerPackage: String? = null,
    val defaultModelId: String? = null,
)

data class EssentialModelRequirement(
    val modelId: String? = null,
    val family: String? = null,
    val capability: String? = null,
    val minContextWindow: Int? = null,
    val maxLatencyMs: Int? = null,
    val allowFallback: Boolean = true,
    val explicitModelPath: String? = null,
) {
    companion object {
        fun anyCompatible(
            family: String? = null,
            capability: String? = null,
            minContextWindow: Int? = null,
            maxLatencyMs: Int? = null,
        ) = EssentialModelRequirement(
            family = family,
            capability = capability,
            minContextWindow = minContextWindow,
            maxLatencyMs = maxLatencyMs,
            allowFallback = true,
        )

        fun fixed(
            modelId: String,
            family: String? = null,
            capability: String? = null,
            minContextWindow: Int? = null,
            maxLatencyMs: Int? = null,
        ) = EssentialModelRequirement(
            modelId = modelId,
            family = family,
            capability = capability,
            minContextWindow = minContextWindow,
            maxLatencyMs = maxLatencyMs,
            allowFallback = false,
        )

        fun fallback(
            preferredModelId: String,
            family: String? = null,
            capability: String? = null,
            minContextWindow: Int? = null,
            maxLatencyMs: Int? = null,
        ) = EssentialModelRequirement(
            modelId = preferredModelId,
            family = family,
            capability = capability,
            minContextWindow = minContextWindow,
            maxLatencyMs = maxLatencyMs,
            allowFallback = true,
        )

        fun explicit(
            modelPath: String,
            modelId: String? = null,
            family: String? = null,
            capability: String? = null,
            minContextWindow: Int? = null,
            maxLatencyMs: Int? = null,
            allowFallback: Boolean = true,
        ) = EssentialModelRequirement(
            modelId = modelId,
            family = family,
            capability = capability,
            minContextWindow = minContextWindow,
            maxLatencyMs = maxLatencyMs,
            allowFallback = allowFallback,
            explicitModelPath = modelPath,
        )
    }
}

data class EssentialGenerateRequest(
    val id: String? = null,
    val sessionId: String? = null,
    val prompt: String,
    val systemInstruction: String = "",
    val attachments: List<EssentialMediaAttachment> = emptyList(),
    val referenceDocuments: List<EssentialReferenceDocument> = emptyList(),
    val modelRequirement: EssentialModelRequirement = EssentialModelRequirement.anyCompatible(),
    val runtimeOptions: EssentialRuntimeOptions = EssentialRuntimeOptions(),
    val adapterId: String? = null,
    val maxTokens: Int = 128,
    val topK: Int = 40,
    val topP: Double = 0.95,
    val temperature: Double = 0.8,
    val seed: Int = 42,
    val timeoutMs: Long? = null,
) {
    fun withRequestId(requestId: String): EssentialGenerateRequest {
        return copy(id = requestId)
    }
}

data class EssentialGenerateChunk(
    val requestId: String,
    val delta: String,
    val accumulatedText: String,
    val modelUsed: String,
)

data class EssentialRuntimeOptions(
    val preferredModelId: String? = null,
    val webSearchEnabled: Boolean = false,
    val locationEnabled: Boolean = false,
    @Deprecated(
        message = "Use sharedMemoryReadEnabled and sharedMemoryWriteEnabled for per-request control.",
        replaceWith = ReplaceWith("sharedMemoryReadEnabled && sharedMemoryWriteEnabled"),
    )
    val sharedMemoryEnabled: Boolean = false,
    val sharedMemoryReadEnabled: Boolean = sharedMemoryEnabled,
    val sharedMemoryWriteEnabled: Boolean = sharedMemoryEnabled,
    val spokenOutputEnabled: Boolean = false,
)

data class EssentialGenerateResult(
    val requestId: String,
    val text: String,
    val modelUsed: String,
    val finishReason: String,
)

enum class EssentialTaskType(val wireName: String) {
    TEXT_GENERATION("text_generation"),
    MULTIMODAL_CHAT("multimodal_chat"),
    IMAGE_CAPTION("image_caption"),
    PLANT_IDENTIFICATION("plant_identification"),
    STT("stt"),
    TTS("tts"),
    VOICE_CONVERSATION("voice_conversation"),
}

enum class EssentialMediaKind(val wireName: String) {
    IMAGE("image"),
    AUDIO("audio"),
    TEXT("text"),
    URL("url"),
    DOCUMENT("document"),
    REFERENCE("reference"),
}

data class EssentialMediaAttachment(
    val kind: EssentialMediaKind,
    val uri: String? = null,
    val filePath: String? = null,
    val mimeType: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val durationMs: Long? = null,
    val metadata: Map<String, String> = emptyMap(),
)

data class EssentialReferenceDocument(
    val title: String,
    val text: String = "",
    val uri: String? = null,
    val filePath: String? = null,
    val mimeType: String = "text/plain",
    val metadata: Map<String, String> = emptyMap(),
)

data class EssentialTaskRequest(
    val id: String? = null,
    val sessionId: String? = null,
    val taskType: EssentialTaskType,
    val prompt: String? = null,
    val modelRequirement: EssentialModelRequirement = EssentialModelRequirement.anyCompatible(),
    val attachments: List<EssentialMediaAttachment> = emptyList(),
    val referenceDocuments: List<EssentialReferenceDocument> = emptyList(),
    val systemInstruction: String = "",
    val runtimeOptions: EssentialRuntimeOptions = EssentialRuntimeOptions(),
    val maxTokens: Int = 256,
    val topK: Int = 40,
    val topP: Double = 0.95,
    val temperature: Double = 0.7,
    val seed: Int = 42,
    val timeoutMs: Long? = null,
    val metadata: Map<String, String> = emptyMap(),
) {
    fun withRequestId(requestId: String): EssentialTaskRequest = copy(id = requestId)

    companion object {
        fun pixelFeatureChat(
            prompt: String,
            sessionId: String? = null,
            image: EssentialMediaAttachment? = null,
            audio: EssentialMediaAttachment? = null,
            references: List<EssentialReferenceDocument> = emptyList(),
            runtimeOptions: EssentialRuntimeOptions = EssentialRuntimeOptions(
                webSearchEnabled = true,
                locationEnabled = true,
                sharedMemoryReadEnabled = false,
                sharedMemoryWriteEnabled = false,
            ),
            modelRequirement: EssentialModelRequirement = EssentialModelRequirement.anyCompatible(
                capability = "multimodal_chat",
            ),
        ): EssentialTaskRequest = EssentialTaskRequest(
            sessionId = sessionId,
            taskType = EssentialTaskType.MULTIMODAL_CHAT,
            prompt = prompt,
            modelRequirement = modelRequirement,
            attachments = listOfNotNull(image, audio),
            referenceDocuments = references,
            runtimeOptions = runtimeOptions,
            systemInstruction = """
                You are a Pixel feature support assistant running through the Essential AI API.
                Web search and location context may be supplied by the host app; when present, use them directly and do not claim that web search or location access is unavailable.
                Shared memory is optional past context only. If memory is disabled or not relevant, ignore it completely.
                For product URLs, product names, or product photos, identify the item, use web/review context when supplied, and compare options by use case.
                Answer in the user's language with practical steps and concise cautions.
            """.trimIndent(),
            metadata = mapOf(
                "demo" to "pixel_feature_chat",
                "domain" to "pixel_usage_support",
                "web_first" to runtimeOptions.webSearchEnabled.toString(),
                "location_context" to runtimeOptions.locationEnabled.toString(),
                "shared_memory_read" to runtimeOptions.sharedMemoryReadEnabled.toString(),
                "shared_memory_write" to runtimeOptions.sharedMemoryWriteEnabled.toString(),
            ),
        )

        @Deprecated(
            message = "Use pixelFeatureChat for the external AI API demo app.",
            replaceWith = ReplaceWith("pixelFeatureChat(prompt, sessionId, image, audio, references, modelRequirement = modelRequirement)"),
        )
        fun macHelpChat(
            prompt: String,
            sessionId: String? = null,
            image: EssentialMediaAttachment? = null,
            audio: EssentialMediaAttachment? = null,
            references: List<EssentialReferenceDocument> = emptyList(),
            modelRequirement: EssentialModelRequirement = EssentialModelRequirement.anyCompatible(
                capability = "multimodal_chat",
            ),
        ): EssentialTaskRequest = EssentialTaskRequest(
            sessionId = sessionId,
            taskType = EssentialTaskType.MULTIMODAL_CHAT,
            prompt = prompt,
            modelRequirement = modelRequirement,
            attachments = listOfNotNull(image, audio),
            referenceDocuments = references,
            metadata = mapOf(
                "demo" to "mac_help_chat",
                "domain" to "mac_usage_support",
            ),
        )

        fun productQaChat(
            productName: String,
            question: String,
            references: List<EssentialReferenceDocument>,
            images: List<EssentialMediaAttachment> = emptyList(),
            sessionId: String? = null,
            modelRequirement: EssentialModelRequirement = EssentialModelRequirement.anyCompatible(
                capability = "multimodal_chat",
            ),
        ): EssentialTaskRequest = EssentialTaskRequest(
            sessionId = sessionId,
            taskType = EssentialTaskType.MULTIMODAL_CHAT,
            prompt = "商品「$productName」について質問に答えてください。\n質問: $question",
            modelRequirement = modelRequirement,
            attachments = images,
            referenceDocuments = references,
            systemInstruction = "参照資料を最優先し、資料にない内容は推測と明記してください。",
            metadata = mapOf(
                "domain" to "product_qa",
                "productName" to productName,
            ),
        )

        fun plantIdentification(
            image: EssentialMediaAttachment,
            prompt: String = "この植物の名前、特徴、育て方の注意点を日本語で説明してください。",
            modelRequirement: EssentialModelRequirement = EssentialModelRequirement.anyCompatible(
                capability = "plant_identification",
            ),
        ): EssentialTaskRequest = EssentialTaskRequest(
            taskType = EssentialTaskType.PLANT_IDENTIFICATION,
            prompt = prompt,
            modelRequirement = modelRequirement,
            attachments = listOf(image),
            metadata = mapOf("demo" to "plant_identification"),
        )
    }
}

data class EssentialTaskResult(
    val requestId: String,
    val taskType: EssentialTaskType,
    val status: String,
    val text: String,
    val modelUsed: String,
    val finishReason: String,
    val metadata: Map<String, String> = emptyMap(),
)

data class EssentialTaskChunk(
    val requestId: String,
    val taskType: EssentialTaskType,
    val delta: String,
    val accumulatedText: String,
    val modelUsed: String,
)

data class EssentialModelDescriptor(
    val modelId: String,
    val family: String?,
    val path: String?,
    val sizeBytes: Long,
    val route: String,
    val runtimeFamily: String = route,
    val supportsImage: Boolean = false,
    val supportsAudio: Boolean = false,
) {
    val isInstalled: Boolean
        get() = !path.isNullOrBlank() || route == "mock"
}

data class EssentialAdapterDescriptor(
    val adapterId: String,
    val baseModelId: String,
)

enum class EssentialErrorCode {
    MODEL_NOT_INSTALLED,
    MODEL_INCOMPATIBLE,
    ADAPTER_INCOMPATIBLE,
    DEVICE_CAPACITY_INSUFFICIENT,
    PERMISSION_DENIED,
    SESSION_CANCELLED,
    RUNTIME_UNAVAILABLE,
    INVALID_CONFIGURATION,
    REQUEST_TIMED_OUT,
}

class EssentialException(
    val code: EssentialErrorCode,
    override val message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

internal data class ResolvedModel(
    val modelId: String?,
    val modelPath: String?,
)

internal fun nextRequestId(): String = UUID.randomUUID().toString()
