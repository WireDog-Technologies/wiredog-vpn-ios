import Foundation
import NetworkExtension
import UIKit

enum VPNError: LocalizedError {
    case alreadyConnecting
    case managerNotAvailable
    case invalidConfiguration
    case connectionFailed(String)
    case tunnelStartFailed(Error)
    case notConnected
    case subscriptionExpired
    case notAuthenticated
    case anotherVPNActive

    var errorDescription: String? {
        switch self {
        case .alreadyConnecting:
            return "VPN is already connecting"
        case .managerNotAvailable:
            return "VPN manager not available"
        case .invalidConfiguration:
            return "Invalid VPN configuration"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .tunnelStartFailed(let error):
            return "Failed to start VPN tunnel: \(error.localizedDescription)"
        case .notConnected:
            return "VPN is not connected"
        case .subscriptionExpired:
            return "Your subscription has expired. Please renew your subscription to continue using the VPN."
        case .notAuthenticated:
            return "You are not authenticated. Please log in to use the VPN."
        case .anotherVPNActive:
            return "Another VPN configuration is selected. Go to Settings > VPN, and select WireDog VPN."
        }
    }
}

@MainActor
class VPNService: ObservableObject {
    static let shared = VPNService()

    @Published var connectionState: ConnectionState = .disconnected
    @Published var currentServerId: String?
    @Published var sessionId: String?
    @Published var statistics: TunnelStatistics?
    @Published var error: VPNError?
    @Published var isReconnecting = false
    @Published var isConnectionHealthy = true

    private var vpnManager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var statisticsTimer: Timer?
    private var userInitiatedDisconnect = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private var reconnectTask: Task<Void, Never>?
    private var lastKillSwitchEnabled = false
    private var lastIPv6Enabled = true
    private var lastLANAccessEnabled = true
    private var lastBlockAdsEnabled = true
    private var lastBlockMalwareEnabled = true
    private var lastSuccessfulHandshake: Date?
    private var lastStatsResponse: Date?
    private var foregroundedAt: Date?
    // WireGuard renegotiates session keys every 120s (REKEY_AFTER_TIME). last_handshake_time_sec is only
    // updated on a full cryptographic handshake — NOT on keepalive packets. A healthy connection can
    // legitimately have a handshake up to ~180s old, so the threshold must exceed that.
    private static let staleHandshakeThreshold: TimeInterval = 190
    private static let foregroundGracePeriod: TimeInterval = 8

    private init() {
        Task {
            await loadVPNManager()
        }

        // Fires before the run loop resumes timers — guarantees isConnectionHealthy = true
        // is set before any health check can run, giving benefit of the doubt on foreground.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.connectionState == .connected else { return }
            self.isConnectionHealthy = true
            self.foregroundedAt = Date()
        }
    }

    // MARK: - VPN Manager Setup

    private func loadVPNManager() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()

            // Remove any stale profiles that don't match our bundle ID
            let bundleId = Config.tunnelBundleIdentifier
            let stale = managers.filter {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier != bundleId
            }
            for manager in stale {
                try? await manager.removeFromPreferences()
            }

            let matching = managers.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundleId
            }

            self.vpnManager = matching ?? createNewVPNManager()

            observeVPNStatus()
            updateConnectionState()

            if let storedSessionId = UserDefaults.standard.string(forKey: "vpn_session_id") {
                if connectionState == .connected {
                    // Tunnel survived the app kill (iOS Network Extension keeps running).
                    // Restore the session token so disconnect() can notify the backend correctly.
                    self.sessionId = storedSessionId
                    LogService.shared.logService("VPN: Restored session token after app relaunch")
                } else {
                    // Tunnel is gone — call /disconnect to decrement the backend counter.
                    UserDefaults.standard.removeObject(forKey: "vpn_session_id")
                    LogService.shared.logService("VPN: Crash recovery — calling disconnect for stale session")
                    Task {
                        _ = try? await APIClient.shared.request(
                            endpoint: .disconnect,
                            body: DisconnectRequest(sessionId: storedSessionId)
                        ) as DisconnectResponse
                    }
                }
            }
        } catch {
            LogService.shared.logService("VPN manager load failed: \(error)", level: .error)
        }
    }

    private func createNewVPNManager() -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()

        let protocolConfig = NETunnelProviderProtocol()
        protocolConfig.providerBundleIdentifier = Config.tunnelBundleIdentifier
        protocolConfig.serverAddress = "WireDog VPN"

        manager.protocolConfiguration = protocolConfig
        manager.localizedDescription = "WireDog VPN"
        manager.isEnabled = true

        return manager
    }

    // MARK: - Kill Switch Configuration

    private func configureKillSwitch(enabled: Bool, lanAccessEnabled: Bool = true, for manager: NETunnelProviderManager) {
        guard let protocolConfig = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            return
        }

        if enabled {
            // Enable kill switch via includeAllNetworks (iOS 14+)
            if #available(iOS 14.0, *) {
                protocolConfig.includeAllNetworks = true
                protocolConfig.excludeLocalNetworks = lanAccessEnabled
            }

            // Configure on-demand rules for always-on VPN
            let connectRule = NEOnDemandRuleConnect()
            connectRule.interfaceTypeMatch = .any

            manager.onDemandRules = [connectRule]
            manager.isOnDemandEnabled = true
        } else {
            // Disable kill switch
            if #available(iOS 14.0, *) {
                protocolConfig.includeAllNetworks = false
                protocolConfig.excludeLocalNetworks = false
            }

            manager.onDemandRules = []
            manager.isOnDemandEnabled = false
        }
    }

    // MARK: - Connection Methods

    func connect(serverId: String, killSwitchEnabled: Bool, ipv6Enabled: Bool = true, lanAccessEnabled: Bool = true, blockAdsEnabled: Bool = true, blockMalwareEnabled: Bool = true) async throws {
        LogService.shared.logService("Connect initiated for server \(serverId)")

        guard connectionState == .disconnected || isReconnecting else {
            LogService.shared.logService("Connect failed: already connecting", level: .error)
            throw VPNError.alreadyConnecting
        }

        // Verify subscription before attempting to connect
        let authService = AuthService.shared
        guard authService.isAuthenticated else {
            LogService.shared.logService("Connect failed: not authenticated", level: .error)
            throw VPNError.notAuthenticated
        }

        // Refresh user profile to ensure subscription data is current
        do {
            try await authService.fetchUserProfile()
        } catch {
            LogService.shared.logService("Connect failed: unable to refresh subscription status", level: .error)
            throw VPNError.connectionFailed("Unable to verify subscription status")
        }

        guard let user = authService.currentUser else {
            LogService.shared.logService("Connect failed: not authenticated", level: .error)
            throw VPNError.notAuthenticated
        }

        // Check if subscription exists and is active
        guard let expiresAt = user.subscriptionExpiresAt, expiresAt > Date() else {
            LogService.shared.logService("Connect failed: subscription expired", level: .error)
            throw VPNError.subscriptionExpired
        }

        connectionState = .connecting
        error = nil
        isConnectionHealthy = true
        lastSuccessfulHandshake = nil
        lastStatsResponse = nil
        if !isReconnecting {
            userInitiatedDisconnect = false
            reconnectAttempts = 0
        }
        lastKillSwitchEnabled = killSwitchEnabled
        lastIPv6Enabled = ipv6Enabled
        lastLANAccessEnabled = lanAccessEnabled
        lastBlockAdsEnabled = blockAdsEnabled
        lastBlockMalwareEnabled = blockMalwareEnabled

        do {
            // Phase 1: Fetch WireGuard configuration from API
            let connectRequest = ConnectRequest(serverId: serverId, blockAds: blockAdsEnabled, blockMalware: blockMalwareEnabled)
            let response: ConnectResponse = try await APIClient.shared.request(
                endpoint: .connect,
                body: connectRequest
            )

            // TODO: Test whether vpn_session_id can be replayed to re-authenticate with the backend.
            // If it can, migrate this to Keychain (same pattern as auth token in KeychainService).
            self.sessionId = response.sessionId
            UserDefaults.standard.set(response.sessionId, forKey: "vpn_session_id")
            self.currentServerId = serverId
            LogService.shared.logService("Connecting to server \(serverId)")

            // Phase 2: Build WireGuard configuration
            let wgConfig = TunnelConfigService.buildWgQuickConfig(from: response.config, ipv6Enabled: ipv6Enabled)

            // Phase 3: Configure and start VPN
            guard let manager = vpnManager else {
                throw VPNError.managerNotAvailable
            }

            guard let protocolConfig = manager.protocolConfiguration as? NETunnelProviderProtocol else {
                throw VPNError.invalidConfiguration
            }

            // Configure kill switch
            configureKillSwitch(enabled: killSwitchEnabled, lanAccessEnabled: lanAccessEnabled, for: manager)

            // TODO: Confirm with backend that WireGuard keypairs are rotated on every /connect call.
            // If keys are long-lived (same key reused across sessions), add server-side rotation.
            // Store config in provider configuration
            protocolConfig.providerConfiguration = ["wgConfig": wgConfig]

            // Save preferences
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()

            // Start the tunnel
            let options: [String: NSObject] = ["wgConfig": wgConfig as NSObject]
            try manager.connection.startVPNTunnel(options: options)

            // Start statistics polling
            startStatisticsPolling()
            LogService.shared.logService("VPN tunnel started for server \(serverId)")

        } catch let vpnError as VPNError {
            LogService.shared.logService("Connect failed: \(vpnError.localizedDescription ?? "unknown error")", level: .error)
            connectionState = .disconnected
            self.error = vpnError
            throw vpnError
        } catch let nsError as NSError where nsError.domain == NEVPNErrorDomain {
            LogService.shared.logService("Connect failed: NEVPNError \(nsError.code) — \(nsError.localizedDescription)", level: .error)
            connectionState = .disconnected
            let vpnError = Self.mapNEVPNError(nsError)
            self.error = vpnError
            throw vpnError
        } catch {
            LogService.shared.logService("Connect failed: \(error.localizedDescription)", level: .error)
            connectionState = .disconnected
            let vpnError = VPNError.connectionFailed(error.localizedDescription)
            self.error = vpnError
            throw vpnError
        }
    }

    /// Maps a raw NEVPNError into a user-facing VPNError. NEVPNError.configurationDisabled (code 2)
    /// is the opaque "operation couldn't be completed" error iOS returns when startVPNTunnel
    /// can't proceed — in practice this fires when another VPN app's configuration is active,
    /// since iOS disables all other VPN configurations while one is connected.
    private static func mapNEVPNError(_ nsError: NSError) -> VPNError {
        guard let code = NEVPNError.Code(rawValue: nsError.code) else {
            return .connectionFailed(nsError.localizedDescription)
        }
        switch code {
        case .configurationDisabled:
            return .anotherVPNActive
        case .configurationInvalid, .configurationStale, .configurationUnknown:
            return .invalidConfiguration
        case .connectionFailed, .configurationReadWriteFailed:
            return .connectionFailed(nsError.localizedDescription)
        @unknown default:
            return .connectionFailed(nsError.localizedDescription)
        }
    }

    func disconnect() async {
        guard connectionState == .connected || connectionState == .connecting else { return }

        userInitiatedDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        isConnectionHealthy = true
        connectionState = .disconnecting

        // Stop statistics polling
        stopStatisticsPolling()

        let capturedSessionId = sessionId
        self.sessionId = nil
        UserDefaults.standard.removeObject(forKey: "vpn_session_id")
        self.currentServerId = nil

        // Disable kill switch before stopping tunnel so the user has internet while disconnected.
        // It will be re-enabled on the next connect if the setting is still on.
        if lastKillSwitchEnabled, let manager = vpnManager {
            configureKillSwitch(enabled: false, for: manager)
            try? await manager.saveToPreferences()
            try? await manager.loadFromPreferences()
        }

        // Stop VPN tunnel
        vpnManager?.connection.stopVPNTunnel()
        LogService.shared.logService("VPN disconnecting")

        // Notify backend after tunnel stops — non-critical, best-effort
        if let sessionId = capturedSessionId {
            Task.detached {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s for tunnel to fully stop
                _ = try? await APIClient.shared.request(
                    endpoint: .disconnect,
                    body: DisconnectRequest(sessionId: sessionId)
                ) as DisconnectResponse
            }
        }
        // Connection state will be updated by status observer
    }

    // MARK: - Status Observation

    private func observeVPNStatus() {
        // Remove existing observer if any
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: vpnManager?.connection,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateConnectionState()
            }
        }
    }

    private func updateConnectionState() {
        guard let status = vpnManager?.connection.status else {
            connectionState = .disconnected
            return
        }

        switch status {
        case .invalid, .disconnected:
            let wasActive = connectionState == .connected || connectionState == .connecting || connectionState == .disconnecting
            LogService.shared.logService("VPN status: disconnected")
            connectionState = .disconnected
            stopStatisticsPolling()

            // Auto-reconnect on unexpected disconnect
            if wasActive && !userInitiatedDisconnect && currentServerId != nil {
                attemptReconnect()
            }
        case .connecting, .reasserting:
            LogService.shared.logService("VPN status: connecting")
            connectionState = .connecting
        case .connected:
            LogService.shared.logService("VPN status: connected")
            connectionState = .connected
            isReconnecting = false
            reconnectAttempts = 0
            if statisticsTimer == nil {
                startStatisticsPolling()
            }
        case .disconnecting:
            LogService.shared.logService("VPN status: disconnecting")
            connectionState = .disconnecting
        @unknown default:
            LogService.shared.logService("VPN status: unknown", level: .warning)
            connectionState = .disconnected
        }
    }

    // MARK: - Auto-Reconnect

    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts,
              let serverId = currentServerId else {
            isReconnecting = false
            if reconnectAttempts >= maxReconnectAttempts {
                LogService.shared.logService("Reconnection failed after \(maxReconnectAttempts) attempts", level: .error)
                error = .connectionFailed("Reconnection failed after \(maxReconnectAttempts) attempts")
            }
            return
        }

        isReconnecting = true
        reconnectAttempts += 1
        LogService.shared.logService("Auto-reconnect attempt \(reconnectAttempts)/\(maxReconnectAttempts)", level: .warning)

        // Exponential backoff with jitter: 1s, 2s, 4s, 8s, 15s max
        let baseDelay = min(pow(2.0, Double(reconnectAttempts - 1)), 15.0)
        let jitterFactor = Double.random(in: 0.5...1.5)
        let delay = baseDelay * jitterFactor

        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled, !userInitiatedDisconnect else { return }

            do {
                try await connect(
                    serverId: serverId,
                    killSwitchEnabled: lastKillSwitchEnabled,
                    ipv6Enabled: lastIPv6Enabled,
                    lanAccessEnabled: lastLANAccessEnabled,
                    blockAdsEnabled: lastBlockAdsEnabled,
                    blockMalwareEnabled: lastBlockMalwareEnabled
                )
            } catch {
                // Will retry via updateConnectionState when disconnect is detected again
                LogService.shared.logService("Reconnect attempt \(reconnectAttempts) failed: \(error.localizedDescription)", level: .warning)
            }
        }
    }

    // MARK: - Statistics

    private func startStatisticsPolling() {
        stopStatisticsPolling()
        statisticsTimer = Timer.scheduledTimer(
            withTimeInterval: Config.statisticsPollingInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchStatistics()
            }
        }
    }

    private func stopStatisticsPolling() {
        statisticsTimer?.invalidate()
        statisticsTimer = nil
        statistics = nil
    }

    private func fetchStatistics() async {
        guard let session = vpnManager?.connection as? NETunnelProviderSession else {
            checkConnectionHealth()
            return
        }

        let message = TunnelMessage(type: .getStatistics)
        guard let messageData = try? JSONEncoder().encode(message) else { return }

        do {
            try session.sendProviderMessage(messageData) { [weak self] responseData in
                guard let data = responseData,
                      let stats = try? JSONDecoder().decode(TunnelStatistics.self, from: data) else {
                    Task { @MainActor in
                        self?.checkConnectionHealth()
                    }
                    return
                }

                Task { @MainActor in
                    self?.statistics = stats
                    self?.lastStatsResponse = Date()

                    if let lastHandshake = stats.lastHandshake {
                        self?.lastSuccessfulHandshake = lastHandshake
                    }

                    self?.checkConnectionHealth()
                }
            }
        } catch {
            LogService.shared.logService("Failed to fetch statistics: \(error)", level: .error)
            checkConnectionHealth()
        }
    }

    private func checkConnectionHealth() {
        guard connectionState == .connected else { return }

        // After foregrounding, give WireGuard time to complete a fresh handshake before
        // evaluating health — stale background-era timestamps would cause false positives.
        if let foregroundedAt = foregroundedAt,
           Date().timeIntervalSince(foregroundedAt) < Self.foregroundGracePeriod {
            isConnectionHealthy = true
            return
        }

        // Use the most recent handshake we've ever seen during this session
        if let lastHandshake = lastSuccessfulHandshake {
            let elapsed = Date().timeIntervalSince(lastHandshake)
            let newHealth = elapsed < Self.staleHandshakeThreshold
            if newHealth != isConnectionHealthy && !newHealth {
                LogService.shared.logService("Connection unhealthy: stale handshake (\(String(format: "%.1f", elapsed))s old)", level: .warning)
            }
            isConnectionHealthy = newHealth
        } else if let lastResponse = lastStatsResponse {
            // We're getting stats but have never seen a handshake — check how long we've been waiting
            let elapsed = Date().timeIntervalSince(lastResponse)
            let newHealth = elapsed < Self.staleHandshakeThreshold
            if newHealth != isConnectionHealthy && !newHealth {
                LogService.shared.logService("Connection unhealthy: no handshake response (\(String(format: "%.1f", elapsed))s)", level: .warning)
            }
            isConnectionHealthy = newHealth
        } else {
            // No stats at all yet — give it a grace period from when we connected
            // After the threshold, mark unhealthy
            // (stats polling starts immediately on connect, so if we still have nothing, something's wrong)
        }
    }

    /// Called when the app returns to the foreground. Triggers an immediate stats fetch
    /// so fresh WireGuard data is available as soon as possible. Health state and grace
    /// period are already set by the willEnterForeground notification observer in init.
    func handleAppForeground() {
        guard connectionState == .connected else { return }
        Task { await fetchStatistics() }
    }

    deinit {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        statisticsTimer?.invalidate()
    }
}
