//
//  WorldViewController.swift
//  bonchi-festival
//
//  Projector World: root UIViewController.
//  Hosts the SpriteKit scenes and bridges Multipeer Connectivity messages
//  to the active game scene.
//
//  Layout (back → front):
//    ┌─────────────────────────────────────┐
//    │  SCNView  – 3-D Bug3DNode world      │  (background, always present)
//    │  SKView   – HUD / net / proxy nodes  │  (transparent overlay)
//    └─────────────────────────────────────┘
//  During WaitingScene the SKScene has its own solid background and covers the SCNView.
//  During BugHunterScene (isProjectorMode=true) the SKScene background is clear so the
//  SceneKit 3-D bugs show through.
//

import UIKit
import SpriteKit
import SceneKit

// MARK: - WorldViewController

/// Install this as the rootViewController on the projector device.
final class WorldViewController: UIViewController {

    private var scnView: SCNView!
    private var skView: SKView!
    private var gameScene: BugHunterScene?
    private var bug3DCoordinator: ProjectorBug3DCoordinator?
    let projectorManager = ProjectorGameManager()

    /// Overlay view displayed in the bottom-right corner showing connected iOS controllers.
    private var connectedPlayersView: ConnectedPlayersView!

    /// Tracks the view size at the last layout pass so we can detect genuine changes.
    private var lastLayoutSize: CGSize = .zero

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // ── SceneKit layer (back) — renders 3-D bugs during gameplay ──────
        scnView = SCNView(frame: .zero)
        scnView.translatesAutoresizingMaskIntoConstraints = false
        scnView.backgroundColor    = UIColor(red: 0.05, green: 0.12, blue: 0.05, alpha: 1)
        scnView.autoenablesDefaultLighting = false
        view.addSubview(scnView)

        // ── SpriteKit layer (front, transparent) — HUD + net + proxy nodes ─
        skView = SKView(frame: .zero)
        skView.translatesAutoresizingMaskIntoConstraints = false
        skView.ignoresSiblingOrder = true
        skView.backgroundColor    = .clear
        skView.isOpaque           = false
        skView.allowsTransparency = true
        // Uncomment during development:
        // skView.showsFPS         = true
        // skView.showsNodeCount   = true
        view.addSubview(skView)

        // Pin both views to fill the entire view controller root view.
        for subview in [scnView!, skView!] {
            NSLayoutConstraint.activate([
                subview.topAnchor.constraint(equalTo: view.topAnchor),
                subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }

        projectorManager.delegate = self
        projectorManager.start()

        // ── Connected players overlay (bottom-right, always on top) ───────
        connectedPlayersView = ConnectedPlayersView()
        connectedPlayersView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(connectedPlayersView)
        NSLayoutConstraint.activate([
            connectedPlayersView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            connectedPlayersView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            connectedPlayersView.widthAnchor.constraint(equalToConstant: 220),
        ])
        // Scene creation is deferred to viewDidLayoutSubviews so that skView.bounds
        // reflects the final, correct screen size.
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let newSize = view.bounds.size
        guard newSize.width > 0, newSize.height > 0, newSize != lastLayoutSize else { return }
        lastLayoutSize = newSize

        // Update the 3-D coordinator's cached view size used for 3D→2D projection.
        bug3DCoordinator?.updateCachedViewSize(newSize)

        // First layout: present the waiting scene with the now-correct size.
        if skView.scene == nil {
            presentWaitingScene()
        }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - Scene Transitions

    private func presentWaitingScene() {
        bug3DCoordinator?.stopSpawning()
        bug3DCoordinator = nil
        gameScene = nil
        let scene = WaitingScene(size: skView.bounds.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene, transition: SKTransition.fade(withDuration: 0.4))
    }

    private func startGame() {
        let scene = BugHunterScene(size: skView.bounds.size)
        scene.scaleMode      = .resizeFill
        scene.isProjectorMode = true   // transparent bg; BugSpawner not auto-started
        scene.gameDelegate   = self
        gameScene = scene
        skView.presentScene(scene, transition: SKTransition.fade(withDuration: 0.5))

        // Start 3-D bug coordinator — spawns Bug3DNode in scnView and keeps
        // invisible proxy BugNodes synced in the SpriteKit overlay.
        let coordinator = ProjectorBug3DCoordinator()
        coordinator.attach(to: scnView, bugScene: scene)
        // When a bug is captured, notify the responsible iOS client so it can add points.
        coordinator.onCaptureNotify = { [weak self] bugType, playerIndex in
            self?.projectorManager.sendBugCaptured(bugType: bugType, toPlayerAtSlot: playerIndex)
        }
        coordinator.startSpawning()
        bug3DCoordinator = coordinator
    }

    /// Forward a net-launch event to the active game scene.
    func fireNet(angle: Float, power: Float, playerIndex: Int) {
        gameScene?.fireNet(angle: angle, power: power, playerIndex: playerIndex)
    }
}

// MARK: - BugHunterSceneDelegate

extension WorldViewController: BugHunterSceneDelegate {

    func scene(_ scene: SKScene, didUpdateScore score: Int, timeRemaining: Double) {
        let payload = GameStatePayload(state: "playing", score: score, timeRemaining: timeRemaining)
        projectorManager.sendGameState(payload)
    }

    func sceneDidFinish(_ scene: SKScene, finalScore: Int) {
        let payload = GameStatePayload(state: "finished", score: finalScore, timeRemaining: 0)
        projectorManager.sendGameState(payload)

        bug3DCoordinator?.stopSpawning()

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.presentWaitingScene()
        }
    }
}

// MARK: - ProjectorGameManagerDelegate

extension WorldViewController: ProjectorGameManagerDelegate {

    func managerDidReceiveStartGame(_ manager: ProjectorGameManager) {
        DispatchQueue.main.async { self.startGame() }
    }

    func managerDidReceiveReset(_ manager: ProjectorGameManager) {
        DispatchQueue.main.async { self.presentWaitingScene() }
    }

    func manager(_ manager: ProjectorGameManager, didReceiveLaunch payload: LaunchPayload, playerIndex: Int) {
        DispatchQueue.main.async { self.fireNet(angle: payload.angle, power: payload.power, playerIndex: playerIndex) }
    }

    func manager(_ manager: ProjectorGameManager, didUpdateConnectedPlayers players: [(name: String, playerIndex: Int)]) {
        connectedPlayersView.update(players: players)
    }
}

// MARK: - ProjectorBug3DCoordinator

/// Manages the SceneKit 3-D bug layer on the projector device.
///
/// Architecture mirrors `ARGameView.Coordinator`:
///   • `Bug3DNode` instances are placed in an `SCNScene` viewed by a fixed perspective camera.
///   • Each bug gets an **invisible** proxy `BugNode` added to `BugHunterScene`.  The proxy is
///     positioned every frame at the screen-space projection of its Bug3DNode so that the net
///     projectile's physics body can collide with it through the existing `didBegin(contact:)` path.
///   • When `BugHunterScene.onBugCaptured` fires for a proxy, the matching Bug3DNode is dismissed.
final class ProjectorBug3DCoordinator: NSObject {

    // MARK: Dependencies

    weak var scnView: SCNView?
    weak var bugScene: BugHunterScene?

    // MARK: SceneKit scene + camera

    private let scnScene  = SCNScene()

    /// Camera Z-position.  Bugs are placed at Z=0 (world origin plane) so the
    /// viewing distance equals this value.  The visible frustum half-height at Z=0 is
    /// approximately `cameraZ × tan(cameraFOV / 2)` ≈ 2.43 units.
    private static let cameraZ: Float = 3.5

    /// Vertical field-of-view (degrees).  At 65° and cameraZ=3.5 the visible height at
    /// Z=0 is ~4.86 units — enough room for bugs to wander across the whole screen.
    private static let cameraFOV: CGFloat = 65

    /// Bug3DNode geometry is built at ~0.05–0.10-unit scale (designed for AR at 1–3 m).
    /// Multiplying by this factor makes a bug occupy a comfortable ~20 % of screen height
    /// in the ~4.86-unit tall projector world.
    private static let bugScaleMultiplier: Float = 10

    /// Minimum spawn interval (seconds) after the difficulty ramp is fully applied.
    private static let minSpawnInterval: TimeInterval = 0.6
    /// Initial spawn interval (seconds) at the start of a game round.
    private static let initialSpawnInterval: TimeInterval = 1.8
    /// Duration (seconds) over which the spawn interval ramps from initial to minimum.
    private static let spawnAccelerationDuration: TimeInterval = 75.0

    private let cameraNode: SCNNode = {
        let n = SCNNode()
        let cam = SCNCamera()
        cam.fieldOfView = ProjectorBug3DCoordinator.cameraFOV
        n.camera = cam
        n.position = SCNVector3(0, 0, ProjectorBug3DCoordinator.cameraZ)
        return n
    }()

    // MARK: Bug tracking (accessed from both main thread and SceneKit render thread)
    private var bug3DNodes:  [UUID: Bug3DNode] = [:]
    private var proxyNodes:  [UUID: BugNode]   = [:]
    /// Reverse map: ObjectIdentifier(proxy BugNode) → bug UUID.
    private var proxyToUUID: [ObjectIdentifier: UUID] = [:]

    // MARK: Spawn state

    private var spawnTimer:   Timer?
    private var isSpawning    = false
    private var spawnElapsed: TimeInterval = 0
    private var lastSpawnTime: Date?

    /// Cached on the main thread so the render thread can read it safely.
    private var cachedViewSize: CGSize = UIScreen.main.bounds.size

    /// Called on the main thread when a bug is captured, with the bug type and the
    /// player slot index of the net that hit it.  Set by `WorldViewController` to
    /// forward the event to `ProjectorGameManager.sendBugCaptured`.
    var onCaptureNotify: ((BugType, Int) -> Void)?

    // MARK: - Init / attach

    override init() {
        super.init()
        setupScene()
    }

    /// Wire the coordinator to the views.  Must be called on the main thread before `startSpawning()`.
    func attach(to scnView: SCNView, bugScene: BugHunterScene) {
        self.scnView  = scnView
        self.bugScene = bugScene
        scnView.scene    = scnScene
        scnView.delegate = self
        scnView.isPlaying = true   // keep rendering even with no camera movement
        if scnView.bounds.size.height > 0 { cachedViewSize = scnView.bounds.size }

        bugScene.onBugCaptured = { [weak self] proxy, playerIndex in
            self?.handleCapture(of: proxy, playerIndex: playerIndex)
        }
    }

    // MARK: - SceneKit scene setup

    private func setupScene() {
        scnScene.rootNode.addChildNode(cameraNode)

        let ambientNode  = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type      = .ambient
        ambientLight.intensity = 600
        ambientNode.light = ambientLight
        scnScene.rootNode.addChildNode(ambientNode)

        let dirNode  = SCNNode()
        let dirLight = SCNLight()
        dirLight.type      = .directional
        dirLight.intensity = 1200
        dirNode.light = dirLight
        dirNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scnScene.rootNode.addChildNode(dirNode)
    }

    // MARK: - Lifecycle

    /// Update the cached view size used for 3D→2D projection.
    /// Call this whenever the view controller's view changes size (e.g., rotation, external display).
    func updateCachedViewSize(_ size: CGSize) {
        cachedViewSize = size
    }

    func startSpawning() {
        stopSpawning()
        isSpawning    = true
        spawnElapsed  = 0
        lastSpawnTime = Date()
        if let v = scnView, v.bounds.size.height > 0 { cachedViewSize = v.bounds.size }
        scheduleNextSpawn(delay: 0.8)
    }

    func stopSpawning() {
        isSpawning = false
        spawnTimer?.invalidate()
        spawnTimer = nil

        bug3DNodes.values.forEach { $0.removeFromParentNode() }
        bug3DNodes.removeAll()

        proxyNodes.values.forEach { $0.removeFromParent() }
        proxyNodes.removeAll()
        proxyToUUID.removeAll()
    }

    // MARK: - Spawning

    private func scheduleNextSpawn(delay: TimeInterval) {
        guard isSpawning else { return }
        spawnTimer?.invalidate()
        spawnTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.spawnBug()
        }
    }

    private func spawnBug() {
        guard isSpawning, let scnView else {
            scheduleNextSpawn(delay: 0.4)
            return
        }

        let bugType = randomBugType()
        let uuid    = UUID()

        let bug3D = Bug3DNode(type: bugType)
        let s = Self.bugScaleMultiplier
        bug3D.scale    = SCNVector3(s, s, s)
        bug3D.position = randomEdgePosition3D(in: scnView)
        scnScene.rootNode.addChildNode(bug3D)
        bug3DNodes[uuid] = bug3D

        // Movement: float in from an edge, linger, then drift off-screen.
        let destPos = randomCenterPosition3D(in: scnView)
        let exitPos = randomEdgePosition3D(in: scnView)
        let moveIn  = SCNAction.move(to: destPos, duration: Double.random(in: 6.0...10.0))
        let linger  = SCNAction.wait(forDuration: Double.random(in: 1.5...3.5))
        let moveOut = SCNAction.move(to: exitPos, duration: Double.random(in: 3.0...5.0))
        let remove  = SCNAction.run { [weak self] _ in
            DispatchQueue.main.async { self?.removeBug(uuid: uuid) }
        }
        moveIn.timingMode  = .easeInEaseOut
        moveOut.timingMode = .easeIn
        bug3D.runAction(SCNAction.sequence([moveIn, linger, moveOut, remove]), forKey: "movement")

        // Invisible proxy BugNode in the SpriteKit overlay — carries the physics body
        // that the net projectile collides with.  Position is synced each frame.
        let proxy = BugNode(type: bugType)
        proxy.alpha = 0       // invisible: only physics matters
        proxyNodes[uuid]                      = proxy
        proxyToUUID[ObjectIdentifier(proxy)]  = uuid
        DispatchQueue.main.async { [weak self] in
            self?.bugScene?.addChild(proxy)
        }

        // Progressive spawn interval: linearly interpolates from initialSpawnInterval to
        // minSpawnInterval over spawnAccelerationDuration seconds, then stays at minimum.
        let now = Date()
        if let last = lastSpawnTime { spawnElapsed += now.timeIntervalSince(last) }
        lastSpawnTime = now
        let fraction   = min(1.0, spawnElapsed / Self.spawnAccelerationDuration)
        let range      = Self.initialSpawnInterval - Self.minSpawnInterval
        let nextDelay  = Self.initialSpawnInterval - fraction * range
        scheduleNextSpawn(delay: nextDelay)
    }

    private func randomBugType() -> BugType {
        switch Double.random(in: 0..<1) {
        case ..<0.60: return .butterfly
        case ..<0.90: return .beetle
        default:      return .stag
        }
    }

    // MARK: - 3-D position helpers

    /// Half-width and half-height of the visible frustum at Z = 0 (world origin plane).
    private func visibleHalfExtents(in view: SCNView) -> (halfW: Float, halfH: Float) {
        let fovRad = Float(Self.cameraFOV) * .pi / 180.0
        let halfH  = Self.cameraZ * tan(fovRad / 2)
        let aspect = Float(view.bounds.width / max(view.bounds.height, 1))
        return (halfH * aspect, halfH)
    }

    private func randomEdgePosition3D(in view: SCNView) -> SCNVector3 {
        let (halfW, halfH) = visibleHalfExtents(in: view)
        // Spawn 0.5 world-units beyond the visible frustum edge so bugs enter from off-screen.
        let margin: Float  = 0.5
        switch Int.random(in: 0..<4) {
        case 0: return SCNVector3( Float.random(in: -halfW...halfW),  halfH + margin, 0)
        case 1: return SCNVector3( Float.random(in: -halfW...halfW), -halfH - margin, 0)
        case 2: return SCNVector3(-halfW - margin, Float.random(in: -halfH...halfH),  0)
        default: return SCNVector3(halfW + margin, Float.random(in: -halfH...halfH),  0)
        }
    }

    private func randomCenterPosition3D(in view: SCNView) -> SCNVector3 {
        let (halfW, halfH) = visibleHalfExtents(in: view)
        return SCNVector3(
            Float.random(in: -halfW * 0.75 ... halfW * 0.75),
            Float.random(in: -halfH * 0.75 ... halfH * 0.75),
            Float.random(in: -0.4...0.4)   // slight Z variation for depth interest
        )
    }

    // MARK: - Capture

    /// Called by `BugHunterScene.onBugCaptured` when a proxy is hit by the net.
    private func handleCapture(of proxy: BugNode, playerIndex: Int) {
        guard let uuid = proxyToUUID[ObjectIdentifier(proxy)] else { return }
        bug3DNodes[uuid]?.captured()
        let bugType = proxy.bugType
        bug3DNodes.removeValue(forKey: uuid)
        proxyNodes.removeValue(forKey: uuid)
        proxyToUUID.removeValue(forKey: ObjectIdentifier(proxy))
        onCaptureNotify?(bugType, playerIndex)
    }

    /// Called when a bug exits the screen naturally (end of its movement sequence).
    private func removeBug(uuid: UUID) {
        guard bug3DNodes[uuid] != nil else { return }   // already captured
        if let proxy = proxyNodes[uuid] {
            proxy.removeFromParent()
            proxyToUUID.removeValue(forKey: ObjectIdentifier(proxy))
        }
        bug3DNodes.removeValue(forKey: uuid)
        proxyNodes.removeValue(forKey: uuid)
    }
}

// MARK: - SCNSceneRendererDelegate

extension ProjectorBug3DCoordinator: SCNSceneRendererDelegate {

    /// Projects each Bug3DNode's world position into SpriteKit overlay coordinates and
    /// moves the corresponding proxy BugNode so the net collision detection stays accurate.
    /// Runs on the SceneKit render thread; UI writes are batched to the main thread.
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let scnView = self.scnView else { return }

        let viewHeight = cachedViewSize.height

        var updates: [(BugNode, CGPoint)] = []
        for (uuid, bug3D) in bug3DNodes {
            guard let proxy = proxyNodes[uuid] else { continue }
            let projected = scnView.projectPoint(bug3D.worldPosition)
            // projected.z is normalized depth in [0, 1]; values outside that range mean
            // the bug is behind the camera or beyond the far clipping plane — skip those.
            guard projected.z > 0, projected.z < 1 else { continue }
            updates.append((proxy, CGPoint(
                x: CGFloat(projected.x),
                y: viewHeight - CGFloat(projected.y)   // flip Y: SceneKit → SpriteKit
            )))
        }

        guard !updates.isEmpty else { return }
        DispatchQueue.main.async {
            for (proxy, pos) in updates {
                proxy.position = pos
            }
        }
    }
}

// MARK: - ConnectedPlayersView

/// A semi-transparent UIView displayed in the bottom-right corner of the projector screen
/// showing the names and player-color indicators of all currently connected iOS controllers.
final class ConnectedPlayersView: UIView {

    /// Accent colors matching `NetProjectile.playerColors` (cyan, orange, magenta).
    static let playerColors: [UIColor] = [
        UIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1),
        UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1),
        UIColor(red: 1.0, green: 0.2,  blue: 0.8, alpha: 1),
    ]

    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor          = UIColor.black.withAlphaComponent(0.55)
        layer.cornerRadius       = 12
        layer.masksToBounds      = true

        stackView.axis           = .vertical
        stackView.spacing        = 6
        stackView.alignment      = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])

        // Initial state: no players connected
        update(players: [])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    /// Refresh the panel with the current list of connected players.
    func update(players: [(name: String, playerIndex: Int)]) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let header = UILabel()
        header.text      = "接続中 \(players.count) / \(ProjectorGameManager.maxPlayers)"
        header.textColor = UIColor.white.withAlphaComponent(0.85)
        header.font      = .systemFont(ofSize: 13, weight: .semibold)
        stackView.addArrangedSubview(header)

        for i in 0..<ProjectorGameManager.maxPlayers {
            if let player = players.first(where: { $0.playerIndex == i }) {
                stackView.addArrangedSubview(makeRow(name: player.name, slot: i))
            } else {
                stackView.addArrangedSubview(makeEmptyRow(slot: i))
            }
        }
    }

    // MARK: - Private helpers

    private func makeRow(name: String, slot: Int) -> UIView {
        let color     = Self.playerColors[slot % Self.playerColors.count]
        let row       = UIStackView()
        row.axis      = .horizontal
        row.spacing   = 8
        row.alignment = .center

        let dot = makeDot(color: color)
        let lbl = UILabel()
        lbl.text      = name
        lbl.textColor = .white
        lbl.font      = .systemFont(ofSize: 13)
        lbl.lineBreakMode = .byTruncatingMiddle

        row.addArrangedSubview(dot)
        row.addArrangedSubview(lbl)
        return row
    }

    private func makeEmptyRow(slot: Int) -> UIView {
        let color     = Self.playerColors[slot % Self.playerColors.count]
        let row       = UIStackView()
        row.axis      = .horizontal
        row.spacing   = 8
        row.alignment = .center

        let dot = makeDot(color: color.withAlphaComponent(0.3))
        let lbl = UILabel()
        lbl.text      = "待機中..."
        lbl.textColor = UIColor.white.withAlphaComponent(0.35)
        lbl.font      = .systemFont(ofSize: 13)

        row.addArrangedSubview(dot)
        row.addArrangedSubview(lbl)
        return row
    }

    private func makeDot(color: UIColor) -> UIView {
        let dot = UIView()
        dot.backgroundColor    = color
        dot.layer.cornerRadius = 6
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 12),
            dot.heightAnchor.constraint(equalToConstant: 12),
        ])
        return dot
    }
}

