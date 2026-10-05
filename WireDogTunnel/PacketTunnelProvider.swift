import NetworkExtension
// WireGuardKit sources are embedded directly in this target - no import needed

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var adapter: WireGuardAdapter?
    private var tunnelConfiguration: TunnelConfiguration?

    // MARK: - Tunnel Lifecycle

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // The app always passes wgConfig when it initiates the connect (VPNService.connect()). A nil
        // options dict only happens when iOS itself starts the tunnel — the Settings > VPN toggle, or
        // an on-demand rule evaluation — with no app process involved to hand over a fresh config.
        if let configString = options?["wgConfig"] as? String {
            startWireGuardTunnel(configString: configString, completionHandler: completionHandler)
            return
        }

        NSLog("[WireDog] No options provided (standalone start) — originating our own session")
        startStandaloneTunnel(completionHandler: completionHandler)
    }

    /// Handles a start with no app-provided options by fetching a fresh WireGuard config directly
    /// from the backend, using the auth token and last-connected server persisted (by the app) to
    /// the shared App Group container. Fails cleanly with no user-facing surface — there is no UI to
    /// report to here — the toggle in Settings will simply revert to off.
    private func startStandaloneTunnel(completionHandler: @escaping (Error?) -> Void) {
        guard TunnelStandaloneConnectBackoff.shouldAttempt() else {
            NSLog("[WireDog] Standalone connect backing off after repeated failures")
            completionHandler(PacketTunnelError.standaloneUnavailable)
            return
        }

        guard let token = TunnelKeychain.getAuthToken() else {
            NSLog("[WireDog] Standalone start failed: no auth token available")
            TunnelStandaloneConnectBackoff.recordFailure()
            completionHandler(PacketTunnelError.standaloneUnavailable)
            return
        }

        guard let serverId = TunnelStorage.lastConnectedServerId else {
            NSLog("[WireDog] Standalone start failed: no last-connected server on record")
            TunnelStandaloneConnectBackoff.recordFailure()
            completionHandler(PacketTunnelError.standaloneUnavailable)
            return
        }

        Task {
            do {
                let result = try await TunnelAPIClient.connect(token: token, serverId: serverId, dedicatedIpId: TunnelStorage.lastConnectedGatewayId)
                TunnelStorage.sessionId = result.sessionId
                TunnelStorage.setExitIP(result.exitIp, forSession: result.sessionId)
                TunnelStandaloneConnectBackoff.recordSuccess()
                NSLog("[WireDog] Standalone /connect succeeded, starting tunnel")
                startWireGuardTunnel(configString: result.wgConfig, completionHandler: completionHandler)
            } catch {
                NSLog("[WireDog] Standalone /connect failed: \(error)")
                TunnelStandaloneConnectBackoff.recordFailure()
                completionHandler(PacketTunnelError.standaloneUnavailable)
            }
        }
    }

    private func startWireGuardTunnel(configString: String, completionHandler: @escaping (Error?) -> Void) {
        NSLog("[WireDog] Starting tunnel with config length: \(configString.count)")

        // Parse WireGuard configuration
        do {
            tunnelConfiguration = try TunnelConfiguration(fromWgQuickConfig: configString, called: "WireDog")
        } catch {
            NSLog("[WireDog] Failed to parse WireGuard config: \(error)")
            completionHandler(PacketTunnelError.invalidConfiguration)
            return
        }

        guard let tunnelConfig = tunnelConfiguration else {
            completionHandler(PacketTunnelError.invalidConfiguration)
            return
        }

        // Create WireGuard adapter
        adapter = WireGuardAdapter(with: self) { logLevel, message in
            #if DEBUG
            NSLog("[WireGuard/\(logLevel)] \(message)")
            #endif
        }

        // Start the WireGuard tunnel
        adapter?.start(tunnelConfiguration: tunnelConfig) { [weak self] adapterError in
            if let error = adapterError {
                NSLog("[WireDog] Failed to start tunnel: \(error)")
                self?.adapter = nil
                completionHandler(error)
                return
            }

            NSLog("[WireDog] Tunnel started successfully")
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        NSLog("[WireDog] Stopping tunnel with reason: \(reason.rawValue)")

        adapter?.stop { [weak self] error in
            if let error = error {
                NSLog("[WireDog] Error stopping tunnel: \(error)")
            } else {
                NSLog("[WireDog] Tunnel stopped successfully")
            }

            self?.adapter = nil
            self?.tunnelConfiguration = nil
            self?.notifyBackendOfDisconnectIfOwed(completionHandler: completionHandler)
        }
    }

    /// If a sessionId is still present in shared storage at teardown time, nobody else has claimed
    /// responsibility for telling the backend yet. The app's own disconnect() clears this key
    /// *before* it calls stopVPNTunnel(), so an app-initiated disconnect always finds it already
    /// nil here and skips this entirely (avoiding a double /disconnect against the backend's
    /// non-idempotent counter decrement). A Settings-toggled-off session, or any teardown the app
    /// never initiated, still has the key set — that's what this path is for.
    ///
    /// Best-effort only: stopTunnel runs under a limited time budget before iOS may reclaim the
    /// extension process, so this isn't a hard guarantee. On failure/timeout the key is deliberately
    /// left in place — the app's existing crash-recovery reconciliation (VPNService.loadVPNManager)
    /// will find it stale on next launch and retry via its own durable pending-disconnect queue.
    private func notifyBackendOfDisconnectIfOwed(completionHandler: @escaping () -> Void) {
        guard let sessionId = TunnelStorage.sessionId, let token = TunnelKeychain.getAuthToken() else {
            completionHandler()
            return
        }

        Task {
            do {
                try await TunnelAPIClient.disconnect(token: token, sessionId: sessionId)
                TunnelStorage.sessionId = nil
                NSLog("[WireDog] Standalone /disconnect succeeded")
            } catch {
                NSLog("[WireDog] Standalone /disconnect failed, leaving for app reconciliation: \(error)")
            }
            completionHandler()
        }
    }

    // MARK: - App Communication

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let message = try? JSONDecoder().decode(TunnelMessage.self, from: messageData) else {
            NSLog("[WireDog] Failed to decode app message")
            completionHandler?(nil)
            return
        }

        switch message.type {
        case .getStatistics:
            handleGetStatistics(completionHandler: completionHandler)
        case .updateConfiguration:
            handleUpdateConfiguration(data: message.data, completionHandler: completionHandler)
        }
    }

    private func handleGetStatistics(completionHandler: ((Data?) -> Void)?) {
        guard let adapter = adapter else {
            completionHandler?(nil)
            return
        }

        adapter.getRuntimeConfiguration { [weak self] configString in
            let stats = self?.parseStatistics(from: configString) ?? TunnelStatistics()
            let response = try? JSONEncoder().encode(stats)
            completionHandler?(response)
        }
    }

    private func handleUpdateConfiguration(data: Data?, completionHandler: ((Data?) -> Void)?) {
        guard let data = data,
              let configString = String(data: data, encoding: .utf8),
              let newConfig = try? TunnelConfiguration(fromWgQuickConfig: configString, called: "WireDog") else {
            let response = try? JSONEncoder().encode(["success": false])
            completionHandler?(response)
            return
        }

        adapter?.update(tunnelConfiguration: newConfig) { error in
            let success = error == nil
            if let error = error {
                NSLog("[WireDog] Failed to update config: \(error)")
            }
            let response = try? JSONEncoder().encode(["success": success])
            completionHandler?(response)
        }
    }

    private func parseStatistics(from configString: String?) -> TunnelStatistics {
        var bytesReceived: UInt64 = 0
        var bytesSent: UInt64 = 0
        var lastHandshake: Date?

        guard let config = configString else {
            return TunnelStatistics(bytesReceived: 0, bytesSent: 0, lastHandshake: nil)
        }

        // Parse WireGuard runtime config output
        // Format: key=value pairs, one per line
        let lines = config.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("rx_bytes=") {
                let value = trimmed.replacingOccurrences(of: "rx_bytes=", with: "")
                bytesReceived = UInt64(value) ?? 0
            } else if trimmed.hasPrefix("tx_bytes=") {
                let value = trimmed.replacingOccurrences(of: "tx_bytes=", with: "")
                bytesSent = UInt64(value) ?? 0
            } else if trimmed.hasPrefix("last_handshake_time_sec=") {
                let value = trimmed.replacingOccurrences(of: "last_handshake_time_sec=", with: "")
                if let seconds = Int64(value), seconds > 0 {
                    lastHandshake = Date(timeIntervalSince1970: TimeInterval(seconds))
                }
            }
        }

        return TunnelStatistics(
            bytesReceived: bytesReceived,
            bytesSent: bytesSent,
            lastHandshake: lastHandshake
        )
    }

    // MARK: - Sleep/Wake

    override func sleep(completionHandler: @escaping () -> Void) {
        // WireGuard handles sleep gracefully
        NSLog("[WireDog] Going to sleep")
        completionHandler()
    }

    override func wake() {
        // WireGuard handles wake gracefully
        NSLog("[WireDog] Waking up")
    }
}

// MARK: - Error Types

enum PacketTunnelError: Error, LocalizedError {
    case missingConfiguration
    case invalidConfiguration
    case adapterCreationFailed
    case standaloneUnavailable

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "WireGuard configuration not provided"
        case .invalidConfiguration:
            return "Invalid WireGuard configuration"
        case .adapterCreationFailed:
            return "Failed to create WireGuard adapter"
        case .standaloneUnavailable:
            return "Unable to start VPN without the app — sign in or connect from WireDog VPN first"
        }
    }
}

// MARK: - Tunnel Message Types (shared with main app)

struct TunnelMessage: Codable {
    let type: MessageType
    let data: Data?

    enum MessageType: String, Codable {
        case getStatistics
        case updateConfiguration
    }
}

struct TunnelStatistics: Codable {
    let bytesReceived: UInt64
    let bytesSent: UInt64
    let lastHandshake: Date?

    init(bytesReceived: UInt64 = 0, bytesSent: UInt64 = 0, lastHandshake: Date? = nil) {
        self.bytesReceived = bytesReceived
        self.bytesSent = bytesSent
        self.lastHandshake = lastHandshake
    }
}
