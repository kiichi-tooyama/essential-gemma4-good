# Essential SDK Capability and Integration Guide

Date: 2026-05-03

This document is a programmer-facing guide for building external apps and in-app features on top of Essential. It covers the current SDK surface, the expanded multimodal input model, reference-document grounding for product Q&A, voice responses, URL handling, and known boundaries.

## Goals

The SDK should let another app treat Essential as an on-device AI runtime:

- send text prompts and receive text answers
- stream answers token by token
- send images from camera, gallery, screenshots, or normalized external files
- send audio from microphone recordings, files, or externally normalized WAV/MP3 sources
- send URLs as part of the prompt context
- send reference documents so the model answers against product material, manuals, FAQ, policies, or meeting notes
- ask for TTS/voice conversation responses where the Essential app speaks the answer
- use one session id for continuous chat state
- keep model selection explicit, fallback-capable, and debuggable

The SDK does not upload model bundles, manage R2/CDN delivery, or publish server artifacts. Runtime behavior depends on installed local model bundles and app permissions.

## Capability Inventory

| Area | Current surface | Notes |
| --- | --- | --- |
| Text generation | `generate`, `generateStream`, `runTask(TEXT_GENERATION)` | LiteRT-LM is the preferred runtime for app-facing generation. |
| Streaming | Android `Flow`, Dart `Stream` | Use this for chat UIs. |
| Image input | `EssentialMediaAttachment(kind=IMAGE)` / Dart `EssentialInputAttachment.imageFile` | Passed to LiteRT-LM as `imagePaths`. |
| Audio input | `EssentialMediaAttachment(kind=AUDIO)` / Dart `EssentialInputAttachment.audioFile` | Passed to LiteRT-LM as `audioPaths` where supported. STT is a separate task. |
| URL input | `EssentialMediaKind.URL` / Dart `EssentialInputAttachment.url` | Included in assembled prompt context. If the caller wants page text, the caller should fetch or normalize it and pass a reference document. |
| Reference documents | `EssentialReferenceDocument` | Included before the user prompt and treated as grounding material. |
| Product Q&A | `EssentialTaskRequest.productQaChat(...)` in Android SDK | Uses references first and supports product photos. |
| STT | `EssentialTaskType.STT` / `EssentialAudioTaskPayload` | Uses audio payloads or transcript metadata fallback depending on runtime path. |
| TTS | `EssentialTaskType.TTS` | Essential service can speak generated text using Android TTS. |
| Voice conversation | `EssentialTaskType.VOICE_CONVERSATION` | Generates text and asks the Essential service to speak the answer. |
| Model listing | `client.models.list()` / Dart `listModels()` | Shows installed local models only. |
| Model selection | `EssentialModelRequirement` | Supports fixed model, fallback model, any compatible, and explicit model path. |
| Adapter APIs | `adapters.list/attach/detach` | Present but LiteRT-LM path currently reports no adapters. |

## Request Model

Use `EssentialTaskRequest` for broad app integrations and `EssentialGenerateRequest` for simple text/chat generation.

### Android `EssentialTaskRequest`

Important fields:

- `sessionId`: keep the same value for a conversation or product Q&A thread.
- `taskType`: `TEXT_GENERATION`, `MULTIMODAL_CHAT`, `IMAGE_CAPTION`, `STT`, `TTS`, or `VOICE_CONVERSATION`.
- `prompt`: the user question or command.
- `attachments`: images, audio, URLs, text snippets, documents, or external references.
- `referenceDocuments`: trusted text the model should use as grounding.
- `systemInstruction`: behavior instruction, for example "Use the reference documents first."
- `modelRequirement`: model/capability selection.
- `maxTokens`, `topK`, `topP`, `temperature`: generation controls.
- `metadata`: caller-defined small strings for tracing.

### Dart `EssentialGenerateRequest`

The Dart SDK now accepts:

- `systemInstruction`
- `attachments`
- `referenceDocuments`

The client assembles these into a prompt with sections:

1. `Reference Documents`
2. `Input Attachments`
3. `Media Attachments`
4. `User Prompt`

Image and audio file attachments are passed to the GenAI runtime as `imagePaths` and `audioPaths`.

## Multimodal Attachments

### Android

```kotlin
val image = EssentialMediaAttachment(
    kind = EssentialMediaKind.IMAGE,
    filePath = imageFile.absolutePath,
    mimeType = "image/jpeg",
    metadata = mapOf("source" to "camera"),
)

val url = EssentialMediaAttachment(
    kind = EssentialMediaKind.URL,
    uri = "https://example.com/product",
    mimeType = "text/uri-list",
)
```

### Dart

```dart
const image = EssentialInputAttachment.imageFile(
  '/tmp/product.jpg',
  name: 'product-photo',
  mimeType: 'image/jpeg',
);

const url = EssentialInputAttachment.url(
  'https://example.com/product',
  name: 'product-page',
);
```

## External Normalization

External apps may normalize inputs before passing them to Essential. This is recommended when the caller already has a domain-specific pipeline.

Examples:

- OCR text extracted from a receipt or product label
- cleaned transcript from a meeting recorder
- downloaded webpage text
- PDF text extracted by the caller
- ASR transcript generated by another engine
- product catalog JSON converted to readable text

Send normalized material as text attachments or reference documents:

```kotlin
val manual = EssentialReferenceDocument(
    title = "Product Manual",
    text = extractedPdfText,
    uri = "https://example.com/manual.pdf",
)
```

```dart
const manual = EssentialReferenceDocument(
  title: 'Product Manual',
  text: 'Battery life: 12 hours. Warranty: 1 year.',
  uri: 'https://example.com/manual.pdf',
);
```

## Product Q&A Chat

Use this pattern when building a product support bot, shopping comparison UI, manual assistant, or in-store help app.

### Android Product Q&A

```kotlin
val specs = EssentialReferenceDocument(
    title = "商品仕様",
    text = """
        製品名: Essential Bottle
        容量: 500ml
        保証: 1年
        注意: 食洗機不可
    """.trimIndent(),
    uri = "https://example.com/spec",
)

val photo = EssentialMediaAttachment(
    kind = EssentialMediaKind.IMAGE,
    filePath = productPhoto.absolutePath,
    mimeType = "image/jpeg",
)

val request = EssentialTaskRequest.productQaChat(
    productName = "Essential Bottle",
    question = "この商品は食洗機で洗えますか？レビューで注意点はありますか？",
    references = listOf(specs),
    images = listOf(photo),
    sessionId = "product-essential-bottle",
)

val result = client.runTask(request)
render(result.text)
```

The helper adds a system instruction:

```text
参照資料を最優先し、資料にない内容は推測と明記してください。
```

If live review data is required, the caller should fetch review snippets or search results and pass them as additional `EssentialReferenceDocument` values. The SDK does not silently browse the web for every request because external apps need predictable privacy and latency.

## Voice Response Patterns

### TTS only

```kotlin
val request = EssentialTaskRequest(
    taskType = EssentialTaskType.TTS,
    prompt = "この内容を読み上げてください",
    attachments = listOf(
        EssentialMediaAttachment(
            kind = EssentialMediaKind.TEXT,
            metadata = mapOf("transcript" to "読み上げたい本文"),
        ),
    ),
)
val result = client.runTask(request)
```

### Voice conversation

```kotlin
val request = EssentialTaskRequest(
    sessionId = "voice-session-1",
    taskType = EssentialTaskType.VOICE_CONVERSATION,
    prompt = recognizedSpeech,
    modelRequirement = EssentialModelRequirement.anyCompatible(
        capability = "multimodal_chat",
        maxLatencyMs = 4000,
    ),
    maxTokens = 256,
    temperature = 0.25,
)
val result = client.runTask(request)
// Essential service speaks the answer and also returns result.text.
```

Use `streamTask` when you need visible incremental text. Use `runTask` when you only need the final text and spoken output.

## URL Handling

URLs are supported as input context:

```kotlin
val page = EssentialMediaAttachment(
    kind = EssentialMediaKind.URL,
    uri = "https://example.com/help",
)
```

For robust answers, callers should pass fetched and cleaned page text as a reference document:

```kotlin
val pageText = EssentialReferenceDocument(
    title = "Help page",
    uri = "https://example.com/help",
    text = cleanedHtmlText,
)
```

This avoids ambiguous behavior where the SDK would need to decide whether it may access the network. Essential app UI has its own web-search path, but external SDK calls should be explicit.

## Permission and File Rules

External apps should prefer file paths or content URIs they control. The Essential service can only use paths it can read.

Recommended caller behavior:

- copy temporary images/audio into app-accessible cache
- use stable file extensions and MIME types
- provide normalized text when file access may fail
- avoid secrets in `metadata`
- keep reference documents below the context budget
- do not pass raw credentials, cookies, or private tokens

## Model Selection

For general multimodal chat:

```kotlin
EssentialModelRequirement.anyCompatible(
    capability = "multimodal_chat",
    minContextWindow = 2048,
)
```

For a specific installed model:

```kotlin
EssentialModelRequirement.fixed(
    modelId = "gemma-4-e2b-litertlm-it",
    capability = "multimodal_chat",
)
```

For internal testing with a direct file:

```kotlin
EssentialModelRequirement.explicit(
    modelPath = "/data/user/0/com.example.essential_flutter/files/model.litertlm",
    capability = "multimodal_chat",
)
```

## Streaming Contract

Android:

```kotlin
client.streamTask(request).collect { chunk ->
    textView.text = chunk.accumulatedText
}
```

Dart:

```dart
await for (final chunk in client.generateStream(request)) {
  render(chunk.accumulatedText);
}
```

Cancellation should call `client.cancel(requestId)` or cancel the stream subscription.

## Current Boundaries

- True speaker embedding based diarization is not yet exposed by the SDK. Meeting speaker labels currently persist names and use heuristic segmentation unless a future runtime returns speaker embeddings.
- URL attachments are prompt context unless the caller passes fetched content. Essential UI can browse/search, but SDK calls should be explicit for privacy.
- Adapters are represented in the API but LiteRT-LM adapter attachment is not enabled.
- Only one heavy GenAI inference should run at a time on mobile devices.
- Reference documents are not a vector database. They are prompt-grounding text. Long corpora should be chunked by the caller.
- Audio input depends on installed model support. STT and TTS are separate runtime paths.

## Recommended External App Architecture

1. Collect user input in the external app.
2. Normalize what the app can normalize:
   - OCR text
   - webpage text
   - PDF text
   - product catalog rows
   - speech transcript
3. Build `EssentialReferenceDocument` values for trusted context.
4. Attach raw image/audio files only when the model should inspect the media itself.
5. Use `sessionId` for continuity.
6. Use `streamTask` for chat UI.
7. Use `VOICE_CONVERSATION` or a separate TTS request for spoken answers.
8. Surface SDK errors with their `EssentialErrorCode`.

## Example End-to-End Flow

```kotlin
val client = EssentialClient.connect(
    context = context,
    configuration = EssentialServiceConfiguration(
        servicePackage = "com.example.essential_flutter",
        serviceClassName = "com.example.essential_flutter.service.EssentialService",
        callerPackage = context.packageName,
    ),
)

val productDocs = listOf(
    EssentialReferenceDocument(
        title = "FAQ",
        text = "返品は購入から30日以内。開封済み消耗品は対象外。",
        uri = "https://example.com/faq",
    ),
    EssentialReferenceDocument(
        title = "レビュー要約",
        text = "高評価: 軽い。低評価: キャップが固いという声がある。",
    ),
)

val request = EssentialTaskRequest.productQaChat(
    productName = "Essential Bottle",
    question = "返品できますか？レビュー上の注意点も教えて。",
    references = productDocs,
    sessionId = "product-essential-bottle",
)

client.streamTask(request).collect { chunk ->
    render(chunk.accumulatedText)
}
```

Expected model behavior:

- answer directly
- cite the relevant reference title or URL when useful
- separate facts from inference
- mention missing information instead of fabricating

## Implementation Checklist for SDK Consumers

- [ ] Decide whether the request is text-only or multimodal.
- [ ] Choose `runTask` vs `streamTask`.
- [ ] Use a stable `sessionId` for chat.
- [ ] Add images/audio as attachments with MIME types.
- [ ] Add URLs as URL attachments.
- [ ] Add fetched or normalized text as reference documents.
- [ ] Select `modelRequirement` by capability.
- [ ] Set conservative `maxTokens` for voice, larger for document Q&A.
- [ ] Handle `MODEL_NOT_INSTALLED`, `MODEL_INCOMPATIBLE`, `REQUEST_TIMED_OUT`, and `RUNTIME_UNAVAILABLE`.
- [ ] Log request ids for debugging.
- [ ] Never pass secrets in prompt, metadata, or reference docs.
