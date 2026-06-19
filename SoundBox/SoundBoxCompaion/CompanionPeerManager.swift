import Foundation
import MultipeerConnectivity
import Observation
import UIKit

@MainActor
@Observable
final class CompanionPeerManager: NSObject {
    var isConnected = false
    var connectedMacName: String?
    var currentState: SpatialState = .neutral

    @ObservationIgnored private let serviceType = "soundbox-sync"
    @ObservationIgnored private lazy var myPeerId = MCPeerID(displayName: UIDevice.current.name)
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var session: MCSession?

    func start() {
        let session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        self.session = session

        let browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        print("[Companion] Browsing started as '\(myPeerId.displayName)'")
    }

    func stop() {
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        browser = nil
        session = nil
        isConnected = false
        connectedMacName = nil
        currentState = .neutral
    }
}

extension CompanionPeerManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.isConnected = true
                self.connectedMacName = peerID.displayName
            case .notConnected:
                self.isConnected = false
                self.connectedMacName = nil
                self.currentState = .neutral
                self.browser?.startBrowsingForPeers()
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let state = try? JSONDecoder().decode(SpatialState.self, from: data) else { return }
        Task { @MainActor in
            self.currentState = state
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension CompanionPeerManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("[Companion] Found peer: '\(peerID.displayName)'")
        Task { @MainActor in
            guard let session = self.session else { return }
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("[Companion] Lost peer: '\(peerID.displayName)'")
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("[Companion] Failed to browse: \(error.localizedDescription)")
    }
}
