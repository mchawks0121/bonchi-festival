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
│       .waiting     → WaitingView
│       .calibrating → CalibrationView（AR カメラ + 照準レティクル + 基準点設定ボタン）
│       .ready,.playing → PlayingView（同一 case で ARGameView インスタンスを維持したまま状態遷移）
│                         gameMode が .projectorServer なら ProjectorServerView、それ以外は ARPlayingView
│       .finished    → FinishedView
│
│     サブビュー:
│       WaitingView         — モード選択カード(ModeCard)、接続状態ピル、「バグ狩り開始」ボタン、
│                             バグ一覧カード(BugLegendRow)、ミッション説明。compact/regular レイアウト分岐あり。
│                             「バグ狩り開始」は startCalibration() を呼ぶ（projectorServer は直接 startGame()）。
│       CalibrationView     — UIViewRepresentable。ARSCNView フルスクリーン + UIKit オーバーレイ。
│                             中央に照準レティクル (CAShapeLayer)、説明ラベル、確定ボタン、戻るボタン。
│                             CalibrationCoordinator: confirmTapped → gameManager.setWorldOrigin(transform:) → .ready
│                                                      backTapped   → gameManager.resetGame()
│       ARPlayingView       — ARGameView（フルスクリーン） + ReadyOverlay (.ready 時) / HUD (.playing 時) + SlingshotView
│                             ARGameView は .ready,.playing 両状態で同一インスタンスを維持
│       ReadyOverlay        — 「スリングショットを引いて網を射出するとゲームスタート！」案内。allowsHitTesting=false
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
│   │     var worldOriginTransform: simd_float4x4? — キャリブレーション時に記録するスポーン基点
│   │     GameState 列挙: .waiting / .calibrating / .ready / .playing / .finished
│   │     GameMode 列挙: .standalone / .projectorClient / .projectorServer
│   │     selectMode(_:)        — モード切替。projectorClient 選択時に MultipeerSession.start()
│   │     startCalibration()    — .calibrating 状態へ遷移（projectorServer は直接 startGame()）
│   │     setWorldOrigin(transform:) — worldOriginTransform を記録して state = .ready に遷移
│   │     confirmReady()        — .ready → startGame() へ遷移（最初のスリングショット発射時に呼ばれる）
│   │     startGame()           — score=0 reset、ARBugScene 生成（非 projectorServer のみ）、multipeerSession.send(.startGame())（接続なし時 no-op）
│   │     resetGame()           — 全状態リセット（worldOriginTransform も nil に）、multipeerSession.send(.resetGame())（接続なし時 no-op）
│   │     sendLaunch(angle:power:) — ARBugScene.fireNet() + multipeerSession.send(.launch())（接続なし時 no-op）
│   │     sendBugSpawned(id:type:normalizedX:normalizedY:) — multipeerSession.send(.bugSpawned())（接続なし時 no-op、モード判定なし）
│   │     sendBugRemoved(id:) — multipeerSession.send(.bugRemoved())（接続なし時 no-op、モード判定なし）
│   │     ※ スタンドアロンとプロジェクタークライアントのスポーンシステムは完全共通（モード分岐なし）
│   │     slingshotDragUpdate: ((CGSize, Bool) -> Void)? — ARGameView.Coordinator がセット。SlingshotView がドラッグ毎に呼ぶ
│   │     onNetFired: ((CGSize, Float) -> Void)? — ARGameView.Coordinator がセット。SlingshotView が発射時に呼ぶ
│   │     resetGame() で slingshotDragUpdate / onNetFired を nil にクリア
│   │     BugHunterSceneDelegate: didUpdateScore/sceneDidFinish — standalone + projectorClient でスコアを state に反映
│   │     MultipeerSessionDelegate: bugCaptured 受信 → score += bugType.points（後方互換）
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
│   │       startSpawning() / stopSpawning() — standalone + projectorClient でバグをスポーン（projectorServer のみ除外）
│   │       ensureSlingshotAttached() — 冪等。SlingshotNode 未接続時のみ pointOfView に追加。.ready/.playing 両状態で呼ばれる
│   │       spawnBug() — カメラ前方 0.5〜1.4m, 水平 ±37°, 垂直オフセット -0.3〜0.45m に ARAnchor 配置
│   │         最大同時出現数: maxActiveBugs=5（超過時は 1.0s 後に再スケジュール）
│   │         スポーン後 sendBugSpawned(id:type:normalizedX:normalizedY:) でプロジェクターに通知
│   │         スポーン基点: gameManager.worldOriginTransform が非 nil ならそれを使用（固定エリア中心）、
│   │                       nil の場合は frame.camera.transform にフォールバック（後方互換）
│   │       randomBugType() — butterfly 60% / beetle 30% / stag 10%
│   │       renderer(_:nodeFor:) — ARAnchor → Bug3DNode (SCNNode) + 不可視プロキシ SKNode を生成
│   │       renderer(_:updateAtTime:) — 毎フレーム 3D→2D 変換でプロキシ位置同期、距離ベーススケール
│   │         scale = clamp(referenceDistance(3.0) / distance, 0.3, 5.0)
│   │         cachedViewHeight で UIKit アクセスをメインスレッドに限定
│   │         cachedDragOffset / cachedIsDragging → SlingshotNode.updateDrag() / resetDrag() を呼ぶ
│   │         wasSlingshotDragging フラグで resetDrag() を 1 フレームのみ呼ぶ
│   │         slingshotNode が未接続 (parent==nil) なら pointOfView に追加 (遅延アタッチ)
│   │       launchNet3D(dragOffset:power:): カメラ変換から方向ベクトルを計算し Net3DNode を発射
│   │         fork 世界座標 = cameraTransform × (0, -0.12, -0.28, 1)
│   │         direction = normalize(fwd + right×normX×0.35 + up×normY×0.35)
│   │       handleCapture(of:) — capture 時に Bug3DNode.captured() + sendBugRemoved(id:) + ARAnchor 削除
│   │     updateUIView: .ready 状態では ensureSlingshotAttached() を呼ぶのみ（stopSpawning しない）
│   │     antialiasingMode = .multisampling4X、lightingEnvironment.intensity = 1.5 (PBR 品質向上)
│   │     難易度カーブ: nextDelay = max(1.5, 3.5 - spawnElapsed / 75.0)
│   │
│   ├── ARBugScene.swift
│   │     SKScene (backgroundColor = .clear)。照準・ロックオン・捕獲の全 UI を担当。
│   │     BugHunterSceneDelegate プロトコルをこのファイルで定義:
│   │       func scene(_:didUpdateScore:timeRemaining:) — 毎フレームスコア/残り時間を通知
│   │       func sceneDidFinish(_:finalScore:) — タイムアップ時に最終スコアを通知
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
│   │     SCNNode サブクラス。USDZ モデル優先（Apple AR Quick Look ギャラリーのファイルを使用）。
│   │     USDZ が見つからない場合は手続き的 PBR ジオメトリにフォールバック。
│   │     モデルマッピング（USDZ ファイルを Xcode プロジェクトに追加して使用）:
│   │       butterfly → toy_biplane.usdz  (scale: 0.005)
│   │       beetle    → gramophone.usdz   (scale: 0.004)
│   │       stag      → toy_drummer.usdz  (scale: 0.004)
│   │     preloadAssets(): ゲーム起動直後にバックグラウンドで全 USDZ を非同期プリロード。
│   │       NSLock + loadingInProgress セットで重複 I/O 防止。スポーン時はキャッシュからクローン。
│   │     usdzScale(for:): 網羅的 switch でバグタイプ別スケール定数を返す（コンパイル時漏れ検知）。
│   │     butterfly (🐞):
│   │       abdomen: SCNCapsule(capRadius:0.009, height:0.048)、茶色 PBR + シアンブルーエミッシブ
│   │       upper wings: SCNPlane(0.095×0.070)、monarch オレンジ、半透明、isDoubleSided
│   │       lower wings: SCNPlane(0.065×0.052)、暗いオレンジ
│   │       antennae: SCNCylinder + SCNSphere ball tip
│   │       アニメ: 翼ピボットノード (uwR/uwL/lwR/lwL) の Z 回転フラッピング + 体 Y ドリフト
│   │     beetle (🦠):
│   │       body: SCNSphere(r=0.040) × scale(1.05, 0.68, 1.22)、赤光沢 PBR + 毒グリーンエミッシブ
│   │       suture: SCNCylinder(r=0.0028)、暗赤黒
│   │       thorax + head: addSphere ヘルパー
│   │       compound eyes: 球 × 2
│   │       legs: 3ペア × 2段セグメント (addLeg ヘルパー)
│   │       アニメ: Y 回転 (5.5s) + Z ロック (0.38s サイクル)
│   │     stag (👾):
│   │       body: SCNCapsule(capRadius:0.028, height:0.068)、暗金属 PBR + 赤オレンジエミッシブ
│   │       thorax + head + eyes: addSphere
│   │       mandibles: SCNCapsule × 2 + 内側 SCNCone tooth
│   │       legs: 3ペア × addLeg
│   │       elbowed antennae: SCNCylinder + SCNSphere tip
│   │       アニメ: Y 回転 (7.5s) + X 軸頷き (1.4s サイクル)
│   │     全共通: フェードイン (0.25s) + ホバー (±1.8cm, 0.65〜0.85s サイクル)
│   │             + 二次水平ドリフト（+X→-Z→-X→+Z スクエア軌道、±0.03m, 5s サイクル）
│   │     captured(): removeAllActions() + 3 回グリッチ点滅 → SCNAction.fadeOut(easeIn, 0.18s) → removeFromParentNode
│   │
│   ├── SlingshotNode.swift
│   │     SCNNode サブクラス。3D Y 字スリングショットを AR シーンに描画。
│   │     arView.pointOfView の子として追加 → カメラ空間固定（端末の動きに追従）。
│   │     フォーク中心位置: camera-local (0, -0.12, -0.28)。
│   │     ノード構成:
│   │       forkRoot — フォーク全体の親ノード（位置オフセット保持）
│   │         stem     — stemBottom(0,-0.050,0) → branch(0,0.010,0) の SCNCylinder (r=0.007)
│   │         leftArm  — branch → leftTip(-0.035,0.055,0) の SCNCylinder (r=0.006)
│   │         rightArm — branch → rightTip(+0.035,0.055,0) の SCNCylinder (r=0.006)
│   │         tip caps — 各チップに SCNSphere (r=0.009) の装飾球
│   │         leftBandNode / rightBandNode — SCNCylinder。updateDrag() で毎フレーム更新
│   │         pouchNode — トーラスリム + 8 スポーク + 同心リング × 2（網ポーチ）
│   │     材質: wood (brown PBR r=0.82, m=0.04) / band (orange PBR) / pouch (green PBR + emission)
│   │     updateDrag(offset:maxDrag:): pullPoint を計算してバンドとポーチを更新
│   │       maxPullDepth=0.08m (+Z 方向), maxPullLateral=0.025m, maxPullDown=0.014m
│   │     resetDrag(): pullPoint = neutralPull、pouchNode を非表示に
│   │     alignCylinder(_:from:to:): Y 軸 → 方向ベクトル へのクォータニオン回転と高さ更新
│   │
│   ├── Net3DNode.swift
│   │     SCNNode サブクラス。ARSCNView 空間を飛翔する 3D 網メッシュ。
│   │     ノード構成:
│   │       rim (SCNTorus, ringRadius=0.042, pipeRadius=0.0045) — プレイヤー色アクセント、eulerAngles=(π/2,0,0) でカメラ方向に向ける
│   │       spokes × 8 (SCNBox 0.082×0.001×0.001) — 放射状スポーク
│   │       inner rings × 2 (SCNTorus, r=0.020, 0.032) — 同心内リング
│   │     accentColors: cyan / orange / magenta（Player 1〜3 に対応）
│   │     launch(from:direction:power:completion:):
│   │       origin から direction に 0.65〜1.85m 移動（easeOut, 0.55s）
│   │       tumbling spin: X + Z 軸の複合回転（1.2〜2.7 ターン）
│   │       scale: 0.25 → 1.0 → 0.5 の連続変化（unfurling 効果）
│   │       opacity: 即時フェードイン → hold → フェードアウト
│   │       完了後 completion() を呼び出し（removeFromParentNode 用）
│   │
│   ├── SlingshotView.swift
│   │     SwiftUI フルスクリーンオーバーレイ。ジェスチャ管理専用（3D 描画は SlingshotNode が担当）。
│   │     フォーク位置参照: forkYRatio=0.62（PowerIndicatorView 配置のみに使用）
│   │     最大ドラッグ距離: 220pt (maxDragDistance)。任意方向スワイプ可。
│   │     angle = atan2(dragOffset.height, -dragOffset.width)（SpriteKit 座標系に変換）
│   │     power = min(dragLength / 220, 1.0)
│   │     ドラッグ中: gameManager.slingshotDragUpdate?(offset, true) → Coordinator が SlingshotNode を更新
│   │     発射時: gameManager.state == .ready なら gameManager.confirmReady() を先に呼ぶ（ゲーム開始シグナル）
│   │             gameManager.onNetFired?(dragOffset, power) → Coordinator が Net3DNode を発射
│   │             gameManager.sendLaunch(angle:power:) → ARBugScene の当たり判定を起動
│   │     PowerIndicatorView — 水平バー (緑/黄/赤)、power に応じてリアルタイム更新
│   │
│   └── SoundManager.swift
│         AVAudioEngine + AVAudioPlayerNode × 6 によるシングルトンのサウンドマネージャ。
│         外部音声ファイルなし。PCM サイン波バッファをランタイムで生成。
│         makeTone(frequency:duration:amplitude:fadeIn:fadeOut:) — 純音（サイン波 + 線形エンベロープ）
│         makeSweep(startFreq:endFreq:duration:amplitude:) — 周波数グライドサイン波
│         playSequence(_:noteDuration:noteGap:amplitude:) — DispatchQueue.asyncAfter でノートを順次発音
│         公開 API:
│           playThrow()              — 高→低スイープ（網発射時）
│           playCapture(points:)     — 上昇アルペジオ（捕獲時。ポイント数で音数変化）
│           playMiss()               — 下降スイープ（ミス時）
│           playLockOn()             — 短ビープ（ロックオン取得時）
│           playGameStart()          — C5→E5→G5→C6 ファンファーレ（ゲーム開始時）
│           playGameEnd()            — G5→E5→C5→G4 下降メロディ（ゲーム終了時）
│         AVAudioSession.Category.ambient: 他アプリ音楽と共存、サイレントスイッチ非対応
│
├── Shared/
│   └── GameProtocol.swift
│         MessageType: launch / gameState / startGame / resetGame / bugCaptured / bugSpawned / bugRemoved
│         GameMessage: type + optional payloads
│         LaunchPayload:      angle(Float), power(Float), timestamp(Double)
│         GameStatePayload:   state(String), score(Int=0), timeRemaining(Double)
│         BugCapturedPayload: bugType(BugType), playerIndex(Int) — 後方互換のみ、現在は未使用
│         BugSpawnedPayload:  id(String), bugType(BugType), normalizedX(Float), normalizedY(Float)
│         BugRemovedPayload:  id(String)
│         BugType: butterfly(1pt, speed:110, size:40) / beetle(3pt, speed:70, size:55) / stag(5pt, speed:45, size:70)
│           computed: points / emoji / displayName / speed / size / speedLabel / rarityLabel / lore
│         PhysicsCategory: none(0) / bug(0x1) / net(0x2)
│
└── World/
    ├── WorldViewController.swift
    │     UIViewController。SCNView + SKView + ConnectedPlayersView の配置・管理。
    │     viewDidLoad で Bug3DNode.preloadAssets() を呼び出し USDZ を非同期プリロード（iOS AR パスと同様）。
    │     viewDidLayoutSubviews で初回レイアウト後に startGame() を直接呼び出す（3D を即時表示）。
    │     startGame(): 既存 coordinator を stopSpawning()+nil 後、BugHunterScene(isProjectorMode=true) 生成、
    │       ProjectorBug3DCoordinator.attach() — バグスポーンなし（スマホ主導）
    │     fireNet(angle:power:playerIndex:): gameScene?.fireNet() に転送（視覚のみ）
    │     ProjectorGameManagerDelegate:
    │       managerDidReceiveStartGame → startGame()
    │       managerDidReceiveReset → bug3DCoordinator?.stopSpawning()（シーン遷移なし）
    │       didReceiveLaunch → fireNet()
    │       didReceiveBugSpawned → coordinator.addSyncedBug(id:type:normalizedX:normalizedY:)
    │       didReceiveBugRemoved → coordinator.removeSyncedBug(id:)
    │       didUpdateConnectedPlayers → connectedPlayersView.update(players:)
    │
    │     ─── ProjectorBug3DCoordinator（WorldViewController.swift 内の final class）───
    │       SCNScene に固定パースカメラ（cameraZ=3.5, FOV=65°）を設置。
    │       Bug3DNode を bugScaleMultiplier=10 でスケール拡大して scnView に表示。
    │       独立スポーン機能なし・プロキシ BugNode なし。
    │       addSyncedBug(id:type:normalizedX:normalizedY:):
    │         normalizedX(-1〜1) → x = normalizedX × halfW × 0.70
    │         normalizedY(0〜1)  → y = (normalizedY×2-1) × halfH × 0.60
    │         フェードイン + スケールアップ + 常時ホバーアニメ
    │       removeSyncedBug(id:): bug3D.captured() アニメ後 removeFromParentNode
    │       stopSpawning(): 全 Bug3DNode を即削除
    │       attach(to:bugScene:) / updateCachedViewSize(_:)
    │
    ├── WaitingScene.swift
    │     SKScene。isProjectorOverlay=true のとき backgroundColor=.clear（SceneKit 3D 層が透過して見える）。
    │     isProjectorOverlay=false のとき backgroundColor = 暗い緑（スタンドアロン用）。
    │     タイトル "君は、バグハンター 🦟" (HiraginoSans-W7, 80pt) + パルスアニメ
    │     サブタイトル "You are the Bug Hunter" (W3, 40pt)
    │     浮遊バグ絵文字 (🦋/🐛/🪲 × ポイント表示) — 独立した上下フロートアニメ
    │     接続待ちテキスト (W3, 34pt) — フェードブリンクアニメ
    │     操作説明テキスト (W3, 30pt)
    │
    ├── BugHunterScene.swift
    │     SKScene。isProjectorMode=true のとき backgroundColor=.clear。
    │     タイマー・スコア・HUD・BugSpawner・physics contactDelegate なし（スマホ主導）。
    │     fireNet(angle:power:playerIndex:): origin = 画面下部中央 → NetProjectile.launch() → シーンに追加（視覚のみ）
    │
    ├── BugSpawner.swift
    │     旧 SpriteKit BugNode スポーナー（現在は未使用）。
    │
    ├── NetProjectile.swift
    │     SKNode (name="net")。netShape(spider-web SKShapeNode) + ringNode(accent ring) + centerDot
    │     netShape: CGMutablePath。外周円 + 8 スポーク + 3 同心円。緑系 stroke + 薄い fill。
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
          sendGameState(_:): 全ピアに gameState メッセージを broadcast（後方互換のみ）。
          sendBugCaptured(bugType:toPlayerAtSlot:): 後方互換のみ（現在は呼ばれない）。
          delegate: ProjectorGameManagerDelegate
            managerDidReceiveStartGame / managerDidReceiveReset
            didReceiveLaunch / didReceiveBugSpawned / didReceiveBugRemoved / didUpdateConnectedPlayers
```

---

## 通信プロトコル（Multipeer Connectivity）

### メッセージ型

```swift
// GameProtocol.swift に定義
enum MessageType: String, Codable {
    case launch       // iOS → Projector: スリングショット発射
    case startGame    // iOS → Projector: ゲーム開始
    case resetGame    // iOS → Projector: バグクリア
    case bugSpawned   // iOS → Projector: バグ出現通知（スマホ主導同期）
    case bugRemoved   // iOS → Projector: バグ捕獲通知（スマホ主導同期）
    case gameState    // 後方互換のみ（現在は送信されない）
    case bugCaptured  // 後方互換のみ（現在は送信されない）
}
```

### ペイロード

```swift
struct LaunchPayload:      Codable { let angle: Float; let power: Float; let timestamp: Double }
struct BugSpawnedPayload:  Codable { let id: String; let bugType: BugType; let normalizedX: Float; let normalizedY: Float }
struct BugRemovedPayload:  Codable { let id: String }
struct BugCapturedPayload: Codable { let bugType: BugType; let playerIndex: Int } // 後方互換
struct GameStatePayload:   Codable { let state: String; let score: Int; let timeRemaining: Double } // 後方互換
```

### フロー図

```
iOS Controller (×最大3台)               Projector Server
    │                                        │
    │── startGame ──────────────────────────>│
    │── launch(angle, power, timestamp) ────>│  → playerIndex を peerID から特定
    │                                        │  → NetProjectile を発射（視覚のみ）
    │── bugSpawned(id, type, x, y) ─────────>│  → addSyncedBug: Bug3DNode を追加
    │── bugRemoved(id) ─────────────────────>│  → removeSyncedBug: Bug3DNode をcaptured()で削除
    │── resetGame ───────────────────────── >│  → stopSpawning: 全 Bug3DNode 即削除
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
| スポーン間隔 | `max(1.5, 3.5 - elapsed / 75)` 秒（スマホ側のみ） |
| 同時出現上限 | 5 匹（maxActiveBugs=5） |
| タイマー管理 | スマホ（iOS）側のみ。プロジェクターはタイマーなし |
| スコア管理 | iOS（スタンドアロン・クライアント）側のみ |
| 最大接続 | 3 台。4 台目以降は拒否 |
| プロジェクター表示 | 常時 3D シーン。終了画面・待機画面なし |

---

## プロジェクター レイアウト

```
┌────────────────────────────────────────────────┐
│  SCNView  — Bug3DNode（3D バグ、スマホ主導）    │ ← 背面 (z=0)
│  SKView   — BugHunterScene 透過オーバーレイ     │ ← 前面 (透過)
│               NetProjectile（視覚的な網）        │
│  ConnectedPlayersView ──────────────── [右下]   │ ← 常時最前面 UIKit
└────────────────────────────────────────────────┘
```

- 常時 3D シーンを表示し続ける（待機・終了画面への遷移なし）
- バグの追加・削除はすべて iOS スマホ側からの `bugSpawned`/`bugRemoved` メッセージで制御される

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
- **スレッド — UIKit**: SceneKit レンダースレッドから UIKit にアクセスしない（`cachedViewHeight` パターン参照）。
- **スレッド — アンカー辞書**: `ARGameView.Coordinator` の `bugAnchorMap`, `anchorBug3DNodeMap`, `anchorProxyNodeMap`, `nodeAnchorMap` はメインスレッドとレンダースレッドから同時アクセスされるため、`mapLock`（`NSLock`）で全アクセスを保護する。
- **スレッド — スナップショットパターン**: `renderer(_:updateAtTime:)` ではロック下で辞書スナップショットを取得し、ロック解放後に重い投影計算を行う（ロック保持時間を最小化）。
- **Multipeer 受信コールバック**は常に `DispatchQueue.main.async` でメインスレッドに戻す。
- **コメント**: 日本語・英語どちらでも可。`// MARK: -` でセクション分け。
- **ファイル分割**: iOS 側は `Controller/`、プロジェクター側は `World/`、共有型は `Shared/`。
- **依存ライブラリ**: 追加しない。Apple 標準フレームワークのみ使用。
- **アセット**: 外部画像・サウンドファイルなし。すべて手続き的に生成（`CGPath`, `SKShapeNode`, `SCNGeometry`, PCM バッファ等）。

---

## 開発環境

| 項目 | バージョン |
|------|-----------|
| Swift | 5.9 以上 |
| iOS Deployment Target | iOS 17.0 以上 |
| Xcode | 15 以上 |
| フレームワーク | SwiftUI, UIKit, ARKit, SceneKit, SpriteKit, MultipeerConnectivity, Combine, AVFoundation |

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
- `WaitingScene` は `isProjectorOverlay = true` のとき `backgroundColor = .clear` になる。SCNView は常に有効なままで、WaitingScene は透過オーバーレイとして表示される。
- `ProjectorBug3DCoordinator` の生成・破棄は `startGame()` 呼び出し時のみ行う。`presentWaitingScene()` では coordinator を nil にせず `stopSpawning()` のみ呼ぶ。
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

### SoundManager（サウンドエフェクト再生）

```swift
// 単音再生（ARBugScene 等から直接呼び出す）
SoundManager.shared.playThrow()
SoundManager.shared.playCapture(points: bugNode.points)
SoundManager.shared.playMiss()
SoundManager.shared.playLockOn()
SoundManager.shared.playGameStart()
SoundManager.shared.playGameEnd()
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
