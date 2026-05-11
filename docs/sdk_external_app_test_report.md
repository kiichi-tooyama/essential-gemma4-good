# External App SDK Test Report

Date: 2026-04-28

## Scope

This report covers SDK calls from external apps into the Essential host app:
text generation, streamed generation, final result return, image attachment
metadata, speech transcript/audio attachment metadata, and demo app contracts.

## Implemented External APIs

Android SDK:

- `generate(request)`: sends a prompt and returns the final text to the caller.
- `generateStream(request)`: streams partial text to the caller and completes
  with the same request id.
- `runTask(request)`: sends a typed task and returns a final `EssentialTaskResult`.
- `streamTask(request)`: streams typed task chunks for chat-style UI.
- `EssentialTaskRequest.pixelFeatureChat(...)`: demo helper for Pixel usage support.
- `EssentialTaskRequest.plantIdentification(...)`: demo helper for plant photo workflows.

iOS EssentialKit:

- `runTask(_:)`: maps typed external tasks to the installed Essential inference engine and returns `EssentialTaskResult`.
- `streamTask(_:)`: streams typed task chunks to the caller.
- `EssentialTaskRequest.pixelFeatureChat(...)`
- `EssentialTaskRequest.plantIdentification(...)`

Dart SDK:

- Existing `runTask(...)` / `streamTask(...)` APIs were verified with multimodal contract tests.

Supported task types:

- `text_generation`
- `multimodal_chat`
- `image_caption`
- `plant_identification`
- `stt`
- `tts`
- `voice_conversation`

## Result Return Behavior

The final result is returned to the calling app in-process through the SDK:

- Synchronous: `EssentialTaskResult.text`
- Streaming: `EssentialTaskChunk.accumulatedText`
- Errors: `EssentialException` with `EssentialErrorCode`

No polling is required by the external app.

## Image And Speech Attachment Behavior

External apps can pass attachments as URI/file metadata:

- Image: `EssentialMediaAttachment(kind = IMAGE, uri/filePath, mimeType, width, height)`
- Audio: `EssentialMediaAttachment(kind = AUDIO, uri/filePath, mimeType, durationMs)`
- Speech transcript: `metadata["transcript"]`

The current host service accepts this contract and forwards the attachment
summary into the model prompt. A true image-understanding answer requires an
installed vision-capable model bundle. When only a text model is installed, the
service must not claim it inspected pixels; it asks for missing visual details.

## Measured Local Model Performance

Gemma-4-E4B-it Q4_K_M GGUF:

- File: `gemma-4-E4B-it-Q4_K_M.gguf`
- Size: `5,335,285,504 bytes`
- SHA-256: `e87f2659d0674d528911b017b65e3da65912c961dd53aa4eb7d244e29c64c3fd`
- Local Pixel M4 `llama-cli` Japanese prompt speed:
  - Prompt: `36.6 tokens/s`
  - Generation: `27.8 tokens/s`
- Memory shown by `llama-cli`:
  - Model: about `5073 MiB`
  - Context: about `28 MiB`
  - Compute: about `543 MiB`

Q2_K was tested and rejected because Japanese output quality degraded. Q4_K_M is
the documented default for E4B.

## Verification Commands

Completed successfully:

- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`
- Android APK install through `adb install -r`
- Android app launch through `adb shell monkey`; logcat checked with no `FATAL EXCEPTION`
- `packages/essential_android_sdk ./gradlew :assembleRelease`
- `platform/ios_framework/EssentialKit swift test`
- `packages/essential_sdk_dart dart test`
- `PYTHONPATH=packages/essential_sdk_python python3 -m pytest packages/essential_sdk_python/tests`
- `PYTHONPATH=server/common:server/registry_api ... unittest server/tests/test_bundle_seed_integrity.py`
- Registry API health/catalog/download/range artifact checks
- Android SDK release AAR build

Observed existing failure outside this change:

- `platform/ios_framework/AppGroupSupport swift test` currently fails because
  `AppGroupSupportTests.swift` constructs `SharedAdapterRecord` without the
  newer `ownerAppId` / `namespaceId` arguments. EssentialKit's own tests pass.

## Known Limits

- Plant identification accuracy cannot be marketed as photo-level recognition
  unless a vision-capable model bundle is installed and tested with labeled
  plant images.
- Current Android service transport passes attachment references and metadata,
  not raw image/audio bytes, to keep IPC stable and avoid Binder size limits.
- Voice conversation uses the same typed task contract. Full microphone capture
  and audio playback remain the calling app's UI responsibility unless it uses
  Essential's in-app chat UI.
