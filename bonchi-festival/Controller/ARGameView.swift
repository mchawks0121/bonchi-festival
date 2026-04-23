//
//  ARGameView.swift
//  bonchi-festival
//
//  iOS Controller: SwiftUI wrapper for AR 3D gameplay.
//
//  Implementation intent:
//    Rewritten to use RealityKit (no SceneKit) as required.
//    ARView replaces ARSCNView; ARSessionDelegate replaces ARSCNViewDelegate.
//    SceneEvents.Update subscription replaces ARSCNViewDelegate.renderer(updateAtTime:).
//    Bug3DNode.entity (Entity) is added to AnchorEntity(anchor:) in the RealityKit scene.
//    SlingshotNode.entity is attached via AnchorEntity(.camera).
//
//  A container UIView holds two layers:
//    • ARView (back)  — RealityKit scene rendered on top of the AR camera.
//    • SKView (front, transparent) — presents ARBugScene for the crosshair,
//      lock-on ring, and score/timer HUD.
//
//  Every frame the Coordinator projects each Bug3DNode's world position via
//  ARView.project(_:) into viewport coordinates and updates the corresponding
//  proxy SKNode in the SpriteKit overlay.  ARBugScene uses those proxy positions
//  for its existing lock-on and capture logic unchanged.
//
//  Security considerations:
//    No arbitrary data processing; only positions from ARKit transforms.
//    NSLock protects all anchor maps from main/session-thread data races.
//
//  Constraints:
//    SceneKit (SCNNode, ARSCNView, ARSCNViewDelegate, etc.) must NOT be used.
//

import SwiftUI
import ARKit
import RealityKit
import SpriteKit
import Combine

// MARK: - ARGameView

struct ARGameView: UIViewRepresentable {

    @EnvironmentObject var gameManager: GameManager

    func makeCoordinator() -> Coordinator { Coordinator(gameManager: gameManager) }

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: UIScreen.main.bounds)

        // ── RealityKit AR layer (back) ────────────────────────────────────
        let arView = ARView(frame: container.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Enable environment-based lighting so PBR materials react to real-world light.
        arView.environment.lighting.intensityExponent = 1.0
        arView.renderOptions = []  // no special render-option overrides needed
        // Disable all debug overlays (feature points, anchor geometry, etc.) to
        // prevent any debug visualizations from appearing in the AR view.
        arView.debugOptions = []
        container.addSubview(arView)
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator

        // Pre-warm USDZ asset cache before the first bug spawns (即時性).
        Bug3DNode.preloadAssets()

        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic  // enables PBR environment reflections
        arView.session.run(config)

        // ── SpriteKit overlay — crosshair / HUD (front, transparent) ─────
        let skView = SKView(frame: container.bounds)
        skView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        skView.backgroundColor  = .clear
        skView.isOpaque         = false
        skView.allowsTransparency = true
        container.addSubview(skView)
        context.coordinator.skView = skView

        if let scene = gameManager.arBugScene {
            scene.scaleMode = .resizeFill
            skView.presentScene(scene)
            context.coordinator.startSpawning()
        } else {
            // In the ready state the AR session runs but spawning hasn't started yet.
            // Attach the slingshot now so the player can see and use it immediately.
            context.coordinator.ensureSlingshotAttached()
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator

        if let scene = gameManager.arBugScene,
           coordinator.skView?.scene !== scene {
            scene.scaleMode = .resizeFill
            coordinator.skView?.presentScene(scene,
                                             transition: SKTransition.fade(withDuration: 0.25))
            coordinator.startSpawning()
        } else if gameManager.arBugScene == nil {
            coordinator.stopSpawning()
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopSpawning()
        coordinator.arView?.session.pause()
    }
}

// MARK: - Coordinator

extension ARGameView {

    /// Drives AR-anchor-based bug spawning and maps each anchor to a Bug3DNode
    /// (RealityKit Entity visual) and a proxy SKNode (SpriteKit overlay,
    /// used by ARBugScene for lock-on and proximity capture detection).
    final class Coordinator: NSObject, ARSessionDelegate {

        // MARK: Dependencies

        weak var gameManager: GameManager?
        weak var arView: ARView?
        weak var skView: SKView?

        // MARK: Anchor bookkeeping
        //
        // All four maps are read/written from both the main thread and the
        // ARSessionDelegate queue, so every access is performed under mapLock.

        /// Protects all anchor maps against concurrent access.
        private let mapLock = NSLock()
        /// Maps anchor UUID → BugType
        private var bugAnchorMap:       [UUID: BugType]         = [:]
        /// Maps proxy SKNode identity → ARAnchor (for capture removal)
        private var nodeAnchorMap:      [ObjectIdentifier: ARAnchor] = [:]
        /// Maps anchor UUID → Bug3DNode entity (for capture animation)
        private var anchorBug3DNodeMap: [UUID: Bug3DNode]        = [:]
        /// Maps anchor UUID → proxy SKNode (for per-frame position sync)
        private var anchorProxyNodeMap: [UUID: SKNode]           = [:]
        /// Maps anchor UUID → RealityKit AnchorEntity (for removal from scene)
        private var anchorEntityMap:    [UUID: AnchorEntity]     = [:]

        // MARK: 3-D slingshot state

        private var slingshotNode:        SlingshotNode?
        /// Camera-tracking AnchorEntity to which the slingshot entity is attached.
        private var slingshotCameraAnchor: AnchorEntity?
        /// Drag state cached on the main thread; read during SceneEvents.Update.
        private var cachedDragOffset:      CGSize = .zero
        private var cachedIsDragging:      Bool   = false
        private var wasSlingshotDragging:  Bool   = false

        // MARK: Spawn geometry constants
        private static let minSpawnDistance:     Float  = 0.5
        private static let maxSpawnDistance:     Float  = 1.4
        private static let horizontalAngleRange: ClosedRange<Float> = -0.65...0.65
        private static let verticalOffsetRange:  ClosedRange<Float> = -0.30...0.45
        private static let referenceDistance:    Float  = 3.0
        private static let minBugScale:          Float  = 0.3
        private static let maxBugScale:          Float  = 5.0
        private static let maxActiveBugs:        Int    = 5
        private static let maxHorizontalAngle:   Float  = 0.65

        // MARK: Spawning

        private var isSpawning:   Bool     = false
        private var spawnTimer:   Timer?
        private var spawnElapsed: TimeInterval = 0
        private var lastSpawnTime: Date?

        // MARK: SceneEvents.Update subscription (replaces ARSCNViewDelegate.renderer)
        // Fires on the main thread every rendered frame.
        private var updateSubscription: Cancellable?

        init(gameManager: GameManager) {
            self.gameManager = gameManager
        }

        // MARK: - Spawning control

        func startSpawning() {
            guard gameManager?.gameMode != .projectorServer else { return }
            stopSpawning()
            isSpawning    = true
            spawnElapsed  = 0
            lastSpawnTime = Date()
            mapLock.lock()
            bugAnchorMap.removeAll()
            nodeAnchorMap.removeAll()
            anchorBug3DNodeMap.removeAll()
            anchorProxyNodeMap.removeAll()
            anchorEntityMap.removeAll()
            mapLock.unlock()

            ensureSlingshotAttached()

            // Wire capture callbacks so ARBugScene can drive the capture flow:
            // - onBugCaptured3D: fires ~0.20 s after capture to start the 3-D animation
            // - onCaptureBug:    fires at healingAnimationDuration to remove the anchor
            gameManager?.arBugScene?.onBugCaptured3D = { [weak self] node in
                self?.startBug3DCaptureAnimation(of: node)
            }
            gameManager?.arBugScene?.onCaptureBug = { [weak self] node in
                self?.handleCapture(of: node)
            }

            // Subscribe to per-frame updates on the main thread.
            // SceneEvents.Update replaces ARSCNViewDelegate.renderer(_:updateAtTime:).
            updateSubscription = arView?.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                self?.handleSceneUpdate()
            }

            // Plant forest tree entities around the spawn origin to create
            // the "bug hunting in a forest" atmosphere (即時性).
            if let view = arView {
                ForestEnvironment.plantARTrees(in: view,
                                              origin: gameManager?.worldOriginTransform)
            }

            scheduleNextSpawn(delay: 0.9)
        }

        /// Attaches the 3-D slingshot to the camera and wires drag/fire callbacks.
        /// Idempotent: no-op if the slingshot is already attached.
        func ensureSlingshotAttached() {
            guard gameManager?.gameMode != .projectorServer else { return }
            guard slingshotNode == nil else { return }

            let sn = SlingshotNode()
            slingshotNode = sn

            // AnchorEntity(.camera) keeps the slingshot fixed in the camera view frustum.
            guard let arView else { return }
            let cameraAnchor = AnchorEntity(.camera)
            arView.scene.addAnchor(cameraAnchor)
            cameraAnchor.addChild(sn.entity)
            slingshotCameraAnchor = cameraAnchor

            gameManager?.slingshotDragUpdate = { [weak self] offset, isDragging in
                self?.cachedDragOffset = offset
                self?.cachedIsDragging = isDragging
            }
            gameManager?.onNetFired = { [weak self] dragOffset, power in
                self?.launchNet3D(dragOffset: dragOffset, power: power)
            }
        }

        func stopSpawning() {
            isSpawning = false
            spawnTimer?.invalidate()
            spawnTimer = nil
            updateSubscription?.cancel()
            updateSubscription = nil

            // Remove slingshot camera anchor from the RealityKit scene
            if let ca = slingshotCameraAnchor {
                arView?.scene.removeAnchor(ca)
                slingshotCameraAnchor = nil
            }
            slingshotNode = nil
            cachedDragOffset    = .zero
            cachedIsDragging    = false
            wasSlingshotDragging = false

            // Remove all bug entities from the RealityKit scene
            mapLock.lock()
            let entitiesToRemove = Array(anchorEntityMap.values)
            anchorBug3DNodeMap.removeAll()
            anchorProxyNodeMap.removeAll()
            bugAnchorMap.removeAll()
            nodeAnchorMap.removeAll()
            anchorEntityMap.removeAll()
            mapLock.unlock()

            entitiesToRemove.forEach { arView?.scene.removeAnchor($0) }
        }

        private func scheduleNextSpawn(delay: TimeInterval) {
            guard isSpawning else { return }
            spawnTimer?.invalidate()
            spawnTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.spawnBug()
            }
        }

        private func spawnBug() {
            guard isSpawning,
                  let arView,
                  let frame = arView.session.currentFrame else {
                scheduleNextSpawn(delay: 0.4)
                return
            }

            mapLock.lock()
            let currentBugCount = bugAnchorMap.count
            mapLock.unlock()
            guard currentBugCount < Coordinator.maxActiveBugs else {
                scheduleNextSpawn(delay: 1.0)
                return
            }

            let bugType         = randomBugType()
            let distance        = Float.random(in: Coordinator.minSpawnDistance...Coordinator.maxSpawnDistance)
            let horizontalAngle = Float.random(in: Coordinator.horizontalAngleRange)
            let verticalOffset  = Float.random(in: Coordinator.verticalOffsetRange)

            // Transform local camera-space position → world space.
            // In ARKit/RealityKit camera space, −Z is forward.
            let localPos = simd_float4(
                distance * sin(horizontalAngle),
                verticalOffset,
                -distance * cos(horizontalAngle),
                1
            )
            let baseTransform = gameManager?.worldOriginTransform ?? frame.camera.transform
            let worldPos      = baseTransform * localPos

            var anchorTransform = matrix_identity_float4x4
            anchorTransform.columns.3 = worldPos

            let anchor = ARAnchor(name: "bug", transform: anchorTransform)
            mapLock.lock()
            bugAnchorMap[anchor.identifier] = bugType
            mapLock.unlock()
            arView.session.add(anchor: anchor)

            let normalizedX = horizontalAngle / Coordinator.maxHorizontalAngle
            let vertRange   = Coordinator.verticalOffsetRange
            let normalizedY = (verticalOffset - vertRange.lowerBound) /
                              (vertRange.upperBound - vertRange.lowerBound)
            gameManager?.sendBugSpawned(id: anchor.identifier.uuidString,
                                         type: bugType,
                                         normalizedX: normalizedX,
                                         normalizedY: Float(normalizedY))

            let now = Date()
            if let last = lastSpawnTime { spawnElapsed += now.timeIntervalSince(last) }
            lastSpawnTime = now

            let nextDelay = max(1.5, 3.5 - spawnElapsed / 75.0)
            scheduleNextSpawn(delay: nextDelay)
        }

        private func randomBugType() -> BugType {
            // stag (toy_drummer.usdz) is excluded to reduce rendering load.
            // Only the two lighter USDZ models are spawned.
            return Double.random(in: 0..<1) < 0.60 ? .butterfly : .beetle
        }

        // MARK: - ARSessionDelegate
        //
        // session(_:didAdd:) and session(_:didRemove:) are called on the ARKit session queue.
        // All entity/scene modifications are dispatched to the main thread.

        /// Creates a Bug3DNode entity and proxy SKNode for each recognised bug anchor.
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                mapLock.lock()
                let bugType = bugAnchorMap[anchor.identifier]
                mapLock.unlock()
                guard let bugType else { continue }

                // All RealityKit scene modifications must happen on the main thread.
                DispatchQueue.main.async { [weak self] in
                    self?.addBugEntity(for: anchor, bugType: bugType)
                }
            }
        }

        /// Called when ARKit removes anchors (e.g. session reset). Cleans up entities and proxies.
        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            for anchor in anchors {
                mapLock.lock()
                let proxy        = anchorProxyNodeMap[anchor.identifier]
                let anchorEntity = anchorEntityMap[anchor.identifier]
                anchorProxyNodeMap.removeValue(forKey: anchor.identifier)
                anchorBug3DNodeMap.removeValue(forKey: anchor.identifier)
                anchorEntityMap.removeValue(forKey: anchor.identifier)
                if let proxy { nodeAnchorMap.removeValue(forKey: ObjectIdentifier(proxy)) }
                bugAnchorMap.removeValue(forKey: anchor.identifier)
                mapLock.unlock()

                DispatchQueue.main.async { [weak self] in
                    proxy?.removeFromParent()
                    if let ae = anchorEntity { self?.arView?.scene.removeAnchor(ae) }
                }
            }
        }

        /// Creates the Bug3DNode entity + AnchorEntity pair and proxy SKNode.
        /// Must be called on the main thread.
        private func addBugEntity(for anchor: ARAnchor, bugType: BugType) {
            guard let arView else { return }

            // Bug3DNode: RealityKit entity with USDZ model + availableAnimations loop.
            let bug3D = Bug3DNode(type: bugType)

            // AnchorEntity tracking the ARKit anchor — tracks the world-space position.
            let anchorEntity = AnchorEntity(anchor: anchor)
            anchorEntity.addChild(bug3D.entity)
            arView.scene.addAnchor(anchorEntity)

            // Proxy SKNode in the SpriteKit overlay for lock-on / capture detection.
            // An invisible BugNode child preserves the correct `points` value.
            let proxy = SKNode()
            proxy.name = "bugContainer"
            let invisibleBug = BugNode(type: bugType)
            invisibleBug.physicsBody = nil
            invisibleBug.alpha = 0
            proxy.addChild(invisibleBug)

            mapLock.lock()
            anchorBug3DNodeMap[anchor.identifier] = bug3D
            anchorProxyNodeMap[anchor.identifier] = proxy
            anchorEntityMap[anchor.identifier]    = anchorEntity
            nodeAnchorMap[ObjectIdentifier(proxy)] = anchor
            mapLock.unlock()

            proxy.alpha = 0
            if let scene = gameManager?.arBugScene {
                scene.addChild(proxy)
                proxy.run(SKAction.fadeIn(withDuration: 0.25))
            }
        }

        // MARK: - Per-frame scene update (replaces ARSCNViewDelegate.renderer(updateAtTime:))

        /// Fires on the main thread every rendered frame via SceneEvents.Update subscription.
        /// Projects each bug entity's world position to screen coordinates and updates
        /// the corresponding proxy SKNode. Also drives the slingshot drag animation.
        private func handleSceneUpdate() {
            guard let arView else { return }

            // Drive slingshot rubber-band animation from cached drag state.
            if cachedIsDragging {
                slingshotNode?.updateDrag(offset: cachedDragOffset, maxDrag: 300)
                wasSlingshotDragging = true
            } else if wasSlingshotDragging {
                slingshotNode?.resetDrag()
                wasSlingshotDragging = false
            }

            // Camera world position for distance-based scaling.
            let cameraPos = arView.cameraTransform.translation
            let viewHeight = arView.bounds.height

            // Snapshot the maps to avoid holding the lock while iterating.
            mapLock.lock()
            let snapshot: [(Bug3DNode, SKNode)] = anchorBug3DNodeMap.compactMap { (id, bug3D) in
                guard let proxy = anchorProxyNodeMap[id] else { return nil }
                return (bug3D, proxy)
            }
            mapLock.unlock()

            for (bug3D, proxy) in snapshot {
                // Distance-based scale: closer → larger, clamped to min/max.
                let wp   = bug3D.entity.position(relativeTo: nil)
                let dist = simd_distance(cameraPos, wp)
                let s    = max(Coordinator.minBugScale,
                               min(Coordinator.maxBugScale,
                                   Coordinator.referenceDistance / max(dist, 0.1)))
                bug3D.entity.scale = SIMD3<Float>(repeating: s)

                // Project world position to 2-D screen point.
                // ARView.project(_:) returns nil when the point is behind the camera.
                guard let screenPoint = arView.project(wp) else { continue }

                // Convert UIKit top-left origin to SpriteKit bottom-left origin (flip Y).
                proxy.position = CGPoint(x: screenPoint.x,
                                         y: viewHeight - screenPoint.y)
            }
        }

        // MARK: - Capture

        /// Starts the 3-D struggle animation on the Bug3DNode that corresponds
        /// to `node` (the SpriteKit proxy container).
        /// The bug entity is reparented to a world AnchorEntity so its animation
        /// continues after the tracking ARAnchor is later removed.
        /// Called ~0.20 s after capture so the animation aligns with the net landing.
        private func startBug3DCaptureAnimation(of node: SKNode) {
            mapLock.lock()
            let anchor = nodeAnchorMap[ObjectIdentifier(node)]
            mapLock.unlock()
            guard let anchor else { return }

            // Remove from map immediately so handleCapture() won't start a duplicate animation.
            mapLock.lock()
            let bug3D = anchorBug3DNodeMap.removeValue(forKey: anchor.identifier)
            mapLock.unlock()

            if let bug3D, let arView {
                reparentToCaptureAnchor(bug3D, in: arView)
                bug3D.captured()
            }

            gameManager?.sendBugRemoved(id: anchor.identifier.uuidString)
        }

        private func handleCapture(of node: SKNode) {
            mapLock.lock()
            let anchor = nodeAnchorMap[ObjectIdentifier(node)]
            mapLock.unlock()
            guard let anchor else { return }

            // If startBug3DCaptureAnimation() was not called for any reason, handle it here.
            mapLock.lock()
            let bug3D = anchorBug3DNodeMap.removeValue(forKey: anchor.identifier)
            mapLock.unlock()
            if let bug3D, let arView {
                reparentToCaptureAnchor(bug3D, in: arView)
                bug3D.captured()
                gameManager?.sendBugRemoved(id: anchor.identifier.uuidString)
            }

            // Clean up remaining maps and remove proxy / anchor
            mapLock.lock()
            let proxy        = anchorProxyNodeMap[anchor.identifier]
            let anchorEntity = anchorEntityMap[anchor.identifier]
            nodeAnchorMap.removeValue(forKey: ObjectIdentifier(node))
            anchorProxyNodeMap.removeValue(forKey: anchor.identifier)
            anchorEntityMap.removeValue(forKey: anchor.identifier)
            bugAnchorMap.removeValue(forKey: anchor.identifier)
            mapLock.unlock()

            proxy?.removeFromParent()
            if let ae = anchorEntity { arView?.scene.removeAnchor(ae) }
            arView?.session.remove(anchor: anchor)
        }

        /// Reparents `bug3D.entity` from its tracking AnchorEntity to a standalone
        /// world AnchorEntity so the capture animation persists after the AR anchor
        /// is removed from the session.
        private func reparentToCaptureAnchor(_ bug3D: Bug3DNode, in arView: ARView) {
            let worldPos   = bug3D.entity.position(relativeTo: nil)
            let worldRot   = bug3D.entity.orientation(relativeTo: nil)
            let worldScale = bug3D.entity.scale     // preserve current distance-based scale

            bug3D.entity.removeFromParent()

            // Place the world anchor at the bug's current position (identity rotation/scale).
            var anchorTransform = matrix_identity_float4x4
            anchorTransform.columns.3 = SIMD4<Float>(worldPos.x, worldPos.y, worldPos.z, 1)
            let captureAnchor = AnchorEntity(world: anchorTransform)
            arView.scene.addAnchor(captureAnchor)
            captureAnchor.addChild(bug3D.entity)

            // Restore world-space orientation and scale on the re-parented entity.
            bug3D.entity.position    = .zero
            bug3D.entity.orientation = worldRot
            bug3D.entity.scale       = worldScale

            // Remove the empty capture anchor after the animation completes (~1.5 s).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak arView, weak captureAnchor] in
                if let ca = captureAnchor { arView?.scene.removeAnchor(ca) }
            }
        }

        // MARK: - 3-D net launch

        /// Spawns a Net3DNode entity that flies forward from the slingshot.
        /// Called on the main thread via the `onNetFired` callback.
        func launchNet3D(dragOffset: CGSize, power: Float) {
            guard let arView else { return }

            let cameraT: simd_float4x4
            if let frame = arView.session.currentFrame {
                cameraT = frame.camera.transform
            } else {
                // Fall back to the camera anchor's world transform if no frame available yet.
                cameraT = arView.cameraTransform.matrix
            }

            // Camera basis vectors in world space.
            // In ARKit/RealityKit the camera looks in the −Z direction.
            let fwd   = SIMD3<Float>(-cameraT.columns.2.x, -cameraT.columns.2.y, -cameraT.columns.2.z)
            let right = SIMD3<Float>( cameraT.columns.0.x,  cameraT.columns.0.y,  cameraT.columns.0.z)
            let up    = SIMD3<Float>( cameraT.columns.1.x,  cameraT.columns.1.y,  cameraT.columns.1.z)

            // Drag → directional bias (mirrors the 2-D launch convention in SlingshotView).
            let maxDrag: Float = 300
            let normX = Float(-dragOffset.width  / CGFloat(maxDrag))
            let normY = Float( dragOffset.height / CGFloat(maxDrag))
            let direction = simd_normalize(fwd + right * normX * 0.35 + up * normY * 0.35)

            // World-space origin at the slingshot fork position.
            let forkCam = simd_float4(0, -0.12, -0.28, 1)
            let forkW   = cameraT * forkCam
            let origin  = SIMD3<Float>(forkW.x, forkW.y, forkW.z)

            // Place net entity under a world AnchorEntity at world origin.
            // The net's own position property is updated by its flight timer.
            let netAnchor = AnchorEntity(world: matrix_identity_float4x4)
            arView.scene.addAnchor(netAnchor)

            let net = Net3DNode(playerIndex: 0)
            netAnchor.addChild(net.entity)

            net.launch(from: origin, direction: direction, power: power) { [weak arView, weak netAnchor] in
                // Remove the net anchor (and its net entity child) after the flight ends.
                if let na = netAnchor { arView?.scene.removeAnchor(na) }
            }
        }
    }
}
