package io.essential.sdk.demo

import android.content.Context
import android.graphics.Bitmap
import androidx.core.content.FileProvider
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import io.essential.sdk.android.EssentialClient
import io.essential.sdk.android.EssentialErrorCode
import io.essential.sdk.android.EssentialException
import io.essential.sdk.android.EssentialGenerateRequest
import io.essential.sdk.android.EssentialMediaAttachment
import io.essential.sdk.android.EssentialMediaKind
import io.essential.sdk.android.EssentialModelRequirement
import io.essential.sdk.android.EssentialReferenceDocument
import io.essential.sdk.android.EssentialServiceConfiguration
import io.essential.sdk.android.EssentialTaskRequest
import io.essential.sdk.android.EssentialTaskType
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class EssentialExternalSdkInstrumentedTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test
    fun externalAppSdkSurfaceWorksAcrossSupportedMethods() = runBlocking {
        val client = EssentialClient.connect(context, configuration())
        try {
            val models = client.models.list()
            assertTrue("Essential host should expose at least one installed model", models.isNotEmpty())
            val model = models.first { it.isInstalled }

            val ensured = client.models.ensureInstalled(EssentialModelRequirement.fixed(model.modelId))
            assertEquals(model.modelId, ensured.modelId)

            assertTrue(client.adapters.list(model.modelId).isEmpty())
            assertTrue(client.adapters.attach("external-sdk-test-session", "adapter-smoke"))
            assertTrue(client.adapters.detach("external-sdk-test-session"))
            client.cancel("external-sdk-test-noop")

            val stt = client.runTask(
                EssentialTaskRequest(
                    taskType = EssentialTaskType.STT,
                    attachments = listOf(
                        EssentialMediaAttachment(
                            kind = EssentialMediaKind.AUDIO,
                            mimeType = "audio/transcript",
                            metadata = mapOf("transcript" to "外部SDKの音声文字起こしテスト"),
                        ),
                    ),
                ),
            )
            assertEquals("外部SDKの音声文字起こしテスト", stt.text)

            val tts = client.runTask(
                EssentialTaskRequest(
                    taskType = EssentialTaskType.TTS,
                    prompt = "外部SDKの読み上げテスト",
                ),
            )
            assertEquals("melotts", tts.modelUsed)

            val generated = client.generate(
                EssentialGenerateRequest(
                    prompt = "1語で返答: SDK",
                    modelRequirement = EssentialModelRequirement.fixed(model.modelId),
                    maxTokens = 8,
                    temperature = 0.0,
                    timeoutMs = 120_000,
                ),
            )
            assertTrue(generated.text.isNotBlank())

            val streamed = client.generateStream(
                EssentialGenerateRequest(
                    prompt = "1語で返答: STREAM",
                    modelRequirement = EssentialModelRequirement.fixed(model.modelId),
                    maxTokens = 8,
                    temperature = 0.0,
                    timeoutMs = 120_000,
                ),
            ).first()
            assertTrue(streamed.accumulatedText.isNotBlank())

            val imageUri = createImageContentUri()
            val multimodal = client.runTask(
                EssentialTaskRequest.pixelFeatureChat(
                    prompt = "添付画像、音声 transcript、URL、参照資料がある前提で、Pixel機能相談として短く応答してください。回答末尾に参照URLを出してください。",
                    image = EssentialMediaAttachment(
                        kind = EssentialMediaKind.IMAGE,
                        uri = imageUri.toString(),
                        mimeType = "image/png",
                    ),
                    audio = EssentialMediaAttachment(
                        kind = EssentialMediaKind.AUDIO,
                        mimeType = "audio/transcript",
                        metadata = mapOf("transcript" to "画面の説明をしてください"),
                    ),
                    references = listOf(
                        EssentialReferenceDocument(
                            title = "Pixel機能資料",
                            text = "Pixelでは設定アプリから通話、バッテリー、アクセシビリティ、カメラ関連機能を確認できます。",
                            uri = "https://support.google.com/pixelphone/",
                        ),
                    ),
                    modelRequirement = EssentialModelRequirement.fixed(model.modelId),
                ).copy(
                    attachments = listOf(
                        EssentialMediaAttachment(
                            kind = EssentialMediaKind.IMAGE,
                            uri = imageUri.toString(),
                            mimeType = "image/png",
                        ),
                        EssentialMediaAttachment(
                            kind = EssentialMediaKind.URL,
                            uri = "https://support.apple.com/ja-jp/102646",
                            mimeType = "text/uri-list",
                        ),
                        EssentialMediaAttachment(
                            kind = EssentialMediaKind.AUDIO,
                            mimeType = "audio/transcript",
                            metadata = mapOf("transcript" to "画面の説明をしてください"),
                        ),
                    ),
                    maxTokens = 16,
                    temperature = 0.0,
                    timeoutMs = 120_000,
                ),
            )
            assertEquals("1", multimodal.metadata["imagePathCount"])
            assertEquals("3", multimodal.metadata["attachmentCount"])
            assertTrue(multimodal.text.isNotBlank())

            val voice = client.runTask(
                EssentialTaskRequest(
                    taskType = EssentialTaskType.VOICE_CONVERSATION,
                    prompt = "短く挨拶してください。",
                    modelRequirement = EssentialModelRequirement.fixed(model.modelId),
                    maxTokens = 8,
                    temperature = 0.0,
                    timeoutMs = 120_000,
                ),
            )
            assertTrue(voice.text.isNotBlank())
            assertNotNull(voice.metadata["audioPlaybackStatus"])
        } finally {
            client.close()
        }
    }

    @Test
    fun failedHostResponseIsExposedAsSdkException() = runBlocking {
        val client = EssentialClient.connect(context, configuration())
        try {
            val error = runCatching {
                client.generate(
                    EssentialGenerateRequest(
                        prompt = "missing model",
                        modelRequirement = EssentialModelRequirement.fixed("missing-sdk-test-model"),
                        maxTokens = 1,
                    ),
                )
            }.exceptionOrNull()
            assertTrue(error is EssentialException)
            assertEquals(EssentialErrorCode.MODEL_NOT_INSTALLED, (error as EssentialException).code)
        } finally {
            client.close()
        }
    }

    private fun configuration(): EssentialServiceConfiguration {
        return EssentialServiceConfiguration(
            servicePackage = "com.example.essential_flutter",
            serviceClassName = "com.example.essential_flutter.service.EssentialService",
            callerPackage = context.packageName,
        )
    }

    private fun createImageContentUri() = FileProvider.getUriForFile(
        context,
        "${context.packageName}.files",
        File(context.cacheDir, "external-sdk-test.png").also { file ->
            Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888).apply {
                eraseColor(0xff3f7f5f.toInt())
                file.outputStream().use { output ->
                    compress(Bitmap.CompressFormat.PNG, 100, output)
                }
                recycle()
            }
        },
    )
}
