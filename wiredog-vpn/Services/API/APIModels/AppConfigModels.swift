import Foundation

// MARK: - App Config Response

struct AppConfigResponse: Codable {
    let timestamp: String?
    let maintenanceMode: Bool
    let platforms: PlatformConfigs
    // Absent/null when the backend has no legal versions configured (or predates the field).
    let legal: LegalVersions?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case maintenanceMode
        case platforms
        case legal
    }
}

// Currently published Privacy Policy / Terms of Service versions. Opaque strings — only
// compared for equality against what the user last accepted.
struct LegalVersions: Codable, Equatable {
    let privacyVersion: String
    let termsVersion: String
    let summary: String?
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
