//
//  ARGameView.swift
//  bonchi-festival
//
//  iOS Controller: SwiftUI wrapper for ARSKView.
//
//  The Coordinator implements ARSKViewDelegate so that each BugARAnchor
//  (added to the AR session by the spawning timer) is mapped to a BugNode
//  sprite.  ARKit updates the sprite's 2D position every frame to match the
//  projected 3D anchor position, making bugs appear to inhabit real space.
//
//  The player moves their phone to aim the crosshair (drawn by ARBugScene)
//  at a bug, then releases the slingshot to throw the net.
//

import SwiftUI
import ARKit
import SpriteKit

// MARK: - ARGameView

struct ARGameView: UIViewRepresentable {

    @EnvironmentObject var gameManager: GameManager

    func makeCoordinator() -> Coordinator { Coordinator(gameManager: gameManager) }

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> ARSKView {
        let arView = ARSKView(frame: .zero)
        arView.ignoresSiblingOrder = true
        arView.delegate = context.coordinator
        context.coordinator.arView = arView

        // Start world tracking (no plane detection needed)
        let config = ARWorldTrackingConfiguration()
        arView.session.run(config)

        // Present scene if the game has already started
        if let scene = gameManager.arBugScene {
            scene.scaleMode = .resizeFill
            arView.presentScene(scene)
            context.coordinator.startSpawning()
        }

        return arView
    }

    func updateUIView(_ uiView: ARSKView, context: Context) {
        if let scene = gameManager.arBugScene, uiView.scene !== scene {
            // New game started — present fresh scene and begin spawning
            scene.scaleMode = .resizeFill
            uiView.presentScene(scene, transition: SKTransition.fade(withDuration: 0.25))
            context.coordinator.startSpawning()
        } else if gameManager.arBugScene == nil {
            context.coordinator.stopSpawning()
        }
    }

    static func dismantleUIView(_ uiView: ARSKView, coordinator: Coordinator) {
        coordinator.stopSpawning()
        uiView.session.pause()
    }
}

// MARK: - Coordinator

extension ARGameView {

    /// Drives AR-anchor-based bug spawning and maps anchors → BugNode sprites.
    final class Coordinator: NSObject, ARSKViewDelegate {

        // MARK: Dependencies

        weak var gameManager: GameManager?
        weak var arView: ARSKView?

        // MARK: Anchor bookkeeping

        /// Maps anchor UUID → BugType (consulted in view(_:nodeFor:))
        private var bugAnchorMap: [UUID: BugType] = [:]

        /// Maps node ObjectIdentifier → ARAnchor (for capture removal)
        private var nodeAnchorMap: [ObjectIdentifier: ARAnchor] = [:]

        // MARK: Spawn geometry constants
        private static let minSpawnDistance:     Float  = 1.2
        private static let maxSpawnDistance:     Float  = 2.8
        private static let horizontalAngleRange: ClosedRange<Float> = -0.65...0.65  // ±~37 °
        private static let verticalOffsetRange:  ClosedRange<Float> = -0.30...0.45

        // MARK: Spawning

        private var isSpawning  = false
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
            // Initialize to now so the initial 0.9 s delay is counted in spawnElapsed
        lastSpawnTime = Date()
            bugAnchorMap.removeAll()
            nodeAnchorMap.removeAll()

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

            let bugType  = randomBugType()
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
            nodeAnchorMap.removeValue(forKey: ObjectIdentifier(node))
            bugAnchorMap.removeValue(forKey: anchor.identifier)
            arView?.session.remove(anchor: anchor)
        }

        // MARK: - ARSKViewDelegate

        func view(_ view: ARSKView, nodeFor anchor: ARAnchor) -> SKNode? {
            guard let bugType = bugAnchorMap[anchor.identifier] else { return nil }

            // Container node — its 2D position is updated by ARKit every frame
            let container = SKNode()
            container.name = "bugContainer"

            // ── Visual bug node (child; animated independently) ────────────
            let bugNode = BugNode(type: bugType)
            bugNode.physicsBody = nil
            container.addChild(bugNode)

            // Gentle vertical bob
            let bobUp   = SKAction.moveBy(x: 0, y: 10, duration: 0.65)
            let bobDown = SKAction.moveBy(x: 0, y: -10, duration: 0.65)
            bobUp.timingMode   = .easeInEaseOut
            bobDown.timingMode = .easeInEaseOut
            bugNode.run(SKAction.repeatForever(SKAction.sequence([bobUp, bobDown])))

            // Idle wobble
            let wobbleL = SKAction.rotate(byAngle:  0.12, duration: 0.5)
            let wobbleR = SKAction.rotate(byAngle: -0.12, duration: 0.5)
            wobbleL.timingMode = .easeInEaseOut
            wobbleR.timingMode = .easeInEaseOut
            bugNode.run(SKAction.repeatForever(SKAction.sequence([wobbleL, wobbleR])))

            // Store mapping for anchor removal
            nodeAnchorMap[ObjectIdentifier(container)] = anchor

            return container
        }

        /// Fade the container in when ARKit first places it in the scene.
        func view(_ view: ARSKView, didAdd node: SKNode, for anchor: ARAnchor) {
            guard node.name == "bugContainer" else { return }
            node.alpha = 0
            node.run(SKAction.fadeIn(withDuration: 0.5))
        }
    }
}

