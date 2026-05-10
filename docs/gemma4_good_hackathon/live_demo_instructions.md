# Live Demo Instructions

Use this file as the public live-demo README or release note.

## What This Demo Shows

Essential is an Android prototype for private, local-first Gemma 4 workflows.
The demo should show that it is both:

- a user app for chat, voice, photos, and meetings,
- and a local AI API that another Android app can call.

## Recommended 3-Minute Demo Path

1. Open Essential Chat.
2. Ask a normal chat question.
3. Ask a current-location weather question to show web and location context.
4. Mention shared memory as the way Essential can keep consistent answers across
   longer use.
5. Open Essential Live and speak to the AI.
6. Open Meeting Assistant and show transcript, summary, TODO, sentiment, mind
   map, translations, and follow-up Q&A.
7. Open the separate Pixel AI Chat demo app.
8. Send a Pixel feature question from that app.
9. Explain that the Pixel demo app is using Essential as an on-device AI API.

## Demo Prompts

Chat:

```text
What can you help me do today?
```

Web and location:

```text
What is the weather around my current location right now?
```

Essential Live:

```text
Can you explain Essential in one short sentence?
```

Meeting follow-up:

```text
What are the next steps from this meeting?
```

Pixel API demo:

```text
How do I use Call Screen on a Pixel phone?
```

Optional Pixel image demo:

```text
Explain this Pixel settings screenshot and tell me what to tap next.
```

## What Judges Can Try

- Chat with the local Gemma 4 model.
- Enable web and location context for current questions.
- Try Essential Live voice input if the Android device supports speech
  recognition.
- Review a prepared meeting with transcript, summary, TODO, sentiment,
  translation, mind map, and meeting Q&A.
- Open the Pixel AI Chat demo app and send a request through the Essential SDK.
- Review the SDK/API docs to see how another app can send text, photos, voice
  transcripts, audio references, web/location options, reference documents, and
  speech-output requests.

## API Message To Say Clearly

Essential is not only one app. It can be used like a local AI service by another
Android app. The external app can choose:

- preferred Gemma 4 model,
- text/image/audio inputs,
- web search on or off,
- current location on or off,
- shared memory read on or off,
- shared memory write on or off,
- spoken output on or off.

This is the main innovation to highlight in the video.

## Model Files

Gemma 4 LiteRT-LM model files are large and may not be bundled directly with the
APK. The demo video is the primary proof of the full local generation flow. The
public repository documents where model discovery happens and how local model
files are routed.

For local testing, place model files on an Android test device under:

```text
/data/local/tmp/essential_genai_seed/
```

Expected example names:

```text
gemma-4-E2B-it.litertlm
gemma-4-E4B-it.litertlm
```

## Important Notes

- Real Android hardware is the best target for Gemma 4 LiteRT-LM generation.
- Web grounding requires a network.
- Current-location answers require location permission.
- Web search is not offline. The local Gemma 4 generation path is the on-device
  part.
- Speech recognition availability depends on the Android device image.
- Do not build all app flavors at once on a low-space machine. Build the
  standard flavor for normal video recording.

## Verification Commands

```bash
cd apps/essential_flutter
flutter analyze
flutter test test/meeting_enhancements_test.dart
cd android
./gradlew :app:assembleStandardDebug
```

Pixel API demo:

```bash
cd packages/essential_android_sdk
./gradlew :pixel_chat_app:assembleDebug
adb install -r pixel_chat_app/build/outputs/apk/debug/pixel_chat_app-debug.apk
adb shell monkey -p io.essential.sdk.pixelchat 1
```

Device logs:

```bash
adb devices -l
adb shell ls -lh /data/local/tmp/essential_genai_seed
adb logcat -v time | rg --line-buffered "ESSENTIAL_|EssentialGenAI|EssentialVoice|AndroidRuntime|FATAL"
```
