# ぼんち祭り バグハンター — PM ドキュメント生成プロンプト

> **用途**: このファイルを GitHub Copilot（チャット／エージェントモード）に渡すことで、  
> キックオフ資料兼プロジェクト管理ドキュメント（`PROJECT_PLAN.md` 相当）を再現・拡張生成できます。  
> **バージョン**: Xcode 26 / iOS 26 / Swift 6.0  
> **最終更新**: 2025年4月

---

## このファイルの使い方

1. GitHub Copilot のチャット欄でこのファイルを「Add Files」でコンテキストに追加する。
2. 以下の「▶ AI へのプロンプト」ブロックをそのままコピーして投げる。
3. 出力された Markdown を `PROJECT_PLAN.md` に貼り付けて調整する。
4. **キックオフ当日**はこのドキュメントをスクリーンに映して進行する。

---

## ▶ AI へのプロンプト（ここからコピーして使う）

```
あなたはプロジェクトマネジメントのプロフェッショナルであり、
iOS / Swift 開発にも精通したテクニカル PM です。

以下の「プロジェクト概要」「技術スタック」「チーム構成」「スケジュール」を読み込み、
チームキックオフ資料として使えるほど網羅的・詳細な「プロジェクト計画書」を
Markdown で生成してください。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## プロジェクト概要
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

プロジェクト名   : ぼんち祭り バグハンター
イベント本番日   : 8月1日（ぼんち祭り会場）
開発期間         : 約14週間（4月下旬〜8月1日）
目的             : 祭り会場でスマートフォンを使い、AR 空間に出現するバグを
                   スリングショットで捕獲する参加型体験ゲームを提供する。
                   大型スクリーン（プロジェクター）にリアルタイムスコアを表示し、
                   最大3人が同時にプレイできるマルチプレイヤー形式。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## 技術スタック（Xcode 26 / iOS 26 固定）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

| カテゴリ | 技術 | 用途・備考 |
|---------|------|-----------|
| 開発環境 | Xcode 26.x | Deployment Target: iOS 26.0 |
| 言語 | Swift 6.0 | SWIFT_STRICT_CONCURRENCY = complete |
| AR | ARKit 6 | ARWorldTrackingConfiguration + sceneReconstruction |
| 3D描画 | RealityKit 3 | Entity/AnchorEntity。SceneKit は使用禁止 |
| 2D描画 | SpriteKit | プロジェクター大画面・透過HUDオーバーレイ |
| UI | SwiftUI 6 | Liquid Glass（.glassBackground() / .glassEffect()）|
| 通信 | MultipeerConnectivity | iOS↔プロジェクター P2P。encryptionPreference: .required |
| 並行処理 | Swift Concurrency | actor / @MainActor / Sendable。nonisolated(unsafe) 禁止 |
| テスト | Swift Testing | XCTest から移行済み |
| 3Dアセット | USDZ | toy_biplane / gramophone / toy_drummer（Apple AR Quick Look）|
| デバイス | iPhone（iOS 26+） | コントローラー／スタンドアロン端末（最大3台）|
| デバイス | iPad / Mac | プロジェクター接続サーバー端末 |

Xcode 26 / iOS 26 固有の制約:
- UIKit AppDelegate ベース（SwiftUI App プロトコルは不使用）
- RealityView（iOS 18+）は不使用。ARView + AnchorEntity パターン継続
- Liquid Glass は #available(iOS 26, *) ガード不要（Deployment Target が iOS 26.0）

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## ディレクトリ構造
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

bonchi-festival/
├── AppDelegate.swift
├── ContentView.swift
├── Controller/          ← チームA・C が担当（AR・UI・サウンド）
│   ├── GameManager.swift
│   ├── ARGameView.swift
│   ├── ARBugScene.swift
│   ├── Bug3DNode.swift
│   ├── SlingshotNode.swift
│   ├── SlingshotView.swift
│   ├── Net3DNode.swift
│   ├── MultipeerSession.swift
│   └── SoundManager.swift
├── Shared/              ← チームC が担当（全チームのブロッカー）
│   └── GameProtocol.swift
└── World/               ← チームB が担当（プロジェクター側）
    ├── ProjectorGameManager.swift
    ├── BugHunterScene.swift
    ├── NetProjectile.swift
    ├── WorldViewController.swift
    └── ProjectorBug3DCoordinator.swift

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## チーム構成
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

チームA（ARコア）
  人数: 1〜2名
  担当: Controller/ の AR・3D・スリングショット
  成果物:
    AppDelegate.swift / GameManager.swift / ARGameView.swift
    Bug3DNode.swift / ARBugScene.swift
    SlingshotNode.swift / Net3DNode.swift / SlingshotView.swift

チームB（プロジェクター）
  人数: 1〜2名
  担当: World/ の大画面表示・サーバー役
  成果物:
    ProjectorGameManager.swift / BugHunterScene.swift
    NetProjectile.swift / WorldViewController.swift
    ProjectorBug3DCoordinator.swift

チームC（基盤・UX）
  人数: 1〜2名
  担当: Shared/ + 通信・SwiftUI・サウンド
  成果物:
    GameProtocol.swift（★全チームのブロッカー）
    MultipeerSession.swift / ContentView.swift / SoundManager.swift

横断QA
  人数: 1名（全チームから兼任可）
  担当: M3〜M4 の統合テスト・Swift Testing スイート・不具合管理

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## マイルストーン（本番：8月1日）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

M0 環境整備           5月2日   全員: Xcode 26 + iOS 26 ビルド確認・Swift 6 警告棚卸し
M1 プロトタイプ完成   5月16日  スリングショット基本動作・プロジェクター表示・Multipeer疎通
M2 全機能実装完了     6月20日  3種バグ・USDZ・キャリブレーション・Liquid Glass UI・SE
M3 統合テスト・調整   7月11日  実機3台通しテスト・スコア集計・当たり判定チューニング
M4 リリース候補（RC） 7月25日  全バグFix・M4以降機能追加禁止・ドキュメント更新完了
🎉本番（ぼんち祭り）  8月1日

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## タスク一覧（P-00〜P-17）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

P-00 Xcode 26 新規プロジェクト作成              全チーム  前提:なし
P-01 Shared/GameProtocol.swift                  チームC   前提:P-00 ★ブロッカー
P-02 AppDelegate.swift                          チームA   前提:P-00
P-03 Controller/GameManager.swift               チームA   前提:P-01,P-02
P-04 Controller/MultipeerSession.swift          チームC   前提:P-01
P-05 World/ProjectorGameManager.swift           チームB   前提:P-01
P-06 Controller/Bug3DNode.swift                 チームA   前提:P-01
P-07 Controller/ARBugScene.swift                チームA   前提:P-01
P-08 Controller/ARGameView.swift                チームA   前提:P-03,P-06,P-07
P-09 Controller/SlingshotNode.swift             チームA   前提:P-01
P-10 Controller/Net3DNode.swift                 チームA   前提:P-01
P-11 Controller/SlingshotView.swift             チームA   前提:P-09,P-10
P-12 Controller/SoundManager.swift              チームC   前提:P-03
P-13 ContentView.swift（全画面SwiftUI）         チームC   前提:P-03,P-04,P-12
P-14 World/BugHunterScene.swift + NetProjectile チームB   前提:P-05
P-15 World/WorldViewController.swift            チームB   前提:P-05,P-06,P-14
P-16 Swift Testing スイート構築                 横断QA    前提:P-01〜P-15
P-17 パフォーマンス最適化・メモリリーク修正      全チーム  前提:P-16

並行作業: Phase3（P-04,P-05）と Phase4（P-06〜P-11）はP-01完了後に同時着手可

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## AI 駆動開発ルール
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

プロンプト必須3点セット:
  Why（目的）/ What（機能概要）/ How（実装方針・禁止事項）

毎回のプロンプトに含める制約:
  - 3Dは RealityKit のみ。ARSCNView・SceneKit 禁止
  - nonisolated(unsafe) 使用禁止
  - BugType の switch は exhaustive（default: 禁止）
  - 1PR = 1ファイル単位
  - コメントに実装意図・セキュリティ考慮・注意点を必ず含める

マージ前チェックリスト:
  □ BugType switch が exhaustive か
  □ nonisolated(unsafe) がないか
  □ @MainActor / actor / Sendable が適切か
  □ MCSession.encryptionPreference が .required か
  □ 強制アンラップ（!）がないか
  □ SPEC.md / PROMPT.md を同じPRで更新したか
  □ Swift 6 strict concurrency ビルドエラーがゼロか

ドキュメント三点セット（コード変更時は同PRで更新必須）:
  SPEC.md        → ゲーム仕様・ルール・アーキテクチャ
  PROMPT.md      → 各ファイルの実装説明
  PROMPT_26.md   → チーム別 Copilot プロンプト集

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## PRルール
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1PR = 1機能  / self-review 禁止 / M4以降機能追加禁止
ブランチ: feat/<タスクID>-<ファイル名>  例: feat/p-01-game-protocol
コミット: <タスクID>: <何をしたか>       例: P-01: Add GameProtocol.swift

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## 生成してほしいドキュメントの構成（必須セクション）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

以下の見出し順で、各セクションを詳細に出力してください。

1. プロジェクト概要とゴール
   - プロジェクト名・背景・目的・成功基準（KPI）
   - 非目標（スコープ外）を明記する

2. 使用技術スタック
   - フレームワーク・言語・ツール・デバイス一覧（表形式）
   - Xcode 26 / iOS 26 固有の対応事項（表形式）

3. AI を使った開発について
   - 活用方法・進め方のTips（iOS 26 / Swift 6 対応版）
   - レビュー方針

4. 役割分け
   - 役割一覧と担当内容（表形式）
   - 兼任ルール

5. チーム分け（案）
   - チームA/B/C/QA の担当領域（表形式）

6. マイルストーンとスケジュール
   - M0〜M4 + 本番（表形式）
   - チーム別タスク列を含むガントチャート相当の表
   - 各マイルストーンの完了基準（DoD: Definition of Done）
   - 備考・注意事項

7. Swift 6 移行チェックリスト
   - 優先度別ファイルと対応内容（表形式）

8. Liquid Glass UI 対応方針
   - 対象画面と対応内容（表形式）
   - テーマ・カラートークンの扱い

9. チーム別詳細（目的・人数・成果物・タスク）
   - チームA / B / C / QA それぞれについて
     - 目的・人数・担当ディレクトリ
     - 成果物ファイル一覧（表形式、ファイル名＋一行概要）
     - マイルストーン別タスク（表形式）

10. タスク細分化（P-00〜P-17）
    - Phase 0〜8 のフェーズ別表（タスクID / ファイル / 担当 / 前提）
    - 並行作業ルールの明示
    - ブロッカーの強調

11. AI 駆動開発 詳細指針
    - プロンプト必須3点セット（Why / What / How）の解説
    - 毎回記載すべき制約一覧（表形式）
    - AI コード生成後の必須チェック項目（チェックボックス形式）
    - ドキュメント三点セット管理ルール（コードブロック形式）

12. PR ルール（全チーム共通）
    - ルール一覧（表形式）
    - ブランチ命名規則・コミットメッセージ規則

13. リスク管理
    - 特定済みリスク一覧（リスク / 確率 / 影響度 / 対策）（表形式）
    - リスク発生時のエスカレーション先

14. コミュニケーション計画
    - 定例ミーティング（頻度・参加者・目的）
    - 非同期コミュニケーションのルール（GitHub Issues / PR / Slack 等）
    - 進捗報告の書式

15. キックオフアジェンダ
    - 当日の進行プログラム（時間・内容・担当）
    - 参加者への事前準備依頼事項

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## 出力フォーマット要件
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- 言語: 日本語
- フォーマット: GitHub Flavored Markdown（GFM）
- 表はパイプ記法で統一する
- セクション番号は ## 1. のように付ける
- コードやファイル名はバッククォートで囲む
- 重要事項は **太字** または > ブロッククォートで強調する
- チェックリストは - [ ] 形式で書く
- ドキュメント末尾に「最終更新: <年月>」と「対象環境: Xcode 26 / iOS 26 / Swift 6.0」を記載する
```

---

## 生成後の調整チェックリスト

プロンプトで生成したドキュメントを `PROJECT_PLAN.md` に反映する前に、  
以下を人間が確認・調整する。

- [ ] メンバー名・人数を実際のチーム構成に合わせて修正した
- [ ] マイルストーン日付が実際のスケジュールと一致している
- [ ] 新しく追加されたファイル名が成果物一覧に含まれている
- [ ] Swift 6 移行チェックリストに未対応ファイルを追加した
- [ ] リスク管理に実際のリスクを追記した
- [ ] コミュニケーション計画のツール名（Slack 等）を実際に使うものに修正した
- [ ] キックオフアジェンダの日時・場所を記載した
- [ ] `SPEC.md` / `PROMPT.md` と矛盾していないか確認した

---

## 補足：各セクションの生成クオリティを上げるコツ

### リスク管理を充実させるには

プロンプトの末尾に以下を追加する：

```
リスク管理セクションでは、iOS ARKit ゲームの実機テスト困難・
MultipeerConnectivity の距離制限・Xcode 26 ベータ版の不安定さ・
祭り会場の Wi-Fi 環境・USDZ アセット入手遅延 などを
特定済みリスクとして必ず含めてください。
```

### キックオフアジェンダを詳細にするには

プロンプトの末尾に以下を追加する：

```
キックオフアジェンダは90分構成で生成してください。
「プロジェクト概要説明（20分）」「技術スタック説明（15分）」
「チーム紹介・役割確認（15分）」「スケジュール確認（20分）」
「AI開発ルール説明（10分）」「質疑応答（10分）」の順で
各セッションの狙い・進行担当・必要資料を明記してください。
```

### 週次進捗レポートテンプレートを追加するには

プロンプトの末尾に以下を追加する：

```
ドキュメント末尾に、毎週の進捗報告に使う Markdown テンプレートを
「週次進捗レポート」セクションとして追加してください。
チーム別の完了タスク・残課題・ブロッカー・翌週の予定を記載できる形式にしてください。
```
