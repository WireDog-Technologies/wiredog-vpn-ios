import Foundation
import Combine
import Network
import UIKit

@MainActor
class VPNManager: ObservableObject {
    // MARK: - Published Properties
    @Published var connectionState: ConnectionState = .disconnected
    @Published var selectedServer: Server?
    @Published var connectionStats: ConnectionStats
    @Published var settings: VPNSettings = VPNSettings()
    @Published var availableServers: [Server] = []
    @Published var recommendedServers: [Server] = []
    @Published var recentServers: [Server] = []
    @Published var favoriteServers: [Server] = []
    @Published var connectionDuration: TimeInterval = 0
    @Published var user: User?
    @Published var publicIP: String?
    @Published var originalIP: String?
    @Published var currentLocation: String?
    @Published var isLoading = false
    @Published var isFetchingNetworkInfo = false
    /// True while a server switch is tearing down the old tunnel before bringing up the new
    /// one. Lets the UI (e.g. the map marker) treat that whole disconnect-old → connect-new
    /// sequence as one continuous "in progress" state instead of flickering through the
    /// intermediate connected/disconnected values `connectionState` genuinely passes through.
    @Published private(set) var isSwitchingServer = false
    @Published var isConnectionHealthy = true
    @Published var errorMessage: String?
    @Published var needsSubscription: Bool = false
    @Published var showReviewPrompt: Bool = false
    private(set) var pendingServer: Server? = nil

    // MARK: - Services
    private let vpnService = VPNService.shared
    private let authService = AuthService.shared
    private let ipService = IPService.shared

    // MARK: - Private Properties
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var serverCacheTimestamp: Date?
    private let serverCacheTTL: TimeInterval = 5 * 60 // 5 minutes
    private var lastAPIServers: [APIServer] = []
    private static let lastConnectedServerKey = "lastConnectedServerId"
    private static let userManuallyDisconnectedKey = "userManuallyDisconnected"
    private static let connectedAtKey = "vpnConnectedAt"
    private var hasRecordedReviewPromptForCurrentConnection = false
    private var connectTask: Task<Void, Never>?

    // Network monitoring for auto-connect triggers
    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "com.wiredog.vpn.pathmonitor", qos: .utility)
    private var isInitialPathUpdate = true
    private var networkAutoConnectTask: Task<Void, Never>?

    // Foreground latency polling
    private var latencyPollingTask: Task<Void, Never>?
    private static let latencyPollingInterval: TimeInterval = 60
    private static let latencyPollingJitter: TimeInterval = 20

    // MARK: - Initialization

    init() {
        self.connectionStats = ConnectionStats(
            downloadSpeed: 0,
            uploadSpeed: 0,
            connectionTime: 0,
            dataTransferred: 0
        )

        self.settings = SettingsStorage.loadSettings()

        setupBindings()
        setupSettingsObserver()

        // Load initial data
        Task {
            await loadServers()
            await fetchPublicIP()
            if self.originalIP == nil, let currentIP = self.publicIP {
                self.originalIP = currentIP
            }
            await fetchGeoLocation()
            await measureLatencies()
            startLatencyPolling()
        }

        // Monitor network path changes for auto-connect (WiFi join, network recovery, device wake)
        setupNetworkMonitoring()
        setupLatencyPollingLifecycle()
    }

    // MARK: - Bindings

    private func setupBindings() {
        // Bind VPN service connection state
        vpnService.$connectionState
            .combineLatest(vpnService.$isReconnecting)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, isReconnecting in
                guard let self = self else { return }

                if isReconnecting && state == .disconnected {
                    self.connectionState = .reconnecting
                } else {
                    self.connectionState = state
                }

                if state == .connected {
                    let savedStart = UserDefaults.standard.object(forKey: Self.connectedAtKey) as? Date
                    self.startTimer(restoreFrom: savedStart)
                    if !self.hasRecordedReviewPromptForCurrentConnection {
                        self.hasRecordedReviewPromptForCurrentConnection = true
                        if ReviewPromptService.shared.recordSuccessfulConnection() {
                            self.showReviewPrompt = true
                        }
                    }
                    Task { await self.fetchPublicIPOnConnect() }
                } else if state == .disconnected && !isReconnecting {
                    self.hasRecordedReviewPromptForCurrentConnection = false
                    self.stopTimer()
                    self.connectionDuration = 0
                    self.resetStats()
                    Task { await self.fetchPublicIPOnDisconnect() }
                }
            }
            .store(in: &cancellables)

        // Bind VPN statistics
        vpnService.$statistics
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.updateStats(from: stats)
            }
            .store(in: &cancellables)

        // Bind auth service user
        authService.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                if let profile = profile {
                    self?.user = User(
                        username: profile.username ?? profile.displayName ?? profile.accountNumber ?? "User",
                        accountNumber: profile.accountNumber ?? "",
                        subscriptionPlan: profile.planTier.rawValue.capitalized,
                        subscriptionEndDate: profile.subscriptionExpiresAt
                    )
                } else {
                    self?.user = nil
                }
            }
            .store(in: &cancellables)

        // Bind connection health
        vpnService.$isConnectionHealthy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] healthy in
                self?.isConnectionHealthy = healthy
            }
            .store(in: &cancellables)

        // Bind VPN errors
        vpnService.$error
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                LogService.shared.logApp("[VPNManager] VPN error: \(error.localizedDescription)", level: .error)
                self?.errorMessage = error.localizedDescription
            }
            .store(in: &cancellables)
    }

    private func setupSettingsObserver() {
        $settings
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { settings in
                SettingsStorage.saveSettings(settings)
            }
            .store(in: &cancellables)
    }

    // MARK: - Server Management

    func loadServers() async {
        // Return cache if still fresh
        if let cacheTime = serverCacheTimestamp,
           Date().timeIntervalSince(cacheTime) < serverCacheTTL,
           !availableServers.isEmpty {
            LogService.shared.logApp("[VPNManager] Servers loaded from cache (\(availableServers.count) servers)")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let apiServers: [APIServer] = try await APIClient.shared.request(
                endpoint: .servers
            )

            // Convert API servers to local Server model
            var servers = apiServers.map { apiServer in
                Server.from(apiServer: apiServer, isFavorite: ServerStorage.isFavorite(apiServer.id))
            }

            // Apply cached latencies immediately so the UI is never blank
            let cached = await LatencyService.shared.loadCache()
            applyLatencies(cached, to: &servers)

            lastAPIServers = apiServers
            availableServers = servers
            serverCacheTimestamp = Date()
            updateServerFavoriteStates()
            updateRecommendedServers()

            if selectedServer == nil {
                if let lastServerId = UserDefaults.standard.string(forKey: Self.lastConnectedServerKey),
                   let lastServer = availableServers.first(where: { $0.id == lastServerId }) {
                    selectedServer = lastServer
                } else {
                    selectedServer = availableServers.first
                }
            }

            LogService.shared.logApp("[VPNManager] Servers loaded from API (\(availableServers.count) servers)")

        } catch let apiError as APIError {
            if case .unauthorized = apiError {
                authService.handleUnauthorized()
                return
            }
            // Fallback to stale cache
            if !availableServers.isEmpty {
                LogService.shared.logApp("[VPNManager] Failed to load servers from API, using stale cache: \(apiError.localizedDescription)", level: .warning)
                return
            }
            LogService.shared.logApp("[VPNManager] Failed to load servers from API: \(apiError.localizedDescription)", level: .error)
            errorMessage = apiError.localizedDescription
        } catch {
            // Fallback to stale cache if available
            if !availableServers.isEmpty {
                LogService.shared.logApp("[VPNManager] Failed to load servers, using stale cache: \(error.localizedDescription)", level: .warning)
                return
            }
            LogService.shared.logApp("[VPNManager] Failed to load servers from API: \(error.localizedDescription)", level: .error)
            errorMessage = "Failed to load servers. Please check your connection."
        }
    }

    /// Measures fresh latencies for all servers and updates the UI.
    func measureLatencies() async {
        let fresh = await LatencyService.shared.measureAll(availableServers)
        guard !fresh.isEmpty else { return }
        await LatencyService.shared.saveCache(fresh)
        applyLatencies(fresh, to: &availableServers)
        updateRecommendedServers()
    }

    // MARK: - Latency Polling

    private func startLatencyPolling() {
        latencyPollingTask?.cancel()
        latencyPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let jitter = TimeInterval.random(in: 0...Self.latencyPollingJitter)
                let delay = Self.latencyPollingInterval + jitter
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.measureLatencies()
            }
        }
    }

    private func stopLatencyPolling() {
        latencyPollingTask?.cancel()
        latencyPollingTask = nil
    }

    private func setupLatencyPollingLifecycle() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopLatencyPolling()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startLatencyPolling()
        }
    }

    private func applyLatencies(_ latencies: [String: Int], to servers: inout [Server]) {
        for i in servers.indices {
            if let ms = latencies[servers[i].id] {
                servers[i].latencyMs = ms
            }
        }
    }

    private func updateRecommendedServers() {
        let measured = availableServers.filter { $0.latencyMs > 0 && $0.load < 0.8 }
        if measured.isEmpty {
            // First launch before any measurement — fall back to backend isRecommended flag
            let recommendedIds = Set(lastAPIServers.filter { $0.isRecommended }.map { $0.id })
            recommendedServers = availableServers.filter { recommendedIds.contains($0.id) }
        } else {
            // score = latency + (load% × 2)  where load% = load * 100
            recommendedServers = Array(
                measured
                    .sorted { ($0.latencyMs + Int($0.load * 100) * 2) < ($1.latencyMs + Int($1.load * 100) * 2) }
                    .prefix(3)
            )
        }
    }

    // MARK: - Connection Methods

    func connect(to server: Server) {
        guard connectionState == .disconnected else { return }

        LogService.shared.logApp("[VPNManager] Connect requested: \(server.city ?? server.countryName) (\(server.id))")

        // Subscription check
        if let userProfile = authService.currentUser {
            let isSubscriptionActive = userProfile.subscriptionExpiresAt.map { $0 > Date() } ?? false
            if !isSubscriptionActive {
                LogService.shared.logApp("[VPNManager] Connect failed: subscription not active", level: .error)
                pendingServer = server
                needsSubscription = true
                return
            }
        } else {
            // User not loaded, cannot proceed
            LogService.shared.logApp("[VPNManager] Connect failed: user profile not loaded", level: .error)
            errorMessage = "Unable to verify subscription. Please try logging out and back in."
            return
        }

        pendingServer = nil
        selectedServer = server
        errorMessage = nil
        UserDefaults.standard.set(false, forKey: Self.userManuallyDisconnectedKey)

        connectTask = Task {
            do {
                // Check app config before connecting
                await AppConfigService.shared.checkAppConfig()

                switch AppConfigService.shared.updateAction {
                case .maintenance:
                    LogService.shared.logApp("[VPNManager] Connect blocked: maintenance mode enabled", level: .warning)
                    errorMessage = "WireDog VPN is currently under maintenance. Please try again later."
                    return
                case .forceUpdate(let message):
                    LogService.shared.logApp("[VPNManager] Connect blocked: force update required", level: .warning)
                    errorMessage = "A required update is available. Please update the app before connecting. \(message)"
                    return
                case .softUpdate, .none:
                    // Allow connection
                    break
                }

                try await vpnService.connect(
                    serverId: server.id,
                    killSwitchEnabled: settings.isKillSwitchEnabled,
                    ipv6Enabled: settings.isIPv6Enabled,
                    lanAccessEnabled: settings.isLANAccessEnabled,
                    blockAdsEnabled: settings.isBlockAdsEnabled,
                    blockMalwareEnabled: settings.isBlockMalwareEnabled
                )
                addRecentServer(server)
                UserDefaults.standard.set(server.id, forKey: Self.lastConnectedServerKey)
            } catch VPNError.cancelled {
                // User-initiated cancel (tap-again-to-cancel) — expected, nothing to surface.
                LogService.shared.logApp("[VPNManager] Connect cancelled")
            } catch let apiError as APIError {
                if case .unauthorized = apiError {
                    authService.handleUnauthorized()
                } else {
                    LogService.shared.logApp("[VPNManager] Connect error: \(apiError.localizedDescription)", level: .error)
                    errorMessage = apiError.localizedDescription
                }
            } catch {
                LogService.shared.logApp("[VPNManager] Connect error: \(error.localizedDescription)", level: .error)
                errorMessage = error.localizedDescription
            }
        }
    }

    func disconnect() {
        guard connectionState == .connected || connectionState == .connecting else { return }

        LogService.shared.logApp("[VPNManager] Disconnect requested")
        UserDefaults.standard.set(true, forKey: Self.userManuallyDisconnectedKey)

        Task {
            await vpnService.disconnect()
        }
    }

    /// Cancels an in-flight connect attempt — covers both a first attempt still awaiting the
    /// backend/tunnel, and an in-progress auto-reconnect loop (which outlives connectTask, since
    /// its retries are scheduled internally by VPNService rather than by this Task).
    func cancelConnect() {
        guard connectionState == .connecting || connectionState == .reconnecting else { return }

        LogService.shared.logApp("[VPNManager] Cancel connect requested")
        UserDefaults.standard.set(true, forKey: Self.userManuallyDisconnectedKey)

        connectTask?.cancel()
        vpnService.cancelConnect()
    }

    func toggleConnection() {
        switch connectionState {
        case .connected:
            disconnect()
        case .disconnected:
            if let server = selectedServer {
                connect(to: server)
            }
        case .connecting, .reconnecting:
            cancelConnect()
        case .disconnecting:
            break // nothing to do — can't cancel a disconnect already in progress
        }
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Skip the first callback fired immediately on monitor start —
                // app-launch auto-connect is already handled by MainTabView.task
                if self.isInitialPathUpdate {
                    self.isInitialPathUpdate = false
                    return
                }

                guard path.status == .satisfied else { return }

                // Debounce rapid transitions (e.g., WiFi handoff, cellular → WiFi switch)
                self.networkAutoConnectTask?.cancel()
                self.networkAutoConnectTask = Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    await self.attemptAutoConnect()
                }
            }
        }

        monitor.start(queue: pathMonitorQueue)
    }

    // MARK: - Foreground Handling

    func handleAppForeground() {
        vpnService.handleAppForeground()
    }

    // MARK: - Auto-Connect

    func attemptAutoConnect() async {
        guard settings.isAutoConnectEnabled else {
            LogService.shared.logApp("[VPNManager] Auto-connect skipped: disabled")
            return
        }

        guard connectionState == .disconnected else {
            LogService.shared.logApp("[VPNManager] Auto-connect skipped: not disconnected")
            return
        }

        guard !UserDefaults.standard.bool(forKey: Self.userManuallyDisconnectedKey) else {
            LogService.shared.logApp("[VPNManager] Auto-connect skipped: manually disconnected")
            return
        }

        guard let lastServerId = UserDefaults.standard.string(forKey: Self.lastConnectedServerKey) else {
            LogService.shared.logApp("[VPNManager] Auto-connect skipped: no last server")
            return
        }

        // Ensure servers are loaded
        if availableServers.isEmpty {
            await loadServers()
        }

        guard let server = availableServers.first(where: { $0.id == lastServerId }) else {
            LogService.shared.logApp("[VPNManager] Auto-connect skipped: last server not in list", level: .warning)
            return
        }

        LogService.shared.logApp("[VPNManager] Auto-connect triggered for server \(server.city ?? server.countryName)")
        connect(to: server)
    }

    // MARK: - Public IP

    func fetchPublicIP() async {
        publicIP = await ipService.getPublicIPSafe()
    }

    private func fetchGeoLocation() async {
        currentLocation = await ipService.getGeoLocation()
    }

    private func fetchPublicIPOnConnect() async {
        isFetchingNetworkInfo = true
        ipService.clearGeoCache()
        await ipService.resetConnections()
        let newIP = await ipService.getPublicIPSafe()
        publicIP = newIP
        isFetchingNetworkInfo = false
        LogService.shared.logApp("[VPNManager] Connected - VPN IP assigned")
    }

    private func fetchPublicIPOnDisconnect() async {
        isFetchingNetworkInfo = true
        ipService.clearGeoCache()
        await ipService.resetConnections()
        let currentIP = await ipService.getPublicIPSafe()
        publicIP = currentIP
        if let ip = currentIP {
            originalIP = ip
        }
        currentLocation = await ipService.getGeoLocation()
        isFetchingNetworkInfo = false
        LogService.shared.logApp("[VPNManager] Disconnected - original IP refreshed")
    }

    // MARK: - Timer Management

    private var connectedAt: Date?

    private func startTimer(restoreFrom savedDate: Date? = nil) {
        stopTimer()
        let start = savedDate ?? Date()
        connectedAt = start
        UserDefaults.standard.set(start, forKey: Self.connectedAtKey)
        connectionDuration = Date().timeIntervalSince(start)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.connectedAt else { return }
                self.connectionDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        connectedAt = nil
        UserDefaults.standard.removeObject(forKey: Self.connectedAtKey)
    }

    // MARK: - Statistics

    private var previousBytesReceived: UInt64 = 0
    private var previousBytesSent: UInt64 = 0
    private var previousStatsTime: Date?

    private func updateStats(from tunnelStats: TunnelStatistics) {
        let now = Date()
        let totalBytes = Double(tunnelStats.bytesReceived + tunnelStats.bytesSent)
        let totalGB = totalBytes / (1024 * 1024 * 1024)

        // Delta-based speed calculation
        var downloadSpeed: Double = 0
        var uploadSpeed: Double = 0

        if let prevTime = previousStatsTime {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                let rxDelta = tunnelStats.bytesReceived > previousBytesReceived
                    ? Double(tunnelStats.bytesReceived - previousBytesReceived)
                    : 0
                let txDelta = tunnelStats.bytesSent > previousBytesSent
                    ? Double(tunnelStats.bytesSent - previousBytesSent)
                    : 0

                // Convert bytes/sec to Mbps (bytes * 8 / 1_000_000)
                downloadSpeed = (rxDelta / elapsed) * 8 / 1_000_000
                uploadSpeed = (txDelta / elapsed) * 8 / 1_000_000
            }
        }

        previousBytesReceived = tunnelStats.bytesReceived
        previousBytesSent = tunnelStats.bytesSent
        previousStatsTime = now

        connectionStats = ConnectionStats(
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            connectionTime: connectionDuration,
            dataTransferred: totalGB
        )
    }

    private func resetStats() {
        previousBytesReceived = 0
        previousBytesSent = 0
        previousStatsTime = nil
        connectionStats = ConnectionStats(downloadSpeed: 0, uploadSpeed: 0, connectionTime: 0, dataTransferred: 0)
    }

    // MARK: - Server Selection

    func selectServer(_ server: Server) {
        let previousServer = selectedServer
        selectedServer = server
        let isSameServer = server.id == previousServer?.id

        switch connectionState {
        case .connected, .connecting, .reconnecting:
            // Already connected/connecting to this exact server — nothing to move.
            guard !isSameServer else { return }
            switchServer(to: server)
        case .disconnecting:
            // Mid-teardown from something else — just update the selection and let it settle.
            return
        case .disconnected:
            // Re-tapping the already-selected server while idle reads as "connect to this."
            // Picking a *different* server just updates the selection, same as before — the
            // user still has to hit Connect for that one.
            guard isSameServer else { return }
            connect(to: server)
        }
    }

    private func switchServer(to server: Server) {
        isSwitchingServer = true

        switch connectionState {
        case .connected:
            disconnect()
        case .connecting, .reconnecting:
            cancelConnect()
        default:
            break
        }

        connectTask?.cancel()
        connectTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isSwitchingServer = false }
            let didDisconnect = await self.waitForDisconnected()
            guard !Task.isCancelled else { return }
            guard didDisconnect else {
                self.errorMessage = "Unable to switch servers. Please try again."
                return
            }
            self.connect(to: server)
        }
    }

    /// Waits for `connectionState` to settle at `.disconnected` (e.g. after a server-switch
    /// disconnect), bounded by a timeout so a stuck tunnel teardown can't hang forever.
    private func waitForDisconnected(timeout: TimeInterval = 8) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { [weak self] in
                guard let self else { return false }
                for await state in await self.$connectionState.values {
                    if state == .disconnected { return true }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    func selectServerFromMap(_ serverId: String) {
        if let server = availableServers.first(where: { $0.id == serverId }) {
            selectServer(server)
        }
    }

    // MARK: - Favorites & Recent

    func toggleFavorite(_ server: Server) {
        ServerStorage.toggleFavorite(server.id)
        updateServerFavoriteStates()
    }

    private func addRecentServer(_ server: Server) {
        ServerStorage.addRecentServer(server.id)
        recentServers = ServerStorage.getRecentServers(from: availableServers)
    }

    private func updateServerFavoriteStates() {
        var updatedServers = availableServers
        for i in 0..<updatedServers.count {
            updatedServers[i].isFavorite = ServerStorage.isFavorite(updatedServers[i].id)
        }
        availableServers = updatedServers
        favoriteServers = ServerStorage.getFavoriteServers(from: availableServers)
        recentServers = ServerStorage.getRecentServers(from: availableServers)
    }

    // MARK: - Cleanup

    deinit {
        timer?.invalidate()
        pathMonitor?.cancel()
        networkAutoConnectTask?.cancel()
    }
}
