import Foundation

struct VPNSettings: Equatable, Codable {
    let protocolType: String = "AmneziaWG"
    var isKillSwitchEnabled: Bool = false
    var isAutoConnectEnabled: Bool = false
    var isIPv6Enabled: Bool = true
    var isLANAccessEnabled: Bool = true

    enum CodingKeys: String, CodingKey {
        case isKillSwitchEnabled, isAutoConnectEnabled, isIPv6Enabled, isLANAccessEnabled
    }
}
