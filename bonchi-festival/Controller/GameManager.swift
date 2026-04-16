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
import ARKit

// MARK: - GameManager

/// Drives game state on the iOS controller side.
final class GameManager: ObservableObject {

    // MARK: State

    enum GameState: String {
        case waiting     = "waiting"
        case calibrating = "calibrating"
        case ready       = "ready"       // after calibration — first slingshot shot starts the game
        case playing     = "playing"
        case finished    = "finished"
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

    /// World-space camera transform captured during calibration.
    /// When set, bug spawns are centered on this position instead of the live camera.
    var worldOriginTransform: simd_float4x4? = nil

    /// The live ARBugScene rendered by the on-device ARSKView.
    @Published var arBugScene: ARBugScene?

    // MARK: Slingshot 3-D callbacks
    // These are set by ARGameView.Coordinator so that SlingshotView can communicate
    // drag state and fire events to the 3-D AR layer without a direct reference to
    // the Coordinator.  Both closures are called on the main thread.

    /// Called every time the drag state changes (or resets to .zero / false).
    var slingshotDragUpdate: ((CGSize, Bool) -> Void)?
    /// Called when the player releases the slingshot; passes the final drag offset and power.
    var onNetFired: ((CGSize, Float) -> Void)?

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

    /// Transition to the calibration screen so the player can set the AR world origin.
    /// In projector-server mode there is no AR session, so we skip straight to startGame().
    func startCalibration() {
        guard gameMode != .projectorServer else {
            startGame()
            return
        }
        worldOriginTransform = nil
        state = .calibrating
    }

    /// Record `transform` (typically the current AR camera transform) as the spawn
    /// origin, then transition to the ready screen where the first slingshot shot
    /// will signal game start.
    func setWorldOrigin(transform: simd_float4x4) {
        worldOriginTransform = transform
        state = .ready
    }

    /// Called when the player fires the slingshot from the ready screen.
    /// Transitions from `.ready` to `.playing` and starts the game clock + bug spawning.
    func confirmReady() {
        guard state == .ready else { return }
        startGame()
    }

    /// Start a new 90-second game round on-device (and signal the projector if connected).
    func startGame() {
        score = 0
        timeRemaining = 90.0
        state = .playing
        SoundManager.shared.playGameStart()

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
        worldOriginTransform = nil
        score = 0
        timeRemaining = 90.0
        state = .waiting
        slingshotDragUpdate = nil
        onNetFired = nil
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

    /// Notify the projector that a bug has appeared in the shared AR world.
    /// The projector will mirror the bug at the corresponding screen position.
    /// Only sent in projectorClient mode.
    func sendBugSpawned(id: String, type: BugType, normalizedX: Float, normalizedY: Float) {
        guard gameMode == .projectorClient else { return }
        let payload = BugSpawnedPayload(id: id, bugType: type,
                                        normalizedX: normalizedX, normalizedY: normalizedY)
        multipeerSession.send(.bugSpawned(payload))
    }

    /// Notify the projector that the phone's AR layer captured a bug (remove it from display).
    /// Only sent in projectorClient mode.
    func sendBugRemoved(id: String) {
        guard gameMode == .projectorClient else { return }
        let payload = BugRemovedPayload(id: id)
        multipeerSession.send(.bugRemoved(payload))
    }
}

// MARK: - BugHunterSceneDelegate

extension GameManager: BugHunterSceneDelegate {

    func scene(_ scene: SKScene, didUpdateScore score: Int, timeRemaining: Double) {
        DispatchQueue.main.async {
            // Phone is the score authority in both standalone and projectorClient modes.
            // projectorServer has no AR scene, so its score is always 0 — skip it.
            if self.gameMode != .projectorServer {
                self.score = score
            }
            self.timeRemaining = timeRemaining
        }
    }

    func sceneDidFinish(_ scene: SKScene, finalScore: Int) {
        DispatchQueue.main.async {
            if self.gameMode != .projectorServer {
                self.score = finalScore
            }
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

