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

    /// URL at which the local preview HTTP server can be reached, or nil when the
    /// server is not running (i.e. projector-server mode is not selected).
    @Published var previewURL: URL? = nil

    /// World-space camera transform captured during calibration.
    /// When set, bug spawns are centered on this position instead of the live camera.
    var worldOriginTransform: simd_float4x4? = nil

    /// The live ARBugScene rendered by the on-device ARSKView.
    @Published var arBugScene: ARBugScene?

    // MARK: Dependencies

    let multipeerSession = MultipeerSession()
    private let previewServer = PreviewServer()
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
        // Stop Multipeer Connectivity if leaving client mode.
        if gameMode == .projectorClient { multipeerSession.stop() }
        // Stop the preview server if leaving projector-server mode.
        if gameMode == .projectorServer { stopPreviewServer() }
        gameMode = mode
        if mode == .projectorClient { multipeerSession.start() }
        // Start the preview server whenever projector-server mode is selected so the
        // operator can monitor the game from any browser on the same Wi-Fi network.
        if mode == .projectorServer { startPreviewServer() }
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
    /// origin, then immediately begin the game.
    func setWorldOrigin(transform: simd_float4x4) {
        worldOriginTransform = transform
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
        if gameMode == .projectorClient { multipeerSession.send(.resetGame()) }
    }

    // MARK: - Preview server

    private func startPreviewServer() {
        previewServer.htmlProvider = { [weak self] in self?.buildPreviewHTML() ?? "" }
        previewServer.start()
        previewURL = previewServer.previewURL
    }

    private func stopPreviewServer() {
        previewServer.stop()
        previewURL = nil
    }

    /// Threshold below which the time remaining is highlighted in red on the preview page.
    private static let previewTimeWarningThreshold: Double = 10.0
    /// CSS hex color for time values above the warning threshold.
    private static let previewTimeNormalColor = "#ffffff"
    /// CSS hex color for time values at or below the warning threshold.
    private static let previewTimeWarningColor = "#ff5577"
    /// CSS hex color for the "waiting" / "calibrating" state badge.
    private static let previewColorWaiting  = "#33ffcc"
    /// CSS hex color for the "playing" state badge.
    private static let previewColorPlaying  = "#ffcc00"
    /// CSS hex color for the "finished" state badge and the time-warning highlight.
    private static let previewColorFinished = "#ff5577"
    /// CSS hex color for the score value.
    private static let previewColorScore    = "#ffcc00"

    /// Builds the full HTML document served on each preview page request.
    /// The document includes a CSS-styled status panel with the current game state,
    /// time remaining, and score.  A `<meta http-equiv="refresh">` tag causes the
    /// browser to auto-reload every 3 seconds, keeping the displayed values current.
    ///
    /// - Note: This method is invoked from `PreviewServer`'s background queue via the
    ///   `htmlProvider` closure.  All accessed properties (`state`, `timeRemaining`,
    ///   `score`) are value types read without synchronisation; minor tearing is
    ///   acceptable for a non-critical status page.
    /// - Returns: A complete UTF-8 HTML document string.
    private func buildPreviewHTML() -> String {
        let stateLabel: String
        let stateClass: String
        switch state {
        case .waiting:    stateLabel = "待機中 / WAITING";   stateClass = "waiting"
        case .calibrating: stateLabel = "準備中 / READY";    stateClass = "waiting"
        case .playing:    stateLabel = "プレイ中 / PLAYING"; stateClass = "playing"
        case .finished:   stateLabel = "終了 / FINISHED";   stateClass = "finished"
        }
        let timeStr   = String(format: "%.1f", timeRemaining)
        let timeColor = timeRemaining < Self.previewTimeWarningThreshold
            ? Self.previewTimeWarningColor
            : Self.previewTimeNormalColor

        return """
        <!DOCTYPE html>
        <html lang="ja">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="refresh" content="3">
          <title>BugHunter プレビュー</title>
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
              min-height: 100vh;
              background: linear-gradient(180deg, #0a0533 0%, #020208 100%);
              color: #fff;
              font-family: 'Courier New', monospace;
              display: flex; flex-direction: column;
              align-items: center; justify-content: center;
              padding: 40px 20px;
            }
            h1 { font-size: 2rem; color: \(Self.previewColorWaiting); letter-spacing: 4px; margin-bottom: 8px; }
            .subtitle { color: rgba(102,187,255,0.75); font-size: 0.85rem;
                        margin-bottom: 48px; letter-spacing: 1px; }
            .state-badge {
              font-size: 1rem; padding: 10px 28px;
              border-radius: 999px; border: 1.5px solid currentColor;
              margin-bottom: 36px; letter-spacing: 2px;
            }
            .waiting  { color: \(Self.previewColorWaiting);  }
            .playing  { color: \(Self.previewColorPlaying);  }
            .finished { color: \(Self.previewColorFinished); }
            .grid {
              display: grid; grid-template-columns: 1fr 1fr;
              gap: 16px; max-width: 400px; width: 100%; margin-bottom: 32px;
            }
            .card {
              background: rgba(255,255,255,0.06);
              border: 1px solid rgba(255,255,255,0.1);
              border-radius: 16px; padding: 20px; text-align: center;
            }
            .card .label {
              font-size: 0.6rem; color: rgba(255,255,255,0.45);
              letter-spacing: 2px; margin-bottom: 8px;
            }
            .card .value { font-size: 2rem; font-weight: bold; }
            .wide { grid-column: span 2; }
            footer { color: rgba(255,255,255,0.25); font-size: 0.7rem; }
          </style>
        </head>
        <body>
          <h1>🐛 BUG HUNTER</h1>
          <p class="subtitle">ぼんち祭り バグハンター — プロジェクタープレビュー</p>
          <div class="state-badge \(stateClass)">\(stateLabel)</div>
          <div class="grid">
            <div class="card">
              <div class="label">TIME</div>
              <div class="value" style="color:\(timeColor)">\(timeStr)</div>
            </div>
            <div class="card">
              <div class="label">SCORE</div>
              <div class="value" style="color:\(Self.previewColorScore)">\(score)</div>
            </div>
          </div>
          <footer>3秒ごとに自動更新 • BugHunter Projector Preview</footer>
        </body>
        </html>
        """
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
            // In projector-client mode the score is accumulated exclusively from
            // `bugCaptured` messages sent by the projector.  The local ARBugScene
            // runs with zero captured bugs (no AR spawning), so its score is always 0;
            // syncing it here would wipe out every point earned via bugCaptured.
            if self.gameMode == .standalone {
                self.score = score
            }
            self.timeRemaining = timeRemaining
        }
    }

    func sceneDidFinish(_ scene: SKScene, finalScore: Int) {
        DispatchQueue.main.async {
            // Same reasoning as above: preserve the bugCaptured-accumulated score
            // in projector-client mode instead of overwriting with the scene's 0.
            if self.gameMode == .standalone {
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

