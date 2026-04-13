# ぼんち祭り バグハンター — AI開発プロンプト

## このドキュメントについて

このファイルは、**ぼんち祭り バグハンター** プロジェクトを AI（GitHub Copilot 等）に継続開発させるための包括的なコンテキスト・プロンプトです。  
プロジェクトの概要・現在の実装状態・アーキテクチャ・コーディング規約・未実装タスクをすべて記載しています。

---

## プロジェクト概要

**ぼんち祭り バグハンター** は、ARKit × SpriteKit × SceneKit × MultipeerConnectivity を組み合わせた iOS／iPad ゲームです。

- **テーマ**: 腐敗したデジタルワールドに出現する「バグ（害虫）」を、スリングショットで網を飛ばして捕獲する。  
- **コンセプト**: バグたちは `NullReferenceException`、自己増殖するウイルス、致命的なデータ破壊グリッチとして擬人化される。世界は感染しており、プレイヤーは「バグハンター」として世界を浄化する。  
- **ロケーション**: 祭り（ぼんち祭り）会場での大型スクリーン展示を想定。観客が iPhone でスリングショットをプレイ。

---

## プラットフォーム構成

| デバイス | 役割 | ターゲット |
|---------|------|-----------|
| iPhone (最大3台) | コントローラー（ARスリングショット） | iOS 17.0+ |
| iPad / Mac | プロジェクターサーバー（大画面表示） | iOS 17.0+ (Catalyst or iPad) |

---

## プレイモード

| モード | 定数 | 説明 |
|--------|------|------|
| スタンドアロン | `isARMode=false, isProjectorMode=false` | 1台の iPhone で完結する AR バグハンター。 |
| プロジェクター・クライアント | （GameManager で管理） | iPhone がコントローラー。スリングショット操作をプロジェクターへ送信。 |
| プロジェクター・サーバー | `isProjectorMode=true` | 大画面表示デバイス。最大3台の iPhone を受け付ける。 |

---

## ファイル構成と責務

```
bonchi-festival/
├── ContentView.swift            SwiftUI ルート。起動→スタート→ゲーム→リザルト画面を管理。
├── Controller/
│   ├── GameManager.swift        iOS 側の全ゲーム状態・スコア管理。Multipeer 通信ハブ。
│   │                            bugCaptured 受信 → score += bugType.points
│   ├── ARGameView.swift         ARSCNView (3D バグ表示) + 透過 SKView オーバーレイの合成。
│   │                            ARSCNViewDelegate / ARSKViewDelegate を実装。
│   ├── ARBugScene.swift         SpriteKit 透過シーン。照準リング・ロックオンリング・捕獲アニメを担当。
│   │                            プロキシ BugNode を 3D 投影座標に毎フレーム同期。
│   ├── Bug3DNode.swift          SceneKit 3D バグモデル（蝶・甲虫・クワガタ）。
│   │                            手続き的ジオメトリ。corruptionAura（発光オーラ）付き。
│   └── SlingshotView.swift      SwiftUI/UIKit スリングショット UI。下スワイプ → angle/power に変換。
├── Shared/
│   └── GameProtocol.swift       Multipeer で共有するメッセージ型・BugType 定義。
│                                MessageType, GameMessage, LaunchPayload, GameStatePayload,
│                                BugCapturedPayload, BugType, PhysicsCategory
└── World/                       プロジェクター側（iPad / Mac Catalyst）
    ├── WorldViewController.swift  ルート UIViewController。
    │                              レイアウト: SCNView (背面) + SKView 透過オーバーレイ (前面)
    │                              + ConnectedPlayersView (右下)
    ├── WaitingScene.swift         待機画面 SKScene。タイトル・バグ説明・接続待ちテキスト。
    ├── BugHunterScene.swift       ゲーム中 SKScene（isProjectorMode=true で透過）。
    │                              HUD（残り時間バー・タイムラベル）・ネット物理衝突判定を担当。
    │                              onBugCaptured コールバックで捕獲を ProjectorBug3DCoordinator へ通知。
    ├── BugSpawner.swift           SpriteKit 不可視 BugNode の生成・ベジェ経路制御。
    │                              （プロジェクターでは ProjectorBug3DCoordinator が直接呼ぶ）
    ├── NetProjectile.swift        網 SKShapeNode。playerIndex を保持しプレイヤー色で描画。
    ├── ProjectorBug3DCoordinator.swift
    │                              SCNView に Bug3DNode を配置し、BugHunterScene に不可視プロキシを同期。
    │                              捕獲イベント → onCaptureNotify(bugType, playerIndex) コールバック。
    └── ProjectorGameManager.swift 最大3台の MultipeerConnectivity 接続管理。
                                   sendBugCaptured(bugType:toPlayerAtSlot:) で特定プレイヤーに送信。
```

---

## 通信プロトコル（Multipeer Connectivity）

### メッセージ型

```swift
// GameProtocol.swift に定義
enum MessageType: String, Codable {
    case launch       // iOS → Projector
    case startGame    // iOS → Projector
    case resetGame    // iOS → Projector
    case gameState    // Projector → iOS（全員）
    case bugCaptured  // Projector → iOS（該当プレイヤーのみ）
}
```

### ペイロード

```swift
struct LaunchPayload:      Codable { let angle: Float; let power: Float; let timestamp: Double }
struct GameStatePayload:   Codable { let state: String; let score: Int; let timeRemaining: Double }
struct BugCapturedPayload: Codable { let bugType: BugType; let playerIndex: Int }
```

### フロー図

```
iOS Controller (×最大3台)               Projector Server
    │                                        │
    │── startGame ──────────────────────────>│
    │── launch(angle, power, timestamp) ────>│  → playerIndex を peerID から特定
    │                                        │  → 対応色の NetworkProjectile を発射
    │                                        │  → 網がプロキシ BugNode に接触
    │<── bugCaptured(bugType, playerIndex) ──│  ※ 該当プレイヤーにのみ unicast
    │  score += bugType.points               │
    │<── gameState(state, 0, timeRemaining) ─│  score 常に 0（iOS 側が独自管理）
    │── resetGame ───────────────────────── >│
```

---

## バグ仕様

```swift
enum BugType: String, CaseIterable, Codable {
    case butterfly  // Null Bug  — 1pt, 速い(110), 60%
    case beetle     // Virus Bug — 3pt, 普通(70), 30%
    case stag       // Glitch    — 5pt, 遅い(45), 10%
}
```

| 種類 | 絵文字 | ポイント | 速度 | 出現率 | ロア |
|------|--------|---------|------|-------|------|
| Null (butterfly) | 🐞 | 1 pt | 110 | 60 % | 軽微な未定義参照エラー |
| Virus (beetle) | 🦠 | 3 pt | 70 | 30 % | 自己増殖型ランタイムエラー |
| Glitch (stag) | 👾 | 5 pt | 45 | 10 % | 致命的なデータ破壊バグ |

---

## ゲームルール

| 項目 | 値 |
|------|---|
| 制限時間 | 90 秒 |
| スポーン間隔 | `max(0.6, 1.8 - elapsed / 75)` 秒 |
| スコア管理 | iOS（クライアント）側のみ。プロジェクターは 0 固定。 |
| 最大接続 | 3 台。4 台目以降は拒否。 |
| ゲーム終了 | プロジェクターは 4 秒後に自動で WaitingScene へ戻る。 |

---

## プロジェクター レイアウト

```
┌────────────────────────────────────────────────┐
│  SCNView  — Bug3DNode（3D バグ）               │ ← 背面 (z=0)
│  SKView   — BugHunterScene 透過オーバーレイ     │ ← 前面 (透過)
│               HUD / 網 / 不可視プロキシ BugNode  │
│  ConnectedPlayersView ──────────────── [右下]   │ ← 常時最前面 UIKit
└────────────────────────────────────────────────┘
```

- **SCNView.backgroundColor**: `UIColor(red:0.05, green:0.12, blue:0.05, alpha:1)` （現在は暗い緑）
- **WaitingScene.backgroundColor**: `SKColor(red:0.04, green:0.08, blue:0.04, alpha:1)` （現在は暗い緑）

> ⚠️ **未実装タスク**: プロジェクターの背景を「腐敗したデジタルワールド」スタイルに変更する。  
> 詳細は「未実装タスク」セクション参照。

---

## プレイヤー色分け

| スロット | 色名 | UIColor (R, G, B) | SKColor |
|---------|------|------------------|---------|
| Player 1 | シアン | (0.0, 1.0, 1.0) | `.cyan` |
| Player 2 | オレンジ | (1.0, 0.55, 0.0) | — |
| Player 3 | マゼンタ | (1.0, 0.2, 0.8) | — |

---

## 接続機器情報パネル（ConnectedPlayersView）

- `WorldViewController` 内の UIKit `UIView` サブクラス（または SwiftUI）。
- 右下に常時表示。内容: 「接続中 N / 3」 + デバイス名 + カラードット。
- 未接続スロットは「待機中…」とグレーで表示。

---

## スコア設計（重要）

1. **プロジェクター側はスコアを一切持たない。** `BugHunterScene` はスコア変数を持たず、`GameStatePayload.score` は常に `0`。
2. バグ捕獲時: `ProjectorGameManager.sendBugCaptured(bugType:toPlayerAtSlot:)` が当該プレイヤーの `MCPeerID` にのみ `bugCaptured` を unicast。
3. iOS 側 `GameManager` が `bugCaptured` を受信し `score += bugType.points`。
4. スタンドアロンモードは `ARBugScene` → `BugHunterSceneDelegate` 経由でスコアを更新。

---

## AR（スタンドアロン・クライアント）の仕組み

```
ARSCNView (3D バグ)
    │ Bug3DNode: SCNNode + 手続きジオメトリ
    │ corruptionAura: 発光エフェクト
SKView (透過オーバーレイ)
    └── ARBugScene
        ├── 照準クロスヘア（中央固定）
        ├── ロックオンリング（バグ接近時オレンジ）
        ├── プロキシ BugNode（3D 投影座標に毎フレーム同期）
        └── 捕獲パーティクルアニメ
```

- `ARSCNViewDelegate` でカメラ姿勢を毎フレーム取得し、Bug3DNode の 3D 座標を 2D 画面座標に変換してプロキシを移動。
- `cachedViewHeight` でレンダースレッドからの UIKit アクセスを回避。

---

## 物理衝突

```swift
// PhysicsCategory (GameProtocol.swift)
static let bug: UInt32 = 0x1 << 0   // BugNode
static let net: UInt32 = 0x1 << 1   // NetProjectile

// BugNode
physicsBody?.isDynamic          = false
physicsBody?.categoryBitMask    = PhysicsCategory.bug
physicsBody?.contactTestBitMask = PhysicsCategory.net
physicsBody?.collisionBitMask   = 0

// NetProjectile
physicsBody?.isDynamic          = true
physicsBody?.categoryBitMask    = PhysicsCategory.net
physicsBody?.contactTestBitMask = PhysicsCategory.bug
physicsBody?.collisionBitMask   = 0
```

接触 → `BugHunterScene.didBegin(_:)` → `onBugCaptured?(bugNode, netNode.playerIndex)`

---

## コーディング規約

- **言語**: Swift 5.9 以上。`final class` を基本とする。
- **UI**: SwiftUI（iOS 側）、UIKit + SpriteKit + SceneKit（プロジェクター側）。
- **スレッド**: SceneKit レンダースレッドから UIKit にアクセスしない（`cachedViewHeight` パターン参照）。
- **Multipeer 受信コールバック**は常に `DispatchQueue.main.async` でメインスレッドに戻す。
- **コメント**: 日本語・英語どちらでも可。`// MARK: -` でセクション分け。
- **ファイル分割**: iOS 側は `Controller/`、プロジェクター側は `World/`、共有型は `Shared/`。
- **依存ライブラリ**: 追加しない。Apple 標準フレームワークのみ使用。
- **アセット**: 外部画像・サウンドファイルなし。すべて手続き的に生成（`CGPath`, `SKShapeNode`, `SCNGeometry` 等）。

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

```
1. Xcode で bonchi-festival.xcodeproj を開く
2. ターゲット bonchi-festival を選択
3. 実機 iPhone を接続してビルド・実行
4. スタート画面でモード選択
```

> ⚠️ ARKit は実機が必要。シミュレーターでは AR 機能が動作しない。

---

## 未実装タスク

### 1. プロジェクター背景を「腐敗したデジタルワールド」に変更（優先度: 高）

#### 要件

プロジェクターの全画面表示を、**サイバーパンク／腐敗したデジタルワールド**のビジュアルテーマに変更する。

#### 変更対象ファイル

| ファイル | 変更内容 |
|---------|---------|
| `World/WorldViewController.swift` | `scnView.backgroundColor` を暗い青黒に変更。SceneKit シーンに Tron スタイルのグリッド床・背景壁を追加（`SCNPlane` + 手続き生成テクスチャ）。 |
| `World/WaitingScene.swift` | 背景色を暗い青黒に変更。マトリックスレイン（落下する日本語カタカナ/16進数文字）、グリッドライン、スキャンライン、グリッチフラッシュを追加。 |
| `World/BugHunterScene.swift` | スタンドアロン背景色を変更。プロジェクターモードではグリッド・スキャンラインを低透明度で SK オーバーレイに追加（3D バグの視認性を損なわない程度）。 |

#### デザイン仕様

**カラーパレット**
```
背景ベース : UIColor(red: 0.03, green: 0.03, blue: 0.10, alpha: 1)  // 深い青黒
グリッドライン: UIColor(red: 0.0,  green: 0.6,  blue: 1.0,  alpha: 0.4) // シアン
マトリックス文字（ヘッド）: SKColor(red: 0.9, green: 1.0, blue: 0.9, alpha: 1.0)
マトリックス文字（テール）: SKColor(red: 0.0, green: 0.9, blue: 0.4, alpha: 0.0〜0.8)
腐敗色（文字の一部）: SKColor(red: 0.8, green: 0.1, blue: 0.6, alpha: ...)  // マゼンタ
グリッチフラッシュ: SKColor(red: 0.0, green: 1.0, blue: 0.5, alpha: 0.07)
スキャンライン: SKColor(white: 1.0, alpha: 0.05)
```

**WaitingScene の背景エフェクト実装ガイド**

```swift
// 1. グリッドライン (zPosition: -2)
//    48pt セル幅の縦横ライン。上記シアン色、alpha 0.07。

// 2. マトリックスレイン (zPosition: -1)
//    SKAction.repeatForever で 0.08 秒ごとに spawnMatrixDrop() を呼ぶ。
//    各ドロップ: SKNode コンテナ + 子 SKLabelNode × 6〜18 文字。
//    フォント "Menlo-Bold" 16pt。文字セット: "01アイウエオカキクケコ#$%&ABCDEF0123456789"
//    コンテナを画面上端から下端まで速度 100〜250 pt/s で落下させ removeFromParent。
//    末尾の一部文字をマゼンタ（腐敗色）でランダムに着色。

// 3. スキャンライン (zPosition: 5)
//    高さ 2pt の水平バー × 3 本。独立した速度(60〜120 pt/s)で上から下へループ。

// 4. グリッチフラッシュ (zPosition: 15)
//    画面全体を覆う SKShapeNode。3〜7 秒おきに alpha 0.07 → 0 → 0.04 → 0 と点滅。
```

**SceneKit 背景グリッド実装ガイド**

```swift
// ProjectorBug3DCoordinator.setupScene() に追加
// scnScene.background.contents = UIColor(darkBlueBlack)

// Tron スタイルグリッド床
// SCNPlane(width: 20, height: 20)
// .eulerAngles.x = -.pi / 2  // 水平配置
// .position = SCNVector3(0, -2.8, -3)
// material.diffuse.contents = makeGridTexture(base:line:)

// 背景壁
// SCNPlane(width: 20, height: 12)
// .position = SCNVector3(0, 0, -4)
// material.diffuse.contents = makeGridTexture(base:line:)

// makeGridTexture: UIGraphicsImageRenderer で 512×512 の UIImage を生成。
// セルサイズ 64pt の格子線を描画。
```

**BugHunterScene プロジェクターモード用オーバーレイ**

```swift
// isProjectorMode == true のとき setupBackground() で追加
// グリッドライン: alpha 0.04（ゲームプレイの邪魔にならない最小限）
// スキャンライン: 1本、alpha 0.04、ゆっくり(90秒で1往復程度)
// マトリックスレインは追加しない（3D バグの視認性を損なうため）
```

---

## 既知の制約・注意事項

- `SceneKit` の `SCNView` と `SpriteKit` の `SKView` を重ねるとき、`SKView.allowsTransparency = true` かつ `SKView.isOpaque = false` が必須。
- `WaitingScene` 表示中は `SCNView` に `SCNScene` が設定されていない（または空）。待機中のプロジェクターは SCNView を積極的に使わない。
- `ProjectorBug3DCoordinator` の生成・破棄はシーン遷移ごとに行う。`stopSpawning()` を呼び出してから `nil` にする。
- Multipeer Connectivity のコールバックはバックグラウンドスレッドで届く。UI 操作は必ず `DispatchQueue.main.async`。
- ARKit は実機専用。シミュレーターでは `ARSession` が起動しない。

---

## よく使うコードパターン

### SKAction で無限ループ

```swift
node.run(SKAction.repeatForever(SKAction.sequence([
    SKAction.wait(forDuration: 0.08, withRange: 0.06),
    SKAction.run { [weak self] in self?.doSomething() }
])))
```

### Multipeer メッセージ送信

```swift
let msg = GameMessage.bugCaptured(BugCapturedPayload(bugType: .stag, playerIndex: 1))
let data = try! JSONEncoder().encode(msg)
session.send(data, toPeers: [targetPeer], with: .reliable)
```

### SceneKit 3D → 2D 画面座標変換

```swift
let projected = scnView.projectPoint(SCNVector3(x, y, z))
let screenPoint = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
```
