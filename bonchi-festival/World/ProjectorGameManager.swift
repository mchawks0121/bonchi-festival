//
//  ProjectorGameManager.swift
//  bonchi-festival
//
//  Projector World: Multipeer Connectivity session for the projector device.
//  Advertises itself so the iOS controller can discover and connect.
//

import Foundation
import MultipeerConnectivity

// MARK: - Delegate

protocol ProjectorGameManagerDelegate: AnyObject {
    func managerDidReceiveStartGame(_ manager: ProjectorGameManager)
    func managerDidReceiveReset(_ manager: ProjectorGameManager)
    func manager(_ manager: ProjectorGameManager, didReceiveLaunch payload: LaunchPayload, playerIndex: Int)
    /// Called on the main thread whenever the set of connected players changes.
    func manager(_ manager: ProjectorGameManager, didUpdateConnectedPlayers players: [(name: String, playerIndex: Int)])
}

// MARK: - ProjectorGameManager

/// Manages Multipeer Connectivity on the Projector (World) side.
final class ProjectorGameManager: NSObject {

    /// Must match `MultipeerSession.serviceType`.
    static let serviceType = "bughunter-game"

    /// Maximum number of simultaneously connected clients.
    static let maxPlayers = 3

    private let myPeerID = MCPeerID(displayName: "BugHunter-Projector")
    private var mcSession: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    /// Maps each connected peer to its assigned player slot (0, 1, or 2).
    private var playerSlots: [MCPeerID: Int] = [:]
    /// Tracks which slots are currently occupied.
    private var usedSlots: Set<Int> = []

    weak var delegate: ProjectorGameManagerDelegate?

    override init() {
        super.init()
        mcSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self

        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: Self.serviceType
        )
        advertiser.delegate = self

        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser.delegate = self
    }

    // MARK: Lifecycle

    /// Start advertising and browsing for peers.
    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    /// Stop all network activity.
    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        mcSession.disconnect()
    }

    // MARK: Outgoing

    /// Send the current game state back to all connected iOS controllers.
    func sendGameState(_ payload: GameStatePayload) {
        let message = GameMessage.gameState(payload)
        guard !mcSession.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(message) else { return }
        try? mcSession.send(data, toPeers: mcSession.connectedPeers, with: .reliable)
    }

    // MARK: - Private helpers

    /// Returns a snapshot of connected players sorted by slot index, for display.
    private func connectedPlayerList() -> [(name: String, playerIndex: Int)] {
        playerSlots
            .map { (name: $0.key.displayName, playerIndex: $0.value) }
            .sorted { $0.playerIndex < $1.playerIndex }
    }

    private func notifyPlayersUpdate() {
        let players = connectedPlayerList()
        delegate?.manager(self, didUpdateConnectedPlayers: players)
    }
}

// MARK: - MCSessionDelegate

extension ProjectorGameManager: MCSessionDelegate {

    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                guard self.playerSlots[peerID] == nil else { break }
                // Assign the lowest available slot
                let slot = (0..<Self.maxPlayers).first { !self.usedSlots.contains($0) } ?? 0
                self.playerSlots[peerID] = slot
                self.usedSlots.insert(slot)
                self.notifyPlayersUpdate()
            case .notConnected:
                if let slot = self.playerSlots[peerID] {
                    self.usedSlots.remove(slot)
                    self.playerSlots.removeValue(forKey: peerID)
                    self.notifyPlayersUpdate()
                }
            default:
                break
            }
        }
    }

    func session(_ session: MCSession,
                 didReceive data: Data,
                 fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(GameMessage.self, from: data) else { return }
        let playerIndex = playerSlots[peerID] ?? 0
        DispatchQueue.main.async {
            switch message.type {
            case .startGame:
                self.delegate?.managerDidReceiveStartGame(self)
            case .resetGame:
                self.delegate?.managerDidReceiveReset(self)
            case .launch:
                if let payload = message.launchPayload {
                    self.delegate?.manager(self, didReceiveLaunch: payload, playerIndex: playerIndex)
                }
            default:
                break
            }
        }
    }

    func session(_ session: MCSession,
                 didReceive stream: InputStream,
                 withName streamName: String,
                 fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 with progress: Progress) {}

    func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 at localURL: URL?,
                 withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension ProjectorGameManager: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Reject new connections once the player cap is reached
        guard usedSlots.count < Self.maxPlayers else {
            invitationHandler(false, nil)
            return
        }
        invitationHandler(true, mcSession)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension ProjectorGameManager: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
