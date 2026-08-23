import Foundation
import Combine

enum AuthError: LocalizedError {
    case keychainSaveFailed
    case invalidCredentials
    case networkError(Error)
    case notAuthenticated
    case invalidEmail
    case invalidResetCode
    case expiredResetCode
    case weakPassword(String)
    case emailAlreadyRegistered
    case accountCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .keychainSaveFailed:
            return "Failed to save credentials securely"
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .notAuthenticated:
            return "Not authenticated"
        case .invalidEmail:
            return "Invalid email format"
        case .invalidResetCode:
            return "Invalid reset code"
        case .expiredResetCode:
            return "Reset code expired or not found"
        case .weakPassword(let message):
            return message
        case .emailAlreadyRegistered:
            return "This email is already registered"
        case .accountCreationFailed(let message):
            return message
        }
    }
}

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isAuthenticated = false
    @Published var currentUser: UserProfile?
    @Published var isLoading = false
    @Published var error: AuthError?

    private let keychainService: KeychainServiceProtocol
    private let apiClient: APIClient

    init(
        keychainService: KeychainServiceProtocol = KeychainService.shared,
        apiClient: APIClient = .shared,
        checkSession: Bool = true
    ) {
        self.keychainService = keychainService
        self.apiClient = apiClient
        if checkSession {
            Task {
                await checkExistingSession()
            }
        }
    }

    // MARK: - Public Methods

    func loginStandard(email: String, password: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            let request = StandardLoginRequest(identifier: email, password: password)
            let response: LoginResponse = try await apiClient.request(
                endpoint: .login,
                body: request
            )

            guard keychainService.saveAuthToken(response.token) else {
                LogService.shared.logApp("Standard login failed: keychain save failed", level: .error)
                throw AuthError.keychainSaveFailed
            }

            isAuthenticated = true
            try await fetchUserProfile()
            LogService.shared.logApp("User logged in (standard)")
        } catch let apiError as APIError {
            if case .unauthorized = apiError {
                LogService.shared.logApp("Standard login failed: invalid credentials", level: .error)
                throw AuthError.invalidCredentials
            }
            LogService.shared.logApp("Standard login failed: \(apiError.localizedDescription)", level: .error)
            throw AuthError.networkError(apiError)
        } catch {
            LogService.shared.logApp("Standard login failed: \(error.localizedDescription)", level: .error)
            self.error = error as? AuthError ?? AuthError.networkError(error)
            throw error
        }
    }

    func loginAnonymous(accountNumber: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let cleanedNumber = accountNumber
            .replacingOccurrences(of: " ", with: "")
            .uppercased()

        do {
            let request = AnonymousLoginRequest(identifier: cleanedNumber)
            let response: LoginResponse = try await apiClient.request(
                endpoint: .login,
                body: request
            )

            guard keychainService.saveAuthToken(response.token) else {
                LogService.shared.logApp("Anonymous login failed: keychain save failed", level: .error)
                throw AuthError.keychainSaveFailed
            }

            isAuthenticated = true
            try await fetchUserProfile()
            LogService.shared.logApp("User logged in (anonymous)")
        } catch let apiError as APIError {
            if case .unauthorized = apiError {
                LogService.shared.logApp("Anonymous login failed: invalid account number", level: .error)
                throw AuthError.invalidCredentials
            }
            LogService.shared.logApp("Anonymous login failed: \(apiError.localizedDescription)", level: .error)
            throw AuthError.networkError(apiError)
        } catch {
            LogService.shared.logApp("Anonymous login failed: \(error.localizedDescription)", level: .error)
            self.error = error as? AuthError ?? AuthError.networkError(error)
            throw error
        }
    }

    /// Brings published auth state in line with a token an out-of-band flow (TV pairing) has
    /// already saved to the keychain, then fetches the profile — same effect as a normal login's
    /// tail end, without repeating its request/response handling.
    func signInWithStoredToken() async throws {
        isAuthenticated = true
        try await fetchUserProfile()
        LogService.shared.logApp("User signed in (TV pairing)")
    }

    func logout() async {
        isLoading = true
        defer { isLoading = false }

        // Attempt server logout (ignore errors)
        do {
            try await apiClient.requestVoid(endpoint: .logout)
        } catch {
            // Ignore logout errors - we still want to clear local state
        }

        keychainService.deleteAuthToken()
        currentUser = nil
        isAuthenticated = false
        LogService.shared.logApp("User logged out")
    }

    func deleteAccount() async throws {
        isLoading = true
        defer { isLoading = false }

        try await apiClient.requestVoid(endpoint: .deleteAccount)

        keychainService.deleteAuthToken()
        currentUser = nil
        isAuthenticated = false
        LogService.shared.logApp("Account deleted")
    }

    func fetchUserProfile() async throws {
        guard isAuthenticated else {
            throw AuthError.notAuthenticated
        }

        let profile: UserProfile = try await apiClient.request(endpoint: .me)
        currentUser = profile
    }

    // MARK: - Account Registration

    func registerStandard(email: String, password: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        LogService.shared.logApp("[RegisterStandard] Starting registration for email: \(redactEmail(email))")

        do {
            let request = StandardAccountRequest(email: email, password: password)
            LogService.shared.logApp("[RegisterStandard] Sending request to /auth/register/standard")

            let response: StandardAccountResponse = try await apiClient.request(
                endpoint: .registerStandard,
                body: request
            )

            LogService.shared.logApp("[RegisterStandard] Account created successfully, account number: \(redactAccountNumber(response.accountNumber))")

            // Auto-login with the registered credentials
            try await loginStandard(email: email, password: password)
            LogService.shared.logApp("[RegisterStandard] Auto-login successful")
        } catch let apiError as APIError {
            LogService.shared.logApp("[RegisterStandard] API Error - \(apiError.localizedDescription)", level: .error)

            if case .badRequest = apiError {
                LogService.shared.logApp("[RegisterStandard] Validation error (400)", level: .error)
                throw AuthError.weakPassword("Validation failed - check email format and password requirements")
            }
            throw AuthError.networkError(apiError)
        } catch {
            LogService.shared.logApp("[RegisterStandard] Unexpected error - \(error.localizedDescription)", level: .error)
            self.error = error as? AuthError ?? AuthError.networkError(error)
            throw error
        }
    }

    func registerAnonymous() async throws -> String {
        isLoading = true
        error = nil

        defer { isLoading = false }

        LogService.shared.logApp("[RegisterAnonymous] Starting anonymous account creation")

        do {
            LogService.shared.logApp("[RegisterAnonymous] Sending request to /auth/register/anonymous")

            let response: AnonymousAccountResponse = try await apiClient.request(
                endpoint: .registerAnonymous,
                body: AnonymousAccountRequest()
            )

            LogService.shared.logApp("[RegisterAnonymous] Account created successfully, account number: \(redactAccountNumber(response.accountNumber))")

            return response.accountNumber
        } catch let apiError as APIError {
            LogService.shared.logApp("[RegisterAnonymous] API Error - \(apiError.localizedDescription)", level: .error)
            throw AuthError.accountCreationFailed("Failed to create anonymous account. Please try again.")
        } catch {
            LogService.shared.logApp("[RegisterAnonymous] Unexpected error - \(error.localizedDescription)", level: .error)
            self.error = error as? AuthError ?? AuthError.networkError(error)
            throw error
        }
    }

    // MARK: - Checkout Handoff

    /// Mints a one-time code so the checkout website can recognize this already-authenticated
    /// user without asking them to sign in again. The code travels as a URL fragment (`#`), not
    /// a query parameter — fragments are never sent to the server or included in a Referer
    /// header, matching the mitigation Legal signed off on for this flow.
    func checkoutHandoffURL() async throws -> URL {
        let response: HandoffTokenResponse = try await apiClient.request(endpoint: .handoffToken)
        guard var components = URLComponents(url: Config.checkoutURL, resolvingAgainstBaseURL: false) else {
            return Config.checkoutURL
        }
        components.fragment = "handoff=\(response.token)"
        return components.url ?? Config.checkoutURL
    }

    // MARK: - Password Reset

    func forgotPassword(email: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        LogService.shared.logApp("[ForgotPassword] Starting with email: \(redactEmail(email))")

        do {
            let request = ForgotPasswordRequest(email: email)
            LogService.shared.logApp("[ForgotPassword] Sending request to /auth/forgot-password")

            let _: EmptyResponse = try await apiClient.request(
                endpoint: .forgotPassword,
                body: request
            )
            LogService.shared.logApp("[ForgotPassword] Success - Reset code sent")
        } catch let apiError as APIError {
            LogService.shared.logApp("[ForgotPassword] API Error - \(apiError.localizedDescription)", level: .error)

            if case .badRequest = apiError {
                LogService.shared.logApp("[ForgotPassword] Bad request (400) - Likely invalid email format", level: .error)
                throw AuthError.invalidEmail
            }
            throw AuthError.networkError(apiError)
        } catch {
            LogService.shared.logApp("[ForgotPassword] Unexpected error - \(error.localizedDescription)", level: .error)
            self.error = error as? AuthError ?? AuthError.networkError(error)
            throw error
        }
    }

    func verifyResetCode(email: String, code: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        LogService.shared.logApp("[VerifyResetCode] Starting verification for email: \(redactEmail(email))")

        do {
            let request = VerifyResetCodeRequest(email: email, code: code)
            LogService.shared.logApp("[VerifyResetCode] Sending request to /auth/verify-reset-code")

            let _: EmptyResponse = try await apiClient.request(
                endpoint: .verifyResetCode,
                body: request
            )
            LogService.shared.logApp("[VerifyResetCode] Code verified successfully")
        } catch let apiError as APIError {
            LogService.shared.logApp("[VerifyResetCode] API Error - \(apiError.localizedDescription)", level: .error)

            if case .badRequest = apiError {
                LogService.shared.logApp("[VerifyResetCode] Bad request (400) - Invalid or expired code", level: .error)
                throw AuthError.invalidResetCode
            }
            throw AuthError.networkError(apiError)
        } catch {
            LogService.shared.logApp("[VerifyResetCode] Unexpected error - \(error.localizedDescription)", level: .error)
            self.error = error as? AuthError ?? AuthError.networkError(error)
            throw error
        }
    }

    func resetPassword(email: String, code: String, newPassword: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        LogService.shared.logApp("[ResetPassword] Starting password reset for email: \(redactEmail(email))")

        do {
            let request = ResetPasswordRequest(email: email, code: code, newPassword: newPassword)
            LogService.shared.logApp("[ResetPassword] Sending request to /auth/reset-password")

            let _: EmptyResponse = try await apiClient.request(
                endpoint: .resetPassword,
                body: request
            )

            LogService.shared.logApp("[ResetPassword] Password reset successful, attempting auto-login")

            // Auto-login with the new password
            try await loginStandard(email: email, password: newPassword)
            LogService.shared.logApp("[ResetPassword] Password reset successfully and auto-logged in")
        } catch let apiError as APIError {
            LogService.shared.logApp("[ResetPassword] API Error - \(apiError.localizedDescription)", level: .error)

            if case .badRequest = apiError {
                LogService.shared.logApp("[ResetPassword] Bad request (400) - Invalid code or weak password", level: .error)
                throw AuthError.invalidResetCode
            }
            throw AuthError.networkError(apiError)
        } catch {
            LogService.shared.logApp("[ResetPassword] Unexpected error - \(error.localizedDescription)", level: .error)
            self.error = error as? AuthError ?? AuthError.networkError(error)
            throw error
        }
    }

    // MARK: - Session Expiry

    func handleUnauthorized() {
        keychainService.deleteAuthToken()
        currentUser = nil
        isAuthenticated = false
        LogService.shared.logApp("Session expired — returning to login", level: .warning)
    }

    // MARK: - Private Methods

    private func redactEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return "***" }
        let localPart = String(parts[0])
        let domain = String(parts[1])
        if localPart.count <= 2 {
            return "***@\(domain)"
        }
        let first = localPart.prefix(1)
        let last = localPart.suffix(1)
        return "\(first)***\(last)@\(domain)"
    }

    private func redactAccountNumber(_ accountNumber: String) -> String {
        guard accountNumber.count >= 4 else { return "****" }
        let suffix = String(accountNumber.suffix(4))
        return "****\(suffix)"
    }

    private func checkExistingSession() async {
        guard keychainService.hasAuthToken else {
            isAuthenticated = false
            return
        }

        isAuthenticated = true
        LogService.shared.logApp("[Auth] Session token found, restoring session", level: .debug)
        // App launch/relaunch is a common place to land on a stale pooled connection from
        // before a network change — reset first so this fetch doesn't fail for that reason.
        await apiClient.resetConnections()
        do {
            try await fetchUserProfile()
            LogService.shared.logApp("[Auth] Session restored successfully")
        } catch let apiError as APIError {
            if case .unauthorized = apiError {
                // Confirmed 401 — token is genuinely expired
                LogService.shared.logApp("[Auth] Session expired (401 from server)", level: .warning)
                keychainService.deleteAuthToken()
                isAuthenticated = false
            } else {
                // Network error, timeout, server blip — keep the user logged in
                LogService.shared.logApp("[Auth] Session check failed (network error): \(apiError.localizedDescription) — keeping session", level: .warning)
            }
        } catch {
            // Non-API error (e.g. decoding failure) — keep the user logged in
            LogService.shared.logApp("[Auth] Session check failed: \(error.localizedDescription) — keeping session", level: .warning)
        }
    }
}
