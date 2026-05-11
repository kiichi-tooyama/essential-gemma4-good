# Essential Android 実機検証レポート

作成日: 2026-04-29

## 要約

- 端末: A402XM / Android 16 / arm64-v8a / MediaTek MT6989 / Mali-G720-Immortalis MC12 / RAM 約 11.5 GB
- 本体アプリで Vulkan GPU backend を有効化し、`gemma-4-e4b-it` の実機推論が成功した。
- E4B の同一短文 smoke で、CPU 版は first token 約 121.5 秒だったが、Vulkan 版は first token 約 48.9 秒、prefill は約 10.9 秒まで短縮した。
- R2 配信は E4B manifest、署名、sha256、content-length、range 対応を確認済み。
- E4B は品質面で最も安定。E2B は速度は出るが、出力にチャットテンプレート由来の不安定さが見られた。essential-mini は現エンジンでは非常に遅く、公式訴求には不向き。

## 測定環境

| 項目 | 値 |
|---|---|
| 端末モデル | A402XM |
| Android | 16 |
| ABI | arm64-v8a |
| SoC | MT6989 |
| GPU | Mali-G720-Immortalis MC12 |
| RAM | MemTotal 11,460,072 kB |
| ストレージ | `/data/user/0` 空き 141 GB |
| バッテリー | 95-100% / 充電中 |
| 温度 | 約 34.7-34.9 C |
| アプリ | `com.example.essential_flutter` debug build |
| 推論 backend | llama.cpp + ggml Vulkan + CPU fallback |
| Context | 512 |
| Threads | 8 |
| GPU layers | large GGUF は 99 |

## インストール済みモデル

| Model | File | Size | SHA-256 |
|---|---:|---:|---|
| gemma-4-e4b-it | `gemma-4-E4B-it-Q4_K_M.gguf` | 5,335,285,504 bytes | `e87f2659d0674d528911b017b65e3da65912c961dd53aa4eb7d244e29c64c3fd` |
| gemma-4-e2b-it | `gemma-4-E2B-it-Q2_K.gguf` | 1,468,138,752 bytes | `9b4179759fd7e6c959179fb710db5d04f0ce756515c275515d68c29b04000d41` |
| essential-mini | `tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf` | 668,788,096 bytes | `9fecc3b3cd76bba89d504f29b616eedf7da85b96540e490ca5824d3f7d2776a0` |
| whisper-base | `whisper-base.ggml` | 147,951,465 bytes | `60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe` |
| whisper-tiny | `whisper-tiny.ggml` | 77,691,713 bytes | `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21` |
| piper-lessac-medium | `en_US-lessac-medium.onnx` | 63,201,425 bytes | `ea793a648ce0370665f99fbf891eae3b3a973565c72b08534bb5b2c04e8f2332` |
| ssd-mobilenet-v2 | `ssd_mobilenet_v2.tflite` | 2,807,218 bytes | `a809cd290b4d6a2e8a9d5dad076e0bd695b8091974e0eed1052b480b2f21b6dc` |
| coco-labels | `coco_labels.txt` | 621 bytes | `bd17f1ee35d5f3c862a4894605855abbb9dda4b0621fdb0ac4c2c8c7bb7e730a` |

## 配信検査

Production registry:

- E4B manifest endpoint: `http://210.131.210.210/essential/v1/models/gemma-4-e4b-it/manifest`
- download path: `https://models.node-cloud.net/artifacts/gemma-4-E4B-it-Q4_K_M.gguf`
- artifact size: `5335285504`
- sha256: `e87f2659d0674d528911b017b65e3da65912c961dd53aa4eb7d244e29c64c3fd`
- signature: Ed25519, key id `ed25519-7704ee5e8a5764d2`

R2 / Cloudflare response:

- HTTP 200
- `content-length: 5335285504`
- `accept-ranges: bytes`
- `cache-control: public, max-age=31536000, immutable`
- `server: cloudflare`

## 推論ベンチマーク

### gemma-4-e4b-it Q4_K_M / Vulkan

| Case | Prompt | Prompt tokens | Load | Prefill | First token | Generation | Output | Notes |
|---|---|---:|---:|---:|---:|---:|---|---|
| E4B-1 | `日本語で一文だけ返答: こんにちは` | 108 | 22.57 s | 10.89 s | 48.88 s | 51.11 s | `こんにちは。` | 正常 |
| E4B-2 | `MacでPDFを圧縮する方法を一文で教えて` | 109 | cached | 2.07 s | 22.65 s | 33.94 s | `MacでPDFを圧縮するには、プレビューアプリでPDFを開き、「ファイル」メニューから「書き出す」を選択し、圧縮のレベルを設定して保存します。` | 正常、約 34 tokens / 33.94 s |

CPU 版の参考値:

- E4B CPU optimized: model load 15.13 s、first token 121.55 s、generation 128.66 s、出力 `こんにちは。`
- Vulkan 化により、同一短文 case の first token は約 2.49 倍高速化、prefill は約 11 秒まで短縮。

### gemma-4-e2b-it Q2_K / Vulkan

| Case | Prompt | Prompt tokens | Load | Prefill | First token | Generation | Output | Notes |
|---|---|---:|---:|---:|---:|---:|---|---|
| E2B-1 | `日本語で一文だけ返答: こんにちは` | 108 | 8.85 s | 10.44 s | 41.27 s | 60.19 s | `<|channel>thought...` | 速度は取得できたが出力品質は不安定 |
| E2B-2 | `MacでPDFを圧縮する方法を一文で教えて` | 109 | cached | 2.12 s | 13.69 s | 30.86 s | `ユーザーからの質問内容に、関係ない別分野の説明を足さないでください...` | 速度は良好、品質は要プロンプト/テンプレート調整 |

### essential-mini / TinyLlama Q4_K_M

| Case | Prompt | Prompt tokens | Load | Prefill | First token | Decode | Result |
|---|---|---:|---:|---:|---:|---|---|
| mini-1 | `日本語で一文だけ返答: こんにちは` | 206 | 1.22 s | 63.32 s | 63.46 s | 10-15 s/token | 途中停止 |

所見:

- モデルロードは速いが、prefill と decode が極端に遅い。
- large GGUF と違い、現設定では GPU backend の恩恵が薄いか、CPU fallback が強く出ている可能性が高い。
- 公式サイト向けには E4B を主役にし、mini は「軽量モデル候補、現時点では調整中」と扱うのが安全。

## UI / SDK アプリ検査

| App | Package | Build | Install | Launch / UI | Result |
|---|---|---|---|---|---|
| Main app | `com.example.essential_flutter` | OK | OK | 起動 OK | Vulkan 通常 APK に戻し済み |
| Mac Chat | `io.essential.sdk.macchat` | OK | OK | Activity focus OK | 端末ロック中で UI dump は SystemUI 側を取得 |
| Plant Camera | `io.essential.sdk.plantcamera` | OK | OK | 前回 UI確認済み | `カメラ起動中`、`植物名`、`撮る` を確認済み |
| SDK Demo | `io.essential.sdk.demo` | OK | blocked | `INSTALL_FAILED_USER_RESTRICTED` | HyperOS/Android 側のUSBインストール制限 |

## 植物認識エンジン所見

- 現在の `ssd-mobilenet-v2` は COCO 物体検出であり、植物種名を高精度に出す用途には不十分。
- 種名レベルの植物判定には、Pl@ntNet API など植物同定専用モデル/APIが必要。
- Plant Camera app は常時カメラ preview、撮影ボタン、植物名表示 UI を実装済み。API key 未設定時は Essential service fallback に入る。

## なぜ GPU を使っていなかったか

以前の Android native build は llama.cpp の Vulkan backend が無効だったため、LLM 推論は CPU 経路だけを使っていた。

今回の対応:

- `GGML_VULKAN=ON`
- Vulkan shader generator の host toolchain を追加
- Android native minSdk を 28 に上げ、Vulkan 1.1 symbol link を解消
- Vulkan-Hpp / SPIRV-Headers を追加
- large GGUF の load option で `gpuLayers=99`
- perf log を有効化

## エンジン比較メモ

現状の llama.cpp Vulkan は E4B で実動し、CPU より明確に高速。ただし first token はまだ 20-50 秒級で、公式サイトで「即時応答」と言うには弱い。

候補:

- llama.cpp Vulkan: 現在のコードに最も近い。GGUF 資産をそのまま使いやすい。Android では端末/driver差の検証が必要。
- MLC LLM: Android GPU 実行を前提にした導入資料があり、TVM runtime を Gradle subproject として組み込める。
- MediaPipe LLM Inference: Google AI Edge の Android 向け on-device LLM API。GPU backend と LoRA 対応の公式資料あり。
- ExecuTorch: PyTorch 系の Android AAR / LLM runner があり、XNNPACK/KleidiAI/QNN などの backend 戦略に向く。

## 公式サイト向けに使いやすい表現

- 「5GB級 Gemma 系モデルをスマートフォン上でオフライン実行」
- 「R2/Cloudflare から署名付き manifest と sha256 検証でモデル配信」
- 「Mali-G720-Immortalis MC12 搭載 Android 実機で Vulkan GPU backend による推論を確認」
- 「E4B Q4_K_M で日本語応答生成に成功」
- 「CPU版比で E4B の first token を約 2.5 倍高速化」

避けるべき表現:

- 「リアルタイム会話」: 現時点の first token は 20-50 秒級。
- 「植物名を高精度判定」: API key 付き専用エンジン導入前は未達。
- 「全モデルが高速」: essential-mini は現エンジンでは遅い。

## 未解決課題

- E4B の first token を 5 秒以内にするには、engine / quantization / prompt cache / GPU layer 配置の追加改善が必要。
- E2B のチャットテンプレートと system prompt を調整し、特殊 token 混入を防ぐ必要がある。
- essential-mini は現在の llama.cpp 設定と相性が悪く、モデル差し替えまたは CPU/GPU backend の個別設定が必要。
- Demo app の再インストールは端末セキュリティ設定によりブロックされた。ユーザー側で USB インストール許可が必要。
- Plant Camera の種名判定は Pl@ntNet API key または専用モデルの導入後に精度評価が必要。

## 参考資料

- MLC LLM Android: https://llm.mlc.ai/docs/deploy/android.html
- Google AI Edge MediaPipe LLM Inference Android: https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference/android
- ExecuTorch Android: https://docs.pytorch.org/executorch/stable/using-executorch-android.html
