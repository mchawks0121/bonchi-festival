# GitHub Copilot 活用ナレッジ — ぼんち祭り バグハンター

> このドキュメントは **ぼんち祭り バグハンター** プロジェクトを通じて得た  
> GitHub Copilot の活用ナレッジ・プロンプトエンジニアリング・ベストプラクティスをまとめたものです。  
> ARKit × RealityKit × SpriteKit × MultipeerConnectivity という複雑なスタックを  
> iOS 開発経験の浅いチームが約 14 週間で実装した実体験に基づきます。

---

## 目次

1. [GitHub Copilot とは ― このプロジェクトでの活用概要](#1-github-copilot-とは--このプロジェクトでの活用概要)
2. [プロンプトエンジニアリング基礎](#2-プロンプトエンジニアリング基礎)
3. [このプロジェクト固有のプロンプトテンプレート集](#3-このプロジェクト固有のプロンプトテンプレート集)
4. [copilot-instructions.md の設計ノウハウ](#4-copilot-instructionsmd-の設計ノウハウ)
5. [SPEC.md パターン ― AI の記憶を補う設計](#5-specmd-パターン--ai-の記憶を補う設計)
6. [エージェントモード活用術](#6-エージェントモード活用術)
7. [チーム開発での Copilot 活用ルール](#7-チーム開発での-copilot-活用ルール)
8. [iOS / Swift 開発固有のプロンプトテクニック](#8-ios--swift-開発固有のプロンプトテクニック)
9. [プロンプトエンジニアリング アンチパターン](#9-プロンプトエンジニアリング-アンチパターン)
10. [継続開発のための Copilot 活用フロー](#10-継続開発のための-copilot-活用フロー)
11. [Copilot 活用度セルフチェックリスト](#11-copilot-活用度セルフチェックリスト)
12. [参考リソース・次のステップ](#12-参考リソース次のステップ)
13. [人間によるコードレビューガイドライン](#13-人間によるコードレビューガイドライン)

---

## 1. GitHub Copilot とは ― このプロジェクトでの活用概要

### 1-1. Copilot の主要モードと使い分け

| モード | 特徴 | このプロジェクトでの主な用途 |
|--------|------|--------------------------|
| **インライン補完** | カーソル位置のコードを自動補完。Tab で受け入れ | 定型的な Swift 構文・プロトコル準拠・switch 全ケース補完 |
| **チャット（@workspace）** | ファイルを指定してQ&Aや局所修正 | スレッドエラーの原因調査・ARKit API の使い方確認 |
| **エージェントモード** | 自律的に複数ファイルを読み・書き・テスト実行 | フレームワーク移行（SceneKit → RealityKit）・ドキュメント同期更新 |

### 1-2. このプロジェクトで実際に使ったモードとユースケース

| ユースケース | 使用モード | 効果 |
|------------|-----------|------|
| `BugType` の switch 全ケース補完 | インライン補完 | 漏れのない網羅的 switch を即座に生成 |
| ARKit `ARAnchor` → RealityKit `AnchorEntity` 移行 | エージェント | `ARGameView.swift` 全体の置き換えを一括実施 |
| `NSLock` のロック範囲を指摘させる | チャット | スレッド安全性の脆弱箇所を文章で説明 |
| `SPEC.md` / `PROMPT.md` の更新 | エージェント | コード変更と同一 PR でドキュメントを自動更新 |
| `MCSession.encryptionPreference` の設定確認 | チャット | セキュリティ要件の確認と修正提案 |
| 手続き的 PBR ジオメトリ（`Bug3DNode`）の実装 | インライン補完 + チャット | RealityKit プリミティブの組み合わせを素早く実装 |
| `MultipeerSession` のデリゲートメソッド実装 | インライン補完 | 定型的な MPC コードを高精度で補完 |
| `SoundManager` の PCM バッファ生成 | チャット | AVAudioEngine の低レベル API を教えながら実装 |

### 1-3. エージェントモードとチャットモードの使い分け判断基準

```
変更ファイルが 2 個以上　→　エージェントモード
コンパイルエラーを実際に直したい　→　エージェントモード
「なぜこうなるか」を理解したい　→　チャットモード
1 箇所の小さな修正　→　インライン補完 or チャット
フレームワーク移行・大規模リファクタリング　→　エージェントモード
```

> **ポイント**: エージェントモードはファイルを自律的に書き換えるため、  
> 変更してはいけないファイルを明示してからタスクを渡すこと（§6 参照）。

---

## 2. プロンプトエンジニアリング基礎

### 2-1. Why / What / How の3点セットが必須な理由

このプロジェクトの初期段階で「AR のバグを直して」とだけ送った結果、  
Copilot は **SceneKit (`SCNNode`) ベースのコード** を生成しました。  
当時すでに **RealityKit (`Entity`)** に移行済みだったため、全コードが使い物にならず  
30 分の作業が無駄になりました。

**教訓**: フレームワーク・スレッドモデル・禁止事項を最初に与えないと、Copilot は  
「それらしいコード」を生成するが「このプロジェクトに合うコード」にはならない。

### 2-2. 良いプロンプトと悪いプロンプトの対比

#### ❌ Before（悪い例）

```
ARView にバグが出現するコードを書いて
```

**問題点**: フレームワーク不明・スレッド制約なし・既存の `Bug3DNode` クラスを無視

#### ✅ After（良い例）

```
## Why
ARGameView.Coordinator でバグを AR 空間にスポーンするメソッドを追加したい。

## What
spawnBug() メソッドを Coordinator に追加する。
- BugType をランダムに選択し（Null 60%、Virus 40%）
- カメラから 0.5〜1.4 m の範囲にランダム配置する
- Bug3DNode.entity を AnchorEntity の子として ARView に追加する
- sendBugSpawned(id:type:normalizedX:normalizedY:) でプロジェクターに通知する

## How（制約）
- RealityKit の Entity / AnchorEntity を使う（SceneKit の SCNNode は使わない）
- UI 更新は必ず DispatchQueue.main.async で包む
- bugAnchorMap / anchorBug3DNodeMap などの辞書アクセスは mapLock (NSLock) で保護する
- BugType の switch は default を使わず全ケース網羅する

参照ファイル: ARGameView.swift, Bug3DNode.swift, GameProtocol.swift
```

### 2-3. コンテキスト設計: 何をどの順番で与えるか

#### ファイルの選び方

このプロジェクトで常にピン留めしているファイル（優先度順）:

| 優先度 | ファイル | 理由 |
|--------|---------|------|
| ★★★ | `SPEC.md` | ゲーム仕様・定数・状態遷移の唯一の真実 |
| ★★★ | `.github/copilot-instructions.md` | コーディング規約・禁止事項 |
| ★★★ | 変更対象ファイル本体 | Copilot に現在の実装を把握させる |
| ★★ | `PROMPT.md` | 各ファイルの実装説明（再現性向上） |
| ★★ | 関連する Shared 型 (`GameProtocol.swift`) | メッセージ型・BugType の定義 |
| ★ | 関連ファイル（呼び出し元）| コンテキスト補完 |

> **SPEC.md をピン留めする理由**: Copilot はセッションをまたいで記憶を持たない。  
> スポーン距離定数（`minSpawnDistance: 0.5m`）・スコア設計・通信フローなどを  
> 毎回コンテキストとして与えることで、前回と同じ品質を再現できる。

#### コンテキスト量の最適化

| 状況 | 推奨 | 理由 |
|------|------|------|
| コンテキストが少なすぎる | ❌ | フレームワーク違い・定数ズレが頻発 |
| コンテキストが多すぎる（10 ファイル以上） | ❌ | Copilot の注意が分散・矛盾した生成 |
| **重要ファイル 3〜5 個に絞る** | ✅ | 精度・速度のバランス最良 |

### 2-4. 制約の書き方

```
## 禁止事項（制約）
- SceneKit (SCNNode / ARSCNView) を新規コードに使わない
- switch BugType に default を書かない
- MCSession の encryptionPreference を .optional 以下にしない
- SceneKit レンダースレッドから UIKit プロパティへ直接アクセスしない
  （cachedViewHeight パターンを踏襲すること）
- 強制アンラップ (!) は使わない。guard let / if let を使う
- NSLock なしで辞書・配列に並行アクセスしない
```

---

## 3. このプロジェクト固有のプロンプトテンプレート集

### 3-1. 新規ファイル実装依頼テンプレート

```markdown
## Why（なぜ必要か）
[このファイル/機能を追加する背景・目的]

## What（何を実装するか）
- クラス名: [ClassName]
- 役割: [責務を1〜2文で]
- 主要メソッド:
  - [methodName()]: [何をするか]
  - [methodName2()]: [何をするか]

## How（実装方針・制約）
### 使用フレームワーク
- RealityKit（Entity / AnchorEntity）— SceneKit は使わない
- Swift Concurrency: @MainActor / actor isolation を正しく使う
- MultipeerConnectivity: MCSession.encryptionPreference = .required

### 禁止事項
- switch BugType に default を書かない（全ケース網羅）
- 強制アンラップ (!) を使わない
- レンダースレッドから UIKit へ直接アクセスしない
- NSLock なしで辞書/配列に並行アクセスしない

### 参照ファイル
- SPEC.md（仕様・定数）
- GameProtocol.swift（BugType / GameMessage 型）
- [関連する既存ファイル]

### コメント要件
各メソッドに実装意図・セキュリティ考慮・制約コメントを付ける

## ドキュメント更新
実装完了後、SPEC.md と PROMPT.md の該当箇所も更新すること
```

### 3-2. バグ修正・デバッグ依頼テンプレート

```markdown
## エラー情報
```
[Xcode のエラーメッセージをここに貼る]
```

## 再現手順
1. [操作手順 1]
2. [操作手順 2]
3. [クラッシュ / 不正動作]

## 期待する動作
[本来どうなるべきか]

## 関連ファイル・クラス
- [ファイル名.swift] の [メソッド名] 付近
- [関連する型・プロトコル]

## 制約
- RealityKit ベースで修正する（SceneKit への差し戻し禁止）
- @MainActor / nonisolated の付与を正しく行う
- 修正箇所に「なぜこの修正が必要か」のコメントを追加する
```

#### スレッドエラー調査の実例

```markdown
## エラー
"UI API called on a background thread" が ARView の
SceneEvents.Update ハンドラ内で発生する

## 対象
ARGameView.swift の Coordinator.session(_:didUpdate:) 内の
cachedViewHeight アクセス

## 依頼
1. スレッド違反の根本原因を特定してください
2. cachedViewHeight パターンを使った修正案を示してください
3. 同じパターンで他に問題になりそな箇所があれば指摘してください

## 制約
- DispatchQueue.main.async でラップする方針で修正する
- NSLock によるキャッシュアクセスは既存の cacheLock を流用する
```

### 3-3. コードレビュー依頼テンプレート

```markdown
## レビュー対象
[ファイル名.swift] の [クラス名 / メソッド名]

## レビュー観点（優先順）
1. Swift 6 strict concurrency:
   - @MainActor / nonisolated の付与漏れ
   - Sendable 準拠の不足
   - actor isolation 違反

2. スレッド安全性:
   - mapLock / cacheLock の保護範囲
   - SceneKit レンダースレッドからの UIKit アクセス

3. セキュリティ:
   - MCSession.encryptionPreference が .required か
   - 受信データのバリデーション（長さ・型チェック）
   - Codable デコードで try? でエラーを握り潰していないか

4. このプロジェクト固有ルール:
   - switch BugType に default がないか
   - 強制アンラップ (!) がないか
   - SPEC.md の定数と一致しているか

## 出力形式
問題箇所: [行番号 or コード引用]
問題の種類: [Concurrency / Security / Logic 等]
改善案: [具体的なコード]
```

### 3-4. リファクタリング依頼テンプレート

#### NSLock → actor 移行例

```markdown
## Why
Bug3DNode.entityCache の NSLock ベースの排他制御を
Swift 6 の actor isolation に移行したい。

## What
- Bug3DNode.entityCache を格納する CacheActor を追加する
- preloadAssets() / cloneEntity(for:) を async/await に変更する
- cacheLock (NSLock) を削除する

## How（制約）
- Swift 6 strict concurrency（Xcode 26 設定）に準拠する
- async/await の使用箇所は @MainActor コンテキストから呼ぶ
- 既存の呼び出しサイト（ARGameView.makeUIView / 
  WorldViewController.viewDidLoad）を壊さない
- SPEC.md / PROMPT.md の Bug3DNode セクションも更新する

参照: Bug3DNode.swift（現在の NSLock 実装）
```

#### ARSCNView → ARView (RealityKit) 移行例

```markdown
## Why
SceneKit ベースの ARSCNView / SCNNode を
RealityKit の ARView / Entity に完全移行する。

## What（移行マッピング）
- ARSCNView → ARView (cameraMode: .ar)
- ARSCNViewDelegate → ARSessionDelegate
- SCNNode → Entity（子エンティティとして追加）
- SCNScene → AnchorEntity
- renderer(_:updateAtTime:) → SceneEvents.Update

## 禁止事項
- import SceneKit を残さない
- SCNNode / ARSCNView を新規コードに使わない
- UI 更新は必ず DispatchQueue.main.async

移行後、SPEC.md のアーキテクチャ図と
PROMPT.md の ARGameView.swift セクションを更新すること
```

### 3-5. ドキュメント生成依頼テンプレート

#### SPEC.md / PROMPT.md 更新依頼例

```markdown
## 変更内容の概要
[今回実装・変更した内容を箇条書きで]

## 更新対象ドキュメント

### SPEC.md
以下のセクションを更新してください:
- 「AR スポーン設定」の定数表（変更があれば）
- 「出現バグ一覧」（BugType 変更があれば）
- 「アーキテクチャ概要」のファイル構成ツリー

### PROMPT.md
以下のファイル説明を更新してください:
- [変更したファイル名].swift のセクション
  - 変更・追加したメソッドの説明
  - 新しい定数・プロパティの説明

## 制約
- 既存の書式（表・コードブロック・コメント形式）を維持する
- コードの実態と矛盾しないよう、実装を参照して更新する
```

#### コードコメント追加依頼例

```markdown
以下のメソッドに以下の3種類のコメントを追加してください。

対象: Bug3DNode.swift の preloadAssets()

1. 実装意図コメント（なぜこの方法を選んだか）
   例: // USDZ をゲーム開始前に非同期ロードし entityCache に保存する。
       // clone() は Entity.loadAsync より高速なため、初回のみロードし以降は clone する。

2. セキュリティ考慮コメント（該当する場合）
   例: // 外部 URL ではなく Bundle リソースのみ参照するため、
       // パストラバーサル等のリスクは存在しない。

3. 制約・注意点コメント
   例: // このメソッドは iOS AR パス（ARGameView.makeUIView）と
       // プロジェクターパス（WorldViewController.viewDidLoad）の
       // 両方から呼ばれる必要がある。新規エントリポイント追加時は注意。
```

### 3-6. テストコード生成依頼テンプレート

#### Swift Testing フレームワーク向け

```markdown
## What
GameManager の状態遷移ロジックのユニットテストを Swift Testing で書く。

## テスト対象
- GameManager.startCalibration() → state: .waiting → .calibrating
- GameManager.setWorldOrigin(transform:) → state: .calibrating → .ready
- GameManager.confirmReady() → state: .ready → .playing
- GameManager.finishGame() → state: .playing → .finished
- GameManager.resetGame() → state: .finished → .waiting

## 制約
- @Test / @Suite / #expect を使う（XCTest は使わない）
- @MainActor で GameManager を操作する
- MultipeerSession の実際の接続は不要（モックまたは無視）
- 各テストは独立して実行できるようにする
```

#### MultipeerConnectivity のモック化依頼例

```markdown
## Why
MultipeerSession を実機なしでテストしたい。

## What
MultipeerSessionProtocol を定義し、
MockMultipeerSession を実装してテスト用に差し替えられるようにする。

## 対象メソッド（最低限モック化する）
- send(_ message: GameMessage)
- connectedPeers: [MCPeerID]
- delegate: MultipeerSessionDelegate?

## 制約
- 既存の MultipeerSession の public API を壊さない
- GameManager が MultipeerSessionProtocol を参照するよう変更する
- MCSession は実際には生成しない（テスト時は MockMultipeerSession を注入）
```

---

## 4. copilot-instructions.md の設計ノウハウ

### 4-1. `.github/copilot-instructions.md` の仕組み

`.github/copilot-instructions.md` は GitHub Copilot がリポジトリ内で動作する際に  
**自動的に読み込まれる恒久的な指示書**です。  
チャット・エージェント・インライン補完すべてのモードで有効です。

- プロンプトの冒頭に「暗黙のコンテキスト」として挿入されるイメージ
- 毎回プロンプトに書かなくてよい「チームルール」を定義する場所
- コーディング規約・禁止事項・ドキュメント更新ルールを書く

### 4-2. このプロジェクトで記述したルールとその効果

| ルール | 記述内容 | 効果 |
|--------|---------|------|
| ドキュメント更新 | コード変更時は SPEC.md / PROMPT.md を同時更新 | PR ごとにドキュメントが自動更新される。乖離ゼロ |
| 網羅的 switch | `BugType` switch に `default` を書かない | 新ケース追加時のコンパイルエラーで漏れを検知 |
| スレッドアクセス禁止 | レンダースレッドから UIKit へ直接アクセスしない | `cachedViewHeight` パターンが自動的に踏襲される |
| 定数の閉じ込め | 新定数は `private static let` で閉じ込める | マジックナンバーが生成コードに出現しなくなった |
| NSLock パターン | `cacheLock` パターンを踏襲する | スレッドセーフなキャッシュアクセスが自然に生成される |
| PR 単位 | 1PR = 1機能（単一責務） | レビューしやすい小さな PR が生成される |
| Why/What/How 必須 | コード生成前に仕様ドキュメントを出力する | 仕様外の実装が減少、コードの意図が明確になった |

### 4-3. 効果的な instructions の書き方（Do / Don't）

| Do ✅ | Don't ❌ |
|-------|---------|
| 具体的なクラス名・メソッド名を挙げて説明する | 「いいコードを書く」のような抽象的ルール |
| 禁止事項を明確に書く（`default` 禁止等） | 「できれば避ける」のような曖昧な表現 |
| パターン名を定義する（`cachedViewHeight パターン`） | コンテキストなしのコード断片だけ |
| 更新が必要なドキュメントを明示する | 「ドキュメントも更新」とだけ書く |
| フレームワーク名と禁止フレームワークを明示する | 「最新の API を使う」だけ |

### 4-4. 効果のあったルール TOP 5

| 順位 | ルール | 効果の理由 |
|------|--------|-----------|
| 🥇 1位 | `SPEC.md / PROMPT.md` 同時更新 | 14 週間でドキュメント乖離が起きなかった最大の要因 |
| 🥈 2位 | `switch BugType` の `default` 禁止 | `stag` ケースの追加時に3ファイルで漏れをコンパイルエラーで検知 |
| 🥉 3位 | Why/What/How を先に出力 | 実装前に仕様の曖昧さが発覚し、無駄な実装が減少 |
| 4位 | `private static let` 定数閉じ込め | SPEC.md との定数乖離がなくなった |
| 5位 | 1PR = 1機能 | レビュー時間が平均 1/3 に短縮された（体感） |

---

## 5. SPEC.md パターン ― AI の記憶を補う設計

### 5-1. なぜ AI は「記憶」を持てないのか

GitHub Copilot（LLM）はセッション単位でステートレスです。  
「先週話した設計」「前の PR で決めた定数」は次のセッションでは存在しません。

```
セッション 1: "スポーン距離は 0.5〜1.4m に決定"
セッション 2: "スポーン距離は？" → 答えられない（覚えていない）
```

**解決策**: すべての決定事項を `SPEC.md` に書き、毎回コンテキストとして渡す。

### 5-2. SPEC.md を「生きたドキュメント」として維持する運用ルール

1. **コードを変更する前に SPEC.md を更新する**（仕様先行）  
2. **コード変更と同じ PR で SPEC.md も更新する**（同期更新）  
3. **定数の変更は必ず SPEC.md の表も更新する**（単一の真実の源）  
4. **画面遷移・通信フローは図（テキストベース）で維持する**

```markdown
# SPEC.md の定数表の例（AR スポーン設定）

| 定数 | 値 | 説明 |
|------|---|------|
| minSpawnDistance | 0.5 m | カメラからの最小スポーン距離 |
| maxSpawnDistance | 1.4 m | カメラからの最大スポーン距離 |
| referenceDistance | 3.0 m | スケール計算の基準距離 |
| minBugScale | 0.3 | スケール下限 |
| maxBugScale | 5.0 | スケール上限 |
```

> コードの定数とこの表が一致しているか、PR レビューで必ず確認する。

### 5-3. コードと同 PR でドキュメントを更新させる仕組み

`.github/copilot-instructions.md` に以下を記述することで、  
Copilot が自動的にドキュメント更新を含むコードを生成するようになります:

```
コードに変更を加えた際は、**必ず関連するドキュメントも同時に更新してください**。
- `SPEC.md` — ゲーム仕様・ルール・アーキテクチャの変更を反映する。
- `PROMPT.md` — AI 継続開発プロンプト（各ファイルの詳細な実装説明）を更新する。
```

### 5-4. AI に「前回と同じ品質を再現させる」テクニック

```markdown
# 品質再現プロンプト

前回の実装と同じ品質・スタイルで [機能名] を実装してください。

参照してほしいファイル（現在の品質基準）:
- Bug3DNode.swift（USDZ + フォールバックパターンの手本）
- ARGameView.swift（NSLock パターン・mapLock 使用の手本）
- SPEC.md（定数・仕様の参照元）

このプロジェクトの規約（.github/copilot-instructions.md に記載）に従うこと。
```

---

## 6. エージェントモード活用術

### 6-1. エージェントモードと通常チャットの違い

| 項目 | チャットモード | エージェントモード |
|------|-------------|----------------|
| ファイル操作 | 提案のみ（人間が適用） | 自律的に読み・書き・実行 |
| 複数ファイル対応 | 1〜2 ファイル程度 | 制限なく複数ファイル横断 |
| ビルド確認 | なし | ビルド・テスト実行可能 |
| 適用速度 | 遅い（人間が貼り付け） | 速い（自動適用） |
| リスク | 低い | 意図しない変更リスクあり |

### 6-2. このプロジェクトでのエージェントモード活用シーン

#### 複数ファイルにまたがるリファクタリング

```markdown
## エージェントへの指示例

以下のリファクタリングを実施してください。

対象: SceneKit → RealityKit 移行
- ARGameView.swift の ARSCNView を ARView に置き換える
- Bug3DNode.swift の SCNNode を Entity に置き換える
- 関連する import SceneKit を削除する

## 変更してはいけないファイル
- GameProtocol.swift（型定義は変更しない）
- SoundManager.swift（サウンド処理は無関係）
- World/ 以下のファイル（プロジェクター側は別タスク）

## 完了条件
- Xcode でビルドエラーがゼロになること
- SPEC.md のアーキテクチャ図を更新すること
- PROMPT.md の ARGameView.swift / Bug3DNode.swift セクションを更新すること
```

#### フレームワーク移行

```markdown
ProjectorBug3DCoordinator を WorldViewController に統合したい。

移行前: 外部クラス ProjectorBug3DCoordinator.swift
移行後: WorldViewController の内部クラス

変更対象:
- WorldViewController.swift: 内部クラス定義を追加
- ProjectorBug3DCoordinator.swift: 削除

注意:
- attach() / detach() の呼び出しインターフェースは維持する
- 自律スポーンロジック（startAutonomousSpawning）は引き継ぐ
- SPEC.md のファイル構成ツリーを更新する
```

#### ドキュメント自動生成

```markdown
今回の PR（Bug3DNode に USDZ アニメ対応を追加）に対応して
SPEC.md と PROMPT.md を更新してください。

変更内容:
1. USDZ モデルマッピング表に toy_biplane を追加
2. preloadAssets() の動作説明を更新（availableAnimations ループ）
3. usdzScale(for:) の butterfly ケースを追記

形式: 既存の書式（表・コードブロック）を維持する
```

### 6-3. エージェントに指示する際の注意点

1. **スコープを限定する**: 変更対象ファイルを明示し「それ以外は触らない」と書く  
2. **変更禁止ファイルを列挙する**: 特に共有型定義（`GameProtocol.swift`）は誤変更リスクが高い  
3. **完了条件を定義する**: 「ビルドエラーゼロ」「SPEC.md 更新済み」など検証基準を設ける  
4. **レビューポイントを指定する**: 「スレッド安全性を特に確認してください」と伝える

### 6-4. エージェントが失敗しやすいパターンと対策

| 失敗パターン | 症状 | 対策 |
|------------|------|------|
| スコープ超え | 無関係ファイルを書き換える | 「変更してはいけないファイル」を明示 |
| 旧 API 混入 | SceneKit API が混在する | フレームワーク制約をプロンプトに書く |
| ドキュメント忘れ | コードのみ更新してドキュメントを更新しない | 「SPEC.md / PROMPT.md も更新」を毎回書く |
| 定数ズレ | SPEC.md と異なる値を使う | SPEC.md をコンテキストに必ず含める |
| 過剰実装 | 依頼していない機能を追加する | 「これ以外の機能を追加しない」と明示 |
| ビルドエラー放置 | コンパイルエラーが残る | 「ビルドエラーゼロを確認してから完了とする」 |

---

## 7. チーム開発での Copilot 活用ルール

### 7-1. 「そのままマージしない」ためのレビュー文化

> **重要**: Copilot の出力は「動くかもしれないが正しいとは限らない」。  
> 自信満々に見えるコードでも、ロジックの微妙なズレ・スレッド違反・  
> セキュリティの欠陥が含まれることがある。

**レビュー文化の作り方**:
1. Copilot 生成コードを「提案」として扱う（「完成品」ではない）
2. PR 説明に「Copilot 生成を含む」を明記する
3. レビュアーは §13 のチェックリストを使う
4. 初回の実機テストは必ずレビュアーも行う

### 7-2. マージ前チェックリスト（このプロジェクトで運用）

#### Swift 6 strict concurrency

- [ ] `@MainActor` 付与漏れがない
- [ ] `nonisolated` が意図的に使われている
- [ ] `Sendable` 準拠が必要な型に付いている
- [ ] actor isolation 違反がコンパイル警告に出ていない
- [ ] `@preconcurrency` で警告を握り潰していない

#### セキュリティ

- [ ] `MCSession.encryptionPreference == .required`
- [ ] 受信データのサイズ・型バリデーションがある
- [ ] `Codable` デコードで `try?` でなく `try catch` を使っている
- [ ] 強制アンラップ (`!`) がない（または十分な根拠コメントがある）

#### ドキュメント更新

- [ ] `SPEC.md` が変更内容を反映して更新されている
- [ ] `PROMPT.md` の該当ファイル説明が更新されている
- [ ] 追加した定数・メソッドにコメント（意図・制約）が付いている

#### このプロジェクト固有

- [ ] `switch BugType` に `default` がない
- [ ] `NSLock`（`mapLock` / `cacheLock`）の保護範囲が正しい
- [ ] `Bug3DNode.preloadAssets()` が両パスで呼ばれている（新エントリポイント追加時）
- [ ] SPEC.md の定数（`minSpawnDistance` 等）とコードの値が一致している

### 7-3. チーム内でのプロンプト共有（PROMPT_26.md 運用）

このプロジェクトでは `PROMPT_26.md` に「実際に使ったプロンプト集」を蓄積しています。  
新しいプロンプトが効果的だった場合は以下の形式で追記します:

```markdown
## [機能名 / タスク名] — [YYYY-MM-DD]

### 使用モード
[インライン / チャット / エージェント]

### プロンプト
```
[実際に使ったプロンプト]
```

### 結果
[効果・問題点・改善点]

### 再利用時の注意
[次に使うときの注意事項]
```

### 7-4. 初心者メンバーへの Copilot 導入のコツ

#### 最初に教えるべき3つのこと

1. **Why/What/How テンプレートを使う習慣を作る**  
   最初の1週間はテンプレートを見ながら必ずプロンプトを書く。「慣れたら」では定着しない。

2. **SPEC.md を必ずコンテキストに含める**  
   「なんかうまく生成されない」の 80% はコンテキスト不足。まず SPEC.md を渡す。

3. **生成されたコードを必ず一行ずつ読む**  
   Tab で即受け入れは禁止。「なぜこの行が必要か」を説明できないコードはマージしない。

#### 避けさせるべき失敗パターン

| NG パターン | 対策 |
|------------|------|
| エラーメッセージだけ貼って「直して」 | 再現手順・期待動作・関連ファイルもセットで渡す |
| 生成コードをコピペしてビルド確認のみでマージ | §13 のチェックリストを必ず通す |
| 複数機能を一度に依頼 | 1 プロンプト = 1 機能に分割する |
| 「いい感じに」という依頼 | 具体的な制約・形式・条件を書く |
| SPEC.md を確認せずに定数を書く | 定数は必ず SPEC.md 参照で入力する |

---

## 8. iOS / Swift 開発固有のプロンプトテクニック

### 8-1. Swift 6 strict concurrency エラーを Copilot に直させるコツ

#### actor isolation エラーの依頼例

```markdown
以下の Swift 6 コンパイルエラーを修正してください。

エラー:
"Main actor-isolated property 'arBugScene' can not be mutated
from a nonisolated context"

対象コード: GameManager.swift の didReceive(_:fromPeer:) 内

修正方針:
1. GameManager クラス全体に @MainActor を付与するか
2. 問題の箇所だけ Task { @MainActor in ... } でラップするかを判断して修正
   （GameManager は ObservableObject なので @MainActor が望ましい）

制約:
- MultipeerSession のデリゲートコールバックは background スレッドで呼ばれる
- スコアやゲーム状態の更新は必ずメインスレッドで行う
```

#### Sendable 準拠の追加依頼例

```markdown
以下の型を Swift 6 Sendable に準拠させてください。

対象: GameProtocol.swift の BugType, GameMessage, LaunchPayload 等

制約:
- これらの型は Multipeer Connectivity の送受信スレッドと
  メインスレッドをまたいで使われる
- Codable 準拠は維持する
- 不変（let only）にできるプロパティはすべて let にする
- @unchecked Sendable は使わない（本当に Sendable にする）
```

#### @MainActor / nonisolated の使い分け依頼例

```markdown
ARGameView.Coordinator の以下のメソッドについて、
@MainActor / nonisolated をどう付与すべきか教えてください。

- session(_:didAdd:) — ARSessionDelegate、background スレッドで呼ばれる
- renderer(_:updateAtTime:) — SCNSceneRendererDelegate、レンダースレッドで呼ばれる
- spawnBug() — ARView への Entity 追加を行う
- sendBugSpawned(id:type:) — MultipeerSession.send() を呼ぶ

このプロジェクトの制約:
- ARView への Entity 追加はメインスレッドが安全
- MultipeerSession.send() は MPC のスレッドで実行する
- cachedViewHeight は nonisolated なメソッドから読む
```

### 8-2. ARKit / RealityKit 向けのプロンプト工夫

#### Entity / AnchorEntity パターンを前提とした指示

```markdown
## RealityKit の Entity パターン（このプロジェクトの前提）

- バグは AnchorEntity（worldTransform 固定）の子 Entity として追加する
- ARView.scene.addAnchor() でシーンに追加する
- Entity の削除は anchor.removeFromParent() で行う
- アニメーション: entity.availableAnimations を playAnimation(animation.repeat()) でループ

この前提で Bug3DNode に [機能名] を追加してください。
```

#### レンダースレッド問題（UIKit 直アクセス禁止）を守らせる方法

```markdown
## このプロジェクトのスレッドルール（必ず守ること）

SceneKit / RealityKit のレンダースレッドから UIKit に直接アクセスしてはいけない。
代わりに cachedViewHeight パターンを使う:

```swift
// NG: レンダースレッドから UIView.bounds に直接アクセス
let height = arView.bounds.height  // ❌

// OK: メインスレッドで事前キャッシュした値を使う
private var cachedViewHeight: CGFloat = 667  // ✅ @MainActor で更新
```

このルールに違反するコードを生成しないこと。
```

### 8-3. MultipeerConnectivity のセキュリティ要件を守らせる方法

```markdown
## MCSession のセキュリティ要件（このプロジェクトの必須要件）

MCSession を作成する際は必ず以下を使うこと:

```swift
// ✅ 必須: 暗号化を要求する
let session = MCSession(
    peer: peerID,
    securityIdentity: nil,
    encryptionPreference: .required  // ← 必ず .required
)
```

`.optional` や `.none` は絶対に使わない。
祭り会場の公共 Wi-Fi 環境での使用を想定しているため、
暗号化なしの通信はセキュリティリスクになる。
```

### 8-4. フレームワーク移行（旧 API → 新 API）の効率的な依頼方法

```markdown
## フレームワーク移行プロンプト（SceneKit → RealityKit）

以下の対応表に従って [ファイル名.swift] を移行してください。

| SceneKit（旧） | RealityKit（新） |
|--------------|----------------|
| SCNNode | Entity |
| ARSCNView | ARView |
| ARSCNViewDelegate | ARSessionDelegate + SceneEvents.Update |
| SCNScene | AnchorEntity |
| SCNGeometry | MeshResource |
| SCNMaterial | SimpleMaterial / PhysicallyBasedMaterial |
| renderer(_:updateAtTime:) | SceneEvents.Update サブスクリプション |
| SCNNode.position | Entity.transform.translation |

移行後:
- import SceneKit を削除する
- SPEC.md のアーキテクチャ概要を更新する
- PROMPT.md の該当セクションを更新する
```

---

## 9. プロンプトエンジニアリング アンチパターン

このプロジェクトで実際に経験した「やってはいけない」パターンです。

### ❌ パターン 1: 曖昧な依頼

**Before（悪い例）**:
```
バグを直して
```

**After（良い例）**:
```
ARGameView.swift の spawnBug() でバグが正しい位置にスポーンされない問題を修正してください。
エラー: バグが常にカメラ正面 1m に配置される（ランダム位置にならない）
期待: minSpawnDistance(0.5m)〜maxSpawnDistance(1.4m) のランダム位置に配置される
原因調査から始めて、修正案を示してください。
```

**改善のポイント**: 「何が」「どう」おかしいかを具体的に伝える。

---

### ❌ パターン 2: コンテキスト不足

**Before（悪い例）**:
```
Bug3DNode に USDZ アニメーションを追加してください
```

**After（良い例）**:
```
Bug3DNode.swift に USDZ アニメーションのループ再生を追加してください。

コンテキスト（必ず読んでください）:
- Bug3DNode.swift（現在の実装）
- SPEC.md（USDZ モデルマッピング表）

実装仕様:
- Entity.loadAsync(named:) でロード後、availableAnimations を再帰取得する
- playAnimation(animation.repeat(duration: .infinity)) でループ
- アニメーションがない場合は手続き的アニメにフォールバック
```

**改善のポイント**: 関連ファイルを必ず渡す。

---

### ❌ パターン 3: スコープが広すぎる

**Before（悪い例）**:
```
マルチプレイ機能を全部実装してください
```

**After（良い例）**:
```
MultipeerSession.swift に接続状態通知デリゲートを追加してください。

今回のスコープ（これだけ実装する）:
- MultipeerSessionDelegate プロトコルに didChangeConnectionStatus(isConnected:) を追加
- GameManager がこのデリゲートを実装して isConnected を更新する

次の PR で実装（今回は実装しない）:
- 最大接続数制限（3台）
- 接続拒否ロジック
```

**改善のポイント**: 1 プロンプト = 1 機能に分割する。

---

### ❌ パターン 4: 制約を後から追加する

**Before（悪い例）**:
```
# プロンプト 1回目
ARView にバグをスポーンするコードを書いて

# プロンプト 2回目（後から追加）
あ、SCNNode じゃなくて RealityKit の Entity を使ってください
あと NSLock で保護してください
あと default: は書かないでください
```

**After（良い例）**:
```
# 最初から制約をすべて書く
ARView にバグをスポーンするコードを書いてください。

制約（最初から全部）:
- RealityKit Entity / AnchorEntity を使う（SCNNode は禁止）
- NSLock (mapLock) でマップアクセスを保護する
- switch BugType に default を書かない
- DispatchQueue.main.async で UI 更新をラップする
```

**改善のポイント**: 制約は最初のプロンプトに全部書く。

---

### ❌ パターン 5: AI の出力を確認せずに承認する

**Before（悪い例）**:
```
// Copilot が生成したコード（確認なしでコミット）
let session = MCSession(peer: myPeerID, securityIdentity: nil,
                         encryptionPreference: .none)  // 暗号化なし！
```

**After（良い例）**:
```
生成後に .encryptionPreference の値を必ず確認する。
祭り会場（公共ネットワーク）では .required 以外は使用禁止。
```

**改善のポイント**: セキュリティ要件に関わるコードは必ず手動確認。

---

### ❌ パターン 6: フレームワーク指定を省略する

**Before（悪い例）**:
```
3D のバグモデルを表示するコードを書いてください
```

**After（良い例）**:
```
RealityKit の Entity を使って Bug3DNode を実装してください。
SceneKit (SCNNode / ARSCNView) は使わないでください。
このプロジェクトは ARView（RealityKit）ベースです。
```

**改善のポイント**: SceneKit か RealityKit か常に明示する。

---

### ❌ パターン 7: switch の default 禁止を伝え忘れる

**Before（悪い例）**:
```
BugType の switch 文を書いてください
// → Copilot は default: case が付いたコードを生成する
```

**After（良い例）**:
```
BugType の switch 文を書いてください。
default: は使わず、.butterfly / .beetle / .stag の全ケースを明示してください。
（新しい BugType 追加時にコンパイルエラーで漏れを検知するため）
```

**改善のポイント**: `default` 禁止は copilot-instructions.md にも書いておく。

---

## 10. 継続開発のための Copilot 活用フロー

### 10-1. 新機能追加フロー

```
[1] SPEC.md 更新
    ├── 新機能の仕様を SPEC.md に追記（先に仕様を固める）
    ├── Why（なぜ必要か）/ What（何を実装するか）を SPEC.md に書く
    └── Copilot に「SPEC.md の [セクション名] を参照して実装して」と伝えられる状態にする
    
[2] プロンプト作成（Why/What/How）
    ├── §3-1 のテンプレートを使う
    ├── 制約（禁止事項・フレームワーク・スレッドルール）を必ず書く
    └── コンテキストファイル（SPEC.md / 関連ファイル）を指定する
    
[3] Copilot に実装依頼
    ├── エージェントモード: 複数ファイルにまたがる場合
    └── チャット/インライン: 単一ファイルの場合
    
[4] レビュー（§7-2 のチェックリスト）
    ├── Swift 6 concurrency 確認
    ├── セキュリティ確認
    ├── SPEC.md との定数一致確認
    └── 実機テスト（AR 機能は必ず実機で確認）
    
[5] PROMPT.md 更新
    ├── 変更したファイルのセクションを更新
    └── 新しいメソッド・定数の説明を追記
    
[6] PR 作成
    └── 1PR = 1機能（単一責務）
```

### 10-2. バグ修正フロー

```
[1] エラー収集
    ├── Xcode のエラーメッセージ・スタックトレースを取得
    ├── 再現手順を明確にする
    └── 関連ファイルを特定する（ARGameView.swift / Bug3DNode.swift 等）
    
[2] Copilot にデバッグ仮説を出させる
    ├── §3-2 のデバッグテンプレートを使う
    ├── 「原因の仮説を3つ挙げてください」と聞く
    └── 最も可能性が高い仮説から修正を依頼する
    
[3] 修正依頼
    ├── 制約（フレームワーク・スレッドルール）を明示する
    └── 「修正箇所に理由コメントを追加してください」と伝える
    
[4] テスト追加依頼
    ├── §3-6 のテストテンプレートを使う
    └── 再現ケースをカバーするテストを追加する
    
[5] レビュー
    └── §13-4 のレビューフローを実施
```

### 10-3. リファクタリングフロー

```
[1] 対象の特定
    ├── 「現在の問題点は何か」をチャットで確認する
    └── 影響範囲（ファイル一覧）を明確にする
    
[2] Copilot に移行計画を出させる
    ├── 「リファクタリング計画を段階的に示してください」
    ├── 各ステップで変更するファイルを確認する
    └── 変更してはいけないファイル・APIを特定する
    
[3] ファイル単位で依頼
    ├── 1ファイル = 1 PR を目標に分割する
    ├── §3-4 のリファクタリングテンプレートを使う
    └── 各ステップで動作確認する
    
[4] ドキュメント更新
    ├── SPEC.md のアーキテクチャ図を更新する
    └── PROMPT.md の各ファイルセクションを更新する
```

---

## 11. Copilot 活用度セルフチェックリスト

### 🟢 初級（Copilot を使い始めた段階）

- [ ] インライン補完を Tab で受け入れ/拒否できる
- [ ] Copilot チャットで質問できる
- [ ] 「何をしたいか」を1〜2文で伝えられる（参照: §2）
- [ ] 生成コードをそのままコミットしない習慣がある
- [ ] SPEC.md をコンテキストに含める習慣がある（参照: §5）
- [ ] エラーメッセージを貼り付けてデバッグを依頼できる（参照: §3-2）
- [ ] フレームワーク名（RealityKit/ARKit）を明示できる（参照: §8）

### 🟡 中級（Copilot を日常的に使いこなせている段階）

- [ ] Why/What/How テンプレートを使えている（参照: §3-1）
- [ ] コンテキストファイルを適切に3〜5個に絞れている（参照: §2-3）
- [ ] エージェントモードで複数ファイルのリファクタリングができる（参照: §6）
- [ ] Swift 6 concurrency エラーを Copilot に修正させられる（参照: §8-1）
- [ ] `switch BugType` の `default` 禁止を守らせられる（参照: §2-4）
- [ ] MCSession の `encryptionPreference` を確認している（参照: §7-2）
- [ ] SPEC.md と PROMPT.md の同時更新を習慣化できている（参照: §5-3）
- [ ] §7-2 のマージ前チェックリストを使っている
- [ ] NSLock の保護範囲を確認できる（参照: §13-2）
- [ ] 生成コードの「なぜこの行が必要か」を全行説明できる

### 🔴 上級（チームをリードできる段階）

- [ ] `.github/copilot-instructions.md` を設計・改善できる（参照: §4）
- [ ] SPEC.md を生きたドキュメントとして運用できる（参照: §5）
- [ ] チームのプロンプト集（PROMPT_26.md 等）を整備できる（参照: §7-3）
- [ ] エージェントへの指示でスコープを適切に限定できる（参照: §6-3）
- [ ] アンチパターンを見つけてレビューコメントで指摘できる（参照: §9）
- [ ] Swift Testing で Copilot 生成コードのテストを追加できる（参照: §3-6）
- [ ] フレームワーク移行（SceneKit → RealityKit 等）を Copilot で完遂できる（参照: §8-4）
- [ ] §13 のレビューガイドラインを使って Copilot 生成 PR をレビューできる
- [ ] 初心者メンバーへの Copilot 導入をサポートできる（参照: §7-4）
- [ ] Copilot の出力品質を評価して改善フィードバックを出せる

---

## 12. 参考リソース・次のステップ

### GitHub Copilot 公式ドキュメント

| リソース | URL |
|---------|-----|
| GitHub Copilot ドキュメント（公式） | https://docs.github.com/copilot |
| Copilot in Xcode | https://docs.github.com/copilot/using-github-copilot/using-github-copilot-in-your-ide |
| Copilot instructions ファイル | https://docs.github.com/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot |
| Copilot エージェントモード | https://docs.github.com/copilot/using-github-copilot/using-copilot-coding-agent-to-work-on-tasks |

### Apple ドキュメント・WWDC セッション

| リソース | URL |
|---------|-----|
| RealityKit ドキュメント | https://developer.apple.com/documentation/realitykit |
| ARKit ドキュメント | https://developer.apple.com/documentation/arkit |
| MultipeerConnectivity ドキュメント | https://developer.apple.com/documentation/multipeerconnectivity |
| Swift Testing ドキュメント | https://developer.apple.com/documentation/testing |
| WWDC23: Meet Swift Testing | https://developer.apple.com/videos/play/wwdc2023/10195/ |
| WWDC24: What's new in Swift | https://developer.apple.com/videos/play/wwdc2024/10136/ |
| Apple AR Quick Look ギャラリー（USDZ） | https://developer.apple.com/jp/augmented-reality/quick-look/ |

### このリポジトリの関連ドキュメント

| ファイル | 説明 |
|---------|------|
| `SPEC.md` | ゲーム仕様・アーキテクチャ・定数の完全定義 |
| `PROMPT.md` | 各ファイルの実装詳細・AI 継続開発コンテキスト |
| `PROMPT_26.md` | 使用したプロンプト集・ナレッジ蓄積 |
| `.github/copilot-instructions.md` | Copilot への恒久的コーディング規約 |

### チームが次に取り組むべき改善点（優先度順）

| 優先度 | 改善項目 | 理由 |
|--------|---------|------|
| 🔴 高 | Swift Testing によるユニットテスト追加 | Copilot 生成コードの品質保証が不十分 |
| 🔴 高 | NSLock → Swift actor への移行 | Swift 6 strict concurrency への完全準拠 |
| 🟡 中 | MultipeerSession のモック化 | 実機なしでのテスト自動化 |
| 🟡 中 | PROMPT_26.md のプロンプト集整理 | チームナレッジの再利用性向上 |
| 🟢 低 | CI/CD への Swift Testing 統合 | 自動テスト実行の仕組み化 |

---

## 13. 人間によるコードレビューガイドライン

> **目的**: Copilot が生成したコードを人間がレビューする際の観点・知識・注意点を体系化する。  
> AI はコンパイルエラーを回避しつつ「それらしいコード」を生成するが、  
> 設計意図・スレッド安全性・セキュリティ・UX 上の整合性は人間がチェックしなければならない。

### 13-1. レビューの基本姿勢

- **Copilot 生成コードは「動くかもしれないが正しいとは限らない」という前提で読む。**
- 「このコードが機能するか」だけでなく「このコードが *意図通りに* 機能するか」を確かめる。
- Copilot は古い API・廃止予定 API を出力することがある。Apple Developer Documentation で最新性を確認する。
- 生成コードが既存の命名規則・アーキテクチャパターン（`Coordinator` パターン・`mapLock` 保護等）と一致しているか確認する。
- **Copilot の「自信」に騙されない**: エラーがなく自然に見えるコードでもロジックが微妙にずれていることがある。

### 13-2. このプロジェクト固有のレビューチェックリスト

#### Swift / 言語レベル

| チェック項目 | 確認方法 | NG 時の対処法 |
|------------|---------|-------------|
| 強制アンラップ (`!`) がない、または根拠コメントがある | `grep -n "!"` で検索 | `guard let` / `if let` に変換 |
| `switch BugType` が網羅的（`default` なし） | `grep -n "default:"` で検索 | `default` を削除し全ケースを明示 |
| `try!` / `try?` の使い方が適切か | コードを目視確認 | `try catch` で明示的なエラーハンドリングに変換 |
| Swift 6 strict concurrency が正しいか | Xcode Build の警告確認 | `@MainActor` / `nonisolated` / `Sendable` を適切に付与 |
| クロージャの `[weak self]` 漏れがないか | クロージャを目視確認 | `[weak self]` を追加して循環参照を防止 |

#### スレッド安全性

| チェック項目 | 確認方法 | NG 時の対処法 |
|------------|---------|-------------|
| `mapLock` / `cacheLock` 保護範囲が正しいか | ロック/アンロックのペアを目視確認 | `lock()` 〜 `unlock()` のスコープを修正 |
| SceneKit レンダースレッドから UIKit アクセスしていないか | `renderer(_:updateAtTime:)` 内を確認 | `cachedViewHeight` パターンに置き換え |
| `DispatchQueue.main.async` の漏れがないか | UI 更新箇所を確認 | `DispatchQueue.main.async { }` でラップ |
| `SceneEvents.Update` ハンドラ内で重い処理をしていないか | ハンドラ内を確認 | 重い処理を別スレッド/フレームに移動 |

#### AR / RealityKit

| チェック項目 | 確認方法 | NG 時の対処法 |
|------------|---------|-------------|
| `AnchorEntity` / `Entity` 生成がメインスレッドか | Thread Sanitizer で確認 | `DispatchQueue.main.async` でラップ |
| `Bug3DNode.preloadAssets()` が両パスで呼ばれているか | `ARGameView.makeUIView` と `WorldViewController.viewDidLoad` を確認 | 漏れているパスに追加 |
| スポーン距離定数が SPEC.md と一致しているか | コードと SPEC.md の表を照合 | SPEC.md の値に合わせる |
| USDZ 不在時のフォールバック処理があるか | `loadUSDZModel()` の分岐を確認 | 手続き的ジオメトリへのフォールバックを追加 |

#### MultipeerConnectivity / セキュリティ

| チェック項目 | 確認方法 | NG 時の対処法 |
|------------|---------|-------------|
| `MCSession.encryptionPreference == .required` か | `MCSession(` の初期化箇所を確認 | `.required` に変更 |
| 受信データの長さ・型チェックがあるか | `didReceive(_:fromPeer:)` を確認 | バリデーションコードを追加 |
| `MCPeerID` の保持・解放タイミングが正しいか | `peerJoined` / `peerLeft` の処理を確認 | ライフサイクルに合わせて修正 |
| `Codable` デコードで `try?` でエラーを握り潰していないか | デコード箇所を確認 | `try catch` に変換して適切にログ/ハンドリング |

#### ゲームロジック / 状態管理

| チェック項目 | 確認方法 | NG 時の対処法 |
|------------|---------|-------------|
| `GameManager.state` の遷移が SPEC.md の遷移図と一致しているか | SPEC.md の画面構成表と照合 | 遷移ロジックを修正 |
| `BugType` の得点・出現率が SPEC.md と一致しているか | SPEC.md の「出現バグ一覧」と照合 | 定数を SPEC.md の値に合わせる |
| サーバー/スタンドアロンモード分岐に漏れがないか | `.projectorServer` / `.standalone` の分岐を確認 | 漏れているモードのケースを追加 |
| タイマー・スポーンループの開始/停止が対になっているか | start/stop の対を確認 | 対になっていない場合はリーク防止のため修正 |

#### ドキュメント

| チェック項目 | 確認方法 | NG 時の対処法 |
|------------|---------|-------------|
| `SPEC.md` が変更内容を反映して更新されているか | PR の diff を確認 | 同じ PR でドキュメントを更新依頼 |
| `PROMPT.md` の該当ファイル説明が更新されているか | PR の diff を確認 | 同じ PR でドキュメントを更新依頼 |
| 追加した定数・メソッドにコメントが付いているか | 追加コードを確認 | 実装意図・制約・セキュリティコメントを追加 |

### 13-3. Copilot 生成コードでよく見られる問題パターン（警戒リスト）

| パターン | 症状 | 発生しやすい箇所 | 検出方法 | 修正方針 |
|---------|------|----------------|---------|---------|
| 旧 API 使用 | `ARSCNView` / `SCNNode` 系が混在 | AR 処理全般 | `import SceneKit` の有無を確認 | RealityKit の対応 API に置き換え |
| デフォルト付き switch | `BugType` の新ケースがコンパイルエラーにならない | バグ種別分岐 | `grep -rn "default:" --include="*.swift"` | `default` を削除し全ケースを明示 |
| メインスレッド外 UI 更新 | ランタイムクラッシュ（スレッド違反警告） | SceneKit コールバック内 | Xcode Thread Sanitizer | `DispatchQueue.main.async` でラップ |
| 暗号化省略 | MCSession が平文通信 | MultipeerConnectivity 初期化 | `.encryptionPreference` の値確認 | `.required` に変更 |
| 強制アンラップ乱用 | EXC_BAD_ACCESS クラッシュ | オプショナル処理 | `grep -n "!"` | `guard let` / `if let` に変換 |
| preloadAssets 呼び忘れ | USDZ が毎回ロードされ FPS 低下 | 新エントリポイント追加時 | プロジェクターパスのコードパス確認 | `makeUIView` / `viewDidLoad` 両方で呼ぶ |
| ドキュメント未更新 | コードと仕様書が乖離 | 定数・API 変更時 | SPEC.md / PROMPT.md の diff 確認 | 同一 PR でドキュメントも更新 |
| try? でエラー握り潰し | デコード失敗がサイレントに無視される | Codable デコード全般 | `try?` の箇所を grep | `try catch` に変換 |
| [weak self] 漏れ | メモリリーク・循環参照 | クロージャ内 self 参照 | クロージャを目視 | `[weak self]` を追加 |
| @preconcurrency 乱用 | Swift 6 concurrency 警告を隠蔽 | import 文 | `@preconcurrency` を grep | 根本的な concurrency 修正を行う |

### 13-4. レビューフロー（推奨手順）

```
[1] PR の目的を把握
    ├── PR 説明文・コミットメッセージで Why / What / How を確認
    └── 落とし穴: Copilot が生成した説明文はコードと乖離することがある
              → 実際のコード diff と照合して確認する

[2] ドキュメント更新の確認
    ├── SPEC.md / PROMPT.md が同じ PR で更新されているか確認
    └── 落とし穴: ドキュメント更新を別 PR に分けると乖離が起きやすい
              → 更新がない場合は修正依頼を出す前にまず確認する

[3] 静的解析
    ├── Xcode Build（警告ゼロが目標）
    ├── Swift Compiler の strict concurrency 警告確認
    └── 落とし穴: Warning を `@preconcurrency` で握り潰していないか確認

[4] スレッド安全性レビュー
    ├── NSLock 保護範囲を目視確認（mapLock / cacheLock）
    ├── Thread Sanitizer を有効にしてシミュレータで動作確認
    └── 落とし穴: SceneKit / RealityKit コールバック内の self 参照

[5] セキュリティレビュー
    ├── MCSession.encryptionPreference 確認（.required 必須）
    ├── 受信データバリデーション確認
    └── 落とし穴: Codable デコードの try? によるエラー無視

[6] 機能テスト（実機 / シミュレータ）
    ├── スタンドアロンモードで AR スポーン・捕獲の動作確認
    ├── プロジェクターモードで接続・スコア同期の動作確認
    └── 落とし穴: シミュレータでは AR 機能が再現できない
              → AR に関わる変更は必ず実機テスト

[7] 承認 / 修正依頼
    └── 上記 §13-2 のチェックリストをレビューコメントに添付して完了を明示
```

### 13-5. レビュアー向けナレッジ Tips

- **AI 生成コードの「自信」に騙されない**: Copilot はエラーがなく自然に見えるコードを生成するが、ロジックが微妙にずれていることがある。特にゲーム状態遷移（`.waiting` → `.calibrating` → `.ready` → `.playing` → `.finished`）のような細かい順序に注意。

- **grep でパターンを機械的に確認**: `git diff` で変更箇所を確認した後、以下のコマンドで警戒パターンを機械的に検出する:
  ```bash
  grep -rn "default:" --include="*.swift"        # BugType switch の default
  grep -rn "!" --include="*.swift" | grep -v "//" # 強制アンラップ（コメント除外）
  grep -rn "try?" --include="*.swift"             # エラー握り潰し
  grep -rn "\.optional\|\.none" --include="*.swift" | grep -i "encryption" # 暗号化省略
  grep -rn "import SceneKit" --include="*.swift"  # SceneKit 混在
  ```

- **フレームワーク混在に注意**: `import SceneKit` と `import RealityKit` が同一ファイルに混在しているケースは要注意（移行途中のコードが混入している可能性）。

- **テスト不足は Copilot の弱点**: Copilot はテストコードを省略しがちなため、重要なロジック変更にはテストが追加されているか確認する。

- **プロンプトの痕跡を見る**: Copilot が生成したコードには「プロンプトで意図しなかった処理」が紛れることがある。差分全体を一行ずつ読み、「なぜこの行が必要か」を説明できるかセルフチェックする。

- **SPEC.md を常に手元に開く**: レビュー中は SPEC.md を開いた状態で、定数・遷移・通信フローを随時照合する。特に `minSpawnDistance` / `maxSpawnDistance` / `referenceDistance` などのスポーン定数は変更されやすい。

---

最終更新: 2025年4月  
対象環境: Xcode 26 / iOS 26 / Swift 6.0 / GitHub Copilot
