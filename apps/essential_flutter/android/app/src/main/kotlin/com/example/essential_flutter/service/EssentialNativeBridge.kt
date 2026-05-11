package com.example.essential_flutter.service

internal class EssentialNativeBridge {
    init {
        System.loadLibrary("essential_android_service")
    }

    external fun nativeRunInference(
        requestId: String,
        modelPath: String,
        prompt: String,
        contextSize: Int,
        threads: Int,
        batchThreads: Int,
        gpuLayers: Int,
        useMmap: Boolean,
        useMlock: Boolean,
        maxTokens: Int,
        topK: Int,
        topP: Float,
        temperature: Float,
        seed: Int,
    ): String

    external fun nativeStreamInference(
        requestId: String,
        modelPath: String,
        prompt: String,
        contextSize: Int,
        threads: Int,
        batchThreads: Int,
        gpuLayers: Int,
        useMmap: Boolean,
        useMlock: Boolean,
        maxTokens: Int,
        topK: Int,
        topP: Float,
        temperature: Float,
        seed: Int,
        callback: TokenCallback,
    ): String

    external fun nativeCancel(requestId: String): Boolean

    external fun nativeAttachAdapter(requestId: String, adapterPath: String, scale: Float): Boolean

    external fun nativeDetachAdapter(requestId: String): Boolean

    external fun nativeSynthesizeTtsPcm16(
        modelPath: String,
        text: String,
        speed: Float,
        pitch: Float,
    ): ShortArray
}

internal interface TokenCallback {
    fun onToken(token: String)
}
