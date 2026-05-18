# ぼんち祭り バグハンター — 開発者キックオフ資料

> **本番日**: 2025年8月1日（ぼんち祭り当日）  
> **開発期間**: 2025年4月下旬〜7月25日（約14週間）  
> **対象環境**: Xcode 26 / iOS 26 / Swift 6.0  
> **作成日**: 2025年4月

---

## 1. プロジェクト概要

**ぼんち祭り バグハンター**は、ARKit × RealityKit × SpriteKit × MultipeerConnectivity を組み合わせた iOS ゲームです。  
iPhone のカメラ越しに 3D バグ（害虫）が出現し、スリングショットで網を飛ばして捕獲します。

### プレイモード

| モード | 説明 |
|--------|------|
| 📱 **スタンドアロン** | 1台の iPhone で完結する AR モード |
| 🎮 **プロジェクター／クライアント** | iPhone がコントローラーとして Multipeer 接続し、プロジェクター画面へ操作を送信 |
| 📺 **プロジェクター／サーバー** | 大画面表示デバイス。最大3台のクライアントから操作を受け付ける |

---

## 2. 技術スタック

| カテゴリ | 技術 | 用途 |
|---------|------|------|
| AR/3D | **ARKit 6** | AR 空間でのバグ配置・カメラトラッキング |
| AR/3D | **RealityKit 3** | 3Dモデル（`Bug3DNode`、`SlingshotNode`、`Net3DNode`）レンダリング |
| 2D UI | **SpriteKit** | 照準クロスヘア・捕獲エフェクト・大画面オーバーレイ |
| UI | **SwiftUI 6** | 全画面 UI（Liquid Glass エフェクト適用） |
| 通信 | **MultipeerConnectivity** | iOS デバイス ↔ プロジェクター間の P2P 通信 |
| 言語 | **Swift 6.0** | strict concurrency 有効（`SWIFT_STRICT_CONCURRENCY = complete`） |
| 並行処理 | Swift Concurrency (`actor`, `@MainActor`, `Sendable`) | スレッドセーフ処理 |
| テスト | Swift Testing | ユニットテスト・統合テスト |
| 3Dアセット | USDZ（Apple AR Quick Look） | バグの 3D モデル（`toy_biplane` / `gramophone` / `toy_drummer`） |

### 対応デバイス

| 役割 | デバイス |
|------|---------|
| コントローラー／スタンドアロン | iPhone（ARKit 対応、iOS 26+） |
| 大画面表示サーバー | iPad / Mac（プロジェクター接続） |

---

## 3. リポジトリ構成

```
bonchi-festival/
├── AppDelegate.swift          … UIKit エントリーポイント
├── ContentView.swift          … SwiftUI ルート画面切り替え
│
├── Controller/                … ★チームA・チームC 担当（iOS/AR 側）
│   ├── GameManager.swift      … ゲーム状態管理（@MainActor）
│   ├── MultipeerSession.swift … iOS 側 Multipeer ラッパー
│   ├── ARGameView.swift       … ARView + SKView 重ね合わせ
│   ├── Bug3DNode.swift        … RealityKit 3D バグエンティティ（USDZ / 手続きジオメトリ）
│   ├── ARBugScene.swift       … SpriteKit 透過照準 UI
│   ├── SlingshotNode.swift    … 3D スリングショット表示
│   ├── Net3DNode.swift        … 3D 飛翔網メッシュ
│   ├── SlingshotView.swift    … SwiftUI スリングショット UI
│   ├── SoundManager.swift     … 手続き型サウンドエフェクト
│   └── ForestEnvironment.swift … 3D 木エンティティ（背景装飾）
│
├── Shared/                    … ★チームC 担当（全チームのブロッカー）
│   └── GameProtocol.swift     … 共有型定義（BugType・メッセージプロトコル）
│
└── World/                     … ★チームB 担当（プロジェクター側）
    ├── WorldViewController.swift      … プロジェクター用 UIViewController
    ├── ProjectorGameManager.swift     … 最大3台 Multipeer 接続管理
    ├── BugHunterScene.swift           … 大画面 SKScene
    ├── NetProjectile.swift            … 大画面用飛翔網スプライト
    └── BugSpawner.swift               … 旧スポーナー（現在未使用）
```

---

## 4. チーム構成と担当範囲

| チーム | 役割 | 担当ディレクトリ |
|--------|------|----------------|
| **チームA：ARコア** | ARKit・RealityKit 層（バグスポーン・スリングショット・網飛翔） | `Controller/` |
| **チームB：プロジェクター** | SpriteKit 大画面側（`BugHunterScene`、`WorldViewController`） | `World/` |
| **チームC：基盤・UX** | 通信基盤・SwiftUI 全画面・SE・共通型定義 | `Shared/`、`Controller/`（通信・UI） |
| **横断QA** | 実機統合テスト・Swift Testing・不具合管理 | 全領域（M3〜M4） |

> 小規模チームでは兼任可（例：チームA がチームC の通信部分も担当）

---

## 5. マイルストーン

| # | 期限 | テーマ | 達成基準 |
|---|------|-------|---------|
| **M0** | 5月2日 | 環境整備 | Xcode 26 + iOS 26 実機ビルド成功。Swift 6 strict concurrency エラー棚卸し完了 |
| **M1** | 5月16日 | プロトタイプ | スリングショット基本動作・バグスポーン（1種類）・Multipeer 基本接続 が動く |
| **M2** | 6月20日 | 全機能実装 | 3種バグ・USDZ・3クライアント同時接続・Liquid Glass UI・SE 完成 |
| **M3** | 7月11日 | 統合テスト | 実機（iPhone×3台 + プロジェクター）での通しテスト完了。スコア・タイマー正常動作確認 |
| **M4** | 7月25日 | RC | 全バグ Fix・パフォーマンス最適化・ドキュメント更新完了 |
| **🎉 本番** | **8月1日** | ぼんち祭り | — |

> **M4（7/25）以降は機能追加禁止。バグ修正のみ。**

---

## 6. 開発フロー（実装順序）

依存関係があるため、以下の順番を守ること。

```
Phase 0 — 環境構築（M0）
  └─ P-00: Xcode 26 新規プロジェクト作成・iOS 26 ターゲット設定

Phase 1 — 共有型定義（M0）★全チームのブロッカー
  └─ P-01: Shared/GameProtocol.swift（チームC 最優先着手）

Phase 2 — アプリ基盤（M1）
  ├─ P-02: AppDelegate.swift（チームA）
  └─ P-03: Controller/GameManager.swift（チームA）

Phase 3 & 4 — 通信層 + ARコア（M1〜M2）※Phase 1 完了後に並行着手可
  ├─ P-04: Controller/MultipeerSession.swift（チームC）
  ├─ P-05: World/ProjectorGameManager.swift（チームB）
  ├─ P-06: Controller/Bug3DNode.swift（チームA）
  ├─ P-07: Controller/ARBugScene.swift（チームA）
  ├─ P-08: Controller/ARGameView.swift（チームA）
  ├─ P-09: Controller/SlingshotNode.swift（チームA）
  ├─ P-10: Controller/Net3DNode.swift（チームA）
  └─ P-11: Controller/SlingshotView.swift（チームA）

Phase 5〜7 — サウンド・UI・プロジェクター（M2）
  ├─ P-12: Controller/SoundManager.swift（チームC）
  ├─ P-13: ContentView.swift / 全 SwiftUI 画面（チームC）
  ├─ P-14: World/BugHunterScene.swift & NetProjectile.swift（チームB）
  └─ P-15: World/WorldViewController.swift（チームB）

Phase 8 — 統合・QA（M3〜M4）
  ├─ P-16: Swift Testing スイート構築（横断QA）
  └─ P-17: パフォーマンス最適化・メモリリーク修正（全チーム）
```

---

## 7. PR ルール

| ルール | 内容 |
|--------|------|
| **1PR = 1機能** | 単一責務。差分を小さく保ちレビューしやすくする |
| **Self-review 禁止** | AI 生成コードも含め、必ず別のメンバーがレビューしてからマージする |
| **ドキュメント同時更新** | コードに変更を加えた場合は `SPEC.md` と `PROMPT.md` も同じ PR で更新する |
| **Swift 6 警告ゼロ** | `-strict-concurrency=complete` ビルドエラー・警告は放置しない |

---

## 8. コーディング規約

### Swift 6 Concurrency

| ルール | 理由 |
|--------|------|
| RealityKit 操作は `@MainActor` で隔離する | RealityKit のエンティティはメインスレッド専用 |
| SpriteKit 操作は main thread で呼ぶ | SKScene の描画はメインスレッドのみ |
| `nonisolated(unsafe)` は使用禁止 | 技術的負債になる。`actor` か `@MainActor` で正しく設計する |
| `BugType` の `switch` は網羅的に書く（`default:` 禁止） | 新しいケース追加時にコンパイルエラーで漏れを検知する |

### Liquid Glass UI（iOS 26）

```swift
// iOS 26 以降でのみ動作するため #available ガードを必ず付ける
if #available(iOS 26, *) {
    view.glassBackground()
}
```

### AI（GitHub Copilot）活用ルール

プロンプトには必ず以下3点を含める。

| 項目 | 例 |
|------|----|
| **Why（目的）** | 「観客がスリングショット操作を直感的に体験できるようにするため」 |
| **What（機能概要）** | 対象ファイル名・クラス名・実装すべきプロパティ・メソッドを箇条書き |
| **How（実装方針）** | 「3D は RealityKit のみ。`ARSCNView`・SceneKit は使わない」など制約を明記 |

> 詳細なプロンプトテンプレートは `PROMPT_26.md` を参照。

---

## 9. ゲーム仕様早見表

### バグ一覧

| バグ | 名前 | ポイント | 出現率 | USDZ |
|------|------|---------|--------|------|
| 🐞 | Null（butterfly） | 1 pt | 約60% | ―（手続きジオメトリ） |
| 🦠 | Virus（beetle） | 3 pt | 約40% | `gramophone.usdz` |
| 🤖 | Glitch（stag） | 5 pt | スポーン対象外 | `toy_drummer.usdz` |

### ゲームルール

| 項目 | 値 |
|------|---|
| 制限時間 | **90 秒** |
| スポーン間隔 | 開始時 3.5 秒 → 75 秒時点で最短 1.5 秒 |
| 同時出現上限 | **最大 5 匹** |
| 最大同時接続 | **3 台** |
| スコア管理 | **iOS 側のみ**（プロジェクターはスコアを計算しない） |
| タイマー管理 | **iOS 側のみ** |

### 通信メッセージ一覧

| メッセージ | 方向 | 説明 |
|-----------|------|------|
| `launch` | iOS → Projector | スリングショット発射（視覚同期） |
| `startGame` | iOS → Projector | ゲーム開始 |
| `resetGame` | iOS → Projector | バグをクリア |
| `bugSpawned` | iOS → Projector | バグ出現通知 |
| `bugRemoved` | iOS → Projector | バグ捕獲通知 |

---

## 10. 環境セットアップ手順（M0 チェックリスト）

全員が M1 着手前に完了させること。

- [ ] Xcode 26 をインストール（[developer.apple.com/xcode](https://developer.apple.com/xcode/)）
- [ ] iOS 26 搭載 iPhone を Xcode に接続・Developer Mode を有効化
- [ ] リポジトリをクローンし、`bonchi-festival.xcodeproj` をビルド（警告・エラーを記録）
- [ ] `SWIFT_STRICT_CONCURRENCY = complete` のビルドエラーを各自棚卸しして Issue 起票
- [ ] USDZ ファイル 3 点を Apple AR Quick Look ギャラリーから取得し Xcode プロジェクトに追加
  - `toy_biplane.usdz`（Null バグ用）
  - `gramophone.usdz`（Virus バグ用）
  - `toy_drummer.usdz`（Glitch バグ用）
- [ ] Multipeer 接続の動作確認（iPhone 2台で同一 LAN に接続、相互検出を確認）

---

## 11. 参照ドキュメント

| ドキュメント | 内容 |
|------------|------|
| [`SPEC.md`](./SPEC.md) | ゲーム仕様・ルール・アーキテクチャの詳細 |
| [`PROJECT_PLAN.md`](./PROJECT_PLAN.md) | チーム構成・マイルストーン・タスク細分化・AI 活用指針 |
| [`PROMPT.md`](./PROMPT.md) | 各ファイルの詳細実装説明（AI へのコンテキスト用） |
| [`PROMPT_26.md`](./PROMPT_26.md) | Xcode 26 / iOS 26 向け AI プロンプトテンプレート集 |
| [`COPILOT_KNOWLEDGE.md`](./COPILOT_KNOWLEDGE.md) | GitHub Copilot 向けコーディング規約・プロジェクト知識 |

---

> 質問・不明点はチームリードまたは GitHub Issues へ。  
> **本番は8月1日！全員で最高の体験を作りましょう 🎉**
