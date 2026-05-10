# essential_sdk_dart

Essential の Dart / Flutter 向け SDK です。FFI ランタイムを包む `EssentialClient` を公開し、モデル解決、ストリーミング、タイムアウト、キャンセル、統一エラーコードを提供します。

## 主要 API

- `EssentialClient.initialize(...)`
- `initializeRuntime()`
- `listModels()`
- `ensureModelInstalled(...)`
- `generate(...)`
- `generateStream(...)`
- `cancel(requestId)`
- `attachAdapter(...)`
- `detachAdapter(...)`

## モデル指定

```dart
const anyModel = EssentialModelRequirement.anyCompatible();
const fixedModel = EssentialModelRequirement.fixed('essential-mini');
const fallbackModel = EssentialModelRequirement.fallback('essential-mini');
```

## クイックスタート

```dart
final client = await EssentialClient.initialize(
  const EssentialConfiguration(
    defaultModelId: 'essential-mini',
    installedModels: [
      EssentialInstalledModel(
        modelId: 'essential-mini',
        modelPath: '/data/user/0/com.example.app/files/models/essential-mini.gguf',
        family: 'llama.cpp',
        contextWindow: 4096,
      ),
    ],
  ),
);

await for (final chunk in client.generateStream(
  const EssentialGenerateRequest(
    prompt: 'この文を3行で要約して',
    modelRequirement: EssentialModelRequirement.fallback('essential-mini'),
    timeoutMs: 10000,
  ),
)) {
  print(chunk.accumulatedText);
}
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

`EssentialException.code` で判定できます。

## サンプル

`example/quick_start.dart` を参照してください。