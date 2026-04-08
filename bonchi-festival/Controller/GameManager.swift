//
//  GameManager.swift
//  bonchi-festival
//
//  iOS Controller: game state, 90-second countdown timer, and score management.
//

import Foundation
import Combine
import MultipeerConnectivity

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

    // MARK: Dependencies

    let multipeerSession = MultipeerSession()
    private var timerCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Init

    init() {
        multipeerSession.delegate = self
        multipeerSession.start()

        // Mirror MultipeerSession's isConnected into our own @Published
        multipeerSession.$isConnected
            .receive(on: RunLoop.main)
            .assign(to: \.isConnected, on: self)
            .store(in: &cancellables)
    }

    // MARK: Actions

    /// Start a new 90-second game round.
    func startGame() {
        score = 0
        timeRemaining = 90.0
        state = .playing
        multipeerSession.send(.startGame())
        startTimer()
    }

    /// Reset everything back to the waiting screen.
    func resetGame() {
        timerCancellable?.cancel()
        score = 0
        timeRemaining = 90.0
        state = .waiting
        multipeerSession.send(.resetGame())
    }

    /// Encode a slingshot launch and forward it to the projector.
    func sendLaunch(angle: Float, power: Float) {
        let payload = LaunchPayload(
            angle: angle,
            power: power,
            timestamp: Date().timeIntervalSince1970
        )
        multipeerSession.send(.launch(payload))
    }

    // MARK: Private

    private func startTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.timeRemaining = max(0, self.timeRemaining - 0.1)
                if self.timeRemaining <= 0 {
                    self.timerCancellable?.cancel()
                    self.state = .finished
                }
            }
    }
}

// MARK: - MultipeerSessionDelegate

extension GameManager: MultipeerSessionDelegate {

    func session(_ session: MultipeerSession, didReceive message: GameMessage, from peer: MCPeerID) {
        switch message.type {
        case .gameState:
            if let payload = message.gameStatePayload {
                score = payload.score
                timeRemaining = payload.timeRemaining
            }
        default:
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
