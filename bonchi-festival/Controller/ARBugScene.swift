//
//  ARBugScene.swift
//  bonchi-festival
//
//  iOS Controller: SpriteKit scene for on-device AR gameplay.
//  The background is transparent so the ARSKView camera feed shows through.
//
//  Bugs are placed in 3D world space as ARAnchor objects by ARGameView.
//  ARKit projects each anchor to a 2D screen position and adds the
//  corresponding BugNode as a child of this scene automatically.
//
//  The player moves their phone to aim the crosshair at a bug, then
//  pulls and releases the slingshot to throw the net.  Hit detection is
//  proximity-based: if a bug's projected position is within `catchRadius`
//  points of the scene centre, it is captured.
//

import SpriteKit

// MARK: - ARBugScene

final class ARBugScene: SKScene {

    // MARK: Public

    weak var gameDelegate: BugHunterSceneDelegate?

    /// Called (on main thread) when a bug container node is captured so that
    /// ARGameView can remove the corresponding ARAnchor from the session.
    var onCaptureBug: ((SKNode) -> Void)?

    // MARK: Private state

    private(set) var score: Int = 0
    private var timeRemaining: Double = 90.0
    private var lastUpdate: TimeInterval = 0
    private var gameEnded = false

    // MARK: Crosshair nodes

    private var crosshairRing: SKShapeNode!

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        physicsWorld.gravity = .zero
        setupCrosshair()
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        guard !gameEnded else { return }
        guard lastUpdate > 0 else { lastUpdate = currentTime; return }

        let dt = min(currentTime - lastUpdate, 0.05)   // cap to avoid big jumps
        lastUpdate = currentTime
        timeRemaining = max(0, timeRemaining - dt)

        gameDelegate?.scene(self, didUpdateScore: score, timeRemaining: timeRemaining)

        if timeRemaining <= 0 { endGame() }
    }

    // MARK: - Public API

    /// The radius (in scene points) within which a bug must be from screen
    /// centre to count as caught.  Exposed as a constant for easy tuning.
    static let catchRadius: CGFloat = 120

    /// Called by GameManager when the player releases the slingshot.
    /// `angle` and `power` come from the gesture; only `power` is used here
    /// (for the visual throw strength).  Hit detection is always centre-based.
    func fireNet(angle: Float, power: Float) {
        guard !gameEnded else { return }

        playNetThrowAnimation()

        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // Find the closest "bugContainer" child within the catch zone.
        // Radius is fixed; the crosshair gives clear visual feedback on aim.
        let catchRadius = ARBugScene.catchRadius

        var closest: SKNode?
        var closestDist = CGFloat.infinity

        for node in children where node.name == "bugContainer" {
            let dist = hypot(node.position.x - center.x,
                             node.position.y - center.y)
            if dist < catchRadius, dist < closestDist {
                closestDist = dist
                closest = node
            }
        }

        if let container = closest {
            let bugNode = container.children.first(where: { $0 is BugNode }) as? BugNode
            catchBug(container: container, bugNode: bugNode)
        } else {
            playMissAnimation(near: center)
        }
    }

    // MARK: - Private: game flow

    private func endGame() {
        gameEnded = true

        // Gently fade out all remaining bugs
        children
            .filter { $0.name == "bugContainer" }
            .forEach { node in
                node.name = nil
                node.run(SKAction.sequence([
                    SKAction.fadeOut(withDuration: 0.5),
                    SKAction.removeFromParent()
                ]))
            }

        gameDelegate?.sceneDidFinish(self, finalScore: score)
        showEndOverlay()
    }

    private func showEndOverlay() {
        let overlay = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        overlay.fillColor   = SKColor.black.withAlphaComponent(0.45)
        overlay.strokeColor = .clear
        overlay.zPosition   = 80
        overlay.alpha       = 0
        addChild(overlay)
        overlay.run(SKAction.fadeIn(withDuration: 0.7))
    }

    // MARK: - Private: capture

    private func catchBug(container: SKNode, bugNode: BugNode?) {
        // Mark immediately to prevent double-capture
        container.name = "bugContainer_captured"
        let pts = bugNode?.points ?? 1

        // ── 1. Existing BugNode captured() animation ─────────────────────
        bugNode?.captured()

        // ── 2. Large net expands from the bug's position ─────────────────
        let netEmoji = SKLabelNode(text: "🕸️")
        netEmoji.fontSize  = 90
        netEmoji.position  = container.position
        netEmoji.zPosition = 62
        netEmoji.setScale(0.1)
        addChild(netEmoji)
        netEmoji.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 2.4, duration: 0.40),
                SKAction.sequence([
                    SKAction.fadeIn(withDuration: 0.05),
                    SKAction.wait(forDuration: 0.20),
                    SKAction.fadeOut(withDuration: 0.15)
                ])
            ]),
            SKAction.removeFromParent()
        ]))

        // ── 3. Brief white screen flash ───────────────────────────────────
        let flash = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        flash.fillColor   = SKColor.white.withAlphaComponent(0.18)
        flash.strokeColor = .clear
        flash.zPosition   = 71
        addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0, duration: 0.28),
            SKAction.removeFromParent()
        ]))

        // ── 4. Score pop ──────────────────────────────────────────────────
        let popText = pts == 5 ? "⭐+\(pts)pts" : "+\(pts)pts"
        let pop = SKLabelNode(text: popText)
        pop.fontName  = "HiraginoSans-W7"
        pop.fontSize  = pts == 5 ? 64 : 54
        pop.fontColor = pts == 5
            ? SKColor(red: 0.2, green: 1.0, blue: 0.8, alpha: 1)
            : SKColor(red: 1,   green: 0.85, blue: 0,  alpha: 1)
        pop.position  = CGPoint(x: container.position.x,
                                y: container.position.y + 30)
        pop.zPosition = 65
        pop.setScale(0.4)
        addChild(pop)
        pop.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.2, duration: 0.18),
                SKAction.fadeIn(withDuration: 0.08)
            ]),
            SKAction.group([
                SKAction.moveBy(x: 0, y: 70, duration: 0.60),
                SKAction.sequence([
                    SKAction.wait(forDuration: 0.30),
                    SKAction.fadeOut(withDuration: 0.30)
                ])
            ]),
            SKAction.removeFromParent()
        ]))

        // ── 5. Crosshair flashes green ────────────────────────────────────
        pulseCrosshair(success: true)

        // ── 6. Tell ARGameView to remove the ARAnchor (after animation) ───
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.onCaptureBug?(container)
        }

        score += pts
    }

    // MARK: - Private: throw / miss animations

    private func playNetThrowAnimation() {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let net = SKLabelNode(text: "🕸️")
        net.fontSize  = 52
        net.position  = center
        net.zPosition = 53
        net.setScale(0.15)
        net.alpha = 0.95
        addChild(net)
        net.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.9, duration: 0.42),
                SKAction.fadeOut(withDuration: 0.42)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    private func playMissAnimation(near center: CGPoint) {
        pulseCrosshair(success: false)

        let miss = SKLabelNode(text: "MISS")
        miss.fontName  = UIFont.systemFont(ofSize: 1).familyName  // system font fallback
        miss.fontSize  = 42
        miss.fontColor = SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
        miss.position  = CGPoint(x: center.x, y: center.y - 90)
        miss.zPosition = 55
        miss.alpha = 0
        addChild(miss)
        miss.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.08),
                SKAction.moveBy(x: 0, y: 28, duration: 0.38)
            ]),
            SKAction.fadeOut(withDuration: 0.20),
            SKAction.removeFromParent()
        ]))
    }

    private func pulseCrosshair(success: Bool) {
        let hitColor  = success
            ? SKColor(red: 0.2, green: 1.0, blue: 0.5, alpha: 1)
            : SKColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1)
        let baseColor = SKColor(red: 0.2, green: 1.0, blue: 0.8, alpha: 0.85)
        crosshairRing.removeAction(forKey: "pulse")
        crosshairRing.run(
            SKAction.sequence([
                SKAction.run   { [weak self] in self?.crosshairRing.strokeColor = hitColor },
                SKAction.scale(to: 1.40, duration: 0.10),
                SKAction.scale(to: 1.00, duration: 0.14),
                SKAction.run   { [weak self] in self?.crosshairRing.strokeColor = baseColor }
            ]),
            withKey: "hitPulse"
        )
    }

    // MARK: - Private: crosshair setup

    private func setupCrosshair() {
        let cx   = size.width  / 2
        let cy   = size.height / 2
        let cyan = SKColor(red: 0.2, green: 1.0, blue: 0.8, alpha: 0.85)

        // Outer ring (also used for hit-pulse)
        crosshairRing = SKShapeNode(circleOfRadius: 54)
        crosshairRing.strokeColor = cyan
        crosshairRing.fillColor   = .clear
        crosshairRing.lineWidth   = 2.5
        crosshairRing.position    = CGPoint(x: cx, y: cy)
        crosshairRing.zPosition   = 50
        addChild(crosshairRing)

        // Centre dot
        let dot = SKShapeNode(circleOfRadius: 5)
        dot.fillColor   = cyan
        dot.strokeColor = .clear
        dot.position    = CGPoint(x: cx, y: cy)
        dot.zPosition   = 51
        addChild(dot)

        // Four tick marks (N / S / E / W)
        let tickGap: CGFloat = 64
        let tickLen: CGFloat = 14
        let dirs: [(CGFloat, CGFloat)] = [(0, 1), (0, -1), (1, 0), (-1, 0)]
        for (ox, oy) in dirs {
            let path = CGMutablePath()
            path.move(to:    CGPoint(x: cx + ox * tickGap,            y: cy + oy * tickGap))
            path.addLine(to: CGPoint(x: cx + ox * (tickGap + tickLen), y: cy + oy * (tickGap + tickLen)))
            let tick = SKShapeNode(path: path)
            tick.strokeColor = cyan
            tick.lineWidth   = 2.5
            tick.zPosition   = 50
            addChild(tick)
        }

        // Gentle idle pulse on the ring
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.07, duration: 0.85),
            SKAction.scale(to: 1.00, duration: 0.85)
        ])
        crosshairRing.run(SKAction.repeatForever(pulse), withKey: "pulse")
    }
}
