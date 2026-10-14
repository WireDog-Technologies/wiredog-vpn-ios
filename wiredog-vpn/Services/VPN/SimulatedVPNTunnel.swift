import Foundation
import NetworkExtension

/// Debug-only stand-in for the Network Extension tunnel, so the tvOS UI can be exercised in the
/// simulator (which can't run a packet tunnel). It plugs into the existing `VPNTunnelManagerProviding`
/// seam: `VPNService` runs its normal connect/disconnect/state flow against a fake connection that
/// walks connecting → connected, and skips the backend's /vpn/connect so no real connection counter
/// is touched. Everything below is compiled out unless this is a Debug build on the tvOS simulator;
/// Release builds, and Debug builds on a real Apple TV, use the real tunnel exactly as before.
enum VPNSimulation {
    #if DEBUG && targetEnvironment(simulator) && os(tvOS)
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    /// Simulated sessions are never known to the backend, so /disconnect must never be sent for them.
    static let sessionPrefix = "sim-"

    static func isSimulated(sessionId: String) -> Bool {
        sessionId.hasPrefix(sessionPrefix)
    }
}

#if DEBUG && targetEnvironment(simulator) && os(tvOS)

extension VPNSimulation {
    /// Stand-in for the backend's /vpn/connect response. Uses documentation-range addresses
    /// (RFC 5737) and an obviously fake key, so nothing here can reach a real server.
    static func connectResponse(serverId: String) -> ConnectResponse {
        ConnectResponse(
            config: WireGuardConfigResponse(
                privateKey: "SIMULATED-PRIVATE-KEY",
                address: "10.0.0.2/32",
                dns: "10.0.0.1",
                peer: PeerConfig(
                    publicKey: "SIMULATED-PUBLIC-KEY",
                    endpoint: "192.0.2.1:51820",
                    allowedIPs: "0.0.0.0/0, ::/0",
                    persistentKeepalive: 25
                ),
                awg: AwgParams(jc: 0, jmin: 0, jmax: 0, s1: 0, s2: 0, h1: 1, h2: 2, h3: 3, h4: 4)
            ),
            sessionId: sessionPrefix + UUID().uuidString.lowercased(),
            server: ServerInfo(id: serverId, city: nil, stateCode: nil, ipAddress: "192.0.2.1", exitIp: "203.0.113.10")
        )
    }
}

final class SimulatedVPNConnection: VPNConnectionManaging {
    private(set) var status: NEVPNStatus = .disconnected
    private var bytesReceived: UInt64 = 0
    private var bytesSent: UInt64 = 0

    /// How long the fake handshake takes before reporting connected.
    var connectDelay: TimeInterval = 1.5
    var disconnectDelay: TimeInterval = 0.5

    func startVPNTunnel(options: [String: NSObject]?) throws {
        bytesReceived = 0
        bytesSent = 0
        transition(to: .connecting)
        DispatchQueue.main.asyncAfter(deadline: .now() + connectDelay) { [weak self] in
            guard let self, self.status == .connecting else { return }
            self.transition(to: .connected)
        }
    }

    func stopVPNTunnel() {
        guard status != .disconnected else { return }
        transition(to: .disconnecting)
        DispatchQueue.main.asyncAfter(deadline: .now() + disconnectDelay) { [weak self] in
            guard let self, self.status == .disconnecting else { return }
            self.transition(to: .disconnected)
        }
    }

    /// Plausible, ever-growing traffic numbers so the stats UI has something to show.
    func nextStatistics() -> TunnelStatistics {
        bytesReceived += UInt64.random(in: 20_000...400_000)
        bytesSent += UInt64.random(in: 5_000...80_000)
        return TunnelStatistics(bytesReceived: bytesReceived, bytesSent: bytesSent, lastHandshake: Date())
    }

    private func transition(to newStatus: NEVPNStatus) {
        status = newStatus
        // VPNService observes NEVPNStatusDidChange on its connection object, same as the real one.
        NotificationCenter.default.post(name: .NEVPNStatusDidChange, object: self)
    }
}

final class SimulatedVPNTunnelManager: VPNTunnelManaging {
    var protocolConfiguration: NEVPNProtocol? = NETunnelProviderProtocol()
    var localizedDescription: String?
    var isEnabled = false
    var onDemandRules: [NEOnDemandRule]?
    var isOnDemandEnabled = false

    let connection = SimulatedVPNConnection()
    var vpnConnection: VPNConnectionManaging { connection }

    func saveToPreferences() async throws {}
    func loadFromPreferences() async throws {}
    func removeFromPreferences() async throws {}
}

struct SimulatedVPNTunnelManagerProvider: VPNTunnelManagerProviding {
    private let manager = SimulatedVPNTunnelManager()

    func loadAllFromPreferences() async throws -> [VPNTunnelManaging] { [] }
    func makeNew() -> VPNTunnelManaging { manager }
}

#endif
