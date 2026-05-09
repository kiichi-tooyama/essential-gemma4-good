# Essential Dart SDK

Essential の Dart / Flutter 向け SDK です。`EssentialClient` を通じてモデル解決、ストリーミング生成、タイムアウト、キャンセル、アダプター管理、統一エラーコードを利用できます。

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

詳しい導入手順と実装例は `docs/developer_api.md` を参照してください。
