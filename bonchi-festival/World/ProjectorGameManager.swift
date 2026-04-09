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
    func manager(_ manager: ProjectorGameManager, didReceiveLaunch payload: LaunchPayload)
}

// MARK: - ProjectorGameManager

/// Manages Multipeer Connectivity on the Projector (World) side.
final class ProjectorGameManager: NSObject {

    /// Must match `MultipeerSession.serviceType`.
    static let serviceType = "bughunter-game"

    private let myPeerID = MCPeerID(displayName: "BugHunter-Projector")
    private var mcSession: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

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

    /// Send the current game state back to the iOS controller.
    func sendGameState(_ payload: GameStatePayload) {
        let message = GameMessage.gameState(payload)
        guard !mcSession.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(message) else { return }
        try? mcSession.send(data, toPeers: mcSession.connectedPeers, with: .reliable)
    }
}

// MARK: - MCSessionDelegate

extension ProjectorGameManager: MCSessionDelegate {

    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {}

    func session(_ session: MCSession,
                 didReceive data: Data,
                 fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(GameMessage.self, from: data) else { return }
        DispatchQueue.main.async {
            switch message.type {
            case .startGame:
                self.delegate?.managerDidReceiveStartGame(self)
            case .resetGame:
                self.delegate?.managerDidReceiveReset(self)
            case .launch:
                if let payload = message.launchPayload {
                    self.delegate?.manager(self, didReceiveLaunch: payload)
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
