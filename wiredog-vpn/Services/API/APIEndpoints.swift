import Foundation

enum HTTPMethod: String {
    case GET
    case POST
    case PUT
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
    case deleteAccount
    case forgotPassword
    case verifyResetCode
    case resetPassword
    case registerStandard
    case registerAnonymous
    case validateIAP
    case reportIssue

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
        case .validateIAP:
            return "/auth/validate-iap"
        case .reportIssue:
            return "/feedback/report-issue"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .login, .logout, .connect, .disconnect, .forgotPassword, .verifyResetCode, .resetPassword, .registerStandard, .registerAnonymous, .validateIAP, .reportIssue:
            return .POST
        case .me, .servers, .appConfig:
            return .GET
        case .deleteAccount:
            return .DELETE
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .login, .appConfig, .forgotPassword, .verifyResetCode, .resetPassword, .registerStandard, .registerAnonymous, .reportIssue:
            return false
        case .logout, .me, .servers, .connect, .disconnect, .deleteAccount, .validateIAP:
            return true
        }
    }
}
