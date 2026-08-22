import Foundation

enum BroadcastSeverity: String, Codable {
    case info
    case maintenance
    case incident
}

enum BroadcastTarget: Codable, Equatable {
    case all
    case region(String)
    case server(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "region":
            self = .region(try container.decode(String.self, forKey: .value))
        case "server":
            self = .server(try container.decode(String.self, forKey: .value))
        default:
            self = .all
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all:
            try container.encode("all", forKey: .type)
        case .region(let value):
            try container.encode("region", forKey: .type)
            try container.encode(value, forKey: .value)
        case .server(let value):
            try container.encode("server", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

struct BroadcastMessage: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let severity: BroadcastSeverity
    let target: BroadcastTarget
    let startAt: Date
    let endAt: Date?
}
