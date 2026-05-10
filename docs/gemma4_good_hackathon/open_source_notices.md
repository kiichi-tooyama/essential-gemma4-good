# Open Source and Model Notices

This summary is for the Kaggle writeup, public repository, and media package.
Before final submission, verify exact versions from the lockfiles and Gradle
metadata in the release folder.

## Core Frameworks

- Flutter and Dart SDK: main cross-platform application framework.
- Android SDK, Android Gradle Plugin, Kotlin, and Kotlin coroutines: native
  Android app, services, and SDK demo apps.
- AndroidX libraries, including test, startup, core, camera, and FileProvider
  related components used by the demo apps.

## On-Device AI and Media

- Google AI Edge LiteRT-LM / LiteRT Android: Gemma 4 LiteRT-LM execution path.
- Gemma 4 model files: governed by Google Gemma terms and model license terms.
- whisper.cpp: local meeting audio transcription support.
- MeloTTS export/runtime assets: speech-output model family used for native TTS
  playback where available.
- Android SpeechRecognizer and Android TextToSpeech: platform speech input and
  fallback speech output.
- llama.cpp: included native runtime dependency where present in the repository.

## Flutter Packages Used by Essential

Representative packages include `camera`, `file_picker`, `flutter_map`,
`geolocator`, `image_picker`, `just_audio`, `latlong2`, `path`,
`path_provider`, `record`, `url_launcher`, and `webview_flutter`.

## Native Graphics and Runtime Dependencies

- Vulkan-Hpp and Vulkan headers.
- SPIR-V Headers.
- Android NDK and CMake build tooling for native runtime bridges.

## Release Rule

The public project license applies only to original Essential code and docs.
Bundled third-party code, open-source libraries, and model files keep their own
licenses and terms. Do not present the custom Essential usage restriction as a
replacement for Gemma or open-source license obligations.
