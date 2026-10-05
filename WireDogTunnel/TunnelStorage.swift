import Foundation

/// Shared (App Group) storage the extension reads/writes when it originates its own session — e.g.
/// a tunnel started standalone from iOS Settings > VPN rather than through the app. Key names are
/// duplicated literals rather than shared constants (VPNService.swift / ServerStorage.swift aren't
/// part of this target) — keep them in sync if either side's key ever changes:
///   - "lastConnectedServerId" ↔ ServerStorage.lastConnectedServerKey
///   - "lastConnectedGatewayId" ↔ ServerStorage.lastConnectedGatewayKey
///   - "vpn_session_id" ↔ VPNService.sessionIdKey
///   - "vpn_exit_ip" ↔ VPNService.exitIPKey ([sessionId: exitIp])
enum TunnelStorage {
    private static let lastConnectedServerKey = "lastConnectedServerId"
    private static let lastConnectedGatewayKey = "lastConnectedGatewayId"
    private static let sessionIdKey = "vpn_session_id"
    private static let exitIPKey = "vpn_exit_ip"

    /// Records the exit IP the backend assigned to a session this extension started, so the app
    /// can show it without an ipify lookup.
    static func setExitIP(_ exitIP: String?, forSession sessionId: String) {
        if let exitIP, !exitIP.isEmpty {
            TunnelConfig.sharedDefaults.set([sessionId: exitIP], forKey: exitIPKey)
        } else {
            TunnelConfig.sharedDefaults.removeObject(forKey: exitIPKey)
        }
    }

    static var lastConnectedServerId: String? {
        TunnelConfig.sharedDefaults.string(forKey: lastConnectedServerKey)
    }

    /// The organization's named Dedicated IP gateway the last connection used, nil for the shared
    /// network. (UserDefaults.integer returns 0 for a missing key and real ids start at 1.)
    static var lastConnectedGatewayId: Int? {
        let id = TunnelConfig.sharedDefaults.integer(forKey: lastConnectedGatewayKey)
        return id > 0 ? id : nil
    }

    static var sessionId: String? {
        get { TunnelConfig.sharedDefaults.string(forKey: sessionIdKey) }
        set {
            if let newValue {
                TunnelConfig.sharedDefaults.set(newValue, forKey: sessionIdKey)
            } else {
                TunnelConfig.sharedDefaults.removeObject(forKey: sessionIdKey)
            }
        }
    }
}

/// Guards against a Settings/on-demand retry storm: if standalone connect attempts keep failing
/// (e.g. an expired token), iOS's on-demand rule can re-invoke startTunnel repeatedly. Without this,
/// each retry would immediately re-hit the backend with a doomed /connect call. Backs off
/// exponentially (capped) between attempts instead.
enum TunnelStandaloneConnectBackoff {
    private static let failureCountKey = "standalone_connect_failure_count"
    private static let lastFailureAtKey = "standalone_connect_last_failure_at"
    private static let maxBackoffSeconds: TimeInterval = 300

    static func shouldAttempt() -> Bool {
        let defaults = TunnelConfig.sharedDefaults
        let count = defaults.integer(forKey: failureCountKey)
        guard count > 0 else { return true }

        let lastFailureAt = defaults.double(forKey: lastFailureAtKey)
        let backoff = min(pow(2.0, Double(count)), maxBackoffSeconds)
        return Date().timeIntervalSince1970 - lastFailureAt >= backoff
    }

    static func recordFailure() {
        let defaults = TunnelConfig.sharedDefaults
        let count = defaults.integer(forKey: failureCountKey) + 1
        defaults.set(count, forKey: failureCountKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastFailureAtKey)
    }

    static func recordSuccess() {
        let defaults = TunnelConfig.sharedDefaults
        defaults.removeObject(forKey: failureCountKey)
        defaults.removeObject(forKey: lastFailureAtKey)
    }
}
