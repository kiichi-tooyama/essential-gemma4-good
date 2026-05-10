# Essential

Essential is a local-first Android assistant and on-device AI API powered by
Gemma 4 LiteRT-LM through Google AI Edge.

It is built for the Gemma 4 Good Hackathon. The app shows Gemma 4 running as a
real mobile product layer: chat, voice, screenshot/photo questions, optional web
and location grounding, shared memory, meeting processing, and an SDK that lets
other Android apps call the same local AI features.

## What Is Included

- `apps/essential_flutter`: the main Flutter Android app.
- `packages/essential_android_sdk`: Android SDK and demo apps.
- `packages/essential_android_sdk/samples/PixelFeatureChatDemo.kt`: minimal
  external-app API example used in the video.
- `packages/essential_android_sdk/pixel_chat_app`: separate Pixel Feature Chat
  demo app that calls Essential.
- `docs/gemma4_good_hackathon`: video script, Kaggle writeup, demo checklist,
  and submission notes.
- `native/third_party/whisper.cpp`: local meeting transcription dependency.
- Bundled test models may be included for the hackathon demo package. If model
  files are included, their original model terms still apply.

## Demo Flow

The 3-minute demo focuses on API proof:

1. Show the small external-app code needed to call Essential.
2. Open Pixel Feature Chat, attach a Pixel settings screenshot, ask by voice
   “How do I update from here?”, and receive spoken output.
3. Show Essential Chat with web/location context and shared memory.
4. Show Essential Live voice conversation.
5. Show Meeting Assistant with transcript, summary, TODOs, translation, mind
   map, and follow-up Q&A.

## Build Notes

Main app debug build:

```bash
cd apps/essential_flutter
flutter build apk --debug --flavor standard
```

SDK demo apps:

```bash
cd packages/essential_android_sdk
./gradlew :pixel_chat_app:assembleDebug :demo_app:assembleDebug :plant_camera_app:assembleDebug
```

## Licensing

The original Essential project code, documentation, demos, and project
materials are licensed under CC BY 4.0. See the repository-root `LICENSE` file.

Third-party open-source components and Gemma model files are not relicensed by
this notice. They remain governed by their own licenses and terms.
