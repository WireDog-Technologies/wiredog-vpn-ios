import Foundation

enum HTTPMethod: String {
    case GET
    case POST
    case PUT
    case PATCH
    case DELETE
}

enum APIEndpoint {
    case login
    case logout
    case me
    case servers
    case connect
    case disconnect
    case appConfig
    case announcements
    case deleteAccount
    case forgotPassword
    case verifyResetCode
    case resetPassword
    case registerStandard
    case registerAnonymous
    case handoffToken
    case milestones
    case verifyTwoFactor
    case loginLookup(identifier: String)
    case ssoExchange
    case changePassword
    case validateIAP
    case reportIssue
    case startTvPairing
    case tvPairingStatus(code: String)

    var path: String {
        switch self {
        case .login:
            return "/auth/login"
        case .logout:
            return "/auth/logout"
        case .me:
            return "/auth/me"
        case .servers:
            return "/vpn/servers"
        case .connect:
            return "/vpn/connect"
        case .disconnect:
            return "/vpn/disconnect"
        case .appConfig:
            return "/app/config"
        case .announcements:
            return "/app/announcements"
        case .deleteAccount:
            return "/auth/account"
        case .forgotPassword:
            return "/auth/forgot-password"
        case .verifyResetCode:
            return "/auth/verify-reset-code"
        case .resetPassword:
            return "/auth/reset-password"
        case .registerStandard:
            return "/auth/register/standard"
        case .registerAnonymous:
            return "/auth/register/anonymous"
        case .handoffToken:
            return "/auth/handoff-token"
        case .milestones:
            return "/auth/milestones"
        case .verifyTwoFactor:
            return "/auth/2fa/verify"
        case .loginLookup:
            return "/auth/login/lookup"
        case .ssoExchange:
            return "/auth/sso/exchange"
        case .changePassword:
            return "/auth/password"
        case .validateIAP:
            return "/auth/validate-iap"
        case .reportIssue:
            return "/feedback/report-issue"
        case .startTvPairing:
            return "/auth/tv/start-pairing"
        case .tvPairingStatus(let code):
            return "/auth/tv/pairing-status/\(code)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .login, .verifyTwoFactor, .ssoExchange, .logout, .connect, .disconnect, .forgotPassword, .verifyResetCode, .resetPassword, .registerStandard, .registerAnonymous, .handoffToken, .milestones, .validateIAP, .reportIssue, .startTvPairing:
            return .POST
        case .me, .servers, .appConfig, .announcements, .tvPairingStatus, .loginLookup:
            return .GET
        case .deleteAccount:
            return .DELETE
        case .changePassword:
            return .PATCH
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .loginLookup(let identifier):
            return [URLQueryItem(name: "identifier", value: identifier)]
        case .servers:
            // Opt in to organization "gateway" entries (named Dedicated IPs). Older clients omit
            // this and the backend keeps returning the plain list for them.
            return [URLQueryItem(name: "gateways", value: "1")]
        default:
            return []
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .login, .verifyTwoFactor, .loginLookup, .ssoExchange, .appConfig, .announcements, .forgotPassword, .verifyResetCode, .resetPassword, .registerStandard, .registerAnonymous, .reportIssue, .startTvPairing, .tvPairingStatus:
            return false
        case .logout, .me, .servers, .connect, .disconnect, .deleteAccount, .handoffToken, .milestones, .changePassword, .validateIAP:
            return true
        }
    }
}
