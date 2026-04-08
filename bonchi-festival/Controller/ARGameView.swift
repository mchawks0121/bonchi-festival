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

        // MARK: Aura constants
        /// Glitch symbols shown orbiting each bug's corruption aura.
        private static let auraGlitchSymbols: [String] = ["⚠️", "❌", "👾"]

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

            // ── Corruption aura — space-distortion effect ──────────────────
            // Two counter-rotating broken rings that suggest the bug is
            // warping the surrounding space.
            let aura = SKNode()
            aura.name     = "corruptionAura"
            aura.zPosition = -1
            container.addChild(aura)

            let innerRing = makeGlitchRing(radius: 44, lineWidth: 2.0, alpha: 0.55,
                                           color: SKColor(red: 1.0, green: 0.3, blue: 0.1, alpha: 1))
            aura.addChild(innerRing)
            innerRing.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 2.8)))

            let outerRing = makeGlitchRing(radius: 66, lineWidth: 1.5, alpha: 0.35,
                                           color: SKColor(red: 0.8, green: 0.1, blue: 1.0, alpha: 1))
            aura.addChild(outerRing)
            outerRing.run(SKAction.repeatForever(SKAction.rotate(byAngle: -.pi * 2, duration: 4.2)))

            // Three orbiting glitch symbols using SpriteKit's native circular path follow
            let orbitRadius: CGFloat = 56
            for (i, sym) in Coordinator.auraGlitchSymbols.enumerated() {
                let label = SKLabelNode(text: sym)
                label.fontSize  = 18
                label.zPosition = 2
                label.alpha     = 0.7
                aura.addChild(label)

                // Build a full-circle CGPath offset so the label orbits the aura centre.
                // Each symbol starts at a different phase so they are evenly spread.
                let phaseOffset = CGFloat(i) * (.pi * 2 / CGFloat(Coordinator.auraGlitchSymbols.count))
                let orbitPath   = UIBezierPath(arcCenter: .zero,
                                               radius: orbitRadius,
                                               startAngle: phaseOffset,
                                               endAngle: phaseOffset + .pi * 2,
                                               clockwise: true).cgPath
                let orbitDuration = 5.0 + Double(i) * 0.9
                label.run(SKAction.repeatForever(
                    SKAction.follow(orbitPath, asOffset: false, orientToPath: false,
                                   duration: orbitDuration)
                ))

                // Flicker
                let flicker = SKAction.sequence([
                    SKAction.fadeAlpha(to: CGFloat.random(in: 0.2...0.9), duration: 0.12),
                    SKAction.fadeAlpha(to: CGFloat.random(in: 0.5...1.0), duration: 0.18)
                ])
                label.run(SKAction.repeatForever(flicker))
            }

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

        /// Build one "broken" glitch ring (circle with gap segments drawn as separate arcs).
        private func makeGlitchRing(radius: CGFloat, lineWidth: CGFloat,
                                    alpha: CGFloat, color: SKColor) -> SKNode {
            let node = SKNode()
            // 6 arc segments with gaps to give a broken / corrupted look
            let segments   = 6
            let gapFraction: CGFloat = 0.18
            for i in 0..<segments {
                let startAngle = CGFloat(i) / CGFloat(segments) * .pi * 2
                let endAngle   = startAngle + (.pi * 2 / CGFloat(segments)) * (1 - gapFraction)
                let path = CGMutablePath()
                path.addArc(center: .zero,
                            radius: radius,
                            startAngle: startAngle,
                            endAngle: endAngle,
                            clockwise: false)
                let arc = SKShapeNode(path: path)
                arc.strokeColor = color
                arc.fillColor   = .clear
                arc.lineWidth   = lineWidth
                arc.alpha       = alpha
                node.addChild(arc)
            }
            return node
        }

        /// Fade the container in when ARKit first places it in the scene.
        func view(_ view: ARSKView, didAdd node: SKNode, for anchor: ARAnchor) {
            guard node.name == "bugContainer" else { return }
            node.alpha = 0
            node.run(SKAction.fadeIn(withDuration: 0.5))
        }
    }
}

