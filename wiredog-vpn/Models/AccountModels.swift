import Foundation

// MARK: - Standard Account

struct StandardAccountRequest: Codable {
    let email: String
    let password: String
}

struct StandardAccountResponse: Codable {
    let message: String
    let accountNumber: String
}

// MARK: - Anonymous Account

struct AnonymousAccountResponse: Codable {
    let accountNumber: String
    let displayName: String
}
