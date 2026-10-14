import Foundation

// MARK: - Request Models

struct ForgotPasswordRequest: Codable {
    let email: String
}

struct VerifyResetCodeRequest: Codable {
    let email: String
    let code: String
}

struct VerifyResetCodeResponse: Decodable {
    // True when the account has 2FA on: the reset itself must then carry a current 2FA code.
    let twoFactorRequired: Bool?
}

struct ResetPasswordRequest: Codable {
    let email: String
    let code: String
    let newPassword: String
    let twoFactorCode: String?
}

