# ぼんち祭り バグハンター — サーバー・クライアント連携 実装プロンプト

> 用途: このドキュメントを GitHub Copilot に渡すことで、**スタンドアロンモード（iOS 単体でのバグ生成・捕獲）** および **プロジェクター側サーバーと iOS クライアントの MultipeerConnectivity 連携** の両方を正確に実装・改修できるようにする。旧バージョンは MultipeerConnectivity 連携のみを対象としていたが、本バージョンからスタンドアロンモードも含めた全モードをカバーする。
> 対象環境: 最新の iOS SDK / 最新の Xcode / Swift / MultipeerConnectivity

---

## 1. 目的（Why）

本仕様の目的は以下を実現することです。

- **スタンドアロンモード**: iOS クライアント 1 台だけでバグ生成・捕獲を完結させる
- **プロジェクター連携モード**: プロジェクター側を唯一の権限サーバーとして扱い、iOS クライアントとの状態同期を一貫したフローで実現する
- スポーンや削除の最終決定権をサーバーに集約する（連携時）
- クライアントごとの差分や二重処理を防ぐ
- 途中参加・再接続・切断復帰を含めて、接続中クライアントの状態を整合させる
- 通信仕様と責務分離を明確にし、他環境でも流用しやすい形にする

---

## 2. 機能概要（What）

### 2-1. 動作モデル（GameMode 別）

| GameMode | バグ生成権限 | 通信 | 表示 |
|---|---|---|---|
| `standalone` | iOS クライアント自身が自律生成 | なし（MultipeerSession 未起動） | AR 表示 |
| `projectorClient` | プロジェクター（サーバー）のみが生成・ID 発行 | MultipeerConnectivity | AR 表示 |
| `projectorServer` | プロジェクター（サーバー）のみが生成・ID 発行 | MultipeerConnectivity | 平面表示（非ARモード） |

- **スタンドアロンモード**: iOS デバイスが唯一のバグ生成権限を持つ。スポーンはローカルでのみ行われ、ネットワーク送受信は一切発生しない。
- **プロジェクター連携モード**: プロジェクター側（`projectorServer`）が唯一のサーバーである。バグの生成、安定 ID の発行、削除判定、全体同期はサーバーだけが行う。クライアント（`projectorClient`）はサーバーから受け取ったイベントを AR シーンに反映するだけで、自律的にバグ生成しない。

### 2-2. 通信フロー（projectorClient ↔ projectorServer）

- スポーン: Server → All Clients (`bugSpawned`)
- 削除要求: Client → Server (`bugRemoved`)
- 削除確定通知: Server → All Clients (`bugRemoved`)
- 得点通知: Server → Target Client (`bugCaptured`)
- ゲーム状態同期: Server → All Clients (`gameState`)
- 操作要求（発射/開始/リセット）: Client → Server (`launch` / `startGame` / `resetGame`)

### 2-3. 非対象

この文書では以下を扱わない。

- AR 空間への配置方法（ARKit アンカー計算の詳細）
- RealityKit / SpriteKit の描画詳細（マテリアル、アニメーション等）
- UI レイアウトやオーバーレイ表示
- ゲーム演出、移動アニメーション、スコア演出

---

## 3. 実装方針（How）

### 3-1. 接続方式（projectorClient / projectorServer のみ）

- サーバー（`projectorServer`）は `MCNearbyServiceAdvertiser` で広告し、`MCNearbyServiceBrowser` でも探索する
- クライアント（`projectorClient`）は `MCNearbyServiceBrowser` でサーバーを発見したら即座に招待する
- サーバーは招待受理時に接続上限を確認し、空きがある場合のみ接続を許可する
- `MCSession` は暗号化必須の設定を使用する
- スタンドアロンモード（`standalone`）では MultipeerSession を起動しない

### 3-2. 責務分離

- 通信層はメッセージの送受信、接続管理、再同期要求の処理だけを担当する
- ゲーム層は受信イベントを購読し、ローカル状態へ反映する
- 通信層は描画 API や UI API に依存しない
- スタンドアロンモードのバグ生成ロジックは AR コーディネーター（`ARGameView.Coordinator`）に閉じ込め、通信層を一切経由しない

### 3-3. 整合性維持（連携モード）

- サーバーはバグごとに `UUID().uuidString` を発行する
- クライアントは受信した安定 ID を削除まで保持する
- 途中参加時はサーバーが生存中エンティティ一覧を再送する
- 同一 ID の重複追加はクライアント側で無視する

### 3-4. 表示モード

- **プロジェクター側**（`projectorServer`）: `ARView(cameraMode: .nonAR)` + `SKView` による平面 2D 表示。ARKit トラッキングは使用しない。
- **iOS クライアント側**（`standalone` / `projectorClient`）: `ARView`（ARKit + RealityKit）による AR 表示。ARKit ワールドトラッキング + `ARAnchor` でバグを空間に固定する。

---

## 4. デバイスロール

### 4-1. プロジェクター（projectorServer）

- **表示**: `ARView(cameraMode: .nonAR)` + 透明 `SKView` オーバーレイによる平面 2D 表示。RealityKit の固定カメラ（`PerspectiveCameraComponent`）でバグを立体的に描画。
- MultipeerConnectivity セッションの主導権を持つ
- サービス識別子は `bughunter-game` で固定する
- 最大同時接続数は 3 クライアントとする
- 接続ごとにプレイヤースロットを 0, 1, 2 の順で割り当てる
- 接続直後に必要な初期同期を送信する
- `ProjectorBug3DCoordinator` がバグを自律スポーンし、`onBugSpawned` コールバック経由で `ProjectorGameManager.sendBugSpawned` を呼び出して全クライアントへブロードキャストする
- クライアントからの削除要求（`bugRemoved`）を受信したら妥当性を確認し、削除を確定した後で全クライアントへ中継通知する

### 4-2. iOS コントローラー（projectorClient）

- **表示**: ARKit ワールドトラッキング + RealityKit (`ARView`) による AR 表示。バグは `ARAnchor` ベースの `AnchorEntity` に紐付けて空間に固定される。
- サーバーへ接続し、受信した `bugSpawned` をローカル AR シーンに反映する
- バグ捕獲時はサーバーへ `bugRemoved` を送信する（サーバーが全クライアントへ中継）
- 発射（`launch`）、開始（`startGame`）、リセット（`resetGame`）の入力イベントをサーバーへ送信する
- サーバー未確定のローカル状態を権威状態として扱わない
- 重複スポーンや未知 ID の削除通知を受けてもクラッシュしない

### 4-3. iOS スタンドアロン（standalone）

- **表示**: iOS クライアントと同様の AR 表示（ARKit + RealityKit）。
- MultipeerSession は起動しない
- `ARGameView.Coordinator` が `ARKit ARAnchor` ベースでバグを自律スポーンする
- バグ捕獲はすべてローカルで完結する。`sendBugRemoved` は呼ばれるが、接続ピアがないため送信は no-op になる
- スコア・タイマーはすべて iOS 側で管理する

---

## 5. 接続管理仕様

### 5-1. セッション確立

- クライアントはサーバー発見後に `invitePeer(_:to:withContext:timeout:)` を呼ぶ
- サーバーは接続数が 3 未満の場合のみ招待を承諾する
- 接続確立時に空きスロットの最小値を割り当てる
- 切断時は割り当て済みスロットを解放する
- 再接続時はその時点の空きスロットを再割り当てする

### 5-2. スロット管理

- サーバーは `playerSlots: [MCPeerID: Int]` を管理する
- サーバーは `usedSlots: Set<Int>` を管理する
- スロット番号はクライアント識別と個別通知に使用する
- クライアント数が上限を超える接続要求は拒否する

### 5-3. 再同期

- サーバーは `MCSessionState.connected` 直後に現在の生存バグ一覧を対象クライアントへ送信する
- 再同期は通常の `bugSpawned` メッセージを個別送信する方式で行う
- クライアントは通常受信と同一経路で処理する

---

## 6. メッセージプロトコル

### 6-1. エンベロープ

全メッセージは JSON で送受信し、共通エンベロープを持つ。

```json
{
    "type": "<MessageType>",
    "launchPayload": null,
    "gameStatePayload": null,
    "bugCapturedPayload": null,
    "bugSpawnedPayload": null,
    "bugRemovedPayload": null
}
```

- `type` でメッセージ種別を表す
- 使用しないペイロードは `null` にする
- デコード失敗メッセージは破棄する
- 未知の `type` は破棄する

### 6-2. メッセージ種別

| MessageType | 方向 | ペイロード | 用途 |
|---|---|---|---|
| `startGame` | Client → Server | なし | ゲーム開始要求 |
| `resetGame` | Client → Server | なし | ゲームリセット要求 |
| `launch` | Client → Server | `LaunchPayload` | 発射イベント送信 |
| `bugSpawned` | Server → All Clients | `BugSpawnedPayload` | スポーン通知 |
| `bugRemoved` | Client → Server / Server → All Clients | `BugRemovedPayload` | 削除要求または削除確定通知 |
| `bugCaptured` | Server → Target Client | `BugCapturedPayload` | 個別加点通知 |
| `gameState` | Server → All Clients | `GameStatePayload` | 全体状態同期 |

### 6-3. ペイロード定義

#### LaunchPayload

```text
angle     : Float
power     : Float
timestamp : Double
```

#### BugSpawnedPayload

```text
id          : String
bugType     : BugType
normalizedX : Float
normalizedY : Float
```

#### BugRemovedPayload

```text
id : String
```

#### BugCapturedPayload

```text
bugType     : BugType
playerIndex : Int
```

#### GameStatePayload

```text
state         : String
score         : Int
timeRemaining : Double
```

---

## 7. 同期ルール

### 7-1. スポーン同期（projectorClient モード）

1. サーバー（`ProjectorBug3DCoordinator`）が新しいバグ ID（`UUID().uuidString`）を発行する
2. サーバーが内部状態（`autonomousBugData`）へ登録する
3. サーバーが `bugSpawned` を全クライアントへブロードキャストする（`ProjectorGameManager.sendBugSpawned`）
4. クライアントは未登録 ID のみ AR 空間に `ARAnchor` として配置する

### 7-1b. スポーン（standalone モード）

1. `ARGameView.Coordinator` がローカルでバグ種別をランダム決定する
2. ARKit `ARAnchor` を世界座標に追加する（`arView.session.add(anchor:)`）
3. `session(_:didAdd:)` で `Bug3DNode` エンティティと SpriteKit プロキシノードを生成する
4. `GameManager.sendBugSpawned` は呼ばれるが、接続ピアがないため no-op となる

### 7-2. 削除同期（projectorClient モード）

1. クライアントがバグを捕獲し、サーバー割り当ての安定 ID を `bugRemoved` として送信する
2. サーバーがその ID の生存を確認する
3. サーバーが内部状態から削除する
4. サーバーが `bugRemoved` を全クライアントへブロードキャストする
5. 全クライアントは対象 ID をローカル AR シーンから削除する

### 7-3. 遅延参加

1. クライアントが接続完了する（`MCSessionState.connected`）
2. サーバーが `requestCurrentBugs` コールバックで現在生存中の全 ID を列挙する
3. 各 ID について `bugSpawned` を当該クライアントへ個別送信する
4. クライアントは既存 ID を重複追加しない（`serverIDToAnchorID` で存在確認）

### 7-4. 同時表示上限

- サーバーとクライアントは同じ上限値を共有する
- 上限は 4 体（`maxActiveBugs = 4` / `maxSimultaneousBugs`）
- サーバーは上限到達中に新規スポーンを確定しない
- クライアントは上限超過の `bugSpawned` を受信しても安全に破棄する

### 7-5. スタンドアロン削除フロー

1. iOS ネットがバグに命中し、SpriteKit の `onCaptureBug` コールバックが呼ばれる
2. `ARGameView.Coordinator.handleCapture(of:)` が ARAnchor を session から除去する
3. スコアは `ARBugScene` → `BugHunterSceneDelegate` 経由で `GameManager` へ反映される
4. `sendBugRemoved` は呼ばれるが、接続ピアがないため no-op となる（ネットワーク副作用なし）

---

## 8. サーバー側状態管理（projectorServer）

### 8-1. 必須管理情報

- 接続中ピア一覧（`MCSession.connectedPeers`）
- ピアごとのスロット番号（`playerSlots: [MCPeerID: Int]`）
- 使用中スロット集合（`usedSlots: Set<Int>`）
- 現在生存中のバグ一覧（`autonomousBugData` / `syncedBugData`）
- バグ ID と spawn 情報の対応（normalizedX, normalizedY, BugType）

### 8-2. 要件

- 生存中一覧は遅延参加同期（`requestCurrentBugs` コールバック）にそのまま利用できる形で保持する
- 削除確定前に一覧から消さない
- 接続イベントとゲームイベントの更新順序が競合しないようにする（`DispatchQueue.main` で統一）
- 共有マップへのアクセスはロックまたは同等の排他制御で保護する

---

## 9. クライアント側状態管理

### 9-1. 必須管理情報（projectorClient）

- サーバー接続状態（`isConnected`）
- サーバー発行 ID → ローカル ARAnchor UUID マップ（`serverIDToAnchorID: [String: UUID]`）
- ARAnchor UUID → サーバー ID 逆引きマップ（`anchorIDToServerID: [UUID: String]`）
- ARAnchor UUID → Bug3DNode / プロキシ SKNode マップ

### 9-2. 必須管理情報（standalone）

- ARAnchor UUID → BugType マップ（`bugAnchorMap`）
- ARAnchor UUID → Bug3DNode / プロキシ SKNode マップ
- サーバー ID マップは不使用（`serverIDToAnchorID` / `anchorIDToServerID` は空のまま）

### 9-3. 要件

- 同一 ID の `bugSpawned` を重複適用しない（`serverIDToAnchorID` で存在確認）
- 未知 ID の `bugRemoved` を受けても無視する（`serverIDToAnchorID[id]` が nil → early return）
- セッション切断時は接続依存状態を安全に破棄または再接続待ちに戻す
- 通信コールバックから UI を直接触る場合はメインスレッドへ移譲する（`DispatchQueue.main.async`）
- RealityKit レンダースレッドから UIKit に直接アクセスしない（`cachedViewHeight` パターンを踏襲）

---

## 10. エラーハンドリング要件

- JSON エンコード失敗時はログを残して送信を中止する
- 接続先が 0 件なら送信をスキップする
- デコード失敗時はメッセージを破棄する
- 未知 ID の削除要求または削除通知はサイレントスキップする
- 再同期用コールバックやデータソースが未設定なら空振りで終了する
- 切断済みピアへの個別送信失敗はクラッシュ原因にしない

---

## 11. コーディング規約

- サーバー・クライアント連携ロジックおよびスタンドアロンのバグ生成ロジックを対象に変更する
- 描画ロジックと通信ロジックを同一責務に混在させない
- `switch` は網羅的に書き、安易な `default` を使わない（`GameMode`・`MessageType`・`BugType` すべて）
- 新しい定数は型の内部に閉じ込め、マジックナンバーを避ける
- 共有状態はスレッドセーフに扱う（`NSLock` / `DispatchQueue.main` で保護）
- メッセージ型、サービス識別子、接続上限はサーバーとクライアントで必ず一致させる
- スタンドアロンモードのコードは通信層を経由させない

---

## 12. Copilot への実装指示

- スタンドアロン・サーバー・クライアント連携の変更だけを行う
- AR 表示、描画、UI、演出、ゲームバランスには触れない
- 既存コードのうち通信責務・バグ生成責務に直接関係しない部分は変更しない
- 必要なら通信層の型定義、送受信処理、接続管理、再同期処理、スタンドアロン生成ロジックのみを更新する
- 変更時は 1 つの PR 単位に収まる範囲で実装する

---

## 13. ファイル別責務早見表

| ファイル | 役割 |
|---|---|
| `Shared/GameProtocol.swift` | メッセージ型定義（`MessageType`, `GameMessage`, ペイロード, `BugType`） |
| `Controller/MultipeerSession.swift` | iOS クライアント側 MultipeerConnectivity ラッパー |
| `Controller/GameManager.swift` | iOS ゲーム状態管理、モード切替、`sendBugRemoved` / `sendBugSpawned` |
| `Controller/ARGameView.swift` | AR 表示・スタンドアロンバグ生成・server-sync コールバック受信 |
| `World/ProjectorGameManager.swift` | プロジェクター側 MultipeerConnectivity ラッパー、スロット管理、ブロードキャスト |
| `World/WorldViewController.swift` | プロジェクター UI ルート、`ProjectorBug3DCoordinator` の生成・接続 |
| `World/BugSpawner.swift` | `BugSpawner` クラス（旧プロジェクター 2D スポーナー、現在は `ProjectorBug3DCoordinator` に置き換え済みで直接使用されていない）と `BugNode` クラス（AR コーディネーターがプロキシノード生成に使用）を定義 |

