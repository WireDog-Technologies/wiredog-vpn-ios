import Foundation

struct Server: Identifiable, Hashable, Codable {
    let id: String  // API format: "CA-SFO-001" (StateCode-CityCode-Number)
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
            id: apiServer.id,
            countryName: apiServer.state,
            countryCode: apiServer.stateCode,
            city: apiServer.city,
            load: Double(apiServer.load) / 100.0,
            host: apiServer.host,
            latencyMs: 0,
            ipAddress: "",  // Not provided by API
            latitude: apiServer.latitude,
            longitude: apiServer.longitude,
            isFavorite: isFavorite
        )
    }
}
