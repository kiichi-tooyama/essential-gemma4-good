# Developer API Guide

This guide explains how to use Essential as a local AI runtime from a Dart or Flutter app. The API is centered on `EssentialClient`, which resolves installed models, sends requests to the runtime, streams output, and reports typed errors.

## When to Use the SDK

Use the SDK when your app needs:

- Local text generation with an installed Gemma LiteRT-LM model
- Streaming responses for chat or live assistant UI
- Runtime model discovery and compatibility checks
- Cancellation, timeout handling, and consistent error codes
- Optional adapter attachment for task-specific behavior

The SDK does not include large model files. Models are downloaded separately through Essential's model management flow, backed by Hugging Face-hosted artifacts.

## Package Location

```text
packages/essential_sdk_dart/
```

Add the package from this repository in your Flutter app:

```yaml
dependencies:
  essential_sdk_dart:
    path: packages/essential_sdk_dart
```

Then import the SDK:

```dart
import 'package:essential_sdk_dart/essential_sdk_dart.dart';
```

## Initialize a Client

Create a client with the models that are available to your app. Each installed model needs a stable ID and a local model path.

```dart
final client = await EssentialClient.initialize(
  const EssentialConfiguration(
    defaultModelId: 'gemma-4-e2b-litertlm-it',
    installedModels: [
      EssentialInstalledModel(
        modelId: 'gemma-4-e2b-litertlm-it',
        modelPath: '/data/user/0/com.example.app/files/models/gemma-4-E2B-it.litertlm',
        family: 'gemma',
        capabilities: ['chat'],
        contextWindow: 8192,
      ),
    ],
  ),
);
```

Before sending generation requests, initialize the runtime:

```dart
await client.initializeRuntime();
```

## List Installed Models

Use `listModels()` to show available local models or choose a fallback.

```dart
final models = await client.listModels();

for (final model in models) {
  print('${model.modelId}: ${model.modelPath}');
}
```

## Generate a Full Response

Use `generate()` when your UI can wait for a complete response.

```dart
final response = await client.generate(
  const EssentialGenerateRequest(
    prompt: 'Summarize this meeting note in three bullet points.',
    modelRequirement: EssentialModelRequirement.fallback(
      'gemma-4-e2b-litertlm-it',
    ),
    timeoutMs: 30000,
  ),
);

print(response.text);
```

## Stream a Response

Use `generateStream()` for chat screens and live assistant experiences.

```dart
await for (final chunk in client.generateStream(
  const EssentialGenerateRequest(
    prompt: 'Draft a polite reply to this message.',
    modelRequirement: EssentialModelRequirement.anyCompatible(),
    timeoutMs: 30000,
  ),
)) {
  updateMessageBubble(chunk.accumulatedText);
}
```

Each stream event contains the current accumulated text, so the UI can redraw directly from the latest chunk.

## Select a Model

The SDK supports three common selection modes.

```dart
const anyCompatible = EssentialModelRequirement.anyCompatible();

const fixedModel = EssentialModelRequirement.fixed(
  'gemma-4-e2b-litertlm-it',
);

const fallbackModel = EssentialModelRequirement.fallback(
  'gemma-4-e2b-litertlm-it',
);
```

Use `anyCompatible()` when any installed model is acceptable. Use `fixed()` when the task requires a specific model. Use `fallback()` when you prefer a model but can accept another compatible one if needed.

## Cancel a Request

Pass a stable request ID when you need cancellation.

```dart
const requestId = 'chat-message-42';

final stream = client.generateStream(
  const EssentialGenerateRequest(
    requestId: requestId,
    prompt: 'Write a long explanation.',
    modelRequirement: EssentialModelRequirement.anyCompatible(),
  ),
);

await client.cancel(requestId);
```

Cancellation is useful when the user edits a prompt, starts a new voice turn, or leaves the screen.

## Handle Errors

SDK failures are reported through `EssentialException`. Use the error code for user-facing recovery.

```dart
try {
  final response = await client.generate(request);
  print(response.text);
} on EssentialException catch (error) {
  switch (error.code) {
    case EssentialErrorCode.modelNotInstalled:
      showInstallModelScreen();
      break;
    case EssentialErrorCode.requestTimedOut:
      showRetryMessage();
      break;
    case EssentialErrorCode.runtimeUnavailable:
      showRuntimeUnavailableMessage();
      break;
    default:
      showGenericError(error.message);
  }
}
```

Important error codes:

- `modelNotInstalled`
- `modelIncompatible`
- `adapterIncompatible`
- `deviceCapacityInsufficient`
- `permissionDenied`
- `sessionCancelled`
- `runtimeUnavailable`
- `invalidConfiguration`
- `requestTimedOut`

## Attach an Adapter

Adapters can be attached when the installed runtime supports them.

```dart
await client.attachAdapter(
  const EssentialAdapterAttachment(
    adapterId: 'meeting-summary',
    modelId: 'gemma-4-e2b-litertlm-it',
    adapterPath: '/data/user/0/com.example.app/files/adapters/meeting-summary.adapter',
  ),
);
```

Detach when the adapter is no longer needed:

```dart
await client.detachAdapter('meeting-summary');
```

## Recommended App Flow

1. Start the app and initialize `EssentialClient`.
2. Call `listModels()` and check whether a compatible model is installed.
3. If no model is available, open Essential's model management screen and download the Hugging Face-backed Gemma LiteRT-LM bundle.
4. Call `initializeRuntime()`.
5. Use `generateStream()` for chat and voice UI, or `generate()` for background tasks.
6. Catch `EssentialException` and route the user to install, retry, or change model settings.

## Notes for Android Integrations

- Use an arm64-v8a device for the included native runtime.
- Keep model files in app-private storage or another location your app can read reliably.
- Do not bundle large model files in the APK. Download and verify them separately.
- Long-running generation should be cancellable from the UI.
- Voice and meeting features require the normal Android microphone and file permissions for your app flow.
