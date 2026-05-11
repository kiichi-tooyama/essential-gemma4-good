# Essential Android SDK

Essential の Android Bound Service / AIDL 実装を利用するための開発者向け SDK です。`EssentialClient` が非同期 API、ストリーミング、タイムアウト、キャンセル、モデル選択をまとめて提供します。

## 含まれるもの

- `EssentialClient.connect(...)` による Service 接続
- `models.list()` / `models.ensureInstalled(...)`
- `generate(...)` / `generateStream(...)`
- `runTask(...)` / `streamTask(...)` for image, speech, and typed multimodal tasks
- `cancel(requestId)`
- `adapters.list(...)` / `attach(...)` / `detach(...)`
- 統一エラーコード (`EssentialErrorCode`)

## 導入

`settings.gradle.kts`

```kotlin
includeBuild("packages/essential_android_sdk")
```

または Maven/AAR 配布時に `io.essential.sdk.android:essential-android-sdk` を依存追加してください。

ホスト側の Essential Service が公開されている必要があります。

## サービス設定

```kotlin
val configuration = EssentialServiceConfiguration(
    servicePackage = "com.example.essential_flutter",
    serviceClassName = "com.example.essential_flutter.service.EssentialService"
)
```

## クイックスタート

```kotlin
val client = EssentialClient.connect(context, configuration)

val request = EssentialGenerateRequest(
    prompt = "こんにちは",
    modelRequirement = EssentialModelRequirement.fallback("essential-mini")
)

lifecycleScope.launch {
    client.generateStream(request).collect { chunk ->
        render(chunk.accumulatedText)
    }
}
```

## 外部アプリから結果を受け取る

同期実行では `generate(...)` または `runTask(...)` の戻り値が、そのまま呼び出し元アプリへ返る最終結果です。

```kotlin
val result = client.runTask(
    EssentialTaskRequest.pixelFeatureChat(
        prompt = "Pixelで通話スクリーニングを使う方法を教えて",
    )
)
render(result.text)
```

ストリーミング実行では `generateStream(...)` または `streamTask(...)` の `Flow` が呼び出し元アプリへ逐次返ります。

```kotlin
client.streamTask(
    EssentialTaskRequest.pixelFeatureChat(prompt = "Pixelのバッテリー設定を確認したい")
).collect { chunk ->
    render(chunk.accumulatedText)
}
```

## 画像・音声付きタスク

Binderのサイズ制限を避けるため、SDKは画像/音声の実データを直接AIDLに詰めず、呼び出し元アプリが読めるURIまたはファイルパスを添付します。

```kotlin
val request = EssentialTaskRequest.plantIdentification(
    image = EssentialMediaAttachment(
        kind = EssentialMediaKind.IMAGE,
        filePath = "/sdcard/Download/plant.jpg",
        mimeType = "image/jpeg",
    ),
)

val result = client.runTask(request)
render(result.text)
```

音声会話は、呼び出し元アプリが録音・再生UIを持ち、Essentialへ音声ファイルまたは音声認識済み transcript を渡す形で利用できます。

```kotlin
val request = EssentialTaskRequest.pixelFeatureChat(
    prompt = "この内容に返答して",
    audio = EssentialMediaAttachment(
        kind = EssentialMediaKind.AUDIO,
        mimeType = "audio/transcript",
        metadata = mapOf("transcript" to "Pixelでスクリーンショットを撮りたい"),
    ),
)
```

固定モデル:

```kotlin
val requirement = EssentialModelRequirement.fixed("essential-mini")
```

全モデル対応:

```kotlin
val requirement = EssentialModelRequirement.anyCompatible()
```

fallback モード:

```kotlin
val requirement = EssentialModelRequirement.fallback("essential-mini")
```

## エラーコード

- `MODEL_NOT_INSTALLED`
- `MODEL_INCOMPATIBLE`
- `ADAPTER_INCOMPATIBLE`
- `DEVICE_CAPACITY_INSUFFICIENT`
- `PERMISSION_DENIED`
- `SESSION_CANCELLED`
- `RUNTIME_UNAVAILABLE`
- `INVALID_CONFIGURATION`
- `REQUEST_TIMED_OUT`

## サンプル

`samples/QuickStart.kt`、`samples/PixelFeatureChatDemo.kt`、`samples/PlantIdentificationDemo.kt` を参照してください。

## スマホに入れられるデモアプリ

SDKの動作確認用に、通常のAndroid APKとしてインストールできるデモアプリを同梱しています。

```bash
cd packages/essential_android_sdk
./gradlew :demo_app:assembleDebug
adb install -r demo_app/build/outputs/apk/debug/demo_app-debug.apk
adb shell monkey -p io.essential.sdk.demo -c android.intent.category.LAUNCHER 1
```

デモアプリには次の画面があります。

- Pixel使い方相談チャット: 外部アプリから `runTask(...)` でプロンプトを送り、Web検索、位置情報、共有メモリ読み込み、共有メモリ書き込み、優先モデルをリクエスト単位で制御します。
- 植物写真デモ: 端末内の写真を選択し、画像添付付き `plant_identification` タスクとして送信します。

現在のGemma 4 E4B ITバンドルはテキストモデルのため、植物写真の実ピクセル認識は視覚対応モデルを追加した環境で有効になります。SDKとホストサービスの外部アプリ連携、写真URI添付、結果返却の経路を確認するためのデモです。
