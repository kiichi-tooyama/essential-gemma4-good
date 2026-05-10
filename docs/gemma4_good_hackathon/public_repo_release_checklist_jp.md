# Public Code Repository 準備チェックリスト

Kaggle の public code repository は「本当に実装している証拠」。見た目よりも、審査員が Gemma 4 / LiteRT / task routing の実装箇所を見つけやすいことを優先する。

## 1. 公開前に外すもの

- `.env`、API key、署名鍵、keystore、個人トークン。
- `.agents/`、内部エージェント作業ログ、不要な自動生成メモ。
- `build/`、`.dart_tool/`、`.gradle/`、巨大な model artifact。
- 個人情報が映るスクリーンショット。
- Kaggle 提出に不要な失敗ログや古いレポート。

## 2. 残すべきもの

- `apps/essential_flutter/`
- `packages/essential_sdk_dart/`
- `packages/essential_android_sdk/`
- `native/inference_core/`
- `native/runtimes/audio/`
- `server/common/essential_server/bootstrap.py`
- `scripts/register_server_models.py`
- `docs/gemma4_good_hackathon/`

## 3. README に必ず書くこと

Public repo の README 冒頭に入れる内容:

```md
# Essential Field Companion

Essential is a local-first Android assistant powered by Gemma 4 LiteRT-LM through Google AI Edge. It routes tasks between on-device reasoning, live speech recognition, Whisper meeting transcription, MeloTTS speech output, optional web/location grounding, and SDK-style access from other apps.
```

続けて以下のリンクを書く:

- Kaggle Writeup
- YouTube demo
- APK / Live demo
- Architecture docs: `docs/gemma4_good_hackathon/`

## 4. 審査員向けコード案内

README にこの表を入れる。

| What to verify | Path |
| --- | --- |
| Android app | `apps/essential_flutter/` |
| Gemma 4 LiteRT-LM bridge | `apps/essential_flutter/android/app/src/main/kotlin/com/example/essential_flutter/ai/GalleryLiteRtLmRuntime.kt` |
| Native method channel | `apps/essential_flutter/android/app/src/main/kotlin/com/example/essential_flutter/MainActivity.kt` |
| Chat routing | `apps/essential_flutter/lib/features/chat/` |
| Meeting assistant | `apps/essential_flutter/lib/features/meeting_assistant/` |
| Web grounding | `apps/essential_flutter/lib/features/shared/web_research_service.dart` |
| Dart SDK API | `packages/essential_sdk_dart/` |
| Android SDK API | `packages/essential_android_sdk/` |
| llama.cpp runtime path | `native/inference_core/` |
| Submission docs | `docs/gemma4_good_hackathon/` |

## 5. 公開前コマンド

```bash
cd /Users/toyama_kiichi/Essential/apps/essential_flutter
flutter analyze
flutter test
cd android
./gradlew :app:assembleDebug
```

```bash
cd /Users/toyama_kiichi/Essential
git status --short
rg -n "API_KEY|SECRET|TOKEN|PASSWORD|PRIVATE KEY|BEGIN .*KEY|AIza|sk-" .
```

## 6. GitHub に出すときの注意

- モデル本体は repo に入れない。README で準備手順を書く。
- APK を置くなら GitHub Releases に置く。
- 大きいファイルは Kaggle Files か Releases に分ける。
- public repo URL は Kaggle Writeup の Attachments -> Project Links に入れる。
