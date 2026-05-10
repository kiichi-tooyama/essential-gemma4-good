# Track Awards 提出パック

対象: Gemma 4 Good Hackathon の Track Awards

- Cactus: local-first mobile / wearable application that routes tasks between models.
- LiteRT: Google AI Edge LiteRT implementation of Gemma 4.
- llama.cpp: Gemma 4 on resource-constrained hardware.

提出締切: 2026-05-19 08:59 JST。Kaggle 上では未提出ドラフトは審査対象外なので、早めに一度 Submit してから差し替える。

## 1. 一番強い見せ方

Essential の中心メッセージは次の1文に寄せる。

> Essential turns an Android phone into a private Gemma 4 field assistant and local AI API. It routes each task to the best local model path: Gemma 4 LiteRT-LM for mobile reasoning, Android SpeechRecognizer for live voice, Whisper for meeting audio, MeloTTS for speech output, and optional web/location grounding only when the network is available.

この1文で3賞に対応できる。

- Cactus: Android の local-first アプリで、チャット、Live、会議、外部SDK/APIをタスク別にルーティングする。
- LiteRT: Gemma 4 LiteRT-LM を Google AI Edge のモバイル実装として使う。
- llama.cpp: 低リソース端末向けの native runtime / SDK 実験系として llama.cpp パスを持つ。ただし審査で強く主張するなら、動画かリポジトリ内で Gemma 4 GGUF 実行証拠を追加する。

## 2. Kaggle に入れるもの

### Kaggle Writeup

使う本文: `kaggle_writeup_track_awards.md`

Kaggle の Writeup は 1,500 words 以下。本文は英語で出す。日本語説明は提出しない。

Track 選択は、フォームで1つしか選べない場合は LiteRT を選ぶ。理由は現在のデモで最も実装証拠が強いから。本文内で Cactus と llama.cpp の Track Award 適合性も明記する。

### YouTube Video

使う台本: `video_script_track_awards_3min_jp.md`

動画は3分以内。公開または限定公開で、ログインなしで見られる状態にする。動画タイトルは次を推奨。

> Essential Field Companion - Private Gemma 4 LiteRT-LM on Android

### Public Code Repository

使うチェックリスト: `public_repo_release_checklist_jp.md`

GitHub 公開前に、秘密情報、内部エージェント資料、大きすぎる生成物、個人情報、不要なスクリーンショットを外す。Kaggle の Project Links に GitHub URL を添付する。

### Live Demo

使う説明: `live_demo_instructions.md`

一番安全なのは APK / GitHub Releases / デモ動画 / README を組み合わせる方法。審査員がすぐ試せるように、モデルファイルが大きい場合は「動画で動作証拠、READMEでモデル準備手順、APKでUI確認」の形にする。

### Media Gallery

最低限必要:

- Cover image 1枚。
- YouTube video。
- 可能ならスクリーンショット 4枚: model routing, chat/web sources, Essential Live, meeting assistant.

Cover image の作成指示は `media_gallery_assets_jp.md` にある。

## 3. 自分で準備するもの

### 必須

1. Kaggle Writeup を新規作成する。
2. `kaggle_writeup_track_awards.md` の本文を貼る。
3. Track を選ぶ。1つだけなら LiteRT。
4. YouTube に3分以内の動画を上げる。
5. GitHub などの public repo URL を Project Links に入れる。
6. Live Demo URL または APK/README を Project Links / Files に入れる。
7. Cover image を Media Gallery に入れる。
8. 右上の Submit を押す。

### できれば追加

- 実機 Pixel で Gemma 4 LiteRT-LM 生成が動く画面を撮る。
- `adb logcat` の `ESSENTIAL_GENAI_RESULT` または相当ログを保存する。
- llama.cpp 賞を本気で狙うなら、Gemma 4 GGUF を llama.cpp runtime で1回生成し、短いベンチ結果をリポジトリか Writeup 末尾に入れる。

## 4. 正直に書くべき現在の検証状態

2026-05-07 時点の Android Studio エミュレーター検証:

- `flutter analyze`: pass。
- `flutter test`: pass。
- `./gradlew :app:assembleDebug`: pass。
- `web_audio_tools_test.dart`: pass。Web 検索でライブソース6件。
- `audio_stt_smoke_test.dart`: pass。Android SpeechRecognizer available、MeloTTS native audio available。
- `offline_mode_test.dart`: pass。テスト側で connectivity を明示的に offline mock するよう修正。
- `genai_litertlm_smoke_test.dart`: E2B/E4B の discovery と E2B warmup までは pass。Android emulator の `liblitertlm_jni.so` が SIGILL で落ちたため、最終生成証拠は実機で撮るのが安全。

この状態を隠さない。Writeup では「real device demo is the authoritative proof for LiteRT-LM generation」と書き、エミュレーターは Web/STT/TTS/オフライン/ビルド検証用として扱う。

## 5. 最終提出前チェック

- Writeup が 1,500 words 以下。
- 動画が 3分以内。
- YouTube がログイン不要。
- GitHub が public。
- Live Demo がログイン不要、またはファイル添付。
- Cover image がある。
- Submit 済み。
- 2026-05-19 08:59 JST より前に再確認。
