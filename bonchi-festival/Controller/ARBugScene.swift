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
    private var lockOnRing: SKShapeNode!        // secondary ring drawn around locked bug
    private var currentLockTarget: SKNode?      // bugContainer currently locked on

    // MARK: Background distortion nodes

    /// Container for all glitch-bar distortion effects.  Its alpha is driven by
    /// the current bug count so the distortion grows as more bugs invade.
    private var distortionLayer: SKNode!
    private var distortionBars: [SKShapeNode] = []
    private var lastBugCount = -1

    /// Fraction of full intensity added per active bug.
    /// At 3+ bugs the distortion layer reaches full opacity.
    private static let distortionPerBug: CGFloat = 0.38

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        physicsWorld.gravity = .zero
        setupDistortionLayer()
        setupCrosshair()
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        guard !gameEnded else { return }
        guard lastUpdate > 0 else { lastUpdate = currentTime; return }

        let dt = min(currentTime - lastUpdate, 0.05)
        lastUpdate = currentTime
        timeRemaining = max(0, timeRemaining - dt)

        updateLockOn()
        updateDistortion()

        gameDelegate?.scene(self, didUpdateScore: score, timeRemaining: timeRemaining)

        if timeRemaining <= 0 { endGame() }
    }

    // MARK: - Public API

    /// The radius (in scene points) within which a bug must be from screen
    /// centre to count as caught.  150 pt (~half the crosshair's visible area) gives
    /// forgiving detection while still requiring the player to aim at the bug.
    static let catchRadius: CGFloat = 150

    /// Called by GameManager when the player releases the slingshot.
    func fireNet(angle: Float, power: Float) {
        guard !gameEnded else { return }

        playNetThrowAnimation()

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let catchRadius = ARBugScene.catchRadius

        var closest: SKNode?
        var closestDist = CGFloat.infinity

        for node in children where node.name == "bugContainer" {
            let dist = distanceFromCenter(node)
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

    // MARK: - Private: helpers

    private func distanceFromCenter(_ node: SKNode) -> CGFloat {
        let cx = size.width  / 2
        let cy = size.height / 2
        return hypot(node.position.x - cx, node.position.y - cy)
    }

    // MARK: - Private: background distortion

    /// Creates the full-screen glitch-bar layer (initially invisible).
    /// Bars flicker independently; the parent node's alpha is driven by bug count.
    private func setupDistortionLayer() {
        distortionLayer = SKNode()
        distortionLayer.zPosition = -1   // behind all bugs and crosshair, in front of camera
        distortionLayer.alpha = 0
        addChild(distortionLayer)

        // Subtle purple-red full-screen tint
        let tint = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        tint.fillColor   = SKColor(red: 0.55, green: 0.0, blue: 0.55, alpha: 0.07)
        tint.strokeColor = .clear
        distortionLayer.addChild(tint)

        // Horizontal glitch bars at randomised vertical positions
        let barColors: [SKColor] = [
            SKColor(red: 1.0, green: 0.05, blue: 0.25, alpha: 0.45),  // red
            SKColor(red: 0.7, green: 0.0,  blue: 1.0,  alpha: 0.35),  // purple
            SKColor(red: 0.0, green: 0.9,  blue: 1.0,  alpha: 0.25),  // cyan
            SKColor(red: 1.0, green: 0.55, blue: 0.0,  alpha: 0.30),  // orange
        ]

        for i in 0..<12 {
            let barH  = CGFloat.random(in: 3...14)
            let baseY = CGFloat(i) / 12 * size.height + CGFloat.random(in: 0...size.height / 12)
            let bar   = SKShapeNode(rect: CGRect(x: 0, y: baseY,
                                                 width: size.width, height: barH))
            bar.fillColor   = barColors.randomElement()!
            bar.strokeColor = .clear
            bar.alpha       = 0
            distortionLayer.addChild(bar)
            distortionBars.append(bar)

            // Each bar flickers on its own random schedule
            let waitOff  = Double.random(in: 0.3...5.0)
            let onDur    = Double.random(in: 0.03...0.14)
            let holdDur  = Double.random(in: 0.02...0.10)
            let offDur   = Double.random(in: 0.05...0.22)
            bar.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.wait(forDuration: waitOff),
                SKAction.fadeAlpha(to: 1.0, duration: onDur),
                SKAction.wait(forDuration: holdDur),
                SKAction.fadeAlpha(to: 0,   duration: offDur)
            ])))
        }
    }

    /// Adjusts distortion intensity to match the current number of active bugs.
    private func updateDistortion() {
        let bugCount = children.filter { $0.name == "bugContainer" }.count
        guard bugCount != lastBugCount else { return }
        lastBugCount = bugCount

        // 0 bugs → invisible, 1 bug → 38 %, 2 → 66 %, 3+ → 100 %
        let target = min(CGFloat(bugCount) * ARBugScene.distortionPerBug, 1.0)
        distortionLayer.run(
            SKAction.fadeAlpha(to: target, duration: 0.6),
            withKey: "distortFade"
        )
    }

    // MARK: - Private: lock-on

    private func updateLockOn() {
        // Gather only active bug containers — skip entirely if none exist
        let containers = children.filter { $0.name == "bugContainer" }
        guard !containers.isEmpty else {
            if currentLockTarget != nil {
                currentLockTarget = nil
                refreshLockOnRing(target: nil)
            }
            return
        }

        // Find closest active bug
        var closest: SKNode?
        var closestDist = CGFloat.infinity
        for node in containers {
            let dist = distanceFromCenter(node)
            if dist < closestDist {
                closestDist = dist
                closest = node
            }
        }

        let inRange = closestDist < ARBugScene.catchRadius
        let target  = inRange ? closest : nil

        if target !== currentLockTarget {
            currentLockTarget = target
            refreshLockOnRing(target: target)
        } else if let t = target {
            // Keep ring tracking the bug's 2D position
            lockOnRing.position = t.position
        }
    }

    private func refreshLockOnRing(target: SKNode?) {
        lockOnRing.removeAllActions()
        if let t = target {
            // Snap to bug, flash orange then cycle
            lockOnRing.position   = t.position
            lockOnRing.setScale(1.8)
            lockOnRing.alpha      = 0
            lockOnRing.strokeColor = SKColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1)

            let appear  = SKAction.group([
                SKAction.fadeIn(withDuration: 0.12),
                SKAction.scale(to: 1.0, duration: 0.18)
            ])
            let pulse   = SKAction.sequence([
                SKAction.scale(to: 1.08, duration: 0.30),
                SKAction.scale(to: 1.00, duration: 0.30)
            ])
            lockOnRing.run(SKAction.sequence([
                appear,
                SKAction.repeatForever(pulse)
            ]))

            // Crosshair also turns orange while locked
            crosshairRing.removeAction(forKey: "pulse")
            crosshairRing.strokeColor = SKColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1)
        } else {
            lockOnRing.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.15),
                SKAction.run { [weak self] in self?.lockOnRing.setScale(0) }
            ]))

            // Restore crosshair to cyan idle pulse
            let cyan  = SKColor(red: 0.2, green: 1.0, blue: 0.8, alpha: 0.85)
            crosshairRing.strokeColor = cyan
            let pulse = SKAction.sequence([
                SKAction.scale(to: 1.07, duration: 0.85),
                SKAction.scale(to: 1.00, duration: 0.85)
            ])
            crosshairRing.run(SKAction.repeatForever(pulse), withKey: "pulse")
        }
    }

    // MARK: - Private: game flow

    /// Duration of the post-capture healing animation (seconds).
    /// The ARAnchor is removed from the AR session after this interval, so this
    /// value must be ≥ the longest constituent animation (heal ripple: 0.55 s + buffer).
    private static let healingAnimationDuration: TimeInterval = 0.75

    private func endGame() {
        gameEnded = true

        children
            .filter { $0.name == "bugContainer" }
            .forEach { node in
                node.name = nil
                node.run(SKAction.sequence([
                    SKAction.fadeOut(withDuration: 0.5),
                    SKAction.removeFromParent()
                ]))
            }

        // Fade out background distortion
        distortionLayer.run(SKAction.fadeOut(withDuration: 0.7))

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
        container.name = "bugContainer_captured"
        let pts = bugNode?.points ?? 1

        // ── 1. Existing BugNode captured() animation ─────────────────────
        bugNode?.captured()

        // ── 2. Space-restoration healing ripple ───────────────────────────
        playHealRipple(at: container.position)

        // ── 3. Large net expands from bug position ────────────────────────
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

        // ── 4. Brief cyan-white screen flash (space restored) ─────────────
        let flash = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        flash.fillColor   = SKColor(red: 0.3, green: 1.0, blue: 0.9, alpha: 0.20)
        flash.strokeColor = .clear
        flash.zPosition   = 71
        addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0, duration: 0.30),
            SKAction.removeFromParent()
        ]))

        // ── 5. Score pop ──────────────────────────────────────────────────
        let popText = pts == 5 ? "⭐+\(pts)pts" : "+\(pts)pts"
        let pop = SKLabelNode(text: popText)
        pop.fontName  = "HiraginoSans-W7"
        pop.fontSize  = pts == 5 ? 64 : 54
        pop.fontColor = pts == 5
            ? SKColor(red: 0.2, green: 1.0, blue: 0.8, alpha: 1)
            : SKColor(red: 1,   green: 0.85, blue: 0,  alpha: 1)
        pop.position  = CGPoint(x: container.position.x, y: container.position.y + 30)
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

        // ── 6. Crosshair flashes green ────────────────────────────────────
        pulseCrosshair(success: true)

        // ── 7. Tell ARGameView to remove the ARAnchor (after animations) ──
        DispatchQueue.main.asyncAfter(deadline: .now() + ARBugScene.healingAnimationDuration) { [weak self] in
            self?.onCaptureBug?(container)
        }

        score += pts
    }

    /// Expanding cyan ripple that signals the space has been restored.
    private func playHealRipple(at position: CGPoint) {
        let healRing = SKShapeNode(circleOfRadius: 20)
        healRing.strokeColor = SKColor(red: 0.4, green: 1.0, blue: 0.8, alpha: 0.9)
        healRing.fillColor   = .clear
        healRing.lineWidth   = 3
        healRing.position    = position
        healRing.zPosition   = 68
        addChild(healRing)
        healRing.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 5.0, duration: 0.55),
                SKAction.fadeOut(withDuration: 0.55)
            ]),
            SKAction.removeFromParent()
        ]))
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
        // Use SKLabelNode's default font (Helvetica) — no explicit fontName assignment needed
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

        // Lock-on ring (hidden until a bug enters catch radius)
        lockOnRing = SKShapeNode(circleOfRadius: 58)
        lockOnRing.strokeColor = SKColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1)
        lockOnRing.fillColor   = .clear
        lockOnRing.lineWidth   = 3.5
        lockOnRing.position    = CGPoint(x: cx, y: cy)
        lockOnRing.zPosition   = 52
        lockOnRing.alpha       = 0
        addChild(lockOnRing)

        // Outer crosshair ring (idle pulse)
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
            path.move(to: CGPoint(x: cx + ox * tickGap, y: cy + oy * tickGap))
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
