//
//  BugHunterScene.swift
//  bonchi-festival
//
//  Projector World: main SpriteKit scene for the 90-second bug-hunting game.
//

import SpriteKit

// MARK: - Delegate

protocol BugHunterSceneDelegate: AnyObject {
    func scene(_ scene: SKScene, didUpdateScore score: Int, timeRemaining: Double)
    func sceneDidFinish(_ scene: SKScene, finalScore: Int)
}

// MARK: - BugHunterScene

final class BugHunterScene: SKScene {

    weak var gameDelegate: BugHunterSceneDelegate?

    /// When `true` the scene background is transparent so the AR camera feed shows through.
    var isARMode: Bool = false

    /// When `true` the scene is used as a transparent overlay over a SceneKit 3-D bug world
    /// on the projector device.  Background becomes clear and BugSpawner is not started;
    /// the 3-D coordinator adds invisible proxy BugNodes directly.
    var isProjectorMode: Bool = false

    /// Called (on the main thread) when a `BugNode` is captured via net physics contact.
    /// The projector 3-D coordinator uses this to dismiss the corresponding Bug3DNode.
    var onBugCaptured: ((BugNode) -> Void)?

    // MARK: State

    private var timeRemaining: Double = 90.0
    private var lastUpdate: TimeInterval = 0

    // MARK: Child nodes

    private var spawner: BugSpawner!
    private var timeLabel: SKLabelNode!
    private var timerBar: SKShapeNode!
    private let timerBarMaxWidth: CGFloat = 600

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = (isARMode || isProjectorMode)
            ? .clear
            : SKColor(red: 0.05, green: 0.12, blue: 0.05, alpha: 1)

        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        setupBackground()
        setupHUD()

        spawner = BugSpawner(scene: self)
    }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        guard lastUpdate > 0 else { lastUpdate = currentTime; return }
        let dt = currentTime - lastUpdate
        lastUpdate = currentTime

        timeRemaining = max(0, timeRemaining - dt)
        spawner.elapsed = 90.0 - timeRemaining

        updateTimerBar()

        gameDelegate?.scene(self, didUpdateScore: 0, timeRemaining: timeRemaining)

        if timeRemaining <= 0 {
            endGame()
        }
    }

    // MARK: - Public API

    /// Called by WorldViewController when the iOS device fires the slingshot.
    /// - Parameter playerIndex: 0-based player slot index used to tint the net.
    func fireNet(angle: Float, power: Float, playerIndex: Int = 0) {
        let net = NetProjectile(playerIndex: playerIndex)
        // Launch from the bottom-centre of the scene
        let origin = CGPoint(x: size.width / 2, y: 60)
        addChild(net)
        net.launch(angle: angle, power: power, from: origin, sceneSize: size)
    }

    // MARK: - Private

    private func endGame() {
        spawner.stop()
        // Remove all remaining bugs
        children.filter { $0.name == "bug" }.forEach { $0.removeFromParent() }

        gameDelegate?.sceneDidFinish(self, finalScore: 0)
    }

    // MARK: - HUD Setup

    private func setupBackground() {
        // Scattered glitch symbols to convey "world being corrupted by bugs"
        for _ in 0..<28 {
            let symbol = SKLabelNode(text: ["⚠️", "❌", "🔴", "⛔", "💀", "🔥"].randomElement()!)
            symbol.fontSize  = CGFloat.random(in: 18...44)
            symbol.position  = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height)
            )
            symbol.alpha     = 0.15
            symbol.zPosition = -1
            addChild(symbol)
        }
    }

    private func setupHUD() {
        // Time label (top-right)
        timeLabel = SKLabelNode(text: "⏱ 90.0")
        timeLabel.fontName  = "HiraginoSans-W7"
        timeLabel.fontSize  = 48
        timeLabel.fontColor = .white
        timeLabel.horizontalAlignmentMode = .right
        timeLabel.position  = CGPoint(x: size.width - 24, y: size.height - 72)
        timeLabel.zPosition = 10
        addChild(timeLabel)

        // Timer bar (top, full-width)
        let barBg = SKShapeNode(
            rect: CGRect(x: size.width / 2 - timerBarMaxWidth / 2, y: size.height - 18,
                         width: timerBarMaxWidth, height: 10),
            cornerRadius: 5
        )
        barBg.fillColor   = SKColor.white.withAlphaComponent(0.25)
        barBg.strokeColor = .clear
        barBg.zPosition   = 10
        addChild(barBg)

        timerBar = SKShapeNode(
            rect: CGRect(x: size.width / 2 - timerBarMaxWidth / 2, y: size.height - 18,
                         width: timerBarMaxWidth, height: 10),
            cornerRadius: 5
        )
        timerBar.fillColor   = .green
        timerBar.strokeColor = .clear
        timerBar.zPosition   = 11
        addChild(timerBar)
    }

    private func updateTimerBar() {
        let fraction = CGFloat(timeRemaining / 90.0)
        let width    = timerBarMaxWidth * fraction
        let x        = size.width / 2 - timerBarMaxWidth / 2

        timerBar.path = CGPath(
            roundedRect: CGRect(x: x, y: size.height - 18, width: max(0, width), height: 10),
            cornerWidth: 5, cornerHeight: 5, transform: nil
        )
        timerBar.fillColor = fraction > 0.33 ? (fraction > 0.66 ? .green : .yellow) : .red

        timeLabel.text       = String(format: "⏱ %.1f", timeRemaining)
        timeLabel.fontColor  = timeRemaining < 10 ? .red : .white
    }
}

// MARK: - SKPhysicsContactDelegate

extension BugHunterScene: SKPhysicsContactDelegate {

    func didBegin(_ contact: SKPhysicsContact) {
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB

        let netBody = (bodyA.categoryBitMask & PhysicsCategory.net != 0) ? bodyA : bodyB
        let bugBody = (bodyA.categoryBitMask & PhysicsCategory.bug != 0) ? bodyA : bodyB

        guard netBody.categoryBitMask & PhysicsCategory.net != 0,
              bugBody.categoryBitMask & PhysicsCategory.bug  != 0 else { return }

        guard let netNode = netBody.node as? NetProjectile,
              let bugNode = bugBody.node as? BugNode else { return }

        // Prevent double-firing
        bugNode.physicsBody = nil
        netNode.physicsBody = nil

        // Capture animations
        bugNode.captured()
        netNode.playCapture()

        onBugCaptured?(bugNode)
    }
}
