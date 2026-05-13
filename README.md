# Essential

Essential is an Android-first multimodal assistant built for the Gemma 4 Good Hackathon. It runs model-powered chat, voice, meeting, image, web, and location-aware workflows from one mobile app.

## Features

- On-device chat through Gemma LiteRT-LM model bundles
- Voice recording, speech playback, and live voice interaction
- Meeting assistant with transcription, summaries, action items, mind maps, and translation
- Image and camera input for multimodal questions
- Optional web grounding for current information
- Optional location context for local questions
- External Android and Dart SDKs for app-to-app integration

## Repository Structure

```text
android/                  Android application and native bridge
assets/                   App language files
lib/                      Flutter application source
native/                   Native inference, audio, vision, llama.cpp, and whisper.cpp runtime source
packages/essential_android_sdk/  Android SDK and buildable Pixel Feature Chat app
packages/essential_sdk_dart/  Dart SDK used by the app and external integrations
third_party/              Vulkan and SPIR-V headers required by the Android native build
```

## Model Files

Large model files are not stored in this repository. Essential downloads Gemma LiteRT-LM model bundles from Hugging Face through the app's model management flow, then stores them on the device for offline generation.

## Development

Requirements:

- Flutter 3.35 or newer
- Android Studio with Android SDK and NDK 28
- JDK 21. This public package pins Gradle to Homebrew JDK 21 at `/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home` because JDK 25 currently breaks Android Gradle sync on this project.
- A physical Android device with arm64-v8a support

Run the app:

```bash
flutter pub get
flutter run
```

Build an Android APK:

```bash
flutter build apk --release
```

Open in Android Studio:

- Open the repository root for the Flutter app, or open `android/` for the Android project view.
- The `android/app` folder is required. It contains the Android manifest, bound service, AIDL, Kotlin service code, native bridge, and launcher resources.
- `android/.gradle`, `android/local.properties`, build outputs, and keystores are local/generated files and are intentionally not committed.

Pixel Feature Chat:

```bash
cd packages/essential_android_sdk
./gradlew :pixel_chat_app:installDebug
```

For a release Pixel Chat APK to connect to the release Essential APK, both APKs must be signed with the same certificate because the Essential bound service uses a signature-protected permission. Verify before release:

```bash
./scripts/verify_android_release_signatures.sh \
  /path/to/essential.apk \
  packages/essential_android_sdk/pixel_chat_app/build/outputs/apk/release/pixel_chat_app-release.apk
```

## Developer API

Essential exposes a Dart SDK for apps that want to call the local model runtime, stream generated text, attach adapters, or check installed model state.

- SDK package: `packages/essential_sdk_dart`
- Android SDK and Pixel Feature Chat: `packages/essential_android_sdk`
- API guide: `docs/developer_api.md`

## Privacy

Essential is designed to keep local model execution and user files on the device whenever offline models are used. Network access is used only for features that need it, such as optional web grounding or model download.
