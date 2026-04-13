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
import SpriteKit

// MARK: - GameManager

/// Drives game state on the iOS controller side.
final class GameManager: ObservableObject {

    // MARK: State

    enum GameState: String {
        case waiting  = "waiting"
        case playing  = "playing"
        case finished = "finished"
    }

    /// Whether the game runs standalone (AR-only), as a projector controller (client),
    /// or as the projector display (server).
    enum GameMode: Equatable {
        case standalone
        case projectorClient   // iOS controller that forwards launches to the projector
        case projectorServer   // Projector display device that receives launches
    }

    @Published var state: GameState = .waiting
    @Published var score: Int = 0
    @Published var timeRemaining: Double = 90.0
    @Published var isConnected: Bool = false
    @Published var gameMode: GameMode = .standalone

    /// The live ARBugScene rendered by the on-device ARSKView.
    @Published var arBugScene: ARBugScene?

    // MARK: Dependencies

    let multipeerSession = MultipeerSession()
    private var cancellables = Set<AnyCancellable>()

    // MARK: Init

    init() {
        multipeerSession.delegate = self
        // MultipeerSession is started only when projector mode is selected.

        multipeerSession.$isConnected
            .receive(on: RunLoop.main)
            .assign(to: \.isConnected, on: self)
            .store(in: &cancellables)
    }

    // MARK: Mode selection

    /// Switch between standalone, projector-client, and projector-server modes.
    func selectMode(_ mode: GameMode) {
        guard mode != gameMode else { return }
        if gameMode == .projectorClient { multipeerSession.stop() }
        gameMode = mode
        if mode == .projectorClient { multipeerSession.start() }
    }

    // MARK: Actions

    /// Start a new 90-second game round on-device (and signal the projector if connected).
    func startGame() {
        score = 0
        timeRemaining = 90.0
        state = .playing

        // Projector-server mode: WorldViewController manages all its own UI.
        guard gameMode != .projectorServer else { return }

        let screenSize = UIScreen.main.bounds.size
        let scene = ARBugScene(size: screenSize)
        scene.scaleMode    = .resizeFill
        scene.gameDelegate = self
        arBugScene = scene

        if gameMode == .projectorClient { multipeerSession.send(.startGame()) }
    }

    /// Reset everything back to the waiting screen.
    func resetGame() {
        arBugScene = nil
        score = 0
        timeRemaining = 90.0
        state = .waiting
        if gameMode == .projectorClient { multipeerSession.send(.resetGame()) }
    }

    /// Fire the slingshot: launch on the local AR scene and forward to the projector.
    func sendLaunch(angle: Float, power: Float) {
        // Fire locally on the on-device AR scene
        arBugScene?.fireNet(angle: angle, power: power)

        // Also forward to the projector when in client mode
        if gameMode == .projectorClient {
            let payload = LaunchPayload(
                angle: angle,
                power: power,
                timestamp: Date().timeIntervalSince1970
            )
            multipeerSession.send(.launch(payload))
        }
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
        switch message.type {
        case .bugCaptured:
            // The projector notifies this specific iOS client that a bug it captured.
            // Add the bug's point value to the local score.
            if let payload = message.bugCapturedPayload {
                DispatchQueue.main.async {
                    self.score += payload.bugType.points
                }
            }
        default:
            // All other inbound projector messages (gameState, etc.) are intentionally ignored;
            // iOS drives its own timer and state from the local AR scene / UI.
            break
        }
    }

    func session(_ session: MultipeerSession, peerDidConnect peer: MCPeerID) {
        isConnected = true
    }

    func session(_ session: MultipeerSession, peerDidDisconnect peer: MCPeerID) {
        isConnected = !session.connectedPeers.isEmpty
    }
}

