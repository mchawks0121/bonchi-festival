# ぼんち祭り バグハンター — 新規プロジェクト作成プロンプト集 (Xcode 26 / iOS 26)

> **対象環境**: Xcode 26 / iOS 26 / Swift 6.0
> **使用 AI**: GitHub Copilot コーディングエージェント（チャット／エージェントモード）
> **目的**: **完全新規プロジェクト**として「ぼんち祭り バグハンター」を環境構築からゼロで作成する

---

## このドキュメントについて

このプロンプト集は「ぼんち祭り バグハンター」を **まっさらな状態から** 完成させるための AI 向け指示書です。
既存コードの移行や修正ではなく、**新規 Xcode プロジェクトの作成から始めて** 各ファイルを順番に実装していきます。

### チームでの運用ルール

1. **各プロンプトは 1PR = 1ファイル（または 1機能）の単位で使う**。
   まとめて投げると差分が大きくなりレビューが困難になります。

2. **プロンプトを投げる前に `SPEC.md` と `PROMPT.md` を Copilot のコンテキストに含める**。
   GitHub Copilot エージェントモードでは「Add Files」で両ファイルをピン留めしてから依頼する。

3. **AI の出力は必ず人間がレビューしてからマージする**。
   特に `BugType` switch の網羅性・`@MainActor` / `Sendable` 準拠を確認する。

4. **マージ後は `SPEC.md` / `PROMPT.md` を変わった仕様に合わせて更新する**。

---

## 実装順序（全体ロードマップ）

```
Phase 0 — 環境構築・プロジェクト作成（1週目）
  └─ P-00: Xcode 26 インストール & 新規プロジェクト作成

Phase 1 — 共有型定義（1〜2週目）
  └─ P-01: Shared/GameProtocol.swift — BugType・メッセージ型の全定義

Phase 2 — アプリ基盤（2週目）
  ├─ P-02: AppDelegate.swift — UIKit エントリーポイント
  └─ P-03: Controller/GameManager.swift — ゲーム状態管理

Phase 3 — 通信層（2〜3週目、Phase 1 完了後）
  ├─ P-04: Controller/MultipeerSession.swift — iOS 側 Multipeer ラッパー
  └─ P-05: World/ProjectorGameManager.swift — プロジェクター側 Multipeer ラッパー

Phase 4 — AR コア（3〜5週目、Phase 1 完了後）
  ├─ P-06: Controller/Bug3DNode.swift — RealityKit 3D バグエンティティ
  ├─ P-07: Controller/ARBugScene.swift — SpriteKit 透過照準 UI
  ├─ P-08: Controller/ARGameView.swift — ARView + SKView 重ね合わせ
  ├─ P-09: Controller/SlingshotNode.swift — 3D スリングショット表示
  ├─ P-10: Controller/Net3DNode.swift — 3D 飛翔網メッシュ
  └─ P-11: Controller/SlingshotView.swift — SwiftUI スリングショット UI

Phase 5 — サウンド（3〜4週目）
  └─ P-12: Controller/SoundManager.swift — 手続き型サウンドエフェクト

Phase 6 — UI 全画面（4〜6週目、Phase 2 完了後）
  └─ P-13: ContentView.swift — 全画面実装（WaitingView / CalibrationView / ARPlayingView / FinishedView）

Phase 7 — プロジェクター側（4〜6週目、Phase 3 完了後）
  ├─ P-14: World/BugHunterScene.swift & World/NetProjectile.swift — プロジェクター用 SKScene
  └─ P-15: World/WorldViewController.swift — プロジェクター UIViewController

Phase 8 — 統合・QA（7〜9週目）
  ├─ P-16: Swift Testing スイート構築
  └─ P-17: パフォーマンス最適化 & メモリリーク修正
```

> **ブロッカー**: P-00 が完了しない限り後続は着手不可。最優先で対処すること。
> **並行作業可**: Phase 3（通信層）と Phase 4（AR コア）は Phase 1 完了後に並行して進められます。

---

---

## Phase 0 — 環境構築・プロジェクト作成

### P-00: Xcode 26 インストール & 新規プロジェクト作成

**担当**: プロジェクトリード（全員が環境を揃える）
**ブランチ名例**: `chore/project-setup`

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
Xcode 26 で「ぼんち祭り バグハンター」の新規 iOS プロジェクトを作成し、
ディレクトリ構造・プロジェクト設定・Info.plist・Capabilities を整えてください。
これは既存プロジェクトの移行ではなく、完全な新規作成です。

## 目的（Why）
祭り会場でのリアルタイムデモに向け、Xcode 26 / iOS 26 / Swift 6.0 の
最新スタックで開発環境を整備します。新規プロジェクトから始めることで
レガシーコードによる混乱を排除し、クリーンな状態でチーム開発を開始します。

## 機能概要（What）

### 1. 新規プロジェクト作成
- テンプレート: iOS App（SwiftUI / UIKit App Delegate）
- Product Name: bonchi-festival
- Bundle Identifier: com.mchreo0121.bonchi-festival
- Swift Language Version: Swift 6
- Interface: SwiftUI
- Life Cycle: UIKit App Delegate
- Deployment Target: iOS 26.0

### 2. ディレクトリ構造作成
bonchi-festival/
├── AppDelegate.swift
├── ContentView.swift
├── Controller/        ← グループ追加
├── Shared/            ← グループ追加
└── World/             ← グループ追加

Xcode 上でグループを Controller・Shared・World の 3 つ作成する
各グループは実際のフォルダ（Group with folder）として作成する

### 3. Swift 6 Strict Concurrency 設定
Build Settings で以下を設定:
- SWIFT_VERSION = 6.0
- SWIFT_STRICT_CONCURRENCY = complete

### 4. Info.plist 必須エントリ
NSCameraUsageDescription: AR でバグを捕獲するためにカメラが必要です
NSLocalNetworkUsageDescription: プロジェクターと接続するためにローカルネットワークが必要です
NSBonjourServices: _bughunter-game._tcp, _bughunter-game._udp

### 5. Frameworks 追加（Frameworks, Libraries, and Embedded Content）
- ARKit.framework
- RealityKit.framework
- SpriteKit.framework
- MultipeerConnectivity.framework
- AVFoundation.framework

### 6. 動作確認
xcodebuild -scheme bonchi-festival -destination 'platform=iOS Simulator,name=iPhone 16' build
ビルドエラー・警告ゼロを確認する

## 実装方針（How）
- Xcode の File > New > Project から iOS App テンプレートを選択する
- プロジェクト作成後、SceneDelegate.swift が生成された場合は削除し、UIKit AppDelegate のみ残す
- ViewController.swift や Main.storyboard が生成された場合も削除する
- ContentView.swift のデフォルト内容は後で P-13 で置き換えるので、今は Text("Hello") のままで OK

## 制約・注意点
- SceneKit は使用しない。3D は RealityKit のみ使用する
- 外部ライブラリ（CocoaPods・SPM パッケージ）は使用しない
- nonisolated(unsafe) は使用禁止

## セキュリティ考慮点
- NSCameraUsageDescription は必ず適切な日本語説明を入れること
- Bundle Identifier はリリース前に実際の Apple Developer Account のものに変更すること

## コメント要件
- 実装意図（なぜこの設定を選んだか）
- セキュリティ・スレッドセーフの考慮点
```

---

---

## Phase 1 — 共有型定義

### P-01: Shared/GameProtocol.swift

**担当**: チームC（通信エンジニア）
**ブランチ名例**: `feat/shared-game-protocol`
**前提**: P-00 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
Shared/GameProtocol.swift を新規作成してください。
iOS 側とプロジェクター側で共有する全型定義を実装します。

## 目的（Why）
MultipeerConnectivity を使った iOS ↔ プロジェクター間通信で使う型を
一か所にまとめ、変更に強く型安全なプロトコル基盤を構築します。
Swift 6 の strict concurrency に対応するため、全型を Sendable 準拠にします。

## 機能概要（What）

### BugType enum
- butterfly: Null バグ。1pt, speed=110, size=40, emoji="🐞", rarity="Common"
- beetle: Virus バグ。3pt, speed=70, size=55, emoji="🦠", rarity="Rare"
- stag: Glitch バグ。5pt, speed=45, size=70, emoji="👾", rarity="Epic"

以下の computed property を全て実装すること:
- points: Int
- emoji: String
- displayName: String
- speed: CGFloat
- size: CGFloat
- speedLabel: String
- rarityLabel: String
- lore: String（各バグの説明文）

switch は必ず exhaustive（default: なし）

### MessageType enum
- launch, startGame, resetGame, bugSpawned, bugRemoved, gameState, bugCaptured
- Codable & Sendable 準拠

### Payload 構造体（全て Codable & Sendable）
- LaunchPayload: angle(Float), power(Float), timestamp(Double)
- BugSpawnedPayload: id(String), bugType(BugType), normalizedX(Float), normalizedY(Float)
- BugRemovedPayload: id(String)
- BugCapturedPayload: bugType(BugType), playerIndex(Int)  ← 後方互換用
- GameStatePayload: state(String), score(Int), timeRemaining(Double)  ← 後方互換用

### GameMessage enum
- Codable & Sendable 準拠
- ケース: launch(LaunchPayload), startGame, resetGame, bugSpawned(BugSpawnedPayload),
         bugRemoved(BugRemovedPayload), bugCaptured(BugCapturedPayload), gameState(GameStatePayload)
- encode() -> Data? メソッドを実装する
- static func decode(from: Data) -> GameMessage? メソッドを実装する
- JSON には type キー（MessageType の rawValue）とペイロードを含める

### PhysicsCategory 構造体（Sendable）
- none: UInt32 = 0
- bug: UInt32 = 0x1 << 0
- net: UInt32 = 0x1 << 1

### サービス定数
- static let serviceType = "bughunter-game"

## 実装方針（How）
- 全定義を 1 つの Shared/GameProtocol.swift にまとめる
- GameMessage の Codable 実装は手書き（CodingKeys + init(from:) + encode(to:)）で行う
- encode() は try? JSONEncoder().encode(self) でシンプルに実装する

## 制約・注意点
- BugType の switch は exhaustive（default: なし）
- nonisolated(unsafe) は使用禁止
- NSLock は使用しない

## セキュリティ考慮点
- Multipeer で受け取った Data は必ず decode(from:) を通してから使用する
- デコード失敗時は安全に nil を返す（強制アンラップ禁止）

## コメント要件
- Sendable: MultipeerConnectivity のコールバックスレッドを越えて安全に渡すため というコメントを各型の宣言直前に追加すること
- BugType の各 case に ポイント / 速度 / ゲームデザイン上の役割 コメントを入れること
```

---

---

## Phase 2 — アプリ基盤

### P-02: AppDelegate.swift

**担当**: チームA（ARエンジニア）
**ブランチ名例**: `feat/app-delegate`
**前提**: P-00 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
AppDelegate.swift を新規作成してください。UIKit App Delegate ベースのエントリーポイントです。

## 目的（Why）
SwiftUI App プロトコルではなく UIKit AppDelegate を使うことで、
ARKit セッションやウィンドウを細かく制御できます。

## 機能概要（What）
@main アノテーション付き AppDelegate クラスを実装すること:
- UIWindow を生成し、UIHostingController(rootView: ContentView()) をルートに設定
- window.makeKeyAndVisible() を呼ぶ

## 制約・注意点
- @main アノテーションは AppDelegate にのみ付与する
- SwiftUI の @main struct App: App と共存しないこと
- SceneDelegate.swift は作成しない（UISceneDelegate は不要）

## コメント要件
- UIKit AppDelegate: ARKit セッションとウィンドウを直接管理するため SwiftUI App プロトコルは使用しない というコメントを先頭に入れること
```

---

### P-03: Controller/GameManager.swift

**担当**: チームA（ARエンジニア）
**ブランチ名例**: `feat/game-manager`
**前提**: P-01, P-02 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
Controller/GameManager.swift を新規作成してください。
iOS 側ゲーム全体の状態管理を担う ObservableObject です。

## 目的（Why）
SwiftUI の @StateObject として全画面から参照される中央状態管理オブジェクトです。
GameState と GameMode の状態機械を実装します。

## 機能概要（What）

### 列挙体
- GameState: waiting, calibrating, ready, playing, finished
- GameMode: standalone, projectorClient, projectorServer

### @Published プロパティ
- state: GameState = .waiting
- score: Int = 0
- timeRemaining: Double = 90.0
- isConnected: Bool = false
- gameMode: GameMode = .standalone
- arBugScene: ARBugScene? = nil

### その他のプロパティ
- worldOriginTransform: simd_float4x4? = nil
- slingshotDragUpdate: ((CGSize, Bool) -> Void)? = nil
- onNetFired: ((CGSize, Float) -> Void)? = nil
- private let multipeerSession = MultipeerSession()

### 主要メソッド（全て実装すること）
- selectMode(_:): gameMode を切替。.projectorClient 選択時に multipeerSession.start()
- startCalibration(): .projectorServer 以外は state = .calibrating。.projectorServer は直接 startGame()
- setWorldOrigin(transform:): worldOriginTransform = transform; state = .ready
- confirmReady(): .ready → startGame()
- startGame(): score=0 / timeRemaining=90 リセット; .projectorServer 以外は ARBugScene 生成; multipeerSession.send(.startGame())
- resetGame(): 全状態リセット; worldOriginTransform=nil; slingshotDragUpdate=nil; onNetFired=nil; multipeerSession.send(.resetGame())
- sendLaunch(angle:power:): arBugScene?.fireNet(angle:power:) + multipeerSession.send(.launch(...))
- sendBugSpawned(id:type:normalizedX:normalizedY:): multipeerSession.send(.bugSpawned(...))（モード判定なし）
- sendBugRemoved(id:): multipeerSession.send(.bugRemoved(...))（モード判定なし）

### BugHunterSceneDelegate 実装
- didUpdateScore(_:timeRemaining:): self.score = score; self.timeRemaining = timeRemaining
- sceneDidFinish(_:finalScore:): self.score = finalScore; state = .finished

### MultipeerSessionDelegate 実装
- peerDidConnect(_:): isConnected = true
- peerDidDisconnect(_:): isConnected = (session.connectedPeers.count > 0)
- didReceive(message:from:) の .bugCaptured: score += bugType.points（後方互換）

## 実装方針（How）
- @MainActor final class GameManager: ObservableObject で宣言する
- MultipeerSession は初期化時に生成しデリゲートとして自身を登録する
- sendBugSpawned/sendBugRemoved は接続なし時も呼ぶ（no-op になるだけ）

## セキュリティ考慮点
- worldOriginTransform はキャリブレーション確定後にのみ設定し、resetGame() でクリアする
- デバイスカメラのトランスフォームを外部に送信しないこと

## コメント要件
- @MainActor の理由: @Published プロパティをメインスレッドで安全に更新するため
- 各メソッドに実装意図コメントを入れること
```

---

---

## Phase 3 — 通信層

### P-04: Controller/MultipeerSession.swift

**担当**: チームC（通信エンジニア）
**ブランチ名例**: `feat/multipeer-session`
**前提**: P-01 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
Controller/MultipeerSession.swift を新規作成してください。
iOS 側の MultipeerConnectivity ラッパーです。

## 目的（Why）
iPhone とプロジェクターを同一 LAN 上で自動接続し、
ゲームメッセージをリアルタイムに双方向通信します。
Swift 6 の @MainActor で Multipeer コールバックのスレッドセーフ性を保証します。

## 機能概要（What）

### クラス定義
@MainActor final class MultipeerSession: NSObject, ObservableObject
- static let serviceType = "bughunter-game"（ProjectorGameManager と一致させること）
- weak var delegate: (any MultipeerSessionDelegate)?

### 初期化
- MCPeerID(displayName: UIDevice.current.name) でローカルピア作成
- MCSession(peer:securityIdentity:encryptionPreference: .required) を初期化（暗号化必須）
- MCNearbyServiceAdvertiser, MCNearbyServiceBrowser を初期化

### 主要メソッド
- start(): Advertiser.startAdvertisingPeer() + Browser.startBrowsingForPeers()
- stop(): 両方停止 + session.disconnect()
- send(_ message: GameMessage): 全接続ピアへ .reliable で JSON 送信（接続なし時は no-op）

### MultipeerSessionDelegate プロトコル（このファイルで定義）
@MainActor protocol MultipeerSessionDelegate: AnyObject
- didReceive(message: GameMessage, from peer: MCPeerID)
- peerDidConnect(_ peer: MCPeerID)
- peerDidDisconnect(_ peer: MCPeerID)

### スレッド処理
- MCSessionDelegate 等のコールバックは nonisolated で受け取り
- Task { @MainActor in ... } でメインスレッドに切り替える

## 制約・注意点
- MCPeerID は @unchecked Sendable として扱う（Apple の制約）
- send() のエラーは try? で握りつぶしてよい
- 最大3台の制限は ProjectorGameManager 側で行う

## セキュリティ考慮点
- encryptionPreference: .required を MCSession に設定すること

## コメント要件
- nonisolated を使う箇所に「MCSession コールバックはメインスレッド外で呼ばれるため nonisolated」コメントを入れること
- Task { @MainActor in } に「メインアクターに切り替えて @Published プロパティを安全に更新」コメントを入れること
```

---

### P-05: World/ProjectorGameManager.swift

**担当**: チームB（プロジェクターエンジニア）
**ブランチ名例**: `feat/projector-game-manager`
**前提**: P-01 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
World/ProjectorGameManager.swift を新規作成してください。
プロジェクター側の Multipeer Connectivity ラッパーです。

## 目的（Why）
プロジェクター側で最大3台の iPhone 接続を管理し、
受信したゲームメッセージを WorldViewController に伝えます。

## 機能概要（What）

### クラス定義
@MainActor final class ProjectorGameManager: NSObject
- static let serviceType = "bughunter-game"（MultipeerSession と必ず一致）
- static let maxPlayers = 3
- weak var delegate: (any ProjectorGameManagerDelegate)?
- private(set) var connectedPeers: [MCPeerID] = []

### ProjectorGameManagerDelegate プロトコル（このファイルで定義）
@MainActor protocol ProjectorGameManagerDelegate: AnyObject
- didReceive(message: GameMessage, from peer: MCPeerID, playerIndex: Int)
- playerDidConnect(peer: MCPeerID, playerIndex: Int)
- playerDidDisconnect(peer: MCPeerID, playerIndex: Int)

### 主要メソッド
- start(): Advertiser + Browser 開始
- stop(): 停止
- playerIndex(for peer:) -> Int: peerID から 0-based のプレイヤー番号を返す

### 接続制限
- connectedPeers.count >= 3 のとき新規接続要求を拒否する

## 制約・注意点
- nonisolated + Task { @MainActor in } パターンで安全に処理する
- encryptionPreference: .required で暗号化すること

## コメント要件
- 3台制限ロジックに「最大接続台数 3 台に達した場合は接続を拒否する」コメントを入れること
```

---

---

## Phase 4 — AR コア

### P-06: Controller/Bug3DNode.swift

**担当**: チームA（ARエンジニア）
**ブランチ名例**: `feat/bug-3d-node`
**前提**: P-01 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
Controller/Bug3DNode.swift を新規作成してください。
RealityKit Entity ラッパーとして 3D バグモデルを表示します。

## 目的（Why）
AR 空間に浮かぶ 3D バグを表示するコンポーネントです。
USDZ モデルを優先使用し、存在しない場合は手続き的 PBR ジオメトリにフォールバックします。

## 機能概要（What）

### クラス定義
@MainActor final class Bug3DNode
- let type: BugType
- var entity: Entity（RealityKit エンティティ）
- var worldPosition: SIMD3<Float>（毎フレーム ARView.project で使用）

### USDZ モデルマッピング（変更禁止）
- butterfly: toy_biplane.usdz, usdzScale=0.005
- beetle: gramophone.usdz, usdzScale=0.004
- stag: toy_drummer.usdz, usdzScale=0.004

USDZファイルは Apple AR Quick Look ギャラリーから取得。不在時は手続き的ジオメトリにフォールバック。

### actor BugAssetCache（内部クラス）
// Swift 6 actor: NSLock より型安全にスレッドセーフなキャッシュを実現する
private actor BugAssetCache:
- static let shared = BugAssetCache()
- private var cache: [String: Entity] = [:]
- func load(named name: String) async throws -> Entity（キャッシュヒット時はそのまま返す）
- func preload(names: [String]) async（withTaskGroup で並行ロード）

### static func preloadAssets()
Task { await BugAssetCache.shared.preload(names: ["toy_biplane.usdz", "gramophone.usdz", "toy_drummer.usdz"]) }
ARGameView.makeUIView と WorldViewController.viewDidLoad の両方から呼ばれる。

### init(type:)
- await BugAssetCache.shared.load(named:) で Entity を取得してクローン
- availableAnimations を再帰探索して最初のアニメーションを .infinity でループ再生
- USDZ ロード失敗時は手続き的ジオメトリを生成する

### フォールバックジオメトリ（USDZ なし時）
- butterfly: 4 枚翅（半透明シアン）+ 球形胴体 + 触角、ホバーアニメーション
- beetle: 光沢ドーム甲殻（黒/緑）+ 6 脚、回転アニメーション
- stag: 大顎 + 胴体 + 6 脚（茶）、頷きアニメーション

### captured() メソッド
0.2 秒かけてスケールを 0 に縮小するアニメーションを再生して entity を削除する

## 制約・注意点
- BugType の switch は exhaustive（default: なし）
- SceneKit（SCNNode 等）は使用しない。RealityKit（Entity, AnchorEntity）のみ使用
- actor 外から Entity を直接変更しない（actor 内でクローンを作って返す）

## セキュリティ考慮点
- USDZ ファイルはプロジェクトバンドル内のもののみロードする（外部 URL からのロード禁止）

## コメント要件
- actor の各メソッドに「actor: NSLock より型安全。Swift 6 strict concurrency 準拠」コメントを入れること
```

---

### P-07: Controller/ARBugScene.swift

**担当**: チームA（ARエンジニア）
**ブランチ名例**: `feat/ar-bug-scene`
**前提**: P-01 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
Controller/ARBugScene.swift を新規作成してください。
AR 映像の上に重ねる透過 SpriteKit シーンです。

## 目的（Why）
ARView は 3D バグの表示を担いますが、2D の照準 UI・捕獲アニメーション・スコア表示は
SpriteKit の方が実装が容易です。透過背景の SKView を ARView の前面に重ねて実現します。

## 機能概要（What）

### クラス定義
@MainActor final class ARBugScene: SKScene
- static let catchRadius: CGFloat = 150
- private static let distortionPerBug: CGFloat = 0.50（BugHunterScene=0.38 とは意図的に異なる値）
- var onBugCaptured3D: ((SKNode) -> Void)?
- var onCaptureBug: ((SKNode) -> Void)?
- weak var gameDelegate: (any BugHunterSceneDelegate)?
- private var score: Int = 0

### BugHunterSceneDelegate プロトコル（このファイルで定義）
@MainActor protocol BugHunterSceneDelegate: AnyObject
- func didUpdateScore(_ score: Int, timeRemaining: Double)
- func sceneDidFinish(_ scene: ARBugScene, finalScore: Int)

### 照準ノード（backgroundColor = .clear で透過シーン）
- crosshairRing: SKShapeNode(circleOfRadius: 54), シアン(0.2,1.0,0.8,0.85), lineWidth=2.5
  アイドルパルスアニメ: scale 1.07→1.0（0.85s サイクル）
- lockOnRing: SKShapeNode(circleOfRadius: 58), オレンジ, lineWidth=3.5, alpha=0（非表示）
- 中央ドット: SKShapeNode(circleOfRadius: 5), fill=シアン
- 4方向ティック: gap=64pt, length=14pt, シアン, lineWidth=2.5

### distortionLayer（グリッチ演出）
- 全体ティント: SKColor(0.55, 0.0, 0.55, 0.07), zPosition=-1
- 12 本のバー（高さ3〜14pt）: 赤/紫/シアン/オレンジ各3本
- 各バー独立フリッカーアニメ
- updateDistortion(bugCount:): alpha = min(count × 0.50, 1.0), duration=0.6s

### fireNet(angle:power:)
当たり判定 2 段階:
1. catchRadius(150pt) 以内の最近傍 bugContainer をロックオン対象とする
2. ロックオンなし時は弾道判定（hitBand=90pt, netRange=power×max(W,H)×0.8+200pt）
→ SoundManager.shared.playThrow()
→ playNetThrowAnimation(toward: flyTarget)
→ catchBug または playMissAnimation

### catchBug(container:bugNode:)
PROMPT.md の ARBugScene.catchBug セクションの詳細仕様を参照して実装すること:
- 0.20s 後: onBugCaptured3D コールバック
- 3層 net エンタングルメント
- ヒールリップル（シアン）
- 画面フラッシュ
- スコアポップアップ
- 照準フラッシュ（緑）
- 1.2s 後: onCaptureBug?(container)
- score += pts

### ゲームタイマー
- startGame(): timeRemaining = 90, タイマー開始
- 残り0秒で endGame() を呼ぶ
- didUpdateScore(_:timeRemaining:) を毎秒呼ぶ

### endGame()
- 全 bugContainer フェードアウト + remove
- distortionLayer フェードアウト
- 黒半透明全画面をフェードイン
- gameDelegate?.sceneDidFinish(self, finalScore: score)

## 制約・注意点
- バグの SKNode コンテナ名を "bugContainer" で統一する
- ARAnchor 削除（onCaptureBug）は 1.2s 後に行う

## コメント要件
- distortionPerBug = 0.50 に「ARBugScene.distortionPerBug=0.50 / BugHunterScene=0.38（プロジェクター画面の視認性最適化のため異なる値）」コメントを入れること
```

---

### P-08: Controller/ARGameView.swift

**担当**: チームA（ARエンジニア）
**ブランチ名例**: `feat/ar-game-view`
**前提**: P-03, P-06, P-07 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
Controller/ARGameView.swift を新規作成してください。
UIView コンテナに ARView（背面）+ SKView（前面・透過）を重ね合わせる UIViewRepresentable です。

## 目的（Why）
RealityKit の ARView で 3D バグを AR 空間に表示し、前面に透過 SpriteKit シーン（ARBugScene）を
重ねて 2D UI を表示します。毎フレーム 3D→2D 座標変換でプロキシ位置を同期します。

## 機能概要（What）

### makeUIView レイヤー構成
UIView (container, UIScreen.main.bounds)
├── ARView (autoresizingMask: flexible, 背面)
│     autoenablesDefaultLighting = true
│     automaticallyUpdatesLighting = true
│     antialiasingMode = .multisampling4X
│     scene.lightingEnvironment.intensity = 1.5
│     config = ARWorldTrackingConfiguration()
└── SKView (autoresizingMask: flexible, 前面)
      backgroundColor = .clear, isOpaque = false, allowsTransparency = true

makeUIView で Bug3DNode.preloadAssets() を呼び出すこと。

### Coordinator クラス
@MainActor final class Coordinator: NSObject, ARSessionDelegate

スポーン定数（変更禁止）:
- minSpawnDistance: Float = 0.5
- maxSpawnDistance: Float = 1.4
- horizontalAngleRange: ClosedRange<Float> = -0.65...0.65
- verticalOffsetRange: ClosedRange<Float> = -0.30...0.45
- referenceDistance: Float = 3.0
- minBugScale: Float = 0.3
- maxBugScale: Float = 5.0
- maxActiveBugs: Int = 5

アンカー辞書（@MainActor 隔離でロック不要）:
- bugAnchorMap: [UUID: BugType] = [:]
- anchorBug3DNodeMap: [UUID: Bug3DNode] = [:]
- anchorProxyNodeMap: [UUID: SKNode] = [:]
- nodeAnchorMap: [ObjectIdentifier: ARAnchor] = [:]

### startSpawning()
1. gameMode == .projectorServer → 即 return
2. stopSpawning() → アンカー辞書を全クリア
3. ensureSlingshotAttached()
4. arBugScene?.onBugCaptured3D / onCaptureBug コールバック登録
5. scheduleNextSpawn(delay: 0.9) で初回スポーンを予約

### spawnBug()
- currentBugCount >= 5 → 1.0s 後に再試行
- スポーン位置: PROMPT.md の spawnBug セクションの座標変換式を参照
- gameManager?.worldOriginTransform ?? frame.camera.transform を基準にワールド座標を決定
- randomBugType(): butterfly 60% / beetle 40%（stag は除外）
- 難易度カーブ: nextDelay = max(1.5, 3.5 - spawnElapsed / 75.0)

### 毎フレーム処理（SceneEvents.Update）
1. slingshotNode 位置更新
2. cachedIsDragging に応じて SlingshotNode.updateDrag / resetDrag 呼び出し
3. 各 Bug3DNode の 3D→2D 座標変換:
   scale = clamp(referenceDistance(3.0) / distance, 0.3, 5.0)
   projected = arView.project(bug3D.worldPosition)
   skPoint = (projected.x, cachedViewHeight - projected.y)
   projected.z が 0〜1 の範囲内のみ更新

### launchNet3D(dragOffset:power:)
PROMPT.md の launchNet3D セクションの定数を使用:
- maxDrag=300, forkCam=(0,-0.12,-0.28,1)
- normX = Float(-dragOffset.width / 300)
- normY = Float(dragOffset.height / 300)
- direction = normalize(fwd + right * normX * 0.35 + up * normY * 0.35)

## 制約・注意点
- ARSessionDelegate のコールバックは nonisolated で受け取り Task { @MainActor in } でディスパッチ
- gameMode == .projectorServer の場合は早期 return
- cachedViewHeight は @MainActor var で UIKit アクセスをメインスレッドに限定する

## コメント要件
- nonisolated を使う箇所に理由コメントを必ず入れること
- スポーン定数の各値に用途コメントを入れること
```

---

### P-09: Controller/SlingshotNode.swift

**担当**: チームA（ARエンジニア）
**ブランチ名例**: `feat/slingshot-node`
**前提**: P-06 と同一 Phase

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
Controller/SlingshotNode.swift を新規作成してください。
ARView のカメラ空間に固定表示される 3D スリングショットモデルです。

## 目的（Why）
プレイヤーが常に手に持っているように見える 3D Y 字スリングショットを
カメラ空間に固定表示します。

## 機能概要（What）

### クラス定義
@MainActor final class SlingshotNode
- var entity: Entity（ARView の pointOfView にアタッチする）

### ジオメトリ（全て手続き的生成・USDZ なし）
- Y 字フォーク: 2本の fork arm（茶色 PBR マテリアル）+ グリップ棒
- ゴム紐左右: 細い cylinder
- 網ポーチ: 緑色の小さな球

### updateDrag(offset: CGSize, maxDrag: CGFloat)
- ドラッグ量（最大 300pt）に応じてポーチと左右ゴム紐を変形する
- offset.width → 左右、offset.height → 上下に変位

### resetDrag()
- ポーチとゴム紐をニュートラル位置に戻す

## 制約・注意点
- SceneKit（SCNNode）は使用しない。RealityKit（Entity, ModelEntity）で実装する
- カメラ空間への追加は ARGameView.Coordinator.ensureSlingshotAttached() が行う

## コメント要件
- クラス先頭に「@MainActor: RealityKit Entity の変更はメインスレッドで行う必要があるため」コメントを入れること
```

---

### P-10: Controller/Net3DNode.swift

**担当**: チームA（ARエンジニア）
**ブランチ名例**: `feat/net-3d-node`
**前提**: P-06 と同一 Phase

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
Controller/Net3DNode.swift を新規作成してください。
ARView に配置される 3D 飛翔網メッシュです。

## 目的（Why）
スリングショットから発射される 3D 網を AR 空間で可視化します。
複数プレイヤーの網を色で識別します。

## 機能概要（What）

### クラス定義
@MainActor final class Net3DNode
- let playerIndex: Int（色分け用: 0=シアン, 1=オレンジ, 2=マゼンタ）
- var entity: Entity

### 網ジオメトリ（手続き的生成）
- セグメントリム（円周フレーム）: 16分割
- 8 本のスポーク（中心→外周）
- 同心リング × 3
- playerIndex に対応した色:
  - 0: シアン (0.0, 1.0, 1.0)
  - 1: オレンジ (1.0, 0.55, 0.0)
  - 2: マゼンタ (1.0, 0.2, 0.8)

### launch(from:direction:power:completion:)
- from: SIMD3<Float>（発射起点）
- direction: SIMD3<Float>（正規化済み発射方向）
- power: Float（0.0〜1.0）
- completion: (() -> Void)?（entity 削除用）
- power と direction に応じた速度で entity を飛翔させる
- 到達後フェードアウト（0.3s）して completion を呼ぶ

## 制約・注意点
- launch のシグネチャは変更しない（ARGameView.Coordinator から呼ばれるため）
- SceneKit は使用しない（RealityKit のみ）

## コメント要件
- @MainActor の理由をクラス先頭コメントに記載すること
- playerIndex の色分け表を定数のコメントに記載すること
```

---

### P-11: Controller/SlingshotView.swift

**担当**: チームA（ARエンジニア）
**ブランチ名例**: `feat/slingshot-view`
**前提**: P-03 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の SwiftUI エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
Controller/SlingshotView.swift を新規作成してください。
フルスクリーンオーバーレイとしてスリングショットのジェスチャを管理する SwiftUI View です。

## 目的（Why）
3D 描画（SlingshotNode / Net3DNode）とジェスチャ管理を分離することで、
SwiftUI のジェスチャ認識と RealityKit のレンダリングを干渉なく共存させます。

## 機能概要（What）

### SlingshotView
- DragGesture(minimumDistance: 5) でスワイプを検出する
- ドラッグ中: gameManager.slingshotDragUpdate?(offset, true) を呼ぶ
- ドラッグ終了: gameManager.slingshotDragUpdate?(offset, false) + 発射判定
  - magnitude > 30pt の場合のみ gameManager.sendLaunch(angle:power:) を呼ぶ
  - power = min(dragOffset.magnitude, 300) / 300（0〜1 に正規化）
- gameManager.state == .playing のときのみドラッグを有効にする

### PowerIndicatorView
- 引き量を表示するインジケーター（2D 描画のみ）
- ドラッグ中のみ表示
- 引き量に応じて色変化（低=緑, 中=黄, 高=赤）

### 定数
static let maxDragDistance: CGFloat = 300  // ARGameView.launchNet3D の maxDrag と一致させること

## 制約・注意点
- 3D 描画はしない（このファイルには 2D 描画のみ）
- gameManager.state != .playing のときはジェスチャを完全に無視する

## コメント要件
- maxDragDistance = 300 に「ARGameView.launchNet3D の maxDrag と一致」コメントを入れること
```

---

---

## Phase 5 — サウンド

### P-12: Controller/SoundManager.swift

**担当**: チームC（通信エンジニア）
**ブランチ名例**: `feat/sound-manager`
**前提**: P-00 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
Controller/SoundManager.swift を新規作成してください。
外部音声ファイルを使わず PCM 波形をランタイム生成する AVAudioEngine ベースのサウンドマネージャーです。

## 目的（Why）
祭り会場では音声ファイルの管理が煩雑になります。
PCM サイン波バッファをコードで生成することで、音声ファイル依存ゼロの実装を実現します。

## 機能概要（What）

### クラス定義
// 外部音声ファイル不要: PCM サイン波バッファをランタイム生成することで、音声アセット管理を不要にする
@MainActor final class SoundManager
- static let shared = SoundManager()
- private let engine = AVAudioEngine()
- private var playerPool: [AVAudioPlayerNode] = []（6ノードプール）

### 実装するメソッド
- playThrow(): 短い swoosh 音（サイン波 400→200Hz, 0.15s）
- playCapture(points: Int): pts==5 は高音、それ以外は成功音
- playMiss(): 低音の buzz（200Hz, 0.1s）
- playLockOn(): 短い ping（800Hz, 0.08s）
- playGameStart(): 上昇音（300→900Hz, 0.3s）
- playGameEnd(): 下降音（500→100Hz, 0.5s）

### PCM バッファ生成
private func makeBuffer(startFreq: Float, endFreq: Float, duration: Float, amplitude: Float) -> AVAudioPCMBuffer
- AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) を使用
- 周波数を startFreq から endFreq にリニアスイープする
- サンプル値: sin(2π × instantFreq × sampleIndex / 44100) × amplitude

### ノードプールの管理
- 6 つの AVAudioPlayerNode を engine に接続してプールに入れる
- 再生時は最初の非再生ノードを使用する
- 全ノード使用中の場合は最も古いノードを stop して再利用する

## 制約・注意点
- 外部 .mp3 / .wav ファイルは一切使用しない
- AVAudioEngine.start() は init() 内で呼ぶ
- エラーは try? で握りつぶしてゲーム進行を止めない

## コメント要件
- 各 play メソッドに周波数・音の特性コメントを入れること
```

---

---

## Phase 6 — UI 全画面

### P-13: ContentView.swift

**担当**: チームC（UI エンジニア）
**ブランチ名例**: `feat/content-view`
**前提**: P-03 完了（GameManager）, P-07 完了（ARBugScene 参照のため）

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の SwiftUI エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
ContentView.swift を新規作成してください。
ゲーム全画面の SwiftUI ルートビューと、全サブビューを実装します。

## 目的（Why）
GameManager.state に応じて画面を切り替えるルートビューと、
各ゲーム画面（WaitingView / CalibrationView / ARPlayingView / FinishedView）を実装します。
iOS 26 の Liquid Glass デザインを採用します。

## 機能概要（What）

### 設計トークン（ファイル先頭に定義・変更禁止）
private let accentCyan  = Color(red: 0.20, green: 1.00, blue: 0.80)
private let accentBlue  = Color(red: 0.10, green: 0.60, blue: 1.00)
private let bgTop       = Color(red: 0.03, green: 0.04, blue: 0.10)
private let bgBottom    = Color(red: 0.00, green: 0.00, blue: 0.00)

### ContentView（ルート）
GameManager を @StateObject で保持。state に応じて画面切り替え:
- .animation(.easeInOut(duration: 0.35)) + .transition(.opacity) を使用
- .waiting: WaitingView
- .calibrating: CalibrationView
- .ready, .playing: gameMode == .projectorServer → ProjectorServerView / それ以外 → ARPlayingView
- .finished: FinishedView

### WaitingView
- 背景: LinearGradient(colors:[bgTop, bgBottom], startPoint:.top, endPoint:.bottom)
- HeroLogo コンポーネント（ゲームタイトル）
- ModeCard × 3（standalone / projectorClient / projectorServer）
  各カードをタップで gameManager.selectMode(_:) を呼ぶ
  選択中: accentCyan 枠線 + .glassBackground(.tinted)（iOS 26 Liquid Glass）
  未選択: .glassBackground()（iOS 26 Liquid Glass）
  compact 時（高さ<750pt）: 横スクロール ScrollView / regular 時: 縦 ScrollView
- 接続状態ピル: isConnected=true → シアン / false → グレー
- 「バグ狩り開始」ボタン（accentCyan）:
  projectorServer → gameManager.startGame() / それ以外 → gameManager.startCalibration()
- BugLegendRow × 3（.glassBackground() カード）

ModeCard コンポーネント:
- アイコン + タイトル + サブタイトル
- standalone: "📱 スタンドアロン" / projectorClient: "🎮 コントローラー" / projectorServer: "📺 プロジェクター"

BugLegendRow コンポーネント:
- bugType.emoji + displayName + rarityLabel + points + speedLabel

### CalibrationView（UIViewRepresentable）
UIView (container)
├── ARView (fullscreen) — ARWorldTrackingConfiguration で AR セッション開始
└── UIView (overlay) — @available(iOS 26, *) UIGlassEffect / フォールバック UIVisualEffectView
    ├── 照準レティクル（CAShapeLayer: 十字 + 円、中央固定）
    ├── 説明ラベル（上部）
    ├── 「基準点を設定」UIButton → confirmTapped → gameManager.setWorldOrigin(transform:)
    └── 「戻る」UIButton → backTapped → gameManager.resetGame()

CalibrationCoordinator:
- confirmTapped(): 多重押下防止 + arView.session.currentFrame?.camera.transform 取得
  → キャリブレーション AR セッションを pause() → delegate 解放 → gameManager.setWorldOrigin(transform:)
- backTapped(): 同様にセッション停止 → gameManager.resetGame()

### ARPlayingView
ZStack:
- ARGameView() (ignoresSafeArea)
- if state == .ready: ReadyOverlay (allowsHitTesting: false)
- if state == .playing: HUD（スコア + タイマーバー）← .glassEffect() / .glassBackground() 使用
- SlingshotView()

HUD:
- スコアパネル: .glassEffect() 付き RoundedRectangle + accentCyan テキスト
- タイマーバー: 残り30s以上→accentCyan / 10〜29s→.yellow / 10s未満→.red
- allowsHitTesting(false) を維持

ReadyOverlay: 「スリングショットを引いて網を射出するとゲームスタート！」。.glassBackground() 角丸パネル。

### ProjectorServerView
WorldViewControllerWrapper (UIViewControllerRepresentable) をフルスクリーン表示
左上に戻るボタン（gameManager.resetGame() を呼ぶ）

### FinishedView
- 最終スコアを大きく表示（accentCyan）+ .glassBackground() カードパネル
- 「再デバッグ」ボタン（.glassBackground(.interactive)）→ gameManager.resetGame()
- 背景: LinearGradient(bgTop → bgBottom)

## 制約・注意点
- .ready と .playing は同じ ARPlayingView ケースにまとめて ARGameView インスタンスを維持する
- BugType の switch は exhaustive に保つ

## コメント要件
- .glassBackground() を追加した箇所に「// iOS 26 Liquid Glass: システムマテリアルでカード背景を統一」コメントを入れること
- .glassEffect() の箇所に「// iOS 26 Liquid Glass: AR 映像背景への可読性を自動最適化」コメントを入れること
```

---

---

## Phase 7 — プロジェクター側

### P-14: World/BugHunterScene.swift & World/NetProjectile.swift

**担当**: チームB（プロジェクターエンジニア）
**ブランチ名例**: `feat/bug-hunter-scene`
**前提**: P-01, P-05 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
World/BugHunterScene.swift と World/NetProjectile.swift を新規作成してください。
プロジェクター側の SpriteKit シーンと網エフェクトです。

## 目的（Why）
プロジェクターの SKView 上に透過 SpriteKit シーンを重ね、
各プレイヤーの網アニメーションを大画面に表示します。
タイマーやスコアはスマホ側が管理するため、このシーンはビジュアルのみを担います。

## 機能概要（What）

### BugHunterScene（SKScene）
@MainActor final class BugHunterScene: SKScene
- var isProjectorMode: Bool = false { didSet { backgroundColor = isProjectorMode ? .clear : .black } }
- private static let distortionPerBug: CGFloat = 0.38
  // ARBugScene.distortionPerBug=0.50 とは意図的に異なる（プロジェクター画面の視認性最適化）

fireNet(angle:power:playerIndex:):
- playerIndex に対応した色の NetProjectile を生成
- arc 軌道で飛翔させる（ビジュアルのみ・当たり判定なし）

### NetProjectile（SKNode サブクラス）
@MainActor final class NetProjectile: SKNode
- let playerIndex: Int
- 描画: 🕸️ ラベルノード + プレイヤーカラーのリングノード + 中心ドット
- arc 軌道: SKAction.follow(path:, asOffset:, orientToPath:, duration:)
- 回転アニメーション: SKAction.rotate

## 制約・注意点
- isProjectorMode = true のとき backgroundColor = .clear にする
- タイマー・スコア管理はしない（スマホ側が主導）

## コメント要件
- distortionPerBug = 0.38 に「// ARBugScene.distortionPerBug=0.50 とは意図的に異なる（プロジェクター画面の視認性最適化）」コメントを入れること
```

---

### P-15: World/WorldViewController.swift

**担当**: チームB（プロジェクターエンジニア）
**ブランチ名例**: `feat/world-view-controller`
**前提**: P-05, P-06, P-14 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
World/WorldViewController.swift を新規作成してください。
プロジェクター側のルート UIViewController と、3D バグ管理コーディネーターを実装します。

## 目的（Why）
ARView（非ARモード）+ SKView 透過オーバーレイで大画面にゲームを表示します。
最大3台の iPhone から Multipeer で受信したバグ情報を元に 3D バグを配置し、
自律スポーンでバグを常時表示します。

## 機能概要（What）

### WorldViewController
@MainActor final class WorldViewController: UIViewController
- private let bugScaleMultiplier: Float = 10  // プロジェクター: 大画面に映えるよう iPhone の10倍スケールで表示
- PerspectiveCameraComponent(fieldOfViewInDegrees: 65)（変更禁止）

レイアウト:
self.view
├── ARView (cameraMode: .nonAR, fullscreen, 背面)
└── SKView (fullscreen, 前面)
      isOpaque = false, backgroundColor = .clear
      scene = BugHunterScene(isProjectorMode: true)
右下: ConnectedPlayersView（接続中プレイヤー情報パネル）

viewDidLoad での初期化:
1. Bug3DNode.preloadAssets() 呼び出し
2. ARView・SKView セットアップ
3. ProjectorGameManager 初期化・start() 呼び出し
4. startGame() 直接呼び出し（初回スポーン開始）

### ProjectorBug3DCoordinator（内部クラス）
@MainActor final class ProjectorBug3DCoordinator
- bug3DNodes: [String: Bug3DNode]（Multipeer スポーン）
- autonomousBugs: [Bug3DNode]（自律スポーン）

### startAutonomousSpawning()
// Swift 6: DispatchQueue.main.asyncAfter の代わりに async/await で実装
Task { @MainActor in
    while !Task.isCancelled {
        spawnAutonomousBug()
        try? await Task.sleep(for: .seconds(4.0))
    }
}

### ProjectorGameManagerDelegate 実装
- .bugSpawned: coordinator.addBug(id:type:normalizedX:normalizedY:)
- .bugRemoved: coordinator.removeBug(id:) → Bug3DNode.captured() アニメ
- .launch: bugHunterScene?.fireNet(angle:power:playerIndex:)
- .startGame / .resetGame: バグを全削除
- playerDidConnect / playerDidDisconnect: connectedPlayersView.update(players:)

## 制約・注意点
- ARView(cameraMode: .nonAR) — プロジェクターはカメラ映像不要
- bugScaleMultiplier = 10 は変更しない
- 自律スポーン（autonomousBugs）と Multipeer スポーン（bug3DNodes）を分離して管理する

## コメント要件
- startAutonomousSpawning() の Task ループに「// Swift 6: DispatchQueue.main.asyncAfter の代わりに async/await で実装」コメントを入れること
- bugScaleMultiplier = 10 に「// プロジェクター: 大画面に映えるよう iPhone の10倍スケールで表示」コメントを入れること
```

---

---

## Phase 8 — 統合・QA

### P-16: Swift Testing スイート構築

**担当**: 横断 QA（全チームから兼任）
**ブランチ名例**: `test/swift-testing-suite`
**前提**: P-01〜P-15 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の QA エンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
Xcode 26 の Swift Testing フレームワークを使って、主要ロジックのユニットテストを構築してください。

## 目的（Why）
Swift Testing（import Testing）は Xcode 26 のデフォルトテストフレームワークです。
#expect / @Test / @Suite マクロで読みやすいテストを記述し、リグレッションを防ぎます。

## テスト対象

### BugTypeTests.swift
- BugType.allCases が butterfly / beetle / stag の3ケースを持つことを確認
- butterfly.points == 1, beetle.points == 3, stag.points == 5 を確認
- BugType が Codable で正しく JSON エンコード/デコードできることを確認

### GameMessageTests.swift
- GameMessage.bugSpawned(...) が正しく JSON にエンコードされることを確認
- JSON → GameMessage のデコードが正しく動作することを確認
- 不正な JSON でのデコードが nil を返すことを確認

### SpawnIntervalTests.swift
- スポーン間隔計算式 max(1.5, 3.5 - elapsed / 75) を検証:
  - elapsed=0 → 3.5秒
  - elapsed=75 → 1.5秒
  - elapsed=150 → 1.5秒（最短値でクランプ）

## 実装方針
- import Testing を使う（XCTest は不要）
- @Test / @Suite / #expect / #require マクロを使う
- テストは bonchi-festivalTests/ ディレクトリに追加する

## 制約・注意点
- ARKit / RealityKit を使うコード（ARGameView、Bug3DNode 等）はモックが必要なため除外する

## コメント要件
- 各テストスイートの先頭に「// Swift Testing: Xcode 26 でデフォルトのテストフレームワーク」コメントを入れること
```

---

### P-17: パフォーマンス最適化 & メモリリーク修正

**担当**: チームA + チームB（ARエンジニア + プロジェクターエンジニア）
**ブランチ名例**: `perf/optimize-memory-and-framerate`
**前提**: P-06〜P-15 完了、実機テスト後

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift パフォーマンスエンジニアです。
SPEC.md と PROMPT.md の内容をコンテキストとして参照してください。

## タスク
以下のパフォーマンス改善を実施してください。実機 Instruments での計測結果を元に
最も効果の大きい箇所から着手します。

## 目的（Why）
本番（ぼんち祭り）は屋外でのリアルタイムデモのため、フレームレート安定性が最重要です。
USDZ モデルのクローン生成・SpriteKit の毎フレーム投影計算がボトルネックになる可能性があります。

## 改善対象

### 1. USDZ クローン生成の最適化（Bug3DNode）
- BugAssetCache.load(named:) のキャッシュヒット率を確認し、ミス時のログを追加する
- クローン生成時の availableAnimations の再帰探索を最適化する（深さ制限を設ける）

### 2. 毎フレーム投影計算の最適化（ARGameView.Coordinator）
- SceneEvents.Update のコールバック内で projectPoint が呼ばれる回数を
  maxActiveBugs (=5) 回以内に制限する
- MainActor.run を使用してプロキシ位置更新をバッチ処理する

### 3. SpriteKit distortionLayer の最適化（ARBugScene）
- distortionLayer のフリッカーアクションを SKAction.sequence で事前生成し、
  バグ数が変わったときのみ updateDistortion(bugCount:) を呼ぶ
- update(_:) での currentBugCount 計算を差分更新に変更する

## 計測方法
- Instruments → Time Profiler でボトルネック特定
- Instruments → Leaks で Bug3DNode / AnchorEntity のリーク確認
- Xcode 26 の Memory Graph デバッガーでリテインサイクル確認

## 制約・注意点
- maxActiveBugs = 5 / スポーン間隔の定数は変更しない
- パフォーマンス改善のために機能を削除しない（当たり判定ロジックは維持）
- 変更後は P-16 のテストケースがすべてパスすることを確認する

## コメント要件
- 最適化した箇所に「// Perf: [改善内容] — Instruments で確認済み」コメントを入れること
```

---

---

## チーム間の同期ルール

### 週次同期ミーティング（2週目以降必須）

| 確認項目 | 担当 |
|---------|------|
| 前週の PR マージ状況 | プロジェクトリード |
| Swift 6 コンパイルエラー残数 | 全チーム |
| 実機テスト結果（AR精度・接続安定性） | QA |
| 次週の PR 計画（1PR = 1機能） | 全チーム |
| SPEC.md / PROMPT.md 更新漏れチェック | プロジェクトリード |

### PR 作成チェックリスト

PR を出す前に以下を確認すること:

- [ ] Swift 6 strict concurrency ビルドエラーゼロ
- [ ] BugType の switch がすべて exhaustive（default: ケースなし）
- [ ] 新規コードに実装意図コメント・スレッドセーフコメントあり
- [ ] SPEC.md / PROMPT.md の更新も同一 PR に含めた
- [ ] 実機（iOS 26 デバイス）でのビルド・動作確認済み
- [ ] セルフレビュー禁止（別メンバーのレビュー必須）

### ブランチ戦略

main
├── develop          ← チーム統合ブランチ
│   ├── feat/xxx     ← 各機能ブランチ（P-01 〜 P-17 に対応）
│   ├── fix/xxx      ← バグ修正
│   └── perf/xxx     ← パフォーマンス改善
└── release/v1.0     ← RC ブランチ

main への直接プッシュ禁止。必ず develop を経由する。

---

## よくある AI 生成コードの問題と対処法

| 問題 | 対処法 |
|------|-------|
| BugType switch に default: が追加される | 削除して exhaustive switch に修正。新しいケース追加時はコンパイルエラーで検知できる |
| nonisolated(unsafe) が使われる | @MainActor + Task パターンに書き直す |
| SceneKit の SCNNode / ARSCNView が生成される | このプロジェクトは RealityKit を使用。ARView / Entity / AnchorEntity に修正する |
| 外部ライブラリ（CocoaPods / SPM）を追加しようとする | 標準フレームワークのみ使用。追加しないよう再指示する |
| DispatchQueue.main.async で @Published を更新している | @MainActor 隔離 + MainActor.run { } に変更 |
| Entity.loadAsync のコールバック型が古い | async throws で await Entity.load(named:) を使う |
| 音声ファイル（.mp3/.wav）を追加しようとする | SoundManager は PCM バッファをコード生成する。音声ファイルは不要 |
| SceneDelegate.swift を生成する | このプロジェクトは UIKit AppDelegate のみ使用。SceneDelegate は削除する |
