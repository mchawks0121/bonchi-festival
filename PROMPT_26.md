# ぼんち祭り バグハンター — AI 開発プロンプト集 (Xcode 26 / iOS 26)

> **対象環境**: Xcode 26 / iOS 26 / Swift 6.0  
> **使用 AI**: GitHub Copilot コーディングエージェント（チャット／エージェントモード）

---

## ▶ このドキュメントの使い方

### チームでの運用ルール

1. **各プロンプトは 1PR = 1機能 の単位で使う**。  
   プロンプトを分割しているのは差分を小さく保つためです。まとめて投げないこと。

2. **プロンプトを投げる前に `SPEC.md` と `PROMPT.md` を Copilot のコンテキストに含める**。  
   GitHub Copilot エージェントモードでは「Add Files」で両ファイルをピン留めしてから依頼する。

3. **AIの出力は必ず人間がレビューしてからマージする**。  
   特に `BugType` switch の網羅性・`@MainActor` / `Sendable` 準拠・`#available` ガードを確認する。

4. **マージ後は `SPEC.md` / `PROMPT.md` をそのプロンプトで変わった仕様に合わせて更新する**。

---

## ▶ プロンプトを投げる順番（全体ロードマップ）

```
Phase 0 — 環境整備（全員・1週目）
  └─ P-00: iOS 26 / Xcode 26 ビルド確認 & Swift 6 strict concurrency 対応

Phase 1 — 基盤（チームC・2〜3週目）
  ├─ P-01: Shared/GameProtocol — Sendable 準拠
  └─ P-02: MultipeerSession — actor 化

Phase 2 — ARコア（チームA・2〜5週目、Phase 1 と並行）
  ├─ P-03: Bug3DNode — actor キャッシュ化 & iOS 26 RealityKit 対応
  ├─ P-04: ARGameView — @MainActor Coordinator & Liquid Glass 無関係なAR確認
  └─ P-05: SlingshotNode / Net3DNode — Swift 6 対応

Phase 3 — プロジェクター（チームB・2〜5週目、Phase 1 と並行）
  ├─ P-06: WorldViewController / ProjectorBug3DCoordinator — @MainActor 化
  └─ P-07: BugHunterScene — SKScene Swift 6 対応

Phase 4 — UI / UX（チームC・4〜7週目）
  ├─ P-08: WaitingView — Liquid Glass ModeCard
  ├─ P-09: ARPlayingView HUD — Liquid Glass タイマーバー & スコア
  └─ P-10: FinishedView / CalibrationView — Liquid Glass ポリッシュ

Phase 5 — 統合・QA（全員・8〜11週目）
  ├─ P-11: SoundManager — @MainActor & iOS 26 AVAudioEngine 確認
  └─ P-12: Swift Testing スイート構築

Phase 6 — パフォーマンス & RC（全員・12〜13週目）
  └─ P-13: パフォーマンス最適化 & メモリリーク修正
```

> **並行作業可**: Phase 2 と Phase 3 は Phase 1 の P-01 完了後に並行して進められます。  
> **ブロッカー**: P-00 が通らない限り後続はすべて着手不可。最優先で対処すること。

---

---

## Phase 0 — 環境整備

### P-00: iOS 26 / Xcode 26 ビルド確認 & Swift 6 strict concurrency 対応

**担当**: 全チーム（プロジェクトリードが実施して結果を共有）  
**マイルストーン**: M0（5/2）  
**ブランチ名例**: `chore/xcode26-swift6-build`

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
コンテキストとして SPEC.md と PROMPT.md の内容を参照してください。

## タスク
このプロジェクトを Xcode 26 / iOS 26 / Swift 6.0 でビルドできるように修正してください。

## 目的（Why）
iOS 26 / Xcode 26 への移行に伴い、Swift 6 の strict concurrency チェックがデフォルトで有効になります。
既存コードにはコンパイルエラーや警告が多数出る可能性があるため、先行してクリーンアップします。

## 機能概要（What）
1. `SWIFT_STRICT_CONCURRENCY = complete` の状態でビルドエラーをゼロにする
2. `nonisolated(unsafe)` は使用禁止。`@MainActor` / `actor` / `Sendable` で正しく対応する
3. Deployment Target を iOS 26.0 に変更する（`project.pbxproj` の `IPHONEOS_DEPLOYMENT_TARGET`）
4. Swift 6.0 でビルドが通ることを確認する（シミュレーターで起動確認）

## 実装方針（How）
- まず `xcodebuild -scheme bonchi-festival -destination 'generic/platform=iOS' build` を実行してエラー一覧を出力する
- エラーを `Sendable 非準拠`・`@MainActor 違反`・`actor isolation 違反` の3カテゴリに分類する
- `GameProtocol.swift` の `BugType` / `GameMessage` に `Sendable` を追加するところから着手する
- 各ファイルの修正は小さい差分で、ファイルごとに個別 PR とする

## 制約・注意点
- `BugType` の switch は必ず exhaustive（網羅的）に保つ。`default:` ケースを追加しない
- SceneKit は使用しない。3D 処理はすべて RealityKit（`ARView`, `AnchorEntity`, `Entity`）で行う
- `NSLock` は暫定的に残してよいが、新規コードには使わない

## コメント要件
生成するコードには必ず以下のコメントを含めること:
- 実装意図（なぜ @MainActor / actor を選んだか）
- セキュリティ・スレッドセーフの考慮点
- iOS 26 固有の変更点（`// iOS 26:` プレフィックス）
```

---

---

## Phase 1 — 基盤

### P-01: Shared/GameProtocol — Sendable 準拠

**担当**: チームC（通信エンジニア）  
**マイルストーン**: M1（5/16）  
**ブランチ名例**: `feat/game-protocol-sendable`  
**前提**: P-00 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
コンテキストとして SPEC.md と PROMPT.md の内容を参照してください。

## タスク
`Shared/GameProtocol.swift` を Swift 6 strict concurrency に準拠させてください。

## 目的（Why）
Swift 6 では、Multipeer Connectivity のコールバック（別スレッド）から渡される型が
`Sendable` でないとコンパイルエラーになります。`GameMessage` / `BugType` 等の共有型を
`Sendable` 準拠にすることで、iOS ↔ プロジェクター通信のスレッドセーフ性を型レベルで保証します。

## 機能概要（What）
1. `BugType` enum に `Sendable` 準拠を追加（`CaseIterable, Codable, Sendable`）
2. `GameMessage` / `LaunchPayload` / `BugSpawnedPayload` / `BugRemovedPayload` /
   `BugCapturedPayload` / `GameStatePayload` に `Sendable` 準拠を追加
3. `MessageType` enum に `Sendable` を追加
4. `PhysicsCategory` 構造体に `Sendable` を追加

## 実装方針（How）
- 全型は `struct` または `enum` なので `Sendable` 準拠は `extension` で追加するのが最小差分
- `Codable` と `Sendable` は両立可能。既存の JSON エンコード/デコードロジックは変更しない
- `BugType.points` / `BugType.speed` 等の computed property は変更しない

## 制約・注意点
- `BugType` の switch は exhaustive に保つ。`default:` を追加しない
- 既存の `static let serviceType` 等の定数は変更しない
- `nonisolated(unsafe)` は使用禁止

## コメント要件
- `// Sendable: MultipeerConnectivity のコールバックスレッドを越えて安全に渡すため` のような意図コメントを各型の宣言直前に追加すること
```

---

### P-02: MultipeerSession — actor 化

**担当**: チームC（通信エンジニア）  
**マイルストーン**: M1（5/16）  
**ブランチ名例**: `feat/multipeer-session-actor`  
**前提**: P-01 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
コンテキストとして SPEC.md と PROMPT.md の内容を参照してください。

## タスク
`Controller/MultipeerSession.swift` を Swift 6 の `@MainActor` クラスに移行してください。

## 目的（Why）
現在の `MultipeerSession` は `NSObject, ObservableObject` として実装されており、
`MCSession` のデリゲートコールバックが任意スレッドで呼ばれます。
Swift 6 では `@Published` プロパティへのスレッド外アクセスがエラーになるため、
クラス全体を `@MainActor` に隔離して安全にします。

## 機能概要（What）
1. クラス宣言に `@MainActor` を付与する（`@MainActor final class MultipeerSession`）
2. `MCSessionDelegate` / `MCNearbyServiceAdvertiserDelegate` / `MCNearbyServiceBrowserDelegate` の
   コールバックを `Task { @MainActor in ... }` でラップしてメインスレッドに届ける
3. `send(_ message: GameMessage)` を `async throws` にする（既存の `try? data` は `try` に変更）
4. `delegate` プロパティの型を `(any MultipeerSessionDelegate)?` に変更（Swift 6 existential syntax）

## 実装方針（How）
- `MCSession` の `session(_:peer:didChange:)` / `session(_:didReceive:fromPeer:)` は
  `nonisolated` で受け取り、`Task { @MainActor in self.handleXxx() }` でディスパッチする
- `start()` / `stop()` は既存のシグネチャを維持する
- `MultipeerSessionDelegate` プロトコルのメソッドは `@MainActor` アノテーションを付与する

## 制約・注意点
- `MCPeerID` は `Sendable` 非準拠なので `@unchecked Sendable` として扱う箇所に注意コメントを残す
- `ObservableObject` は維持する（`GameManager` が `@StateObject` で保持しているため）
- プロジェクター側の `ProjectorGameManager.swift` との API 対称性を崩さない

## コメント要件
- `nonisolated` を使う箇所に `// MCSession コールバックはメインスレッド外で呼ばれるため nonisolated` コメントを入れること
- `Task { @MainActor in }` の箇所に `// メインアクターに切り替えて @Published プロパティを安全に更新` コメントを入れること
```

---

---

## Phase 2 — ARコア

### P-03: Bug3DNode — actor キャッシュ化 & iOS 26 RealityKit 対応

**担当**: チームA（ARエンジニア）  
**マイルストーン**: M1〜M2  
**ブランチ名例**: `feat/bug3d-node-actor-cache`  
**前提**: P-01 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
コンテキストとして SPEC.md と PROMPT.md の内容を参照してください。

## タスク
`Controller/Bug3DNode.swift` の USDZ アセットキャッシュを `actor BugAssetCache` に移行し、
iOS 26 / RealityKit 3 に対応させてください。

## 目的（Why）
現在の `Bug3DNode` は `NSLock` + `[String: Entity]` のキャッシュを使っていますが、
Swift 6 では `NSLock` によるロックが `Sendable` 違反になり得ます。
`actor` を使うことで、USDZ の非同期ロードと Entity のクローンをスレッドセーフかつ
型安全に扱えるようにします。

## 機能概要（What）
1. `private actor BugAssetCache` を新規定義する
   - `private var cache: [String: Entity] = [:]`
   - `func load(named name: String) async throws -> Entity`（キャッシュヒット時はそのまま返す）
   - `func preload(names: [String]) async` — 全 USDZ を並行ロード（`async let` / `TaskGroup` 使用）
2. `Bug3DNode.preloadAssets()` を `Task { await BugAssetCache.shared.preload(...) }` に変更
3. `Bug3DNode` の初期化処理で `await cache.load(named:)` を使うように変更
4. iOS 26 で `Entity.load(named:)` のシグネチャが変わっている場合は新 API に合わせる

## 実装方針（How）
- `BugAssetCache` は `static let shared = BugAssetCache()` のシングルトン
- `preload` は `withTaskGroup` で 3 USDZ を並行ロードし、完了を `await` で待つ
- USDZ が存在しない場合の手続き的ジオメトリ（PBR フォールバック）のパスは維持する
- `usdzScale(for:)` の exhaustive switch は変更しない

## USDZ マッピング（変更禁止）
| BugType | USDZ ファイル | スケール |
|---------|-------------|--------|
| butterfly | `toy_biplane.usdz` | 0.005 |
| beetle | `gramophone.usdz` | 0.004 |
| stag | `toy_drummer.usdz` | 0.004 |

## 制約・注意点
- `BugType` の switch は exhaustive に保つ
- `actor` の外から `Entity` を変更してはいけない（`actor` 内でクローンを作って返す）
- `playAnimation` のアニメーションループは変更しない

## コメント要件
- actor の各メソッドに `// なぜ actor を選んだか`（= NSLock より型安全、Swift 6 準拠）のコメントを入れること
```

---

### P-04: ARGameView — @MainActor Coordinator & スポーンロジック確認

**担当**: チームA（ARエンジニア）  
**マイルストーン**: M1〜M2  
**ブランチ名例**: `feat/ar-game-view-main-actor`  
**前提**: P-02, P-03 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
コンテキストとして SPEC.md と PROMPT.md の内容を参照してください。

## タスク
`Controller/ARGameView.swift` の `Coordinator` クラスを Swift 6 の `@MainActor` クラスに移行してください。

## 目的（Why）
`Coordinator` は `ARSessionDelegate` として `ARFrame` を受け取り、プロキシ SKNode の位置更新を
メインスレッドで行います。Swift 6 では `@Published` へのクロスアクセスがエラーになるため、
`Coordinator` 全体を `@MainActor` に隔離して安全にします。

## 機能概要（What）
1. `Coordinator` クラス宣言に `@MainActor` を付与する
2. `ARSessionDelegate` のコールバック（`session(_:didAdd:)` 等）を `nonisolated` で受け取り、
   `Task { @MainActor in }` でディスパッチする
3. `SceneEvents.Update` のサブスクリプションはすでに `@MainActor` なので変更不要
4. 4つのアンカー辞書（`bugAnchorMap`, `anchorBug3DNodeMap`, `anchorProxyNodeMap`, `nodeAnchorMap`）の
   `mapLock: NSLock` を削除し、`@MainActor` による隔離で代替する
5. `cachedViewHeight` は `@MainActor var` に変更して OK（読み取りはすでにメインスレッド）

## 定数（変更禁止）
```
minSpawnDistance   = 0.5
maxSpawnDistance   = 1.4
referenceDistance  = 3.0
minBugScale        = 0.3
maxBugScale        = 5.0
maxActiveBugs      = 5
```

## 制約・注意点
- `ARView` / `ARWorldTrackingConfiguration` は iOS 26 でも変更なし（互換維持）
- `SKView` の透過オーバーレイ構成（ARView 背面 + SKView 前面）は変更しない
- `Bug3DNode.preloadAssets()` の呼び出しは `makeUIView` で維持する
- `gameMode == .projectorServer` の早期 return ロジックは変更しない

## コメント要件
- `nonisolated` を使う箇所と `Task { @MainActor in }` の箇所に理由コメントを必ず追加すること
- `// iOS 26: NSLock を @MainActor 隔離で置換` のようにバージョン文脈を明示すること
```

---

### P-05: SlingshotNode / Net3DNode — Swift 6 対応

**担当**: チームA（ARエンジニア）  
**マイルストーン**: M2  
**ブランチ名例**: `feat/slingshot-net-swift6`  
**前提**: P-03 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
コンテキストとして SPEC.md と PROMPT.md の内容を参照してください。

## タスク
`Controller/SlingshotNode.swift` と `Controller/Net3DNode.swift` を Swift 6 対応にしてください。

## 目的（Why）
両ファイルは RealityKit Entity をラップするクラスですが、Swift 6 では
Entity の変更をメインスレッド以外から行うとコンパイルエラーになります。
`@MainActor` アノテーションで適切に隔離します。

## 機能概要（What）
### SlingshotNode.swift
1. `SlingshotNode` クラスに `@MainActor` を付与する
2. `updateDrag(offset:maxDrag:)` / `resetDrag()` はすでにメインスレッドから呼ばれるので変更最小限
3. USDZ を使わず手続き的に生成しているジオメトリ（ModelEntity）は変更しない

### Net3DNode.swift
1. `Net3DNode` クラスに `@MainActor` を付与する
2. `launch(from:direction:power:completion:)` の completion ハンドラーが
   メインスレッドで呼ばれることをコメントで明示する
3. フェードアウトアニメーション（`AnimationTimingFunction`）は iOS 26 でも互換維持

## 制約・注意点
- 描画メッシュ（セグメントリム + 8スポーク + 同心リング）の定数は変更しない
- `playerIndex` による色分けロジックは変更しない
- `launch` メソッドのシグネチャは変更しない（`ARGameView.Coordinator` から呼ばれるため）

## コメント要件
- `@MainActor` を付与した理由を各クラスの先頭コメントに記載すること
```

---

---

## Phase 3 — プロジェクター

### P-06: WorldViewController / ProjectorBug3DCoordinator — @MainActor 化

**担当**: チームB（プロジェクターエンジニア）  
**マイルストーン**: M1〜M2  
**ブランチ名例**: `feat/world-vc-main-actor`  
**前提**: P-01 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
コンテキストとして SPEC.md と PROMPT.md の内容を参照してください。

## タスク
`World/WorldViewController.swift` と `ProjectorBug3DCoordinator`（同ファイル内）を
Swift 6 の `@MainActor` クラスに移行してください。

## 目的（Why）
`ProjectorBug3DCoordinator` は `ProjectorGameManagerDelegate` として Multipeer Connectivity の
コールバック（任意スレッド）で呼ばれます。Swift 6 では RealityKit Entity の変更を
メインスレッド外から行うとエラーになるため、`@MainActor` で保護します。

## 機能概要（What）
1. `WorldViewController` に `@MainActor` を付与する（`UIViewController` サブクラスはデフォルト @MainActor だが明示する）
2. `ProjectorBug3DCoordinator` に `@MainActor` を付与する
3. `ProjectorGameManagerDelegate` のコールバックを `nonisolated` で受け取り、
   `Task { @MainActor in }` でディスパッチする
4. `autonomousBugs: [Bug3DNode]` と `bug3DNodes: [String: Bug3DNode]` は
   `@MainActor` 隔離によりロック不要になるので既存の同期コードを整理する
5. `startAutonomousSpawning()` は `Task { @MainActor in while ... { await Task.sleep(...) } }` に変更する

## 制約・注意点
- `ARView(cameraMode: .nonAR)` の構成は変更しない（プロジェクターは非AR モード）
- `bugScaleMultiplier = 10` は変更しない
- `PerspectiveCameraComponent(fieldOfViewInDegrees: 65)` の設定は変更しない
- `Bug3DNode.preloadAssets()` の呼び出しは `viewDidLoad` で維持する
- 自律スポーン（`autonomousBugs`）と Multipeer スポーン（`bug3DNodes`）の分離を維持する

## コメント要件
- `startAutonomousSpawning()` の Task-based ループに `// iOS 26: DispatchQueue.main.asyncAfter を Task.sleep に置換` コメントを入れること
```

---

### P-07: BugHunterScene — SKScene Swift 6 対応

**担当**: チームB（プロジェクターエンジニア）  
**マイルストーン**: M2  
**ブランチ名例**: `feat/bug-hunter-scene-swift6`  
**前提**: P-06 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
コンテキストとして SPEC.md と PROMPT.md の内容を参照してください。

## タスク
`World/BugHunterScene.swift` と `World/NetProjectile.swift` を Swift 6 に対応させてください。

## 目的（Why）
SpriteKit の SKScene はメインスレッドで動作しますが、Swift 6 では明示的な
`@MainActor` アノテーションがないとスレッド違反警告が出ます。
型安全を高めつつ、既存の網アニメーションロジックを維持します。

## 機能概要（What）
1. `BugHunterScene` クラスに `@MainActor` を付与する
2. `NetProjectile` クラスに `@MainActor` を付与する
3. `distortionPerBug` の定数コメントに `ARBugScene` との値の違いを明記する
   （ARBugScene: 0.50 / BugHunterScene: 0.38 — 意図的に異なる値）
4. `fireNet(angle:power:playerIndex:)` のプレイヤー色分けロジックは変更しない

## 制約・注意点
- `isProjectorMode = true` のとき `backgroundColor = .clear` になる設定は維持する
- タイマー・スコア管理はこのクラスで行わない（スマホ側が主導）
- `NetProjectile` の `playerIndex` 保持・arc 軌道・回転アニメは変更しない

## コメント要件
- `// ARBugScene.distortionPerBug=0.50 とは意図的に異なる（プロジェクター画面の視認性最適化）` を定数の横に入れること
```

---

---

## Phase 4 — UI / UX

### P-08: WaitingView — Liquid Glass ModeCard

**担当**: チームC（UIデザイナー）  
**マイルストーン**: M2  
**ブランチ名例**: `feat/waiting-view-liquid-glass`  
**前提**: P-00 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の SwiftUI エンジニアです。
コンテキストとして SPEC.md と PROMPT.md の内容を参照してください。

## タスク
`ContentView.swift` の `WaitingView` > `ModeCard` の背景を
iOS 26 の Liquid Glass デザインに更新してください。

## 目的（Why）
iOS 26 は Liquid Glass デザインシステムを採用しており、
システム全体のカードやパネルに `.glassBackground()` を使うことが推奨されます。
`ModeCard` を Liquid Glass 化することでプラットフォームとの一体感を高めます。

## 機能概要（What）
1. `ModeCard` の `RoundedRectangle` 背景を `.glassBackground()` に変更する
2. 選択状態のとき `accentCyan` 枠線 + `.glassBackground(.tinted)` を使う
3. `BugLegendRow` カードも `.glassBackground()` に変更する
4. `HeroLogo` のテキストカラー（accentCyan / accentBlue）は変更しない
5. `#available(iOS 26, *)` は不要（Deployment Target が iOS 26.0 のため）

## 設計トークン（変更禁止）
```swift
private let accentCyan  = Color(red: 0.20, green: 1.00, blue: 0.80)
private let accentBlue  = Color(red: 0.10, green: 0.60, blue: 1.00)
private let bgTop       = Color(red: 0.03, green: 0.04, blue: 0.10)
private let bgBottom    = Color(red: 0.00, green: 0.00, blue: 0.00)
```
背景グラデーション（bgTop → bgBottom）はそのまま維持する。

## 制約・注意点
- compact / regular の レイアウト分岐（ScrollView 方向）は変更しない
- 「バグ狩り開始」ボタンの accentCyan 色は変更しない
- 接続状態ピルの `.connected` / `.notConnected` 色分けは変更しない

## コメント要件
- `.glassBackground()` を追加した箇所に `// iOS 26 Liquid Glass: システムマテリアルでカード背景を統一` コメントを入れること
```

---

### P-09: ARPlayingView HUD — Liquid Glass タイマーバー & スコア

**担当**: チームC（UIデザイナー）  
**マイルストーン**: M2  
**ブランチ名例**: `feat/hud-liquid-glass`  
**前提**: P-08 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の SwiftUI エンジニアです。
コンテキストとして SPEC.md と PROMPT.md の内容を参照してください。

## タスク
`ContentView.swift` の `ARPlayingView` HUD（スコアパネル + タイマーバー）を
iOS 26 の Liquid Glass スタイルに更新してください。

## 目的（Why）
AR カメラ映像の上に表示される HUD は、背景が透過していないと視認性が下がります。
`.glassEffect()` を使うことで、システムが自動的に背景に応じたコントラスト調整を行い、
どんな背景でも読みやすい HUD になります。

## 機能概要（What）
1. スコア表示パネルを `.glassEffect()` 付き `RoundedRectangle` でラップする
2. タイマーバーの背景トラックを `.glassBackground()` のカプセル形状に変更する
3. タイマーバーの色ロジック（残り30秒以上→accentCyan / 10〜29秒→.yellow / 10秒未満→.red）は変更しない
4. `ReadyOverlay` のパネルも `.glassBackground()` に変更する

## 制約・注意点
- AR カメラ映像の上に重ねるため、HUD 要素は `allowsHitTesting(false)` を維持する
- スコアテキストの `accentCyan` 色は変更しない
- HUD の位置（上部固定）は変更しない

## コメント要件
- `.glassEffect()` の箇所に `// iOS 26 Liquid Glass: AR 映像背景への可読性を自動最適化` コメントを入れること
```

---

### P-10: FinishedView / CalibrationView — Liquid Glass ポリッシュ

**担当**: チームC（UIデザイナー）  
**マイルストーン**: M2〜M4  
**ブランチ名例**: `feat/finished-calibration-liquid-glass`  
**前提**: P-08, P-09 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の SwiftUI / UIKit エンジニアです。
コンテキストとして SPEC.md と PROMPT.md の内容を参照してください。

## タスク
`ContentView.swift` の `FinishedView` と `CalibrationView` を
iOS 26 の Liquid Glass スタイルに更新してください。

## 目的（Why）
全画面でのデザイン一貫性を高めるため、`FinishedView` のスコアカードと
`CalibrationView` のオーバーレイパネルを Liquid Glass 化します。

## 機能概要（What）
### FinishedView
1. 最終スコアを表示するカードパネルを `.glassBackground()` でラップする
2. 「再デバッグ」ボタンは `.glassBackground(.interactive)` スタイルにする
3. スコアテキストの accentCyan 色は変更しない

### CalibrationView（UIViewRepresentable の UIKit オーバーレイ）
1. `UIView (overlay)` の背景を `UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))` に変更する
2. iOS 26 では `UIGlassEffect` が利用可能な場合は使用する（`@available(iOS 26, *)`）
3. 「基準点を設定」ボタンと「戻る」ボタンのスタイルをシステムガラス風にアップデートする

## 制約・注意点
- `CalibrationCoordinator.confirmTapped()` / `backTapped()` のロジックは変更しない
- AR セッションの `pause()` → `setWorldOrigin` → state 遷移のシーケンスは変更しない
- `UIVisualEffectView` のフォールバックは iOS 17 以降で動作するものを使う

## コメント要件
- UIKit の `UIGlassEffect` 使用箇所に `// iOS 26: UIGlassEffect でシステムガラス効果を適用（iOS 26 以降のみ）` コメントを追加すること
```

---

---

## Phase 5 — 統合・QA

### P-11: SoundManager — @MainActor & iOS 26 AVAudioEngine 確認

**担当**: チームC（通信エンジニア / UIデザイナー）  
**マイルストーン**: M2〜M3  
**ブランチ名例**: `feat/sound-manager-main-actor`  
**前提**: P-00 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift エンジニアです。
コンテキストとして SPEC.md と PROMPT.md の内容を参照してください。

## タスク
`Controller/SoundManager.swift` を Swift 6 の `@MainActor` シングルトンに移行し、
iOS 26 の `AVAudioEngine` API の変更がないか確認してください。

## 目的（Why）
`SoundManager.shared` はゲーム全体から呼ばれるシングルトンです。
Swift 6 では `static var shared` へのスレッド外アクセスがエラーになるため、
`@MainActor` で隔離します。

## 機能概要（What）
1. `SoundManager` クラスに `@MainActor` を付与する
2. `static let shared = SoundManager()` を `@MainActor static let shared = SoundManager()` に変更する
3. `playThrow()` / `playCapture(points:)` / `playMiss()` / `playLockOn()` / `playGameStart()` / `playGameEnd()` を
   すべて `@MainActor` で呼べるようにする
4. iOS 26 で `AVAudioEngine` / `AVAudioPlayerNode` のシグネチャ変更があれば対応する

## 制約・注意点
- PCM サイン波バッファのランタイム生成ロジックは変更しない（外部音声ファイル不使用のまま）
- 6ノードプールの同時再生ロジックは変更しない
- `SoundManager` を呼ぶ側（`ARBugScene.swift` 等）の呼び出しは変更しない

## コメント要件
- `@MainActor` アノテーションの理由を先頭コメントに追加すること
```

---

### P-12: Swift Testing スイート構築

**担当**: 横断QA（全チームから兼任）  
**マイルストーン**: M3  
**ブランチ名例**: `test/swift-testing-suite`  
**前提**: P-01〜P-11 完了

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の QA エンジニアです。
コンテキストとして SPEC.md と PROMPT.md の内容を参照してください。

## タスク
Xcode 26 / iOS 26 の Swift Testing フレームワークを使って、
「ぼんち祭り バグハンター」の主要ロジックのユニットテストを構築してください。

## 目的（Why）
Swift Testing は Xcode 26 でデフォルトのテストフレームワークになりました。
XCTest に比べて `#expect`, `@Test`, `@Suite` マクロにより可読性が高く、
並行テスト実行もサポートしています。

## テスト対象と内容

### BugType テスト（`BugTypeTests.swift`）
- `BugType.allCases` が butterfly / beetle / stag の3ケースを持つことを確認
- `butterfly.points == 1`, `beetle.points == 3` を確認
- `BugType` が `Codable` で正しく JSON エンコード/デコードできることを確認
- `BugType` が `Sendable` に準拠していることを確認（コンパイル時チェック）

### GameMessage テスト（`GameMessageTests.swift`）
- `GameMessage.bugSpawned(...)` が正しく JSON にエンコードされることを確認
- JSON → `GameMessage` のデコードが正しく動作することを確認
- 不正な JSON でのデコードがエラーになることを確認

### スポーン間隔テスト（`SpawnIntervalTests.swift`）
- スポーン間隔計算式 `max(1.5, 3.5 - elapsed / 75)` を検証
  - elapsed=0 → 3.5秒
  - elapsed=75 → 1.5秒
  - elapsed=150 → 1.5秒（最短値でクランプ）

## 実装方針（How）
- `import Testing` を使う（`import XCTest` は不要）
- `@Test` / `@Suite` / `#expect` / `#require` マクロを使う
- テストは `bonchi-festivalTests/` ディレクトリに追加する
- UI テスト（`bonchi-festivalUITests/`）は今回の対象外

## 制約・注意点
- ARKit / RealityKit を使う部分（`ARGameView`, `Bug3DNode` 等）はモックが必要なため今回は除外する
- テストは `@MainActor` でもメインスレッドで実行されることを意識する

## コメント要件
- 各テストスイートの先頭に `// Swift Testing: Xcode 26 でデフォルトのテストフレームワーク` コメントを入れること
```

---

---

## Phase 6 — パフォーマンス & RC

### P-13: パフォーマンス最適化 & メモリリーク修正

**担当**: チームA + チームB（ARエンジニア + プロジェクターエンジニア）  
**マイルストーン**: M4（7/25）  
**ブランチ名例**: `perf/optimize-memory-and-framerate`  
**前提**: P-03〜P-07 完了、実機テスト M3 通過後

---

**🤖 Copilot へのプロンプト:**

```
あなたは iOS ゲーム「ぼんち祭り バグハンター」の Swift パフォーマンスエンジニアです。
コンテキストとして SPEC.md と PROMPT.md の内容を参照してください。

## タスク
以下のパフォーマンス改善を実施してください。実機 Instruments での計測結果を元に
最も効果の大きい箇所から着手します。

## 目的（Why）
本番（ぼんち祭り）は屋外でのリアルタイムデモのため、フレームレート安定性が最重要です。
USDZ モデルのクローン生成・SpriteKit の毎フレーム投影計算がボトルネックになる可能性があります。

## 改善対象

### 1. USDZ クローン生成の最適化（Bug3DNode）
- `BugAssetCache.load(named:)` のキャッシュヒット率を確認し、ミス時のログを追加する
- クローン生成時の `availableAnimations` の再帰探索を最適化する（深さ制限を設ける）

### 2. 毎フレーム投影計算の最適化（ARGameView.Coordinator）
- `SceneEvents.Update` のコールバック内で `projectPoint` が呼ばれる回数を
  `maxActiveBugs (=5)` 回以内に制限する
- プロキシ位置更新を `DispatchQueue.main.async` ではなく `MainActor.run` に変更する

### 3. SpriteKit distortionLayer の最適化（ARBugScene）
- `distortionLayer` のフリッカーアクションを `SKAction.sequence` で事前生成し、
  バグ数が変わったときのみ `updateDistortion(bugCount:)` を呼ぶ
- `update(_:)` での `currentBugCount` 計算を差分更新に変更する

## 計測方法
- Instruments → Time Profiler でボトルネック特定
- Instruments → Leaks で `Bug3DNode` / `AnchorEntity` のリーク確認
- Xcode 26 の Memory Graph デバッガーでリテインサイクル確認

## 制約・注意点
- `maxActiveBugs = 5` / スポーン間隔の定数は変更しない
- パフォーマンス改善のために機能を削除しない（当たり判定ロジックは維持）
- 変更後は M3 のテストケースがすべてパスすることを確認する

## コメント要件
- 最適化した箇所に `// Perf: [改善内容] — Instruments で確認済み` コメントを入れること
```

---

---

## ▶ チーム間の同期ルール

### 週次同期ミーティング（M2 以降必須）

| 確認項目 | 担当 |
|---------|------|
| 前週の PR マージ状況 | プロジェクトリード |
| Swift 6 コンパイルエラー残数 | 全チーム |
| 実機テスト結果（AR精度・接続安定性） | QA |
| 次週の PR 計画（1PR = 1機能） | 全チーム |
| `SPEC.md` / `PROMPT.md` 更新漏れチェック | プロジェクトリード |

### PR 作成チェックリスト

PR を出す前に以下を確認すること:

- [ ] Swift 6 strict concurrency ビルドエラーゼロ
- [ ] `BugType` の switch がすべて exhaustive（`default:` ケースなし）
- [ ] 新規コードに実装意図コメント・スレッドセーフコメントあり
- [ ] `SPEC.md` / `PROMPT.md` の更新も同一 PR に含めた
- [ ] 実機（iOS 26 デバイス）でのビルド・動作確認済み
- [ ] セルフレビュー禁止（別メンバーのレビュー必須）

### ブランチ戦略

```
main
├── develop          ← チーム統合ブランチ
│   ├── feat/xxx     ← 各チームの機能ブランチ（P-00 〜 P-13 に対応）
│   ├── fix/xxx      ← バグ修正
│   └── perf/xxx     ← パフォーマンス改善
└── release/v1.0     ← M4 以降の RC ブランチ
```

> `main` への直接プッシュ禁止。必ず `develop` を経由する。

---

## ▶ よくある AI 生成コードの問題と対処法

| 問題 | 対処法 |
|------|-------|
| `BugType` switch に `default:` が追加される | 削除して exhaustive switch に修正。新しいケース追加時はコンパイルエラーで検知できる |
| `nonisolated(unsafe)` が使われる | `@MainActor` + `Task` パターンに書き直す |
| `SceneKit` の `SCNNode` / `ARSCNView` が生成される | **このプロジェクトは RealityKit を使用**。`ARView` / `Entity` / `AnchorEntity` に修正する |
| iOS 17 以前のAPIが使われる | Deployment Target は iOS 26.0 なので `#available` 分岐は不要。最新 API を直接使う |
| Liquid Glass の `.glassBackground()` が iOS 17 で動かないと言われる | Deployment Target が iOS 26.0 なので問題ない。AI に再指示する |
| `DispatchQueue.main.async` で `@Published` を更新している | `@MainActor` 隔離 + `MainActor.run { }` または `await MainActor.run { }` に変更 |
| `Entity.loadAsync` のコールバック型が古い | iOS 26 では `async throws` で `await Entity.load(named:)` を使う |
