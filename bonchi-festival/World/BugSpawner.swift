//
//  BugSpawner.swift
//  bonchi-festival
//
//  Projector World: spawns BugNode instances into the SpriteKit scene
//  with a progressive difficulty curve.
//

import SpriteKit

// MARK: - BugSpawner

/// Adds bugs to `scene` at an increasing rate as game time elapses.
final class BugSpawner {

    weak var scene: SKScene?

    /// Seconds elapsed since the game started (updated externally).
    var elapsed: TimeInterval = 0

    private var isRunning = false

    init(scene: SKScene) {
        self.scene = scene
    }

    /// Begin spawning.
    func start() {
        isRunning = true
        scheduleNextSpawn(delay: 0.8)
    }

    /// Stop all pending spawns.
    func stop() {
        isRunning = false
        scene?.removeAction(forKey: "spawner")
    }

    // MARK: - Private

    private func scheduleNextSpawn(delay: TimeInterval) {
        guard isRunning else { return }
        let wait  = SKAction.wait(forDuration: delay)
        let spawn = SKAction.run { [weak self] in self?.spawnBug() }
        scene?.run(SKAction.sequence([wait, spawn]), withKey: "spawner")
    }

    private func spawnBug() {
        guard let scene, isRunning else { return }

        let bugType = randomBugType()
        let bug = BugNode(type: bugType)
        bug.position = randomEdgePosition(in: scene.size)
        scene.addChild(bug)

        // Move along a random bezier path, then remove when it leaves the scene.
        // duration = 600 / speed so slower bugs spend more time on screen:
        // Null (butterfly) ~5.5 s, Virus (beetle) ~8.6 s, Glitch (stag) ~13 s (capped at 12).
        let path     = randomPath(from: bug.position, in: scene.size)
        let duration = max(3.0, min(600.0 / Double(bugType.speed), 12.0))
        let move     = SKAction.follow(path, asOffset: false, orientToPath: true, duration: duration)
        bug.run(SKAction.sequence([move, SKAction.removeFromParent()]))

        // Progressive interval: starts at 1.4 s, drops to 0.4 s over 90 s
        let nextDelay = max(0.4, 1.4 - elapsed / 80.0)
        scheduleNextSpawn(delay: nextDelay)
    }

    // MARK: - Helpers

    private func randomBugType() -> BugType {
        let roll = Double.random(in: 0..<1)
        switch roll {
        case ..<0.60: return .butterfly
        case ..<0.90: return .beetle
        default:      return .stag
        }
    }

    private func randomEdgePosition(in size: CGSize) -> CGPoint {
        switch Int.random(in: 0..<4) {
        case 0: return CGPoint(x: CGFloat.random(in: 0...size.width), y: size.height + 30)
        case 1: return CGPoint(x: CGFloat.random(in: 0...size.width), y: -30)
        case 2: return CGPoint(x: -30, y: CGFloat.random(in: 0...size.height))
        default: return CGPoint(x: size.width + 30, y: CGFloat.random(in: 0...size.height))
        }
    }

    private func randomPath(from start: CGPoint, in size: CGSize) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start)

        var prev = start
        let steps = Int.random(in: 3...5)
        for _ in 0..<steps {
            let next = CGPoint(
                x: CGFloat.random(in: 60...(size.width  - 60)),
                y: CGFloat.random(in: 60...(size.height - 60))
            )
            let ctrl = CGPoint(
                x: (prev.x + next.x) / 2 + CGFloat.random(in: -120...120),
                y: (prev.y + next.y) / 2 + CGFloat.random(in: -120...120)
            )
            path.addQuadCurve(to: next, control: ctrl)
            prev = next
        }
        // Exit off-screen
        path.addLine(to: randomEdgePosition(in: size))
        return path
    }
}

// MARK: - BugNode

/// An invisible SpriteKit node that carries a physics body for net-collision detection.
/// All visual rendering is handled by Bug3DNode (SceneKit); this node has no sprite.
final class BugNode: SKNode {

    let bugType: BugType
    var points: Int { bugType.points }

    init(type: BugType) {
        self.bugType = type
        super.init()

        name = "bug"

        // Physics (kinematic — moved by actions, not forces)
        physicsBody = SKPhysicsBody(circleOfRadius: type.size / 2)
        physicsBody?.isDynamic          = false
        physicsBody?.categoryBitMask    = PhysicsCategory.bug
        physicsBody?.contactTestBitMask = PhysicsCategory.net
        physicsBody?.collisionBitMask   = 0
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not implemented") }

    /// Remove from scene immediately (no visual to animate).
    func captured() {
        removeAllActions()
        removeFromParent()
    }
}
