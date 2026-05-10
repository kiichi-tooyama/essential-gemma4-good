package io.essential.sdk.android.samples

import android.content.Context
import io.essential.sdk.android.EssentialClient
import io.essential.sdk.android.EssentialMediaAttachment
import io.essential.sdk.android.EssentialMediaKind
import io.essential.sdk.android.EssentialModelRequirement
import io.essential.sdk.android.EssentialRuntimeOptions
import io.essential.sdk.android.EssentialServiceConfiguration
import io.essential.sdk.android.EssentialTaskRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Demo: Pixel feature support chat.
 *
 * The calling app can pass text, an optional screenshot/photo, and an optional
 * speech transcript/audio reference. The final answer is returned to this app
 * through runTask(), while streamTask() can be used for live rendering.
 */
fun runPixelFeatureChatDemo(
    context: Context,
    scope: CoroutineScope,
    question: String,
    screenshotPath: String? = null,
    speechTranscript: String? = null,
    renderPartial: (String) -> Unit,
    renderFinal: (String) -> Unit,
) {
    val configuration = EssentialServiceConfiguration(
        servicePackage = "com.example.essential_flutter",
        serviceClassName = "com.example.essential_flutter.service.EssentialService",
    )

    scope.launch {
        val client = EssentialClient.connect(context, configuration)
        val image = screenshotPath?.let {
            EssentialMediaAttachment(
                kind = EssentialMediaKind.IMAGE,
                filePath = it,
                mimeType = "image/png",
            )
        }
        val audio = speechTranscript?.let {
            EssentialMediaAttachment(
                kind = EssentialMediaKind.AUDIO,
                mimeType = "audio/transcript",
                metadata = mapOf("transcript" to it),
            )
        }
        val request = EssentialTaskRequest.pixelFeatureChat(
            prompt = """
                Pixelの機能相談として、Web検索と現在地コンテキストが利用可能な場合は根拠にして日本語で短く案内してください。
                共有メモリはこのデモではOffです。
                質問: $question
            """.trimIndent(),
            image = image,
            audio = audio,
            runtimeOptions = EssentialRuntimeOptions(
                preferredModelId = "gemma-4-e4b-it",
                webSearchEnabled = true,
                locationEnabled = true,
                sharedMemoryReadEnabled = false,
                sharedMemoryWriteEnabled = false,
            ),
            modelRequirement = EssentialModelRequirement.fallback(
                preferredModelId = "gemma-4-e4b-it",
                capability = "multimodal_chat",
            ),
        )

        var latest = ""
        client.streamTask(request).collect { chunk ->
            latest = chunk.accumulatedText
            renderPartial(latest)
        }
        if (latest.isBlank()) {
            latest = client.runTask(request).text
        }
        renderFinal(latest)
    }
}
