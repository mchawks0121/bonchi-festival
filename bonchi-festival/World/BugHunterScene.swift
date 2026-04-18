//
//  BugHunterScene.swift
//  bonchi-festival
//
//  Projector World: SpriteKit overlay scene.
//
//  The projector display is phone-driven: bugs are spawned and removed via
//  messages from the iOS controller (BugSpawnedPayload / BugRemovedPayload).
//  This scene is therefore a lightweight transparent overlay that:
//    • provides the net-launch animation when the phone fires (`fireNet`)
//    • shows a glitch-bar distortion layer that intensifies with bug count
//    • has no independent timer, score, HUD, or bug spawner
//    • has no physics contact delegate (capture decisions are made on the phone)
//

import SpriteKit

// MARK: - BugHunterScene

final class BugHunterScene: SKScene {

    /// When `true` the scene background is transparent so the AR camera feed shows through.
    var isARMode: Bool = false

    /// When `true` the scene is used as a transparent overlay over a SceneKit 3-D bug world
    /// on the projector device.  Background becomes clear.
    var isProjectorMode: Bool = false

    // MARK: World distortion (projector mode only)

    /// Root node for all glitch-bar distortion effects.
    /// Alpha is driven by total bug count via `updateWorldDistortion(bugCount:)`.
    private var distortionLayer: SKNode?
    private var lastDistortionBugCount = -1

    /// Fraction of full distortion intensity per active bug.
    /// At 3 bugs the layer reaches full opacity.
    private static let distortionPerBug: CGFloat = 0.38

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = (isARMode || isProjectorMode)
            ? .clear
            : SKColor(red: 0.05, green: 0.12, blue: 0.05, alpha: 1)

        physicsWorld.gravity = .zero

        if isProjectorMode {
            setupDistortionLayer()
        }
        // No contact delegate: capture decisions are made by the phone, not the projector.
    }

    // MARK: - Public API

    /// Called by WorldViewController when the iOS device fires the slingshot.
    /// Renders a visual net flying across the projector screen (cosmetic only).
    /// - Parameter playerIndex: 0-based player slot index used to tint the net.
    func fireNet(angle: Float, power: Float, playerIndex: Int = 0) {
        let net = NetProjectile(playerIndex: playerIndex)
        let origin = CGPoint(x: size.width / 2, y: 60)
        addChild(net)
        net.launch(angle: angle, power: power, from: origin, sceneSize: size)
        SoundManager.shared.playThrow()
    }

    /// Update the glitch-bar distortion intensity to reflect world corruption.
    /// Called by `ProjectorBug3DCoordinator` whenever the total bug count changes.
    func updateWorldDistortion(bugCount: Int) {
        guard let layer = distortionLayer else { return }
        guard bugCount != lastDistortionBugCount else { return }
        lastDistortionBugCount = bugCount
        let target = min(CGFloat(bugCount) * BugHunterScene.distortionPerBug, 1.0)
        layer.run(SKAction.fadeAlpha(to: target, duration: 0.7), withKey: "distortFade")
    }

    // MARK: - Private: distortion layer

    private func setupDistortionLayer() {
        guard size.width > 0, size.height > 0 else { return }

        let layer = SKNode()
        layer.zPosition = -1   // behind all content but in front of the SceneKit background
        layer.alpha     = 0
        addChild(layer)
        distortionLayer = layer

        // Subtle full-screen purple-red tint
        let tint = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        tint.fillColor   = SKColor(red: 0.60, green: 0.0, blue: 0.60, alpha: 0.06)
        tint.strokeColor = .clear
        layer.addChild(tint)

        // Horizontal glitch bars at randomised vertical positions
        let barColors: [SKColor] = [
            SKColor(red: 1.0, green: 0.05, blue: 0.25, alpha: 0.45),
            SKColor(red: 0.7, green: 0.0,  blue: 1.0,  alpha: 0.35),
            SKColor(red: 0.0, green: 0.9,  blue: 1.0,  alpha: 0.25),
            SKColor(red: 1.0, green: 0.55, blue: 0.0,  alpha: 0.30),
        ]

        for i in 0..<14 {
            let barH  = CGFloat.random(in: 3...16)
            let baseY = CGFloat(i) / 14 * size.height
                        + CGFloat.random(in: 0...size.height / 14)
            let bar   = SKShapeNode(rect: CGRect(x: 0, y: baseY,
                                                 width: size.width, height: barH))
            bar.fillColor   = barColors.randomElement()!
            bar.strokeColor = .clear
            bar.alpha       = 0
            layer.addChild(bar)

            // Each bar flickers on its own random schedule
            let waitOff = Double.random(in: 0.3...5.5)
            let onDur   = Double.random(in: 0.03...0.16)
            let holdDur = Double.random(in: 0.02...0.12)
            let offDur  = Double.random(in: 0.05...0.25)
            bar.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.wait(forDuration: waitOff),
                SKAction.fadeAlpha(to: 1.0, duration: onDur),
                SKAction.wait(forDuration: holdDur),
                SKAction.fadeAlpha(to: 0,   duration: offDur),
            ])))
        }
    }
}
