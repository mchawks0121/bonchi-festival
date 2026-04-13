# ぼんち祭り バグハンター — 仕様書

## 概要

**バグハンター** は、AR（拡張現実）技術を使ってバグ（害虫）を捕まえるスリングショットゲームです。  
iOS デバイスのカメラ越しに 3D バグが出現し、スリングショットで網を飛ばして捕獲します。  
プロジェクター連携モードでは、大画面スクリーンに 3D バグを表示し、最大 3 台の iOS デバイスが同時にコントローラーとして参加できます。

---

## プレイモード

| モード | アイコン | 説明 |
|--------|---------|------|
| スタンドアロン | 📱 | AR のみ。1台の iPhone で完結。 |
| プロジェクター／クライアント | 🎮 | iPhone がコントローラーとして機能し、プロジェクターサーバーに操作を送信。 |
| プロジェクター／サーバー | 📺 | プロジェクター表示デバイス。最大 3 台のクライアントの操作を受け取って大画面にゲームを表示。 |

モードはスタート画面のカードをタップして選択します。

---

## 操作説明

### スリングショット（スタンドアロン・クライアントモード）

1. **狙いを定める** — iPhone を動かして画面中央の照準リングをバグに重ねます。  
   バグが照準内に入ると、ロックオンリング（オレンジ色）が表示されます。

2. **引っ張る** — 画面下部のスリングショット部分を **下に向かってスワイプ** します。  
   引っ張る量が強さ（power）になります。

3. **放す** — 指を離すと網が発射されます。  
   - **ロックオンしている場合**: 網はバグに向かって飛びます。  
   - **ロックオンしていない場合**: 発射角度と弾道から最も近いバグを自動判定します。

4. **捕獲** — 網がバグに当たると捕獲成功。ポイントが加算されます。

### プロジェクターサーバー

- クライアントの発射情報（角度・強さ）を Multipeer Connectivity で受信し、スクリーン上のバグに当てます。
- 最大 3 台のクライアントが同時接続でき、それぞれの網は異なる色で識別されます。

---

## 出現バグ一覧

| バグ | 名前 | ポイント | 出現率 | 移動速度 | 説明 |
|------|------|---------|--------|---------|------|
| 🐞 | Null (butterfly) | 1 pt | 約 60 % | 速い (110) | 軽微な未定義参照エラー。すばやく動き回るが低得点。 |
| 🦠 | Virus (beetle) | 3 pt | 約 30 % | 普通 (70) | 自己増殖型ランタイムエラー。中程度の速度と得点。 |
| 👾 | Glitch (stag) | 5 pt | 約 10 % | 遅い (45) | 致命的なデータ破壊バグ。大型で捕まえやすいが希少。 |

※ 出現率は開始直後の確率です。時間が経過しても比率は変わりませんが、スポーン間隔が短くなります。

---

## ゲームルール

| 項目 | 内容 |
|------|------|
| 制限時間 | **90 秒** |
| 目標 | 時間内にできるだけ多くのバグを捕獲してポイントを稼ぐ |
| スポーン間隔 | 開始時 1.8 秒 → 90 秒時点で最短 0.6 秒（難易度上昇） |
| スコア計算 | **クライアント（iOS）側のみ**で行う。プロジェクターはスコアを計算・表示しない |
| スコア通知 | プロジェクターが `bugCaptured` メッセージで網を射出した iOS へバグ種類を通知 → iOS 側で加算 |
| 最大同時接続 | **3 台**（4 台目以降は接続拒否） |
| ゲーム終了 | タイムアップ後、プロジェクターは自動的に待機画面に戻る |

---

## マルチプレイヤー仕様

### 接続方法
- Multipeer Connectivity により、同一ローカルネットワーク上の iOS デバイスが自動検出・接続されます。
- プロジェクターが広告（Advertise）し、iOS デバイスが招待を受け接続します。
- 3 台に達した時点で、以降の接続要求は拒否されます。

### 独立プレイ
- 各 iOS デバイスは独立してスリングショットを操作でき、同時に複数の網がプロジェクター画面上を飛びます。
- バグはどのプレイヤーの網でも捕獲できます（早い者勝ち）。
- スコアは各 iOS デバイスが独自に管理します（プロジェクター側での合算なし）。

### 網の色分け

| スロット | 色 | R / G / B |
|---------|-----|-----------|
| Player 1（最初に接続） | シアン | (0.0, 1.0, 1.0) |
| Player 2 | オレンジ | (1.0, 0.55, 0.0) |
| Player 3 | マゼンタ | (1.0, 0.2, 0.8) |

### 接続機器情報パネル
- プロジェクター画面の右下に半透明パネルを常時表示します。
- 「接続中 N / 3」のカウントと各プレイヤーのデバイス名・カラードット（上記色）を表示します。
- 未接続スロットは「待機中…」とグレーで表示します。

---

## 難易度曲線

ゲーム開始後、時間が経つにつれてバグの出現頻度が増加します。

```
スポーン間隔（秒） = max(0.6,  1.8 - elapsed / 75)
```

- 0 秒: 約 1.8 秒間隔
- 45 秒: 約 1.2 秒間隔
- 75 秒: 約 0.8 秒間隔
- 90 秒: 最短 0.6 秒間隔

---

## アーキテクチャ概要

```
iOS（iPhone × 最大3台）
├── ContentView.swift      … スタート／ゲーム中／終了画面のルーティング
├── Controller/
│   ├── GameManager.swift  … ゲーム状態・スコア管理、Multipeer 通信（bugCaptured 受信 → スコア加算）
│   ├── ARGameView.swift   … ARSCNView (3D) + SKView 透過オーバーレイ
│   ├── ARBugScene.swift   … SpriteKit シーン (AR 当たり判定・スコア)
│   ├── Bug3DNode.swift    … SceneKit 3D バグモデル（蝶・甲虫・クワガタ）
│   └── SlingshotView.swift … スワイプ操作 → 角度・強さ変換
└── Shared/
    └── GameProtocol.swift … 通信メッセージ型（bugCaptured 含む）、BugType 定義

Projector（Mac / iPad）
└── World/
    ├── WorldViewController.swift      … SpriteKit/SceneKit ビュー管理・ConnectedPlayersView
    ├── BugHunterScene.swift           … 3D バグゲームシーン（スコア計算なし）
    ├── BugSpawner.swift               … BugNode の生成・経路制御
    ├── NetProjectile.swift            … 飛んでくる網ノード（playerIndex 保持・プレイヤー色対応）
    ├── ProjectorBug3DCoordinator.swift … SceneKit 3D バグ + SpriteKit プロキシ管理、捕獲通知
    └── ProjectorGameManager.swift     … 最大3台の Multipeer 接続管理、bugCaptured 送信
```

### 通信フロー（Multipeer Connectivity）

```
iOS Controller (×最大3台)               Projector Server
    │                                        │
    │── startGame ──────────────────────────>│  (いずれかのクライアントが送信)
    │                                        │
    │── launch(angle, power, timestamp) ────>│  → playerIndex はサーバー側で peerID より特定
    │                                        │  → 対応する色の網を発射
    │                                        │  → 網がバグに当たる
    │<── bugCaptured(bugType, playerIndex) ──│  ※ 網を射出したプレイヤーのみに送信
    │                                        │
    │  score += bugType.points               │
    │                                        │
    │<── gameState(state, timeRemaining) ────│  (score は常に 0 — クライアントが独自管理)
    │                                        │
    │── resetGame ───────────────────────── >│
```

### メッセージ型一覧

| 型 | 方向 | ペイロード | 説明 |
|----|------|-----------|------|
| `launch` | iOS → Projector | `LaunchPayload(angle, power, timestamp)` | スリングショット発射 |
| `startGame` | iOS → Projector | なし | ゲーム開始 |
| `resetGame` | iOS → Projector | なし | 待機画面にリセット |
| `gameState` | Projector → iOS | `GameStatePayload(state, score=0, timeRemaining)` | 残り時間の同期 |
| `bugCaptured` | Projector → iOS（該当プレイヤーのみ） | `BugCapturedPayload(bugType, playerIndex)` | バグ捕獲通知・スコア加算 |

### スコア設計

- **スコア計算はクライアント（iOS）側のみ。**
- プロジェクター側でバグが捕獲されると、`ProjectorGameManager.sendBugCaptured(bugType:toPlayerAtSlot:)` が網を射出したプレイヤーの peerID にだけ `bugCaptured` メッセージを送信します。
- iOS 側 `GameManager` が `bugCaptured` を受信し、`score += bugType.points` で加算します。
- スタンドアロンモードでは `ARBugScene` が直接 `BugHunterSceneDelegate` を通じてスコアを更新します。
- プロジェクター側の `BugHunterScene` はスコアを保持しません。

---

## 開発環境

| 項目 | バージョン |
|------|-----------|
| Swift | 5.9 以上 |
| iOS Deployment Target | iOS 17.0 以上 |
| Xcode | 15 以上 |
| フレームワーク | SwiftUI, ARKit, SceneKit, SpriteKit, MultipeerConnectivity |

---

## ビルド手順

1. Xcode でプロジェクトを開く (`bonchi-festival.xcodeproj`)
2. ターゲット `bonchi-festival` を選択
3. 実機 iPhone を接続してビルド・実行
4. スタート画面でプレイモードを選択してゲーム開始

> ⚠️ ARKit を使用するため、実機が必要です。シミュレーターでは AR 機能は動作しません。

---

## 注意事項

- **カメラ権限**: 初回起動時にカメラアクセスを許可してください（AR に必要）。
- **ローカルネットワーク権限**: プロジェクターモードを使う場合、ローカルネットワークへのアクセスを許可してください（Multipeer Connectivity に必要）。
- **明るい場所**: ARKit は十分な光量が必要です。暗い場所ではバグの位置精度が下がります。
- **同時接続上限**: プロジェクターに接続できる iOS デバイスは最大 3 台です。4 台目以降は自動的に拒否されます。
