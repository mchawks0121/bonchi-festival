# 君は、バグハンター 🦟 — bonchi-festival

バグに侵食されたワールドをスリングショットで救う、90秒のデバッグゲームです。  
**スタンドアロンモード**（AR のみ、1台で完結）と  
**プロジェクターモード**（プロジェクターに映した大画面と iOS 端末を同期）の  
2種類のプレイスタイルに対応しています。

---

## ゲームの概要

| 要素 | 内容 |
|------|------|
| 制限時間 | 90 秒 |
| 操作方法 | スリングショットをドラッグして網を発射 |
| ゴール | 制限時間内にできるだけ多くのバグを捕獲してポイントを稼ぐ |

### バグ一覧

| 絵文字 | 種類 | ポイント | 速さ | 特徴 |
|--------|------|----------|------|------|
| 🐞 | Null Bug | 1 pt | 速い | 最も数が多い |
| 🦠 | Virus Bug | 3 pt | 普通 | 中程度の頻度で出現 |
| 👾 | Glitch | 5 pt | 遅い | 最もレアで強敵 |

---

## スタンドアロンモード（📱 AR のみ）

### 概要

iPhone / iPad 1 台だけで完結するモードです。  
ARKit がリアルタイムに周囲の空間を認識し、カメラ映像の中にバグが 3D で出現します。  
端末を向けてバグを照準に捉え、スリングショットで網を投げて捕獲します。

### 必要なもの

- ARKit 対応の iPhone または iPad（1 台）
- カメラへのアクセス許可

### 起動方法

1. アプリを起動する
2. **「スタンドアロン」** カードを選択（デフォルト）
3. **「デバッグ開始」** をタップ
4. カメラが起動し、空間にバグが出現する

### プレイ方法

1. **照準を合わせる** — 端末を動かしてバグを画面中央の十字に近づける
   - バグに近づくと画面右側にロックオンリングが表示される
2. **スリングショットを引く** — 画面下部のフォークをドラッグして後ろに引く  
   - 引いた方向と逆方向に網が飛ぶ（上に引けば上に飛ぶ）
   - パワーインジケーターが赤くなるほど強く飛ぶ
3. **指を離す** — 網が発射され、バグに当たると捕獲される  
   - `+pt` のポップアップとアニメーションが再生される
4. 90 秒後に自動終了、最終スコアが表示される

---

## プロジェクターモード（📡 iOS ↔ プロジェクター同期）

### 概要

**プロジェクターに映した大画面**（2D の虫狩りワールド）と  
**iOS コントローラー**（AR スリングショット）を Wi-Fi / Bluetooth 経由で同期するモードです。

- **プロジェクター側デバイス**（Mac / iPad / 別の iPhone など）がワールドを表示します
- **iOS コントローラー側**がスリングショットで操作します
- MultipeerConnectivity（Bonjour ベース）で自動的に相互接続します

### 必要なもの

- iOS コントローラー用の iPhone または iPad（1 台）
- プロジェクター表示用の別デバイス（Mac / iPad / iPhone などアプリが動くもの）
- 両デバイスが **同じ Wi-Fi ネットワーク** または **Bluetooth 有効** の状態

### セットアップ手順

#### ① プロジェクター側デバイスで表示モードを起動

1. アプリを起動する
2. 待機画面の一番下の **「📺 プロジェクター表示モードで起動」** をタップ
3. **プロジェクターワールド**（大画面用のシーン）が起動し  
   「iOSコントローラーの接続を待っています…」が表示される
4. このデバイスをプロジェクターや外部モニターにミラーリング / AirPlay で接続する

#### ② iOS コントローラーでプロジェクターモードを選択

1. コントローラー用の iPhone / iPad でアプリを起動する
2. **「プロジェクター」** カードを選択する
3. ステータスピルが **「プロジェクターに接続済み」**（緑●）になるまで待つ  
   ※ 同一ネットワーク上にいれば数秒以内に自動接続されます
4. **「デバッグ開始」** をタップ

#### ③ ゲームプレイ

- コントローラー側は AR カメラで 3D バグを狙い、スリングショットで発射
- プロジェクター側の大画面にも同じ発射がリアルタイムで反映され、2D バグに命中する
- スコア・タイマーは両画面で同期される
- 90 秒後にプロジェクター側に「デバッグ完了！」オーバーレイが表示され、  
   4 秒後に自動的に待機画面に戻る

### 通信仕様

| 方向 | メッセージ | 内容 |
|------|-----------|------|
| iOS → Projector | `startGame` | ゲーム開始を通知 |
| iOS → Projector | `resetGame` | 待機画面に戻す |
| iOS → Projector | `launch(angle, power)` | スリングショット発射パラメータ |
| Projector → iOS | `gameState(score, timeRemaining)` | スコア・残時間を同期 |

---

## アーキテクチャ概要

```
bonchi-festival/
├── AppDelegate.swift               iOS コントローラー起動エントリーポイント
├── ContentView.swift               待機 / プレイ / 終了 画面ルーティング（SwiftUI）
│
├── Controller/                     iOS コントローラー側
│   ├── GameManager.swift           ゲーム状態管理・スコア・MultipeerSession 橋渡し
│   ├── ARGameView.swift            ARSCNView + SKView 2 層構成の AR ビュー
│   ├── ARBugScene.swift            透明 SpriteKit シーン（照準・ロックオン・捕獲）
│   ├── Bug3DNode.swift             SceneKit 3D バグノード（PBR マテリアル）
│   ├── SlingshotView.swift         スリングショット操作 UI
│   └── MultipeerSession.swift      Multipeer Connectivity ラッパー（コントローラー側）
│
├── World/                          プロジェクター表示側
│   ├── WorldViewController.swift   UIViewController ルート（プロジェクター表示）
│   ├── WorldViewControllerRepresentable.swift  SwiftUI ラッパー
│   ├── ProjectorGameManager.swift  Multipeer Connectivity ラッパー（プロジェクター側）
│   ├── BugHunterScene.swift        2D SpriteKit ゲームシーン（プロジェクター用）
│   ├── BugSpawner.swift            BugNode をシーンに追加するスポーナー
│   ├── NetProjectile.swift         飛ぶ網ノード（物理衝突あり）
│   └── WaitingScene.swift          待機画面シーン
│
└── Shared/
    └── GameProtocol.swift          両デバイス間の共有メッセージ型・BugType 定義
```

---

## 開発者向けメモ

- `MultipeerSession.serviceType` と `ProjectorGameManager.serviceType` は  
  同じ文字列 `"bughunter-game"` に揃えること
- スタンドアロンモードでは `MultipeerSession` は起動しない  
  （`selectMode(.standalone)` 呼び出し時に停止される）
- プロジェクター側はスコアを自ら管理し (`BugHunterScene`)、  
  iOS 側は AR シーン (`ARBugScene`) が独立してスコアを管理する  
  （それぞれのローカル物理演算で完結）
