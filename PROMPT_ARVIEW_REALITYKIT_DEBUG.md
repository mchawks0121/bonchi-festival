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

## デバッグ手順（推奨順）

1. **キャッシュ確認**: `spawnBug()` 冒頭に `print` を追加し、
   スポーン時点で `entityCache` に値が入っているか確認する。

2. **タイミング検証**: 非 AR 起動後、意図的に 5 秒待ってからスポーンして症状が消えるか確認する
   → 消えれば**原因①（レースコンディション）確定**。

3. **照明検証**: `arView.environment.background = .color(.white)` を追加してモデルが見えるか確認する
   → 見えれば**原因②（IBL 欠如）確定**。

4. **GPU フレームキャプチャ**: Xcode の Metal Debugger でフレームキャプチャを実行し、
   Entity が Draw Call に含まれているか確認する。

5. **Swift 6 警告確認**: Xcode の Runtime Issues パネルで
   Actor isolation 関連の警告が出ていないか確認する。

---

## 最小修正テンプレート（非 AR ViewController）

以下を `viewDidLoad` に追加するだけで原因①②③を一括対処できる。

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

| 状況 | AR モード | 非 AR モード |
|------|-----------|-------------|
| セッション初期化待機 | あり（2〜4 秒） | **なし** |
| IBL 自動生成 | あり（カメラ映像から） | **なし** |
| デフォルトカメラ | ARKit が自動配置 | **なし（手動設定必要）** |

ARKit のセッション起動はカメラ権限取得・センサー初期化のために通常 2〜4 秒かかる。  
この待機時間の間に `Entity.loadAsync` の非同期ロードが完了するため、  
AR モードでは最初のスポーン時に必ずキャッシュが満たされている。  
非 AR モードはこの自然な待機がないため、キャッシュ未完了のままスポーンが走る。
