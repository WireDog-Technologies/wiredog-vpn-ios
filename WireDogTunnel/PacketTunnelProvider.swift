import NetworkExtension
// WireGuardKit sources are embedded directly in this target - no import needed

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var adapter: WireGuardAdapter?
    private var tunnelConfiguration: TunnelConfiguration?

    // MARK: - Tunnel Lifecycle

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // Extract WireGuard configuration from options
        guard let configString = options?["wgConfig"] as? String else {
            NSLog("[WireDog] Missing WireGuard configuration")
            completionHandler(PacketTunnelError.missingConfiguration)
            return
        }

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

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "WireGuard configuration not provided"
        case .invalidConfiguration:
            return "Invalid WireGuard configuration"
        case .adapterCreationFailed:
            return "Failed to create WireGuard adapter"
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
