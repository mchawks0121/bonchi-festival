//
//  ARGameView.swift
//  bonchi-festival
//
//  iOS Controller: SwiftUI wrapper for AR 3D gameplay.
//
//  A container UIView holds two layers:
//    • ARSCNView (back)  — SceneKit 3-D scene rendered on top of the AR camera.
//      Each bug anchor is mapped to a Bug3DNode by the Coordinator.
//    • SKView (front, transparent) — presents ARBugScene for the crosshair,
//      lock-on ring, and score/timer HUD.
//
//  Every frame the Coordinator projects each Bug3DNode's world position into
//  viewport (UIKit) coordinates and updates a proxy SKNode ("bugContainer")
//  in the SpriteKit overlay.  ARBugScene uses those proxy positions for its
//  existing lock-on and capture logic unchanged.
//

import SwiftUI
import ARKit
import SceneKit
import SpriteKit

// MARK: - ARGameView

struct ARGameView: UIViewRepresentable {

    @EnvironmentObject var gameManager: GameManager

    func makeCoordinator() -> Coordinator { Coordinator(gameManager: gameManager) }

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: UIScreen.main.bounds)

        // ── 3-D AR layer (back) ───────────────────────────────────────────
        let arView = ARSCNView(frame: container.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.autoenablesDefaultLighting = true
        // Use ARKit's estimated scene lighting so PBR materials match the real environment
        arView.automaticallyUpdatesLighting = true
        // Smooth geometry edges for higher visual quality (リアルさ).
        arView.antialiasingMode = .multisampling4X
        arView.scene = SCNScene()
        // Boost IBL intensity so PBR metalness/roughness render correctly under typical
        // indoor lighting conditions estimated by ARKit (empirically tuned value).
        arView.scene.lightingEnvironment.intensity = Coordinator.pbrLightingIntensity
        container.addSubview(arView)
        context.coordinator.arView = arView
        arView.delegate = context.coordinator
        // Cache the view height for the render-thread projection
        // context.coordinator.cachedViewHeight = UIScreen.main.bounds.height

        // Pre-warm USDZ asset cache before the first bug spawns (即時性).
        // The first spawn is delayed ≥ 0.9 s; assets typically load in < 0.5 s on device.
        // If loading hasn't completed by spawn time, Bug3DNode automatically falls back
        // to procedural geometry — subsequent bugs will use the USDZ once cached.
        Bug3DNode.preloadAssets()

        let config = ARWorldTrackingConfiguration()
        arView.session.run(config)

        // ── SpriteKit overlay — crosshair / HUD (front, transparent) ─────
        let skView = SKView(frame: container.bounds)
        skView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        skView.backgroundColor = .clear
        skView.isOpaque = false
        skView.allowsTransparency = true
        container.addSubview(skView)
        context.coordinator.skView = skView

        if let scene = gameManager.arBugScene {
            scene.scaleMode = .resizeFill
            skView.presentScene(scene)
            context.coordinator.startSpawning()
        } else {
            // In the ready state the AR session runs but spawning hasn't started.
            // Attach the slingshot now so the player can see and use it immediately.
            context.coordinator.ensureSlingshotAttached()
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator

        // In the ready state: ensure the 3-D slingshot is attached and interactive
        // so the player can practice the gesture before the game starts.
        // The ARBugScene (and bug spawning) begin only when confirmReady() is called.
        if gameManager.state == .ready {
            coordinator.ensureSlingshotAttached()
            return
        }

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

    /// Drives AR-anchor-based bug spawning and maps each anchor to a
    /// Bug3DNode (SceneKit visual) and a proxy SKNode (SpriteKit overlay,
    /// used by ARBugScene for lock-on and proximity capture detection).
    final class Coordinator: NSObject, ARSCNViewDelegate {

        // MARK: Dependencies

        weak var gameManager: GameManager?
        weak var arView: ARSCNView?
        weak var skView: SKView?

        /// Cached view height (set on main thread) used by the render-thread
        /// position projection to avoid accessing UIKit from a background thread.
        private var cachedViewHeight: CGFloat = UIScreen.main.bounds.height

        // MARK: Anchor bookkeeping

        /// Protects all four anchor maps below.
        /// Accessed from both the main thread (spawning / capture) and the
        /// SceneKit rendering thread (ARSCNViewDelegate callbacks), so every
        /// read and write must be performed under this lock.
        private let mapLock = NSLock()

        /// Maps anchor UUID → BugType
        private var bugAnchorMap: [UUID: BugType] = [:]
        /// Maps proxy SKNode identity → ARAnchor (for capture removal)
        private var nodeAnchorMap: [ObjectIdentifier: ARAnchor] = [:]
        /// Maps anchor UUID → Bug3DNode (for capture animation)
        private var anchorBug3DNodeMap: [UUID: Bug3DNode] = [:]
        /// Maps anchor UUID → proxy SKNode (for per-frame position sync)
        private var anchorProxyNodeMap: [UUID: SKNode] = [:]

        // MARK: 3-D slingshot state

        /// The 3-D slingshot node attached to the camera's pointOfView.
        private var slingshotNode: SlingshotNode?
        /// Drag offset cached from the main-thread gesture (read on the render thread).
        /// Follows the same safe-read pattern as `cachedViewHeight`.
        private var cachedDragOffset: CGSize = .zero
        private var cachedIsDragging: Bool   = false
        /// Tracks whether the slingshot was in drag state on the last render frame,
        /// so we only call resetDrag() once after release.
        private var wasSlingshotDragging: Bool = false

        // MARK: Spawn geometry constants
        private static let minSpawnDistance:     Float  = 0.5
        private static let maxSpawnDistance:     Float  = 1.4
        private static let horizontalAngleRange: ClosedRange<Float> = -0.65...0.65  // ±~37°
        private static let verticalOffsetRange:  ClosedRange<Float> = -0.30...0.45

        // MARK: Distance-based scale constants
        /// Bugs are designed for this reference distance (m); scale = referenceDistance / actualDistance.
        private static let referenceDistance: Float = 3.0
        private static let minBugScale:       Float = 0.3
        private static let maxBugScale:       Float = 5.0

        // MARK: Spawn rate constants
        /// Maximum number of bugs alive at the same time.
        private static let maxActiveBugs: Int = 5
        /// Horizontal angle normalisation divisor (= max absolute angle value).
        private static let maxHorizontalAngle: Float = 0.65

        // MARK: Rendering quality constants
        /// IBL intensity multiplier for the AR scene. Empirically tuned so PBR metalness/
        /// roughness values render correctly under typical indoor lighting estimated by ARKit.
        static let pbrLightingIntensity: CGFloat = 1.5

        // MARK: Spawning

        private var isSpawning   = false
        private var spawnTimer: Timer?
        /// Seconds elapsed since spawning started (used for difficulty ramp).
        private var spawnElapsed: TimeInterval = 0
        /// Timestamp of the last spawn, for computing elapsed time.
        private var lastSpawnTime: Date?

        init(gameManager: GameManager) {
            self.gameManager = gameManager
        }

        // MARK: - Spawning control

        func startSpawning() {
            // Bugs spawn on the iPhone in standalone mode AND in projectorClient mode.
            // In projectorServer mode this device IS the projector, so no AR spawning.
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
            mapLock.unlock()

            // Cache view height on main thread for use during rendering
            if let h = arView?.bounds.height, h > 0 { cachedViewHeight = h }

            ensureSlingshotAttached()

            // Wire capture callback so ARBugScene can trigger anchor removal
            gameManager?.arBugScene?.onCaptureBug = { [weak self] node in
                self?.handleCapture(of: node)
            }

            scheduleNextSpawn(delay: 0.9)
        }

        /// Attaches the 3-D slingshot to the camera and wires drag/fire callbacks.
        /// Idempotent: no-op if the slingshot is already attached.
        /// Called in both `.ready` and `.playing` states so the slingshot is visible
        /// before the game timer starts.
        func ensureSlingshotAttached() {
            guard gameManager?.gameMode != .projectorServer else { return }
            guard slingshotNode == nil else { return }

            let sn = SlingshotNode()
            slingshotNode = sn
            // pointOfView may be nil this early; renderer(_:updateAtTime:) retries each frame.
            arView?.pointOfView?.addChildNode(sn)

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

            // Remove 3-D slingshot from the camera
            slingshotNode?.removeFromParentNode()
            slingshotNode = nil
            cachedDragOffset = .zero
            cachedIsDragging = false
            wasSlingshotDragging = false

            // Remove all 3-D bug nodes from the SceneKit scene
            mapLock.lock()
            let nodesToRemove = Array(anchorBug3DNodeMap.values)
            anchorBug3DNodeMap.removeAll()
            anchorProxyNodeMap.removeAll()
            bugAnchorMap.removeAll()
            nodeAnchorMap.removeAll()
            mapLock.unlock()
            nodesToRemove.forEach { $0.removeFromParentNode() }
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
                // Session not ready yet — retry shortly
                scheduleNextSpawn(delay: 0.4)
                return
            }

            // Enforce maximum simultaneous bug count.
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
            // In ARKit camera space −Z is forward.
            let localPos = simd_float4(
                distance * sin(horizontalAngle),
                verticalOffset,
                -distance * cos(horizontalAngle),
                1
            )
            // Use the calibrated world-origin transform when available so that bugs
            // always spawn centred on the pre-set reference position.  Fall back to
            // the live camera transform when no calibration has been performed.
            let baseTransform = gameManager?.worldOriginTransform ?? frame.camera.transform
            let worldPos = baseTransform * localPos

            var anchorTransform = matrix_identity_float4x4
            anchorTransform.columns.3 = worldPos

            let anchor = ARAnchor(name: "bug", transform: anchorTransform)
            mapLock.lock()
            bugAnchorMap[anchor.identifier] = bugType
            mapLock.unlock()
            arView.session.add(anchor: anchor)

            // Notify the projector so the same bug appears on the shared display.
            // normalizedX: horizontal angle → –1…1; normalizedY: vertical → 0…1.
            let normalizedX = horizontalAngle / Coordinator.maxHorizontalAngle
            let vertRange   = Coordinator.verticalOffsetRange
            let normalizedY = (verticalOffset - vertRange.lowerBound) /
                              (vertRange.upperBound - vertRange.lowerBound)
            gameManager?.sendBugSpawned(id: anchor.identifier.uuidString,
                                        type: bugType,
                                        normalizedX: normalizedX,
                                        normalizedY: Float(normalizedY))

            // Track actual elapsed time for the difficulty ramp.
            let now = Date()
            if let last = lastSpawnTime { spawnElapsed += now.timeIntervalSince(last) }
            lastSpawnTime = now

            // Progressive spawn interval: 3.5 s → 1.5 s over 75 s of game time.
            let nextDelay = max(1.5, 3.5 - spawnElapsed / 75.0)
            scheduleNextSpawn(delay: nextDelay)
        }

        private func randomBugType() -> BugType {
            switch Double.random(in: 0..<1) {
            case ..<0.60: return .butterfly
            case ..<0.90: return .beetle
            default:      return .stag
            }
        }

        // MARK: - Capture

        private func handleCapture(of node: SKNode) {
            mapLock.lock()
            let anchor = nodeAnchorMap[ObjectIdentifier(node)]
            mapLock.unlock()
            guard let anchor else { return }

            // Play dismissal animation on the 3-D visual (no lock needed — read-only SCNNode call)
            mapLock.lock()
            let bug3D = anchorBug3DNodeMap[anchor.identifier]
            mapLock.unlock()
            bug3D?.captured()

            // Notify the projector to remove the matching bug from its display.
            gameManager?.sendBugRemoved(id: anchor.identifier.uuidString)

            // Clean up all maps
            mapLock.lock()
            nodeAnchorMap.removeValue(forKey: ObjectIdentifier(node))
            anchorBug3DNodeMap.removeValue(forKey: anchor.identifier)
            anchorProxyNodeMap.removeValue(forKey: anchor.identifier)
            bugAnchorMap.removeValue(forKey: anchor.identifier)
            mapLock.unlock()

            // Remove proxy from the SpriteKit overlay and the AR anchor
            node.removeFromParent()
            arView?.session.remove(anchor: anchor)
        }

        // MARK: - ARSCNViewDelegate

        /// Returns a Bug3DNode for each bug anchor; also creates an invisible proxy
        /// SKNode and adds it to the ARBugScene overlay for lock-on / capture detection.
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            mapLock.lock()
            let bugType = bugAnchorMap[anchor.identifier]
            mapLock.unlock()
            guard let bugType else { return nil }

            // 3-D visual node placed at the anchor's world transform
            let bug3D = Bug3DNode(type: bugType)

            // Proxy SKNode in the SpriteKit overlay — used by ARBugScene for
            // lock-on tracking and proximity-based capture detection.
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
            nodeAnchorMap[ObjectIdentifier(proxy)] = anchor
            mapLock.unlock()

            DispatchQueue.main.async { [weak self] in
                guard let scene = self?.gameManager?.arBugScene else { return }
                proxy.alpha = 0
                scene.addChild(proxy)
                // Match the shorter Bug3DNode fade-in for a unified appearance (即時性).
                proxy.run(SKAction.fadeIn(withDuration: 0.25))
            }

            return bug3D
        }

        /// Projects all active Bug3DNode world positions into SpriteKit overlay
        /// coordinates and updates the corresponding proxy SKNode positions.
        /// Also applies distance-based scaling so bugs appear larger as the camera
        /// approaches them (scale = referenceDistance / cameraDistance).
        /// Also drives the 3-D slingshot node drag state each frame.
        /// Called on the SceneKit rendering thread; UI writes are batched to main.
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let arView = self.arView else { return }

            // Lazily attach SlingshotNode to pointOfView if it was not ready at startSpawning().
            if let sn = slingshotNode, sn.parent == nil {
                arView.pointOfView?.addChildNode(sn)
            }

            // Drive slingshot rubber-band animation from cached drag state.
            // Reading cachedDragOffset / cachedIsDragging from the render thread is safe by
            // the same convention as cachedViewHeight (written on main, read here).
            if cachedIsDragging {
                slingshotNode?.updateDrag(offset: cachedDragOffset, maxDrag: 220)
                wasSlingshotDragging = true
            } else if wasSlingshotDragging {
                slingshotNode?.resetDrag()
                wasSlingshotDragging = false
            }

            // Use the main-thread-cached view height to avoid accessing UIKit here.
            let viewHeight = cachedViewHeight

            // Camera world position for distance-based scaling.
            let cameraPos: simd_float3?
            if let col = arView.session.currentFrame?.camera.transform.columns.3 {
                cameraPos = simd_float3(col.x, col.y, col.z)
            } else {
                cameraPos = nil
            }

            // Take a snapshot of the maps under the lock so the render thread does
            // not race with main-thread mutations (e.g. capture, stopSpawning).
            mapLock.lock()
            let snapshot: [(Bug3DNode, SKNode)] = anchorBug3DNodeMap.compactMap { (id, bug3D) in
                guard let proxy = anchorProxyNodeMap[id] else { return nil }
                return (bug3D, proxy)
            }
            mapLock.unlock()

            var updates: [(SKNode, CGPoint)] = []
            for (bug3D, proxy) in snapshot {

                // Distance-based scale: closer → larger.
                if let cam = cameraPos {
                    let wp = bug3D.simdWorldPosition
                    let dist = simd_distance(cam, wp)
                    let s = max(Coordinator.minBugScale,
                               min(Coordinator.maxBugScale,
                                   Coordinator.referenceDistance / max(dist, 0.1)))
                    bug3D.simdScale = simd_float3(repeating: s)
                }

                let wp = bug3D.worldPosition
                let projected = arView.projectPoint(SCNVector3(wp.x, wp.y, wp.z))
                // Only include points in front of the camera (depth 0–1)
                guard projected.z > 0, projected.z < 1 else { continue }
                // Convert UIKit viewport coords → SpriteKit coords (flip Y)
                updates.append((proxy, CGPoint(
                    x: CGFloat(projected.x),
                    y: viewHeight - CGFloat(projected.y)
                )))
            }

            guard !updates.isEmpty else { return }
            DispatchQueue.main.async {
                for (proxy, pos) in updates {
                    proxy.position = pos
                }
            }
        }

        // MARK: - 3-D net launch

        /// Spawn a Net3DNode that flies forward from the slingshot in the direction
        /// indicated by the player's drag gesture.  Called on the main thread via
        /// the `onNetFired` callback wired during `startSpawning()`.
        func launchNet3D(dragOffset: CGSize, power: Float) {
            guard let arView = arView,
                  let cameraT = arView.session.currentFrame?.camera.transform else { return }

            // Camera basis vectors in world space.
            let fwd   = simd_float3(-cameraT.columns.2.x, -cameraT.columns.2.y, -cameraT.columns.2.z)
            let right = simd_float3( cameraT.columns.0.x,  cameraT.columns.0.y,  cameraT.columns.0.z)
            let up    = simd_float3( cameraT.columns.1.x,  cameraT.columns.1.y,  cameraT.columns.1.z)

            // Drag → directional bias (mirrors the 2-D launch convention in SlingshotView):
            //   pull right (positive width) → fire left (−right)
            //   pull down  (positive height)→ fire up   (+up)
            let maxDrag: Float  = 220
            let normX = Float(-dragOffset.width  / CGFloat(maxDrag))
            let normY = Float( dragOffset.height / CGFloat(maxDrag))
            let direction = simd_normalize(fwd + right * normX * 0.35 + up * normY * 0.35)

            // World-space origin at the slingshot fork position in camera space.
            let forkCam = simd_float4(0, -0.12, -0.28, 1)
            let forkW   = cameraT * forkCam
            let origin  = SCNVector3(forkW.x, forkW.y, forkW.z)

            let net = Net3DNode(playerIndex: 0)
            arView.scene.rootNode.addChildNode(net)
            net.launch(from: origin,
                       direction: SCNVector3(direction.x, direction.y, direction.z),
                       power: power) { [weak net] in
                net?.removeFromParentNode()
            }
        }

        /// Cleans up proxy when ARKit removes an anchor externally (e.g. session reset).
        func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
            mapLock.lock()
            let proxy = anchorProxyNodeMap[anchor.identifier]
            anchorProxyNodeMap.removeValue(forKey: anchor.identifier)
            anchorBug3DNodeMap.removeValue(forKey: anchor.identifier)
            if let proxy { nodeAnchorMap.removeValue(forKey: ObjectIdentifier(proxy)) }
            bugAnchorMap.removeValue(forKey: anchor.identifier)
            mapLock.unlock()
            if let proxy {
                DispatchQueue.main.async { proxy.removeFromParent() }
            }
        }
    }
}

