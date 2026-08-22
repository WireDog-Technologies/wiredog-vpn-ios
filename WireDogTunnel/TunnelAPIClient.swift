import Foundation

/// Minimal networking the extension needs to originate its own VPN session when started standalone
/// (no `options` from the app — e.g. iOS Settings > VPN toggle). Deliberately not a reuse of the
/// app's APIClient.swift: this only needs two calls, and keeping it separate avoids pulling the
/// app's full networking/decoding surface into the extension's tighter memory budget.
enum TunnelAPIError: Error {
    case unauthorized
    case requestFailed(Int)
    case networkError(Error)
    case decodingFailed
}

struct TunnelConnectResult {
    let wgConfig: String
    let sessionId: String
}

enum TunnelAPIClient {
    // Tighter than the app's own request timeouts — startTunnel/stopTunnel both run under a
    // constrained time budget from iOS before the extension process can be reclaimed.
    private static let connectTimeout: TimeInterval = 15
    private static let disconnectTimeout: TimeInterval = 8

    static func connect(token: String, serverId: String) async throws -> TunnelConnectResult {
        var request = URLRequest(url: TunnelConfig.apiBaseURL.appendingPathComponent("/vpn/connect"))
        request.httpMethod = "POST"
        request.timeoutInterval = connectTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // Mirrors ConnectRequest's default field values (blockAds/blockMalware on, not local mode) —
        // the extension has no access to the user's saved preference toggles, only whatever the last
        // app-driven connect persisted into the tunnel config itself.
        let body: [String: Any] = [
            "serverId": serverId,
            "localMode": false,
            "blockAds": true,
            "blockMalware": true
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TunnelAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TunnelAPIError.requestFailed(-1)
        }

        if httpResponse.statusCode == 401 {
            throw TunnelAPIError.unauthorized
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TunnelAPIError.requestFailed(httpResponse.statusCode)
        }

        if let refreshedToken = httpResponse.value(forHTTPHeaderField: "X-Refreshed-Token") {
            // Not persisted here — TunnelKeychain has no write path, kept read-only deliberately so
            // the extension can't diverge from whatever the app itself last wrote/trusts. The app
            // will pick up its own renewal on its next authenticated call.
            _ = refreshedToken
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = json["sessionId"] as? String,
              let config = json["config"] as? [String: Any],
              let wgConfig = buildWgQuickConfig(from: config) else {
            throw TunnelAPIError.decodingFailed
        }

        return TunnelConnectResult(wgConfig: wgConfig, sessionId: sessionId)
    }

    static func disconnect(token: String, sessionId: String) async throws {
        var request = URLRequest(url: TunnelConfig.apiBaseURL.appendingPathComponent("/vpn/disconnect"))
        request.httpMethod = "POST"
        request.timeoutInterval = disconnectTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["sessionId": sessionId])

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TunnelAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw TunnelAPIError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    /// Extension-local equivalent of TunnelConfigService.buildWgQuickConfig(from:ipv6Enabled:) — kept
    /// separate for the same reason as the rest of this file. Always builds with IPv6 left enabled,
    /// matching that function's default, since the extension can't see the user's saved toggle.
    private static func buildWgQuickConfig(from config: [String: Any]) -> String? {
        guard let privateKey = config["privateKey"] as? String,
              let address = config["address"] as? String,
              let dns = config["dns"] as? String,
              let peer = config["peer"] as? [String: Any],
              let publicKey = peer["publicKey"] as? String,
              let endpoint = peer["endpoint"] as? String,
              let allowedIPs = peer["allowedIPs"] as? String,
              let persistentKeepalive = peer["persistentKeepalive"] as? Int,
              let awg = config["awg"] as? [String: Any],
              let jc = awg["Jc"] as? Int, let jmin = awg["Jmin"] as? Int, let jmax = awg["Jmax"] as? Int,
              let s1 = awg["S1"] as? Int, let s2 = awg["S2"] as? Int,
              let h1 = awg["H1"] as? Int, let h2 = awg["H2"] as? Int,
              let h3 = awg["H3"] as? Int, let h4 = awg["H4"] as? Int else {
            return nil
        }

        return """
        [Interface]
        PrivateKey = \(privateKey)
        Address = \(address)
        DNS = \(dns)
        Jc = \(jc)
        Jmin = \(jmin)
        Jmax = \(jmax)
        S1 = \(s1)
        S2 = \(s2)
        H1 = \(h1)
        H2 = \(h2)
        H3 = \(h3)
        H4 = \(h4)

        [Peer]
        PublicKey = \(publicKey)
        Endpoint = \(endpoint)
        AllowedIPs = \(allowedIPs)
        PersistentKeepalive = \(persistentKeepalive)
        """
    }
}
