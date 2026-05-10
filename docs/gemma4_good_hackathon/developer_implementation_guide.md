# Developer Implementation Guide

This guide explains the submission build from a developer point of view. It is
written for reviewers who want to understand how Essential exposes Gemma 4
LiteRT-LM as a local Android AI service.

## Runtime Overview

Essential runs the main language and multimodal reasoning path on Gemma 4
LiteRT-LM through the Android app runtime. The app keeps a task router between
the UI, the SDK service, and the model runtime, so the same capability can be
used from chat, Live voice, meeting notes, and external Android apps.

Core runtime choices:

- Main generation: Gemma 4 LiteRT-LM.
- Live speech input: Android on-device `SpeechRecognizer`.
- Imported meeting audio: on-device Whisper file transcription.
- Speech output: Android TTS. Essential does not require a MeloTTS/Piper model
  download for the normal demo build.
- Web context: optional live web search service.
- Location context: Android location and reverse-geocoding channel.
- Offline mode: native connectivity is checked before web or location work.
  When the device is offline, Essential skips those tools and continues with
  the local model path.

Recorded meeting audio is not sent through `SpeechRecognizer`, because that API
is for live recognition. For imported MP3/WAV files, Essential normalizes the
audio and runs the local Whisper runtime before summary, translation, tasks,
and Q&A.

## App Surfaces

Essential has four main surfaces for the demo:

- Chat: text, image, and document-style prompts.
- Essential Live: one-shot or looped voice input, local Gemma 4 generation, and
  spoken answers.
- Meeting Assistant: transcript-based summary, translation, tasks, Q&A, and
  mind-map style review.
- Model Management: Gemma 4 LiteRT-LM bundles and speech-output assets.

## External API Flow

External apps call Essential through the Android SDK service. The external app
builds an `EssentialTaskRequest`, sends text and optional attachments, and gets
back a task response or stream.

Typical request types:

- `TEXT_GENERATION` for normal local answers.
- `MULTIMODAL_CHAT` for text plus image input.
- `VOICE_CONVERSATION` for a transcript captured with Android
  `SpeechRecognizer`.
- `TTS` for spoken output through Android TTS.

Input and output coverage:

- Inputs: text, voice transcripts, audio references, photos, and reference
  documents.
- Outputs: generated text and spoken output.
- Runtime options: callers can pass `EssentialRuntimeOptions` to request a
  preferred model, enable or disable web search, allow or block location
  context, allow or block shared memory, and request spoken output behavior.

This is the key submission point: Essential is not only a single app screen. It
is an on-device AI layer that another Android app can use like a private local
API.

## Voice Pipeline

The Live flow is:

1. The app calls the native `essential/native_voice` channel.
2. Android `SpeechRecognizer` captures live speech on device when available.
3. The transcript is sent to Gemma 4 LiteRT-LM.
4. Generated text is streamed to the UI.
5. The answer is spoken through Android TTS.

The native channel also exposes `getSpeechRecognizerState` for device tests. It
reports the Android API level, normal recognition availability, on-device
recognition availability, and microphone permission state.

## Image And Context Inputs

Image input is passed as an attachment to the local generation task. The prompt
can ask Gemma 4 to read a photo, describe a screen, or explain a field object.

Optional context tools can enrich the prompt before generation:

- Web search adds current source snippets and URLs.
- Location context adds the user's current place when permission is granted.
- Meeting transcript context adds prior meeting facts for summary and Q&A.

These tools are separate from the Gemma 4 model. The model receives the final
context and answers locally.

In the English UI, Meeting Assistant translation targets Japanese first instead
of translating the summary back into English. The Japanese UI keeps English as
the first translation target.

## Runtime Options Example

```kotlin
val request = EssentialTaskRequest(
    taskType = EssentialTaskType.MULTIMODAL_CHAT,
    prompt = "Explain this photo and answer with a short spoken summary.",
    attachments = listOf(photoAttachment),
    runtimeOptions = EssentialRuntimeOptions(
        preferredModelId = "gemma-4-e4b-litertlm-it",
        webSearchEnabled = false,
        locationEnabled = false,
        sharedMemoryReadEnabled = true,
        sharedMemoryWriteEnabled = true,
        spokenOutputEnabled = true,
    ),
    maxTokens = 512,
)
```

## Build And Test Commands

Run these checks from the repository root:

```bash
cd apps/essential_flutter
flutter analyze
flutter test
flutter build apk --debug
flutter test integration_test/audio_stt_smoke_test.dart -d emulator-5554 --no-dds
flutter test integration_test/web_audio_tools_test.dart -d emulator-5554 --no-dds
```

Run SDK checks:

```bash
cd packages/essential_sdk_dart
dart analyze
dart test
```

Run Android SDK checks:

```bash
cd packages/essential_android_sdk
./gradlew test
```

Run server bundle checks:

```bash
PYTHONPATH=server/common:server/registry_api \
  .venv-server/bin/python -m unittest server.tests.test_bundle_seed_integrity
```

## Submission Limits

State these limits clearly in the demo and writeup:

- SpeechRecognizer is for live voice input. Imported meeting MP3/WAV files use
  the local Whisper transcription path.
- Speech output uses Android TTS in the normal build, so no separate TTS model
  download is required.
- Web search needs network access.
- Location context needs permission.
