# IPC / ローカル API / SDK 設計

## 共通方針

- 外部開発者には SDK を正規入口として提供する
- 内部では共通プロトコルを利用する
- API 形状は OpenAI 互換に近い論理モデルを採用する
- streaming、cancel、timeout、quota を標準機能とする

## Android 設計

### 推奨 IPC

- **Bound Service + AIDL** を主経路とする

### 理由

- 呼び出し元アプリ識別がしやすい
- ストリーミングコールバック設計と相性が良い
- Service ライフサイクル管理が明確

### 主要 API

```text
listModels()
ensureModelInstalled(modelRequirement)
runInference(request)
streamInference(request, callback)
cancel(requestId)
downloadModel(modelId)
getDownloadStatus(taskId)
```

### 補助チャネル

- ContentProvider: モデルメタデータの限定公開
- Deep Link / Intent: Essential アプリ起動、権限同意、設定遷移

## iOS 設計

### 推奨方式

- **EssentialKit (Swift Package / Framework)** を主経路とする
- **App Group** で共有メタデータやキャッシュを連携する

### 理由

- Android のような任意常駐 IPC は制限が強い
- 安定性と審査対応を両立しやすい
- 呼び出し側アプリ内で明示的に推論実行できる

### 主要 API

```text
EssentialClient.initialize(config)
EssentialClient.models.list()
EssentialClient.models.ensureInstalled(requirement)
EssentialClient.generate(request)
EssentialClient.generateStream(request)
EssentialClient.cancel(requestId)
EssentialClient.adapters.attach(sessionId, adapterId)
```

## 共通 SDK 設計

### 配布形態

- Android: AAR / Maven
- iOS: Swift Package
- Flutter: Dart facade package

### モデル指定方式

- capability ベース指定
- 特定 `model_id` 固定
- fallback 許可

### 代表データ構造

```text
ModelRequirement
- modelId?
- family?
- capability?
- minContextWindow?
- maxLatencyMs?
- allowFallback
```

```text
GenerateRequest
- messages
- stream
- modelRequirement
- adapterRequirement
- maxTokens
- temperature
- timeoutMs
```

## セキュリティ

- 呼び出し元アプリ識別
- adapter 利用権限の manifest 制御
- レート制限 / 同時実行制限
- 監査用ローカルイベント記録

## エラー設計

- `MODEL_NOT_INSTALLED`
- `MODEL_INCOMPATIBLE`
- `ADAPTER_INCOMPATIBLE`
- `DEVICE_CAPACITY_INSUFFICIENT`
- `PERMISSION_DENIED`
- `SESSION_CANCELLED`
- `RUNTIME_UNAVAILABLE`