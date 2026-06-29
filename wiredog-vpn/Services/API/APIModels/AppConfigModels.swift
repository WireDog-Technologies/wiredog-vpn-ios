import Foundation

// MARK: - App Config Response

struct AppConfigResponse: Codable {
    let timestamp: String?
    let maintenanceMode: Bool
    let platforms: PlatformConfigs

    enum CodingKeys: String, CodingKey {
        case timestamp
        case maintenanceMode
        case platforms
    }
}

struct PlatformConfigs: Codable {
    let ios: PlatformConfig?

    enum CodingKeys: String, CodingKey {
        case ios
    }
}

struct PlatformConfig: Codable {
    let minSupportedVersion: Int
    let latestVersion: Int
    let forceUpdate: Bool
    let maintenanceMode: Bool
    let updateMessage: String?
    let downloadUrl: String?

    enum CodingKeys: String, CodingKey {
        case minSupportedVersion
        case latestVersion
        case forceUpdate
        case maintenanceMode
        case updateMessage
        case downloadUrl
    }
}

// MARK: - Update Action

enum UpdateAction {
    case maintenance
    case forceUpdate(message: String)
    case softUpdate(message: String)
    case none
}
