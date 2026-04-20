# Copilot コーディング規約

## ドキュメント更新ルール

コードに変更を加えた際は、**必ず関連するドキュメントも同時に更新してください**。

- `SPEC.md` — ゲーム仕様・ルール・アーキテクチャの変更を反映する。
- `PROMPT.md` — AI 継続開発プロンプト（各ファイルの詳細な実装説明）を更新する。

変更の規模に関わらず、コードの振る舞い・定数・API・アーキテクチャに影響する修正はドキュメントに反映してください。

---

## プロジェクト概要

**ぼんち祭り バグハンター** — ARKit × SpriteKit × SceneKit × MultipeerConnectivity を組み合わせた iOS ゲーム。

- `Controller/` — iOS 側のゲームロジック（AR、スリングショット、サウンド）
- `World/` — プロジェクター側（大画面表示サーバー）
- `Shared/` — iOS・プロジェクター共通の型定義（`BugType`、メッセージプロトコル等）

---

## AR バグ 3D モデル（Bug3DNode）

### USDZ モデル（Apple AR Quick Look ギャラリー）

`Bug3DNode` は、Apple の AR Quick Look ギャラリー（<https://developer.apple.com/jp/augmented-reality/quick-look/>）から取得した USDZ ファイルを優先して使用します。USDZ が見つからない場合は手続き的 PBR ジオメトリにフォールバックします。

| BugType | USDZ ファイル | 理由 |
|---------|-------------|------|
| butterfly (Null) | `toy_biplane.usdz` | 飛行する玩具。速い Null バグを表現 |
| beetle (Virus) | `gramophone.usdz` | ドーム型シルエット。Virus バグを表現 |
| stag (Glitch) | `toy_drummer.usdz` | アニメ付き複雑キャラクター。Glitch バグを表現 |

**セットアップ**: 上記 3 ファイルを Apple AR Quick Look ギャラリーからダウンロードし、Xcode プロジェクトに追加してください。ファイルがない場合はゲームは手続きジオメトリで動作します。

**注意**: `Bug3DNode.preloadAssets()` は **iOS AR パス**（`ARGameView.makeUIView`）と**プロジェクターパス**（`WorldViewController.viewDidLoad`）の両方から呼ばれます。新しいエントリポイントを追加する際は両パスで呼び出してください。

### 新しいモデルを追加する場合

1. USDZ ファイルを Xcode プロジェクトに追加する。
2. `Bug3DNode.preloadAssets()` の `mapping` 配列にエントリを追加する。
3. `Bug3DNode.usdzScale(for:)` の `switch` に新しい `BugType` のスケールを追加する（網羅的な `switch` なのでコンパイルエラーで漏れを検知できる）。
4. `SPEC.md` と `PROMPT.md` のモデルマッピング表を更新する。

---

## AR スポーン設定（ARGameView.Coordinator）

| 定数 | 値 | 説明 |
|------|---|------|
| `minSpawnDistance` | 0.5 m | カメラからの最小スポーン距離 |
| `maxSpawnDistance` | 1.4 m | カメラからの最大スポーン距離 |
| `referenceDistance` | 3.0 m | スケール計算の基準距離 (`scale = referenceDistance / actualDistance`) |
| `minBugScale` | 0.3 | スケール下限 |
| `maxBugScale` | 5.0 | スケール上限 |

スポーン距離や参照距離を変更した場合は、`SPEC.md` の「AR レイヤー詳細」セクションと `PROMPT.md` の `ARGameView.swift` 説明を更新してください。

---

## コーディング規約

- Swift の命名規則（camelCase）に従う。
- `BugType` を `switch` する場合は **網羅的な switch** を使用し、`default` を避ける（新しいケース追加時のコンパイルエラー検知のため）。
- SceneKit レンダースレッドから UIKit に直接アクセスしない（`cachedViewHeight` パターンを踏襲する）。
- 新しい定数は `private static let` で Coordinator または Bug3DNode に閉じ込め、マジックナンバーを避ける。
- スレッドセーフなキャッシュアクセスには `NSLock` を使用する（既存の `cacheLock` パターンを踏襲）。

## 必須ルール  
1. 仕様ドキュメントの作成  
コードを生成する前に、必ず仕様ドキュメントを出力してください。  
以下を含めること  
目的（Why）  
機能概要（What）  
実装方針（How）  
仕様が曖昧な場合は、コードを書かずに質問してください。  

2. コード生成ルール  
コードには必ず以下のコメントを含めてください  
実装意図（なぜこの方法を選んだか）  
セキュリティ上の考慮点  
注意点や制約  
コメントが不足している場合は不完全な回答とみなします。  

3. PR単位を意識した出力  
出力は「1つのPR単位」で構成してください。  
以下を満たすこと  
単一責務（1機能のみ）  
不要な変更を含めない  
小さくレビュー可能な単位  
