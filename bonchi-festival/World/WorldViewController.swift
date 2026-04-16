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
//  Both during WaitingScene (isProjectorOverlay=true) and during BugHunterScene
//  (isProjectorMode=true) the SKScene background is clear so the SceneKit 3-D
//  environment always shows through.  The projector display is fully 3-D at all times.
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

        // Preload USDZ assets so the first Bug3DNode spawn uses the model from cache
        // rather than falling back to procedural geometry.  Mirrors the preload call in
        // ARGameView.makeUIView for the iOS AR path.
        Bug3DNode.preloadAssets()

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

        // First layout: start the 3-D game immediately so the projector display
        // is 3D from the moment the view appears, without requiring an iOS client
        // to send a startGame message first.
        if skView.scene == nil {
            startGame()
        }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - Scene Transitions

    private func startGame() {
        // Stop and release any previously running coordinator synchronously
        // (stopSpawning invalidates its timer and removes all nodes on the main thread)
        // before creating a new one to avoid resource leaks or stale callbacks.
        bug3DCoordinator?.stopSpawning()
        bug3DCoordinator = nil
        gameScene = nil

        let scene = BugHunterScene(size: skView.bounds.size)
        scene.scaleMode       = .resizeFill
        scene.isProjectorMode = true   // transparent bg over SceneKit layer
        gameScene = scene
        skView.presentScene(scene, transition: SKTransition.fade(withDuration: 0.5))

        // Start the 3-D coordinator — manages Bug3DNode objects in scnView.
        // Bug spawning is phone-driven; the coordinator just receives add/remove calls.
        let coordinator = ProjectorBug3DCoordinator()
        coordinator.attach(to: scnView, bugScene: scene)
        bug3DCoordinator = coordinator
    }

    /// Forward a net-launch event to the active game scene.
    func fireNet(angle: Float, power: Float, playerIndex: Int) {
        gameScene?.fireNet(angle: angle, power: power, playerIndex: playerIndex)
    }
}

// MARK: - ProjectorGameManagerDelegate

extension WorldViewController: ProjectorGameManagerDelegate {

    func managerDidReceiveStartGame(_ manager: ProjectorGameManager) {
        DispatchQueue.main.async { self.startGame() }
    }

    func managerDidReceiveReset(_ manager: ProjectorGameManager) {
        // Clear all bugs but stay on the same scene (projector is always running).
        DispatchQueue.main.async { self.bug3DCoordinator?.stopSpawning() }
    }

    func manager(_ manager: ProjectorGameManager, didReceiveLaunch payload: LaunchPayload, playerIndex: Int) {
        DispatchQueue.main.async { self.fireNet(angle: payload.angle, power: payload.power, playerIndex: playerIndex) }
    }

    func manager(_ manager: ProjectorGameManager, didReceiveBugSpawned payload: BugSpawnedPayload) {
        DispatchQueue.main.async {
            self.bug3DCoordinator?.addSyncedBug(id: payload.id,
                                                type: payload.bugType,
                                                normalizedX: payload.normalizedX,
                                                normalizedY: payload.normalizedY)
        }
    }

    func manager(_ manager: ProjectorGameManager, didReceiveBugRemoved payload: BugRemovedPayload) {
        DispatchQueue.main.async {
            self.bug3DCoordinator?.removeSyncedBug(id: payload.id)
        }
    }

    func manager(_ manager: ProjectorGameManager, didUpdateConnectedPlayers players: [(name: String, playerIndex: Int)]) {
        connectedPlayersView.update(players: players)
    }
}

// MARK: - ProjectorBug3DCoordinator

/// Manages the SceneKit 3-D bug layer on the projector device.
///
/// Bug lifecycle is fully phone-driven:
///   • `addSyncedBug(id:type:normalizedX:normalizedY:)` — called when the phone sends a
///     `bugSpawned` message.  Creates a Bug3DNode at the corresponding screen position.
///   • `removeSyncedBug(id:)` — called when the phone sends a `bugRemoved` message.
///     Plays the capture animation and removes the node.
///   • `stopSpawning()` — clears all active bugs (used on reset).
///
/// The coordinator no longer spawns bugs independently or maintains proxy SKNodes.
final class ProjectorBug3DCoordinator: NSObject {

    // MARK: Dependencies

    weak var scnView: SCNView?
    weak var bugScene: BugHunterScene?

    // MARK: SceneKit scene + camera

    private let scnScene = SCNScene()

    /// Camera Z-position.  Bugs are placed at Z=0 so the viewing distance equals this value.
    private static let cameraZ: Float = 3.5

    /// Vertical field-of-view (degrees).
    private static let cameraFOV: CGFloat = 65

    /// Scale multiplier applied to Bug3DNode geometry so bugs appear at a comfortable size
    /// on the projector screen.
    private static let bugScaleMultiplier: Float = 10

    private let cameraNode: SCNNode = {
        let n = SCNNode()
        let cam = SCNCamera()
        cam.fieldOfView = ProjectorBug3DCoordinator.cameraFOV
        n.camera = cam
        n.position = SCNVector3(0, 0, ProjectorBug3DCoordinator.cameraZ)
        return n
    }()

    // MARK: Bug tracking (main thread only)

    /// Maps stable bug ID (phone anchor UUID string) → Bug3DNode.
    private var bug3DNodes: [String: Bug3DNode] = [:]

    /// Bug3DNode instances spawned autonomously (without a phone connection).
    private var autonomousBugs: [Bug3DNode] = []

    /// Timer driving the autonomous spawn cycle.
    private var autonomousSpawnTimer: Timer?

    /// Wall-clock time when autonomous spawning started; used for difficulty ramp.
    private var autonomousStartTime: Date = Date()

    /// Cached on the main thread so helpers can read it without accessing the view.
    private var cachedViewSize: CGSize = UIScreen.main.bounds.size

    // MARK: - Init / attach

    override init() {
        super.init()
        setupScene()
    }

    /// Wire the coordinator to the views.  Must be called on the main thread.
    func attach(to scnView: SCNView, bugScene: BugHunterScene) {
        self.scnView  = scnView
        self.bugScene = bugScene
        scnView.scene    = scnScene
        scnView.isPlaying = true   // keep rendering even with no camera movement
        if scnView.bounds.size.height > 0 { cachedViewSize = scnView.bounds.size }
        startAutonomousSpawning()
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

    /// Update the cached view size.  Call when the view controller layout changes.
    func updateCachedViewSize(_ size: CGSize) {
        cachedViewSize = size
    }

    /// Remove all active bugs (e.g. on game reset).
    func stopSpawning() {
        // Stop autonomous spawner
        autonomousSpawnTimer?.invalidate()
        autonomousSpawnTimer = nil

        // Remove autonomous bugs
        autonomousBugs.forEach { $0.removeFromParentNode() }
        autonomousBugs.removeAll()

        // Remove phone-synced bugs
        bug3DNodes.values.forEach { $0.removeFromParentNode() }
        bug3DNodes.removeAll()

        notifyBugCountChanged()
    }

    // MARK: - Phone-driven bug management

    /// Add a bug to the projector scene at the position derived from the phone's spawn angles.
    /// - Parameters:
    ///   - id: Stable identifier from `BugSpawnedPayload.id`.
    ///   - type: Bug type to display.
    ///   - normalizedX: Horizontal position –1…1 (maps to scene width).
    ///   - normalizedY: Vertical position 0…1, where 0 = bottom and 1 = top.
    func addSyncedBug(id: String, type: BugType, normalizedX: Float, normalizedY: Float) {
        guard let scnView else { return }

        let (halfW, halfH) = visibleHalfExtents(in: scnView)
        let x = normalizedX * halfW * 0.70
        let y = (normalizedY * 2.0 - 1.0) * halfH * 0.60

        let bug3D = Bug3DNode(type: type)
        let s = CGFloat(Self.bugScaleMultiplier)
        bug3D.scale    = SCNVector3(s * 0.1, s * 0.1, s * 0.1)   // start small for pop-in
        bug3D.position = SCNVector3(x, y, 0)
        bug3D.opacity  = 0
        scnScene.rootNode.addChildNode(bug3D)
        bug3DNodes[id] = bug3D

        // Appear animation: scale up and fade in
        bug3D.runAction(SCNAction.group([
            SCNAction.fadeIn(duration: 0.4),
            SCNAction.scale(to: s, duration: 0.4)
        ]))

        // Gentle hover so the bug looks alive on screen
        let floatUp   = SCNAction.moveBy(x: 0, y: CGFloat(halfH * 0.06), z: 0, duration: 1.8)
        let floatDown = SCNAction.moveBy(x: 0, y: CGFloat(-halfH * 0.06), z: 0, duration: 1.8)
        floatUp.timingMode   = .easeInEaseOut
        floatDown.timingMode = .easeInEaseOut
        bug3D.runAction(SCNAction.repeatForever(SCNAction.sequence([floatUp, floatDown])),
                        forKey: "hover")

        notifyBugCountChanged()
    }

    /// Remove a bug from the projector scene, playing the capture animation.
    func removeSyncedBug(id: String) {
        guard let bug3D = bug3DNodes[id] else { return }
        bug3D.removeAction(forKey: "hover")
        bug3D.captured()
        bug3DNodes.removeValue(forKey: id)
        notifyBugCountChanged()
    }

    // MARK: - Autonomous bug spawning

    /// Start the autonomous spawn cycle.  Bugs appear on-screen even when no phone is connected,
    /// so the projector world is always corrupted and alive.
    private func startAutonomousSpawning() {
        autonomousSpawnTimer?.invalidate()
        autonomousStartTime = Date()
        scheduleNextAutonomousSpawn(after: 1.5)
    }

    private func scheduleNextAutonomousSpawn(after delay: TimeInterval) {
        autonomousSpawnTimer?.invalidate()
        autonomousSpawnTimer = Timer.scheduledTimer(
            withTimeInterval: delay, repeats: false
        ) { [weak self] _ in
            self?.spawnAutonomousBug()
        }
    }

    private func spawnAutonomousBug() {
        guard let scnView else { return }

        let elapsed   = Date().timeIntervalSince(autonomousStartTime)
        let (halfW, halfH) = visibleHalfExtents(in: scnView)

        // Spawn at a random edge of the visible frustum
        let edge = Int.random(in: 0..<4)
        let startX: Float
        let startY: Float
        switch edge {
        case 0:  startX = Float.random(in: -halfW...halfW);  startY =  halfH * 1.25   // top
        case 1:  startX = Float.random(in: -halfW...halfW);  startY = -halfH * 1.25   // bottom
        case 2:  startX = -halfW * 1.25;                     startY = Float.random(in: -halfH...halfH)  // left
        default: startX =  halfW * 1.25;                     startY = Float.random(in: -halfH...halfH)  // right
        }

        let bugType = randomAutonomousBugType()
        let bug3D   = Bug3DNode(type: bugType)
        let s       = CGFloat(Self.bugScaleMultiplier)
        bug3D.scale    = SCNVector3(s * 0.05, s * 0.05, s * 0.05)
        bug3D.position = SCNVector3(startX, startY, 0)
        bug3D.opacity  = 0
        scnScene.rootNode.addChildNode(bug3D)
        autonomousBugs.append(bug3D)

        // Pop-in appearance
        bug3D.runAction(SCNAction.group([
            SCNAction.fadeIn(duration: 0.5),
            SCNAction.scale(to: s, duration: 0.5),
        ]))

        // Movement path: 2–3 interior waypoints then exit off-screen
        let bugDuration  = max(4.0, min(600.0 / Double(bugType.speed), 14.0))
        let waypointCount = Int.random(in: 2...3)
        let segDur        = bugDuration / Double(waypointCount + 1)

        var actions: [SCNAction] = []
        for _ in 0..<waypointCount {
            let wx   = Float.random(in: -halfW * 0.75 ... halfW * 0.75)
            let wy   = Float.random(in: -halfH * 0.65 ... halfH * 0.65)
            let move = SCNAction.move(to: SCNVector3(wx, wy, 0), duration: segDur)
            move.timingMode = .easeInEaseOut
            actions.append(move)
        }

        // Exit toward the opposite edge
        let exitX = Float.random(in: -halfW * 0.8 ... halfW * 0.8)
        let exitY = Float.random(in: -halfH * 0.8 ... halfH * 0.8)
        let exitPoint: SCNVector3
        switch edge {
        case 0:  exitPoint = SCNVector3(exitX, -halfH * 1.3, 0)
        case 1:  exitPoint = SCNVector3(exitX,  halfH * 1.3, 0)
        case 2:  exitPoint = SCNVector3( halfW * 1.3, exitY, 0)
        default: exitPoint = SCNVector3(-halfW * 1.3, exitY, 0)
        }
        let exitMove = SCNAction.move(to: exitPoint, duration: segDur)
        exitMove.timingMode = .easeIn
        actions.append(exitMove)

        // Removal on the main thread (SCNAction.run fires on the render thread)
        actions.append(SCNAction.run { _ in
            DispatchQueue.main.async { [weak self, weak bug3D] in
                guard let bug3D else { return }
                bug3D.removeFromParentNode()
                self?.autonomousBugs.removeAll { $0 === bug3D }
                self?.notifyBugCountChanged()
            }
        })

        bug3D.runAction(SCNAction.sequence(actions))
        notifyBugCountChanged()

        // Progressive spawn interval: 1.8 s → 0.6 s over 90 s
        let nextDelay = max(0.6, 1.8 - elapsed / 90.0)
        scheduleNextAutonomousSpawn(after: nextDelay)
    }

    private func randomAutonomousBugType() -> BugType {
        let roll = Double.random(in: 0..<1)
        switch roll {
        case ..<0.60: return .butterfly
        case ..<0.90: return .beetle
        default:      return .stag
        }
    }

    /// Notify `bugScene` of the current total bug count so it can update distortion.
    private func notifyBugCountChanged() {
        let total = autonomousBugs.count + bug3DNodes.count
        bugScene?.updateWorldDistortion(bugCount: total)
    }

    // MARK: - 3-D position helpers

    /// Half-width and half-height of the visible frustum at Z = 0 (world origin plane).
    private func visibleHalfExtents(in view: SCNView) -> (halfW: Float, halfH: Float) {
        let fovRad = Float(Self.cameraFOV) * .pi / 180.0
        let halfH  = Self.cameraZ * tan(fovRad / 2)
        let aspect = Float(view.bounds.width / max(view.bounds.height, 1))
        return (halfH * aspect, halfH)
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

