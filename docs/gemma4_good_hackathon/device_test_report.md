# Device Test Report

Date: 2026-05-07

Targets:

- Android Studio emulator `emulator-5554`: `sdk_gphone64_arm64`, Android 16 API 36, 1080x2400.
- Test AVD `emulator-5556`: `Essential_Test_API_36`, Android 16 API 36, 9 GB data partition for large model seed checks.

## Checks

| Check | Result | Notes |
| --- | --- | --- |
| Flutter analyze | Pass | `flutter analyze` from `apps/essential_flutter`. |
| Flutter unit/widget tests | Pass | `flutter test` from `apps/essential_flutter`: 8 tests passed. |
| Debug APK build | Pass | `./gradlew :app:assembleDebug` from `apps/essential_flutter/android`. |
| Android SpeechRecognizer bridge | Pass | `flutter test integration_test/audio_stt_smoke_test.dart -d emulator-5554`. |
| Android TTS bridge | Pass | Live and API speech output use Android TTS in the normal build; no MeloTTS/Piper model is required for setup. |
| Web research integration | Pass | `web_audio_tools_test.dart` returned six live sources. MP3 normalization skipped on `emulator-5554` because `/data/local/tmp/essential-meeting-test.mp3` was not present. |
| Offline web/location gate | Pass | `offline_mode_test.dart` now mocks `essential/connectivity.isOnline=false`; result returned zero sources and removed location context. |
| LiteRT-LM model discovery | Partial pass | On `emulator-5556`, E2B and E4B files were discovered from `/data/local/tmp/essential_genai_seed`. E2B warmup completed. |
| LiteRT-LM generation on emulator | Blocked by emulator native runtime | `liblitertlm_jni.so` crashed with SIGILL in Android emulator during generation. Use real Android hardware as the authoritative demo target for local Gemma 4 generation. |
| Dart SDK analyze/test | Pass | `dart analyze` and `dart test` from `packages/essential_sdk_dart`. |
| Android SDK unit tests | Pass | `./gradlew test` from `packages/essential_android_sdk`. |
| Model setup integrity | Pass | Normal setup requires only Gemma 4 LiteRT-LM for chat and Whisper for imported meeting transcription. |
| Emulator launch | Pass | Reinstalled debug APK, launched `com.example.essential_flutter`, and checked logcat for fatal errors outside the known LiteRT-LM emulator SIGILL. |

## Expected Demo Evidence

- Gemma 4 LiteRT-LM is visible as the main chat model.
- Live voice reports Android `SpeechRecognizer` as the input engine.
- TTS metadata reports Android TTS as the speech-output engine.
- External SDK calls can represent text, image, transcript, and TTS tasks.
- Web search returns live source URLs when network is available.
- Location-aware generation uses current location when permission is granted.

## Emulator Evidence

- Device: `sdk_gphone64_arm64`, Android API 36.
- SpeechRecognizer state: `engine=android_speech_recognizer`,
  `available=true`, `onDeviceAvailable=true`,
  `microphonePermissionGranted=false` before runtime permission prompt.
- Web evidence: the test returned six live sources, with the first source title
  `Google ニュース - 政治 - 最新`.
- Offline evidence: `[WebSearch] skipped: device is offline` and
  `sources=0 locationContext=""`.
- LiteRT-LM seed evidence: `gemma-4-E2B-it.litertlm` and
  `gemma-4-E4B-it.litertlm` were present on `emulator-5556`.
- Limitation evidence: Android emulator crash log showed SIGILL in
  `liblitertlm_jni.so` during local generation. This should be described as an
  emulator/native-runtime limitation, not as the final real-device proof.
