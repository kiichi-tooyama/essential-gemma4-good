# Demo Test Script

Run this before recording the 3-minute video. The goal is to make the phone demo
smooth, not to show every feature.

## 1. Build And Install

Use the standard app flavor for live recording. Do not build all flavors at once
on a low-space machine, because the bundled E4B flavor is very large.

```bash
cd apps/essential_flutter
flutter analyze
flutter test test/meeting_enhancements_test.dart
cd android
./gradlew :app:assembleStandardDebug
adb install -r app/build/outputs/apk/standard/debug/app-standard-debug.apk
```

Build and install the Pixel API demo app:

```bash
cd packages/essential_android_sdk
./gradlew :pixel_chat_app:assembleDebug
adb install -r pixel_chat_app/build/outputs/apk/debug/pixel_chat_app-debug.apk
```

Device checks:

```bash
adb devices -l
adb shell dumpsys package com.example.essential_flutter | rg "versionName|versionCode|lastUpdateTime"
adb shell dumpsys package io.essential.sdk.pixelchat | rg "versionName|versionCode|lastUpdateTime"
```

## 2. Prepare The Phone State

- Essential is installed and can open.
- Pixel AI Chat demo is installed and can open.
- A Gemma 4 LiteRT-LM model is available in Essential.
- Web search is enabled for the chat demo.
- Location permission is granted if you want to ask weather near current
  location.
- Shared memory is enabled in Essential for the chat portion.
- Shared memory is disabled in the Pixel demo request, to show API-level
  control.
- A prepared meeting exists, or use:

```text
docs/gemma4_good_hackathon/demo_assets/english_meeting_demo_2min.wav
```

## 3. Recording Order

### A. Normal Chat

Prompt:

```text
What can you help me do today?
```

Check:

- The answer appears.
- The screen looks like a normal chat app.

### B. Web Search And Location

Prompt:

```text
What is the weather around my current location right now?
```

Check:

- If web/location works, the answer uses current context.
- If it does not work, do not retry many times during recording. Say it falls
  back to local generation.

### C. Essential Live

Speak:

```text
Can you explain Essential in one short sentence?
```

Optional interruption:

```text
Make it even shorter.
```

Check:

- Speech recognition returns text.
- The model starts answering.
- TTS starts.
- Interruption is only shown if stable.

Log if needed:

```bash
adb logcat -c
adb logcat -v time | rg --line-buffered "live_stt|speech recognition|tts|EssentialVoice|AndroidRuntime|ANR"
```

### D. Meeting Assistant

Open a meeting detail screen and show:

- Transcript
- Summary
- TODO
- Sentiment
- Mind Map
- Translation
- Ask AI

Ask:

```text
What are the next steps from this meeting?
```

Check:

- TODO is not duplicated inside Summary.
- Mind Map shows readable node cards, not only lines.
- Chinese translation is real Chinese text, not Japanese or an error sentence.

### E. Pixel API Demo

Open Pixel AI Chat and send:

```text
How do I use Call Screen on a Pixel phone?
```

Optional image prompt:

```text
Explain this Pixel settings screenshot and tell me what to tap next.
```

Check:

- The external app opens separately from Essential.
- It calls the Essential service.
- The answer appears in the Pixel demo app.
- The request is configured with web/location enabled and shared memory read and
  write disabled.

## 4. Short Voiceover Checklist

Say these points clearly:

- Essential looks like chat, but Gemma 4 runs on the phone.
- Web search and location add real-time context.
- Shared memory keeps answers consistent across longer use.
- Essential Live enables voice conversation.
- Meeting Assistant turns audio into transcript, summary, TODO, sentiment,
  translation, mind map, and follow-up Q&A.
- The Pixel demo proves that other apps can use Essential as an on-device AI API.

## 5. Known Limits For Recording

- Do not show model download time in the 3-minute video.
- Do not claim cloud-free web search. Web search uses the network, but generation
  uses the local Gemma 4 path.
- Live voice uses Android SpeechRecognizer for live speech input.
- Imported meeting audio uses the meeting audio transcription path.
- If disk space is low, remove generated build output before rebuilding:

```bash
rm -rf apps/essential_flutter/build
```
