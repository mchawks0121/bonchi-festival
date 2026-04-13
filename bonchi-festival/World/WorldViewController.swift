//
//  WorldViewController.swift
//  bonchi-festival
//
//  Projector World: root UIViewController.
//  Hosts the SpriteKit scenes and bridges Multipeer Connectivity messages
//  to the active game scene.
//

import UIKit
import SpriteKit

// MARK: - WorldViewController

/// Install this as the rootViewController on the projector device.
final class WorldViewController: UIViewController {

    private var skView: SKView!
    private var gameScene: BugHunterScene?
    let projectorManager = ProjectorGameManager()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        skView = SKView(frame: view.bounds)
        skView.autoresizingMask     = [.flexibleWidth, .flexibleHeight]
        skView.ignoresSiblingOrder  = true
        // Uncomment during development:
        // skView.showsFPS            = true
        // skView.showsNodeCount      = true
        view.addSubview(skView)

        projectorManager.delegate = self
        projectorManager.start()

        presentWaitingScene()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - Scene Transitions

    private func presentWaitingScene() {
        gameScene = nil
        let scene = WaitingScene(size: skView.bounds.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene, transition: SKTransition.fade(withDuration: 0.4))
    }

    private func startGame() {
        let scene = BugHunterScene(size: skView.bounds.size)
        scene.scaleMode   = .resizeFill
        scene.gameDelegate = self
        gameScene = scene
        skView.presentScene(scene, transition: SKTransition.fade(withDuration: 0.5))
    }

    /// Forward a net-launch event to the active game scene.
    func fireNet(angle: Float, power: Float) {
        gameScene?.fireNet(angle: angle, power: power)
    }
}

// MARK: - BugHunterSceneDelegate

extension WorldViewController: BugHunterSceneDelegate {

    func scene(_ scene: SKScene, didUpdateScore score: Int, timeRemaining: Double) {
        let payload = GameStatePayload(state: "playing", score: score, timeRemaining: timeRemaining)
        projectorManager.sendGameState(payload)
    }

    func sceneDidFinish(_ scene: SKScene, finalScore: Int) {
        let payload = GameStatePayload(state: "finished", score: finalScore, timeRemaining: 0)
        projectorManager.sendGameState(payload)

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.presentWaitingScene()
        }
    }
}

// MARK: - ProjectorGameManagerDelegate

extension WorldViewController: ProjectorGameManagerDelegate {

    func managerDidReceiveStartGame(_ manager: ProjectorGameManager) {
        DispatchQueue.main.async { self.startGame() }
    }

    func managerDidReceiveReset(_ manager: ProjectorGameManager) {
        DispatchQueue.main.async { self.presentWaitingScene() }
    }

    func manager(_ manager: ProjectorGameManager, didReceiveLaunch payload: LaunchPayload) {
        DispatchQueue.main.async { self.fireNet(angle: payload.angle, power: payload.power) }
    }
}
