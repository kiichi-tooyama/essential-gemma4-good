# Demo Test Script

Run this before recording the 3-minute video. The goal is to make the phone demo
smooth, not to show every feature.

## 1. Build And Install

Use the standard app flavor for live recording. Do not build all flavors at once
on a low-space machine, because the bundled E4B flavor is very large.

```bash
flutter pub get
flutter analyze
cd android
./gradlew :app:installDebug
```

Build and install the Pixel API demo app:

```bash
cd packages/essential_android_sdk
./gradlew :pixel_chat_app:installDebug
```

Release builds must use the same signing certificate for Essential and Pixel Chat
because Essential's service bind permission is `signature` protected. Before
publishing, verify the two release APKs:

```bash
./scripts/verify_android_release_signatures.sh \
  /path/to/app-release.apk \
  packages/essential_android_sdk/pixel_chat_app/build/outputs/apk/release/pixel_chat_app-release.apk
```

Device checks:

```bash
adb devices -l
adb shell dumpsys package com.example.essential_flutter | rg "versionName|versionCode|lastUpdateTime"
adb shell dumpsys package io.essential.sdk.pixelchat | rg "versionName|versionCode|lastUpdateTime"
```

## 2. Prepare The Phone State

- Essential is installed and can open.
- Pixel AI Chat demo is installed and can open. For release testing, install the
  APK signed with the same certificate as Essential.
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
- If the app says the signature does not match, rebuild Pixel Chat with the
  Essential release keystore before recording.
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
