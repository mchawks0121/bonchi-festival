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

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = (isARMode || isProjectorMode)
            ? .clear
            : SKColor(red: 0.05, green: 0.12, blue: 0.05, alpha: 1)

        physicsWorld.gravity = .zero
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
}
