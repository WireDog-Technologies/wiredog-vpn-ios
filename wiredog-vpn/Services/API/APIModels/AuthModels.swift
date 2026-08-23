import Foundation

// MARK: - Login Requests

struct StandardLoginRequest: Encodable {
    let identifier: String
    let password: String
}

struct AnonymousLoginRequest: Encodable {
    let identifier: String
}

// MARK: - Login Response

struct LoginResponse: Decodable {
    let token: String
    let displayName: String?
    let accountType: AccountType
}

// MARK: - User Profile

struct UserProfile: Decodable, Equatable {
    let id: Int
    let username: String?
    let accountNumber: String?
    let accountType: AccountType
    let displayName: String?
    let isActive: Bool
    let planTier: PlanTier
    let billingPeriod: String?
    let subscriptionExpiresAt: Date?
    let subscriptionStartedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case accountNumber
        case accountType
        case displayName
        case isActive
        case planTier
        case billingPeriod
        case subscriptionExpiresAt
        case subscriptionStartedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        accountNumber = try container.decodeIfPresent(String.self, forKey: .accountNumber)
        accountType = try container.decode(AccountType.self, forKey: .accountType)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        planTier = try container.decodeIfPresent(PlanTier.self, forKey: .planTier) ?? .free
        billingPeriod = try container.decodeIfPresent(String.self, forKey: .billingPeriod)
        subscriptionExpiresAt = try container.decodeIfPresent(Date.self, forKey: .subscriptionExpiresAt)
        subscriptionStartedAt = try container.decodeIfPresent(Date.self, forKey: .subscriptionStartedAt)
    }
}

enum AccountType: String, Decodable {
    case standard
    case anonymous
}

enum PlanTier: String, Decodable {
    case free
    case paid
    case premium
    case elite
    case patriot
}

// MARK: - Checkout Handoff

struct HandoffTokenResponse: Decodable {
    let token: String
    let expiresIn: Int
}

// MARK: - TV Pairing (tvOS only)

struct TvPairingStartResponse: Decodable {
    let code: String
    let expiresIn: Int
}

struct TvPairingStatusResponse: Decodable {
    let status: String
    let token: String?
}

// MARK: - IAP Validation

struct ValidateIAPRequest: Encodable {
    let transactionId: String
    let productId: String
    let jwsRepresentation: String
}

struct ValidateIAPResponse: Decodable {
    let success: Bool
    let message: String?
}

// MARK: - Empty Response

struct EmptyResponse: Decodable {}

// MARK: - Error Response

struct ErrorResponse: Decodable {
    let error: String
}
