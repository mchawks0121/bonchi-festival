//
//  ARGameView.swift
//  bonchi-festival
//
//  iOS Controller: SwiftUI wrapper for ARSKView.
//  Presents the BugHunterScene on top of the live camera feed so bugs
//  appear to inhabit the player's real-world environment.
//

import SwiftUI
import ARKit
import SpriteKit

// MARK: - ARGameView

/// Full-screen `ARSKView` that presents `gameManager.localScene` on top of the
/// live AR camera feed.  Automatically stops the AR session when the view is
/// removed from the hierarchy.
struct ARGameView: UIViewRepresentable {

    @EnvironmentObject var gameManager: GameManager

    func makeUIView(context: Context) -> ARSKView {
        let arView = ARSKView(frame: .zero)
        arView.ignoresSiblingOrder = true

        if let scene = gameManager.localScene {
            scene.scaleMode = .resizeFill
            arView.presentScene(scene)
        }

        let config = ARWorldTrackingConfiguration()
        arView.session.run(config)

        return arView
    }

    func updateUIView(_ uiView: ARSKView, context: Context) {
        // If the active scene has changed (e.g. game restarted) re-present it.
        if let scene = gameManager.localScene, uiView.scene !== scene {
            scene.scaleMode = .resizeFill
            uiView.presentScene(scene, transition: SKTransition.fade(withDuration: 0.3))
        }
    }

    static func dismantleUIView(_ uiView: ARSKView, coordinator: Void) {
        uiView.session.pause()
    }
}
