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
    case cancelled
    case deviceLimitReached

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
        case .cancelled:
            return "Connection cancelled"
        case .deviceLimitReached:
            return "You've reached your 5-device limit. Disconnect another device to continue."
        }
    }
}

@MainActor
class VPNService: ObservableObject {
    static let shared = VPNService()

    @Published var connectionState: ConnectionState = .disconnected
    @Published var currentServerId: String?
    // The organization gateway (named Dedicated IP) the current connection uses, if any. Kept so
    // auto-reconnect goes back through the same gateway instead of the shared network.
    private(set) var currentGatewayId: Int?
    @Published var sessionId: String?
    @Published var statistics: TunnelStatistics?
    @Published var error: VPNError?
    @Published var isReconnecting = false
    @Published var isConnectionHealthy = true

    private var vpnManager: VPNTunnelManaging?
    // Guards against firing two concurrent /disconnect calls for the same session — e.g.
    // loadVPNManager()'s cold-start retry and the willEnterForeground retry can both fire within
    // the same launch (SwiftUI's scene lifecycle posts willEnterForeground even on a cold start).
    // Without this, each would independently decrement the backend's (non-idempotent) counter.
    private var sessionsPendingCleanup: Set<String> = []
    // Tracks whether the willEnterForeground handler has fired at least once — its first firing
    // always coincides with cold launch (see init()), so it's skipped there in favor of
    // loadVPNManager()'s own retry.
    private var hasHandledFirstForegroundEvent = false
    private var statusObserver: NSObjectProtocol?
    private var statisticsTimer: Timer?
    private var userInitiatedDisconnect = false
    private var reconnectAttempts = 0
    var maxReconnectAttempts = 10
    private var reconnectTask: Task<Void, Never>?
    private var lastKillSwitchEnabled = false
    private var lastIPv6Enabled = true
    private var lastLANAccessEnabled = true
    private var lastBlockAdsEnabled = true
    private var lastBlockMalwareEnabled = true
    private var lastSuccessfulHandshake: Date?
    private var lastStatsResponse: Date?
    private var foregroundedAt: Date?
    private var connectedSince: Date?
    // WireGuard renegotiates session keys every 120s (REKEY_AFTER_TIME). last_handshake_time_sec is only
    // updated on a full cryptographic handshake — NOT on keepalive packets. A healthy connection can
    // legitimately have a handshake up to ~180s old, so the threshold must exceed that.
    private static let staleHandshakeThreshold: TimeInterval = 190
    private static let foregroundGracePeriod: TimeInterval = 8
    // A connection that drops before staying up this long never really established — clean up its
    // backend session slot immediately instead of blindly reconnecting and leaking another increment.
    static let defaultMinimumStableConnectionDuration: TimeInterval = 30
    var minimumStableConnectionDuration: TimeInterval = VPNService.defaultMinimumStableConnectionDuration
    // Exponential backoff base/cap for auto-reconnect: 1s, 2s, 4s, 8s, 15s max by default.
    var reconnectBaseDelay: TimeInterval = 1.0
    var reconnectMaxDelay: TimeInterval = 15.0
    // Delay before notifying the backend of an orphaned/dead session, to give the tunnel time to
    // fully stop. Overridable so tests don't have to wait on it.
    var disconnectNotifyDelayNanoseconds: UInt64 = 1_500_000_000
    private(set) var lastCleanupTask: Task<Void, Never>?

    private let apiClient: APIClient
    private let authService: AuthService
    private let tunnelManagerProvider: VPNTunnelManagerProviding

    init(
        apiClient: APIClient = .shared,
        authService: AuthService = .shared,
        tunnelManagerProvider: VPNTunnelManagerProviding = SystemVPNTunnelManagerProvider(),
        autoLoadOnInit: Bool = true
    ) {
        self.apiClient = apiClient
        self.authService = authService
        self.tunnelManagerProvider = tunnelManagerProvider

        if autoLoadOnInit {
            Task {
                await loadVPNManager()
            }
        }

        // Fires before the run loop resumes timers — guarantees isConnectionHealthy = true
        // is set before any health check can run, giving benefit of the doubt on foreground.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }

            // SwiftUI's scene lifecycle posts willEnterForeground once even on a cold launch, not
            // just when returning from the background — so this handler's very first firing in the
            // process's life always coincides with loadVPNManager()'s own cold-start retry (below).
            // Skip that one redundant call; every firing after that is a genuine background→foreground
            // return, where this retry is still needed (e.g. the app lost connectivity mid-cleanup and
            // the user reopened it instead of relaunching, so loadVPNManager() never ran again).
            if self.hasHandledFirstForegroundEvent {
                self.retryPendingDisconnects()
            } else {
                self.hasHandledFirstForegroundEvent = true
            }

            guard self.connectionState == .connected else { return }
            self.isConnectionHealthy = true
            self.foregroundedAt = Date()
        }
    }

    // MARK: - VPN Manager Setup

    func loadVPNManager() async {
        do {
            let managers = try await tunnelManagerProvider.loadAllFromPreferences()

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

            if let storedSessionId = Self.sharedDefaults.string(forKey: Self.sessionIdKey) {
                if connectionState == .connected {
                    // Tunnel survived the app kill (iOS Network Extension keeps running).
                    // Restore the session token so disconnect() can notify the backend correctly.
                    self.sessionId = storedSessionId
                    LogService.shared.logService("VPN: Restored session token after app relaunch")
                } else {
                    // Tunnel is gone — call /disconnect to decrement the backend counter.
                    Self.sharedDefaults.removeObject(forKey: Self.sessionIdKey)
                    cleanupOrphanedSession(storedSessionId, reason: "crash recovery — stale session")
                }
            }

            // Retry any /disconnect calls that were owed but never confirmed — e.g. the app lost
            // connectivity right as a previous cleanupOrphanedSession() call went out. Independent
            // of the crash-recovery check above, which only covers the single current session.
            retryPendingDisconnects()
        } catch {
            LogService.shared.logService("VPN manager load failed: \(error)", level: .error)
        }
    }

    private func createNewVPNManager() -> VPNTunnelManaging {
        let manager = tunnelManagerProvider.makeNew()

        let protocolConfig = NETunnelProviderProtocol()
        protocolConfig.providerBundleIdentifier = Config.tunnelBundleIdentifier
        protocolConfig.serverAddress = "WireDog VPN"

        manager.protocolConfiguration = protocolConfig
        manager.localizedDescription = "WireDog VPN"
        manager.isEnabled = true

        return manager
    }

    // MARK: - Kill Switch Configuration

    private func configureKillSwitch(enabled: Bool, lanAccessEnabled: Bool = true, for manager: VPNTunnelManaging) {
        guard let protocolConfig = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            return
        }

        if enabled {
            // Enable kill switch via includeAllNetworks (iOS 14+; unavailable on tvOS)
            #if os(iOS)
            if #available(iOS 14.0, *) {
                protocolConfig.includeAllNetworks = true
                protocolConfig.excludeLocalNetworks = lanAccessEnabled
            }
            #endif

            // Configure on-demand rules for always-on VPN
            let connectRule = NEOnDemandRuleConnect()
            connectRule.interfaceTypeMatch = .any

            manager.onDemandRules = [connectRule]
            manager.isOnDemandEnabled = true
        } else {
            // Disable kill switch
            #if os(iOS)
            if #available(iOS 14.0, *) {
                protocolConfig.includeAllNetworks = false
                protocolConfig.excludeLocalNetworks = false
            }
            #endif

            manager.onDemandRules = []
            manager.isOnDemandEnabled = false
        }
    }

    // MARK: - Connection Methods

    func connect(serverId: String, gatewayId: Int? = nil, killSwitchEnabled: Bool, ipv6Enabled: Bool = true, lanAccessEnabled: Bool = true, blockAdsEnabled: Bool = true, blockMalwareEnabled: Bool = true) async throws {
        LogService.shared.logService("Connect initiated for server \(serverId)")

        guard connectionState == .disconnected || isReconnecting else {
            LogService.shared.logService("Connect failed: already connecting", level: .error)
            throw VPNError.alreadyConnecting
        }

        // Verify subscription before attempting to connect
        guard authService.isAuthenticated else {
            LogService.shared.logService("Connect failed: not authenticated", level: .error)
            throw VPNError.notAuthenticated
        }

        // Refresh user profile to ensure subscription data is current. Reset pooled
        // connections first — a recent network change (e.g. app relaunch after switching
        // networks) can otherwise leave this request stuck on a dead socket and fail here
        // even though the session/subscription are actually fine.
        await apiClient.resetConnections()
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
        connectedSince = nil
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
            let connectRequest = ConnectRequest(serverId: serverId, blockAds: blockAdsEnabled, blockMalware: blockMalwareEnabled, dedicatedIpId: gatewayId)
            let response: ConnectResponse = try await apiClient.request(
                endpoint: .connect,
                body: connectRequest
            )

            // TODO: Test whether vpn_session_id can be replayed to re-authenticate with the backend.
            // If it can, migrate this to Keychain (same pattern as auth token in KeychainService).
            self.sessionId = response.sessionId
            Self.sharedDefaults.set(response.sessionId, forKey: Self.sessionIdKey)
            self.currentServerId = serverId
            self.currentGatewayId = gatewayId
            // Lets the WireDogTunnel extension know which server to reconnect to if it's ever
            // started standalone (e.g. from iOS Settings > VPN) rather than through the app.
            ServerStorage.setLastConnectedServer(serverId, gatewayId: gatewayId)
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

            // Assert enabled every connect, not just on first creation — a different VPN app (or
            // the user editing configs in Settings) can leave iOS having flipped our own manager's
            // isEnabled to false, which surfaces as NEVPNError.configurationDisabled on start.
            manager.isEnabled = true

            // TODO: Confirm with backend that WireGuard keypairs are rotated on every /connect call.
            // If keys are long-lived (same key reused across sessions), add server-side rotation.
            // Store config in provider configuration
            protocolConfig.providerConfiguration = ["wgConfig": wgConfig]

            // Save preferences
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()

            // A cancel (tap-again-to-cancel) may have arrived while awaiting the calls above —
            // check before starting the tunnel, since startVPNTunnel() itself isn't cancellable.
            try Task.checkCancellation()

            // Start the tunnel. iOS enforces a single active VPN tunnel system-wide — starting our
            // own tunnel here is sufficient to preempt whatever else (another app's VPN, or a
            // manually-selected system VPN profile) is currently connected; the OS tears the other
            // one down for us. See startTunnelWithAutoSwapRetry for the retry-on-conflict path.
            let options: [String: NSObject] = ["wgConfig": wgConfig as NSObject]
            try await startTunnelWithAutoSwapRetry(manager: manager, options: options)

            // The tunnel just started — if a cancel landed in the narrow window right around this
            // call, tear it back down immediately rather than leaving an untracked live tunnel.
            if Task.isCancelled {
                // Clear the shared sessionId *before* stopping — same ordering as disconnect().
                // The extension's stopTunnel() treats a still-present shared sessionId as "nobody
                // else is telling the backend about this," and calls /disconnect itself; clearing
                // it first here (rather than after, in cleanupLeakedSessionIfNeeded() below) avoids
                // a race where both the extension and this method's own cleanup call /disconnect
                // for the same session — the backend's /disconnect isn't idempotent, so a double
                // call would double-decrement the device counter, not just double-notify it.
                Self.sharedDefaults.removeObject(forKey: Self.sessionIdKey)
                manager.vpnConnection.stopVPNTunnel()
                throw CancellationError()
            }

            // Start statistics polling
            startStatisticsPolling()
            LogService.shared.logService("VPN tunnel started for server \(serverId)")

        } catch let vpnError as VPNError {
            LogService.shared.logService("Connect failed: \(vpnError.localizedDescription ?? "unknown error")", level: .error)
            cleanupLeakedSessionIfNeeded()
            connectionState = .disconnected
            self.error = vpnError
            throw vpnError
        } catch let nsError as NSError where nsError.domain == NEVPNErrorDomain {
            LogService.shared.logService("Connect failed: NEVPNError \(nsError.code) — \(nsError.localizedDescription)", level: .error)
            cleanupLeakedSessionIfNeeded()
            connectionState = .disconnected
            let vpnError = Self.mapNEVPNError(nsError)
            self.error = vpnError
            throw vpnError
        } catch APIError.deviceLimitReached {
            LogService.shared.logService("Connect failed: device limit reached", level: .error)
            cleanupLeakedSessionIfNeeded()
            connectionState = .disconnected
            let vpnError = VPNError.deviceLimitReached
            self.error = vpnError
            throw vpnError
        } catch {
            cleanupLeakedSessionIfNeeded()
            connectionState = .disconnected
            if Self.isCancellation(error) {
                // User-initiated cancel (tap-again-to-cancel) — expected, not a failure.
                // Don't publish `self.error`, so no error alert surfaces for it.
                LogService.shared.logService("Connect cancelled")
                throw VPNError.cancelled
            }
            LogService.shared.logService("Connect failed: \(error.localizedDescription)", level: .error)
            let vpnError = VPNError.connectionFailed(error.localizedDescription)
            self.error = vpnError
            throw vpnError
        }
    }

    /// True if `error` represents a cancelled operation — either a native `CancellationError`
    /// (from `Task.checkCancellation()`/our own explicit throw) or a cancelled network request
    /// (`URLSession` surfaces Task cancellation as `URLError.cancelled`, which `APIClient` wraps
    /// as `APIError.networkError`).
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if let apiError = error as? APIError,
           case .networkError(let underlying) = apiError,
           let urlError = underlying as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }

    /// If connect() obtained a sessionId (and thus incremented the backend's device counter) before
    /// failing, notify the backend so the counter doesn't leak. No-op if we failed before that point.
    func cleanupLeakedSessionIfNeeded() {
        guard let leaked = self.sessionId else { return }
        cleanupOrphanedSession(leaked, reason: "connect() threw after sessionId obtained")
        self.sessionId = nil
        Self.sharedDefaults.removeObject(forKey: Self.sessionIdKey)
        if !isReconnecting {
            self.currentServerId = nil
            self.currentGatewayId = nil
        }
    }

    /// Starts our tunnel, auto-swapping in for whatever VPN (ours or another app's) is currently
    /// active. iOS enforces a single active tunnel system-wide, so simply starting our own tunnel
    /// is normally enough for the OS to preempt the other one — this is the standard way VPN apps
    /// handle switching on iOS. NEVPNError.configurationDisabled on the first attempt usually
    /// means our own manager's `isEnabled` flag had drifted to false (e.g. iOS reacting to another
    /// VPN app's config being edited/activated), not that the swap itself is disallowed — so we
    /// re-assert `isEnabled`, re-save/reload, and retry once before surfacing it as a real error.
    private func startTunnelWithAutoSwapRetry(manager: VPNTunnelManaging, options: [String: NSObject]) async throws {
        do {
            try manager.vpnConnection.startVPNTunnel(options: options)
        } catch let nsError as NSError where nsError.domain == NEVPNErrorDomain
            && nsError.code == NEVPNError.Code.configurationDisabled.rawValue {
            LogService.shared.logService("Tunnel start hit configurationDisabled — retrying after re-enabling manager", level: .warning)
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            try manager.vpnConnection.startVPNTunnel(options: options)
        }
    }

    /// Maps a raw NEVPNError into a user-facing VPNError. NEVPNError.configurationDisabled (code 2)
    /// surviving the enable/save/reload retry in startTunnelWithAutoSwapRetry indicates a genuine
    /// edge case (e.g. an MDM-enforced VPN profile the user isn't permitted to override) rather
    /// than the common "another VPN app is active" case, which the retry now resolves on its own.
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

    /// Cancels an in-progress auto-reconnect loop (backoff wait or an active retry attempt).
    /// No-ops if not currently reconnecting — an in-flight *first* connect attempt is cancelled
    /// by the caller cancelling its own wrapping Task instead, since connect() is cancellation-aware.
    /// If a session was already claimed by the most recent retry attempt, disconnects it so the
    /// counter stays net-zero even if this fires mid-retry rather than during the backoff wait.
    func cancelConnect() {
        guard isReconnecting else { return }
        userInitiatedDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        reconnectAttempts = 0
        if sessionId != nil {
            Task { await disconnect() }
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
        Self.sharedDefaults.removeObject(forKey: Self.sessionIdKey)
        self.currentServerId = nil
        self.currentGatewayId = nil
        self.connectedSince = nil

        // Disable kill switch before stopping tunnel so the user has internet while disconnected.
        // It will be re-enabled on the next connect if the setting is still on.
        if lastKillSwitchEnabled, let manager = vpnManager {
            configureKillSwitch(enabled: false, for: manager)
            try? await manager.saveToPreferences()
            try? await manager.loadFromPreferences()
        }

        // Stop VPN tunnel
        vpnManager?.vpnConnection.stopVPNTunnel()
        LogService.shared.logService("VPN disconnecting")

        // Notify backend after tunnel stops — non-critical, best-effort
        if let capturedSessionId = capturedSessionId {
            cleanupOrphanedSession(capturedSessionId, reason: "user-initiated disconnect")
        }
        // Connection state will be updated by status observer
    }

    /// Best-effort notification to the backend that a session is no longer valid, so its device-count
    /// slot is released. Captures `sessionId` by value so an in-flight cleanup for an old session can
    /// never race against / target a newer session's token obtained after this call was made.
    ///
    /// The sessionId is persisted to a durable pending-disconnect list *before* the network call is
    /// attempted, and only removed on confirmed success — if the app has no connectivity right now
    /// (e.g. mid-airplane-mode), the call fails silently as before, but the record survives so
    /// `retryPendingDisconnects()` can retry it on next launch instead of leaking the counter forever.
    func cleanupOrphanedSession(_ sessionId: String, reason: String) {
        // Guards against firing two concurrent /disconnect calls for the same session — e.g.
        // loadVPNManager()'s cold-start retry and the willEnterForeground retry can both fire within
        // the same launch. Without this, each would independently decrement the backend's
        // (non-idempotent) counter.
        guard !sessionsPendingCleanup.contains(sessionId) else { return }
        sessionsPendingCleanup.insert(sessionId)

        LogService.shared.logService("VPN: cleaning up orphaned session (\(reason))")
        Self.addPendingDisconnect(sessionId)
        let delay = disconnectNotifyDelayNanoseconds
        let client = apiClient
        lastCleanupTask = Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: delay) // time for tunnel to fully stop
            do {
                // The backend's /disconnect response body doesn't have a stable/decodable shape
                // worth depending on (it's just a human-readable message) — requestVoid skips
                // decoding entirely and only cares whether the call succeeded.
                try await client.requestVoid(
                    endpoint: .disconnect,
                    body: DisconnectRequest(sessionId: sessionId)
                )
                Self.removePendingDisconnect(sessionId)
            } catch {
                // Left in the pending list — retried via retryPendingDisconnects() on next launch.
            }
            await MainActor.run { self?.sessionsPendingCleanup.remove(sessionId) }
        }
    }

    // MARK: - Pending Disconnect Retry

    /// Durable record of sessionIds still owed a confirmed /disconnect. `nonisolated` and backed only
    /// by UserDefaults (thread-safe) + a serial queue, so it can be touched from the detached cleanup
    /// Task without hopping back to the main actor.
    private nonisolated static let pendingDisconnectsKey = "vpn_pending_disconnect_ids"
    private nonisolated static let pendingDisconnectsQueue = DispatchQueue(label: "com.wiredog.vpn.pendingDisconnects")

    /// Shared (App Group) storage for the active session's id — not UserDefaults.standard, since the
    /// WireDogTunnel extension can now originate its own session (a Settings-app-initiated connect)
    /// and needs the app's crash-recovery reconciliation in loadVPNManager() to see it too.
    nonisolated static let sessionIdKey = "vpn_session_id"
    private nonisolated static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: Config.appGroupIdentifier) ?? .standard
    }

    private nonisolated static func addPendingDisconnect(_ sessionId: String) {
        pendingDisconnectsQueue.sync {
            var ids = Set(UserDefaults.standard.stringArray(forKey: pendingDisconnectsKey) ?? [])
            ids.insert(sessionId)
            UserDefaults.standard.set(Array(ids), forKey: pendingDisconnectsKey)
        }
    }

    private nonisolated static func removePendingDisconnect(_ sessionId: String) {
        pendingDisconnectsQueue.sync {
            var ids = Set(UserDefaults.standard.stringArray(forKey: pendingDisconnectsKey) ?? [])
            ids.remove(sessionId)
            UserDefaults.standard.set(Array(ids), forKey: pendingDisconnectsKey)
        }
    }

    nonisolated static func pendingDisconnectIds() -> [String] {
        pendingDisconnectsQueue.sync {
            UserDefaults.standard.stringArray(forKey: pendingDisconnectsKey) ?? []
        }
    }

    /// Retries any /disconnect calls that were owed but never confirmed — e.g. the app had no
    /// connectivity right as cleanupOrphanedSession()'s fire-and-forget call went out, so nothing
    /// ever reached the backend. The backend's /disconnect is NOT idempotent (it unconditionally
    /// decrements on every valid call), so cleanupOrphanedSession()'s per-session in-flight guard is
    /// what keeps a repeated retry from double-decrementing a session that's already being retried.
    func retryPendingDisconnects() {
        for sessionId in Self.pendingDisconnectIds() {
            cleanupOrphanedSession(sessionId, reason: "retrying pending disconnect from previous launch")
        }
    }

    // MARK: - Status Observation

    private func observeVPNStatus() {
        // Remove existing observer if any
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: vpnManager?.vpnConnection,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateConnectionState()
            }
        }
    }

    func updateConnectionState() {
        guard let status = vpnManager?.vpnConnection.status else {
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
                let wasStable = connectedSince.map {
                    Date().timeIntervalSince($0) >= minimumStableConnectionDuration
                } ?? false

                // Connection never proved itself stable — clean up its slot rather than letting the
                // upcoming reconnect attempt leak another increment on top of this orphaned one.
                if !wasStable, let staleSessionId = sessionId {
                    cleanupOrphanedSession(
                        staleSessionId,
                        reason: "dropped before \(Int(minimumStableConnectionDuration))s stability threshold"
                    )
                }
                sessionId = nil
                Self.sharedDefaults.removeObject(forKey: Self.sessionIdKey)
                connectedSince = nil

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
            connectedSince = Date()
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

    func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts,
              let serverId = currentServerId else {
            isReconnecting = false
            if reconnectAttempts >= maxReconnectAttempts {
                LogService.shared.logService("Reconnection failed after \(maxReconnectAttempts) attempts", level: .error)
                error = .connectionFailed("Reconnection failed after \(maxReconnectAttempts) attempts")
                if let staleSessionId = sessionId {
                    cleanupOrphanedSession(staleSessionId, reason: "reconnect attempts exhausted")
                    sessionId = nil
                    Self.sharedDefaults.removeObject(forKey: Self.sessionIdKey)
                }
                currentServerId = nil
                currentGatewayId = nil
            }
            return
        }

        isReconnecting = true
        reconnectAttempts += 1
        LogService.shared.logService("Auto-reconnect attempt \(reconnectAttempts)/\(maxReconnectAttempts)", level: .warning)

        // Exponential backoff with jitter, scaled by reconnectBaseDelay/reconnectMaxDelay
        // (defaults: 1s, 2s, 4s, 8s, 15s max)
        let baseDelay = min(reconnectBaseDelay * pow(2.0, Double(reconnectAttempts - 1)), reconnectMaxDelay)
        let jitterFactor = Double.random(in: 0.5...1.5)
        let delay = baseDelay * jitterFactor

        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled, !userInitiatedDisconnect else { return }

            do {
                try await connect(
                    serverId: serverId,
                    gatewayId: currentGatewayId,
                    killSwitchEnabled: lastKillSwitchEnabled,
                    ipv6Enabled: lastIPv6Enabled,
                    lanAccessEnabled: lastLANAccessEnabled,
                    blockAdsEnabled: lastBlockAdsEnabled,
                    blockMalwareEnabled: lastBlockMalwareEnabled
                )
            } catch VPNError.anotherVPNActive {
                // Not a transient failure — retrying against a system VPN slot another app
                // owns will just fail the same way every time until the user switches back
                // to WireDog in Settings. Stop the loop instead of burning all retry attempts.
                LogService.shared.logService("Reconnect aborted: another VPN configuration is active", level: .error)
                isReconnecting = false
                reconnectAttempts = 0
                currentServerId = nil
                currentGatewayId = nil
                if let staleSessionId = sessionId {
                    cleanupOrphanedSession(staleSessionId, reason: "reconnect aborted — another VPN active")
                    sessionId = nil
                    Self.sharedDefaults.removeObject(forKey: Self.sessionIdKey)
                }
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
        guard let session = vpnManager?.vpnConnection as? NETunnelProviderSession else {
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
