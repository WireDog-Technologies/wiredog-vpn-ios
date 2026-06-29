import Foundation

// MARK: - Request Models

struct ForgotPasswordRequest: Codable {
    let email: String
}

struct VerifyResetCodeRequest: Codable {
    let email: String
    let code: String
}

struct ResetPasswordRequest: Codable {
    let email: String
    let code: String
    let newPassword: String
}

