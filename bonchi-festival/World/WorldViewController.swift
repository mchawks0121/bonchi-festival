//
//  WorldViewController.swift
//  bonchi-festival
//
//  Projector World: root UIViewController.
//  Hosts the SpriteKit scenes and bridges Multipeer Connectivity messages
//  to the active game scene.
//
//  Implementation intent:
//    Rewritten to use RealityKit (no SceneKit) for the 3-D background layer.
//    ARView(cameraMode: .nonAR) replaces SCNView; PerspectiveCameraComponent
//    replaces SCNCamera; Entity/AnchorEntity replaces SCNNode/SCNScene.
//
//  Layout (back → front):
//    ┌─────────────────────────────────────┐
//    │  ARView  – RealityKit 3-D Bug world │  (background, always present)
//    │  SKView  – HUD / net / proxy nodes  │  (transparent overlay)
//    └─────────────────────────────────────┘
//
//  Security considerations:
//    No file I/O beyond USDZ bundle loading handled by Bug3DNode.preloadAssets().
//
//  Constraints:
//    SceneKit (SCNView, SCNScene, SCNNode, SCNAction, etc.) must NOT be used.
//

import UIKit
import SpriteKit
import RealityKit
import Combine

// MARK: - WorldViewController

/// Install this as the rootViewController on the projector device.
final class WorldViewController: UIViewController {

    private var arView: ARView!
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

        // ── RealityKit layer (back) — renders 3-D bugs during gameplay ────
        // cameraMode: .nonAR disables ARKit tracking; the scene is rendered with a
        // fixed perspective camera placed at (0, 0, cameraZ) looking toward Z=0.
        arView = ARView(frame: .zero, cameraMode: .nonAR,
                        automaticallyConfigureSession: false)
        arView.translatesAutoresizingMaskIntoConstraints = false
        // Dark green background colour matching the original SCNView background.
        arView.environment.background = .color(UIColor(red: 0.05, green: 0.12,
                                                       blue: 0.05, alpha: 1))
        view.addSubview(arView)

        // ── SpriteKit layer (front, transparent) — HUD + net + proxy nodes ─
        skView = SKView(frame: .zero)
        skView.translatesAutoresizingMaskIntoConstraints = false
        skView.ignoresSiblingOrder = true
        skView.backgroundColor    = .clear
        skView.isOpaque           = false
        skView.allowsTransparency = true
        view.addSubview(skView)

        // Pin both views to fill the entire view controller root view.
        for subview in [arView!, skView!] as [UIView] {
            NSLayoutConstraint.activate([
                subview.topAnchor.constraint(equalTo: view.topAnchor),
                subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }

        // Preload USDZ assets for both the iOS AR path and this projector path.
        // Mirrors the preload call in ARGameView.makeUIView.
        Bug3DNode.preloadAssets()

        projectorManager.delegate = self
        projectorManager.start()

        // ── Connected players overlay (bottom-right, always on top) ───────
        connectedPlayersView = ConnectedPlayersView()
        connectedPlayersView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(connectedPlayersView)
        NSLayoutConstraint.activate([
            connectedPlayersView.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            connectedPlayersView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            connectedPlayersView.widthAnchor.constraint(equalToConstant: 220),
        ])
        // Scene creation is deferred to viewDidLayoutSubviews so that arView.bounds
        // reflects the final, correct screen size.
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let newSize = view.bounds.size
        guard newSize.width > 0, newSize.height > 0, newSize != lastLayoutSize else { return }
        lastLayoutSize = newSize

        // Update the 3-D coordinator's cached view size used for position calculation.
        bug3DCoordinator?.updateCachedViewSize(newSize)

        // First layout: start the 3-D game immediately.
        if skView.scene == nil {
            startGame()
        }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - Scene Transitions

    private func startGame() {
        bug3DCoordinator?.stopSpawning()
        bug3DCoordinator = nil
        gameScene = nil

        let scene = BugHunterScene(size: skView.bounds.size)
        scene.scaleMode       = .resizeFill
        scene.isProjectorMode = true   // transparent bg over RealityKit layer
        gameScene = scene
        skView.presentScene(scene, transition: SKTransition.fade(withDuration: 0.5))

        let coordinator = ProjectorBug3DCoordinator()
        coordinator.attach(to: arView, bugScene: scene)
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

/// Manages the RealityKit 3-D bug layer on the projector device.
///
/// Implementation intent:
///   Rewritten to use RealityKit (no SceneKit) as required.
///   Each Bug3DNode.entity is placed under its own world AnchorEntity so that
///   individual bug positions can be updated without moving other entities.
///   SCNAction-based animations are replaced by Timer-based entity transform updates.
///
/// Bug lifecycle is fully phone-driven:
///   • addSyncedBug(id:type:normalizedX:normalizedY:) — creates a Bug3DNode entity.
///   • removeSyncedBug(id:)                           — plays capture animation.
///   • stopSpawning()                                 — clears all active bugs.
final class ProjectorBug3DCoordinator {

    // MARK: Dependencies

    weak var arView: ARView?
    weak var bugScene: BugHunterScene?

    // MARK: RealityKit camera constants

    /// Camera Z-position.  Bugs are placed at Z=0 so viewing distance = cameraZ.
    private static let cameraZ: Float = 3.5

    /// Vertical field-of-view (degrees).
    private static let cameraFOV: Float = 65

    /// Scale multiplier applied to Bug3DNode geometry on the projector screen.
    private static let bugScaleMultiplier: Float = 10

    // MARK: Bug tracking (main thread only)

    /// Maps stable bug ID (phone anchor UUID string) → Bug3DNode.
    private var bug3DNodes:   [String: Bug3DNode]   = [:]
    /// Maps stable bug ID → its world AnchorEntity (needed for scene removal).
    private var bug3DAnchors: [String: AnchorEntity] = [:]

    /// Bug3DNode instances spawned autonomously (without a phone connection).
    private var autonomousBugs:   [Bug3DNode]   = []
    /// World AnchorEntity instances for autonomous bugs.
    private var autonomousAnchors: [AnchorEntity] = []

    /// Timer driving the autonomous spawn cycle.
    private var autonomousSpawnTimer: Timer?

    /// Wall-clock time when autonomous spawning started; used for difficulty ramp.
    private var autonomousStartTime: Date = Date()

    /// Cached on the main thread; updated by WorldViewController.viewDidLayoutSubviews.
    private var cachedViewSize: CGSize = UIScreen.main.bounds.size

    // MARK: - Init / attach

    init() {}

    /// Wire the coordinator to the views.  Must be called on the main thread.
    func attach(to arView: ARView, bugScene: BugHunterScene) {
        self.arView   = arView
        self.bugScene = bugScene
        if arView.bounds.size.height > 0 { cachedViewSize = arView.bounds.size }
        setupCamera(in: arView)
        startAutonomousSpawning()
    }

    // MARK: - RealityKit camera setup

    /// Places a perspective camera entity at (0, 0, cameraZ) looking toward Z = 0.
    /// PerspectiveCameraComponent is used in non-AR mode to control the view frustum.
    private func setupCamera(in arView: ARView) {
        let cam = Entity()
        cam.components.set(PerspectiveCameraComponent(
            near: 0.001, far: 1000,
            fieldOfViewInDegrees: ProjectorBug3DCoordinator.cameraFOV
        ))

        let cameraAnchor = AnchorEntity(world: matrix_identity_float4x4)
        cameraAnchor.position = SIMD3<Float>(0, 0, ProjectorBug3DCoordinator.cameraZ)
        cameraAnchor.addChild(cam)
        arView.scene.addAnchor(cameraAnchor)

        // Directional light from upper-right (replaces the former SCNLight directional setup).
        // Added to the scene root anchor so the light illuminates all bug entities uniformly.
        let dirLightEntity = Entity()
        var dirLight = DirectionalLightComponent(color: .white, intensity: 1200,
                                                  isRealWorldProxy: false)
        dirLightEntity.components.set(dirLight)
        // Tilt 45° down and 45° to the right to match original SCNLight euler angles.
        dirLightEntity.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(1, 0, 0))
            * simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))
        cameraAnchor.addChild(dirLightEntity)
    }

    // MARK: - Lifecycle

    func updateCachedViewSize(_ size: CGSize) {
        cachedViewSize = size
    }

    func stopSpawning() {
        autonomousSpawnTimer?.invalidate()
        autonomousSpawnTimer = nil

        // Remove all entity anchors from the RealityKit scene
        autonomousAnchors.forEach { arView?.scene.removeAnchor($0) }
        autonomousAnchors.removeAll()
        autonomousBugs.removeAll()

        bug3DAnchors.values.forEach { arView?.scene.removeAnchor($0) }
        bug3DAnchors.removeAll()
        bug3DNodes.removeAll()

        notifyBugCountChanged()
    }

    // MARK: - Phone-driven bug management

    /// Add a bug to the projector scene at the position derived from the phone's spawn angles.
    func addSyncedBug(id: String, type: BugType, normalizedX: Float, normalizedY: Float) {
        guard let arView else { return }

        let (halfW, halfH) = visibleHalfExtents()
        let x = normalizedX * halfW * 0.70
        let y = (normalizedY * 2.0 - 1.0) * halfH * 0.60

        let bug3D = Bug3DNode(type: type)
        let s = ProjectorBug3DCoordinator.bugScaleMultiplier

        // Place under a world AnchorEntity at the computed screen position.
        let bugAnchor = AnchorEntity(world: matrix_identity_float4x4)
        bugAnchor.position = SIMD3<Float>(x, y, 0)
        arView.scene.addAnchor(bugAnchor)
        bugAnchor.addChild(bug3D.entity)

        // Start small for pop-in effect; scale up to full size over 0.4 s.
        // Uses a Timer (not entity.move) to avoid conflicting with Bug3DNode's
        // own hover timer which independently modifies entity.position.y.
        bug3D.entity.scale = SIMD3<Float>(repeating: s * 0.1)
        let startTime = Date()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak bug3D] t in
            guard let bug3D else { t.invalidate(); return }
            let p = min(1.0, Float(Date().timeIntervalSince(startTime)) / 0.4)
            bug3D.entity.scale = SIMD3<Float>(repeating: s * 0.1 + (s - s * 0.1) * p)
            if p >= 1.0 { t.invalidate() }
        }

        bug3DNodes[id]   = bug3D
        bug3DAnchors[id] = bugAnchor
        notifyBugCountChanged()
    }

    func removeSyncedBug(id: String) {
        guard let bug3D     = bug3DNodes[id],
              let bugAnchor = bug3DAnchors[id] else { return }

        bug3D.captured()
        bug3DNodes.removeValue(forKey: id)
        bug3DAnchors.removeValue(forKey: id)
        notifyBugCountChanged()

        // Remove anchor after capture animation completes (~1.5 s).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak bugAnchor] in
            if let a = bugAnchor { self?.arView?.scene.removeAnchor(a) }
        }
    }

    // MARK: - Autonomous bug spawning

    /// Start the autonomous spawn cycle so the projector world is always alive.
    private func startAutonomousSpawning() {
        autonomousSpawnTimer?.invalidate()
        autonomousStartTime = Date()
        scheduleNextAutonomousSpawn(after: 1.5)
    }

    private func scheduleNextAutonomousSpawn(after delay: TimeInterval) {
        autonomousSpawnTimer?.invalidate()
        autonomousSpawnTimer = Timer.scheduledTimer(
            withTimeInterval: delay, repeats: false
        ) { [weak self] _ in self?.spawnAutonomousBug() }
    }

    private static let spawnMargin: Float = 1.25

    private func spawnAutonomousBug() {
        guard let arView else { return }

        let elapsed        = Date().timeIntervalSince(autonomousStartTime)
        let (halfW, halfH) = visibleHalfExtents()

        // Spawn at a random edge of the visible frustum
        let edge = Int.random(in: 0..<4)
        let startX: Float
        let startY: Float
        switch edge {
        case 0:  startX = Float.random(in: -halfW...halfW);  startY =  halfH * Self.spawnMargin
        case 1:  startX = Float.random(in: -halfW...halfW);  startY = -halfH * Self.spawnMargin
        case 2:  startX = -halfW * Self.spawnMargin;         startY = Float.random(in: -halfH...halfH)
        default: startX =  halfW * Self.spawnMargin;         startY = Float.random(in: -halfH...halfH)
        }

        let bugType = randomAutonomousBugType()
        let bug3D   = Bug3DNode(type: bugType)
        let s       = ProjectorBug3DCoordinator.bugScaleMultiplier

        let bugAnchor = AnchorEntity(world: matrix_identity_float4x4)
        bugAnchor.position = SIMD3<Float>(startX, startY, 0)
        arView.scene.addAnchor(bugAnchor)
        bugAnchor.addChild(bug3D.entity)

        bug3D.entity.scale = SIMD3<Float>(repeating: s * 0.05)
        autonomousBugs.append(bug3D)
        autonomousAnchors.append(bugAnchor)

        // Pop-in scale animation
        let scaleStart = Date()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak bug3D] t in
            guard let bug3D else { t.invalidate(); return }
            let p = min(1.0, Float(Date().timeIntervalSince(scaleStart)) / 0.5)
            bug3D.entity.scale = SIMD3<Float>(repeating: s * 0.05 + (s - s * 0.05) * p)
            if p >= 1.0 { t.invalidate() }
        }

        // Movement path: 2–3 interior waypoints then exit off-screen.
        // The anchor entity position is updated via move(to:) to avoid conflicting
        // with Bug3DNode's hover timer (which only modifies entity.position.y locally).
        let bugDuration  = max(4.0, min(600.0 / Double(bugType.speed), 14.0))
        let waypointCount = Int.random(in: 2...3)
        let segDur        = bugDuration / Double(waypointCount + 1)

        var cumulativeDelay: TimeInterval = 0

        for _ in 0..<waypointCount {
            let wx = Float.random(in: -halfW * 0.75 ... halfW * 0.75)
            let wy = Float.random(in: -halfH * 0.65 ... halfH * 0.65)
            let targetPos = SIMD3<Float>(wx, wy, 0)
            let delay     = cumulativeDelay
            cumulativeDelay += segDur

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak bugAnchor] in
                guard let bugAnchor else { return }
                bugAnchor.move(
                    to: Transform(scale: SIMD3<Float>(repeating: 1), rotation: simd_quatf(),
                                  translation: targetPos),
                    relativeTo: nil,
                    duration: segDur,
                    timingFunction: .easeInOut
                )
            }
        }

        // Exit toward the opposite edge
        let exitX = Float.random(in: -halfW * 0.8 ... halfW * 0.8)
        let exitY = Float.random(in: -halfH * 0.8 ... halfH * 0.8)
        let exitMargin = Self.spawnMargin * 1.04
        let exitPoint: SIMD3<Float>
        switch edge {
        case 0:  exitPoint = SIMD3<Float>(exitX, -halfH * exitMargin, 0)
        case 1:  exitPoint = SIMD3<Float>(exitX,  halfH * exitMargin, 0)
        case 2:  exitPoint = SIMD3<Float>( halfW * exitMargin, exitY, 0)
        default: exitPoint = SIMD3<Float>(-halfW * exitMargin, exitY, 0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + cumulativeDelay) { [weak bugAnchor] in
            bugAnchor?.move(
                to: Transform(scale: SIMD3<Float>(repeating: 1), rotation: simd_quatf(), translation: exitPoint),
                relativeTo: nil,
                duration: segDur,
                timingFunction: .easeIn
            )
        }

        // Remove on completion
        let totalDur = cumulativeDelay + segDur
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDur) { [weak self, weak bug3D, weak bugAnchor] in
            guard let self else { return }
            if let a = bugAnchor { self.arView?.scene.removeAnchor(a) }
            self.autonomousBugs.removeAll    { $0 === bug3D }
            self.autonomousAnchors.removeAll { $0 === bugAnchor }
            self.notifyBugCountChanged()
        }

        notifyBugCountChanged()

        let nextDelay = max(0.6, 1.8 - elapsed / 90.0)
        scheduleNextAutonomousSpawn(after: nextDelay)
    }

    private func randomAutonomousBugType() -> BugType {
        // stag (toy_drummer.usdz) is excluded to reduce rendering load.
        // Only the two lighter USDZ models are spawned.
        return Double.random(in: 0..<1) < 0.60 ? .butterfly : .beetle
    }

    private func notifyBugCountChanged() {
        let total = autonomousBugs.count + bug3DNodes.count
        bugScene?.updateWorldDistortion(bugCount: total)
    }

    // MARK: - Frustum helpers

    /// Half-width and half-height of the visible frustum at Z = 0 (world origin plane).
    /// Calculated from cameraFOV and cameraZ, matching the SceneKit convention.
    private func visibleHalfExtents() -> (halfW: Float, halfH: Float) {
        let fovRad = ProjectorBug3DCoordinator.cameraFOV * .pi / 180.0
        let halfH  = ProjectorBug3DCoordinator.cameraZ * tan(fovRad / 2)
        let aspect = Float(cachedViewSize.width / max(cachedViewSize.height, 1))
        return (halfH * aspect, halfH)
    }
}

// MARK: - ConnectedPlayersView

/// A semi-transparent UIView displayed in the bottom-right corner of the projector screen
/// showing the names and player-color indicators of all currently connected iOS controllers.
final class ConnectedPlayersView: UIView {

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

        update(players: [])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

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

