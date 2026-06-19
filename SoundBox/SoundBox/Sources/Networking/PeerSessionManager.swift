import Foundation
import MultipeerConnectivity
import Observation

@MainActor
@Observable
final class PeerSessionManager: NSObject {
    static let shared = PeerSessionManager()

    var isCompanionConnected = false
    var connectedDeviceName: String?

    @ObservationIgnored private let serviceType = "soundbox-sync"
    @ObservationIgnored private lazy var myPeerId = MCPeerID(displayName: Host.current().localizedName ?? "SoundBox Mac")
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var session: MCSession?
    @ObservationIgnored private var lastSendTime: CFAbsoluteTime = 0
    @ObservationIgnored private let minSendInterval: TimeInterval = 1.0 / 15.0
    @ObservationIgnored private let encoder = JSONEncoder()

    private override init() {
        super.init()
    }

    func start() {
        let session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        print("[PeerSession] Advertising started as '\(myPeerId.displayName)'")
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        session?.disconnect()
        advertiser = nil
        session = nil
        isCompanionConnected = false
        connectedDeviceName = nil
    }

    func send(_ orientation: HeadOrientation) {
        guard let session, !session.connectedPeers.isEmpty else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSendTime >= minSendInterval else { return }
        lastSendTime = now

        let postureString: String
        switch orientation.postureState {
        case .good: postureString = "good"
        case .warning: postureString = "warning"
        case .poor: postureString = "poor"
        }

        let state = SpatialState(
            yaw: orientation.yaw,
            pitch: orientation.pitch,
            roll: orientation.roll,
            severity: orientation.severity,
            postureState: postureString
        )

        guard let data = try? encoder.encode(state) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .unreliable)
    }
}

extension PeerSessionManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.isCompanionConnected = true
                self.connectedDeviceName = peerID.displayName
            case .notConnected:
                let stillConnected = !session.connectedPeers.isEmpty
                self.isCompanionConnected = stillConnected
                if !stillConnected {
                    self.connectedDeviceName = nil
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension PeerSessionManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("[PeerSession] Received invitation from '\(peerID.displayName)'")
        Task { @MainActor in
            invitationHandler(true, self.session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("[PeerSession] Failed to advertise: \(error.localizedDescription)")
    }
}
