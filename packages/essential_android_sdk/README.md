# Essential Android SDK

Essential の Android Bound Service / AIDL 実装を利用するための開発者向け SDK です。`EssentialClient` が非同期 API、ストリーミング、タイムアウト、キャンセル、モデル選択をまとめて提供します。

This public package intentionally includes the SDK library and the Pixel Feature Chat app only. Essential's bound service is protected by a `signature` permission, so a release Pixel Chat APK must be signed with the same certificate as the Essential APK.

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
    serviceClassName = "com.example.essential_flutter.service.EssentialService",
    callerPackage = context.packageName,
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

`samples/QuickStart.kt`、`samples/PixelFeatureChatDemo.kt` を参照してください。

## Pixel Feature Chat をスマホに入れる

```bash
cd packages/essential_android_sdk
./gradlew :pixel_chat_app:installDebug
```

Release 版 Essential APK と接続する Pixel Chat APK は、Essential と同じ証明書で署名してください。ローカルに次の properties がある場合、`assembleRelease` は同じ release key を使います。

```text
~/.android/essential-gemma4-good-release.properties
```

別の場所に置く場合:

```bash
export ESSENTIAL_RELEASE_KEYSTORE_PROPERTIES=/path/to/release.properties
./gradlew :pixel_chat_app:assembleRelease
```

Essential APK と Pixel Chat APK の署名一致は、公開 repo ルートから次で確認できます。

```bash
./scripts/verify_android_release_signatures.sh \
  /path/to/essential.apk \
  packages/essential_android_sdk/pixel_chat_app/build/outputs/apk/release/pixel_chat_app-release.apk
```
