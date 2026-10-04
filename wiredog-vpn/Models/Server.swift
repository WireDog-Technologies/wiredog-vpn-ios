import Foundation

struct Server: Identifiable, Hashable, Codable {
    // Unique per list entry. For a normal server this is the API server id ("CA-SFO-001"); for an
    // organization gateway entry it is "<server id>_gw<gatewayId>", because the shared node and
    // each named gateway on it appear as separate rows. Use `connectServerId` for API calls.
    let id: String
    let countryName: String  // State name for US servers
    let countryCode: String  // State code
    let city: String?
    let load: Double  // 0.0 to 1.0
    let host: String  // Hostname used for latency ping (e.g. nyc-1.wiredogvpn.com)
    var latencyMs: Int  // Client-measured TCP RTT in ms; 0 = not yet measured
    let ipAddress: String
    let latitude: Double
    let longitude: Double
    var isFavorite: Bool
    // Organization gateway entry (named Dedicated IP), nil for a normal server.
    var gatewayId: Int? = nil
    var gatewayName: String? = nil
    // The node's real server id when `id` is the composite gateway id above.
    var apiServerId: String? = nil

    /// What /vpn/connect takes as `serverId`.
    var connectServerId: String { apiServerId ?? id }

    var isDedicated: Bool { gatewayId != nil }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isFavorite)
    }

    static func == (lhs: Server, rhs: Server) -> Bool {
        lhs.id == rhs.id && lhs.isFavorite == rhs.isFavorite
    }

    func countryFlag() -> String {
        "🇺🇸"
    }

    /// Creates a Server from an API response
    static func from(apiServer: APIServer, isFavorite: Bool = false) -> Server {
        Server(
            id: apiServer.gatewayId.map { "\(apiServer.id)_gw\($0)" } ?? apiServer.id,
            countryName: apiServer.state,
            countryCode: apiServer.stateCode,
            city: apiServer.city,
            load: Double(apiServer.load) / 100.0,
            host: apiServer.host,
            latencyMs: 0,
            ipAddress: "",  // Not provided by API
            latitude: apiServer.latitude,
            longitude: apiServer.longitude,
            isFavorite: isFavorite,
            gatewayId: apiServer.gatewayId,
            gatewayName: apiServer.gatewayName,
            apiServerId: apiServer.gatewayId == nil ? nil : apiServer.id
        )
    }
}
