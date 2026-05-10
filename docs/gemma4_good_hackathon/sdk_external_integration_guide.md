# External Integration Guide

This guide shows how another Android app can use Essential as a local AI API.
The 3-minute demo uses the Pixel AI Chat app as the proof.

## Main Idea

An external app does not need to embed its own AI model. It can connect to the
Essential host app and send a typed task request. Essential routes the request
to the installed Gemma 4 path and returns the result.

This lets another app use:

- text prompts,
- image input,
- voice transcripts,
- audio metadata,
- reference documents or internal text,
- optional web search,
- optional current location,
- optional shared memory,
- optional spoken output.

## Connection

```kotlin
val client = EssentialClient.connect(
    context = context,
    configuration = EssentialServiceConfiguration(
        servicePackage = "com.example.essential_flutter",
        serviceClassName = "com.example.essential_flutter.service.EssentialService",
        callerPackage = context.packageName,
        defaultModelId = "gemma-4-e4b-it",
    ),
)
```

## Pixel Feature Chat Demo

This is the request shape used by the Pixel AI Chat demo app.

```kotlin
val image = selectedImageUri?.let {
    EssentialMediaAttachment(
        kind = EssentialMediaKind.IMAGE,
        uri = it.toString(),
        mimeType = contentResolver.getType(it) ?: "image/*",
    )
}

val speechTranscript = EssentialMediaAttachment(
    kind = EssentialMediaKind.AUDIO,
    mimeType = "audio/transcript",
    metadata = mapOf("transcript" to question),
)

val references = listOf(
    EssentialReferenceDocument(
        title = "Pixel Demo Local Guide",
        text = quickGuideText,
        mimeType = "text/plain",
        metadata = mapOf("source" to "bundled_demo_notes"),
    ),
)

val request = EssentialTaskRequest.pixelFeatureChat(
    prompt = """
        Answer in practical English.
        This app is calling Essential from an external Android app.
        Use provided web results, location context, image content, and reference
        documents when available.
        Shared memory is off for this demo request.

        Question: $question
    """.trimIndent(),
    image = image,
    audio = speechTranscript,
    references = references,
    runtimeOptions = EssentialRuntimeOptions(
        preferredModelId = "gemma-4-e4b-it",
        webSearchEnabled = true,
        locationEnabled = true,
        sharedMemoryReadEnabled = false,
        sharedMemoryWriteEnabled = false,
        spokenOutputEnabled = true,
    ),
    modelRequirement = EssentialModelRequirement.fallback(
        preferredModelId = "gemma-4-e4b-it",
        capability = "multimodal_chat",
        minContextWindow = 4096,
    ),
).copy(
    attachments = listOfNotNull(image, speechTranscript),
    maxTokens = 384,
    timeoutMs = 90_000,
)

val result = client.runTask(request)
```

Demo prompt:

```text
How do I use Call Screen on a Pixel phone?
```

Optional image prompt:

```text
Explain this Pixel settings screenshot and tell me what to tap next.
```

## Text Generation

```kotlin
val request = EssentialTaskRequest(
    taskType = EssentialTaskType.TEXT_GENERATION,
    prompt = "Summarize this note in three short bullets.",
    runtimeOptions = EssentialRuntimeOptions(
        preferredModelId = "gemma-4-e2b-it",
        webSearchEnabled = false,
        locationEnabled = false,
        sharedMemoryReadEnabled = false,
        sharedMemoryWriteEnabled = false,
    ),
    maxTokens = 256,
)

val result = client.runTask(request)
```

## Image Question

```kotlin
val image = EssentialMediaAttachment(
    kind = EssentialMediaKind.IMAGE,
    filePath = photoFile.absolutePath,
    mimeType = "image/jpeg",
)

val request = EssentialTaskRequest(
    taskType = EssentialTaskType.MULTIMODAL_CHAT,
    prompt = "What should I pay attention to in this photo?",
    attachments = listOf(image),
    runtimeOptions = EssentialRuntimeOptions(
        preferredModelId = "gemma-4-e4b-it",
        webSearchEnabled = true,
        locationEnabled = true,
        sharedMemoryReadEnabled = false,
        sharedMemoryWriteEnabled = false,
    ),
    maxTokens = 512,
)

val result = client.runTask(request)
```

## Voice Input And Spoken Output

The external app can use Android speech recognition, then send the final
transcript to Essential.

```kotlin
val transcript = speechRecognizerFacade.recognizeOnce()
val request = EssentialTaskRequest(
    taskType = EssentialTaskType.VOICE_CONVERSATION,
    prompt = transcript,
    runtimeOptions = EssentialRuntimeOptions(
        preferredModelId = "gemma-4-e2b-it",
        spokenOutputEnabled = true,
    ),
    maxTokens = 192,
)

val result = client.runTask(request)
```

For direct speech output:

```kotlin
val request = EssentialTaskRequest(
    taskType = EssentialTaskType.TTS,
    prompt = "Your route is clear. Turn left at the next crossing.",
)

val result = client.runTask(request)
```

## Meeting Or Internal Document Grounding

External apps can send internal text or prepared transcripts as context.

```kotlin
val request = EssentialTaskRequest(
    taskType = EssentialTaskType.TEXT_GENERATION,
    prompt = """
        Summarize this meeting transcript, list tasks, and translate the summary
        into Japanese.

        Transcript:
        $meetingTranscript
    """.trimIndent(),
    runtimeOptions = EssentialRuntimeOptions(
        preferredModelId = "gemma-4-e4b-it",
        webSearchEnabled = false,
        locationEnabled = false,
    ),
    maxTokens = 700,
)
```

This is important for apps that already have private notes, support logs,
meeting transcripts, or product documents. They can pass that text to Essential
without building a new AI stack.

## Runtime Customization

`EssentialRuntimeOptions` lets the caller control each request:

- `preferredModelId`: choose the model to try first.
- `webSearchEnabled`: allow web grounding when the app and network permit it.
- `locationEnabled`: allow current-location context when permission is granted.
- `sharedMemoryReadEnabled`: allow past shared memory to be read.
- `sharedMemoryWriteEnabled`: allow the request result to write new shared
  memory.
- `sharedMemoryEnabled`: legacy shortcut that enables both read and write.
- `spokenOutputEnabled`: ask the host to prepare speech output when supported.

The Pixel demo keeps web and location enabled, but turns shared memory read and
write off. This proves that the external app can control privacy behavior per
request.

## Demo Checklist

- Show the Pixel demo app as a separate app.
- Send a Pixel feature question.
- Mention that it calls Essential through the local SDK.
- Mention that text, image, voice transcript, reference documents, web search,
  location, shared memory, and spoken output are API-level options.
- Explain that Gemma 4 LiteRT-LM remains the main local reasoning engine.
