# Essential Quick Actions and Shared Memory Developer Guide

Last updated: 2026-04-30

## Scope

This document describes the chat quick action, Android share intake, shared memory, generated-text sharing, and long audio memo features in the Essential Flutter app.

The implementation is centered on:

- `apps/essential_flutter/lib/features/chat/chat_input_bar.dart`
- `apps/essential_flutter/lib/features/chat/chat_screen.dart`
- `apps/essential_flutter/lib/features/chat/chat_controller.dart`
- `apps/essential_flutter/lib/features/chat/chat_message_bubble.dart`
- `apps/essential_flutter/android/app/src/main/AndroidManifest.xml`
- `apps/essential_flutter/android/app/src/main/kotlin/com/example/essential_flutter/MainActivity.kt`

## Feature Summary

### Quick Actions

Quick actions are context-sensitive chips shown above the chat input field. They are derived from the current composer text and allow one-tap generation workflows.

Current actions:

- `要約`: shown for long or multiline content.
- `返信作成`: shown for mail-like or reply-like content.
- `Web検索`: shown for URLs, product names, reviews, price-related text, or shopping-related content.
- `レビュー相談`: shown for product/review/purchase-related content.
- `文章作成`: always available when text is present as a general writing action.

Each chip builds a complete prompt and calls `ChatScreen._runQuickAction()`, which replaces the composer contents with that prompt and starts generation through the normal chat path. This means quick actions inherit:

- selected model routing,
- Web search augmentation,
- streaming output,
- shared memory injection,
- TTS sharing behavior,
- model health guards.

### Android Share Intake

Essential can receive shared text from other Android apps through `ACTION_SEND` with `text/plain`.

Manifest entry:

```xml
<intent-filter>
    <action android:name="android.intent.action.SEND" />
    <category android:name="android.intent.category.DEFAULT" />
    <data android:mimeType="text/plain" />
</intent-filter>
```

Native channel:

- Channel: `essential/shared_intent`
- Method from Flutter to Android: `getInitialText`
- Method from Android to Flutter: `sharedText`

`MainActivity` extracts:

- `Intent.EXTRA_TEXT`
- fallback: `Intent.EXTRA_SUBJECT`

Flutter then appends the shared text to the composer. If the shared payload contains a URL or product/review wording, quick action chips appear immediately.

### Generated Text Sharing

Assistant messages show a share button after generation completes.

Native channel:

- Channel: `essential/share`
- Method: `sendText`
- Arguments:
  - `text`: generated text
  - `title`: chooser title

The Android implementation uses:

```kotlin
Intent(Intent.ACTION_SEND).apply {
    type = "text/plain"
    putExtra(Intent.EXTRA_TEXT, text)
}
```

It opens `Intent.createChooser`, so LINE, SMS, Gmail, and other apps keep their native recipient selection and send confirmation UI. Essential does not directly send messages on behalf of the user.

### Shared Memory

Shared memory is a cross-chat list of user preferences or facts that can be injected into prompts. It is globally stored, but each chat session can independently enable or disable it.

UI:

- Opened by the memory icon in the chat app bar.
- Allows adding and deleting memory items.
- Includes a per-chat switch: `このチャットで共有メモリーを使う`.

Storage file:

- Application support directory
- `essential_chat_sessions.json`

Persisted keys:

```json
{
  "current_session_id": "...",
  "sessions": [
    {
      "id": "...",
      "title": "...",
      "updated_at": "...",
      "selected_model_id": "...",
      "shared_memory_enabled": true,
      "messages": []
    }
  ],
  "shared_memories": [
    {
      "id": "...",
      "text": "返信は短く丁寧にしてほしい",
      "created_at": "..."
    }
  ]
}
```

Prompt injection:

- `ChatController.buildPrompt()` injects memory for llama/GGUF chat prompts.
- `ChatScreen._buildGenAiPrompt()` injects memory for LiteRT-LM / GenAI prompts.
- Memory is injected only when the current session has `sharedMemoryEnabled == true`.
- The model is instructed not to reveal the memory section directly.

Limits:

- Up to 80 memory items are persisted.
- Prompt injection uses the newest 12 items for compact/Gemma prompts.
- Prompt injection uses the newest 16 items for normal and GenAI prompts.

### Long Audio Memo

The media sheet includes `会議/通話メモ`.

Flow:

1. User records audio with the existing `VoiceRecordingScreen`.
2. The recording is attached as a chat audio attachment.
3. The composer is filled with a structured prompt:
   - transcription,
   - summary,
   - decisions,
   - TODO,
   - important statements,
   - translation when needed,
   - reply draft when needed.
4. The user sends it through the standard multimodal generation path.

This is intentionally implemented as user-initiated recording plus AI processing. Android call recording, background capture, and notification/Gmail/SMS data access are platform- and policy-sensitive and require separate explicit permission surfaces.

## Platform Access Notes

### Google Calendar

Technically possible through either:

- Android Calendar Provider, with calendar permissions and local calendar availability.
- Google Calendar API via OAuth.

For production use, OAuth is safer and clearer because the user sees account-level consent.

### Gmail

Gmail message access is not available through a normal Android runtime permission. Use Gmail API with OAuth scopes. Scope selection should be minimal, for example read-only metadata/content for AI summarization, and compose/send only if the product explicitly needs it.

### Notifications

Notification content can be accessed through a Notification Listener Service after the user enables it in Android settings. This should be opt-in and clearly explain that notification text may include private content.

### SMS

Reading SMS requires sensitive permissions and may be restricted by Play policy. Sending should generally use Android intents or the user-selected SMS app rather than silent direct sending. The current implementation uses a share sheet for safer recipient selection.

### Calls and Meetings

Direct phone call recording is restricted by Android version, region, OEM behavior, and app policy. The current implementation supports user-initiated recording for meetings or notes. If true call recording is required later, it should be implemented behind explicit consent and device capability checks.

## Test Results

Commands run on 2026-04-30:

| Area | Command | Result |
| --- | --- | --- |
| Flutter app analysis | `flutter analyze` in `apps/essential_flutter` | Passed |
| Flutter app tests | `flutter test` in `apps/essential_flutter` | Passed, 1 test |
| Flutter debug APK | `flutter build apk --debug` | Passed |
| Android app Kotlin | `./gradlew :app:compileDebugKotlin` | Passed |
| Dart SDK analysis | `dart pub get && dart analyze` in `packages/essential_sdk_dart` | Passed |
| Dart SDK tests | `dart test` in `packages/essential_sdk_dart` | Passed, 6 tests |
| Protocol package analysis | `dart pub get && dart analyze` in `packages/essential_protocol` | Passed |
| Protocol package tests | `dart test` in `packages/essential_protocol` | Not run: package has no `test` dev dependency |
| UI kit analysis | `dart pub get && dart analyze` in `packages/essential_ui_kit` | Passed |
| UI kit tests | `dart test` in `packages/essential_ui_kit` | Not run: package has no `test` dev dependency |
| Python SDK tests | `python3 -m pytest -q` in `packages/essential_sdk_python` | Passed, 1 test |
| Android SDK build/tests | `./gradlew testDebugUnitTest assembleDebug` in `packages/essential_android_sdk` | Passed; unit test tasks are `NO-SOURCE`, debug AAR and sample APKs built |
| Device install | `adb install -r app-debug.apk` | Passed |
| Android share intake smoke | `adb shell am start -n com.example.essential_flutter/.MainActivity -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT ...` | Passed |
| Quick action UI smoke | Screenshot after share intake | Passed: `Web検索`, `レビュー相談`, `文章作成` chips visible |

## Manual QA Checklist

Use this checklist before a release build:

1. Share a URL from Chrome into Essential.
2. Confirm the text appears in the chat composer.
3. Confirm `Web検索` appears.
4. Tap `Web検索` and confirm generation starts.
5. Share product text from another app.
6. Confirm `レビュー相談` appears.
7. Add a shared memory item such as `返信は短く丁寧にしてほしい`.
8. Generate in a chat with memory enabled.
9. Disable shared memory for the current chat.
10. Generate again and confirm the memory switch remains off for that chat.
11. Generate a reply draft.
12. Tap the assistant message share button.
13. Confirm the Android chooser opens with LINE, SMS, Gmail, or available targets.
14. Open media sheet and select `会議/通話メモ`.
15. Record audio and confirm the meeting-summary prompt and audio attachment are added.

## Implementation Notes

- Quick action detection is intentionally local and deterministic. It does not call the model before showing chips.
- The Web search quick action relies on the existing default-on Web research path in chat generation.
- The share button is visible only for completed non-error assistant messages.
- Shared memory is stored together with chat sessions to keep migration simple.
- Future migrations should version `essential_chat_sessions.json` if the schema grows further.

