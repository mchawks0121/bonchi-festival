# ぼんち祭り バグハンター — サーバー・クライアント連携 実装プロンプト

> **用途**: このドキュメントを GitHub Copilot（チャット／エージェントモード）に渡すことで、  
> プロジェクター（サーバー）と iOS デバイス（クライアント）が **MultipeerConnectivity** を介して  
> リアルタイム同期するアーキテクチャを正確に実装・改修できます。  
> **対象環境**: iOS 17.0+ / Swift 5.9+ / RealityKit + MultipeerConnectivity

---

## 1. 概要

「ぼんち祭り バグハンター」は **プロジェクター（サーバー）が唯一のバグ生成権限者** です。

- iOS クライアントは `projectorClient` モード時にバグを自前でスポーンしません
- プロジェクターが自律的にバグを生成し、全 iOS クライアントへブロードキャストします
- あるクライアントがバグを捕獲したら、プロジェクターが **全クライアントへ削除をリレー** し、全員の AR から同時にバグが消えます
- スタンドアロン（`.standalone`）モードは iOS 側の自律スポーンを継続します（本仕様の対象外）

---

## 2. 設計原則

| 原則 | 要件 |
|------|------|
| **バグ生成権限（Server-Authoritative）** | バグのスポーン・ID 発行・削除判定はプロジェクターのみが行う。iOS クライアントが独自にバグを生成することを禁止する |
| **単一フロー同期** | スポーン: Projector → 全 iOS。削除: iOS → Projector → 全 iOS という一方向フローを厳守する |
| **安定 ID 管理** | バグごとに `UUID().uuidString` を生成し、スポーン〜削除まで同一 ID を全デバイスで使い回す |
| **遅延参加対応** | 途中接続した iOS クライアントに現在生存中の全バグを即座に送信して同期させる |
| **スレッド安全** | 全マップへのアクセスは `NSLock` (`mapLock`) で保護する。メインスレッド以外からの UI 操作禁止 |
| **同時表示上限** | プロジェクター・iOS クライアント双方で最大 4 体。両サイドが同じ上限を持ち、一方が超過しないよう制御する |
| **バグ永続化** | バグはプレイヤーの捕獲またはゲームリセット以外では消滅しない。時間経過や画面外退場による自動削除を禁止する |

---

## 3. デバイスロール

### 3-1. プロジェクター（サーバー）

- 大画面（プロジェクター）に表示される iOS デバイス
- `MCNearbyServiceAdvertiser` でサービスを告知し、接続要求を受理する
- `MCNearbyServiceBrowser` でも同時にブラウズし、クライアントを能動的に招待する
- サービス識別子: `"bughunter-game"`（双方で一致させること）
- 最大同時接続数: **3 クライアント**。超過接続は拒否する
- 各クライアントに 0 始まりの連番スロットインデックス（0, 1, 2）を割り当てる
- 切断時はスロットを解放し、再接続時に空きスロットを再割り当てする

### 3-2. iOS コントローラー（クライアント）

- プレイヤーが手に持つ iPhone
- `projectorClient` モード時に MultipeerSession を起動し、プロジェクターを探してセッションに参加する
- 自身の ARKit セッションにプロジェクターから通知されたバグを AR エンティティとして配置する
- スリングショット発射・ゲーム開始・リセット操作をプロジェクターへ送信する

---

## 4. メッセージプロトコル

### 4-1. エンベロープ構造

全メッセージは以下の共通構造を JSON エンコードして送受信する。

```
{
  "type": "<MessageType>",
  "launchPayload": { ... } | null,
  "gameStatePayload": { ... } | null,
  "bugCapturedPayload": { ... } | null,
  "bugSpawnedPayload": { ... } | null,
  "bugRemovedPayload": { ... } | null
}
```

- 使用しないペイロードフィールドは `null` とする
- デコードに失敗したメッセージは黙って捨てる（アプリをクラッシュさせない）

### 4-2. メッセージ種別と方向

| MessageType | 方向 | ペイロード | 説明 |
|---|---|---|---|
| `startGame` | iOS → Projector | なし | ゲーム開始を指示する |
| `resetGame` | iOS → Projector | なし | ゲームリセットを指示する |
| `launch` | iOS → Projector | `LaunchPayload` | スリングショット発射情報を送信する |
| `bugSpawned` | Projector → 全 iOS | `BugSpawnedPayload` | 新バグのスポーンを通知する |
| `bugRemoved` | iOS → Projector<br>Projector → 全 iOS | `BugRemovedPayload` | バグ削除を通知またはリレーする |
| `bugCaptured` | Projector → 個別 iOS | `BugCapturedPayload` | スコア加算を特定クライアントへ通知する |
| `gameState` | Projector → 全 iOS | `GameStatePayload` | ゲーム進行状態を同期する（任意送信） |

### 4-3. ペイロード定義

#### LaunchPayload
```
angle     : Float   // 発射角（ラジアン、0 = 右, π/2 = 上）
power     : Float   // 発射強度（0.0 〜 1.0 正規化）
timestamp : Double  // Unix 時刻（秒、レイテンシ補正用）
```

#### BugSpawnedPayload
```
id          : String  // サーバー生成の UUID 文字列（全通信で使い回す安定 ID）
bugType     : BugType // .butterfly | .beetle | .stag
normalizedX : Float   // 水平位置ヒント（−1.0 = 左端, +1.0 = 右端）
normalizedY : Float   // 垂直位置ヒント（0.0 = 下端, 1.0 = 上端）
```

#### BugRemovedPayload
```
id : String  // 削除対象バグの UUID（BugSpawnedPayload.id と一致させる）
```

#### BugCapturedPayload
```
bugType     : BugType // 捕獲されたバグの種類（得点計算に使用）
playerIndex : Int     // スコアを加算するプレイヤースロット番号（0 始まり）
```

#### GameStatePayload
```
state         : String  // "waiting" | "playing" | "finished"
score         : Int
timeRemaining : Double
```

---

## 5. バグのライフサイクル

### 5-1. スポーン

1. プロジェクターがバグを生成し `UUID().uuidString` を付与する
2. バグをプロジェクター画面上の RealityKit シーンに配置する（`AnchorEntity(world:)` を使用）
3. `bugSpawned(id, bugType, normalizedX, normalizedY)` を全クライアントへブロードキャストする
4. `normalizedX`/`normalizedY` は正規化された位置ヒントであり、クライアントはこれを元に AR 空間上の位置を復元する

```
normalizedX : Float.random(in: -0.85...0.85)
normalizedY : Float.random(in: 0.10...0.90)
```

### 5-2. バグの移動（プロジェクター側）

- バグは画面外に退場せず、画面内ランダムウェイポイントを **無限に巡回** する
- 巡回は再帰的なスケジューリング（`DispatchQueue.main.asyncAfter` + `anchor.move(to:duration:timingFunction:)`）で実現する
- 1 セグメントの移動時間: `max(5.0, min(600.0 / speed, 15.0))` 秒（速いバグほど短い）
- タイミング関数: `.easeInOut`
- ループ継続条件: バグが追跡配列に存在していること。削除済みなら次の再帰を起動しない

### 5-3. 捕獲フロー

```
iOS クライアントが AR でバグを捕獲
    ↓
bugRemoved(id) をプロジェクターへ送信
    ↓
プロジェクターがそのバグをシーンから削除（removeSyncedBug または removeAutonomousBug）
    ↓
bugRemoved(id) を全クライアントへリレー
    ↓
全クライアントが当該 ID のバグを AR から削除（フェードアウト 0.3 秒 → エンティティ削除）
```

### 5-4. 自然消滅の禁止

- バグは時間経過・画面外移動などによる自動削除を行わない
- プレイヤーによる捕獲または `stopSpawning()` によるゲームリセットのみが削除トリガー
- `stopSpawning()` 時は全アクティブバグの `bugRemoved(id)` をリレーしてからシーンをクリアする

### 5-5. 同時表示上限

- 上限: **4 体**（プロジェクター・iOS クライアント共通）
- 上限に達している間は新規スポーンを行わず、1.5 秒後に再試行する
- iOS クライアントは上限超過の `bugSpawned` を受信した場合、黙って破棄する（クラッシュ禁止）

---

## 6. 遅延参加（Late-Join）同期

途中接続した iOS クライアントに対して、プロジェクターは以下の処理を行う。

1. 接続確立直後（`MCSessionState.connected`）に `sendCurrentBugs(to: peer)` を呼ぶ
2. 現在生存中の全バグ（自律スポーン分 + 電話同期分の両方）を個別の `bugSpawned` メッセージとして送信する
3. クライアントは受信した `bugSpawned` を通常スポーンと同じルートで処理する
4. 重複追加防止: クライアント側は `serverIDToAnchorID[id] != nil` を確認し、同一 ID のバグを二重追加しない

### プロジェクター側の生存バグ管理

プロジェクターは以下の 2 種を分けて管理し、統合して外部へ公開する。

| 区分 | 格納先 | 説明 |
|------|--------|------|
| 自律スポーン分 | `autonomousBugData: [String: (type, normalizedX, normalizedY)]` | プロジェクターが自ら生成したバグの spawn パラメータ |
| 電話同期分 | `syncedBugData: [String: (type, normalizedX, normalizedY)]` | iOS クライアントからの `bugSpawned` 受信で追加されたバグの spawn パラメータ |

```
currentActiveBugs → autonomousBugData + syncedBugData を結合して返す
```

---

## 7. iOS クライアント側の AR 反映

### 7-1. バグ追加（addServerBug）

`bugSpawned` 受信時の処理:

1. 上限チェック（`bugAnchorMap.count >= maxActiveBugs` ならスキップ）
2. `normalizedX` から水平角度を復元: `horizontalAngle = normalizedX × maxHorizontalAngle(0.65 rad)`
3. `normalizedY` から垂直オフセットを復元: `verticalOffset = normalizedY × (vertRange.upper - vertRange.lower) + vertRange.lower`
4. スポーン距離をランダム生成: `Float.random(in: 0.5...1.4)` メートル
5. カメラ座標系でのローカル位置を計算し、`worldOriginTransform`（キャリブレーション原点）でワールド変換する
6. `ARAnchor` を生成して ARKit セッションに追加する
7. 双方向 ID マップに登録する
   - `serverIDToAnchorID[id] = anchor.identifier`
   - `anchorIDToServerID[anchor.identifier] = id`

### 7-2. バグ削除（removeServerBug）

`bugRemoved` 受信時の処理:

1. `serverIDToAnchorID[id]` で `anchorUUID` を O(1) ルックアップする
2. 対応する `anchorProxyNodeMap`・`anchorEntityMap`・`bugAnchorMap` をすべてクリアする
3. 双方向 ID マップから当該エントリを削除する
4. SKNode（プロキシ）をフェードアウト（0.3 秒）後に削除する
5. Bug3DNode に縮小キャプチャアニメーションを再生し、アニメーション完了後に AnchorEntity をシーンから削除する

### 7-3. ID マップの構造（スレッドセーフ要件）

```
mapLock: NSLock  // 以下4マップへの全アクセスを保護すること

serverIDToAnchorID: [String: UUID]              // server ID → ローカル ARAnchor UUID
anchorIDToServerID: [UUID: String]              // ローカル ARAnchor UUID → server ID
bugAnchorMap:       [UUID: BugType]             // ARAnchor UUID → BugType
anchorEntityMap:    [UUID: AnchorEntity]        // ARAnchor UUID → RealityKit AnchorEntity
anchorProxyNodeMap: [UUID: SKNode]              // ARAnchor UUID → SpriteKit プロキシノード
anchorBug3DNodeMap: [UUID: Bug3DNode]           // ARAnchor UUID → Bug3DNode（エンティティ）
nodeAnchorMap:      [ObjectIdentifier: ARAnchor]// SKNode identity → ARAnchor（逆引き）
```

- `mapLock` は読み書きを問わず全マップアクセスで取得・解放すること
- UI 操作（SpriteKit・UIKit）は必ずメインスレッドで行うこと。ARKit デリゲートから直接 UI を変更しない

---

## 8. プロジェクター側のバグ追跡マップ

```
// 自律スポーン分
autonomousBugs:           [Bug3DNode]                          // 追跡配列（捕獲時に削除）
autonomousAnchors:        [AnchorEntity]                       // 対応する AnchorEntity 配列
autonomousBugIDs:         [ObjectIdentifier: String]           // AnchorEntity identity → bug ID
autonomousIDToAnchorKey:  [String: ObjectIdentifier]           // bug ID → AnchorEntity identity（逆引き O(1)）
autonomousBugData:        [String: (type, normalizedX, normalizedY)]  // spawn パラメータ（遅延参加用）

// 電話同期分
bug3DNodes:    [String: Bug3DNode]    // bug ID → Bug3DNode
bug3DAnchors:  [String: AnchorEntity] // bug ID → AnchorEntity
syncedBugData: [String: (type, normalizedX, normalizedY)] // spawn パラメータ（遅延参加用）
```

`removeSyncedBug(id:)` は電話同期分と自律スポーン分の両方を対象とし、どちらの辞書に存在するかをチェックしてから削除すること。

---

## 9. ゲームモード定義

| GameMode | 説明 | バグスポーン権限 | MultipeerSession |
|----------|------|----------------|-----------------|
| `.standalone` | iOS のみで完結するモード | iOS クライアント自身 | 起動しない |
| `.projectorClient` | プロジェクターに接続した iOS | プロジェクターのみ | 起動（Browser + Advertiser） |
| `.projectorServer` | プロジェクター表示デバイス | プロジェクターのみ | Advertiser + Browser |

### projectorClient モードの制約

- `startSpawning()` 内でモードが `.projectorClient` の場合、ローカル自律スポーンタイマーを起動しない
- `gameManager?.onServerBugSpawned` / `onServerBugRemoved` コールバックを設定し、ネットワーク受信をそのまま AR 追加・削除に橋渡しする
- コールバックは `stopSpawning()` / `resetGame()` 時に必ず `nil` クリアし、ゾンビクロージャが発火しないようにする

---

## 10. 接続管理の詳細要件

### 10-1. セッション確立

- iOS クライアントは `MCNearbyServiceBrowser` でプロジェクターを発見次第、即座に `invitePeer(_:to:withContext:timeout:10)` を呼んで招待する
- プロジェクターは `MCNearbyServiceAdvertiser` の招待ハンドラで、`usedSlots.count < maxPlayers(3)` の場合のみ承諾する
- 暗号化設定: `MCSession(encryptionPreference: .required)`

### 10-2. スロット管理

- プロジェクターは `playerSlots: [MCPeerID: Int]` と `usedSlots: Set<Int>` を管理する
- 接続時: 最小の空きスロット番号を割り当てる（0, 1, 2 の順）
- 切断時: 該当スロットを `usedSlots` から削除し `playerSlots` から除去する
- スロット番号は `bugCaptured` の個別送信および UI 表示のプレイヤーカラー決定に使用する

### 10-3. 接続中プレイヤー表示

プロジェクター画面の右下に半透明オーバーレイを常時表示する。

- 表示内容: `"接続中 N / 3"` ヘッダー + プレイヤーごとの名前と色付きドット
- プレイヤーカラー: スロット 0 = シアン / スロット 1 = オレンジ / スロット 2 = ピンク
- 更新タイミング: 接続・切断イベントのたびにリストを再描画する

---

## 11. ゲーム進行とネットワーク操作の対応

| ユーザー操作 | iOS 側処理 | ネットワーク送信 |
|---|---|---|
| スタートボタンタップ | `state = .playing`、ローカルシーン生成 | `startGame()` → Projector |
| ARキャリブレーション完了 | `worldOriginTransform` を記録、`state = .ready` | なし |
| スリングショット発射（初回） | `confirmReady()` でカウントダウン開始 | `startGame()` 送信済みのため追加送信なし |
| スリングショット発射 | ローカル AR シーンでネット発射 | `launch(angle, power, timestamp)` → Projector |
| AR でバグ捕獲 | ローカルスコアに加算 | `bugRemoved(id)` → Projector |
| リセットボタンタップ | ローカル状態初期化 | `resetGame()` → Projector |

---

## 12. エラーハンドリング要件

- JSON エンコード失敗時はログを出力してスキップする（`try?` を使用、クラッシュ禁止）
- 接続先が 0 件の場合は送信をスキップする（`mcSession.connectedPeers.isEmpty` チェック）
- `currentFrame` が取得できない（AR セッション未起動）場合は `addServerBug` を中断する
- `bugRemoved` の ID が存在しない場合はサイレントスキップ（ゾンビ ID の除去試行でクラッシュしない）
- `requestCurrentBugs` コールバックが未設定の場合は `sendCurrentBugs` を空振りで終了する

---

## 13. コーディング規約

- `switch BugType` は **網羅的 switch** を使用し `default` を書かない（新ケース追加時のコンパイルエラーで漏れを検知するため）
- RealityKit のみを使用する（SceneKit / ARSCNView / SCNNode は禁止）
- 新しい定数は `private static let` で閉じ込め、マジックナンバーを避ける
- `NSLock` を使用したスレッドセーフキャッシュパターンを踏襲する
- Swift の命名規則（camelCase）に従う
