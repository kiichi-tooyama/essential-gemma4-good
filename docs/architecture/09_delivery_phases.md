# 開発フェーズ分割

## Phase 1: 技術検証

- Flutter アプリ骨格
- `llama.cpp` のモバイル推論検証
- モデルダウンロードと署名検証の最小プロトタイプ
- Android / iOS の最小 SDK 経路確認

## Phase 2: モデル管理基盤

- モデルカタログ取得
- ダウンロードマネージャ
- ステージング / 有効化 / ロールバック
- モデル管理 UI

## Phase 3: ローカル API / SDK

- Android Bound Service + AIDL
- iOS EssentialKit + App Group
- 共通リクエスト / レスポンス定義
- ストリーミングとキャンセル

## Phase 4: チャット体験

- 初回オンボーディング
- チャット画面
- モデル選択導線
- 推論状態可視化

## Phase 5: Adapter / LoRA

- adapter manifest
- namespace 管理
- attach / detach 制御
- 開発者アプリ向け利用制御

## Phase 6: サーバー配信基盤

- registry API
- manifest signer
- artifact 配信
- admin console

## Phase 7: 安定化

- 低 RAM 対応
- 発熱 / 電力対策
- 異常系回復
- 任意参加テレメトリ

## 完了条件

- 端末単体でチャット利用できる
- 他アプリが SDK 経由で推論できる
- モデル / adapter の配信と更新が成立する
- サーバーが既存環境を壊さず運用できる