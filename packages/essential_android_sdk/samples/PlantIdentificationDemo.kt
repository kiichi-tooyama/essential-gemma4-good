package io.essential.sdk.android.samples

import android.content.Context
import io.essential.sdk.android.EssentialClient
import io.essential.sdk.android.EssentialMediaAttachment
import io.essential.sdk.android.EssentialMediaKind
import io.essential.sdk.android.EssentialModelRequirement
import io.essential.sdk.android.EssentialServiceConfiguration
import io.essential.sdk.android.EssentialTaskRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Demo: identify and explain a plant from a photo.
 *
 * A production app should pass a content URI or file path that the Essential
 * host app can read. If a vision-capable bundle is installed, the host can use
 * the image directly. If only a text model is installed, the response will
 * clearly ask for additional visual details instead of pretending certainty.
 */
fun runPlantIdentificationDemo(
    context: Context,
    scope: CoroutineScope,
    plantPhotoPath: String,
    renderResult: (String) -> Unit,
) {
    val configuration = EssentialServiceConfiguration(
        servicePackage = "com.example.essential_flutter",
        serviceClassName = "com.example.essential_flutter.service.EssentialService",
    )

    scope.launch {
        val client = EssentialClient.connect(context, configuration)
        val request = EssentialTaskRequest.plantIdentification(
            image = EssentialMediaAttachment(
                kind = EssentialMediaKind.IMAGE,
                filePath = plantPhotoPath,
                mimeType = "image/jpeg",
            ),
            modelRequirement = EssentialModelRequirement.fallback(
                preferredModelId = "gemma-4-e4b-it",
                capability = "plant_identification",
            ),
        )
        renderResult(client.runTask(request).text)
    }
}
