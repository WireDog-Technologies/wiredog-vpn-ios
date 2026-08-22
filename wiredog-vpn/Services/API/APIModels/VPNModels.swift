import Foundation

// MARK: - Server from API

struct APIServer: Decodable, Identifiable {
    let id: String
    let state: String
    let stateCode: String
    let city: String
    let latitude: Double
    let longitude: Double
    let isRecommended: Bool
    let latency: Int?
    let load: Int
    let host: String

    enum CodingKeys: String, CodingKey {
        case id
        case state
        case stateCode
        case city
        case latitude
        case longitude
        case isRecommended
        case latency
        case load
        case host
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        state = try container.decode(String.self, forKey: .state)
        stateCode = try container.decode(String.self, forKey: .stateCode)
        city = try container.decode(String.self, forKey: .city)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? 0.0
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? 0.0
        isRecommended = try container.decodeIfPresent(Bool.self, forKey: .isRecommended) ?? false
        latency = try container.decodeIfPresent(Int.self, forKey: .latency)
        load = try container.decodeIfPresent(Int.self, forKey: .load) ?? 0
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
    }
}

// MARK: - Connect Request

struct ConnectRequest: Encodable {
    let serverId: String
    let localMode: Bool
    let blockAds: Bool
    let blockMalware: Bool

    init(serverId: String, localMode: Bool = false, blockAds: Bool = true, blockMalware: Bool = true) {
        self.serverId = serverId
        self.localMode = localMode
        self.blockAds = blockAds
        self.blockMalware = blockMalware
    }
}

// MARK: - Connect Response

struct ConnectResponse: Decodable {
    let config: WireGuardConfigResponse
    let sessionId: String
    let server: ServerInfo?
}

struct AwgParams: Decodable {
    let jc: Int
    let jmin: Int
    let jmax: Int
    let s1: Int
    let s2: Int
    let h1: Int
    let h2: Int
    let h3: Int
    let h4: Int

    enum CodingKeys: String, CodingKey {
        case jc = "Jc", jmin = "Jmin", jmax = "Jmax"
        case s1 = "S1", s2 = "S2"
        case h1 = "H1", h2 = "H2", h3 = "H3", h4 = "H4"
    }
}

struct WireGuardConfigResponse: Decodable {
    let privateKey: String
    let address: String
    let dns: String
    let peer: PeerConfig
    let awg: AwgParams
}

struct PeerConfig: Decodable {
    let publicKey: String
    let endpoint: String
    let allowedIPs: String
    let persistentKeepalive: Int
}

struct ServerInfo: Decodable {
    let id: String
    let city: String?
    let stateCode: String?
    let ipAddress: String?
}

// MARK: - Disconnect Request

struct DisconnectRequest: Encodable {
    let sessionId: String
}

// MARK: - Tunnel Statistics

struct TunnelStatistics: Codable, Equatable {
    let bytesReceived: UInt64
    let bytesSent: UInt64
    let lastHandshake: Date?

    init(bytesReceived: UInt64 = 0, bytesSent: UInt64 = 0, lastHandshake: Date? = nil) {
        self.bytesReceived = bytesReceived
        self.bytesSent = bytesSent
        self.lastHandshake = lastHandshake
    }
}

// MARK: - Tunnel Message (App <-> Extension communication)

struct TunnelMessage: Codable {
    let type: MessageType
    let data: Data?

    enum MessageType: String, Codable {
        case getStatistics
        case updateConfiguration
    }

    init(type: MessageType, data: Data? = nil) {
        self.type = type
        self.data = data
    }
}
