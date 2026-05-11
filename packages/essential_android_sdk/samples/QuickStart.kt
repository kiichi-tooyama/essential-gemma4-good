package io.essential.sdk.android.samples

import android.content.Context
import io.essential.sdk.android.EssentialClient
import io.essential.sdk.android.EssentialGenerateRequest
import io.essential.sdk.android.EssentialModelRequirement
import io.essential.sdk.android.EssentialServiceConfiguration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

fun connectAndStream(
    context: Context,
    scope: CoroutineScope,
    render: (String) -> Unit,
) {
    val configuration = EssentialServiceConfiguration(
        servicePackage = "com.example.essential_flutter",
        serviceClassName = "com.example.essential_flutter.service.EssentialService",
    )

    scope.launch {
        val client = EssentialClient.connect(context, configuration)
        client.generateStream(
            EssentialGenerateRequest(
                prompt = "端末上で要約して",
                modelRequirement = EssentialModelRequirement.fallback("essential-mini"),
                timeoutMs = 10_000,
            ),
        ).collect { chunk ->
            render(chunk.accumulatedText)
        }
    }
}