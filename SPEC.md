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

モードはスタート画面（`WaitingView`）のカードをタップして選択します。  
選択状態は `GameManager.GameMode` 列挙体（`.standalone` / `.projectorClient` / `.projectorServer`）で管理されます。

---

## 画面構成（iOS）

| 画面 | SwiftUI View | 表示条件 |
|------|--------------|---------|
| 待機（モード選択） | `WaitingView` | `gameManager.state == .waiting` |
| キャリブレーション | `CalibrationView` | `gameManager.state == .calibrating` |
| 開始準備 | `ARPlayingView`（`ReadyOverlay` 表示） | `gameManager.state == .ready` かつ非サーバー |
| ゲーム中（AR） | `ARPlayingView`（HUD 表示） | `gameManager.state == .playing` かつ非サーバー |
| ゲーム中（プロジェクターサーバー） | `ProjectorServerView` | `gameManager.state == .playing` かつ `.projectorServer` |
| ゲーム終了 | `FinishedView` | `gameManager.state == .finished` |

- `.ready` と `.playing` は ContentView の switch で同じ `PlayingView` ケースにまとめており、`ARGameView` のインスタンスは状態遷移をまたいで維持されます。
- `CalibrationView` でボタンを押すと `gameManager.setWorldOrigin(transform:)` が呼ばれ、状態が `.calibrating` → `.ready` に遷移します（直接 `.playing` にはなりません）。
- `.ready` 状態では `ARPlayingView` 内に `ReadyOverlay` が表示され、「スリングショットを引いて網を射出するとゲームスタート！」と案内します。
- 最初のスリングショット発射時に `gameManager.confirmReady()` が呼ばれ `.playing` に遷移、タイマーとバグスポーンが開始します。
- `FinishedView` では最終スコアを大きく表示し、「再デバッグ」ボタンで待機画面に戻れます。
- 背景はネイビー→黒のリニアグラデーション（デジタル腐敗テーマ）で統一。

---

## 操作説明

### スリングショット（スタンドアロン・クライアントモード）

1. **狙いを定める** — iPhone を動かして画面中央の照準リングをバグに重ねます。  
   バグが照準内に入ると、ロックオンリング（オレンジ色）が表示されます。

2. **引っ張る** — 画面の **任意の方向にスワイプ** します。  
   引っ張る距離が強さ（power）になります（最大 220 pt）。  
   ARSCNView 内に 3D の Y 字スリングショット（`SlingshotNode`）が常時表示され、  
   ゴム紐と緑色の網ポーチがドラッグ量に応じてリアルタイムに変形します。

3. **放す** — 指を離すと 3D 網（`Net3DNode`）が AR 空間を飛翔します。  
   - **ロックオンしている場合**: 網はバグに向かって飛びます。  
   - **ロックオンしていない場合**: 発射角度と弾道から最も近いバグを自動判定します。

4. **捕獲** — 網がバグに当たると捕獲成功。ポイントが加算されます。

### プロジェクターサーバー

- クライアントの発射情報（角度・強さ）を Multipeer Connectivity で受信し、スクリーン上のバグに当てます。
- 最大 3 台のクライアントが同時接続でき、それぞれの網は異なる色で識別されます。

---

## 出現バグ一覧

| バグ | 名前 | ポイント | 出現率 | 移動速度 | フォントサイズ | 説明 |
|------|------|---------|--------|---------|--------------|------|
| 🐞 | Null (butterfly) | 1 pt | 約 60 % | 速い (110) | 40 pt | 軽微な未定義参照エラー。すばやく動き回るが低得点。 |
| 🦠 | Virus (beetle) | 3 pt | 約 30 % | 普通 (70) | 55 pt | 自己増殖型ランタイムエラー。中程度の速度と得点。 |
| 👾 | Glitch (stag) | 5 pt | 約 10 % | 遅い (45) | 70 pt | 致命的なデータ破壊バグ。大型で捕まえやすいが希少。 |

※ 出現率は開始直後の確率です。時間が経過しても比率は変わりませんが、スポーン間隔が短くなります。

---

## ゲームルール

| 項目 | 内容 |
|------|------|
| 制限時間 | **90 秒** |
| 目標 | 時間内にできるだけ多くのバグを捕獲してポイントを稼ぐ |
| スポーン間隔 | 開始時 3.5 秒 → 75 秒時点で最短 1.5 秒（難易度上昇） |
| 同時出現上限 | **最大 5 匹** |
| タイマー管理 | **スマホ（iOS）側のみ**。プロジェクターはタイマーを持たない |
| スコア計算 | **スマホ（iOS）側のみ**で行う。プロジェクターはスコアを計算・表示しない |
| バグ同期 | スマホが `bugSpawned` / `bugRemoved` を送信し、プロジェクターはそれに従ってバグを追加・削除する |
| 最大同時接続 | **3 台**（4 台目以降は接続拒否） |
| ゲーム終了 | タイムアップ後、スマホは `FinishedView` を表示。プロジェクターは `resetGame` 受信後にバグをクリアするだけで画面遷移なし |

---

## マルチプレイヤー仕様

### 接続方法
- Multipeer Connectivity により、同一ローカルネットワーク上の iOS デバイスが自動検出・接続されます。
- プロジェクター・iOS デバイス双方がサービス名 `"bughunter-game"` で Advertise と Browse を行い、相互に検出・招待します。
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

### 接続機器情報パネル（ConnectedPlayersView）
- プロジェクター画面の右下に半透明パネルを常時表示します。
- 「接続中 N / 3」のカウントと各プレイヤーのデバイス名・カラードット（上記色）を表示します。
- 未接続スロットは「待機中…」とグレーで表示します。
- `WorldViewController` が `ProjectorGameManagerDelegate` を通じて更新を受け、`connectedPlayersView.update(players:)` を呼び出します。

---

## 難易度曲線

ゲーム開始後、時間が経つにつれてバグの出現頻度が増加します。

```
スポーン間隔（秒） = max(1.5,  3.5 - elapsed / 75)
```

- 0 秒: 約 3.5 秒間隔
- 45 秒: 約 2.5 秒間隔
- 75 秒: 最短 1.5 秒間隔

加えて同時出現上限を **5 匹** に制限し、多すぎる出現を防ぎます。

バグスポーンは `ARGameView.Coordinator`（スマホ AR 側）のみで行います。プロジェクターは独立したスポーンを持ちません。

---

## アーキテクチャ概要

```
bonchi-festival/
├── AppDelegate.swift          … UIWindow + UIHostingController(ContentView) の起動
├── ContentView.swift          … SwiftUI ルート。GameManager.state に応じて画面を切り替え
│                                  WaitingView / ARPlayingView / ProjectorServerView / FinishedView
│                                  + ModeCard / BugLegendRow / WorldViewControllerWrapper
├── Controller/
│   ├── GameManager.swift      … iOS 側ゲーム状態（GameState/GameMode 列挙）・スコア・タイマー管理
│   │                             MultipeerSession のデリゲートとして bugCaptured 受信 → スコア加算
│   │                             BugHunterSceneDelegate として ARBugScene のスコア/時間更新を受信
│   ├── MultipeerSession.swift … iOS 側 Multipeer Connectivity ラッパー
│   │                             Advertiser + Browser の両方として動作。サービス名 "bughunter-game"
│   ├── ARGameView.swift       … UIViewRepresentable。UIView コンテナに ARSCNView (3D) + SKView (透過) を重ねる
│   │                             内部 Coordinator: ARSCNViewDelegate。ARAnchor → Bug3DNode + 不可視プロキシ SKNode
│   │                             startSpawning(): standalone + projectorClient でバグをスポーン（projectorServer のみ除外）
│   │                             毎フレーム 3D→2D 座標変換でプロキシ位置同期。距離ベーススケール調整
│   ├── ARBugScene.swift       … SpriteKit 透過シーン。照準クロスヘア・ロックオンリング・捕獲アニメ
│   │                             distortionLayer（グリッチバー × 12本）: バグ数に応じて強度が上昇
│   │                             fireNet(angle:power:) で 2段階当たり判定（ロックオン優先 → 弾道判定）
│   │                             BugHunterSceneDelegate プロトコルを定義（didUpdateScore/sceneDidFinish）
│   ├── Bug3DNode.swift        … SCNNode サブクラス。USDZ モデル優先（toy_biplane/gramophone/toy_drummer）
│   │                             USDZ 不在時は手続き的 PBR ジオメトリにフォールバック
│   │                             butterfly: 4枚翅・触角 / beetle: 光沢甲殻・6脚 / stag: 大顎・6脚
│   │                             各バグ固有アニメ（羽ばたき/回転/頷き）＋共通ホバー＋二次水平ドリフト
│   │                             preloadAssets(): ゲーム開始前に全 USDZ を非同期プリロード（NSLock キャッシュ）
│   ├── SlingshotNode.swift    … SCNNode。3D Y 字スリングショットフォーク + ゴム紐 + 網ポーチ
│   │                             arView.pointOfView の子として追加することでカメラ空間に固定表示
│   │                             updateDrag(offset:maxDrag:): ドラッグ量に応じてゴム紐・ポーチを変形
│   │                             resetDrag(): ドラッグ解除時にニュートラル位置に戻す
│   ├── Net3DNode.swift        … SCNNode。3D 飛翔網メッシュ（トーラスリム + 8 スポーク + 同心リング）
│   │                             launch(from:direction:power:completion:): AR 空間を飛翔→フェードアウト
│   ├── SlingshotView.swift    … SwiftUI スリングショット UI（フルスクリーンオーバーレイ）
│   │                             ジェスチャ管理専用。3D 描画は SlingshotNode / Net3DNode が担当
│   │                             slingshotDragUpdate / onNetFired コールバックを通じて Coordinator と連携
│   │                             PowerIndicatorView（引き量インジケーター）のみ 2D 描画
│   └── SoundManager.swift     … AVAudioEngine ベースの手続き型サウンドエフェクト（シングルトン）
│                                 PCM サイン波バッファをランタイムで生成。外部音声ファイル不要。
│                                 6 ノードプールで複数音の同時再生をサポート。
│                                 playThrow() / playCapture(points:) / playMiss() / playLockOn()
│                                 playGameStart() / playGameEnd()
├── Shared/
│   └── GameProtocol.swift     … Multipeer で共有するメッセージ型・BugType 定義
│                                 MessageType / GameMessage / LaunchPayload / GameStatePayload
│                                 BugCapturedPayload / BugSpawnedPayload / BugRemovedPayload
│                                 BugType / PhysicsCategory
└── World/                     … プロジェクター側（iPad / Mac Catalyst）
    ├── WorldViewController.swift  … ルート UIViewController
    │                                 SCNView (背面、常時アクティブ) + SKView 透過オーバーレイ (前面)
    │                                 + ConnectedPlayersView (右下固定)
    │                                 ProjectorBug3DCoordinator を内部クラスとして定義・管理
    │                                 viewDidLoad で Bug3DNode.preloadAssets() を呼び出し USDZ を非同期プリロード
    │                                 初回レイアウト時に startGame() を直接呼び出す（3D 即時表示）
    │                                 bugSpawned / bugRemoved 受信時に coordinator へ委譲
    ├── WaitingScene.swift         … 待機画面 SKScene（現在はほぼ未使用）
    ├── BugHunterScene.swift       … ゲーム中 SKScene（isProjectorMode=true で透過背景）
    │                                 タイマー・スコア・HUD・スポーナーなし（スマホ主導）
    │                                 fireNet(angle:power:playerIndex:) のみ保持（視覚的な網アニメ用）
    ├── BugSpawner.swift           … 旧 SpriteKit BugNode スポーナー（現在は未使用）
    ├── NetProjectile.swift        … 網 SKNode（描画 net mesh + ringNode + centerDot）
    │                                 playerIndex 保持・プレイヤー色リング・arc 軌道・回転アニメ
    └── ProjectorGameManager.swift … 最大3台の Multipeer 接続管理
                                      bugSpawned / bugRemoved を WorldViewController へデリゲート
```

### 通信フロー（Multipeer Connectivity）

```
iOS Controller (×最大3台)               Projector Server
    │                                        │
    │── startGame ──────────────────────────>│  (いずれかのクライアントが送信)
    │                                        │
    │── launch(angle, power, timestamp) ────>│  → playerIndex はサーバー側で peerID より特定
    │                                        │  → 対応する色の NetProjectile を発射（視覚のみ）
    │                                        │
    │── bugSpawned(id, type, x, y) ─────────>│  → 対応する Bug3DNode をその位置に追加
    │                                        │
    │── bugRemoved(id) ─────────────────────>│  → 対応する Bug3DNode を captured() アニメで削除
    │                                        │
    │── resetGame ───────────────────────── >│  → 全 Bug3DNode を即削除（画面遷移なし）
```

### メッセージ型一覧

| 型 | 方向 | ペイロード | 説明 |
|----|------|-----------|------|
| `launch` | iOS → Projector | `LaunchPayload(angle, power, timestamp)` | スリングショット発射（視覚同期） |
| `startGame` | iOS → Projector | なし | ゲーム開始 |
| `resetGame` | iOS → Projector | なし | バグをクリア |
| `bugSpawned` | iOS → Projector | `BugSpawnedPayload(id, bugType, normalizedX, normalizedY)` | バグ出現通知（全モードで送信、接続なし時は no-op） |
| `bugRemoved` | iOS → Projector | `BugRemovedPayload(id)` | バグ捕獲通知（全モードで送信、接続なし時は no-op） |
| `bugCaptured` | Projector → iOS | `BugCapturedPayload(bugType, playerIndex)` | 旧スコア通知（後方互換のため残存。現在は未使用） |

### スコア設計

- **スコア計算はスマホ（iOS）側のみ。**
- スタンドアロン・プロジェクタークライアント共に、`ARBugScene` での捕獲時に `BugHunterSceneDelegate` を通じて直接スコアが更新されます。
- プロジェクター側はスコアを保持・表示しません。

### スポーンシステムの統一

- **スタンドアロンとプロジェクタークライアントの出現システムは完全共通です。**
- `sendBugSpawned`・`sendBugRemoved`・`sendLaunch`・`startGame`・`resetGame` の Multipeer 送信はすべてモード判定なしで呼ばれます。
- スタンドアロンモード（接続ピアなし）では送信が no-op になるだけで、コードパスは同一です。

### プロジェクター表示設計

- プロジェクターは常に SceneKit 3D シーンを表示し続けます（待機画面や終了画面なし）。
- バグは `bugSpawned` 受信時に `ProjectorBug3DCoordinator.addSyncedBug` で追加されます（フェードイン + スケールアップ + ホバーアニメ）。
- バグは `bugRemoved` 受信時に `removeSyncedBug` で `captured()` アニメ付きで削除されます。
- `resetGame` 受信時は全バグを即座に削除します。

---

## AR レイヤー詳細（スタンドアロン・クライアントモード）

```
ARSCNView (3D バグ)
    └── Bug3DNode (SCNNode)
          ├── USDZ モデル優先（toy_biplane / gramophone / toy_drummer）
          │     ※ USDZ が見つからない場合は手続き的 PBR ジオメトリにフォールバック
          └── 各種アニメーション（羽ばたき・回転・ホバー等）＋二次ドリフト（水平スクエア軌道）

SKView (透過オーバーレイ) → ARBugScene
    ├── 照準クロスヘア（画面中央固定）
    ├── ロックオンリング（最近傍バグに追従、オレンジ）
    ├── distortionLayer（グリッチバー × 12本、バグ数に比例して強化）
    │     tint(紫赤)・赤/紫/シアン/オレンジのバーが独立フリッカー
    ├── 不可視プロキシ bugContainer SKNode（3D 投影座標に毎フレーム同期）
    └── 捕獲エフェクト（net スロー・ミス表示）
```

- `ARGameView.Coordinator` が `ARSCNViewDelegate` として毎フレーム `renderer(_:updateAtTime:)` を実行。
- `arView.projectPoint(SCNVector3)` で 3D → UIKit 座標変換後、Y 軸反転で SpriteKit 座標に変換。
- スポーン距離: カメラ前方 **0.5〜1.4 m**、水平 ±37°、垂直オフセット -0.3〜0.45 m。
- 距離ベーススケール: `scale = referenceDistance(3.0m) / actualDistance`（0.3〜5.0 でクランプ）。
- `antialiasingMode = .multisampling4X` でエッジをスムージング。
- `lightingEnvironment.intensity = 1.5` で IBL 強度を調整し PBR 素材を正確に表現。
- `cachedViewHeight` パターンでレンダースレッドからの UIKit アクセスを回避。
- 捕獲半径: `ARBugScene.catchRadius = 150 pt`（画面中央からの距離）。

### スポーン基点（キャリブレーション）

- バグのスポーン中心は `GameManager.worldOriginTransform`（`simd_float4x4?`）が決定する。
- キャリブレーション実施済みの場合: 記録した基準点トランスフォームを基点にスポーン → バグが常に同じ空間エリアに出現する。
- キャリブレーション未実施（`nil`）の場合: 従来通りライブカメラトランスフォームを基点にスポーン（後方互換）。
- `resetGame()` を呼ぶと `worldOriginTransform` はクリアされる。

### USDZ モデルマッピング

Apple AR Quick Look ギャラリー（<https://developer.apple.com/jp/augmented-reality/quick-look/>）から取得したモデルを使用。

| BugType | USDZ ファイル | スケール定数 |
|---------|-------------|------------|
| butterfly (Null) | `toy_biplane.usdz` | 0.005 |
| beetle (Virus) | `gramophone.usdz` | 0.004 |
| stag (Glitch) | `toy_drummer.usdz` | 0.004 |

USDZ ファイルが存在しない場合は手続き的ジオメトリ（PBR マテリアル）で代替されるため、ファイルがなくてもゲームは動作します。

---

## プロジェクター レイアウト

```
┌────────────────────────────────────────────────┐
│  SCNView  — Bug3DNode（3D バグ）常時アクティブ  │ ← 背面 (z=0)
│  SKView   — BugHunterScene または WaitingScene  │ ← 前面（常に透過 bg）
│               (透過背景) HUD / 網 / プロキシ等   │
│  ConnectedPlayersView ──────────────── [右下]   │ ← 常時最前面 UIKit
└────────────────────────────────────────────────┘
```

- **SCNView.backgroundColor**: `UIColor(red: 0.05, green: 0.12, blue: 0.05, alpha: 1)`（暗い緑）
- **WaitingScene**: `isProjectorOverlay = true` → `backgroundColor = .clear`（3D 環境を常に見せる）
- **BugHunterScene**: `isProjectorMode = true` → `backgroundColor = .clear`
- `ProjectorBug3DCoordinator`（`WorldViewController.swift` 内に定義）: SCNScene に固定パース視点カメラを設置（cameraZ=3.5、FOV=65°）。Bug3DNode を `bugScaleMultiplier=10` でスケール拡大して表示。毎フレーム `scnView.projectPoint()` でプロキシ位置を同期。

---

## あみ（網）仕様

あみ（🕸️）はバグを捕獲するための投射物です。  
スタンドアロン・クライアントモードでは **iOS 側**の `ARBugScene` が処理し、プロジェクターモードでは **プロジェクター側**の `NetProjectile` SKNode が使われます。

---

### 1. スリングショット操作（`SlingshotView.swift`）

| パラメーター | 値 |
|------------|---|
| フォーク Y 位置 | 画面高さの **62 %**（`forkYRatio = 0.62`）|
| フォークサイズ | 幅 100 pt × 高さ 130 pt の Y 字型 |
| 最大ドラッグ距離 | **220 pt**（`maxDragDistance`）|
| 発射方向 | 任意方向（上下左右・斜め全方位） |

**操作手順**

1. 画面のスリングショットを任意の方向にドラッグする（最大 220 pt）。
2. ドラッグ中はゴム紐（オレンジ）と 🕸️ プレビューが表示される。
3. 指を離すと発射。ドラッグ量が 10 pt 未満の場合は発射されない。

**パラメーター計算**

```
angle = atan2(dragOffset.height, -dragOffset.width)   // SpriteKit 座標系
power = min(dragLength / 220, 1.0)                     // 0.0〜1.0
```

**パワーインジケーター（`PowerIndicatorView`）**

| パワー範囲 | バー色 |
|-----------|-------|
| 0.0〜0.39 | 緑 |
| 0.4〜0.69 | 黄 |
| 0.7〜1.0  | 赤 |

**iOS UI 上の網飛翔アニメーション**

- 発射後、🕸️（font size 64pt）がフォーク位置から発射方向へ飛翔する。
- スケール: 0.3 → 1.8 → フェードアウト（0.55 秒）
- 回転量: `power × 540° + 270°`（270°〜810°）

---

### 2. 当たり判定（iOS AR モード：`ARBugScene.fireNet`）

発射時に 2 段階の当たり判定を行います。

#### 第 1 段階：ロックオン優先判定

- 画面中央から **catchRadius = 150 pt** 以内にいる、最も近いバグを捕獲対象とする。
- ロックオン中（オレンジリング表示）のバグが対象になる。

#### 第 2 段階：弾道判定（ロックオンなし時）

- 発射方向の「帯」の中にいるバグを対象とする。
- `hitBand = 90 pt`（発射ライン垂直方向の幅）
- `netRange = power × max(W, H) × 0.8 + 200 pt`（帯の長さ）
- 発射ライン方向への正射影が小さい（最初に到達する）バグを優先。

#### ミス

- 上記いずれにも該当しない場合は **MISS** テキストアニメーションと外れ音が再生される。

---

### 3. 照準・ロックオン UI（`ARBugScene`）

| UI 要素 | 説明 |
|--------|------|
| 照準クロスヘア | 画面中央固定。シアン色リング（半径 54 pt）+ 中央ドット + 4 方向ティック。アイドル時パルス（1.07→1.0倍, 0.85 s サイクル）|
| ロックオンリング | オレンジ色（半径 58 pt）。バグが catchRadius 内に入ると最近傍バグ位置に表示。取得時 1.8→1.0 倍でスナップイン + 繰り返しパルス |
| ロックオン取得時 | 照準リングもオレンジに変色。`SoundManager.playLockOn()` を発火（ターゲット変化時のみ） |
| ロックオン喪失時 | リング非表示に。照準リングはシアンに復帰 |

---

### 4. iOS 側の網アニメーション（`ARBugScene`）

#### 発射アニメーション（`playNetThrowAnimation`）

- 画面中央から発射目標方向（ターゲットバグの 55 % 地点 or 発射方向）へ 🕸️（font 64 pt）が飛翔。
- 移動・拡大（0.2→2.0 倍, 0.30 s）・270° 回転（0.42 s）・フェードアウト（0.22 s 後に開始, 0.20 s）
- 同時に、白い展開リング（半径 28 pt）が 0.3→3.8 倍に拡大しフェードアウト（0.45 s）

#### 捕獲エフェクト（`catchBug`）

| # | エフェクト | 詳細 |
|---|-----------|------|
| 1 | バグ消去 | `BugNode.captured()` + `Bug3DNode.captured()` によるフェードアウト |
| 2 | ヒールリップル | シアン色の拡大リング（半径 20 pt → ×5.0, 0.55 s）が捕獲位置に表示 |
| 3 | 大型網展開 | 🕸️（90 pt）が 0.1→2.4 倍に拡大後フェードアウト（0.40 s）|
| 4 | スクリーンフラッシュ | シアン–ホワイト半透明矩形がフェードアウト（0.30 s）|
| 5 | スコアポップ | `+Xpts`（5pt の場合 ⭐ 付き）が上方へ浮かび上がりフェードアウト |
| 6 | 照準フラッシュ | 照準リングが緑に変色 → スケール 1.4→1.0 → シアンに復帰 |
| 7 | ARAnchor 削除 | アニメーション終了後（0.75 s）に AR アンカーをセッションから除去 |

#### ミスエフェクト（`playMissAnimation`）

- 画面中央下に赤い **MISS** テキストが浮かび上がりフェードアウト（0.38 + 0.20 s）
- 照準リングが赤にフラッシュ → シアンに復帰
- `SoundManager.playMiss()` を発火

---

### 5. プロジェクター側の網ノード（`NetProjectile.swift`）

`NetProjectile` は `BugHunterScene` に追加される `SKNode` で、プロジェクター画面上を飛翔します。

#### ノード構成

| 子ノード | 内容 |
|---------|------|
| `netShape` | `SKShapeNode`。8 本のスポーク + 3 つの同心円で描画した蜘蛛の巣 net パターン（緑系）|
| `ringNode` | プレイヤー色の外周アクセントリング（半径 38 pt）|
| centerDot | プレイヤー色の中央塗りつぶし円（半径 6 pt）|

#### プレイヤー色

| スロット | 色 | R / G / B |
|---------|-----|-----------|
| Player 1 | シアン | (0.0, 1.0, 1.0) |
| Player 2 | オレンジ | (1.0, 0.55, 0.0) |
| Player 3 | マゼンタ | (1.0, 0.2, 0.8) |

#### 物理ボディ

| プロパティ | 値 |
|-----------|---|
| 形状 | 円（radius **44 pt**）|
| isDynamic | true |
| affectedByGravity | false |
| linearDamping / angularDamping | 0 |
| categoryBitMask | `PhysicsCategory.net` (0x2) |
| contactTestBitMask | `PhysicsCategory.bug` (0x1) |
| collisionBitMask | 0（物理的反発なし） |

#### 発射（`launch(angle:power:from:sceneSize:)`）

| パラメーター | 計算式 | 値の範囲 |
|------------|-------|---------|
| 移動速度 | `power × 1400 + 500` pt/s | 500〜1900 pt/s |
| 飛翔時間 | 固定 | **0.55 s** |
| 弧（arcBump）| `sceneSize.height × 0.06 × \|cos(angle)\| × (power + 0.3)` | 角度・パワー依存 |
| スケール変化 | 0.3 → 1.3 → 1.0（unfurl）| 発射直後に展開 |
| 回転量 | `π × (1.5 + power × 2)` rad | 270°〜810° |
| リングアニメ | scale: 0.4→3.5、alpha: 0.85→0.5→0（0.5 s）| 展開演出 |

飛翔は 4 つのアクションを並行実行:
1. `baseMove`（easeOut）: 直線移動
2. `arcAction`: 進行方向に対して垂直に弧を描く上昇→下降
3. `unfurl`: スケール変化
4. `spin`（easeOut）: 回転

飛翔完了後（0.55 s）、シーンから自動削除されます（`removeFromParent`）。

#### 捕獲アニメーション（`playCapture`）

1. 全アクション停止、物理ボディを nil に設定
2. スケール 1.0 → 1.6 → 1.0（0.12 + 0.10 s のパルス）
3. フェードアウト（0.35 s）→ シーンから削除

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

## 開発環境

| 項目 | バージョン |
|------|-----------|
| Swift | 5.9 以上 |
| iOS Deployment Target | iOS 17.0 以上 |
| Xcode | 15 以上 |
| フレームワーク | SwiftUI, UIKit, ARKit, SceneKit, SpriteKit, MultipeerConnectivity, Combine, AVFoundation |
| 外部ライブラリ | なし（Apple 標準フレームワークのみ） |
| アセット | なし（すべて手続き的に生成） |

---

## サウンドエフェクト

`SoundManager`（`Controller/SoundManager.swift`）が AVAudioEngine を使って PCM サイン波バッファをランタイムで合成します。  
外部音声ファイルは一切使用しません。

| イベント | 効果音 | 呼び出し箇所 |
|---------|--------|------------|
| 網を発射 | 高→低周波スイープ（シュッ） | `ARBugScene.fireNet`, `BugHunterScene.fireNet` |
| バグ捕獲 | 上昇アルペジオ（1pt: 2音, 3pt: 3音, 5pt: 4音） | `ARBugScene.catchBug`, `BugHunterScene.didBegin` |
| ミス | 低→さらに低のスイープ（ズドン） | `ARBugScene.playMissAnimation` |
| ロックオン | 短ビープ（目標変化時のみ発火） | `ARBugScene.refreshLockOnRing` |
| ゲーム開始 | C5→E5→G5→C6 上昇ファンファーレ | `GameManager.startGame` |
| ゲーム終了 | G5→E5→C5→G4 下降メロディ | `ARBugScene.endGame`, `BugHunterScene.endGame` |

- `AVAudioSession.Category.ambient` を使用。他アプリの音楽と混在し、サイレントスイッチでも消音されない。
- 複数音の同時再生は 6 ノードのラウンドロビンプールで管理。
- ノートシーケンスは `DispatchQueue.asyncAfter` でスケジューリング（スレッドプールをブロックしない）。

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
- **スレッド安全性**: SceneKit レンダースレッドから UIKit にアクセスしない（`cachedViewHeight` パターン）。Multipeer Connectivity コールバックは常に `DispatchQueue.main.async` でメインスレッドに戻す。`ARGameView.Coordinator` のアンカー辞書（`bugAnchorMap`, `anchorBug3DNodeMap`, `anchorProxyNodeMap`, `nodeAnchorMap`）はメインスレッドとレンダースレッドから同時アクセスされるため、`mapLock`（`NSLock`）で全アクセスを保護する。`renderer(_:updateAtTime:)` ではロック下でスナップショットを取り、ロック解放後に投影計算を行う。
