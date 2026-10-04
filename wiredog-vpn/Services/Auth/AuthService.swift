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
    case invalidTwoFactorCode
    case twoFactorChallengeExpired
    case ssoNotAvailable
    case ssoFailed
    case ssoNoAccount
    case ssoCancelled
    case passwordChangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .keychainSaveFailed:
            return "Failed to save credentials securely"
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError(let error):
            // Despite the case name, every non-401 APIError (decoding failures, 5xx, rate
            // limits, etc.) gets wrapped here too — prefixing "Network error:" mislabeled all
            // of those as connectivity problems. APIError's own errorDescription is already
            // specific per-case, so just pass it through.
            return error.localizedDescription
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
        case .invalidTwoFactorCode:
            return "That code didn't work. Check your authenticator app and try again, or use a recovery code."
        case .twoFactorChallengeExpired:
            return "Your sign-in timed out. Please enter your password again."
        case .ssoNotAvailable:
            return "No single sign-on is set up for this email. Sign in with your password instead."
        case .ssoFailed:
            return "Single sign-on didn't complete. Please try again."
        case .ssoNoAccount:
            return "Your organization hasn't given this email access. Contact your administrator."
        case .ssoCancelled:
            return "Single sign-on was cancelled."
        case .passwordChangeFailed(let message):
            return message
        }
    }
}

/// What a password/account-number login produced: a session, or a pending 2FA challenge the
/// caller must redeem with `verifyTwoFactor`.
enum LoginOutcome: Equatable {
    case signedIn
    case twoFactorRequired(challengeToken: String)
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

    @discardableResult
    func loginStandard(email: String, password: String) async throws -> LoginOutcome {
        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            let request = StandardLoginRequest(identifier: email, password: password)
            let result: LoginResult = try await apiClient.request(
                endpoint: .login,
                body: request
            )

            switch result {
            case .twoFactorRequired(let challengeToken):
                LogService.shared.logApp("Standard login: 2FA required")
                return .twoFactorRequired(challengeToken: challengeToken)
            case .signedIn(let response):
                try await completeLogin(token: response.token)
                LogService.shared.logApp("User logged in (standard)")
                return .signedIn
            }
        } catch let apiError as APIError {
            if case .unauthorized = apiError {
                LogService.shared.logApp("Standard login failed: invalid credentials", level: .error)
                throw AuthError.invalidCredentials
            }
            LogService.shared.logApp("Standard login failed: \(apiError.localizedDescription)", level: .error)
            throw AuthError.networkError(apiError)
        } catch {
            // Reaching here means something other than APIError was thrown (e.g. the keychain
            // save above) — naming the type keeps this distinguishable from an API failure.
            LogService.shared.logApp("Standard login failed (\(type(of: error))): \(error.localizedDescription)", level: .error)
            self.error = error as? AuthError ?? AuthError.networkError(error)
            throw error
        }
    }

    @discardableResult
    func loginAnonymous(accountNumber: String) async throws -> LoginOutcome {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let cleanedNumber = accountNumber
            .replacingOccurrences(of: " ", with: "")
            .uppercased()

        do {
            let request = AnonymousLoginRequest(identifier: cleanedNumber)
            let result: LoginResult = try await apiClient.request(
                endpoint: .login,
                body: request
            )

            switch result {
            case .twoFactorRequired(let challengeToken):
                LogService.shared.logApp("Anonymous login: 2FA required")
                return .twoFactorRequired(challengeToken: challengeToken)
            case .signedIn(let response):
                try await completeLogin(token: response.token)
                LogService.shared.logApp("User logged in (anonymous)")
                return .signedIn
            }
        } catch let apiError as APIError {
            if case .unauthorized = apiError {
                LogService.shared.logApp("Anonymous login failed: invalid account number", level: .error)
                throw AuthError.invalidCredentials
            }
            LogService.shared.logApp("Anonymous login failed: \(apiError.localizedDescription)", level: .error)
            throw AuthError.networkError(apiError)
        } catch {
            LogService.shared.logApp("Anonymous login failed (\(type(of: error))): \(error.localizedDescription)", level: .error)
            self.error = error as? AuthError ?? AuthError.networkError(error)
            throw error
        }
    }

    // MARK: - Two-Factor

    /// Second step of a login whose first step returned `.twoFactorRequired`. `code` is a 6-digit
    /// authenticator code or a recovery code. The challenge token is single-use on success but
    /// survives a wrong code, so the caller can let the user retry.
    func verifyTwoFactor(challengeToken: String, code: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            let response: LoginResponse = try await apiClient.request(
                endpoint: .verifyTwoFactor,
                body: TwoFactorVerifyRequest(challengeToken: challengeToken, code: code)
            )
            try await completeLogin(token: response.token)
            LogService.shared.logApp("User logged in (2FA verified)")
        } catch let apiError as APIError {
            // A timed-out challenge is tagged by the backend; the screen sends the user back to
            // the password step. Any other 401 is a wrong code and can simply be retried.
            if case .twoFactorChallengeExpired = apiError {
                LogService.shared.logApp("2FA verify failed: challenge expired", level: .error)
                throw AuthError.twoFactorChallengeExpired
            }
            if case .unauthorized = apiError {
                LogService.shared.logApp("2FA verify failed: invalid or expired code", level: .error)
                throw AuthError.invalidTwoFactorCode
            }
            LogService.shared.logApp("2FA verify failed: \(apiError.localizedDescription)", level: .error)
            throw AuthError.networkError(apiError)
        } catch {
            LogService.shared.logApp("2FA verify failed (\(type(of: error))): \(error.localizedDescription)", level: .error)
            self.error = error as? AuthError ?? AuthError.networkError(error)
            throw error
        }
    }

    // MARK: - SSO

    /// Whether `email`'s domain has verified SSO. Public lookup, same one the website's login uses.
    /// A failed lookup counts as "no SSO" so a network blip never blocks a password login.
    func ssoAvailable(for email: String) async -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("@") else { return false }
        do {
            let response: SSOLookupResponse = try await apiClient.request(endpoint: .loginLookup(identifier: trimmed))
            return response.sso
        } catch {
            LogService.shared.logApp("SSO lookup failed: \(error.localizedDescription)", level: .warning)
            return false
        }
    }

    /// Runs the whole native SSO flow: browser session to the org's IdP, then exchanges the
    /// one-time code the backend hands back (bound to a PKCE verifier only this call holds).
    func signInWithSSO(email: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        let domain = email.split(separator: "@").last.map { String($0).lowercased() }
        guard let domain, await ssoAvailable(for: email) else {
            throw AuthError.ssoNotAvailable
        }

        do {
            let result = try await SSOService.shared.authenticate(domain: domain)
            let response: LoginResponse = try await apiClient.request(
                endpoint: .ssoExchange,
                body: SSOExchangeRequest(code: result.code, codeVerifier: result.codeVerifier)
            )
            try await completeLogin(token: response.token)
            LogService.shared.logApp("User logged in (SSO)")
        } catch let ssoError as SSOService.SSOError {
            switch ssoError {
            case .cancelled:
                LogService.shared.logApp("SSO cancelled by user")
                throw AuthError.ssoCancelled
            case .noAccount:
                LogService.shared.logApp("SSO failed: no active org membership", level: .error)
                throw AuthError.ssoNoAccount
            case .failed:
                LogService.shared.logApp("SSO failed at the IdP/backend", level: .error)
                throw AuthError.ssoFailed
            }
        } catch let apiError as APIError {
            LogService.shared.logApp("SSO exchange failed: \(apiError.localizedDescription)", level: .error)
            if case .unauthorized = apiError { throw AuthError.ssoFailed }
            throw AuthError.networkError(apiError)
        } catch {
            LogService.shared.logApp("SSO failed (\(type(of: error))): \(error.localizedDescription)", level: .error)
            self.error = error as? AuthError ?? AuthError.networkError(error)
            throw error
        }
    }

    // MARK: - Forced Password Change

    /// Admin-provisioned employees sign in with a temporary password and must replace it
    /// (`UserProfile.mustChangePassword`). The backend clears the flag on a successful change.
    func changePassword(current: String, new: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            let _: EmptyResponse = try await apiClient.request(
                endpoint: .changePassword,
                body: ChangePasswordRequest(currentPassword: current, newPassword: new)
            )
            try await fetchUserProfile()
            LogService.shared.logApp("Password changed")
        } catch let apiError as APIError {
            LogService.shared.logApp("Password change failed: \(apiError.localizedDescription)", level: .error)
            if case .badRequest = apiError {
                throw AuthError.passwordChangeFailed("Couldn't change your password. Check your current password, and that the new one is at least 8 characters with a letter and a number.")
            }
            throw AuthError.networkError(apiError)
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
            LogService.shared.logApp("[RegisterStandard] Unexpected error (\(type(of: error))) - \(error.localizedDescription)", level: .error)
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
            LogService.shared.logApp("[RegisterAnonymous] Unexpected error (\(type(of: error))) - \(error.localizedDescription)", level: .error)
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
        try await handoffURL(for: Config.checkoutURL)
    }

    /// Same one-time-code handoff, landing on the account dashboard. Used to send an employee to
    /// the website to turn on org-required 2FA without signing in a second time.
    func dashboardHandoffURL() async throws -> URL {
        try await handoffURL(for: Config.dashboardURL)
    }

    private func handoffURL(for destination: URL) async throws -> URL {
        let response: HandoffTokenResponse = try await apiClient.request(endpoint: .handoffToken)
        guard var components = URLComponents(url: destination, resolvingAgainstBaseURL: false) else {
            return destination
        }
        components.fragment = "handoff=\(response.token)"
        return components.url ?? destination
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
            LogService.shared.logApp("[ForgotPassword] Unexpected error (\(type(of: error))) - \(error.localizedDescription)", level: .error)
            self.error = error as? AuthError ?? AuthError.networkError(error)
            throw error
        }
    }

    /// Returns true when the account has 2FA on, so the reset must also carry a 2FA code.
    @discardableResult
    func verifyResetCode(email: String, code: String) async throws -> Bool {
        isLoading = true
        error = nil

        defer { isLoading = false }

        LogService.shared.logApp("[VerifyResetCode] Starting verification for email: \(redactEmail(email))")

        do {
            let request = VerifyResetCodeRequest(email: email, code: code)
            LogService.shared.logApp("[VerifyResetCode] Sending request to /auth/verify-reset-code")

            let response: VerifyResetCodeResponse = try await apiClient.request(
                endpoint: .verifyResetCode,
                body: request
            )
            LogService.shared.logApp("[VerifyResetCode] Code verified successfully")
            return response.twoFactorRequired ?? false
        } catch let apiError as APIError {
            LogService.shared.logApp("[VerifyResetCode] API Error - \(apiError.localizedDescription)", level: .error)

            if case .badRequest = apiError {
                LogService.shared.logApp("[VerifyResetCode] Bad request (400) - Invalid or expired code", level: .error)
                throw AuthError.invalidResetCode
            }
            throw AuthError.networkError(apiError)
        } catch {
            LogService.shared.logApp("[VerifyResetCode] Unexpected error (\(type(of: error))) - \(error.localizedDescription)", level: .error)
            self.error = error as? AuthError ?? AuthError.networkError(error)
            throw error
        }
    }

    /// Returns true if the user ended up signed in. A 2FA account is NOT auto-signed-in: the reset
    /// already spent one 2FA code, and the login challenge is a separate gate, so the caller sends
    /// them back to the login screen instead of prompting for a second code right away.
    @discardableResult
    func resetPassword(email: String, code: String, newPassword: String, twoFactorCode: String? = nil) async throws -> Bool {
        isLoading = true
        error = nil

        defer { isLoading = false }

        LogService.shared.logApp("[ResetPassword] Starting password reset for email: \(redactEmail(email))")

        do {
            let request = ResetPasswordRequest(email: email, code: code, newPassword: newPassword, twoFactorCode: twoFactorCode)
            LogService.shared.logApp("[ResetPassword] Sending request to /auth/reset-password")

            let _: EmptyResponse = try await apiClient.request(
                endpoint: .resetPassword,
                body: request
            )

            if twoFactorCode != nil {
                LogService.shared.logApp("[ResetPassword] Password reset successful (2FA account, returning to login)")
                return false
            }

            LogService.shared.logApp("[ResetPassword] Password reset successful, attempting auto-login")

            // Auto-login with the new password
            try await loginStandard(email: email, password: newPassword)
            LogService.shared.logApp("[ResetPassword] Password reset successfully and auto-logged in")
            return true
        } catch let apiError as APIError {
            LogService.shared.logApp("[ResetPassword] API Error - \(apiError.localizedDescription)", level: .error)

            if case .badRequest = apiError {
                LogService.shared.logApp("[ResetPassword] Bad request (400) - Invalid code or weak password", level: .error)
                throw AuthError.invalidResetCode
            }
            throw AuthError.networkError(apiError)
        } catch {
            LogService.shared.logApp("[ResetPassword] Unexpected error (\(type(of: error))) - \(error.localizedDescription)", level: .error)
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

    /// Shared tail of every successful sign-in: persist the token, flip auth state, load the profile.
    private func completeLogin(token: String) async throws {
        guard keychainService.saveAuthToken(token) else {
            LogService.shared.logApp("Login failed: keychain save failed", level: .error)
            throw AuthError.keychainSaveFailed
        }

        isAuthenticated = true
        try await fetchUserProfile()
    }

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
            LogService.shared.logApp("[Auth] Session check failed (\(type(of: error))): \(error.localizedDescription) — keeping session", level: .warning)
        }
    }
}
