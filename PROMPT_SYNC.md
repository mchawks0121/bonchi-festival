# ぼんち祭り バグハンター — サーバー主導バグ同期 実装プロンプト

> **用途**: このファイルを GitHub Copilot（チャット／エージェントモード）に渡すことで、  
> **プロジェクター（サーバー）が全バグをスポーンし、全 iOS クライアントと完全同期する**  
> アーキテクチャを正確に実装・改修できます。  
> **バージョン**: iOS 17.0+ / Swift 5.9+ / RealityKit + MultipeerConnectivity

---

## このドキュメントについて

「ぼんち祭り バグハンター」は **プロジェクター（サーバー）が唯一のバグ生成権限者** です。  
iOS クライアントはバグを自前でスポーンせず、サーバーから通知を受け取って AR 空間に表示します。  
あるプレイヤーがバグを捕まえたら、プロジェクターが **全クライアントへ削除をリレー** するため、  
全員の画面から同時にバグが消えます。

このドキュメントは「サーバー主導バグ同期」機能に関わる全ファイルの実装仕様を記述します。  
変更対象ファイルのみ詳述し、無関係ファイルは `PROMPT.md` / `SPEC.md` を参照してください。

---

## 設計原則

| 原則 | 内容 |
|------|------|
| バグ生成権限 | **プロジェクター（サーバー）のみ**。クライアントは独自スポーン禁止（projectorClient モード） |
| 同期方向 | スポーン: Projector → 全iOS。削除: iOS → Projector → 全iOS |
| ID 管理 | サーバーが `UUID().uuidString` を生成し全通信で使い回す |
| スタンドアロン互換 | `.standalone` モードは従来通り iOS 側で自律スポーン（変更なし） |
| スレッド安全 | 全マップアクセスは `mapLock: NSLock` で保護 |

---

## 通信フロー

```
Projector Server                         iOS Controller (×最大3台)
    │                                        │
    │<── startGame ───────────────────────── │  ゲーム開始
    │<── launch(angle, power, timestamp) ─── │  スリングショット発射
    │                                        │
    │── bugSpawned(id, type, nx, ny) ───────>│  自律スポーン → 全クライアントへブロードキャスト
    │                                        │    → addServerBug(id:type:normalizedX:normalizedY:)
    │                                        │    → ARAnchor 生成 + Bug3DNode 追加
    │                                        │
    │<── bugRemoved(id) ─────────────────────│  捕獲したクライアントが送信
    │── bugRemoved(id) ───────────────────── │  プロジェクターが全クライアントへリレー
    │                                        │    → removeServerBug(id:) でフェードアウト削除
    │── bugRemoved(id) ─────────────────────>│  自律バグが自然消滅した場合もリレー
    │                                        │
    │<── resetGame ───────────────────────── │  ゲームリセット
    │── bugRemoved(id) × N ────────────────>│  全アクティブバグを bugRemoved でリレーしてからクリア
```

---

## 変更ファイル一覧

| ファイル | 役割 | 変更概要 |
|---------|------|---------|
| `Shared/GameProtocol.swift` | 共有メッセージ型 | `bugSpawned`/`bugRemoved` の方向コメント修正 |
| `World/ProjectorGameManager.swift` | プロジェクター Multipeer ラッパー | `sendBugSpawned` / `sendBugRemoved` ブロードキャスト追加 |
| `World/WorldViewController.swift` | プロジェクター表示コントローラー | UUID 割り当て、コールバック配線、リレー実装 |
| `Controller/GameManager.swift` | iOS ゲーム状態管理 | `onServerBugSpawned` / `onServerBugRemoved` コールバック追加 |
| `Controller/ARGameView.swift` | iOS AR 表示 | projectorClient でサーバー主導スポーン、ID マップ追加 |

---

## Shared/GameProtocol.swift

メッセージ方向コメントを実態に合わせて修正します。

```swift
enum MessageType: String, Codable {
    case launch       // iOS → Projector: スリングショット発射
    case gameState    // Projector → iOS: ゲーム状態通知（後方互換）
    case startGame    // iOS → Projector: ゲーム開始
    case resetGame    // iOS → Projector: ゲームリセット
    case bugCaptured  // Projector → iOS: 網がバグに当たった（後方互換・スコア通知）
    case bugSpawned   // Projector → 全iOS: プロジェクターがバグをスポーン（ブロードキャスト）
    case bugRemoved   // iOS → Projector: クライアントが捕獲通知
                      // Projector → 全iOS: 全クライアントへ削除リレー
}

/// Projector → 全iOS: プロジェクターが新規バグをスポーンした際に全クライアントへブロードキャスト。
/// 全クライアントはこの通知を受けて AR 空間に同じバグを表示する。
struct BugSpawnedPayload: Codable {
    /// プロジェクターサーバーが生成した安定 ID。iOS クライアントの ARAnchor と紐付ける。
    let id: String
    let bugType: BugType
    /// 左→右の位置ヒント（-1〜1）。iOS 側がカメラ前方への AR 位置変換に使用。
    let normalizedX: Float
    /// 下→上の位置ヒント（0〜1）。iOS 側がカメラ前方への AR 位置変換に使用。
    let normalizedY: Float
}

/// 双方向で使用:
///   iOS → Projector: 捕獲通知（捕獲した本人のみ送信）
///   Projector → 全iOS: 削除リレー（捕獲・自然消滅いずれの場合も全員へ送信）
struct BugRemovedPayload: Codable {
    /// 対応する BugSpawnedPayload.id と一致する。
    let id: String
}
```

---

## World/ProjectorGameManager.swift

既存の `sendGameState` / `sendBugCaptured` に加えて、以下の 2 メソッドを追加します。

```swift
/// 新規バグを全接続 iOS クライアントへブロードキャストする。
/// ProjectorBug3DCoordinator が自律スポーン時に呼び出す。
func sendBugSpawned(id: String, type: BugType, normalizedX: Float, normalizedY: Float) {
    guard !mcSession.connectedPeers.isEmpty else { return }
    let payload = BugSpawnedPayload(id: id, bugType: type,
                                    normalizedX: normalizedX, normalizedY: normalizedY)
    guard let data = try? JSONEncoder().encode(GameMessage.bugSpawned(payload)) else { return }
    try? mcSession.send(data, toPeers: mcSession.connectedPeers, with: .reliable)
}

/// バグ削除イベントを全接続 iOS クライアントへブロードキャストする。
/// 捕獲受信時のリレー、自然消滅時の通知、リセット時の全バグ削除通知で使用。
func sendBugRemoved(id: String) {
    guard !mcSession.connectedPeers.isEmpty else { return }
    let payload = BugRemovedPayload(id: id)
    guard let data = try? JSONEncoder().encode(GameMessage.bugRemoved(payload)) else { return }
    try? mcSession.send(data, toPeers: mcSession.connectedPeers, with: .reliable)
}
```

---

## World/WorldViewController.swift — ProjectorBug3DCoordinator

### 追加プロパティ

```swift
// MARK: Server-sync callbacks (set by WorldViewController.startGame)

/// 自律バグをスポーンした際に呼ばれる。引数: (id, bugType, normalizedX, normalizedY)
var onBugSpawned: ((String, BugType, Float, Float) -> Void)?

/// バグを削除した際に呼ばれる（捕獲・自然消滅・リセットいずれも）。引数: bugID
var onBugRemoved: ((String) -> Void)?

// MARK: 既存マップに追加

/// AnchorEntity の ObjectIdentifier → サーバー割り当て bugID（自律バグ専用）
private var autonomousBugIDs: [ObjectIdentifier: String] = [:]
```

### stopSpawning() — 変更点

リセット時に全アクティブバグの ID を `onBugRemoved` でリレーしてからクリアします。

```swift
func stopSpawning() {
    autonomousSpawnTimer?.invalidate()
    autonomousSpawnTimer = nil

    // リセット前に全アクティブバグを iOS クライアントへ通知
    for (_, id) in autonomousBugIDs { onBugRemoved?(id) }
    for id in bug3DNodes.keys       { onBugRemoved?(id) }

    // RealityKit アンカーを除去
    autonomousAnchors.forEach { arView?.scene.removeAnchor($0) }
    autonomousAnchors.removeAll()
    autonomousBugs.removeAll()
    autonomousBugIDs.removeAll()

    bug3DAnchors.values.forEach { arView?.scene.removeAnchor($0) }
    bug3DAnchors.removeAll()
    bug3DNodes.removeAll()

    notifyBugCountChanged()
}
```

### spawnAutonomousBug() — 変更点

UUID を生成し、スポーン時に `onBugSpawned` を呼び出します。  
自然消滅時にも `onBugRemoved` を呼び出します。

```swift
private func spawnAutonomousBug() {
    // normalized ヒントをランダム生成（プロジェクター画面上の位置と iOS AR 位置変換で共用）
    let normalizedX = Float.random(in: -0.85...0.85)  // -1〜1 (左→右)
    let normalizedY = Float.random(in: 0.10...0.90)   // 0〜1  (下→上)

    // プロジェクター画面上の 3D 座標（halfW / halfH は visibleHalfExtents() から取得）
    let startX = normalizedX * halfW * 0.70
    let startY = (normalizedY * 2.0 - 1.0) * halfH * 0.60

    let bugType   = randomAutonomousBugType()
    let bug3D     = Bug3DNode(type: bugType)
    let bugAnchor = AnchorEntity(world: matrix_identity_float4x4)
    bugAnchor.position = SIMD3<Float>(startX, startY, 0)
    arView?.scene.addAnchor(bugAnchor)
    bugAnchor.addChild(bug3D.entity)

    // サーバー側で安定 ID を生成
    let bugID = UUID().uuidString
    autonomousBugIDs[ObjectIdentifier(bugAnchor)] = bugID

    autonomousBugs.append(bug3D)
    autonomousAnchors.append(bugAnchor)

    // 全 iOS クライアントへスポーン通知
    onBugSpawned?(bugID, bugType, normalizedX, normalizedY)

    // … (pop-in アニメ + 移動 waypoint + 退場タイマーは既存実装と同じ)

    // 自然消滅時に iOS クライアントへ削除通知
    DispatchQueue.main.asyncAfter(deadline: .now() + totalDur) { [weak self, weak bugAnchor] in
        guard let self else { return }
        if let anchor = bugAnchor,
           let removedID = self.autonomousBugIDs.removeValue(forKey: ObjectIdentifier(anchor)) {
            self.onBugRemoved?(removedID)
        }
        // アンカー・配列のクリーンアップ（既存コードと同じ）
    }
}
```

### WorldViewController.startGame() — コールバック配線

`ProjectorBug3DCoordinator` を生成した直後にコールバックを設定します。

```swift
coordinator.onBugSpawned = { [weak self] id, type, normalizedX, normalizedY in
    self?.projectorManager.sendBugSpawned(id: id, type: type,
                                           normalizedX: normalizedX, normalizedY: normalizedY)
}
coordinator.onBugRemoved = { [weak self] id in
    self?.projectorManager.sendBugRemoved(id: id)
}
```

### ProjectorGameManagerDelegate.didReceiveBugRemoved — リレー追加

クライアントから捕獲通知を受け取ったら、プロジェクター側のバグを削除しつつ全クライアントへリレーします。

```swift
func manager(_ manager: ProjectorGameManager, didReceiveBugRemoved payload: BugRemovedPayload) {
    DispatchQueue.main.async {
        // プロジェクター側のバグを捕獲アニメ付きで削除
        self.bug3DCoordinator?.removeSyncedBug(id: payload.id)
        // 全 iOS クライアントへリレー（他プレイヤーも AR からバグが消える）
        manager.sendBugRemoved(id: payload.id)
    }
}
```

---

## Controller/GameManager.swift

### 追加プロパティ

```swift
// MARK: Server-sync callbacks（projectorClient モード専用）
// ARGameView.Coordinator.setupServerBugCallbacks() で設定。
// stopSpawning() / resetGame() でクリア。

/// プロジェクターが新規バグをスポーンした際に呼ばれる。引数: (id, bugType, nx, ny)
var onServerBugSpawned: ((String, BugType, Float, Float) -> Void)?

/// プロジェクターがバグを削除した際に呼ばれる（捕獲リレー・自然消滅どちらも）。引数: bugID
var onServerBugRemoved: ((String) -> Void)?
```

### resetGame() — 追加

```swift
func resetGame() {
    // … 既存コードそのまま …
    onServerBugSpawned = nil   // ← 追加
    onServerBugRemoved = nil   // ← 追加
    multipeerSession.send(.resetGame())
}
```

### MultipeerSessionDelegate.didReceive — 追加ケース

```swift
func session(_ session: MultipeerSession, didReceive message: GameMessage, from peer: MCPeerID) {
    switch message.type {
    case .bugCaptured:
        // 既存: score += payload.bugType.points
    case .bugSpawned:
        // プロジェクターからのスポーン通知 → AR シーンへ転送
        if let payload = message.bugSpawnedPayload {
            DispatchQueue.main.async {
                self.onServerBugSpawned?(payload.id, payload.bugType,
                                         payload.normalizedX, payload.normalizedY)
            }
        }
    case .bugRemoved:
        // プロジェクターからの削除リレー → AR シーンへ転送
        if let payload = message.bugRemovedPayload {
            DispatchQueue.main.async {
                self.onServerBugRemoved?(payload.id)
            }
        }
    default:
        break
    }
}
```

---

## Controller/ARGameView.swift — Coordinator

### 追加マップ（`mapLock: NSLock` 保護）

```swift
/// サーバーバグ ID (String) → ARAnchor UUID (UUID)
private var serverIDToAnchorID: [String: UUID] = [:]
/// ARAnchor UUID → サーバーバグ ID（O(1) 逆引き用）
private var anchorIDToServerID: [UUID: String] = [:]
```

### startSpawning() — モード分岐追加

```swift
func startSpawning() {
    guard gameManager?.gameMode != .projectorServer else { return }
    stopSpawning()
    // … 既存のマップクリア・スリングショット配線・SceneEvents サブスクリプション …

    // 両マップもクリア
    mapLock.lock()
    serverIDToAnchorID.removeAll()
    anchorIDToServerID.removeAll()
    mapLock.unlock()

    if gameManager?.gameMode == .projectorClient {
        // サーバー主導モード: 自前スポーンなし。サーバー通知でバグを追加・削除
        setupServerBugCallbacks()
    } else {
        // スタンドアロンモード: 従来通り自前スポーン
        scheduleNextSpawn(delay: 0.9)
    }
}
```

### stopSpawning() — 追加クリーンアップ

```swift
func stopSpawning() {
    // … 既存コード …
    // サーバー同期コールバックをクリア
    gameManager?.onServerBugSpawned = nil
    gameManager?.onServerBugRemoved = nil
    // ID マップもクリア
    mapLock.lock()
    serverIDToAnchorID.removeAll()
    anchorIDToServerID.removeAll()
    mapLock.unlock()
}
```

### setupServerBugCallbacks() — 新規メソッド

```swift
/// GameManager のサーバー同期コールバックを配線する（projectorClient モード専用）。
private func setupServerBugCallbacks() {
    gameManager?.onServerBugSpawned = { [weak self] id, type, normalizedX, normalizedY in
        self?.addServerBug(id: id, type: type,
                           normalizedX: normalizedX, normalizedY: normalizedY)
    }
    gameManager?.onServerBugRemoved = { [weak self] id in
        self?.removeServerBug(id: id)
    }
}
```

### addServerBug(id:type:normalizedX:normalizedY:) — 新規メソッド

サーバーが送ってきた normalized ヒントから AR アンカーを生成します。

```swift
/// サーバーからのスポーン通知を受け取り、AR 空間にバグを追加する。
/// 定数は既存 Coordinator の static let と同じ値を使用する。
private func addServerBug(id: String, type: BugType, normalizedX: Float, normalizedY: Float) {
    guard let arView,
          let frame = arView.session.currentFrame else { return }

    // 同時出現上限チェック（maxActiveBugs = 5）
    mapLock.lock()
    let currentCount = bugAnchorMap.count
    mapLock.unlock()
    guard currentCount < Coordinator.maxActiveBugs else { return }

    // normalized ヒント → カメラ前方の AR 座標に変換
    let horizontalAngle = normalizedX * Coordinator.maxHorizontalAngle   // ≈ 0.65 rad
    let vertRange       = Coordinator.verticalOffsetRange                 // -0.30...0.45
    let verticalOffset  = normalizedY * (vertRange.upperBound - vertRange.lowerBound)
                          + vertRange.lowerBound
    let distance = Float.random(in: Coordinator.minSpawnDistance...Coordinator.maxSpawnDistance)

    // カメラローカル → ワールド座標変換（ARKit: カメラ前方 = -Z）
    let localPos = simd_float4(
        distance * sin(horizontalAngle),
        verticalOffset,
        -distance * cos(horizontalAngle),
        1
    )
    let baseTransform = gameManager?.worldOriginTransform ?? frame.camera.transform
    let worldPos      = baseTransform * localPos

    var anchorTransform = matrix_identity_float4x4
    anchorTransform.columns.3 = worldPos

    let anchor = ARAnchor(name: "bug-server", transform: anchorTransform)

    mapLock.lock()
    bugAnchorMap[anchor.identifier]       = type
    serverIDToAnchorID[id]                = anchor.identifier
    anchorIDToServerID[anchor.identifier] = id
    mapLock.unlock()

    arView.session.add(anchor: anchor)
    // ARKit が session(_:didAdd:anchors:) を呼び出し、Bug3DNode + プロキシ SKNode が生成される
}
```

### removeServerBug(id:) — 新規メソッド

別プレイヤーの捕獲や自然消滅によりサーバーから削除通知が来た際のハンドラ。  
捕獲アニメを再生しつつ、全マップをクリアします。

```swift
/// サーバーからの削除通知を受け取り、AR シーンからバグを除去する。
private func removeServerBug(id: String) {
    mapLock.lock()
    guard let anchorUUID = serverIDToAnchorID[id] else {
        mapLock.unlock()
        return
    }
    let proxy        = anchorProxyNodeMap[anchorUUID]
    let anchorEntity = anchorEntityMap[anchorUUID]
    let bug3D        = anchorBug3DNodeMap.removeValue(forKey: anchorUUID)
    if let p = proxy { nodeAnchorMap.removeValue(forKey: ObjectIdentifier(p)) }
    anchorProxyNodeMap.removeValue(forKey: anchorUUID)
    anchorEntityMap.removeValue(forKey: anchorUUID)
    bugAnchorMap.removeValue(forKey: anchorUUID)
    serverIDToAnchorID.removeValue(forKey: id)
    anchorIDToServerID.removeValue(forKey: anchorUUID)
    mapLock.unlock()

    // プロキシをフェードアウトして削除（別プレイヤーが捕まえた視覚表現）
    proxy?.run(SKAction.sequence([
        SKAction.fadeOut(withDuration: 0.3),
        SKAction.removeFromParent()
    ]))

    // 3D エンティティに捕獲アニメを再生してから除去
    if let bug3D, let av = arView {
        reparentToCaptureAnchor(bug3D, in: av)
        bug3D.captured()
    } else if let ae = anchorEntity {
        arView?.scene.removeAnchor(ae)
    }
}
```

### handleCapture + startBug3DCaptureAnimation — サーバー ID を使用

捕獲報告には ARAnchor UUID ではなく **サーバー ID** を使います。  
プロジェクターがサーバー ID で一致を判断してリレーするためです。

```swift
// startBug3DCaptureAnimation(of:) 末尾:
mapLock.lock()
let bugID = anchorIDToServerID[anchor.identifier] ?? anchor.identifier.uuidString
mapLock.unlock()
gameManager?.sendBugRemoved(id: bugID)

// handleCapture(of:) 内:
mapLock.lock()
let bug3D = anchorBug3DNodeMap.removeValue(forKey: anchor.identifier)
let bugID = anchorIDToServerID[anchor.identifier] ?? anchor.identifier.uuidString
mapLock.unlock()
if let bug3D, let arView {
    reparentToCaptureAnchor(bug3D, in: arView)
    bug3D.captured()
    gameManager?.sendBugRemoved(id: bugID)
}
// … マップのクリーンアップ（anchorIDToServerID / serverIDToAnchorID も削除）
mapLock.lock()
if let sID = anchorIDToServerID.removeValue(forKey: anchor.identifier) {
    serverIDToAnchorID.removeValue(forKey: sID)
}
mapLock.unlock()
```

---

## normalizedX / normalizedY 変換の対応表

プロジェクター側とクライアント側で同じ normalized 値を使って位置を合わせます。

```
プロジェクター（Coordinator）          iOS クライアント（addServerBug）
──────────────────────────────         ──────────────────────────────────
normalizedX = random(-0.85...0.85)     horizontalAngle = normalizedX × 0.65  rad
normalizedY = random(0.10...0.90)      verticalOffset  = normalizedY × 0.75 + (-0.30)  m
                                         ※ 0.75 = (0.45 - (-0.30))
startX = normalizedX × halfW × 0.70   distance = random(0.5...1.4)  m
startY = (normalizedY×2-1) × halfH × 0.60
```

---

## モード別動作まとめ

| GameMode | バグスポーン | bugSpawned 送信 | bugRemoved 送信 |
|----------|-------------|----------------|----------------|
| `.standalone` | iOS 側（`spawnBug()`）| no-op（接続なし）| no-op（接続なし）|
| `.projectorClient` | **サーバーから受信** | 不要（受信のみ）| 捕獲時に送信 |
| `.projectorServer` | プロジェクター（`spawnAutonomousBug()`）| 全クライアントへ | 受信後リレー |

---

## コーディング規約（この機能固有）

1. **BugType switch は網羅的に**。`default` を使わず新ケース追加時のコンパイルエラーで検知する。
2. **サーバー ID と ARAnchor UUID は別物**。`serverIDToAnchorID` / `anchorIDToServerID` で O(1) 双方向変換する。
3. **コールバックのメインスレッド保証**。MultipeerDelegate は `DispatchQueue.main.async` で主スレッドに戻してからコールバックを呼ぶ。
4. **ダブルリレー防止**。`removeSyncedBug` 内では `onBugRemoved` を呼ばない（`WorldViewController.didReceiveBugRemoved` が唯一のリレー起点）。
5. **stopSpawning と resetGame の対称性**。`startSpawning` で配線したものはすべて `stopSpawning` でクリアする。

---

## 参照先

| ドキュメント | 内容 |
|-------------|------|
| `SPEC.md` | ゲーム全体仕様・マルチプレイヤー詳細・通信フロー図 |
| `PROMPT.md` | 全ファイルの詳細実装（定数・アニメ・マテリアル値を網羅） |
| `PROMPT_26.md` | Xcode 26 / iOS 26 対応の新規プロジェクト作成ガイド |
