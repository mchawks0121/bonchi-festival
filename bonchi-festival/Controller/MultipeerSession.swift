//
//  MultipeerSession.swift
//  bonchi-festival
//
//  iOS Controller: Multipeer Connectivity wrapper.
//  Acts as both Advertiser (visible to other devices) and Browser (finds the Projector).
//

import Foundation
import MultipeerConnectivity

// MARK: - Delegate

protocol MultipeerSessionDelegate: AnyObject {
    func session(_ session: MultipeerSession, didReceive message: GameMessage, from peer: MCPeerID)
    func session(_ session: MultipeerSession, peerDidConnect peer: MCPeerID)
    func session(_ session: MultipeerSession, peerDidDisconnect peer: MCPeerID)
}

// MARK: - MultipeerSession

/// Manages Multipeer Connectivity for the iOS controller device.
final class MultipeerSession: NSObject, ObservableObject {

    /// Must match `ProjectorGameManager.serviceType`.
    static let serviceType = "bughunter-game"

    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private var mcSession: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    @Published var connectedPeers: [MCPeerID] = []
    @Published var isConnected: Bool = false

    weak var delegate: MultipeerSessionDelegate?

    override init() {
        super.init()
        mcSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self

        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self

        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser.delegate = self
    }

    /// Start advertising and browsing.
    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    /// Stop all Multipeer activity and disconnect.
    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        mcSession.disconnect()
    }

    /// Encode and send a `GameMessage` to all connected peers.
    func send(_ message: GameMessage) {
        guard !mcSession.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(message) else { return }
        try? mcSession.send(data, toPeers: mcSession.connectedPeers, with: .reliable)
    }
}

// MARK: - MCSessionDelegate

extension MultipeerSession: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                self.isConnected = !self.connectedPeers.isEmpty
                self.delegate?.session(self, peerDidConnect: peerID)
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                self.isConnected = !self.connectedPeers.isEmpty
                self.delegate?.session(self, peerDidDisconnect: peerID)
            default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(GameMessage.self, from: data) else { return }
        DispatchQueue.main.async {
            self.delegate?.session(self, didReceive: message, from: peerID)
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

extension MultipeerSession: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, mcSession)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerSession: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
