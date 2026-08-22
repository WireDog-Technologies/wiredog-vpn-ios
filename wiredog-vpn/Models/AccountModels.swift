import Foundation

// MARK: - Standard Account

struct StandardAccountRequest: Encodable {
    let email: String
    let password: String
    let platform: String = "iOS"
}

struct StandardAccountResponse: Codable {
    let message: String
    let accountNumber: String
}

// MARK: - Anonymous Account

struct AnonymousAccountRequest: Encodable {
    let platform: String = "iOS"
}

struct AnonymousAccountResponse: Codable {
    let accountNumber: String
    let displayName: String
}
