import Foundation

struct VPNSettings: Equatable, Codable {
    let protocolType: String = "AmneziaWG"
    var isKillSwitchEnabled: Bool = false
    var isAutoConnectEnabled: Bool = false
    var isIPv6Enabled: Bool = true
    var isLANAccessEnabled: Bool = true
    var isBlockAdsEnabled: Bool = true
    var isBlockMalwareEnabled: Bool = true

    enum CodingKeys: String, CodingKey {
        case isKillSwitchEnabled, isAutoConnectEnabled, isIPv6Enabled, isLANAccessEnabled, isBlockAdsEnabled, isBlockMalwareEnabled
    }

    init() {}

    // Custom decode: falls back to each property's default for any key missing from
    // stored JSON, so adding a new setting never invalidates existing users' saved
    // preferences (synthesized Decodable would require every key to be present).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isKillSwitchEnabled = try container.decodeIfPresent(Bool.self, forKey: .isKillSwitchEnabled) ?? false
        isAutoConnectEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAutoConnectEnabled) ?? false
        isIPv6Enabled = try container.decodeIfPresent(Bool.self, forKey: .isIPv6Enabled) ?? true
        isLANAccessEnabled = try container.decodeIfPresent(Bool.self, forKey: .isLANAccessEnabled) ?? true
        isBlockAdsEnabled = try container.decodeIfPresent(Bool.self, forKey: .isBlockAdsEnabled) ?? true
        isBlockMalwareEnabled = try container.decodeIfPresent(Bool.self, forKey: .isBlockMalwareEnabled) ?? true
    }
}
