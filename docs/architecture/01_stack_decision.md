# 技術スタック選定レポート

## 結論

`Essential` のクロスプラットフォームアプリ基盤は **Flutter** を採用する。

### 採用構成

- アプリ UI / 共通アプリ層: Flutter
- LLM 推論: `llama.cpp` 系
- 補助モデル: ONNX Runtime / TensorFlow Lite
- リアルタイム前後処理: MediaPipe を限定利用

## Flutter vs React Native

| 観点 | Flutter | React Native | 評価 |
|---|---|---|---|
| C/C++ 推論ランタイム連携 | `dart:ffi` で実装しやすい | Native Module / Bridge 設計が増える | Flutter 優位 |
| ストリーミング UI | 高頻度描画でも一貫性が高い | Bridge 境界の考慮が増える | Flutter 優位 |
| Android / iOS の見た目統一 | 高い | 高いがネイティブ依存差が出やすい | Flutter 優位 |
| 推論ワーカー分離 | Isolate で整理しやすい | JS スレッドとネイティブ同期設計が難しい | Flutter 優位 |
| ネイティブ SDK 組み込み | Plugin 境界が明確 | 結局ネイティブ実装比率が高くなりやすい | Flutter 優位 |
| Web 人材流用 | やや弱い | 強い | RN 優位 |

## Flutter を選ぶ理由

- LLM 推論で必要になる C/C++ ランタイム連携との相性が良い
- チャット UI、ダウンロード進捗、モデル管理画面を高品質に揃えやすい
- Android / iOS の差分を Plugin / Platform Channel / FFI 層へ閉じ込めやすい
- ストリーミングレスポンス表示と長時間処理の状態表現がしやすい

## React Native を主採用しない理由

- 推論、ファイル I/O、サービス連携、ストリーミング通知でネイティブ依存が増えやすい
- Android Service や iOS Framework 連携の実装重心がネイティブに寄り、JS 層のメリットが相対的に下がる
- 高頻度なトークン更新やダウンロード進捗通知で設計複雑性が上がる

## 推論ランタイム選定

### 1. LLM: llama.cpp

**採用理由**

- Gemma 系を含む量子化済み LLM の運用実績がある
- GGUF 配布と相性が良い
- モバイルでの CPU / GPU 利用選択肢が豊富
- adapter / LoRA 適用戦略を取りやすい

**用途**

- チャット
- 要約
- テキスト生成

### 2. ONNX Runtime

**採用理由**

- モデル種類の柔軟性が高い
- 埋め込み、分類、マルチモーダル補助に拡張しやすい

**用途**

- 埋め込み
- 軽量分類
- 補助推論

### 3. TensorFlow Lite

**採用理由**

- Android での実績が豊富
- 既存資産の取り込みに有利

**用途**

- 軽量補助モデル
- レガシー互換

### 4. MediaPipe

**採用理由**

- 音声 / 画像などリアルタイム前後処理に強い

**用途**

- 将来のマルチモーダル拡張
- 前処理 / 後処理

## 最終判断

- クロスプラットフォーム層は Flutter
- 推論は単一ランタイムに寄せず、LLM と補助モデルでハイブリッド構成
- Android / iOS の差異はネイティブ層で吸収し、上位 API は共通化する