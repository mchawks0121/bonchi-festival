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
        arView.scene = SCNScene()
        container.addSubview(arView)
        context.coordinator.arView = arView
        arView.delegate = context.coordinator
        // Cache the view height for the render-thread projection
        // context.coordinator.cachedViewHeight = UIScreen.main.bounds.height

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

        /// Maps anchor UUID → BugType
        private var bugAnchorMap: [UUID: BugType] = [:]
        /// Maps proxy SKNode identity → ARAnchor (for capture removal)
        private var nodeAnchorMap: [ObjectIdentifier: ARAnchor] = [:]
        /// Maps anchor UUID → Bug3DNode (for capture animation)
        private var anchorBug3DNodeMap: [UUID: Bug3DNode] = [:]
        /// Maps anchor UUID → proxy SKNode (for per-frame position sync)
        private var anchorProxyNodeMap: [UUID: SKNode] = [:]

        // MARK: Spawn geometry constants
        private static let minSpawnDistance:     Float  = 1.2
        private static let maxSpawnDistance:     Float  = 2.8
        private static let horizontalAngleRange: ClosedRange<Float> = -0.65...0.65  // ±~37°
        private static let verticalOffsetRange:  ClosedRange<Float> = -0.30...0.45

        // MARK: Distance-based scale constants
        /// Bugs are designed for this reference distance (m); scale = referenceDistance / actualDistance.
        private static let referenceDistance: Float = 2.0
        private static let minBugScale:       Float = 0.3
        private static let maxBugScale:       Float = 3.0

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
            stopSpawning()
            isSpawning    = true
            spawnElapsed  = 0
            lastSpawnTime = Date()
            bugAnchorMap.removeAll()
            nodeAnchorMap.removeAll()
            anchorBug3DNodeMap.removeAll()
            anchorProxyNodeMap.removeAll()

            // Cache view height on main thread for use during rendering
            if let h = arView?.bounds.height, h > 0 { cachedViewHeight = h }

            // Wire capture callback so ARBugScene can trigger anchor removal
            gameManager?.arBugScene?.onCaptureBug = { [weak self] node in
                self?.handleCapture(of: node)
            }

            scheduleNextSpawn(delay: 0.9)
        }

        func stopSpawning() {
            isSpawning = false
            spawnTimer?.invalidate()
            spawnTimer = nil

            // Remove all 3-D bug nodes from the SceneKit scene
            anchorBug3DNodeMap.values.forEach { $0.removeFromParentNode() }
            anchorBug3DNodeMap.removeAll()
            anchorProxyNodeMap.removeAll()
            bugAnchorMap.removeAll()
            nodeAnchorMap.removeAll()
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
            let worldPos = frame.camera.transform * localPos

            var anchorTransform = matrix_identity_float4x4
            anchorTransform.columns.3 = worldPos

            let anchor = ARAnchor(name: "bug", transform: anchorTransform)
            bugAnchorMap[anchor.identifier] = bugType
            arView.session.add(anchor: anchor)

            // Track actual elapsed time for the difficulty ramp.
            let now = Date()
            if let last = lastSpawnTime { spawnElapsed += now.timeIntervalSince(last) }
            lastSpawnTime = now

            // Progressive spawn interval: 1.8 s → 0.6 s over 90 s of game time
            let nextDelay = max(0.6, 1.8 - spawnElapsed / 75.0)
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
            guard let anchor = nodeAnchorMap[ObjectIdentifier(node)] else { return }

            // Play dismissal animation on the 3-D visual
            anchorBug3DNodeMap[anchor.identifier]?.captured()

            // Clean up all maps
            nodeAnchorMap.removeValue(forKey: ObjectIdentifier(node))
            anchorBug3DNodeMap.removeValue(forKey: anchor.identifier)
            anchorProxyNodeMap.removeValue(forKey: anchor.identifier)
            bugAnchorMap.removeValue(forKey: anchor.identifier)

            // Remove proxy from the SpriteKit overlay and the AR anchor
            node.removeFromParent()
            arView?.session.remove(anchor: anchor)
        }

        // MARK: - ARSCNViewDelegate

        /// Returns a Bug3DNode for each bug anchor; also creates an invisible proxy
        /// SKNode and adds it to the ARBugScene overlay for lock-on / capture detection.
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard let bugType = bugAnchorMap[anchor.identifier] else { return nil }

            // 3-D visual node placed at the anchor's world transform
            let bug3D = Bug3DNode(type: bugType)
            anchorBug3DNodeMap[anchor.identifier] = bug3D

            // Proxy SKNode in the SpriteKit overlay — used by ARBugScene for
            // lock-on tracking and proximity-based capture detection.
            // An invisible BugNode child preserves the correct `points` value.
            let proxy = SKNode()
            proxy.name = "bugContainer"
            let invisibleBug = BugNode(type: bugType)
            invisibleBug.physicsBody = nil
            invisibleBug.alpha = 0
            proxy.addChild(invisibleBug)

            anchorProxyNodeMap[anchor.identifier] = proxy
            nodeAnchorMap[ObjectIdentifier(proxy)] = anchor

            DispatchQueue.main.async { [weak self] in
                guard let scene = self?.gameManager?.arBugScene else { return }
                proxy.alpha = 0
                scene.addChild(proxy)
                proxy.run(SKAction.fadeIn(withDuration: 0.5))
            }

            return bug3D
        }

        /// Projects all active Bug3DNode world positions into SpriteKit overlay
        /// coordinates and updates the corresponding proxy SKNode positions.
        /// Also applies distance-based scaling so bugs appear larger as the camera
        /// approaches them (scale = referenceDistance / cameraDistance).
        /// Called on the SceneKit rendering thread; UI writes are batched to main.
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let arView = self.arView else { return }

            // Use the main-thread-cached view height to avoid accessing UIKit here.
            let viewHeight = cachedViewHeight

            // Camera world position for distance-based scaling.
            let cameraPos: simd_float3?
            if let col = arView.session.currentFrame?.camera.transform.columns.3 {
                cameraPos = simd_float3(col.x, col.y, col.z)
            } else {
                cameraPos = nil
            }

            var updates: [(SKNode, CGPoint)] = []
            for (anchorID, bug3D) in anchorBug3DNodeMap {
                guard let proxy = anchorProxyNodeMap[anchorID] else { continue }

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

        /// Cleans up proxy when ARKit removes an anchor externally (e.g. session reset).
        func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
            guard let proxy = anchorProxyNodeMap[anchor.identifier] else { return }
            DispatchQueue.main.async { proxy.removeFromParent() }
            anchorProxyNodeMap.removeValue(forKey: anchor.identifier)
            anchorBug3DNodeMap.removeValue(forKey: anchor.identifier)
            nodeAnchorMap.removeValue(forKey: ObjectIdentifier(proxy))
            bugAnchorMap.removeValue(forKey: anchor.identifier)
        }
    }
}

