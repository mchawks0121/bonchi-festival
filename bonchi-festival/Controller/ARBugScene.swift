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

// MARK: - BugHunterSceneDelegate

/// Receives score and lifecycle events from ARBugScene.
protocol BugHunterSceneDelegate: AnyObject {
    func scene(_ scene: SKScene, didUpdateScore score: Int, timeRemaining: Double)
    func sceneDidFinish(_ scene: SKScene, finalScore: Int)
}

// MARK: - ARBugScene

final class ARBugScene: SKScene {

    // MARK: Public

    weak var gameDelegate: BugHunterSceneDelegate?

    /// Called (on main thread) when a bug container node is captured so that
    /// ARGameView can remove the corresponding ARAnchor from the session.
    var onCaptureBug: ((SKNode) -> Void)?

    /// Called ~0.20 s after capture (when the net visually lands on the bug) so
    /// ARGameView can immediately start the 3-D Bug3DNode struggle animation.
    var onBugCaptured3D: ((SKNode) -> Void)?

    // MARK: Public state

    /// When true the countdown timer is frozen (used during the `.ready` pre-game phase).
    var isTimerPaused: Bool = false

    // MARK: Private state

    private(set) var score: Int = 0
    private var timeRemaining: Double = 90.0
    private var lastUpdate: TimeInterval = 0
    private var gameEnded = false

    /// Pending fire queued before the scene was presented to an SKView.
    /// Replayed in didMove(to:) once crosshair nodes are initialised.
    private var pendingFire: (angle: Float, power: Float)? = nil

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
    /// At exactly 2 bugs the distortion layer reaches full opacity (clamped at 1.0).
    private static let distortionPerBug: CGFloat = 0.50

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        physicsWorld.gravity = .zero
        setupDistortionLayer()
        setupCrosshair()

        // Replay any fire that was queued before the scene was presented.
        if let pending = pendingFire {
            pendingFire = nil
            fireNet(angle: pending.angle, power: pending.power)
        }
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        guard !gameEnded else { return }
        guard lastUpdate > 0 else { lastUpdate = currentTime; return }

        let dt = min(currentTime - lastUpdate, 0.05)
        lastUpdate = currentTime

        // Countdown is frozen during the `.ready` pre-game phase.
        if !isTimerPaused {
            timeRemaining = max(0, timeRemaining - dt)
        }

        updateLockOn()
        updateDistortion()

        gameDelegate?.scene(self, didUpdateScore: score, timeRemaining: timeRemaining)

        if !isTimerPaused && timeRemaining <= 0 { endGame() }
    }

    // MARK: - Public API

    /// The radius (in scene points) within which a bug must be from screen
    /// centre to count as caught.  150 pt (~half the crosshair's visible area) gives
    /// forgiving detection while still requiring the player to aim at the bug.
    static let catchRadius: CGFloat = 150

    /// Called by GameManager when the player releases the slingshot.
    func fireNet(angle: Float, power: Float) {
        guard !gameEnded else { return }

        // Play the throw sound exactly once regardless of whether the shot is queued
        // or fires immediately.
        SoundManager.shared.playThrow()

        // If the scene has not yet been presented to an SKView (e.g. the player
        // fired immediately after confirmReady() but before updateUIView had a
        // chance to call presentScene), queue the shot.  It will be replayed in
        // didMove(to:) once the scene is running and crosshair nodes are ready.
        guard view != nil else {
            pendingFire = (angle, power)
            return
        }

        let center      = CGPoint(x: size.width / 2, y: size.height / 2)
        let catchRadius = ARBugScene.catchRadius

        // ── 1. Primary: lock-on capture (bug within catchRadius of screen centre) ──
        var closest: SKNode?
        var closestDist = CGFloat.infinity

        for node in children where node.name == "bugContainer" {
            let dist = distanceFromCenter(node)
            if dist < catchRadius, dist < closestDist {
                closestDist = dist
                closest = node
            }
        }

        // ── 2. Secondary: trajectory hit (any bug along the net's flight path) ──
        if closest == nil {
            let dirX: CGFloat = CGFloat(cos(angle))
            let dirY: CGFloat = CGFloat(sin(angle))
            // Net range grows with power: minimum 200 pt, up to 80 % of the longer side.
            let netRange  = CGFloat(power) * max(size.width, size.height) * 0.8 + 200
            // Half-width of the "hit band" around the flight line (generous to feel responsive).
            let hitBand: CGFloat = 90

            var bestProj = CGFloat.infinity
            for node in children where node.name == "bugContainer" {
                let dx = node.position.x - center.x
                let dy = node.position.y - center.y
                // Scalar projection onto flight direction (must be positive = in front).
                let proj = dx * dirX + dy * dirY
                guard proj > 0, proj <= netRange else { continue }
                // Perpendicular distance from the flight line.
                let perp = abs(dx * dirY - dy * dirX)
                guard perp < hitBand else { continue }
                // Prefer the bug the net reaches first.
                if proj < bestProj {
                    bestProj = proj
                    closest = node
                }
            }
        }

        // ── Compute the visual fly-target so the animation matches the capture ──
        let flyTarget: CGPoint
        if let t = closest {
            // Fly 55 % of the way to the bug so the net visibly travels toward it.
            let frac: CGFloat = 0.55
            flyTarget = CGPoint(
                x: center.x + (t.position.x - center.x) * frac,
                y: center.y + (t.position.y - center.y) * frac
            )
        } else {
            // No target: fly in the actual launch direction.
            let range = CGFloat(power) * 180 + 120
            flyTarget = CGPoint(
                x: center.x + CGFloat(cos(angle)) * range,
                y: center.y + CGFloat(sin(angle)) * range
            )
        }

        playNetThrowAnimation(toward: flyTarget)

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
        guard crosshairRing != nil, lockOnRing != nil else { return }
        lockOnRing.removeAllActions()
        if let t = target {
            // `refreshLockOnRing` is only called when the target changes (see `updateLockOn`),
            // so the sound fires at most once per new lock-on acquisition.
            SoundManager.shared.playLockOn()
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

            // Restore crosshair to yellow-green idle pulse (not blue/cyan)
            let ringColor = SKColor(red: 0.85, green: 1.0, blue: 0.50, alpha: 0.85)
            crosshairRing.strokeColor = ringColor
            let pulse = SKAction.sequence([
                SKAction.scale(to: 1.07, duration: 0.85),
                SKAction.scale(to: 1.00, duration: 0.85)
            ])
            crosshairRing.run(SKAction.repeatForever(pulse), withKey: "pulse")
        }
    }

    // MARK: - Private: game flow

    /// Duration the capture animation runs before the ARAnchor is removed.
    /// Must be ≥ the longest animation chain: net cinch (~0.3 s) + bug struggle (~0.4 s)
    /// + dissolve (~0.4 s) = ~1.1 s; set to 1.2 s for safety.
    private static let healingAnimationDuration: TimeInterval = 1.2

    private func endGame() {
        gameEnded = true
        SoundManager.shared.playGameEnd()

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
        SoundManager.shared.playCapture(points: pts)

        let bugCenter = container.position

        // ── 1. Net entanglement: dramatic multi-piece wrap ────────────────────
        playNetEntangle(at: bugCenter)

        // ── 2. Trigger 3-D bug struggle when the net visually arrives (~0.20 s) ─
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            self?.onBugCaptured3D?(container)
        }

        // ── 3. 2-D proxy struggle: violent thrash → constrict → fade ─────────
        //      (proxy container has no visible children; these run for consistency)
        container.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.18),
            // Impact jolt
            SKAction.group([
                SKAction.scale(to: 1.40, duration: 0.05),
                SKAction.rotate(byAngle: .pi * 0.30, duration: 0.05)
            ]),
            // Violent thrash — multi-axis struggle trying to escape the net
            SKAction.group([
                SKAction.sequence([
                    SKAction.rotate(byAngle:  .pi * 0.55, duration: 0.07),
                    SKAction.rotate(byAngle: -.pi * 0.80, duration: 0.08),
                    SKAction.rotate(byAngle:  .pi * 0.60, duration: 0.07),
                    SKAction.rotate(byAngle: -.pi * 0.40, duration: 0.06)
                ]),
                SKAction.sequence([
                    SKAction.scale(to: 0.80, duration: 0.07),
                    SKAction.scale(to: 1.25, duration: 0.07),
                    SKAction.scale(to: 0.72, duration: 0.07),
                    SKAction.scale(to: 1.10, duration: 0.07)
                ])
            ]),
            // Net tightens — bug is subdued and shrinks as it's captured
            SKAction.group([
                SKAction.sequence([
                    SKAction.scale(to: 0.60, duration: 0.20),
                    SKAction.scale(to: 0.35, duration: 0.18)
                ]),
                SKAction.sequence([
                    SKAction.wait(forDuration: 0.10),
                    SKAction.fadeOut(withDuration: 0.32)
                ])
            ])
        ]))

        // ── 4. Space-restoration healing ripple ───────────────────────────────
        playHealRipple(at: bugCenter)

        // ── 5. Brief yellow-green screen flash (changed from cyan-white) ─────
        let flash = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        flash.fillColor   = SKColor(red: 0.5, green: 1.0, blue: 0.3, alpha: 0.22)
        flash.strokeColor = .clear
        flash.zPosition   = 71
        addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0, duration: 0.30),
            SKAction.removeFromParent()
        ]))

        // ── 6. Score pop ──────────────────────────────────────────────────────
        let popText = pts == 5 ? "⭐+\(pts)pts" : "+\(pts)pts"
        let pop = SKLabelNode(text: popText)
        pop.fontName  = "HiraginoSans-W7"
        pop.fontSize  = pts == 5 ? 64 : 54
        pop.fontColor = pts == 5
            ? SKColor(red: 1.0, green: 0.95, blue: 0.2, alpha: 1)
            : SKColor(red: 1,   green: 0.85, blue: 0,  alpha: 1)
        pop.position  = CGPoint(x: bugCenter.x, y: bugCenter.y + 30)
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

        // ── 7. Crosshair flashes green ────────────────────────────────────────
        pulseCrosshair(success: true)

        // ── 8. Anchor cleanup after all animations complete ───────────────────
        DispatchQueue.main.asyncAfter(deadline: .now() + ARBugScene.healingAnimationDuration) { [weak self] in
            self?.onCaptureBug?(container)
        }

        score += pts
    }

    /// Enhanced net entanglement animation at the bug's 2-D screen position.
    ///
    /// Three layers compose a "net wraps and cinches" feel:
    /// - **Main net** (🕸️): flies from screen centre, billows open on impact, cinches tight.
    /// - **Four binding strands** (small 🕸️): snap outward like threads, then constrict back.
    /// - **Constricting ring**: yellow circle that contracts around the bug.
    private func playNetEntangle(at bugPos: CGPoint) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // ── Main net ──────────────────────────────────────────────────────────
        let mainNet = SKLabelNode(text: "🕸️")
        mainNet.fontSize  = 88
        mainNet.position  = center
        mainNet.zPosition = 62
        mainNet.setScale(0.8)
        mainNet.alpha     = 1.0
        addChild(mainNet)

        mainNet.run(SKAction.sequence([
            // Fly toward the bug, spinning and growing as it approaches
            SKAction.group([
                SKAction.move(to: bugPos, duration: 0.20),
                SKAction.rotate(byAngle: -.pi * 2.4, duration: 0.20),
                SKAction.scale(to: 1.65, duration: 0.20)
            ]),
            // Billow open on impact
            SKAction.group([
                SKAction.scale(to: 2.7, duration: 0.07),
                SKAction.rotate(byAngle: -.pi * 0.3, duration: 0.07)
            ]),
            // Cinch tight around the bug
            SKAction.group([
                SKAction.scale(to: 0.50, duration: 0.24),
                SKAction.rotate(byAngle: .pi * 1.3, duration: 0.24)
            ]),
            // Linger while the bug struggles
            SKAction.wait(forDuration: 0.38),
            // Shrink to nothing as bug fades
            SKAction.group([
                SKAction.scale(to: 0.20, duration: 0.26),
                SKAction.fadeOut(withDuration: 0.26)
            ]),
            SKAction.removeFromParent()
        ]))

        // ── Four binding strands ──────────────────────────────────────────────
        let bindAngles: [CGFloat] = [.pi / 5, .pi / 5 + .pi,
                                     3 * .pi / 5, 3 * .pi / 5 + .pi]
        for (i, angle) in bindAngles.enumerated() {
            let strand = SKLabelNode(text: "🕸️")
            strand.fontSize  = 30
            strand.position  = bugPos
            strand.zPosition = 61
            strand.alpha     = 0.0
            strand.setScale(0.3)
            addChild(strand)

            let delay: Double = Double(i) * 0.04 + 0.22
            let reach: CGFloat = 46
            let tx = bugPos.x + cos(angle) * reach
            let ty = bugPos.y + sin(angle) * reach

            strand.run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                // Snap outward
                SKAction.group([
                    SKAction.fadeAlpha(to: 0.90, duration: 0.06),
                    SKAction.move(to: CGPoint(x: tx, y: ty), duration: 0.09),
                    SKAction.scale(to: 0.88, duration: 0.09),
                    SKAction.rotate(byAngle: .pi * 1.2, duration: 0.09)
                ]),
                // Constrict back
                SKAction.group([
                    SKAction.move(to: bugPos, duration: 0.14),
                    SKAction.scale(to: 0.38, duration: 0.14),
                    SKAction.rotate(byAngle: .pi * 0.6, duration: 0.14)
                ]),
                SKAction.wait(forDuration: 0.28),
                SKAction.fadeOut(withDuration: 0.18),
                SKAction.removeFromParent()
            ]))
        }

        // ── Constricting ring ─────────────────────────────────────────────────
        let ring = SKShapeNode(circleOfRadius: 54)
        ring.strokeColor = SKColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 0.9)
        ring.fillColor   = SKColor(red: 1.0, green: 0.95, blue: 0.3, alpha: 0.08)
        ring.lineWidth   = 2.5
        ring.position    = bugPos
        ring.zPosition   = 60
        ring.alpha       = 0
        addChild(ring)

        ring.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.20),
            SKAction.group([
                SKAction.fadeAlpha(to: 0.85, duration: 0.06),
                SKAction.scale(to: 0.88, duration: 0.06)
            ]),
            // Cinch tight
            SKAction.group([
                SKAction.scale(to: 0.22, duration: 0.32),
                SKAction.fadeAlpha(to: 0.35, duration: 0.32)
            ]),
            SKAction.wait(forDuration: 0.22),
            SKAction.fadeOut(withDuration: 0.18),
            SKAction.removeFromParent()
        ]))
    }

    /// Expanding ripple that signals the space has been restored.
    /// Changed from cyan to yellow-green to avoid "blue circle" appearance.
    private func playHealRipple(at position: CGPoint) {
        let healRing = SKShapeNode(circleOfRadius: 20)
        healRing.strokeColor = SKColor(red: 0.6, green: 1.0, blue: 0.3, alpha: 0.9)
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

    private func playNetThrowAnimation(toward flyTarget: CGPoint) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // Expanding ring that mimics the net mouth opening
        let ring = SKShapeNode(circleOfRadius: 28)
        ring.strokeColor = UIColor.white.withAlphaComponent(0.60)
        ring.fillColor   = .clear
        ring.lineWidth   = 2.5
        ring.position    = center
        ring.zPosition   = 52
        ring.setScale(0.3)
        ring.alpha = 0.85
        addChild(ring)
        ring.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 3.8, duration: 0.45),
                SKAction.fadeOut(withDuration: 0.45)
            ]),
            SKAction.removeFromParent()
        ]))
        // NOTE: The 3-D Net3DNode (SceneKit) is the primary net visual;
        //       this ring provides supplementary 2D feedback from the launch point.
    }

    private func playMissAnimation(near center: CGPoint) {
        pulseCrosshair(success: false)
        SoundManager.shared.playMiss()

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
        guard crosshairRing != nil else { return }
        let hitColor  = success
            ? SKColor(red: 0.2, green: 1.0, blue: 0.5, alpha: 1)
            : SKColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1)
        // Base color matches the setupCrosshair yellow-green (no blue)
        let baseColor = SKColor(red: 0.85, green: 1.0, blue: 0.50, alpha: 0.85)
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
        let cx    = size.width  / 2
        let cy    = size.height / 2
        // Use white/light-green for the crosshair to avoid appearing as a "blue circle"
        // in the AR camera view. Cyan was previously used but perceived as blue.
        let ringColor = SKColor(red: 0.85, green: 1.0, blue: 0.50, alpha: 0.85)

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
        crosshairRing.strokeColor = ringColor
        crosshairRing.fillColor   = .clear
        crosshairRing.lineWidth   = 2.5
        crosshairRing.position    = CGPoint(x: cx, y: cy)
        crosshairRing.zPosition   = 50
        addChild(crosshairRing)

        // Centre dot
        let dot = SKShapeNode(circleOfRadius: 5)
        dot.fillColor   = ringColor
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
            tick.strokeColor = ringColor
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
