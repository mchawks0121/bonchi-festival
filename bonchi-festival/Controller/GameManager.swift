//
//  GameManager.swift
//  bonchi-festival
//
//  iOS Controller: game state, score management, and local AR scene ownership.
//  The game runs entirely on-device using an ARSKView-hosted ARBugScene.
//  When a projector IS connected it also receives launch / state events.
//

import Foundation
import Combine
import MultipeerConnectivity
import UIKit

// MARK: - GameManager

/// Drives game state on the iOS controller side.
final class GameManager: ObservableObject {

    // MARK: State

    enum GameState: String {
        case waiting  = "waiting"
        case playing  = "playing"
        case finished = "finished"
    }

    @Published var state: GameState = .waiting
    @Published var score: Int = 0
    @Published var timeRemaining: Double = 90.0
    @Published var isConnected: Bool = false

    /// The live ARBugScene rendered by the on-device ARSKView.
    @Published var arBugScene: ARBugScene?

    // MARK: Dependencies

    let multipeerSession = MultipeerSession()
    private var cancellables = Set<AnyCancellable>()

    // MARK: Init

    init() {
        multipeerSession.delegate = self
        multipeerSession.start()

        multipeerSession.$isConnected
            .receive(on: RunLoop.main)
            .assign(to: \.isConnected, on: self)
            .store(in: &cancellables)
    }

    // MARK: Actions

    /// Start a new 90-second game round on-device (and signal the projector if connected).
    func startGame() {
        score = 0
        timeRemaining = 90.0

        let screenSize = UIScreen.main.bounds.size
        let scene = ARBugScene(size: screenSize)
        scene.scaleMode    = .resizeFill
        scene.gameDelegate = self
        arBugScene = scene

        state = .playing
        multipeerSession.send(.startGame())
    }

    /// Reset everything back to the waiting screen.
    func resetGame() {
        arBugScene = nil
        score = 0
        timeRemaining = 90.0
        state = .waiting
        multipeerSession.send(.resetGame())
    }

    /// Fire the slingshot: launch on the local AR scene and forward to the projector.
    func sendLaunch(angle: Float, power: Float) {
        // Fire locally on the on-device AR scene
        arBugScene?.fireNet(angle: angle, power: power)

        // Also send to the projector if one is connected
        let payload = LaunchPayload(
            angle: angle,
            power: power,
            timestamp: Date().timeIntervalSince1970
        )
        multipeerSession.send(.launch(payload))
    }
}

// MARK: - BugHunterSceneDelegate

extension GameManager: BugHunterSceneDelegate {

    func scene(_ scene: SKScene, didUpdateScore score: Int, timeRemaining: Double) {
        DispatchQueue.main.async {
            self.score = score
            self.timeRemaining = timeRemaining
        }
    }

    func sceneDidFinish(_ scene: SKScene, finalScore: Int) {
        DispatchQueue.main.async {
            self.score = finalScore
            self.timeRemaining = 0
            self.state = .finished
        }
    }
}

// MARK: - MultipeerSessionDelegate

extension GameManager: MultipeerSessionDelegate {

    func session(_ session: MultipeerSession, didReceive message: GameMessage, from peer: MCPeerID) {
        // iOS drives its own game state from the local AR scene.
        // Projector gameState messages are intentionally ignored.
    }

    func session(_ session: MultipeerSession, peerDidConnect peer: MCPeerID) {
        isConnected = true
    }

    func session(_ session: MultipeerSession, peerDidDisconnect peer: MCPeerID) {
        isConnected = !session.connectedPeers.isEmpty
    }
}

