# Essential SDK Developer Guide

この資料は、外部アプリからEssential本体を端末内AI APIとして使うための開発者向けガイドです。Android SDK、Dart SDK、アプリ内GenAIチャンネル、音声会話、画像/OCR、ストリーミング、モデル選択、実装上の注意点をまとめます。

## 1. Essentialでできること

Essentialは、端末内にあるモデルを外部アプリやFlutter UIから呼び出すオンデバイスAI基盤です。ネットワークAPIのようにタスクを投げますが、推論は原則として端末内で実行されます。

主な機能:

- テキスト生成、チャット、要約、翻訳、コード生成
- ストリーミング生成
- 画像質問、画像説明、OCR的な読み取り
- 音声入力、文字起こし、音声コマンド
- TTSによる読み上げ
- STT + LLM + TTSを組み合わせた疑似音声会話
- 外部AndroidアプリからのBound Service/AIDL連携
- Dart/Flutterアプリ内からのTask Router利用
- モデル要件指定、フォールバック、明示モデルパス指定
- SDKデモアプリからのMacヘルプチャット、植物写真相談

## 2. ランタイム構成

Essentialは複数のランタイムを用途に応じて使い分けます。

| ランタイム | 用途 | 主な形式 |
| --- | --- | --- |
| LiteRT-LM / Google AI Edge | 高速な端末内LLM、Gemma 4、画像/音声入力 | `.litertlm`, `.task` |
| llama.cpp | GGUFモデル、テキスト生成 | `.gguf` |
| ONNX Runtime | 分類、補助的な音声/画像タスク | `.onnx` |
| Android SpeechRecognizer | ライブSTT | Android system API |
| MeloTTS | 読み上げモデルファミリー | Android export bundle |
| TFLite / MediaPipe系 | 物体検出、画像タスク | `.tflite`, `.task` |

現在の高品質チャット/画像/音声入力では、`gemma-4-E2B-it.litertlm`のようなLiteRT-LMモデルを優先します。GGUF版Gemmaは大きく、画像ネイティブ入力もできないため、画像質問や低遅延チャットではLiteRT-LMが推奨です。

## 3. Android SDKの基本

Android SDKは`packages/essential_android_sdk`にあります。

### 3.1 接続

```kotlin
import io.essential.sdk.android.EssentialClient
import io.essential.sdk.android.EssentialServiceConfiguration

val client = EssentialClient.connect(
    context = context,
    configuration = EssentialServiceConfiguration(
        servicePackage = "com.example.essential_flutter",
        serviceClassName = "com.example.essential_flutter.service.EssentialService",
        callerPackage = context.packageName,
    ),
)
```

### 3.2 テキスト生成

```kotlin
import io.essential.sdk.android.EssentialModelRequirement
import io.essential.sdk.android.EssentialTaskRequest
import io.essential.sdk.android.EssentialTaskType

val request = EssentialTaskRequest(
    taskType = EssentialTaskType.TEXT_GENERATION,
    prompt = "MacでPDFを圧縮する方法を一文で教えて",
    modelRequirement = EssentialModelRequirement.anyCompatible(
        capability = "text_generation",
    ),
    maxTokens = 128,
    temperature = 0.3,
)

val result = client.runTask(request)
println(result.text)
```

### 3.3 ストリーミング生成

```kotlin
val request = EssentialTaskRequest(
    taskType = EssentialTaskType.MULTIMODAL_CHAT,
    prompt = "端末内AI APIの利点を3つ教えて",
    maxTokens = 256,
)

client.streamTask(request).collect { chunk ->
    renderPartialText(chunk.accumulatedText)
}
```

チャットUIでは`streamTask`を使うと、通常のAIアプリのように生成途中の文字を表示できます。最終結果だけでよいバッチ処理では`runTask`を使います。

## 4. モデル要件指定

`EssentialModelRequirement`で、使いたいモデルや能力を指定できます。

```kotlin
EssentialModelRequirement.anyCompatible(
    family = "gemma",
    capability = "multimodal_chat",
    minContextWindow = 2048,
    maxLatencyMs = 4000,
)
```

固定モデル:

```kotlin
EssentialModelRequirement.fixed(
    modelId = "local-genai:gemma-4-E2B-it.litertlm",
    capability = "multimodal_chat",
)
```

明示パス:

```kotlin
EssentialModelRequirement.explicit(
    modelPath = "/data/user/0/com.example.essential_flutter/files/genai_models/gemma-4-E2B-it.litertlm",
    modelId = "gemma-4-e2b-litertlm",
    capability = "multimodal_chat",
)
```

実運用では、明示パスより`anyCompatible`または`fixed`が推奨です。明示パスは検証、社内配布、ベンチマーク向けです。

## 5. 画像/OCR/マルチモーダル

画像を外部アプリから送る場合は、`EssentialMediaAttachment`を使います。

```kotlin
import io.essential.sdk.android.EssentialMediaAttachment
import io.essential.sdk.android.EssentialMediaKind

val image = EssentialMediaAttachment(
    kind = EssentialMediaKind.IMAGE,
    filePath = imageFile.absolutePath,
    mimeType = "image/jpeg",
)

val request = EssentialTaskRequest(
    taskType = EssentialTaskType.MULTIMODAL_CHAT,
    prompt = "この本の名前と作者を教えて。OCRできる文字は根拠として示して。",
    attachments = listOf(image),
    modelRequirement = EssentialModelRequirement.anyCompatible(
        capability = "multimodal_chat",
    ),
    maxTokens = 512,
    temperature = 0.25,
)

val result = client.runTask(request)
```

OCR用途では、プロンプトに「画像内の文字を正確に読み取る」「不確かな文字は不確かと明記する」と入れると安定します。Gemma 4 LiteRT-LMは画像入力をネイティブに扱えるため、従来の軽量物体検出より本の表紙・文書・画面UIの質問に向いています。

## 6. 音声入力と疑似Live会話

疑似Live会話は、以下のパイプラインです。

1. Android端末内の`SpeechRecognizer`でユーザー音声を文字化
2. LiteRT-LMへテキスト生成リクエスト
3. 生成途中のトークンを画面へストリーミング表示
4. MeloTTSモデルファミリーで回答を読み上げる。MeloTTSアセット未導入時のみAndroid TTSへフォールバックする
5. 継続モードなら再度STTへ戻る

Android外部アプリの概念コード:

```kotlin
suspend fun voiceLoop(client: EssentialClient, speech: SpeechRecognizerFacade, tts: TextToSpeech) {
    val sessionId = "voice-${System.currentTimeMillis()}"
    while (isActive) {
        val userText = speech.recognizeOnce()
        if (userText.isBlank()) continue

        val request = EssentialTaskRequest(
            sessionId = sessionId,
            taskType = EssentialTaskType.VOICE_CONVERSATION,
            prompt = userText,
            modelRequirement = EssentialModelRequirement.anyCompatible(
                capability = "multimodal_chat",
                maxLatencyMs = 4000,
            ),
            maxTokens = 192,
            topK = 1,
            topP = 0.85,
            temperature = 0.25,
            metadata = mapOf("mode" to "pseudo_live"),
        )

        val builder = StringBuilder()
        client.streamTask(request).collect { chunk ->
            builder.append(chunk.delta)
            renderTranscript(userText, builder.toString())
        }
        tts.speak(builder.toString(), TextToSpeech.QUEUE_FLUSH, null, "essential-live")
    }
}
```

本体アプリ側では、`Essential Live`画面がこの疑似Live動作を提供します。会議アシスタントでは、録音済みMP3/WAVを取り込んだ場合に端末内Whisperで文字起こしし、そのtranscriptをLiteRT-LMの要約・翻訳・TODO生成へ渡します。完全な双方向音声ストリーミングではありませんが、Gemini Live風に「発話、応答表示、読み上げ、再待機」を連続実行します。

## 7. Dart SDK

Dart SDKは`packages/essential_sdk_dart`にあります。Flutterアプリ内のローカルランタイムやTask Routerを直接使う用途に向いています。

### 7.1 Task Routerでテキスト生成

```dart
final facade = EssentialTaskRouterFacade(
  capabilityRegistry: EssentialCapabilityRegistry.defaultRegistry(),
  router: const EssentialTaskRouter(),
  runtimes: <EssentialRuntimeFamily, EssentialRuntime>{
    EssentialRuntimeFamily.llamaCpp: llamaRuntime,
  },
);

final response = await facade.runTask(
  EssentialTaskRequest(
    taskType: EssentialTaskType.textGeneration,
    payload: const EssentialTextTaskPayload(
      prompt: '端末内AIの利点を一文で説明して',
      maxTokens: 128,
      temperature: 0.3,
    ),
  ),
);

print(response.result.text);
```

### 7.2 GenAI MethodChannelでLiteRT-LM

Flutterアプリ内では`EssentialGenAiRuntime`でLiteRT-LMへ直接アクセスできます。

```dart
final runtime = EssentialGenAiRuntime();
final models = await runtime.discoverModels();
final model = models.firstWhere((m) => m.path.endsWith('.litertlm'));

var visible = '';
final result = await runtime.generate(
  requestId: 'chat-${DateTime.now().microsecondsSinceEpoch}',
  modelPath: model.path,
  prompt: '自然な日本語で短く答えて: こんにちは',
  maxTokens: 128,
  topK: 1,
  topP: 0.85,
  temperature: 0.25,
  onToken: (token) {
    visible += token;
    render(visible);
  },
);

print(result.text);
```

`onToken`を使うと、生成完了を待たずにUIへ逐次表示できます。

## 8. タスクタイプ一覧

Android SDK:

| TaskType | 用途 |
| --- | --- |
| `TEXT_GENERATION` | 通常のテキスト生成 |
| `MULTIMODAL_CHAT` | テキスト、画像、音声を含むチャット |
| `IMAGE_CAPTION` | 画像説明 |
| `PLANT_IDENTIFICATION` | 植物写真相談デモ |
| `STT` | 音声文字起こし |
| `TTS` | 読み上げ |
| `VOICE_CONVERSATION` | STT + LLM + TTSの会話用途 |

Dart SDK:

| TaskType | 用途 |
| --- | --- |
| `textGeneration` | テキスト生成 |
| `imageClassification` | 画像分類 |
| `objectDetection` | 物体検出 |
| `ocr` | OCR |
| `imageCaption` | 画像説明 |
| `multimodalChat` | 画像/音声付きチャット |
| `stt` | 音声文字起こし |
| `tts` | 読み上げ |
| `voiceCommand` | 音声コマンド |
| `locationContext` | 位置情報文脈 |
| `mapReasoning` | 地図/位置推論 |

## 9. 実用パターン

### 9.1 チャットアプリ

- `sessionId`を固定し、会話単位で渡す
- `streamTask`または`onToken`で逐次表示
- 短文では`maxTokens=128〜256`
- 詳細説明では`maxTokens=512〜1024`
- `temperature=0.2〜0.4`で安定

### 9.2 写真質問アプリ

- 画像はJPEG/PNGのファイルパスで渡す
- 長辺を端末側で適度に縮小すると初回速度が安定
- OCRでは「不確かな文字は不確かと明記」と指示する
- 本、看板、レシート、UI画面などはLiteRT-LM/Gemma visionを使う

### 9.3 音声アシスタント

- STT結果を必ず画面に出して確認可能にする
- AI返答は短くする
- TTS中は再録音を一時停止する
- 割り込み停止ボタンを用意する
- バッテリー節約のため長文回答を避ける

### 9.4 外部アプリの業務利用

- ユーザー入力や添付ファイルをEssentialへ渡す
- 返答テキスト、使用モデル、メタデータを保存
- 個人情報をクラウドへ送らない設計を説明できる
- モデル未導入時の案内UIを用意する

## 10. エラー処理

代表的なエラー:

| エラー | 対応 |
| --- | --- |
| `MODEL_NOT_INSTALLED` | AI追加画面でモデルを導入する |
| `MODEL_INCOMPATIBLE` | 画像/音声対応モデルへ切り替える |
| `ADAPTER_INCOMPATIBLE` | Adapterを外す、または対応ベースモデルへ変更 |
| `DEVICE_CAPACITY_INSUFFICIENT` | 軽量モデルへフォールバック |
| `PERMISSION_DENIED` | マイク/ファイル権限を要求 |
| `REQUEST_TIMED_OUT` | maxTokensを下げる、画像サイズを下げる |
| `RUNTIME_UNAVAILABLE` | 本体アプリ/サービス起動、モデル配置を確認 |

## 11. 推奨パラメータ

| 用途 | maxTokens | topK | topP | temperature |
| --- | ---: | ---: | ---: | ---: |
| 挨拶/短い質問 | 64〜128 | 1 | 0.85 | 0.2〜0.3 |
| 通常チャット | 256〜512 | 1〜16 | 0.85〜0.95 | 0.25〜0.6 |
| 画像質問/OCR | 256〜512 | 1 | 0.85 | 0.2〜0.3 |
| 詳細説明 | 768〜2048 | 16〜64 | 0.9〜0.95 | 0.5〜0.8 |
| 長文生成 | 2048以上 | 16〜64 | 0.9〜0.95 | 0.6〜0.9 |

空の箇条書きや同じ文の繰り返しが出る場合は、`topK`と`temperature`を下げます。短い音声会話では`topK=1`、`temperature=0.25`が安定します。

## 12. パフォーマンス注意点

- `.litertlm`は初回にGPU/OpenCLコンパイルが入り、初回だけ遅くなります。
- 2回目以降はキャッシュが効きます。
- 画像入力はvision executor初期化があるため、初回はテキストより重いです。
- 40,000トークンのような大きい設定は通常チャットのデフォルトにしないでください。
- 短いUI会話では小さい`maxTokens`を使う方が体感速度が大きく改善します。
- 複数の重いエンジンを同時キャッシュするとGPUメモリを圧迫します。

## 13. セキュリティとプライバシー

- 推論は原則端末内で実行されます。
- 外部アプリはEssential本体のBound Serviceへ接続します。
- マイク、ファイル、写真の権限は呼び出し元アプリ側でも適切に扱ってください。
- モデルファイルのパスをログに残す場合、ユーザー固有パスが含まれる点に注意してください。
- 画像や音声をクラウドへ送らないことをUIで明示できます。

## 14. 既存サンプル

- `packages/essential_android_sdk/samples/QuickStart.kt`
- `packages/essential_android_sdk/samples/MacHelpChatDemo.kt`
- `packages/essential_android_sdk/samples/PlantIdentificationDemo.kt`
- `packages/essential_android_sdk/demo_app`
- `packages/essential_android_sdk/mac_chat_app`
- `packages/essential_android_sdk/plant_camera_app`
- `packages/essential_sdk_dart/example/quick_start.dart`

## 15. 推奨実装チェックリスト

- LiteRT-LMモデルが導入済みか確認する
- 画像/音声タスクではマルチモーダル対応モデルを要求する
- 短文では小さい`maxTokens`を使う
- ストリーミングUIでは`streamTask`または`onToken`を使う
- 音声会話ではSTT結果とAI回答を画面に表示する
- TTS中の停止ボタンを用意する
- モデル未導入、権限なし、タイムアウトを明示的に案内する
- 実機で初回と2回目以降を分けてベンチマークする
