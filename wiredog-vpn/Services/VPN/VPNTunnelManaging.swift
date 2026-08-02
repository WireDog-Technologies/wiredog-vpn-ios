import Foundation
import NetworkExtension

/// Thin seam over `NEVPNConnection` so `VPNService`'s connect/disconnect accounting logic can be
/// unit tested without a real Network Extension entitlement (which unit tests can't obtain).
protocol VPNConnectionManaging: AnyObject {
    var status: NEVPNStatus { get }
    func startVPNTunnel(options: [String: NSObject]?) throws
    func stopVPNTunnel()
}

/// Thin seam over `NETunnelProviderManager`. Production code wraps the real system type;
/// tests substitute a fully-controllable fake.
protocol VPNTunnelManaging: AnyObject {
    var protocolConfiguration: NEVPNProtocol? { get set }
    var localizedDescription: String? { get set }
    var isEnabled: Bool { get set }
    var onDemandRules: [NEOnDemandRule]? { get set }
    var isOnDemandEnabled: Bool { get set }
    var vpnConnection: VPNConnectionManaging { get }
    func saveToPreferences() async throws
    func loadFromPreferences() async throws
    func removeFromPreferences() async throws
}

/// Seam over `NETunnelProviderManager.loadAllFromPreferences()` / `NETunnelProviderManager()`,
/// both of which touch real system VPN configuration state.
protocol VPNTunnelManagerProviding {
    func loadAllFromPreferences() async throws -> [VPNTunnelManaging]
    func makeNew() -> VPNTunnelManaging
}

// MARK: - Production adapters

extension NEVPNConnection: VPNConnectionManaging {}

extension NETunnelProviderManager: VPNTunnelManaging {
    var vpnConnection: VPNConnectionManaging { self.connection }
}

struct SystemVPNTunnelManagerProvider: VPNTunnelManagerProviding {
    func loadAllFromPreferences() async throws -> [VPNTunnelManaging] {
        try await NETunnelProviderManager.loadAllFromPreferences().map { $0 as VPNTunnelManaging }
    }

    func makeNew() -> VPNTunnelManaging {
        NETunnelProviderManager()
    }
}
