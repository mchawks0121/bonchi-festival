# ぼんち祭り バグハンター — AI 開発プロンプト

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

| モード | GameMode 列挙値 | 説明 |
|--------|----------------|------|
| スタンドアロン | `.standalone` | 1台の iPhone で完結する AR バグハンター |
| プロジェクター・クライアント | `.projectorClient` | iPhone がコントローラー。スリングショット操作をプロジェクターへ送信 |
| プロジェクター・サーバー | `.projectorServer` | 大画面表示デバイス。最大3台の iPhone を受け付ける |

---

## ファイル構成と責務

```
bonchi-festival/
├── AppDelegate.swift
│     UIWindow を生成し UIHostingController(rootView: ContentView()) をルートに設定。
│     SwiftUI ライフサイクルではなく UIKit AppDelegate ベース。
│
├── ContentView.swift
│     SwiftUI ルートビュー。GameManager を @StateObject で保持。
│     GameManager.state に応じて以下のビューを切り替え（.animation + .transition(.opacity)）:
│       .waiting  → WaitingView
│       .playing  → PlayingView（gameMode が .projectorServer なら ProjectorServerView、それ以外は ARPlayingView）
│       .finished → FinishedView
│
│     サブビュー:
│       WaitingView         — モード選択カード(ModeCard)、接続状態ピル、「デバッグ開始」ボタン、
│                             バグ一覧カード(BugLegendRow)、ミッション説明。compact/regular レイアウト分岐あり。
│       ARPlayingView       — ARGameView（フルスクリーン） + HUD（スコア・タイマー・タイマーバー） + SlingshotView
│       ProjectorServerView — WorldViewControllerWrapper（UIViewControllerRepresentable）+ 戻るボタン
│       FinishedView        — 最終スコア表示・「再デバッグ」ボタン
│       ModeCard            — アイコン・タイトル・サブタイトル付き選択カード。compact/regular でレイアウト変化
│       BugLegendRow        — バグ絵文字・表示名・レアリティ・ポイント・速度ラベルの1行
│       WorldViewControllerWrapper — UIViewControllerRepresentable で WorldViewController をラップ
│
├── Controller/
│   ├── GameManager.swift
│   │     ObservableObject。iOS 側ゲーム全体を管理。
│   │     @Published: state(GameState), score(Int), timeRemaining(Double),
│   │                 isConnected(Bool), gameMode(GameMode), arBugScene(ARBugScene?)
│   │     GameState 列挙: .waiting / .playing / .finished
│   │     GameMode 列挙: .standalone / .projectorClient / .projectorServer
│   │     selectMode(_:) — モード切替。projectorClient 選択時に MultipeerSession.start()
│   │     startGame()    — score=0 reset、ARBugScene 生成（非 projectorServer のみ）、projectorClient は startGame 送信
│   │     resetGame()    — 全状態リセット、projectorClient は resetGame 送信
│   │     sendLaunch(angle:power:) — ARBugScene.fireNet() + projectorClient は launch 送信
│   │     BugHunterSceneDelegate: didUpdateScore/sceneDidFinish — standalone のみスコアを自 state に反映
│   │     MultipeerSessionDelegate: bugCaptured 受信 → score += bugType.points
│   │
│   ├── MultipeerSession.swift
│   │     iOS 側 Multipeer Connectivity ラッパー（NSObject, ObservableObject）。
│   │     serviceType = "bughunter-game"（ProjectorGameManager と一致必須）
│   │     MCSession + MCNearbyServiceAdvertiser + MCNearbyServiceBrowser を同時起動。
│   │     start() / stop() で広告・ブラウジングを制御。
│   │     send(_:) — 全接続ピアへ reliable 送信。
│   │     MultipeerSessionDelegate プロトコル:
│   │       didReceive(message:from:) / peerDidConnect / peerDidDisconnect
│   │     コールバックはすべて DispatchQueue.main.async で配送。
│   │
│   ├── ARGameView.swift
│   │     UIViewRepresentable。UIView コンテナ（=makeUIView の戻り値）に以下を重ねる:
│   │       ARSCNView (背面) — SceneKit で 3D バグを描画。ARWorldTrackingConfiguration 使用。
│   │       SKView (前面, 透過) — ARBugScene を presentScene する。allowsTransparency = true。
│   │     内部 Coordinator クラス (ARSCNViewDelegate):
│   │       startSpawning() / stopSpawning() — standalone のみバグをスポーン
│   │       spawnBug() — カメラ前方 1.2〜2.8m, 水平 ±37°, 垂直オフセット -0.3〜0.45m に ARAnchor 配置
│   │       randomBugType() — butterfly 60% / beetle 30% / stag 10%
│   │       renderer(_:nodeFor:) — ARAnchor → Bug3DNode (SCNNode) + 不可視プロキシ SKNode を生成
│   │       renderer(_:updateAtTime:) — 毎フレーム 3D→2D 変換でプロキシ位置同期、距離ベーススケール
│   │         scale = clamp(referenceDistance(2.0) / distance, 0.3, 3.0)
│   │         cachedViewHeight で UIKit アクセスをメインスレッドに限定
│   │       handleCapture(of:) — capture 時に Bug3DNode.captured() + ARAnchor 削除
│   │     难易度カーブ: nextDelay = max(0.6, 1.8 - spawnElapsed / 75.0)
│   │
│   ├── ARBugScene.swift
│   │     SKScene (backgroundColor = .clear)。照準・ロックオン・捕獲の全 UI を担当。
│   │     public API:
│   │       fireNet(angle:power:) — 2段階当たり判定:
│   │         1. ロックオン (catchRadius=150pt 以内の最近傍 bugContainer)
│   │         2. 弾道判定 (hitBand=90pt × netRange=power×最長辺×0.8+200pt)
│   │         捕獲後 catchBug(container:bugNode:) → onCaptureBug コールバック
│   │     照準クロスヘア: 画面中央固定、crosshairRing (SKShapeNode)
│   │     ロックオンリング: lockOnRing (オレンジ) が最近傍バグの位置に追従
│   │     distortionLayer: グリッチバー × 12本 (赤/紫/シアン/オレンジ)
│   │       バグ数 0→1→2→3+ で alpha 0→38%→66%→100% に遷移
│   │       各バーは独立したランダムフリッカーアクション
│   │
│   ├── Bug3DNode.swift
│   │     SCNNode サブクラス。手続き的 PBR ジオメトリで各バグを表現。
│   │     butterfly (🐞):
│   │       abdomen: SCNCapsule(capRadius:0.009, height:0.048)、茶色 PBR
│   │       upper wings: SCNPlane(0.095×0.070)、monarch オレンジ、半透明、isDoubleSided
│   │       lower wings: SCNPlane(0.065×0.052)、暗いオレンジ
│   │       antennae: SCNCylinder + SCNSphere ball tip
│   │       アニメ: 翼ピボットノード (uwR/uwL/lwR/lwL) の Z 回転フラッピング + 体 Y ドリフト
│   │     beetle (🦠):
│   │       body: SCNSphere(r=0.040) × scale(1.05, 0.68, 1.22)、赤光沢 PBR (roughness:0.14, metalness:0.62)
│   │       suture: SCNCylinder(r=0.0028)、暗赤黒
│   │       thorax + head: addSphere ヘルパー
│   │       compound eyes: 球 × 2
│   │       legs: 3ペア × 2段セグメント (addLeg ヘルパー)
│   │       アニメ: Y 回転 (5.5s) + Z ロック (0.38s サイクル)
│   │     stag (👾):
│   │       body: SCNCapsule(capRadius:0.028, height:0.068)、暗金属 PBR (roughness:0.20, metalness:0.65)
│   │       thorax + head + eyes: addSphere
│   │       mandibles: SCNCapsule × 2 + 内側 SCNCone tooth
│   │       legs: 3ペア × addLeg
│   │       elbowed antennae: SCNCylinder + SCNSphere tip
│   │       アニメ: Y 回転 (7.5s) + X 軸頷き (1.4s サイクル)
│   │     全共通: フェードイン (0.45s) + ホバー (±1.8cm, 0.65〜0.85s サイクル)
│   │     captured(): removeAllActions() + SCNAction.fadeOut(0.05s) → removeFromParentNode
│   │
│   └── SlingshotView.swift
│         SwiftUI フルスクリーンオーバーレイ。DragGesture で操作を検出。
│         フォーク位置: 画面高さの 62% (forkYRatio=0.62)
│         最大ドラッグ距離: 220pt (maxDragDistance)。任意方向スワイプ可。
│         angle = atan2(dragOffset.height, -dragOffset.width)（SpriteKit 座標系に変換）
│         power = min(dragLength / 220, 1.0)
│         SlingshotForkShape — Y 字 Shape（stem + 2本のフォーク）
│         ゴム紐: leftFork → pullPoint と rightFork → pullPoint を Path で描画
│         PowerIndicatorView — 水平バー (緑/黄/赤)、power に応じてリアルタイム更新
│         net 飛翔アニメ: 発射方向に 🕸️ 絵文字が飛ぶ (scale 0.3→1.8→fade, 回転 270°〜810°)
│
├── Shared/
│   └── GameProtocol.swift
│         MessageType: launch / gameState / startGame / resetGame / bugCaptured
│         GameMessage: type + optional payloads (launchPayload, gameStatePayload, bugCapturedPayload)
│         LaunchPayload:      angle(Float), power(Float), timestamp(Double)
│         GameStatePayload:   state(String), score(Int=0), timeRemaining(Double)
│         BugCapturedPayload: bugType(BugType), playerIndex(Int)
│         BugType: butterfly(1pt, speed:110, size:40) / beetle(3pt, speed:70, size:55) / stag(5pt, speed:45, size:70)
│           computed: points / emoji / displayName / speed / size / speedLabel / rarityLabel / lore
│         PhysicsCategory: none(0) / bug(0x1) / net(0x2)
│
└── World/
    ├── WorldViewController.swift
    │     UIViewController。SCNView + SKView + ConnectedPlayersView の配置・管理。
    │     viewDidLayoutSubviews で初回レイアウト後に presentWaitingScene() を呼ぶ。
    │     presentWaitingScene(): bug3DCoordinator?.stopSpawning() → nil、WaitingScene に遷移
    │     startGame(): BugHunterScene(isProjectorMode=true) 生成、ProjectorBug3DCoordinator.attach()+startSpawning()
    │     fireNet(angle:power:playerIndex:): gameScene?.fireNet() に転送
    │     BugHunterSceneDelegate:
    │       didUpdateScore → sendGameState(payload) (score=0 固定)
    │       sceneDidFinish → sendGameState + stopSpawning + 4秒後に presentWaitingScene
    │     ProjectorGameManagerDelegate: startGame/reset/launch/playersUpdate を受信して処理
    │
    │     ─── ProjectorBug3DCoordinator（WorldViewController.swift 内の final class）───
    │       SCNScene に固定パースカメラ（cameraZ=3.5, FOV=65°）を設置。
    │       Bug3DNode を bugScaleMultiplier=10 でスケール拡大して scnView に表示。
    │       毎フレーム scnView.projectPoint() → BugHunterScene 上の不可視プロキシ BugNode 位置を同期。
    │       スポーン: 難易度カーブ max(0.6, 1.8 - spawnElapsed / 75)
    │       捕獲時: Bug3DNode.captured() + プロキシ除去 + onCaptureNotify(bugType, playerIndex) コールバック
    │       attach(to:bugScene:) / startSpawning() / stopSpawning() / updateCachedViewSize(_:)
    │
    ├── WaitingScene.swift
    │     SKScene (backgroundColor = SKColor(red:0.04, green:0.08, blue:0.04, alpha:1) 暗い緑)
    │     タイトル "君は、バグハンター 🦟" (HiraginoSans-W7, 80pt) + パルスアニメ
    │     サブタイトル "You are the Bug Hunter" (W3, 40pt)
    │     浮遊バグ絵文字 (🦋/🐛/🪲 × ポイント表示) — 独立した上下フロートアニメ
    │     接続待ちテキスト (W3, 34pt) — フェードブリンクアニメ
    │     操作説明テキスト (W3, 30pt)
    │
    ├── BugHunterScene.swift
    │     SKScene。isProjectorMode=true のとき backgroundColor=.clear。
    │     physicsWorld.contactDelegate = self（SKPhysicsContactDelegate）。
    │     HUD: timeLabel (残り秒数)、timerBar (SKShapeNode, 最大幅 600pt, 残り時間に比例)
    │     setupBackground(): isProjectorMode=false のとき標準背景を描画
    │     BugSpawner を生成（isProjectorMode のとき spawner.start() は呼ばれない）
    │     update(_:): 時間更新 + timerBar 更新 + gameDelegate?.scene(didUpdateScore:0, timeRemaining:)
    │     endGame(): gameDelegate?.sceneDidFinish(finalScore:0) + 全 BugNode 消去
    │     fireNet(angle:power:playerIndex:): origin = 画面下部中央 → NetProjectile.launch() → シーンに追加
    │     didBegin(contact:): NetProjectile × BugNode 接触 → onBugCaptured?(bugNode, playerIndex)
    │       + Bug3DNode 捕獲アニメ + BugNode 除去 + NetProjectile.playCapture()
    │
    ├── BugSpawner.swift
    │     BugNode をランダムエッジ位置にスポーン。ベジェ曲線パスで移動後 removeFromParent。
    │     elapsed (外部から毎フレーム更新) を使って難易度カーブを適用。
    │     duration = clamp(600 / speed, 3.0, 12.0)
    │
    ├── NetProjectile.swift
    │     SKNode (name="net")。netLabel(🕸️ 64pt) + ringNode(circleOfRadius:34) + centerDot
    │     playerIndex を保持。playerColors[playerIndex % 3] でリング色を決定。
    │     physicsBody: circleOfRadius=44, isDynamic=true, affectedByGravity=false
    │     launch(angle:power:from:sceneSize:):
    │       travelSpeed = power×1400+500 pt/s、travelTime=0.55s
    │       baseMove(easeOut) + arcAction(上昇+下降) + unfurl(scale 0.3→1.3→1.0) + spin(easeOut)
    │       arc 強度 = sceneSize.height×0.06×|cos(angle)|×(power+0.3)
    │       rotation = π×(1.5 + power×2) rad
    │     playCapture(): アクション停止 + physicsBody=nil + pulse + fadeOut → removeFromParent
    │
    └── ProjectorGameManager.swift
          MCSession + MCNearbyServiceAdvertiser + MCNearbyServiceBrowser。
          serviceType = "bughunter-game"
          maxPlayers = 3。usedSlots: Set<Int> で接続上限管理。
          playerSlots: [MCPeerID: Int] で peerID → slot 0/1/2 を管理。
          advertiser: 招待受け入れ時に usedSlots.count < maxPlayers を確認して拒否。
          sendGameState(_:): 全ピアに gameState メッセージを broadcast。
          sendBugCaptured(bugType:toPlayerAtSlot:): 該当スロットの peerID にのみ unicast。
          delegate: ProjectorGameManagerDelegate
            managerDidReceiveStartGame / managerDidReceiveReset / didReceiveLaunch / didUpdateConnectedPlayers
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
    │                                        │  → 対応色の NetProjectile を発射
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

| 種類 | 絵文字 | ポイント | 速度 | フォントサイズ | 出現率 | ロア |
|------|--------|---------|------|--------------|-------|------|
| Null (butterfly) | 🐞 | 1 pt | 110 | 40pt | 60 % | 軽微な未定義参照エラー |
| Virus (beetle) | 🦠 | 3 pt | 70 | 55pt | 30 % | 自己増殖型ランタイムエラー |
| Glitch (stag) | 👾 | 5 pt | 45 | 70pt | 10 % | 致命的なデータ破壊バグ |

---

## ゲームルール

| 項目 | 値 |
|------|---|
| 制限時間 | 90 秒 |
| スポーン間隔 | `max(0.6, 1.8 - elapsed / 75)` 秒 |
| スコア管理 | iOS（クライアント）側のみ。プロジェクターは 0 固定 |
| 最大接続 | 3 台。4 台目以降は拒否 |
| ゲーム終了 | プロジェクターは 4 秒後に自動で WaitingScene へ戻る |

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

- **SCNView.backgroundColor**: `UIColor(red: 0.05, green: 0.12, blue: 0.05, alpha: 1)`（暗い緑）
- **WaitingScene.backgroundColor**: `SKColor(red: 0.04, green: 0.08, blue: 0.04, alpha: 1)`（暗い緑）

---

## プレイヤー色分け

| スロット | 色名 | UIColor (R, G, B) | SKColor |
|---------|------|------------------|---------|
| Player 1 | シアン | (0.0, 1.0, 1.0) | `.cyan` |
| Player 2 | オレンジ | (1.0, 0.55, 0.0) | — |
| Player 3 | マゼンタ | (1.0, 0.2, 0.8) | — |

---

## スコア設計（重要）

1. **プロジェクター側はスコアを一切持たない。** `BugHunterScene` はスコア変数を持たず、`GameStatePayload.score` は常に `0`。
2. バグ捕獲時: `ProjectorGameManager.sendBugCaptured(bugType:toPlayerAtSlot:)` が当該プレイヤーの `MCPeerID` にのみ `bugCaptured` を unicast。
3. iOS 側 `GameManager` が `bugCaptured` を受信し `score += bugType.points`。
4. スタンドアロンモードは `ARBugScene.fireNet` → `BugHunterSceneDelegate` 経由でスコアを更新。
5. **projectorClient モードでは ARBugScene 上にバグがスポーンしない**（Coordinator.startSpawning で `gameMode == .standalone` チェックあり）。スコアは bugCaptured のみで加算。

---

## AR（スタンドアロン・クライアント）の仕組み

```
ARSCNView (3D バグ)
    │ Bug3DNode: SCNNode + 手続き的 PBR ジオメトリ
    │   butterfly: 4枚翅（ピボットノードで羽ばたき）+ 触角
    │   beetle: 光沢ドームウイング + suture + 6脚 + 複眼
    │   stag: 大顎 + 6脚 + elbowed antenna
SKView (透過オーバーレイ)
    └── ARBugScene
        ├── 照準クロスヘア（中央固定）
        ├── ロックオンリング（バグ接近時オレンジ）
        ├── distortionLayer（グリッチバー × 12本、バグ数に比例）
        ├── プロキシ bugContainer SKNode（3D 投影座標に毎フレーム同期）
        └── 捕獲エフェクト
```

- `ARSCNViewDelegate` でカメラ姿勢を毎フレーム取得し、Bug3DNode の 3D 座標を 2D 画面座標に変換してプロキシを移動。
- `cachedViewHeight` でレンダースレッドからの UIKit アクセスを回避。
- 捕獲半径 150pt（`ARBugScene.catchRadius`）、弾道ヒットバンド 90pt。

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

// NetProjectile (circleOfRadius: 44 pt)
physicsBody?.isDynamic          = true
physicsBody?.affectedByGravity  = false
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
| フレームワーク | SwiftUI, UIKit, ARKit, SceneKit, SpriteKit, MultipeerConnectivity, Combine |

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

## 既知の制約・注意事項

- `SCNView` と `SKView` を重ねるとき、`SKView.allowsTransparency = true` かつ `SKView.isOpaque = false` が必須。
- `WaitingScene` 表示中は `SCNView` に `SCNScene` が設定されていない（ProjectorBug3DCoordinator = nil）。
- `ProjectorBug3DCoordinator` の生成・破棄はシーン遷移ごとに行う。`stopSpawning()` を呼び出してから `nil` にする。
- Multipeer Connectivity のコールバックはバックグラウンドスレッドで届く。UI 操作は必ず `DispatchQueue.main.async`。
- ARKit は実機専用。シミュレーターでは `ARSession` が起動しない。
- `ProjectorBug3DCoordinator` は `WorldViewController.swift` 内で `final class` として定義されている（別ファイルではない）。

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

### PBR マテリアル生成（Bug3DNode パターン）

```swift
let m = SCNMaterial()
m.diffuse.contents   = UIColor(red: 0.55, green: 0.08, blue: 0.08, alpha: 1)
m.roughness.contents = NSNumber(value: 0.14)
m.metalness.contents = NSNumber(value: 0.62)
m.lightingModel      = .physicallyBased
```

---

## 未実装タスク

### 1. プロジェクター背景を「腐敗したデジタルワールド」に変更（優先度: 高）

#### 要件

プロジェクターの全画面表示を、**サイバーパンク／腐敗したデジタルワールド**のビジュアルテーマに変更する。  
現在の背景色（暗い緑）から、テーマに合った暗い青黒ベースのデジタル演出に差し替える。

#### 変更対象ファイル

| ファイル | 変更内容 |
|---------|---------|
| `World/WorldViewController.swift` | `scnView.backgroundColor` を暗い青黒 `UIColor(red:0.03, green:0.03, blue:0.10)` に変更。SceneKit シーンに Tron スタイルのグリッド床・背景壁を追加（`SCNPlane` + 手続き生成テクスチャ）。 |
| `World/WaitingScene.swift` | 背景色を暗い青黒に変更。マトリックスレイン（落下する日本語カタカナ/16進数文字）、グリッドライン、スキャンライン、グリッチフラッシュを追加。 |
| `World/BugHunterScene.swift` | `isProjectorMode=false` のとき背景色を暗い青黒に変更。`isProjectorMode=true` のときグリッドライン・スキャンライン（低透明度）を SK オーバーレイに追加（3D バグの視認性を損なわない程度）。 |

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

**SceneKit 背景グリッド実装ガイド（ProjectorBug3DCoordinator の setupScene に追加）**

```swift
// scnScene.background.contents = UIColor(red:0.03, green:0.03, blue:0.10, alpha:1)

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
