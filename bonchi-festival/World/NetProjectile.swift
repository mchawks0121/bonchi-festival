//
//  NetProjectile.swift
//  bonchi-festival
//
//  Projector World: net projectile node launched from iOS controller data.
//

import SpriteKit

// MARK: - NetProjectile

/// An animated net emoji that flies across the scene, colliding with BugNodes.
final class NetProjectile: SKNode {

    /// Called when this net captures a bug; passes the captured BugNode.
    var onCapture: ((BugNode) -> Void)?

    private let netLabel: SKLabelNode
    private let ringNode: SKShapeNode

    // MARK: Init

    init() {
        netLabel = SKLabelNode(text: "🕸️")
        netLabel.fontSize = 52
        netLabel.verticalAlignmentMode   = .center
        netLabel.horizontalAlignmentMode = .center

        ringNode = SKShapeNode(circleOfRadius: 34)
        ringNode.strokeColor = UIColor.white.withAlphaComponent(0.45)
        ringNode.fillColor   = .clear
        ringNode.lineWidth   = 2

        super.init()

        addChild(netLabel)
        addChild(ringNode)

        name = "net"

        // Expanding ring physics body (used for contact detection)
        physicsBody = SKPhysicsBody(circleOfRadius: 44)
        physicsBody?.isDynamic          = false
        physicsBody?.categoryBitMask    = PhysicsCategory.net
        physicsBody?.contactTestBitMask = PhysicsCategory.bug
        physicsBody?.collisionBitMask   = 0
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: Launch

    /// Animate the net flying across the scene.
    /// - Parameters:
    ///   - angle: Launch angle in radians (0 = right, π/2 = up).
    ///   - power: Normalised 0–1 power from the iOS slingshot.
    ///   - origin: Scene-space starting position.
    ///   - sceneSize: Used to compute travel distance.
    func launch(angle: Float, power: Float, from origin: CGPoint, sceneSize: CGSize) {
        position = origin

        // Map power → travel distance; ensure net always crosses most of the screen
        let travelSpeed = CGFloat(power) * 1_400 + 500   // 500–1 900 pts/s
        let travelTime: TimeInterval = 0.55
        let dx = cos(CGFloat(angle)) * travelSpeed * CGFloat(travelTime)
        let dy = sin(CGFloat(angle)) * travelSpeed * CGFloat(travelTime)

        // Fly
        let moveAction = SKAction.moveBy(x: dx, y: dy, duration: travelTime)
        moveAction.timingMode = .easeOut

        // Ring expands as the net opens
        ringNode.run(SKAction.group([
            SKAction.scale(to: 2.2, duration: 0.4),
            SKAction.fadeOut(withDuration: 0.4)
        ]))

        // Spin slightly for realism
        let spin = SKAction.rotate(byAngle: CGFloat(power) * .pi, duration: travelTime)

        run(SKAction.group([moveAction, spin])) { [weak self] in
            self?.removeFromParent()
        }
    }

    // MARK: Capture

    /// Trigger a brief pulse animation after capturing a bug, then remove.
    func playCapture() {
        removeAllActions()
        physicsBody = nil
        let pulse   = SKAction.sequence([
            SKAction.scale(to: 1.6, duration: 0.12),
            SKAction.scale(to: 1.0, duration: 0.10)
        ])
        let fadeOut = SKAction.fadeOut(withDuration: 0.35)
        run(SKAction.sequence([pulse, fadeOut, SKAction.removeFromParent()]))
    }
}
