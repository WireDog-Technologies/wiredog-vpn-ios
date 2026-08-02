import Foundation
import NetworkExtension
@testable import wiredog_vpn

/// Fully-controllable fake for `VPNConnectionManaging` — lets tests set `.status` directly and force
/// `startVPNTunnel` to throw a specific error, neither of which is possible against a real `NEVPNConnection`.
final class FakeVPNConnection: VPNConnectionManaging {
    var status: NEVPNStatus = .disconnected
    var startVPNTunnelError: Error?
    private(set) var startVPNTunnelCallCount = 0
    private(set) var stopVPNTunnelCallCount = 0
    /// Test-only hook invoked synchronously at the top of startVPNTunnel — lets tests deterministically
    /// cancel the enclosing Task at the exact point production code can't itself observe cancellation
    /// until after this call returns.
    var onStartVPNTunnel: (() -> Void)?

    func startVPNTunnel(options: [String: NSObject]?) throws {
        startVPNTunnelCallCount += 1
        onStartVPNTunnel?()
        if let error = startVPNTunnelError {
            throw error
        }
    }

    func stopVPNTunnel() {
        stopVPNTunnelCallCount += 1
    }
}

/// Fake for `VPNTunnelManaging`. Stores a real `NETunnelProviderProtocol` so `configureKillSwitch`'s
/// `as? NETunnelProviderProtocol` cast still succeeds — that class is safe to instantiate off-device,
/// only *activating* a tunnel requires an entitlement.
final class FakeVPNTunnelManager: VPNTunnelManaging {
    var protocolConfiguration: NEVPNProtocol? = NETunnelProviderProtocol()
    var localizedDescription: String?
    var isEnabled = false
    var onDemandRules: [NEOnDemandRule]?
    var isOnDemandEnabled = false

    let connection = FakeVPNConnection()
    var vpnConnection: VPNConnectionManaging { connection }

    var saveToPreferencesError: Error?
    var loadFromPreferencesError: Error?
    private(set) var saveToPreferencesCallCount = 0
    private(set) var loadFromPreferencesCallCount = 0
    private(set) var removeFromPreferencesCallCount = 0

    func saveToPreferences() async throws {
        saveToPreferencesCallCount += 1
        if let error = saveToPreferencesError { throw error }
    }

    func loadFromPreferences() async throws {
        loadFromPreferencesCallCount += 1
        if let error = loadFromPreferencesError { throw error }
    }

    func removeFromPreferences() async throws {
        removeFromPreferencesCallCount += 1
    }
}

/// Fake for `VPNTunnelManagerProviding` — hands out a single `FakeVPNTunnelManager` that the test
/// keeps a reference to, so `VPNService.connect()`'s `createNewVPNManager()` path (no existing
/// manager found in "preferences") always resolves to the same controllable fake.
final class FakeVPNTunnelManagerProvider: VPNTunnelManagerProviding {
    let manager: FakeVPNTunnelManager

    init(manager: FakeVPNTunnelManager = FakeVPNTunnelManager()) {
        self.manager = manager
    }

    func loadAllFromPreferences() async throws -> [VPNTunnelManaging] {
        []
    }

    func makeNew() -> VPNTunnelManaging {
        manager
    }
}

struct FakeError: Error, LocalizedError {
    let message: String
    init(_ message: String = "fake error") { self.message = message }
    var errorDescription: String? { message }
}
