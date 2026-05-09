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
packages/essential_sdk_dart/  Dart SDK used by the app and external integrations
third_party/              Vulkan and SPIR-V headers required by the Android native build
```

## Model Files

Large model files are not stored in this repository. Essential downloads Gemma LiteRT-LM model bundles from Hugging Face through the app's model management flow, then stores them on the device for offline generation.

## Development

Requirements:

- Flutter 3.35 or newer
- Android Studio with Android SDK and NDK 28
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

## Developer API

Essential exposes a Dart SDK for apps that want to call the local model runtime, stream generated text, attach adapters, or check installed model state.

- SDK package: `packages/essential_sdk_dart`
- API guide: `docs/developer_api.md`

## Privacy

Essential is designed to keep local model execution and user files on the device whenever offline models are used. Network access is used only for features that need it, such as optional web grounding or model download.

## License

This project is provided for hackathon review and demonstration. Third-party runtime components keep their original licenses in their source directories.
