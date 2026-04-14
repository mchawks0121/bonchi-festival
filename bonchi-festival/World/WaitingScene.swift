//
//  WaitingScene.swift
//  bonchi-festival
//
//  Projector World: splash / lobby screen displayed while waiting for the iOS
//  controller to start the game.
//

import SpriteKit

/// Simple animated waiting screen shown on the projector before the game starts.
///
/// When `isProjectorOverlay` is `true` the background is transparent so the
/// SceneKit 3-D layer beneath shows through.  This ensures the projector display
/// is always fully 3-D — even during the inter-round waiting state.
final class WaitingScene: SKScene {

    /// Set to `true` when this scene is used as a transparent overlay over a
    /// SceneKit 3-D background (projector mode).  Set to `false` for standalone use.
    var isProjectorOverlay: Bool = false

    override func didMove(to view: SKView) {
        backgroundColor = isProjectorOverlay
            ? .clear
            : SKColor(red: 0.04, green: 0.08, blue: 0.04, alpha: 1)

        setupTitle()
        setupFloatingBugs()
        setupInstructions()
    }

    // MARK: - Setup

    private func setupTitle() {
        let title = SKLabelNode(text: "君は、バグハンター 🦟")
        title.fontName  = "HiraginoSans-W7"
        title.fontSize  = 80
        title.fontColor = .white
        title.position  = CGPoint(x: size.width / 2, y: size.height * 0.72)
        addChild(title)

        // Gentle pulsing scale animation
        let scaleUp   = SKAction.scale(to: 1.05, duration: 1.2)
        let scaleDown = SKAction.scale(to: 0.95, duration: 1.2)
        title.run(SKAction.repeatForever(SKAction.sequence([scaleUp, scaleDown])))

        let subtitle = SKLabelNode(text: "You are the Bug Hunter")
        subtitle.fontName  = "HiraginoSans-W3"
        subtitle.fontSize  = 40
        subtitle.fontColor = SKColor.white.withAlphaComponent(0.65)
        subtitle.position  = CGPoint(x: size.width / 2, y: size.height * 0.62)
        addChild(subtitle)
    }

    private func setupFloatingBugs() {
        let bugs: [(emoji: String, pts: Int)] = [("🦋", 1), ("🐛", 3), ("🪲", 5)]
        let spacing: CGFloat = 240
        let baseX = size.width / 2 - CGFloat(bugs.count - 1) * spacing / 2

        for (i, bug) in bugs.enumerated() {
            let container = SKNode()
            container.position = CGPoint(x: baseX + CGFloat(i) * spacing,
                                         y: size.height * 0.40)
            addChild(container)

            let emoji = SKLabelNode(text: bug.emoji)
            emoji.fontSize = 80
            emoji.verticalAlignmentMode   = .center
            emoji.horizontalAlignmentMode = .center
            container.addChild(emoji)

            let pts = SKLabelNode(text: "\(bug.pts) pt")
            pts.fontName  = "HiraginoSans-W7"
            pts.fontSize  = 36
            pts.fontColor = SKColor(red: 1, green: 0.85, blue: 0, alpha: 1)
            pts.position  = CGPoint(x: 0, y: -60)
            pts.verticalAlignmentMode   = .center
            pts.horizontalAlignmentMode = .center
            container.addChild(pts)

            // Float up and down with different phases
            let offset = Double(i) * 0.5
            let up   = SKAction.moveBy(x: 0, y: 18, duration: 1.0 + offset)
            let down = SKAction.moveBy(x: 0, y: -18, duration: 1.0 + offset)
            up.timingMode   = .easeInEaseOut
            down.timingMode = .easeInEaseOut
            container.run(SKAction.repeatForever(SKAction.sequence([up, down])))
        }
    }

    private func setupInstructions() {
        let waiting = SKLabelNode(text: "iOSコントローラーの接続を待っています…")
        waiting.fontName  = "HiraginoSans-W3"
        waiting.fontSize  = 34
        waiting.fontColor = SKColor.white.withAlphaComponent(0.55)
        waiting.position  = CGPoint(x: size.width / 2, y: size.height * 0.20)
        addChild(waiting)

        // Blinking dots animation
        let fadeOut = SKAction.fadeAlpha(to: 0.1, duration: 0.7)
        let fadeIn  = SKAction.fadeAlpha(to: 0.55, duration: 0.7)
        waiting.run(SKAction.repeatForever(SKAction.sequence([fadeOut, fadeIn])))

        let how = SKLabelNode(text: "スリングショットを引いて網を飛ばそう！")
        how.fontName  = "HiraginoSans-W3"
        how.fontSize  = 30
        how.fontColor = SKColor.white.withAlphaComponent(0.45)
        how.position  = CGPoint(x: size.width / 2, y: size.height * 0.12)
        addChild(how)
    }
}
