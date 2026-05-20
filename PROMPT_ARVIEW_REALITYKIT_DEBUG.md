# ARView / RealityKit — nonAR モード デバッグプロンプト

> **対象環境**: Swift 5 / Xcode 26 / RealityKit / ARKit / iOS 18 以降  
> **用途**: ARView を使ったプロジェクトで「非 AR モード（`cameraMode: .nonAR`）では USDZ モデルが表示されない」問題を解決するための AI コンテキスト・プロンプトです。

---

## 問題の概要

`ARView(frame:cameraMode:automaticallyConfigureSession:)` の `cameraMode: .nonAR` を使ったビュー（プロジェクターサーバー表示など）において、USDZ モデルが以下のいずれかの状態になる。

- 完全に不可視（何も描画されない）
- 真っ黒に見える（形はあるが照明が当たっていない）
- 手続きジオメトリ（フォールバック形状）が代わりに描画される

同じ USDZ ファイルを同じクラスで読み込んでいるにも関わらず、AR モード（`cameraMode: .ar`）では正常に表示される。

---

## 原因①【最頻出】Entity.loadAsync のレースコンディション

### 現象

`Entity.loadAsync(named:)` は非同期で実行される。  
AR モードでは `arView.session.run(config)` が ARKit セッション初期化のために 2〜4 秒かかり、その間にアセットロードが完了する。  
非 AR モードにはこの自然な待機がなく、**プリロード完了前にスポーン処理が走る**。

結果として `entityCache[type]` が `nil` のまま `Entity` 生成が呼ばれ、
フォールバックの手続きジオメトリが使われるか、何も描画されない。

### 確認方法

```swift
// spawnBug() の先頭に追加
print("[DEBUG] cache for \(type): \(entityCache[type.rawValue] == nil ? "nil ← ロード未完了" : "OK")")
```

キャッシュが `nil` ならこれが原因。

### 対策

```swift
// ❌ 悪い例: ロード完了を待たずにスポーン開始
Bug3DNode.preloadAssets()
startGame()

// ✅ 良い例: 完了フラグをポーリングしてから開始
Bug3DNode.preloadAssets()
waitForPreloadThenStart()

private func waitForPreloadThenStart() {
    guard Bug3DNode.isPreloadComplete else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitForPreloadThenStart()
        }
        return
    }
    startGame()
}
```

または `Entity.load(named:)` の**同期版**を使ってプリロード時に確実にキャッシュを埋める。

---

## 原因②【PBR マテリアルが真っ暗】IBL（画像ベースライティング）の欠如

### 現象

AR モードでは `config.environmentTexturing = .automatic` により、
カメラ映像から IBL（Image Based Lighting）が自動生成され PBR マテリアルに適用される。

非 AR モードでは IBL が自動生成されないため、
**金属光沢・反射系マテリアルを持つ USDZ が真っ黒になる**。

> **⚠️ 白背景にしてもモデルが一切見えない場合は原因②ではありません。**  
> 原因②の症状は「形はあるが真っ暗/真っ黒」です。  
> 「完全に不可視（ポリゴン自体が描画されない）」の場合は **原因⑤・⑥** を確認してください。

### 対策（いずれか一つ以上を実施）

```swift
// 方法 A: 背景色を設定（最も手軽。環境光として機能する）
arView.environment.background = .color(.white)

// 方法 B: ImageBasedLightComponent を追加（推奨）
// ※ .reality または .skybox ファイルが必要
if let resource = try? EnvironmentResource.load(named: "studio") {
    let iblEntity = Entity()
    iblEntity.components[ImageBasedLightComponent.self] =
        ImageBasedLightComponent(source: .single(resource))
    iblEntity.components[ImageBasedLightReceiverComponent.self] =
        ImageBasedLightReceiverComponent()
    anchorEntity.addChild(iblEntity)
}

// 方法 C: DirectionalLight を複数追加してフラットな照明を確保
let lightAnchor = AnchorEntity(world: .init(translation: [0, 2, 2]))
var dirLight = DirectionalLightComponent()
dirLight.intensity = 2000
dirLight.isRealWorldProxy = false
lightAnchor.components[DirectionalLightComponent.self] = dirLight
arView.scene.addAnchor(lightAnchor)
```

---

## 原因③【エンティティが描画されない】PerspectiveCameraComponent の未設定

### 現象

`cameraMode: .nonAR` では RealityKit がデフォルトカメラを自動配置しないことがある。  
カメラエンティティが存在しない場合、**シーン全体が描画されない**。

### 対策

```swift
let cameraEntity = Entity()
cameraEntity.components[PerspectiveCameraComponent.self] =
    PerspectiveCameraComponent(
        near: 0.01,
        far: 1000,
        fieldOfViewInDegrees: 60
    )
cameraEntity.position = SIMD3<Float>(0, 0, 3) // Z 方向にバック

let cameraAnchor = AnchorEntity(world: .init())
cameraAnchor.addChild(cameraEntity)
arView.scene.addAnchor(cameraAnchor)
```

---

## 原因④【Xcode 26 / Swift 6 特有】Actor isolation によるスレッド問題

### 現象

Xcode 26 では Swift 6 の strict concurrency が有効になる場合がある。  
`@MainActor` 外から RealityKit Entity を操作すると、
**ランタイム警告または描画の欠落**が発生することがある。

### 確認方法

Xcode の Runtime Issues（⚠️ Thread Performance Checker）に
`Main actor-isolated … called from non-isolated context` が出ていないか確認する。

### 対策

```swift
Entity.loadAsync(named: name)
    .receive(on: DispatchQueue.main) // ← メインスレッドに切り替えてからキャッシュ
    .sink(
        receiveCompletion: { completion in
            if case .failure(let error) = completion {
                print("[ERROR] Failed to load \(name): \(error)")
            }
        },
        receiveValue: { [weak self] loaded in
            self?.entityCache[typeKey] = loaded
        }
    )
    .store(in: &cancellables)
```

---

## 原因⑤【白背景でも完全に不可視】iOS シミュレータでの RealityKit 3D 描画非対応

### 現象

`arView.environment.background = .color(.white)` を設定すると **背景色は白になる** が、
`AnchorEntity` 以下に追加した 3D エンティティ（`ModelEntity` 等）が一切表示されない。

### 原因

RealityKit の 3D レンダリングは **Metal GPU** を必要とするため、iOS シミュレータでは動作しない。

- `environment.background = .color(...)` は UIKit/CALayer レイヤーで描画 → シミュレータでも見える
- `AnchorEntity` 以下の 3D エンティティは Metal ベースのレンダリングパイプラインを使用 → **シミュレータでは描画されない**

背景色が変わって「ARView は動いている」ように見えるため、実機未使用に気づきにくい。

### 確認方法

Xcode 下部コンソールに以下のいずれかが出力されていないか確認する：

```
[SceneKit] Error: OpenGL ES context is not supported on this version of iOS.
```

またはシミュレータの機種名（例: `iPhone 16 Pro Simulator`）が
Xcode ウィンドウタイトルに表示されていないか確認する。

### 対策

**実機（iPhone / iPad）で実行する。** RealityKit は物理デバイスのみ完全サポート。  
シミュレータでの 3D プレビューが必要な場合は SceneKit か SwiftUI Canvas を代替手段として検討する。

---

## 原因⑥【白背景でも完全に不可視】`Entity.loadAsync` が Xcode 26 / Swift 6 で `ModelComponent` を持たない Entity を返す

### 現象

- `preloadAssets()` のプリロードでエラーが出ていない
- `entityCache[type.rawValue]` に Entity が格納されている（nil でない）
- `loadUSDZModel()` で `cached.clone(recursive: true)` が成功している
- にもかかわらず何も描画されない（背景色は見えるが 3D モデルがない）

### 原因

Xcode 26 / Swift 6 strict concurrency モードでは `Entity.loadAsync(named:)` の  
Combine `receiveValue` クロージャが **Main Actor 以外のスレッド** で呼ばれることがある。

このとき `Entity` の `ModelComponent`（実際の描画データ）が不完全な状態でキャッシュに入り、
`clone(recursive: true)` しても形状のない Entity が生成される。

> 本プロジェクトの `Bug3DNode.preloadAssets()` は現時点で `.receive(on: DispatchQueue.main)` を
> 持たないため、このパターンに該当する可能性がある。

### 確認方法

```swift
// Bug3DNode.loadUSDZModel() 内の clone 直後に追加
func hasModelComponent(_ e: Entity) -> Bool {
    if e.components.has(ModelComponent.self) { return true }
    return e.children.contains { hasModelComponent($0) }
}
print("[DEBUG] \(bugType.rawValue) hasModelComponent: \(hasModelComponent(model))")
```

`false` が出れば Entity は存在するが描画可能な形状データを持っていない。

### 対策

```swift
// ❌ 旧コード: Main Actor 保証なし（Xcode 26 では receiveValue が非メインスレッドで届く可能性）
Entity.loadAsync(named: name)
    .sink(
        receiveCompletion: { ... },
        receiveValue: { loaded in
            entityCache[typeKey] = loaded
        }
    )
    .store(in: &preloadCancellables)

// ✅ 対策 A: .receive(on:) でメインスレッドを保証（最小変更）
Entity.loadAsync(named: name)
    .receive(on: DispatchQueue.main)
    .sink(
        receiveCompletion: { ... },
        receiveValue: { loaded in
            cacheLock.lock()
            entityCache[typeKey] = loaded
            cacheLock.unlock()
        }
    )
    .store(in: &preloadCancellables)

// ✅ 対策 B: async/await に移行（Swift 6 推奨。Entity.loadAsync は deprecated）
Task { @MainActor in
    do {
        let loaded = try await Entity(named: name, in: nil)
        cacheLock.lock()
        entityCache[typeKey] = loaded
        loadingInProgress.remove(typeKey)
        cacheLock.unlock()
    } catch {
        print("Bug3DNode preload failed for \(name): \(error)")
        cacheLock.lock()
        loadingInProgress.remove(typeKey)
        cacheLock.unlock()
    }
}
```

---

## デバッグ手順（推奨順）

1. **実機確認**: iOS シミュレータではなく実機（iPhone / iPad）で実行しているか確認する
   → シミュレータなら**原因⑤確定**。実機に切り替える。

2. **キャッシュ確認**: `spawnBug()` 冒頭に `print` を追加し、
   スポーン時点で `entityCache` に値が入っているか確認する。

3. **タイミング検証**: 非 AR 起動後、意図的に 5 秒待ってからスポーンして症状が消えるか確認する
   → 消えれば**原因①（レースコンディション）確定**。

4. **照明検証**: `arView.environment.background = .color(.white)` を追加してモデルが見えるか確認する
   → **見えれば原因②（IBL 欠如）確定**。  
   → **白背景にしても見えない場合は原因②ではない**。手順 5 以降へ進む。

5. **ModelComponent 確認**: 上記「原因⑥ 確認方法」の `print` を追加し、
   クローン後の Entity に `ModelComponent` が存在するか確認する
   → `false` なら**原因⑥（Swift 6 / loadAsync 問題）確定**。`.receive(on: DispatchQueue.main)` を追加する。

6. **GPU フレームキャプチャ**: Xcode の Metal Debugger でフレームキャプチャを実行し、
   Entity が Draw Call に含まれているか確認する。

7. **Swift 6 警告確認**: Xcode の Runtime Issues パネルで
   Actor isolation 関連の警告が出ていないか確認する。

---

## 最小修正テンプレート（非 AR ViewController）

以下を `viewDidLoad` に追加するだけで原因①②③を一括対処できる。  
原因⑥（Swift 6 loadAsync 問題）対策は `preloadAssets()` 内に `.receive(on: DispatchQueue.main)` を追加すること。  
原因⑤（シミュレータ）は実機でのみ解消される。

```swift
override func viewDidLoad() {
    super.viewDidLoad()

    // ARView を nonAR モードで生成
    arView = ARView(
        frame: .zero,
        cameraMode: .nonAR,
        automaticallyConfigureSession: false
    )
    view.addSubview(arView)
    arView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        arView.topAnchor.constraint(equalTo: view.topAnchor),
        arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])

    // ① カメラを明示的に設定（原因③ 対策）
    let cam = Entity()
    cam.components[PerspectiveCameraComponent.self] =
        PerspectiveCameraComponent(near: 0.01, far: 500, fieldOfViewInDegrees: 60)
    cam.position = [0, 0, 3]
    let camAnchor = AnchorEntity(world: .init())
    camAnchor.addChild(cam)
    arView.scene.addAnchor(camAnchor)

    // ② ライティングを確保（原因② 対策）
    arView.environment.background = .color(.black)
    let lightAnchor = AnchorEntity(world: .init(translation: [0, 2, 2]))
    var dirLight = DirectionalLightComponent()
    dirLight.intensity = 1500
    dirLight.isRealWorldProxy = false
    lightAnchor.components[DirectionalLightComponent.self] = dirLight
    arView.scene.addAnchor(lightAnchor)

    // ③ アセットプリロード開始（原因① 対策: 完了後に startGame を呼ぶ）
    preloadAssets()
}

private func preloadAssets() {
    // ※ Bug3DNode.preloadAssets() 等、プロジェクト固有のプリロード処理に置き換えてください
    // preloadAssets() が完了したら waitForPreloadThenStart() を呼ぶ
    waitForPreloadThenStart()
}

private func waitForPreloadThenStart() {
    // ※ isPreloadComplete はプリロード完了を示すフラグに置き換えてください
    guard isPreloadComplete else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitForPreloadThenStart()
        }
        return
    }
    startGame()
}
```

---

## 参考: AR パスが成功する理由

| 状況 | AR モード | 非 AR モード | シミュレータ |
|------|-----------|-------------|-------------|
| セッション初期化待機 | あり（2〜4 秒） | **なし** | — |
| IBL 自動生成 | あり（カメラ映像から） | **なし** | — |
| デフォルトカメラ | ARKit が自動配置 | **なし（手動設定必要）** | — |
| 3D Entity 描画 | ✅ 実機のみ | ✅ 実機のみ | **❌ 非対応** |

ARKit のセッション起動はカメラ権限取得・センサー初期化のために通常 2〜4 秒かかる。  
この待機時間の間に `Entity.loadAsync` の非同期ロードが完了するため、  
AR モードでは最初のスポーン時に必ずキャッシュが満たされている。  
非 AR モードはこの自然な待機がないため、キャッシュ未完了のままスポーンが走る。
