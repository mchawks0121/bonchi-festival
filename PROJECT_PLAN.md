# ぼんち祭り バグハンター — プロジェクト計画書

> **対象環境**: Xcode 26 / iOS 26 / Swift 6.0  
> 最終更新: 2025年4月

---

## 1. 使用技術

| カテゴリ | 技術 | 用途 |
|---------|------|------|
| フレームワーク | ARKit 6 | AR空間でのバグ配置・カメラトラッキング（iOS 26） |
| フレームワーク | RealityKit 3 | 3Dモデル（`Bug3DNode`、`SlingshotNode`、`Net3DNode`）レンダリング（SceneKit から移行済） |
| フレームワーク | SpriteKit | プロジェクター側大画面表示、HUDオーバーレイ（透過SKView） |
| フレームワーク | SwiftUI 6 | 各画面のUI（`WaitingView`、`CalibrationView`、`FinishedView` 等）+ Liquid Glass エフェクト |
| 通信 | MultipeerConnectivity | iOS（コントローラー）↔ プロジェクター（サーバー）間のP2P通信 |
| 言語 | Swift 6.0 | 全実装言語（strict concurrency 有効） |
| 並行処理 | Swift Concurrency (`actor`, `@MainActor`, `Sendable`) | スレッドセーフ処理（NSLock から段階的移行） |
| テスト | Swift Testing | ユニットテスト・スナップショットテスト（XCTest から移行） |
| 3Dアセット | USDZ（Apple AR Quick Look ギャラリー） | バグの3Dモデル（`toy_biplane` / `gramophone` / `toy_drummer`）|
| デバイス | iPhone（ARKit対応、iOS 26+）| コントローラー／スタンドアロン端末 |
| デバイス | iPad / Mac（プロジェクター接続） | 大画面表示サーバー端末 |

### Xcode 26 / iOS 26 固有の対応事項

| 項目 | 内容 |
|------|------|
| Deployment Target | iOS 26.0 |
| Swift | 6.0（`SWIFT_STRICT_CONCURRENCY = complete`） |
| Xcode | 26.x |
| ライフサイクル | UIKit AppDelegate ベース維持（SwiftUI App プロトコルは使用しない） |
| UI テーマ | Liquid Glass デザインシステム（`.glassBackground()`, `.glassEffect()`）を WaitingView / HUD に適用 |
| ARKit | `ARWorldTrackingConfiguration` + `sceneReconstruction` で精度向上 |
| RealityKit | `RealityView`（iOS 18 以降）は不使用。`ARView` + `AnchorEntity` パターンを継続 |
| Swift Concurrency | 既存 `NSLock` パターンを `actor` へ段階移行。既存コードは `nonisolated` アノテーションで暫定対応 |

---

## 2. AIを使った開発について

### 活用方法

- **GitHub Copilot（コーディングエージェント）** をメイン生成ツールとして使用
- コードの新規実装・リファクタ・バグ修正などをAIに依頼し、開発速度を向上させる
- `SPEC.md`（仕様書）と `PROMPT.md`（実装説明書）を常に最新に保ち、AIへのコンテキスト品質を確保する
- **新規タスクには `PROMPT_26.md` のチーム別プロンプトを使用する**

### 進め方のTips（iOS 26 / Swift 6 対応版）

- AIに依頼する前に**仕様を明文化**する（What / Why / How を記載）。曖昧な指示は曖昧なコードを生む
- AIが生成したコードには必ず**実装意図・注意点のコメント**を含めるよう指示する
- **1PR = 1機能** の単位でAIに依頼し、差分を小さく保つ
- AIは `default:` を書きがちなので、`BugType` の `switch` は網羅的（exhaustive）になっているか必ず確認する
- **Swift 6 concurrency**: AIに `@MainActor` / `actor` / `Sendable` の適切な使用を必ず指示する。`nonisolated(unsafe)` は技術的負債なので使用禁止
- **Liquid Glass UI**: SwiftUI の `.glassBackground()` / `.glassEffect()` は iOS 26 のみで動作。`#available(iOS 26, *)` ガードを忘れずに指示する
- スレッドセーフ性（RealityKit は基本 `@MainActor`、SpriteKit は main thread）をAIへ伝えてから生成させる
- RealityKit の `Entity.loadAsync` は Swift 6 では `async throws` に変わるため、`async/await` 構文を使うよう指示する

### レビュー方針

- AIが生成したコードは**必ず人間がレビュー**してからマージする（self-review は不可）
- セキュリティ・スレッドセーフ・アーキテクチャ逸脱の観点でチェックする
- Swift 6 のコンパイラ警告ゼロを必達とする（`-strict-concurrency=complete` ビルドエラーを放置しない）
- レビュー後、`SPEC.md` / `PROMPT.md` の更新も確認する（コードだけマージしない）

---

## 3. 役割分け

| 役割 | 担当内容 |
|------|---------|
| **プロジェクトリード** | 全体の進捗管理、マイルストーン調整、最終品質チェック、`PROMPT_26.md` メンテ |
| **ARエンジニア** | ARKit・RealityKit層の実装（バグスポーン、スリングショット、ネット飛翔）|
| **プロジェクターエンジニア** | SpriteKit大画面側の実装（`BugHunterScene`、`WorldViewController`）|
| **通信エンジニア** | MultipeerConnectivity（接続管理、メッセージプロトコル設計、Swift 6 Sendable 対応）|
| **UIデザイナー / フロントエンド** | SwiftUI画面（`WaitingView`、`FinishedView`、HUD）+ Liquid Glass UI、サウンド設計 |
| **QA / テスター** | 実機テスト（複数台接続・AR精度・スコア計算）、Swift Testing でのテスト整備、バグ報告 |

> 小規模チームの場合は兼任可（例：ARエンジニアが通信も担当）

---

## 4. チーム分け（案）

| チーム | メンバー（役割） | 担当領域 |
|--------|----------------|---------|
| **チームA: ARコア** | ARエンジニア × 1〜2名 | `Controller/` 配下（`ARGameView`, `Bug3DNode`, `SlingshotNode`, `Net3DNode`）|
| **チームB: プロジェクター** | プロジェクターエンジニア × 1〜2名 | `World/` 配下（`BugHunterScene`, `WorldViewController`, `ProjectorBug3DCoordinator`）|
| **チームC: 基盤・UX** | 通信エンジニア＋UIデザイナー × 1〜2名 | `Shared/`（`GameProtocol`）、`MultipeerSession`、SwiftUI画面、`SoundManager` |
| **横断: QA** | テスター × 1名（全チームから兼任可） | 実機統合テスト、Swift Testing、不具合管理 |

---

## 5. 各チームタスク期限・マイルストーン（本番：8月1日）

```
現在: 4月下旬  →  本番: 8月1日（約14週間）
```

| マイルストーン | 期限 | チームA（ARコア） | チームB（プロジェクター） | チームC（基盤・UX） |
|--------------|------|-----------------|------------------------|-------------------|
| **M0: 環境整備** | 5月2日（1週） | Xcode 26 + iOS 26 実機ビルド確認。Swift 6 strict concurrency ビルドエラー棚卸し | 同左 | `GameProtocol.swift` の `Sendable` 準拠対応 |
| **M1: プロトタイプ完成** | 5月16日（4週） | スリングショット基本動作・バグスポーン（1種類）が動く | プロジェクター画面にバグが表示される | Multipeer接続・基本メッセージ送受信が通る |
| **M2: 全機能実装完了** | 6月20日（8週） | 3種バグ・USDZモデル・キャリブレーション対応・Swift 6 actor 化 | 自律スポーン・3クライアント同時接続対応 | スコア・タイマー・SE・全画面遷移・Liquid Glass UI の完成 |
| **M3: 統合テスト・調整** | 7月11日（11週） | 距離・スケール・当たり判定チューニング | プロジェクター側スコア集計・ゲームオーバー画面 | マルチプレイヤー全体フロー通し確認・Swift Testing スイート整備 |
| **M4: リリース候補（RC）** | 7月25日（13週） | 全バグFix・パフォーマンス最適化 | 全バグFix・最終表示調整 | 最終UIポリッシュ・ドキュメント更新完了 |
| **🎉 本番（ぼんち祭り）** | **8月1日** | — | — | — |

### 備考

- **M0（5/2）** は iOS 26 / Xcode 26 固有のコンパイルエラーを全チームで先行解消する。ここを疎かにすると M1 以降が詰まる
- **M1（5/16）** は「動くもの」を最優先。見た目より接続・AR基本動作を優先する
- **M2（6/20）** 以降は各チーム間での統合作業が増えるため、週次で同期ミーティングを設ける
- **M3（7/11）** は実機（iPhone × 複数台 + プロジェクター接続デバイス）での通しテストを必須とする
- **M4（7/25）** 以降は機能追加禁止（バグ修正のみ）とし、本番当日のリスクを下げる
- 各PRは上記マイルストーンを意識した単一責務の単位で作成する

---

## 6. Swift 6 移行チェックリスト

新規コードはすべて Swift 6 strict concurrency 準拠で書く。既存コードは以下の優先度で移行する。

| 優先度 | ファイル | 対応内容 |
|--------|---------|---------|
| 🔴 高 | `GameProtocol.swift` | `BugType`, `GameMessage` 等を `Sendable` 準拠にする |
| 🔴 高 | `MultipeerSession.swift` | `@MainActor` 隔離 or `actor MultipeerSession` に移行 |
| 🟡 中 | `ARGameView.swift` | `Coordinator` の `NSLock` を `actor` or `@MainActor` + `Task` に置換 |
| 🟡 中 | `Bug3DNode.swift` | `entityCache` / `cacheLock` を `actor BugAssetCache` に移行 |
| 🟢 低 | `SoundManager.swift` | `@MainActor` アノテーションで暫定対応 |
| 🟢 低 | `WorldViewController.swift` | `ProjectorBug3DCoordinator` を `@MainActor` クラスに昇格 |

---

## 7. Liquid Glass UI 対応方針

iOS 26 の Liquid Glass デザインシステムは `#available(iOS 26, *)` で条件分岐し、iOS 17 以前でも動作するフォールバックを維持する（現在の Deployment Target が iOS 26.0 なら不要）。

| 画面 | 対応内容 |
|------|---------|
| `WaitingView` | `ModeCard` の背景を `.glassBackground()` に変更 |
| `ARPlayingView` HUD | タイマーバー・スコア表示を `.glassEffect()` パネルに変更 |
| `FinishedView` | スコアカードを `.glassBackground()` に変更 |
| `CalibrationView` | オーバーレイパネルを `.glassBackground()` に変更 |

> Liquid Glass はダークテーマ・ライトテーマ両対応。既存の `accentCyan` / `bgTop` / `bgBottom` カラートークンはそのまま維持し、背景素材のみ置換する。

---

## 8. チーム別詳細（目的・人数・成果物・タスク）

### チームA：ARコア

| 項目 | 内容 |
|------|------|
| **人数** | ARエンジニア × 1〜2名 |
| **目的** | iPhone 上のAR空間にバグを出現させ、スリングショットで捕獲する体験を実現する |
| **担当ディレクトリ** | `bonchi-festival/Controller/` |

#### 成果物ファイル一覧

| ファイル | 概要 |
|---------|------|
| `AppDelegate.swift` | UIKit AppDelegate エントリーポイント。ARKitセッション・ウィンドウ管理 |
| `GameManager.swift` | `@MainActor` 中央状態管理。`GameState` / `GameMode` 状態機械 |
| `ARGameView.swift` | `ARSCNView`（3D）＋ 透過 `SKView` オーバーレイ。`Coordinator` でAR描画ループ処理 |
| `Bug3DNode.swift` | USDZ / 手続き的PBRジオメトリによる3Dバグノード。`NSLock` + `entityCache` でスレッドセーフプリロード |
| `ARBugScene.swift` | 透過 SpriteKit シーン。照準クロスヘア・ロックオンリング・捕獲アニメーション |
| `SlingshotNode.swift` | `SCNNode` ベースのY字スリングショット。ゴム紐・網ポーチをドラッグ量に応じてリアルタイム変形 |
| `Net3DNode.swift` | 飛翔する3D網ノード。ロックオン済みバグへ追尾 or 最近傍バグを自動判定 |
| `SlingshotView.swift` | スリングショット操作を受け付ける SwiftUI ラッパービュー |

#### マイルストーン別タスク

| MS | 期限 | タスク |
|----|------|-------|
| M0 | 5/2 | Xcode 26 + iOS 26 実機ビルド確認。Swift 6 strict concurrency ビルドエラー棚卸し |
| M1 | 5/16 | スリングショット基本動作・バグスポーン（1種類）が実機動作 |
| M2 | 6/20 | 3種バグ・USDZモデル・キャリブレーション・Swift 6 `actor` 化 |
| M3 | 7/11 | 距離・スケール・当たり判定チューニング |
| M4 | 7/25 | 全バグFix・パフォーマンス最適化 |

---

### チームB：プロジェクター

| 項目 | 内容 |
|------|------|
| **人数** | プロジェクターエンジニア × 1〜2名 |
| **目的** | 大画面スクリーンにバグと得点を表示し、最大3台のiPhoneからの操作を受け付けるサーバー役を実現する |
| **担当ディレクトリ** | `bonchi-festival/World/` |

#### 成果物ファイル一覧

| ファイル | 概要 |
|---------|------|
| `ProjectorGameManager.swift` | `@MainActor final class`。最大3台接続制限・Multipeer受信デリゲート |
| `BugHunterScene.swift` | SpriteKit 大画面シーン。バグノード管理・スコア表示・ゲームオーバー |
| `NetProjectile.swift` | プロジェクター上で飛翔する網スプライト。プレイヤーカラー（最大3色）で識別 |
| `WorldViewController.swift` | UIViewController ベースのプロジェクター画面。`ProjectorBug3DCoordinator` を保持 |
| `ProjectorBug3DCoordinator.swift` | 自律スポーン（`autonomousBugs`）と Phone 同期バグ（`bug3DNodes`）を並行管理 |

#### マイルストーン別タスク

| MS | 期限 | タスク |
|----|------|-------|
| M0 | 5/2 | Xcode 26 + iOS 26 実機ビルド確認 |
| M1 | 5/16 | プロジェクター画面にバグが表示される |
| M2 | 6/20 | 自律スポーン・3クライアント同時接続対応 |
| M3 | 7/11 | スコア集計・ゲームオーバー画面 |
| M4 | 7/25 | 全バグFix・最終表示調整 |

---

### チームC：基盤・UX

| 項目 | 内容 |
|------|------|
| **人数** | 通信エンジニア＋UIデザイナー × 1〜2名 |
| **目的** | iOS↔プロジェクター間の通信基盤と全UI画面・SEを完成させ、チーム全体の共通型定義を維持する |
| **担当ディレクトリ** | `bonchi-festival/Shared/`、`bonchi-festival/Controller/`（通信・UI・サウンド部分） |

#### 成果物ファイル一覧

| ファイル | 概要 |
|---------|------|
| `Shared/GameProtocol.swift` | `BugType` / `GameMessage` 等の共有型定義。全型 `Sendable` 準拠。**全チームのブロッカー** |
| `Controller/MultipeerSession.swift` | `@MainActor final class`。iOS 側 Multipeer ラッパー。暗号化 `.required` |
| `ContentView.swift` | SwiftUI ルートビュー。全画面遷移（WaitingView / CalibrationView / ARPlayingView / FinishedView）+ Liquid Glass |
| `Controller/SoundManager.swift` | `@MainActor` SEプレイヤー。捕獲音・ミス音・BGM |

#### マイルストーン別タスク

| MS | 期限 | タスク |
|----|------|-------|
| M0 | 5/2 | `GameProtocol.swift` の `Sendable` 準拠対応（**最優先・ブロッカー**） |
| M1 | 5/16 | Multipeer接続・基本メッセージ送受信が通る |
| M2 | 6/20 | スコア・タイマー・SE・全画面遷移・Liquid Glass UI の完成 |
| M3 | 7/11 | マルチプレイヤー全体フロー通し・Swift Testing スイート整備 |
| M4 | 7/25 | 最終UIポリッシュ・ドキュメント更新完了 |

---

### 横断：QA

| 項目 | 内容 |
|------|------|
| **人数** | 1名（全チームから兼任可） |
| **目的** | シミュレーターでは検証不能なARKit / MultipeerConnectivity の実機動作を保証する |
| **担当フェーズ** | M3〜M4（統合テスト・調整フェーズ） |

#### 成果物

| 成果物 | 内容 |
|--------|------|
| Swift Testing スイート | `GameProtocol` デコード / スコア計算 / スポーン確率の単体テスト |
| 実機テスト報告書 | iPhone × 3台 + プロジェクター接続デバイスでの通しテスト結果 |
| 不具合チケット | GitHub Issues に `bug` / `priority` ラベルで起票 |

---

## 9. タスク細分化（フェーズ別・担当チーム付き）

> **並行作業ルール**: Phase 3・4 は P-01 完了後に同時着手可。Phase 5〜7 は Phase 2・3 の完了後。

### Phase 0 — 環境構築（M0: 5/2）

| タスクID | ファイル / 作業 | 担当 | 前提 |
|---------|--------------|------|------|
| P-00 | Xcode 26 新規プロジェクト作成・`iOS 26.0` ターゲット・Swift 6 ビルド確認 | **全チーム** | — |

### Phase 1 — 共有型定義（M0: 5/2）★ブロッカー

| タスクID | ファイル | 担当 | 前提 |
|---------|---------|------|------|
| P-01 | `Shared/GameProtocol.swift` | **チームC** | P-00 |

> P-01 は後続タスク全ての依存元。最優先で着手する。

### Phase 2 — アプリ基盤（M1: 5/16）

| タスクID | ファイル | 担当 | 前提 |
|---------|---------|------|------|
| P-02 | `AppDelegate.swift` | チームA | P-00 |
| P-03 | `Controller/GameManager.swift` | チームA | P-01, P-02 |

### Phase 3 — 通信層（M1: 5/16）

| タスクID | ファイル | 担当 | 前提 |
|---------|---------|------|------|
| P-04 | `Controller/MultipeerSession.swift` | チームC | P-01 |
| P-05 | `World/ProjectorGameManager.swift` | チームB | P-01 |

### Phase 4 — ARコア（M1〜M2: 5/16〜6/20）

| タスクID | ファイル | 担当 | 前提 |
|---------|---------|------|------|
| P-06 | `Controller/Bug3DNode.swift` | チームA | P-01 |
| P-07 | `Controller/ARBugScene.swift` | チームA | P-01 |
| P-08 | `Controller/ARGameView.swift` | チームA | P-03, P-06, P-07 |
| P-09 | `Controller/SlingshotNode.swift` | チームA | P-01 |
| P-10 | `Controller/Net3DNode.swift` | チームA | P-01 |
| P-11 | `Controller/SlingshotView.swift` | チームA | P-09, P-10 |

### Phase 5 — サウンド（M2: 6/20）

| タスクID | ファイル | 担当 | 前提 |
|---------|---------|------|------|
| P-12 | `Controller/SoundManager.swift` | チームC | P-03 |

### Phase 6 — UI全画面（M2: 6/20）

| タスクID | ファイル | 担当 | 前提 |
|---------|---------|------|------|
| P-13 | `ContentView.swift`（全画面 SwiftUI + Liquid Glass） | チームC | P-03, P-04, P-12 |

### Phase 7 — プロジェクター側（M2: 6/20）

| タスクID | ファイル | 担当 | 前提 |
|---------|---------|------|------|
| P-14 | `World/BugHunterScene.swift` & `World/NetProjectile.swift` | チームB | P-05 |
| P-15 | `World/WorldViewController.swift` | チームB | P-05, P-06, P-14 |

### Phase 8 — 統合・QA（M3〜M4: 7/11〜7/25）

| タスクID | 作業 | 担当 | 前提 |
|---------|------|------|------|
| P-16 | Swift Testing スイート構築（デコード / スコア計算 / スポーン確率） | 横断QA | P-01〜P-15 |
| P-17 | パフォーマンス最適化・メモリリーク修正 | 全チーム | P-16 |

---

## 10. AI駆動開発 詳細指針

### 10-1. プロンプト作成の鉄則

毎回のプロンプトに **必ず** 以下3点を含める。省略すると生成品質が著しく低下する。

| 項目 | 記載例 |
|------|-------|
| **Why（目的）** | 「観客がスリングショット操作を直感的に体験できるようにするため」 |
| **What（機能概要）** | 対象ファイル名・クラス名・実装すべきプロパティ・メソッドを箇条書き |
| **How（実装方針）** | フレームワーク指定・スレッドモデル・禁止事項 |

### 10-2. プロンプトに必ず記載する制約

| 制約 | 記載例 |
|------|-------|
| フレームワーク | 「3DはRealityKitのみ。`ARSCNView`・SceneKitは使わない」 |
| スレッド | 「RealityKitは`@MainActor`。SpriteKitはmain thread専用」 |
| 並行処理 | 「`nonisolated(unsafe)` は使用禁止。`actor` または `@MainActor` で解決する」 |
| switch | 「`BugType` のswitchは網羅的に書き `default:` を書かない」 |
| PR粒度 | 「1PR = 1ファイル（または1機能）単位で出力する」 |
| コメント | 「実装意図・セキュリティ考慮・注意点のコメントを必ず含める」 |
| コードコメント | 「セキュリティ上の考慮点・注意点・制約をすべてコード内コメントで明記する」 |

### 10-3. AIコード生成後の必須チェック項目

生成コードをPRに出す前に以下を全員が確認する。

- [ ] `BugType` の switch が exhaustive（`default:` なし）になっているか
- [ ] `nonisolated(unsafe)` が使われていないか
- [ ] `@MainActor` / `actor` / `Sendable` が適切に使われているか
- [ ] `MCSession` の `encryptionPreference` が `.required` になっているか
- [ ] 強制アンラップ（`!`）がコード内に残っていないか
- [ ] `SPEC.md` / `PROMPT.md` の更新が同じPRに含まれているか
- [ ] Swift 6 strict concurrency ビルドエラーがゼロか

### 10-4. ドキュメント三点セット管理ルール

```
コードを変更したら、必ず以下3ファイルも同じPRで更新する。
ドキュメントが古くなると次回以降のAI生成品質が劣化する。

SPEC.md        → ゲーム仕様・ルール・アーキテクチャの最新状態
PROMPT.md      → 各ファイルの実装説明（AI再現プロンプト用）
PROMPT_26.md   → 新規タスクのチーム別プロンプト集（Xcode 26 / iOS 26 対応）
```

---

## 11. PRルール（全チーム共通）

| ルール | 詳細 |
|--------|------|
| **1PR = 1機能** | 複数ファイルに渡る大きな変更はNG。差分を小さく保つ |
| **self-review 禁止** | 自分がプロンプトを投げて自分でマージしない。必ず他のメンバーがレビューする |
| **ドキュメント同時更新** | コードの振る舞いが変わったら `SPEC.md` / `PROMPT.md` も同じPRで更新 |
| **コンパイル警告ゼロ** | `-strict-concurrency=complete` のビルド警告を放置しない |
| **M4以降は機能追加禁止** | 7/25以降はバグ修正PRのみ受け付ける |
| **ブランチ命名規則** | `feat/<タスクID>-<ファイル名>` 例: `feat/p-01-game-protocol` |
| **コミットメッセージ** | `<タスクID>: <何をしたか>` 例: `P-01: Add GameProtocol.swift with Sendable types` |
