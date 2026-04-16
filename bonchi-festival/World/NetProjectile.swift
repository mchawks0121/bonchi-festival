//
//  NetProjectile.swift
//  bonchi-festival
//
//  Projector World: net projectile node launched from iOS controller data.
//  The net is drawn procedurally as a spider-web pattern (SKShapeNode) rather
//  than an emoji, producing a richer, scalable look on the projector screen.
//

import SpriteKit

// MARK: - NetProjectile

/// An animated net mesh that flies across the scene, colliding with BugNodes.
final class NetProjectile: SKNode {

    /// Net / ring accent colors for each player slot (index 0–2).
    static let playerColors: [SKColor] = [
        SKColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1),   // Player 1: cyan
        SKColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1),  // Player 2: orange
        SKColor(red: 1.0, green: 0.2,  blue: 0.8, alpha: 1),  // Player 3: magenta
    ]

    /// Called when this net captures a bug; passes the captured BugNode.
    var onCapture: ((BugNode) -> Void)?

    /// The player slot index (0-based) that fired this net.
    /// Read by `BugHunterScene.didBegin(contact:)` to attribute the capture.
    let playerIndex: Int

    private let netShape: SKShapeNode   // drawn net mesh
    private let ringNode: SKShapeNode   // outer accent ring

    // MARK: Init

    /// - Parameter playerIndex: 0-based slot index used to tint the net (wraps at 3).
    init(playerIndex: Int = 0) {
        self.playerIndex = playerIndex
        let color = NetProjectile.playerColors[playerIndex % NetProjectile.playerColors.count]

        // ── Drawn net mesh ─────────────────────────────────────────────────────
        // Create a spider-web pattern: radial spokes + concentric circles.
        netShape = SKShapeNode(path: NetProjectile.netPath(outerRadius: 34,
                                                            spokeCount: 8,
                                                            ringCount:  3))
        netShape.strokeColor = SKColor(red: 0.30, green: 0.92, blue: 0.45, alpha: 0.95)
        netShape.fillColor   = SKColor(red: 0.10, green: 0.55, blue: 0.20, alpha: 0.12)
        netShape.lineWidth   = 2.2
        netShape.lineCap     = .round

        // ── Outer accent ring (player colour) ──────────────────────────────────
        ringNode = SKShapeNode(circleOfRadius: 38)
        ringNode.strokeColor = color.withAlphaComponent(0.80)
        ringNode.fillColor   = color.withAlphaComponent(0.06)
        ringNode.lineWidth   = 3.5

        super.init()

        addChild(ringNode)
        addChild(netShape)

        // Small filled dot at the centre so the player colour is always visible
        let dot = SKShapeNode(circleOfRadius: 6)
        dot.fillColor   = color
        dot.strokeColor = .clear
        dot.zPosition   = 1
        addChild(dot)

        name = "net"

        // Physics body for contact detection.
        physicsBody = SKPhysicsBody(circleOfRadius: 44)
        physicsBody?.isDynamic          = true
        physicsBody?.affectedByGravity  = false
        physicsBody?.linearDamping      = 0
        physicsBody?.angularDamping     = 0
        physicsBody?.categoryBitMask    = PhysicsCategory.net
        physicsBody?.contactTestBitMask = PhysicsCategory.bug
        physicsBody?.collisionBitMask   = 0
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: Net path factory

    /// Build a CGPath representing a spider-web net with `spokeCount` radial spokes
    /// and `ringCount` concentric circles inside `outerRadius`.
    private static func netPath(outerRadius: CGFloat,
                                 spokeCount: Int,
                                 ringCount:  Int) -> CGPath {
        let path = CGMutablePath()

        // Outer ring
        path.addEllipse(in: CGRect(x: -outerRadius, y: -outerRadius,
                                   width:  outerRadius * 2,
                                   height: outerRadius * 2))

        // Radial spokes from centre to outer ring
        for i in 0..<spokeCount {
            let angle = CGFloat(i) * .pi * 2 / CGFloat(spokeCount)
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: outerRadius * cos(angle),
                                     y: outerRadius * sin(angle)))
        }

        // Concentric inner rings
        for r in 1...ringCount {
            let radius = outerRadius * CGFloat(r) / CGFloat(ringCount + 1)
            path.addEllipse(in: CGRect(x: -radius, y: -radius,
                                       width:  radius * 2,
                                       height: radius * 2))
        }

        return path
    }

    // MARK: Launch

    /// Animate the net flying across the scene.
    /// - Parameters:
    ///   - angle: Launch angle in radians (0 = right, π/2 = up).
    ///   - power: Normalised 0–1 power from the iOS slingshot.
    ///   - origin: Scene-space starting position.
    ///   - sceneSize: Used to compute travel distance.
    func launch(angle: Float, power: Float, from origin: CGPoint, sceneSize: CGSize) {
        position = origin
        setScale(0.3)   // net starts folded/compact as it leaves the slingshot

        // Map power → travel distance; ensure net always crosses most of the screen
        let travelSpeed = CGFloat(power) * 1_400 + 500   // 500–1 900 pts/s
        let travelTime: TimeInterval = 0.55
        let dx = cos(CGFloat(angle)) * travelSpeed * CGFloat(travelTime)
        let dy = sin(CGFloat(angle)) * travelSpeed * CGFloat(travelTime)

        // Base trajectory (easeOut gives natural deceleration)
        let baseMove = SKAction.moveBy(x: dx, y: dy, duration: travelTime)
        baseMove.timingMode = .easeOut

        // Arc bump: the net rises perpendicular to the travel direction then falls back.
        let arcBump = sceneSize.height * 0.06 * abs(cos(CGFloat(angle))) * CGFloat(power + 0.3)
        let arcUp   = SKAction.moveBy(x: 0, y:  arcBump, duration: travelTime * 0.40)
        arcUp.timingMode = .easeOut
        let arcDown = SKAction.moveBy(x: 0, y: -arcBump, duration: travelTime * 0.60)
        arcDown.timingMode = .easeIn
        let arcAction = SKAction.sequence([arcUp, arcDown])

        // Net unfurls from compact → briefly over-expanded → settled
        let unfurl = SKAction.sequence([
            SKAction.scale(to: 1.3, duration: travelTime * 0.35),
            SKAction.scale(to: 1.0, duration: travelTime * 0.65)
        ])

        // Ring starts small and bright, then expands dramatically as the net opens
        ringNode.setScale(0.4)
        ringNode.alpha = 0.90
        ringNode.run(SKAction.group([
            SKAction.scale(to: 3.2, duration: 0.5),
            SKAction.sequence([
                SKAction.fadeAlpha(to: 0.5, duration: 0.25),
                SKAction.fadeOut(withDuration: 0.25)
            ])
        ]))

        // Multi-rotation spin: 0.75–2.5 full turns so the net clearly spins in flight
        let minRotations: CGFloat = 1.5
        let maxAdditionalRotations: CGFloat = 2
        let rotations = .pi * minRotations + CGFloat(power) * .pi * maxAdditionalRotations
        let spin = SKAction.rotate(byAngle: rotations, duration: travelTime)
        spin.timingMode = .easeOut

        run(SKAction.group([baseMove, arcAction, unfurl, spin])) { [weak self] in
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

