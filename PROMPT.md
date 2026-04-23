# ぼんち祭り バグハンター — 完全再現プロンプト

## このドキュメントについて

このファイルは **ぼんち祭り バグハンター** を **ゼロから完全再現できる** レベルで記述した AI コンテキスト・プロンプトです。  
全ソースファイルを精査した上で、定数・アニメーション秒数・マテリアル RGB 値・分岐ロジックをすべて網羅しています。  
AI（GitHub Copilot 等）に継続開発・バグ修正・機能追加をさせる際のコンテキストとして利用してください。

---

## プロジェクト概要

**ぼんち祭り バグハンター** は、ARKit × SpriteKit × RealityKit × MultipeerConnectivity を組み合わせた iOS ゲームです。

- **テーマ**: 腐敗したデジタルワールドに出現する「バグ（害虫）」を、スリングショットで網を飛ばして捕獲する。
- **コンセプト**: バグは `NullReferenceException`・自己増殖ウイルス・致命的データ破壊グリッチとして擬人化される。プレイヤーは「バグハンター」として世界を浄化する。
- **ロケーション**: 祭り（ぼんち祭り）会場での大型スクリーン展示。観客が iPhone でスリングショットをプレイ。

---

## Xcode プロジェクト設定

| 項目 | 値 |
|------|---|
| Bundle Identifier | com.mchreo0121.bonchi-festival（参考値） |
| Deployment Target | iOS 17.0 |
| Swift | 5.9 以上 |
| Xcode | 15 以上 |
| AppDelegate ベース | `@main class AppDelegate: UIResponder, UIApplicationDelegate` |
| ライフサイクル | UIKit AppDelegate（SwiftUI App プロトコルは **使用しない**） |

### Info.plist 必須エントリ

```xml
<key>NSCameraUsageDescription</key>
<string>AR でバグを捕獲するためにカメラが必要です</string>
<key>NSLocalNetworkUsageDescription</key>
<string>プロジェクターと接続するためにローカルネットワークが必要です</string>
<key>NSBonjourServices</key>
<array>
    <string>_bughunter-game._tcp</string>
    <string>_bughunter-game._udp</string>
</array>
```

### Capabilities

- **ARKit**: 実機専用（シミュレーター非対応）
- **Multipeer Connectivity**: プロジェクターモードに必要
- 外部ライブラリ不使用。Apple 標準フレームワークのみ。

---

## プラットフォーム構成

| デバイス | 役割 | ターゲット |
|---------|------|-----------|
| iPhone (最大3台) | コントローラー（ARスリングショット） | iOS 17.0+ |
| iPad / Mac | プロジェクターサーバー（大画面表示） | iOS 17.0+ |

---

## プレイモード

| モード | GameMode 列挙値 | 説明 |
|--------|----------------|------|
| スタンドアロン | `.standalone` | 1台の iPhone で完結する AR バグハンター |
| プロジェクター・クライアント | `.projectorClient` | iPhone がコントローラー。操作をプロジェクターへ送信 |
| プロジェクター・サーバー | `.projectorServer` | 大画面表示デバイス。最大3台の iPhone を受け付ける |

---

## ファイル構成と責務（詳細）

```
bonchi-festival/
├── AppDelegate.swift            ← UIKit AppDelegate。UIHostingController(ContentView()) をルートに設定
├── ContentView.swift            ← SwiftUI ルートビュー
├── Controller/
│   ├── GameManager.swift        ← iOS 側ゲーム状態管理 ObservableObject
│   ├── MultipeerSession.swift   ← iOS 側 Multipeer Connectivity ラッパー
│   ├── ARGameView.swift         ← UIViewRepresentable (ARView + SKView 重ね合わせ)
│   ├── ARBugScene.swift         ← SpriteKit 透過シーン（照準・捕獲 UI）
│   ├── Bug3DNode.swift          ← RealityKit Entity ラッパー（3D バグ表示、USDZ + availableAnimations ループ）
│   ├── ForestEnvironment.swift  ← 手続き的 3D 木エンティティを AR / プロジェクター両シーンに植林する enum ユーティリティ
│   ├── SlingshotNode.swift      ← RealityKit Entity ラッパー（3D Y 字スリングショット）
│   ├── Net3DNode.swift          ← RealityKit Entity ラッパー（3D 飛翔網メッシュ、透明度は各 ModelEntity のマテリアル α で制御）
│   ├── SlingshotView.swift      ← SwiftUI ジェスチャオーバーレイ
│   └── SoundManager.swift       ← AVAudioEngine ベースサウンドマネージャ（シングルトン）
├── Shared/
│   └── GameProtocol.swift       ← Multipeer 共有型 (BugType, GameMessage 等)
└── World/
    ├── WorldViewController.swift  ← プロジェクター側 UIViewController + ProjectorBug3DCoordinator
    ├── ProjectorGameManager.swift ← プロジェクター側 Multipeer ラッパー
    ├── BugHunterScene.swift       ← プロジェクター用 SKScene（透過オーバーレイ）
    ├── WaitingScene.swift         ← 待機画面 SKScene（ほぼ未使用）
    ├── NetProjectile.swift        ← プロジェクター用 網 SKNode
    └── BugSpawner.swift           ← 旧 SpriteKit スポーナー（現在未使用）
```

---

## AppDelegate.swift

```swift
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: ContentView())
        self.window = window
        window.makeKeyAndVisible()
        return true
    }
}
```

---

## ContentView.swift

`GameManager` を `@StateObject` で保持するルートビュー。

### 設計トークン（ファイル先頭のプライベート定数）

```swift
private let accentCyan  = Color(red: 0.20, green: 1.00, blue: 0.80)
private let accentBlue  = Color(red: 0.10, green: 0.60, blue: 1.00)
private let bgTop       = Color(red: 0.03, green: 0.04, blue: 0.10)
private let bgBottom    = Color(red: 0.00, green: 0.00, blue: 0.00)
```

### 状態遷移とビュー切り替え

```swift
switch gameManager.state {
case .waiting:    WaitingView()
case .calibrating: CalibrationView()
case .ready, .playing: PlayingView()   // 同一ケースで ARGameView インスタンスを維持
case .finished:   FinishedView()
}
// 全遷移: .animation(.easeInOut(duration:0.35)) + .transition(.opacity)
```

**PlayingView の内訳**:
- `gameManager.gameMode == .projectorServer` → `ProjectorServerView`
- それ以外 → `ARPlayingView`

### WaitingView

- 背景: `LinearGradient(colors:[bgTop, bgBottom], startPoint:.top, endPoint:.bottom)`
- 上部: `HeroLogo`（compact 高さ<750pt: icon 88pt / タイトル 66pt / サブタイトル 32pt、regular: 118/90/44pt）
- `ModeCard` × 3（standalone/projectorClient/projectorServer）
  - compact 時は `.horizontal` `ScrollView`（横並び）、regular 時は縦 `ScrollView`
- 接続状態ピル: `.connected` 時シアン、`.notConnected` 時グレー
- 「バグ狩り開始」ボタン（accentCyan）:
  - projectorServer 選択 → `gameManager.startGame()` 直接
  - それ以外 → `gameManager.startCalibration()`
- `BugLegendRow` × 3（バグ一覧カード）+ ミッション説明テキスト

**ModeCard**: アイコン + タイトル + サブタイトル。選択中は accentCyan 枠線 + 薄いシアン背景。  
**BugLegendRow**: バグ絵文字 + 表示名 + レアリティ + ポイント + 速度ラベル（`BugType` computed から取得）。

### CalibrationView（UIViewRepresentable）

`ARView` フルスクリーン + UIKit オーバーレイを重ねる `UIView` を返す。

```
UIView (container)
├── ARView (fullscreen)
│     ARWorldTrackingConfiguration で AR セッション開始
└── UIView (overlay)
    ├── 照準レティクル (CAShapeLayer: 十字 + 円、中央固定)
    ├── 説明ラベル（上部）
    ├── 「基準点を設定」UIButton → confirmTapped → gameManager.setWorldOrigin(transform:)
    └── 「戻る」UIButton → backTapped → gameManager.resetGame()
```

`CalibrationCoordinator`:
- `confirmTapped()`: 多重押下を防止しつつ `arView.session.currentFrame?.camera.transform` を取得。遷移前にキャリブレーション用 AR セッションを `pause()` / delegate 解放してから `gameManager.setWorldOrigin(transform:)` → state = `.ready`
- `backTapped()`: 同様にキャリブレーション用 AR セッションを停止してから `gameManager.resetGame()` → state = `.waiting`

### ARPlayingView

```
ZStack
├── ARGameView() (ignoresSafeArea)
├── if state == .ready: ReadyOverlay (allowsHitTesting: false)
├── if state == .playing: HUD（スコア + タイマーバー）
└── SlingshotView() (フルスクリーン、ジェスチャのみ)
```

**タイマーバー色**:
```swift
// 残り30秒以上 → accentCyan / 残り10-29秒 → .yellow / 残り10秒未満 → .red
```

**ReadyOverlay**: 「スリングショットを引いて網を射出するとゲームスタート！」。半透明黒背景角丸パネル、`allowsHitTesting(false)`。

### ProjectorServerView

```swift
struct WorldViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WorldViewController { WorldViewController() }
    func updateUIViewController(_ vc: WorldViewController, context: Context) {}
}
```

フルスクリーンに `WorldViewControllerWrapper` + 左上に戻るボタン。

### FinishedView

最終スコアを大きく表示（accentCyan）+ 「再デバッグ」ボタン → `gameManager.resetGame()`。  
背景: `LinearGradient(bgTop → bgBottom)`。

---

## Controller/GameManager.swift

`ObservableObject`。iOS 側ゲーム全体の状態管理。

### 列挙体

```swift
enum GameState { case waiting, calibrating, ready, playing, finished }
enum GameMode  { case standalone, projectorClient, projectorServer }
```

### @Published プロパティ

```swift
@Published var state: GameState = .waiting
@Published var score: Int = 0
@Published var timeRemaining: Double = 90.0
@Published var isConnected: Bool = false
@Published var gameMode: GameMode = .standalone
@Published var arBugScene: ARBugScene? = nil
```

### その他のプロパティ

```swift
var worldOriginTransform: simd_float4x4? = nil
var slingshotDragUpdate: ((CGSize, Bool) -> Void)? = nil
var onNetFired: ((CGSize, Float) -> Void)? = nil
private let multipeerSession = MultipeerSession()
```

### 主要メソッド

| メソッド | 動作 |
|---------|------|
| `selectMode(_:)` | `gameMode` を切替。`.projectorClient` 選択時に `multipeerSession.start()` |
| `startCalibration()` | `.projectorServer` 以外は `state = .calibrating`。`.projectorServer` は直接 `startGame()` |
| `setWorldOrigin(transform:)` | `worldOriginTransform = transform`; `state = .ready` |
| `confirmReady()` | `.ready` → `startGame()` |
| `startGame()` | `score=0` / `timeRemaining=90` リセット; `.projectorServer` 以外は `ARBugScene` 生成; `multipeerSession.send(.startGame())` |
| `resetGame()` | 全状態リセット; `worldOriginTransform=nil`; `slingshotDragUpdate=nil`; `onNetFired=nil`; `multipeerSession.send(.resetGame())` |
| `sendLaunch(angle:power:)` | `arBugScene?.fireNet(angle:power:)` + `multipeerSession.send(.launch(...))` |
| `sendBugSpawned(id:type:normalizedX:normalizedY:)` | `multipeerSession.send(.bugSpawned(...))` （モード判定なし; 接続なし時 no-op） |
| `sendBugRemoved(id:)` | `multipeerSession.send(.bugRemoved(...))` （モード判定なし; 接続なし時 no-op） |

**BugHunterSceneDelegate 実装**:
- `didUpdateScore(_:timeRemaining:)` → `self.score = score`; `self.timeRemaining = timeRemaining`
- `sceneDidFinish(_:finalScore:)` → `self.score = finalScore`; `state = .finished`

**MultipeerSessionDelegate 実装**:
- `peerDidConnect(_:)` → `isConnected = true`
- `peerDidDisconnect(_:)` → `isConnected = (session.connectedPeers.count > 0)`
- `didReceive(message:from:)` の `.bugCaptured` → `score += bugType.points`（後方互換）

**重要**: `sendBugSpawned`/`sendBugRemoved` は接続モードに関わらず常に呼ばれる。接続なし時は no-op。

---

## Controller/MultipeerSession.swift

iOS 側 Multipeer Connectivity ラッパー（`NSObject, ObservableObject`）。

```swift
static let serviceType = "bughunter-game"   // ProjectorGameManager と必ず一致
// MCSession + MCNearbyServiceAdvertiser + MCNearbyServiceBrowser を同時起動
// start() / stop() で制御
// send(_ message: GameMessage) — 全接続ピアへ .reliable 送信（JSON エンコード）
// 受信コールバックはすべて DispatchQueue.main.async で配送
```

**MultipeerSessionDelegate プロトコル**:
```swift
func didReceive(message: GameMessage, from peer: MCPeerID)
func peerDidConnect(_ peer: MCPeerID)
func peerDidDisconnect(_ peer: MCPeerID)
```

---

## Controller/ARGameView.swift

`UIViewRepresentable`。`UIView` コンテナに `ARView`（背面）+ `SKView`（前面・透過）を重ねる。

### makeUIView レイヤー構成

```
UIView (container, UIScreen.main.bounds)
├── ARView (autoresizingMask: flexible, 背面)
│     autoenablesDefaultLighting = true
│     automaticallyUpdatesLighting = true
│     antialiasingMode = .multisampling4X
│     scene.lightingEnvironment.intensity = 1.5
│     config = ARWorldTrackingConfiguration()
└── SKView (autoresizingMask: flexible, 前面)
      backgroundColor = .clear, isOpaque = false, allowsTransparency = true
```

`makeUIView` で `Bug3DNode.preloadAssets()` を呼び出し（USDZ を事前ロード）。

### Coordinator 定数

```swift
private static let minSpawnDistance:     Float = 0.5
private static let maxSpawnDistance:     Float = 1.4
private static let horizontalAngleRange: ClosedRange<Float> = -0.65...0.65  // ±~37°
private static let verticalOffsetRange:  ClosedRange<Float> = -0.30...0.45
private static let referenceDistance:    Float = 3.0   // 距離ベーススケール基準
private static let minBugScale:          Float = 0.3
private static let maxBugScale:          Float = 5.0
private static let maxActiveBugs:        Int   = 5
```

### アンカー辞書（全て `mapLock: NSLock` で保護）

```swift
private var bugAnchorMap:       [UUID: BugType]               // anchor.identifier → BugType
private var anchorBug3DNodeMap: [UUID: Bug3DNode]              // anchor.identifier → Bug3DNode
private var anchorProxyNodeMap: [UUID: SKNode]                 // anchor.identifier → proxy SKNode
private var nodeAnchorMap:      [ObjectIdentifier: ARAnchor]   // proxy SKNode → ARAnchor
```

### startSpawning()

1. `gameMode == .projectorServer` → 即 return
2. `stopSpawning()` → アンカー辞書を全クリア
3. `ensureSlingshotAttached()`
4. `arBugScene?.onBugCaptured3D` / `onCaptureBug` コールバックを登録
5. `scheduleNextSpawn(delay: 0.9)`

### ensureSlingshotAttached()（冪等）

```swift
// projectorServer → return
// slingshotNode != nil → return
let sn = SlingshotNode()
slingshotNode = sn
arView?.pointOfView?.addChildNode(sn)
gameManager?.slingshotDragUpdate = { [weak self] offset, isDragging in
    self?.cachedDragOffset = offset; self?.cachedIsDragging = isDragging
}
gameManager?.onNetFired = { [weak self] dragOffset, power in
    self?.launchNet3D(dragOffset: dragOffset, power: power)
}
```

### spawnBug()

```swift
// currentBugCount >= 5 → 1.0s 後に再試行
let distance        = Float.random(in: 0.5...1.4)
let horizontalAngle = Float.random(in: -0.65...0.65)
let verticalOffset  = Float.random(in: -0.30...0.45)
// camera-local → world 変換
let baseTransform = gameManager?.worldOriginTransform ?? frame.camera.transform
let worldPos = baseTransform * simd_float4(
    distance * sin(horizontalAngle), verticalOffset,
    -distance * cos(horizontalAngle), 1)
// ARAnchor をセッションに追加、bugAnchorMap に登録
// normalizedX = horizontalAngle / 0.65
// normalizedY = (verticalOffset - (-0.30)) / (0.45 - (-0.30))
// sendBugSpawned(id:type:normalizedX:normalizedY:)
// 難易度カーブ: nextDelay = max(1.5, 3.5 - spawnElapsed / 75.0)
```

**randomBugType()**: butterfly 60% / beetle 40%  
※ stag (toy_drummer.usdz) はパフォーマンス軽量化のため除外

### session(_:didAdd:) — ARSessionDelegate（nodeFor: の代替）

```swift
// 1. bugAnchorMap から BugType 取得
// 2. Bug3DNode(type:) を生成
// 3. proxy SKNode（name="bugContainer"）+ BugNode(type:) 子として生成
// 4. 各辞書に登録（mapLock 下）
// 5. DispatchQueue.main.async で arBugScene に proxy を追加、fadeIn(0.25s)
// 6. Bug3DNode.entity を AnchorEntity(anchor:) に追加（RealityKit が anchor 位置に配置）
```

### renderer(_:updateAtTime:) — 毎フレーム

```swift
// 1. slingshotNode?.parent == nil → pointOfView に遅延アタッチ
// 2. cachedIsDragging → SlingshotNode.updateDrag / resetDrag
//    wasSlingshotDragging で resetDrag を 1 フレームのみ呼ぶ
// 3. mapLock 下でスナップショット取得、ロック解放後に投影計算
// 4. 各 Bug3DNode:
//    scale = clamp(referenceDistance(3.0) / distance, 0.3, 5.0)
//    projected = arView.projectPoint(bug3D.worldPosition)
//    skPoint = (projected.x, cachedViewHeight - projected.y)
//    projected.z が 0〜1 の範囲内のみ更新
// 5. DispatchQueue.main.async でプロキシ位置を一括更新
```

### launchNet3D(dragOffset:power:)

```swift
// カメラ変換から basis vectors 取得（columns）
let maxDrag: Float = 300   // SlingshotView.maxDragDistance と一致
let normX = Float(-dragOffset.width  / 300)
let normY = Float( dragOffset.height / 300)
let direction = normalize(fwd + right * normX * 0.35 + up * normY * 0.35)
// フォーク世界座標（カメラ空間でのポーチ位置）
let forkCam = simd_float4(0, -0.12, -0.28, 1)
let forkW   = cameraT * forkCam
let net = Net3DNode(playerIndex: 0)
arView.scene.rootNode.addChildNode(net)
net.launch(from: SCNVector3(forkW.x, forkW.y, forkW.z),
           direction: SCNVector3(direction.x, direction.y, direction.z),
           power: power) { [weak net] in net?.removeFromParentNode() }
```

---

## Controller/ARBugScene.swift

`SKScene`（`backgroundColor = .clear`）。照準・ロックオン・捕獲の全 UI を担当。

### 定数

```swift
static let catchRadius: CGFloat         = 150    // ロックオン捕獲半径（画面中央からの距離）
private static let distortionPerBug: CGFloat = 0.50  // バグ 2 匹で distortionLayer 最大
// ← BugHunterScene の 0.38 とは異なる値
```

### crosshair / lockOn ノード

```swift
// lockOnRing: SKShapeNode(circleOfRadius:58), orange, lineWidth=3.5, alpha=0
// crosshairRing: SKShapeNode(circleOfRadius:54), cyan(0.2,1.0,0.8,0.85), lineWidth=2.5
//   idle pulse: scale 1.07→1.0 (0.85s サイクル)
// 中央ドット: SKShapeNode(circleOfRadius:5), fill=cyan
// 4方向ティック: gap=64pt, length=14pt, cyan, lineWidth=2.5
```

### distortionLayer（ARBugScene 版・12本）

```swift
// 全体ティント: SKColor(0.55, 0.0, 0.55, 0.07), zPosition=-1
// 12 本のバー（3〜14pt 高）: 赤/紫/シアン/オレンジ各3本
// 各バー独立フリッカー: wait 0.3〜5.0s, on 0.03〜0.14s, hold 0.02〜0.10s, off 0.05〜0.22s
// updateDistortion(bugCount:): alpha → min(count×0.50, 1.0), duration=0.6s
```

### fireNet(angle:power:)

```swift
SoundManager.shared.playThrow()
// 第 1 段階: catchRadius(150pt) 以内の最近傍 bugContainer を closest とする
// 第 2 段階（closest==nil）: 弾道判定
//   hitBand=90pt, netRange=power×max(W,H)×0.8+200pt
//   正射影 0<proj≤netRange かつ perp<hitBand の最小 proj のバグ
// flyTarget: closest → bugPos×55% / else → center + direction×(power×180+120)
playNetThrowAnimation(toward: flyTarget)
if closest { catchBug(container:bugNode:) } else { playMissAnimation(near:center) }
```

### catchBug(container:bugNode:)

```swift
SoundManager.shared.playCapture(points: pts)

// ── 1. 0.20s 後: onBugCaptured3D コールバック（Bug3DNode.captured() 開始）──

// ── 2. 3層 net エンタングルメント（playNetEntangle） ───────────────────────
// Main net (🕸️ 88pt, zPosition=62):
//   flyTo bugCenter (0.20s, spin -2.4π, scale 1.65)
//   → billow (scale 2.7, rotate -0.3π, 0.07s)
//   → cinch  (scale 0.50, rotate +1.3π, 0.24s)
//   → wait 0.38s → shrink + fadeOut (scale 0.20, 0.26s) → remove
// Binding strands × 4 (🕸️ 30pt, zPosition=61):
//   各 delay=i×0.04+0.22s, 角度=[π/5, π/5+π, 3π/5, 3π/5+π]
//   reach 46pt 先スナップ(0.06+0.09s) → bugCenter へ収縮 (0.14s) → wait 0.28s → fadeOut 0.18s
// 収縮リング (radius=54, 黄色):
//   wait 0.20s → appear (scale 0.88, alpha 0.85, 0.06s) → cinch (scale 0.22, 0.32s)
//   → wait 0.22s → fadeOut 0.18s

// ── 3. ヒールリップル（playHealRipple） ─────────────────────────────────────
// SKShapeNode(circleOfRadius:20), cyan: scale×5.0 + fadeOut (0.55s)

// ── 4. 画面フラッシュ ────────────────────────────────────────────────────────
// SKColor(0.3, 1.0, 0.9, 0.32) 全画面矩形 → fadeAlpha(0, 0.30s) → remove

// ── 5. スコアポップ ──────────────────────────────────────────────────────────
// pts==5: "⭐+5pts" (64pt HiraginoSans-W7, cyan)
// else: "+Xpts" (54pt HiraginoSans-W7, 金黄色)
// scale 0.4→1.2 (0.18s) + moveBy(0, 70, 0.60s) + fadeOut(0.30s)

// ── 6. 照準フラッシュ ────────────────────────────────────────────────────────
// pulseCrosshair(success:true): 緑→scale 1.4→1.0→cyan

// ── 7. ARAnchor 削除 ────────────────────────────────────────────────────────
// DispatchQueue.main.asyncAfter(+1.2s) { onCaptureBug?(container) }
score += pts
```

### playNetThrowAnimation(toward:)

```swift
// 🕸️ (fontSize=64pt) を center から flyTarget に向けて発射
// 0→2.0 倍拡大 (0.30s) + 270° 回転 (0.42s) + fadeOut (0.22s 後に開始, 0.20s)
// 白い展開リング (radius=28pt): 0.3→3.8 倍 + fadeOut (0.45s)
```

### playMissAnimation(near:)

```swift
pulseCrosshair(success: false)   // 赤フラッシュ
SoundManager.shared.playMiss()
// "MISS" (fontSize=42, 赤): fadeIn(0.08s) + moveBy(0,28,0.38s) → fadeOut(0.20s)
```

### endGame()

```swift
SoundManager.shared.playGameEnd()
// 全 bugContainer フェードアウト(0.5s) + remove
// distortionLayer.fadeOut(0.7s)
// gameDelegate?.sceneDidFinish(self, finalScore: score)
// 黒半透明(alpha=0.45)全画面矩形をフェードイン(0.7s) showEndOverlay
```

---

## Shared/GameProtocol.swift

### BugType

```swift
enum BugType: String, CaseIterable, Codable {
    case butterfly  // Null Bug:  1pt, speed=110, size=40, emoji="🐞", rarity="Common"
    case beetle     // Virus Bug: 3pt, speed=70,  size=55, emoji="🦠", rarity="Rare"
    case stag       // Glitch:    5pt, speed=45,  size=70, emoji="👾", rarity="Epic"
}
// computed: points / emoji / displayName / speed / size / speedLabel / rarityLabel / lore
```

### MessageType & GameMessage

```swift
enum MessageType: String, Codable {
    case launch; case startGame; case resetGame; case bugSpawned; case bugRemoved
    case gameState; case bugCaptured  // 後方互換のみ（送信なし）
}
struct LaunchPayload:     Codable { let angle: Float; let power: Float; let timestamp: Double }
struct BugSpawnedPayload: Codable { let id: String; let bugType: BugType
                                    let normalizedX: Float; let normalizedY: Float }
struct BugRemovedPayload: Codable { let id: String }
struct BugCapturedPayload: Codable { let bugType: BugType; let playerIndex: Int }  // 後方互換
struct GameStatePayload:  Codable { let state: String; let score: Int; let timeRemaining: Double } // 後方互換
```

### PhysicsCategory

```swift
struct PhysicsCategory {
    static let none: UInt32 = 0
    static let bug:  UInt32 = 0x1 << 0
    static let net:  UInt32 = 0x1 << 1
}
```

---

## Controller/Bug3DNode.swift

RealityKit `Entity` ラッパー。USDZ モデル優先（Entity.loadAsync で事前ロードし、clone 後に availableAnimations ループ）、不在時は手続き的 PBR ジオメトリにフォールバック。

### USDZ モデルマッピング

| BugType | USDZ ファイル | usdzScale |
|---------|-------------|-----------|
| butterfly | toy_biplane.usdz | 0.005 |
| beetle | gramophone.usdz | 0.004 |
| stag | toy_drummer.usdz | 0.004 |

Apple AR Quick Look ギャラリー（https://developer.apple.com/jp/augmented-reality/quick-look/）から取得。

### preloadAssets()（static）

- `Entity.loadAsync(named:)` を使って USDZ を事前ロードする。
- `NSLock` 保護の `entityCache` / `loadingInProgress` で重複ロードを防ぐ。
- プリロード未完了または失敗時は `init(type:)` 側が手続きジオメトリにフォールバックする。

```swift
// qos: .userInitiated バックグラウンドスレッドで非同期ロード
// NSLock + loadingInProgress: Set<String> で重複 I/O 防止
// entityCache[bugType.rawValue] = Entity (cloned per bug)
// availableAnimations + playAnimation(.repeat(duration: .infinity)) でアニメ自動再生
```

`ARGameView.makeUIView` と `WorldViewController.viewDidLoad` の **両方** から呼び出す。

### 手続き的ジオメトリ（フォールバック）

#### butterfly (Null Bug) — PBR 定数

```swift
// abdomen: SCNCapsule(capRadius:0.009, height:0.048)
//   diffuse(0.10, 0.05, 0.01), roughness=0.65, metalness=0.02
//   emission(0.0, 0.14, 0.35)  ← シアンブルー
// head: SCNSphere(r=0.011) at (0, 0.033, 0)
// upper wings: SCNPlane(0.095×0.070), pivot uvR/uvL at (x=±0.009, y=0.008)
//   diffuse(0.95, 0.50, 0.05, 0.90), emit(0.22,0.08,0.0,0.22)
//   roughness=0.70, metalness=0.0, isDoubleSided=true, transparency=0.08
// lower wings: SCNPlane(0.065×0.052), pivot lwR/lwL at (x=±0.007, y=-0.004)
//   diffuse(0.82, 0.35, 0.05, 0.88), emit(0.18,0.06,0.0,0.18)
// antennae: SCNCylinder(r=0.0018, h=0.036) + SCNSphere(r=0.004) tip
//   at (x=±0.010, y=0.051), eulerZ=±π/7
```

**butterfly アニメ**: 翼 pivot の Z 軸フラッピング（±π/2, 0.12〜0.16s; 下翼は amplitude×0.75, period×1.06）+ body Y 回転 9.0s

#### beetle (Virus Bug) — PBR 定数

```swift
// shellMat: diffuse(0.55, 0.08, 0.08), roughness=0.14, metalness=0.62
//   emission(0.0, 0.18, 0.04)  ← 毒グリーン
// body: SCNSphere(r=0.040), scale(1.05, 0.68, 1.22)
// suture: SCNCylinder(r=0.0028, h=0.074), eulerX=π/2, at (0, 0.022, 0)
//   diffuse(0.18, 0.02, 0.02), roughness=0.08, metalness=0.72
// thorax: SCNSphere(r=0.022) at (0, 0.006, -0.052)
// head: SCNSphere(r=0.018) at (0, 0.002, -0.076)
// eyes: SCNSphere(r=0.007) at (±0.015, 0.010, -0.080)
//   diffuse(0.04, 0.04, 0.04), roughness=0.04, metalness=0.08
// legs: 3 pairs, legZ=[0.010, -0.025, -0.052], outAngle=[π/2.2, π/2.5, π/2.3]
//   diffuse(0.22, 0.04, 0.04), roughness=0.40, metalness=0.28
// antennae: SCNCylinder(r=0.0016, h=0.028) + SCNSphere(r=0.003) tip
//   at (x=±0.010, z=-0.080), eulerX=-π/8, eulerZ=±π/6
```

**beetle アニメ**: Y 回転 5.5s + Z 軸ロック（±π/18, 0.38s サイクル、easeInEaseOut）

#### stag (Glitch Bug) — PBR 定数

```swift
// darkMat: diffuse(0.14, 0.08, 0.02), roughness=0.20, metalness=0.65
//   emission(0.28, 0.05, 0.0)  ← 赤オレンジ
// body: SCNCapsule(capRadius:0.028, height:0.068)
// thorax: SCNSphere(r=0.024) at (0, 0.050, 0)
// head: SCNSphere(r=0.022) at (0, 0.082, 0)
// eyes: SCNSphere(r=0.006) at (±0.018, 0.090, 0.014)
// mandibles: SCNCapsule(r=0.005, h=0.052) at (±0.022, 0.106, 0.010)
//   eulerX=π/2.2, eulerZ=±π/8
//   inner tooth: SCNCone(top=0, bottom=0.005, h=0.013) at (±0.006, 0, -0.012), eulerX=-π/3
// legs: 3 pairs, legY=[0.038, 0.008, -0.024], outAngle=[π/2.6, π/2.5, π/2.4]
// antennae: SCNCylinder(r=0.0018, h=0.030) + SCNSphere(r=0.003) tip
//   at (x=±0.015, y=0.090, z=0.012), eulerX=-π/5, eulerZ=±π/5
```

**stag アニメ**: Y 回転 7.5s + X 軸頷き（±π/22, 1.4s サイクル、easeInEaseOut）

#### addLeg ヘルパー

```swift
// upper: SCNCylinder(r=0.0040, h=0.026)
// knee = origin + (sign×0.026×sin(outAngle), -0.026×cos(outAngle))
// lower: SCNCylinder(r=0.0030, h=0.022), lowerAngle=outAngle+π/6
// legMat: diffuse(バグ種別色), roughness=0.40, metalness=0.28
```

### startAnimations()（全 Bug 共通）

```swift
opacity = 0; runAction(.fadeIn(duration: 0.25))
// 共通ホバー: ±0.018m、easeInEaseOut、random 0.65〜0.85s サイクル
// 二次水平ドリフト（+X→-Z→-X→+Z 正方形軌道、±0.010m、random 6.5〜8.5s サイクル）
```

### captured() アニメーション

```swift
removeAllActions()
// 1. Impact jolt: scale → 1.30 (0.04s)
// 2. Violent thrash (group):
//    Y: rotateBy(π×1.8, 0.10s) + (-π×1.2, 0.08s) + (π×0.7, 0.07s)
//    X: rotateBy(π×0.55, 0.09s) + (-π×0.40, 0.08s)
//    Z: rotateBy(π×0.65, 0.09s) + (-π×0.45, 0.07s)
//    scale: 0.78(0.10s) → 1.18(0.08s) → 0.62(0.07s)
// 3. Net constricts: scale → 0.22 (0.26s, easeIn)
// 4. Glitch blinks (blinkDur=0.055s):
//    isEnabled: false → true → false → true
// 5. Dissolve: 0.22s 後に isEnabled = false → removeFromParent
```

---

## Controller/ForestEnvironment.swift

「森の中でバグ取り」の雰囲気を作る静的 3D 木エンティティ植林ユーティリティ（`enum` — インスタンス不要）。

### 公開 API

```swift
/// AR（パススルー）シーンに 12 本の木を植林する。
static func plantARTrees(in arView: ARView, origin: simd_float4x4?)

/// プロジェクター（非 AR）シーンに 16 本の木を植林する。
static func plantProjectorTrees(in arView: ARView)
```

### 木の構造

各木は `Entity` ルート＋ `ModelEntity` の子（幹・葉冠）で構成。`PhysicallyBasedMaterial` を使用（roughness 0.88、metalness 0.0）。

```
root Entity
├── trunk  ModelEntity  (generateBox, cornerRadius, 茶色)
└── foliage … variant に応じた 1〜3 個の ModelEntity
```

### シルエット variants

| variant | 形状 | 使用プリミティブ |
|---------|------|-----------------|
| 0 — round | 単一大球 | generateSphere × 1 |
| 1 — conical | 幅が上に狭まる 3 段ボックス | generateBox × 3 |
| 2 — layered | 高さ・サイズの異なる 3 球重ね | generateSphere × 3 |

### 配置（AR）

- 呼び出し元: `ARGameView.Coordinator.startSpawning()` — ゲーム開始時に 1 回だけ実行
- `worldOriginTransform` 基準で変換（nil なら identity）
- Y オフセット: −1.2 m（眼線キャリブレーション → 床面）
- 12 本を前半円・側面・背面・遠方に配置（半径 2〜5 m）

### 配置（プロジェクター）

- 呼び出し元: `ProjectorBug3DCoordinator.attach(to:bugScene:)` — ゲーム開始時に 1 回だけ実行
- バグ平面（Z=0）の後方（Z=−1.5〜−4.2）と画面左右側面列に 16 本
- 木の高さ: 1.1〜2.2 ユニット（シーン単位 ≒ 1 m）

---

## Controller/SlingshotNode.swift

RealityKit `Entity` ラッパー。`AnchorEntity(.camera)` の子として追加し、カメラ空間に固定表示。

### ジオメトリ定数（forkRoot ローカル座標）

```swift
// camera-local での forkRoot 全体位置（arView.pointOfView の子として配置）
private static let forkCenter    = SCNVector3(0, -0.09, -0.26)

// forkRoot ローカル座標（フォークの各頂点）
private static let stemBottom    = SCNVector3(0, -0.058, 0)
private static let branch        = SCNVector3(0,  0.006, 0)
private static let leftTip       = SCNVector3(-0.052,  0.068, -0.005)
private static let rightTip      = SCNVector3( 0.052,  0.068, -0.005)
private static let neutralPull   = SCNVector3(0, 0.042, 0.0)  // 待機時のポーチ位置

// ドラッグ変形量（最大値）
private static let maxPullDepth:    Float = 0.080   // +Z 方向（カメラ側に引く）
private static let maxPullLateral:  Float = 0.022   // 横方向
private static let maxPullDown:     Float = 0.012   // 下方向
```

### マテリアル

```swift
// フォーク本体（bodyMat）— 暗いアノダイズドメタル
// diffuse(0.09, 0.09, 0.11), roughness=0.28, metalness=0.85

// チップ装飾（tipMat）— ネオンシアン発光キャップ
// diffuse(0.10, 1.00, 0.82), roughness=0.25, metalness=0.10, emission(0.04, 0.48, 0.36)

// ゴム紐（bandMat）— ネオンシアン
// diffuse(0.08, 0.92, 0.70), roughness=0.50, metalness=0.0, emission(0.03, 0.38, 0.26)

// ポーチ（neonMat）— ネオングリーン球
// diffuse(0.08, 0.90, 0.66), roughness=0.30, metalness=0.08, emission(0.03, 0.36, 0.24)
```

### ノード構成

```
forkRoot (position = forkCenter)
├── stem: cylinderBetween(stemBottom, branch, r=0.008, bodyMat)
├── leftTine: cylinderBetween(branch, leftTip, r=0.007, bodyMat)
├── rightTine: cylinderBetween(branch, rightTip, r=0.007, bodyMat)
├── leftTipCap: ModelEntity(sphere r=0.010, tipMat) at leftTip
├── rightTipCap: ModelEntity(sphere r=0.010, tipMat) at rightTip
├── leftBandEntity: ModelEntity(box h=1.0, bandMat) — alignBand で毎フレーム scale.y + orientation 更新
├── rightBandEntity: ModelEntity(box h=1.0, bandMat) — alignBand で毎フレーム scale.y + orientation 更新
└── pouchEntity: ModelEntity(sphere r=0.012, neonMat), isEnabled=false（ドラッグ中のみ表示）
```

### updateDrag(offset:maxDrag:)

```swift
let nx = Float(offset.width  / maxDrag)   // -1〜1
let ny = Float(offset.height / maxDrag)   // 0〜1
pullPoint = SIMD3<Float>(
     nx * maxPullLateral,      // 横 ±0.022m
     neutralPull.y - ny * maxPullDown,  // 下 0.012m
     ny * maxPullDepth         // +Z カメラ側 0.080m
)
updateBands()   // leftBandEntity / rightBandEntity を alignBand で更新
pouchEntity.isEnabled = true
```

### alignBand(_:from:to:)

Y 軸 → 方向ベクトルへのクォータニオン回転（cross product + 1+dot）。entity.scale.y に長さを設定。アンチパラレル（dot < -0.9999）の場合は X 軸で 180° 反転。

---

## Controller/Net3DNode.swift

RealityKit `Entity` ラッパー。ARView 空間を飛翔する 3D 網メッシュ。

### ノード構成

```swift
// accentColors: [cyan(0,1,1), orange(1,0.55,0), magenta(1,0.2,0.8)]
// rimMat: accent + emission(accent×0.45), roughness=0.55, metalness=0.20
// meshMat: diffuse(0.30,0.90,0.45,0.90), roughness=0.80, isDoubleSided=true
// rim: SCNTorus(ringRadius=0.042, pipeRadius=0.0045), eulerAngles=(π/2,0,0)
// spokes × 8: SCNBox(0.082×0.0015×0.0015), eulerZ=i×π/4
// innerRings: SCNTorus r=0.020, SCNTorus r=0.032, eulerAngles=(π/2,0,0)
// castsShadow = false
```

### launch(from:direction:power:completion:)

```swift
// speed    = 2.0 + power × 3.5   (2.0〜5.5 m/s)
// velocity: vx/vy/vz = direction × speed
// g        = -9.0 m/s²（放物線重力）
// travelTime = 0.60 + power × 0.40   (0.60〜1.00 s)
// 発射時向き: eulerAngles.y = atan2(dir.x, -dir.z)

// physicsMove（放物線キネマティクス）:
// 60fps Timer { elapsed in  // kinematic physics directly
//     let t = Float(elapsed)
//     node.position = SCNVector3(ox+vx*t, oy+vy*t + 0.5*g*t*t, oz+vz*t)
// }
// spinZ = rotateBy(z: 2π×(0.8+power×2.0), duration:travelTime), easeOut
// spinX = rotateBy(x: π×turns×0.45, duration:travelTime), easeOut
// scaleSeq: 0.22 → 1.0(30%) → 1.0(42%) → 0.55(28%)
// fadeSeq: 各 ModelEntity の PBR マテリアル α を 60fps Timer で更新して fadeIn/fadeOut
// group([physicsMove, spinZ, spinX, scaleSeq, fadeSeq]) → completion()
```

---

## Controller/SlingshotView.swift

SwiftUI フルスクリーンオーバーレイ。ジェスチャ管理専用（3D 描画は SlingshotNode / Net3DNode が担当）。

```swift
private let maxDragDistance: CGFloat = 300   // ← 正しい値は 300（220 ではない）
private static let forkYRatio: CGFloat = 0.62
private static let forkHeight: CGFloat = 130
```

### fireSlingshot(sceneSize:)

```swift
let power = Float(min(dragLength / 300, 1.0))
let dx    = -dragOffset.width;  let dy = dragOffset.height   // dy は反転しない
let angle = Float(atan2(dy, dx))
if gameManager.state == .ready { gameManager.confirmReady() }
gameManager.onNetFired?(dragOffset, power)
withAnimation(.spring(response: 0.25)) { dragOffset = .zero }
gameManager.slingshotDragUpdate?(.zero, false)
gameManager.sendLaunch(angle: angle, power: power)
```

### PowerIndicatorView

```swift
// power <0.4: 緑 / 0.4..<0.7: 黄 / 0.7+: 赤
// バー幅=90pt×power、バー高さ=10pt、cornerRadius=4
// 「Power」ラベル (caption2.bold, white)
// padding: horizontal 10pt, vertical 6pt; background black×0.4; cornerRadius 8
```

---

## Controller/SoundManager.swift

`AVAudioEngine` + `AVAudioPlayerNode × 6` によるシングルトン（`SoundManager.shared`）。PCM サイン波をランタイム生成。外部音声ファイルなし。

### 音声セッション

```swift
// .ambient カテゴリ: 他アプリ音楽と共存、サイレントスイッチでも消音されない
// options: [.mixWithOthers]
```

### サウンド一覧（全周波数）

| メソッド | 生成方法 | 周波数 / 音階 | 秒数 | 振幅 |
|---------|---------|-------------|------|-----|
| `playThrow()` | makeSweep | 550→200 Hz | 0.14s | 0.40 |
| `playCapture(points:1)` | playSequence | A5(880.0), C#6(1108.73) Hz | noteDur=0.16s, gap=0.065s | 0.42 |
| `playCapture(points:3)` | playSequence | E5(659.25), G5(783.99), B5(987.77) Hz | same | same |
| `playCapture(points:5)` | playSequence | C5(523.25), E5(659.25), G5(783.99), C6(1046.5) Hz | same | same |
| `playMiss()` | makeSweep | 280→120 Hz | 0.22s | 0.32 |
| `playLockOn()` | makeTone | 1200 Hz | 0.055s, fadeIn=0.005s, fadeOut=0.025s | 0.28 |
| `playGameStart()` | playSequence | C5, E5, G5, C6 | noteDur=0.20s, gap=0.095s | 0.38 |
| `playGameEnd()` | playSequence | G5(783.99), E5(659.25), C5(523.25), G4(392.0) Hz | noteDur=0.26s, gap=0.11s | 0.36 |

### バッファ生成

```swift
// makeTone: samples[i] = amplitude × envelope(t) × sin(2π × freq × t)
// makeSweep: 位相累積方式; freq(t) = start + (end-start) × (t/duration)
// envelope: fadeIn 区間で線形上昇、fadeOut 区間で線形下降、中間は 1.0
// playSequence: DispatchQueue.global(.userInteractive).asyncAfter(delay=noteGap×i)
```

---

## World/WorldViewController.swift

プロジェクター側のルート `UIViewController`。

### viewDidLoad レイアウト

```swift
// scnView.backgroundColor = UIColor(red:0.05, green:0.12, blue:0.05, alpha:1)
// scnView.autoenablesDefaultLighting = false
// skView.backgroundColor = .clear; isOpaque=false; allowsTransparency=true
// 両ビューを Auto Layout 4辺固定（フルスクリーン）
// Bug3DNode.preloadAssets() を呼び出し（iOS AR パスと同様に必須）
// ConnectedPlayersView: trailing-16, bottom-16, width=220 (Auto Layout)
```

### startGame()

```swift
bug3DCoordinator?.stopSpawning(); bug3DCoordinator = nil; gameScene = nil
let scene = BugHunterScene(size: skView.bounds.size)
scene.scaleMode = .resizeFill; scene.isProjectorMode = true
skView.presentScene(scene, transition: .fade(0.5s)); gameScene = scene
let coordinator = ProjectorBug3DCoordinator()
coordinator.attach(to: scnView, bugScene: scene)
bug3DCoordinator = coordinator
```

---

## ProjectorBug3DCoordinator（WorldViewController.swift 内に定義）

`final class ProjectorBug3DCoordinator: NSObject`

### カメラ・スケール定数

```swift
private static let cameraZ:            Float   = 3.5
private static let cameraFOV:          CGFloat = 65     // 垂直 FOV 度
private static let bugScaleMultiplier: Float   = 10     // Bug3DNode 表示スケール
private static let spawnMargin:        Float   = 1.25   // 画面外スポーン余白比
```

### attach(to:bugScene:)

```swift
scnView.scene = scnScene; scnView.isPlaying = true
startAutonomousSpawning()  // ← 電話接続なしでも自律スポーン開始
```

### addSyncedBug(id:type:normalizedX:normalizedY:)

```swift
// normalizedX(-1〜1) → x = normalizedX × halfW × 0.70
// normalizedY(0〜1)  → y = (normalizedY×2-1) × halfH × 0.60
// Bug3DNode を s=10 でスケール; start scale = s×0.1 (pop-in)
// 出現アニメ: fadeIn(0.4s) + scale→s(0.4s)
// ホバー: moveBy(0, halfH×0.06, 0, 1.8s), easeInEaseOut, repeatForever (key="hover")
```

### 自律スポーン（Autonomous Spawning）

**重要**: 電話接続なしでも常時バグが出現する機能。`attach()` から自動的に開始。

```swift
// startAutonomousSpawning():
//   autonomousSpawnTimer を reset; autonomousStartTime = Date()
//   scheduleNextAutonomousSpawn(after: 1.5s)

// spawnAutonomousBug():
//   elapsed = Date().timeIntervalSince(autonomousStartTime)
//   4辺のいずれかからランダムスポーン（spawnMargin=1.25 倍先）
//   2〜3 個の内部経由点（halfW×0.75, halfH×0.65 内）を通る bugAnchor.move(to:duration:) シーケンス
//     move(to:, duration: segDur), easeInEaseOut
//   最後に反対エッジに退場（spawnMargin×1.04 倍先）
//   bugDuration = max(4.0, min(600.0 / Double(bugType.speed), 14.0))
//   segDur = bugDuration / (waypointCount + 1)
//   DispatchQueue.asyncAfter → arView.scene.removeAnchor(bugAnchor)
//   autonomousBugs: [Bug3DNode] で追跡（bug3DNodes とは別）

// 自律スポーン間隔:
//   max(0.6, 1.8 - elapsed / 90.0)   (1.8s → 0.6s over 90s)

// 出現確率: butterfly 60% / beetle 40%  ※ stag は除外（パフォーマンス軽量化）
```

### notifyBugCountChanged()

```swift
let total = autonomousBugs.count + bug3DNodes.count
bugScene?.updateWorldDistortion(bugCount: total)   // distortionLayer 強度更新
```

---

## World/BugHunterScene.swift

プロジェクター用 `SKScene`。透過オーバーレイとして機能。

```swift
var isProjectorMode: Bool = false
// backgroundColor: isProjectorMode ? .clear : SKColor(0.05, 0.12, 0.05)
// physicsWorld.gravity = .zero
// isProjectorMode == true → setupDistortionLayer() 呼び出し
// タイマー・スコア・HUD・BugSpawner・physicsContactDelegate なし（スマホ主導）
```

### distortionLayer（BugHunterScene 版）

```swift
private static let distortionPerBug: CGFloat = 0.38
// 0 匹→0% / 1 匹→38% / 2 匹→66% / 3 匹→100%（ARBugScene の 0.50 と異なる）
// 14 本のバー（ARBugScene は 12 本）: 高さ 3〜16pt
// 紫赤ティント: SKColor(0.60, 0.0, 0.60, 0.06)
// updateWorldDistortion(bugCount:) → fadeAlpha(to: min(count×0.38, 1.0), duration: 0.7s)
```

---

## World/NetProjectile.swift

`SKNode`（`name="net"`）。プロジェクター画面を飛翔する網 SKNode。

### 構成

```swift
// playerColors: [cyan(0,1,1), orange(1,0.55,0), magenta(1,0.2,0.8)]
// netShape: CGPath(outerRadius:34, spokeCount:8, ringCount:3)
//   stroke: SKColor(0.30,0.92,0.45,0.95), fill: SKColor(0.10,0.55,0.20,0.12)
//   lineWidth=2.2, lineCap=.round
// ringNode: circleOfRadius=38, stroke=playerColor×0.80, fill=playerColor×0.06, lineWidth=3.5
// centerDot: circleOfRadius=6, fill=playerColor
// physicsBody: circleOfRadius=44, isDynamic=true, affectedByGravity=false
```

### launch(angle:power:from:sceneSize:)

```swift
// travelSpeed = power×1400+500 pt/s (500〜1900)
// travelTime = 0.55s
// dx=cos(angle)×travelSpeed×0.55, dy=sin(angle)×travelSpeed×0.55
// baseMove(easeOut) + arcAction(up=sceneH×0.06×|cos|×(power+0.3), easeOut/easeIn 0.22/0.33s)
// unfurl: scale 0.3→1.3(0.35×0.55s) → 1.0(0.65×0.55s)
// ringNode: scale 0.4→3.2 + alpha 0.85→0.5(0.25s) → 0(0.25s)
// spin: rotate(π×(1.5+power×2), 0.55s), easeOut
// group([baseMove, arcAction, unfurl, spin]) → removeFromParent
```

---

## World/ProjectorGameManager.swift

```swift
static let serviceType = "bughunter-game"
static let maxPlayers  = 3
// MCSession(encryptionPreference:.required)
// MCNearbyServiceAdvertiser + MCNearbyServiceBrowser を同時使用
// start() / stop() で制御
// playerSlots: [MCPeerID: Int], usedSlots: Set<Int>
// 接続: 最小空きスロット(0,1,2)を割り当て
// 招待: usedSlots.count < maxPlayers の場合のみ accept
// 受信: すべて DispatchQueue.main.async で delegate に転送
```

---

## World/WaitingScene.swift

```swift
var isProjectorOverlay: Bool = false
// backgroundColor: isProjectorOverlay ? .clear : SKColor(0.04, 0.08, 0.04)

// タイトル "君は、バグハンター 🦟": HiraginoSans-W7, 80pt, white, (w/2, h×0.72)
//   パルスアニメ: scale 1.05→0.95 (1.2s サイクル)
// サブタイトル "You are the Bug Hunter": W3, 40pt, white×0.65, (w/2, h×0.62)
// 浮遊バグ [("🦋",1pt), ("🐛",3pt), ("🪲",5pt)]: spacing=240pt, y=h×0.40
//   ホバー: moveBy(0, 18, 1.0+i×0.5s サイクル), easeInEaseOut
// 接続待ちテキスト: W3, 34pt, white×0.55, (w/2, h×0.20), フェードブリンク (0.7s)
// 操作説明: W3, 30pt, white×0.45, (w/2, h×0.12)
```

---

## World/BugSpawner.swift / BugNode

```swift
// BugSpawner: 旧 SpriteKit スポーナー（BugHunterScene では現在未使用）
//   scheduleNextSpawn(delay:) → spawnBug() のループ
//   BugNode を randomEdgePosition に配置 → randomPath で bezier 移動 → remove

// BugNode（BugSpawner.swift 内に定義）:
//   physicsBody: circleOfRadius=type.size/2, isDynamic=false
//   category=bug(0x1), contactTest=net(0x2)
```

---

## 通信プロトコル（Multipeer Connectivity）

### フロー図

```
iOS Controller (×最大3台)               Projector Server
    │                                        │
    │── startGame ──────────────────────────>│ → startGame()
    │── launch(angle, power, timestamp) ────>│ → playerIndex で色分け + NetProjectile 発射
    │── bugSpawned(id, type, x, y) ─────────>│ → addSyncedBug: Bug3DNode 追加
    │── bugRemoved(id) ─────────────────────>│ → removeSyncedBug: captured() アニメで削除
    │── resetGame ───────────────────────── >│ → stopSpawning: 全 Bug3DNode 即削除
```

### normalizedX / normalizedY の計算

```swift
// iOS 側 spawnBug() で算出:
normalizedX = horizontalAngle / 0.65                          // -1〜1
normalizedY = (verticalOffset - (-0.30)) / (0.45 - (-0.30))  // 0〜1 (0=下, 1=上)
// プロジェクター側 addSyncedBug() で 3D 座標に復元:
x = normalizedX × halfW × 0.70
y = (normalizedY × 2.0 - 1.0) × halfH × 0.60
```

---

## バグ仕様

| 種類 | 列挙値 | emoji | ポイント | speed | size | 出現率 |
|------|--------|-------|---------|-------|------|-------|
| Null | `.butterfly` | 🐞 | 1pt | 110 | 40pt | 60% |
| Virus | `.beetle` | 🦠 | 3pt | 70 | 55pt | 40% |
| Glitch | `.stag` | 👾 | 5pt | 45 | 70pt | 0%（スポーン除外） |

---

## ゲームルール

| 項目 | 値 |
|------|---|
| 制限時間 | 90 秒 |
| スポーン間隔 | `max(1.5, 3.5 - spawnElapsed / 75.0)` 秒 |
| 初期スポーン遅延 | 0.9 秒 |
| 同時出現上限 | 5 匹（`maxActiveBugs=5`） |
| タイマー管理 | iOS 側のみ（`ARBugScene` が計時、`GameManager` が受信）|
| スコア管理 | iOS 側のみ（`GameManager.score`）|
| 最大接続 | 3 台（4 台目以降は `advertiser` が拒否） |
| プロジェクター表示 | 常時 3D シーン（待機・終了画面なし）|

---

## プロジェクター レイアウト

```
┌────────────────────────────────────────────────────┐
│  ARView(cameraMode:.nonAR, background: darkGreen, 背面) │ ← 常時アクティブ
│    camera: Z=3.5, FOV=65°                            │
│    Bug3DNode × n (phone-synced + autonomous)         │
│    scale ×10 で表示                                  │
│    autonomous: 電話接続なし時も 1.8s→0.6s 間隔でスポーン│
│  SKView (transparent, 前面)                          │
│    BugHunterScene (isProjectorMode=true, clear bg)   │
│    NetProjectile: 視覚的な網アニメ                    │
│    distortionLayer: 14 本グリッチバー, 0.38/bug       │
│  ConnectedPlayersView (UIKit, 右下, width=220)        │
└────────────────────────────────────────────────────┘
```

---

## コーディング規約

- **Swift 5.9+**。`final class` を基本とする。
- **BugType switch**: `default` を使わず網羅的 switch（新ケース追加時のコンパイルエラー検知）。
- **スレッド — UIKit**: RealityKit SceneEvents.Update はメインスレッドで発火するため UIKit への直接アクセスが安全（`cachedViewHeight` パターン不要）。
- **スレッド — アンカー辞書**: `ARGameView.Coordinator` の 4 辞書は `mapLock`（`NSLock`）で全アクセスを保護。
- **スナップショットパターン**: `renderer(_:updateAtTime:)` でロック下でスナップショット取得後、ロック解放して重い計算を行う。
- **Multipeer コールバック**: 常に `DispatchQueue.main.async` でメインスレッドに戻す。
- **アセット**: 外部画像・音声ファイルなし。すべて手続き的に生成。
- **定数**: `private static let` でクラスに閉じ込め、マジックナンバーを避ける。
- **スレッドセーフキャッシュ**: `Bug3DNode.cacheLock`（`NSLock`）を使用。

---

## よく使うコードパターン

### PBR マテリアル生成

```swift
let m = SCNMaterial()
m.diffuse.contents   = UIColor(red: 0.55, green: 0.08, blue: 0.08, alpha: 1)
m.roughness.contents = NSNumber(value: 0.14)
m.metalness.contents = NSNumber(value: 0.62)
m.emission.contents  = UIColor(red: 0.0, green: 0.18, blue: 0.04, alpha: 1)
m.lightingModel      = .physicallyBased
```

### 3D → 2D 座標変換

```swift
// ARView（iOS）
let proj = arView.projectPoint(bug3D.worldPosition)
// guard proj.z > 0 && proj.z < 1
let skPoint = CGPoint(x: CGFloat(proj.x), y: cachedViewHeight - CGFloat(proj.y))

// ARView(cameraMode:.nonAR)（プロジェクター）
let proj = scnView.projectPoint(SCNVector3(x, y, z))
let skPoint = CGPoint(x: CGFloat(proj.x), y: viewHeight - CGFloat(proj.y))
```

### Multipeer メッセージ送信

```swift
let msg = GameMessage.bugSpawned(BugSpawnedPayload(
    id: anchor.identifier.uuidString, bugType: .stag,
    normalizedX: 0.3, normalizedY: 0.6))
let data = try! JSONEncoder().encode(msg)
mcSession.send(data, toPeers: mcSession.connectedPeers, with: .reliable)
```

### SoundManager 呼び出し

```swift
SoundManager.shared.playThrow()
SoundManager.shared.playCapture(points: bugNode.points)
SoundManager.shared.playMiss()
SoundManager.shared.playLockOn()
SoundManager.shared.playGameStart()
SoundManager.shared.playGameEnd()
```

---

## 開発環境

| 項目 | バージョン |
|------|-----------|
| Swift | 5.9 以上 |
| iOS Deployment Target | iOS 17.0 以上 |
| Xcode | 15 以上 |
| フレームワーク | SwiftUI, UIKit, ARKit, RealityKit, SpriteKit, MultipeerConnectivity, Combine, AVFoundation |

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

- `ARView` と `SKView` を重ねる際 `SKView.allowsTransparency = true` かつ `SKView.isOpaque = false` が必須。
- **`SlingshotView.maxDragDistance = 300`**（SPEC.md・旧ドキュメントの 220 は誤り）。
- **`ARBugScene.distortionPerBug = 0.50`**（phone 側）、**`BugHunterScene.distortionPerBug = 0.38`**（projector 側）は異なる値。
- **`ProjectorBug3DCoordinator` には自律スポーン機能がある**（`startAutonomousSpawning()` が `attach()` から呼ばれる）。電話接続なしでも常時バグが出現する。
- `ProjectorGameManagerDelegate.managerDidReceiveReset` では `stopSpawning()` のみ呼ぶ（coordinator は破棄しない）。
- `ProjectorBug3DCoordinator` は `WorldViewController.swift` 内の `final class` として定義（別ファイルなし）。
- `ConnectedPlayersView` も `WorldViewController.swift` 内に定義（別ファイルなし）。
- Multipeer Connectivity コールバックはバックグラウンドスレッド → 必ず `DispatchQueue.main.async`。
- ARKit は実機専用。シミュレーターでは `ARSession` が起動しない。

---

## 未実装タスク

### 1. プロジェクター背景を「腐敗したデジタルワールド」に変更（優先度: 高）

| ファイル | 変更内容 |
|---------|---------|
| `World/WorldViewController.swift` | `arView.environment.background` を暗い青黒 `UIColor(red:0.03, green:0.03, blue:0.10)` に変更。RealityKit シーンに Tron グリッド床・背景壁を追加（Entity + generatePlane）。 |
| `World/WaitingScene.swift` | 背景色を暗い青黒に。マトリックスレイン・グリッドライン・スキャンライン・グリッチフラッシュを追加。 |
| `World/BugHunterScene.swift` | `isProjectorMode=true` のときグリッドライン・スキャンライン（低透明度）を追加（3D バグの視認性を損なわない程度）。 |

**カラーパレット**

```
背景ベース : UIColor(red: 0.03, green: 0.03, blue: 0.10, alpha: 1)
グリッドライン: UIColor(red: 0.0,  green: 0.6,  blue: 1.0,  alpha: 0.4)
マトリックス文字（ヘッド）: SKColor(red: 0.9, green: 1.0, blue: 0.9, alpha: 1.0)
マトリックス文字（テール）: SKColor(red: 0.0, green: 0.9, blue: 0.4, alpha: 0.0〜0.8)
腐敗色（一部文字）: SKColor(red: 0.8, green: 0.1, blue: 0.6)
グリッチフラッシュ: SKColor(red: 0.0, green: 1.0, blue: 0.5, alpha: 0.07)
スキャンライン: SKColor(white: 1.0, alpha: 0.05)
```

**WaitingScene 背景エフェクト実装ガイド**

```swift
// 1. グリッドライン (zPosition: -2): 48pt セル幅の縦横ライン、シアン alpha 0.07
// 2. マトリックスレイン (zPosition: -1): 0.08s ごとに spawnMatrixDrop()
//    Menlo-Bold 16pt、文字セット "01アイウエオカキクケコ#$%&ABCDEF0123456789"
//    落下速度 100〜250 pt/s、末尾一部文字をマゼンタで着色
// 3. スキャンライン (zPosition: 5): 高さ 2pt × 3 本、60〜120 pt/s でループ
// 4. グリッチフラッシュ (zPosition: 15): 3〜7s おきに alpha 0.07→0→0.04→0
```

**RealityKit 背景グリッド（ProjectorBug3DCoordinator.setupCamera に追加）**

```swift
// scnScene.background.contents = UIColor(red:0.03, green:0.03, blue:0.10, alpha:1)
// グリッド床: SCNPlane(20×20), eulerX=-π/2, position=(0,-2.8,-3)
// 背景壁: SCNPlane(20×12), position=(0,0,-4)
// makeGridTexture(): UIGraphicsImageRenderer(512×512), 64pt セル格子線
//   lineColor: UIColor(red:0.0, green:0.6, blue:1.0, alpha:0.4)
```
