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

/// `/auth/login` answers with a token, or, for an account with 2FA on, a challenge to redeem at
/// `/auth/2fa/verify`. The challenge response has no `token`, so decoding it as a plain
/// `LoginResponse` fails.
enum LoginResult: Decodable {
    case signedIn(LoginResponse)
    case twoFactorRequired(challengeToken: String)

    private enum CodingKeys: String, CodingKey {
        case requiresTwoFactor
        case challengeToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decodeIfPresent(Bool.self, forKey: .requiresTwoFactor) == true {
            self = .twoFactorRequired(challengeToken: try container.decode(String.self, forKey: .challengeToken))
        } else {
            self = .signedIn(try LoginResponse(from: decoder))
        }
    }
}

struct TwoFactorVerifyRequest: Encodable {
    let challengeToken: String
    // A 6-digit authenticator code or a recovery code; the backend accepts either here.
    let code: String
}

// MARK: - SSO

struct SSOLookupResponse: Decodable {
    let sso: Bool
    let domain: String?
}

struct SSOExchangeRequest: Encodable {
    let code: String
    let codeVerifier: String
}

struct ChangePasswordRequest: Encodable {
    let currentPassword: String
    let newPassword: String
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
    // Business/organization state, all from /auth/me. Optional-with-default so an older backend
    // that omits them still decodes.
    let totpEnabled: Bool
    let twoFactorRequiredByOrg: Bool
    let mustChangePassword: Bool
    let subscriptionManagedByOrganization: Bool
    let organizationName: String?
    let organizationRole: String?
    // Where the account stands with an organization (see OrganizationAccess). nil for a plain
    // consumer, or when talking to a backend that predates the field.
    let organizationAccess: OrganizationAccess?
    // Free-trial and account-state fields from /auth/me, optional-with-default for the same reason.
    let trialEndsAt: Date?
    let beganAsTrial: Bool
    // Why this account cannot start the free trial. nil means either "can start one" or "backend
    // didn't say"; trialEligible tells those apart.
    let trialIneligibleReason: TrialIneligibleReason?
    // True only when the backend sent trialIneligibleReason as an explicit null: the account can
    // start a trial. A missing field (older backend) stays false so the app never offers a trial
    // the server did not confirm.
    let trialEligible: Bool
    // Has had paid access or a trial at some point, even if it has since expired.
    let everHadAccess: Bool
    // A card (Stripe) subscription that renews on its own. Apple subscriptions are not covered; ask StoreKit.
    let autoRenews: Bool
    // Set when staff revoked the account (fraud, chargeback, abuse).
    let revokedReason: String?

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
        case totpEnabled
        case twoFactorRequiredByOrg
        case mustChangePassword
        case subscriptionManagedByOrganization
        case organizationName
        case organizationRole
        case organizationAccess
        case trialEndsAt
        case beganAsTrial
        case trialIneligibleReason
        case everHadAccess
        case autoRenews
        case revokedReason
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
        totpEnabled = try container.decodeIfPresent(Bool.self, forKey: .totpEnabled) ?? false
        twoFactorRequiredByOrg = try container.decodeIfPresent(Bool.self, forKey: .twoFactorRequiredByOrg) ?? false
        mustChangePassword = try container.decodeIfPresent(Bool.self, forKey: .mustChangePassword) ?? false
        subscriptionManagedByOrganization = try container.decodeIfPresent(Bool.self, forKey: .subscriptionManagedByOrganization) ?? false
        organizationName = try container.decodeIfPresent(String.self, forKey: .organizationName)
        organizationRole = try container.decodeIfPresent(String.self, forKey: .organizationRole)
        organizationAccess = try container.decodeIfPresent(OrganizationAccess.self, forKey: .organizationAccess)
        trialEndsAt = try container.decodeIfPresent(Date.self, forKey: .trialEndsAt)
        beganAsTrial = try container.decodeIfPresent(Bool.self, forKey: .beganAsTrial) ?? false
        trialIneligibleReason = try container.decodeIfPresent(TrialIneligibleReason.self, forKey: .trialIneligibleReason)
        if container.contains(.trialIneligibleReason) {
            trialEligible = try container.decodeNil(forKey: .trialIneligibleReason)
        } else {
            trialEligible = false
        }
        everHadAccess = try container.decodeIfPresent(Bool.self, forKey: .everHadAccess) ?? false
        autoRenews = try container.decodeIfPresent(Bool.self, forKey: .autoRenews) ?? false
        revokedReason = try container.decodeIfPresent(String.self, forKey: .revokedReason)
    }

    var isRevoked: Bool { revokedReason != nil }

    /// Still in the sign-up funnel: no plan, never had access, not tied to an organization, not
    /// revoked. The people the paywall exit sheet and the reminder sequence are for.
    var isUnpaidNeverPaid: Bool {
        !hasEntitlement && !everHadAccess && !isOrganizationMember && lostOrganizationAccess == nil && !isRevoked
    }

    /// A running, unconverted free trial.
    var isInFreeTrial: Bool {
        guard let end = trialEndsAt else { return false }
        return end > Date()
    }

    /// Whether the backend will let this account connect. An org seat's expiry can be absent
    /// (the org's Stripe period isn't always mirrored), so for those trust `isActive`, which
    /// /auth/me derives from the org's live subscription. Personal accounts keep the expiry check.
    var hasEntitlement: Bool {
        if subscriptionManagedByOrganization { return isActive }
        return subscriptionExpiresAt.map { $0 > Date() } ?? false
    }

    // An 'inactive' org (lapsed subscription) still owns the seat, so the account stays org-managed.
    // 'revoked' does not: that person is a plain consumer again.
    var isOrganizationMember: Bool {
        organizationName != nil || subscriptionManagedByOrganization || organizationAccess == .inactive
    }

    /// Set only when an organization used to cover this account and no longer does. The app
    /// shows this instead of the personal paywall.
    var lostOrganizationAccess: OrganizationAccess? {
        guard let access = organizationAccess, access != .active else { return nil }
        return access
    }
}

// Both enums fall back instead of throwing on an unrecognized value: a strict decode here would
// fail the whole /auth/me response (and so the profile) the first time the backend adds a case.
/// `/auth/me`'s `organizationAccess`. Unknown values decode as `.active` so a future backend
/// state never locks someone out of the app.
enum OrganizationAccess: String, Decodable {
    case active
    // The org's own subscription lapsed or was canceled; the member's seat is intact.
    case inactive
    // An admin removed this person from the org.
    case revoked

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OrganizationAccess(rawValue: raw) ?? .active
    }

    var userMessage: String {
        switch self {
        case .active:
            return ""
        case .inactive:
            return "Your organization's WireDog subscription isn't active right now. Contact your administrator."
        case .revoked:
            return "Your organization has removed your access to WireDog VPN. Contact your administrator if you think this is a mistake."
        }
    }
}

/// `/auth/me`'s `trialIneligibleReason`. Unknown values decode as `.unknown` so a new backend
/// reason never fails the whole profile decode.
enum TrialIneligibleReason: String, Decodable {
    case disabled
    case anonymous
    case unverified
    case used
    case paidBefore = "paid_before"
    case hasTime = "has_time"
    case revoked
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TrialIneligibleReason(rawValue: raw) ?? .unknown
    }
}

enum AccountType: String, Decodable {
    case standard
    case anonymous

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AccountType(rawValue: raw) ?? .standard
    }
}

enum PlanTier: String, Decodable {
    case free
    case paid
    case premium
    case elite
    case patriot

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlanTier(rawValue: raw) ?? .free
    }
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
    // Machine-readable reason on the few errors the app branches on (see APIClient's 403 handling).
    let code: String?
}
