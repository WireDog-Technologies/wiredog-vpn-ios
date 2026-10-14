import Testing
import Foundation
@testable import wiredog_vpn

@Suite(.serialized)
@MainActor
struct TwoFactorAndSSOTests {

    // MARK: - Helpers

    private func makeService(
        keychain: MockKeychainService = MockKeychainService()
    ) -> (AuthService, MockKeychainService) {
        AuthServiceMockURLProtocol.reset()
        let session = makeAuthServiceMockSession()
        let apiClient = APIClient(
            baseURL: URL(string: "https://api.example.com/api")!,
            session: session,
            keychainService: keychain
        )
        let service = AuthService(
            keychainService: keychain,
            apiClient: apiClient,
            checkSession: false
        )
        return (service, keychain)
    }

    private let challengeJSON = """
    { "requiresTwoFactor": true, "challengeToken": "\(String(repeating: "a", count: 64))", "expiresIn": 300 }
    """.data(using: .utf8)!

    // MARK: - LoginResult decoding

    @Test func loginResult_decodesTokenResponse() throws {
        let result = try JSONDecoder().decode(LoginResult.self, from: TestFixtures.loginResponseJSON(token: "tok"))

        guard case .signedIn(let response) = result else {
            Issue.record("Expected .signedIn")
            return
        }
        #expect(response.token == "tok")
    }

    @Test func loginResult_decodesTwoFactorChallenge() throws {
        let result = try JSONDecoder().decode(LoginResult.self, from: challengeJSON)

        guard case .twoFactorRequired(let challengeToken) = result else {
            Issue.record("Expected .twoFactorRequired")
            return
        }
        #expect(challengeToken == String(repeating: "a", count: 64))
    }

    @Test func loginResult_challengeWithoutTokenFailsToDecode() {
        let broken = #"{ "requiresTwoFactor": true }"#.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(LoginResult.self, from: broken)
        }
    }

    // MARK: - Login with 2FA

    @Test func loginStandard_twoFactorRequired_returnsChallengeAndSavesNoToken() async throws {
        let (service, keychain) = makeService()
        AuthServiceMockURLProtocol.configure(data: challengeJSON)

        let outcome = try await service.loginStandard(email: "a@example.com", password: "password123")

        #expect(outcome == .twoFactorRequired(challengeToken: String(repeating: "a", count: 64)))
        #expect(keychain.hasAuthToken == false)
        #expect(service.isAuthenticated == false)
    }

    @Test func loginAnonymous_twoFactorRequired_returnsChallengeAndSavesNoToken() async throws {
        let (service, keychain) = makeService()
        AuthServiceMockURLProtocol.configure(data: challengeJSON)

        let outcome = try await service.loginAnonymous(accountNumber: "1234-5678-9012-3456")

        #expect(outcome == .twoFactorRequired(challengeToken: String(repeating: "a", count: 64)))
        #expect(keychain.hasAuthToken == false)
    }

    // MARK: - verifyTwoFactor

    @Test func verifyTwoFactor_wrongCode_throwsInvalidTwoFactorCode_andSavesNoToken() async {
        let (service, keychain) = makeService()
        AuthServiceMockURLProtocol.configure(data: #"{ "error": "Invalid or expired code" }"#.data(using: .utf8)!, statusCode: 401)

        await #expect(throws: AuthError.self) {
            try await service.verifyTwoFactor(challengeToken: String(repeating: "a", count: 64), code: "000000")
        }
        #expect(keychain.hasAuthToken == false)
    }

    @Test func verifyTwoFactor_success_savesToken() async {
        let (service, keychain) = makeService()
        AuthServiceMockURLProtocol.configure(data: TestFixtures.loginResponseJSON(token: "jwt-after-2fa"))

        // The follow-up /auth/me gets the same canned body and may fail to decode as a profile;
        // the token is saved before that, which is what this test is about.
        try? await service.verifyTwoFactor(challengeToken: String(repeating: "a", count: 64), code: "123456")

        #expect(keychain.getAuthToken() == "jwt-after-2fa")
    }

    // MARK: - Password reset with 2FA

    @Test func verifyResetCode_reportsWhetherTwoFactorIsRequired() async throws {
        let (service, _) = makeService()
        AuthServiceMockURLProtocol.configure(data: #"{ "message": "ok", "twoFactorRequired": true }"#.data(using: .utf8)!)

        let required = try await service.verifyResetCode(email: "a@example.com", code: "123456")

        #expect(required == true)
    }

    @Test func verifyResetCode_withoutFlag_meansNoTwoFactor() async throws {
        let (service, _) = makeService()
        AuthServiceMockURLProtocol.configure(data: #"{ "message": "ok" }"#.data(using: .utf8)!)

        let required = try await service.verifyResetCode(email: "a@example.com", code: "123456")

        #expect(required == false)
    }

    @Test func resetPassword_withTwoFactorCode_doesNotAutoLogin() async throws {
        let (service, keychain) = makeService()
        AuthServiceMockURLProtocol.configure(data: #"{ "message": "ok" }"#.data(using: .utf8)!)

        let signedIn = try await service.resetPassword(
            email: "a@example.com", code: "123456", newPassword: "newpass123", twoFactorCode: "654321"
        )

        #expect(signedIn == false)
        #expect(keychain.hasAuthToken == false)
        #expect(service.isAuthenticated == false)
    }

    // MARK: - SSO lookup

    @Test func ssoAvailable_trueWhenDomainHasSSO() async {
        let (service, _) = makeService()
        AuthServiceMockURLProtocol.configure(data: #"{ "sso": true, "domain": "acme.com" }"#.data(using: .utf8)!)

        #expect(await service.ssoAvailable(for: "ann@acme.com") == true)
    }

    @Test func ssoAvailable_falseWhenNoSSO() async {
        let (service, _) = makeService()
        AuthServiceMockURLProtocol.configure(data: #"{ "sso": false }"#.data(using: .utf8)!)

        #expect(await service.ssoAvailable(for: "ann@gmail.com") == false)
    }

    @Test func ssoAvailable_failedLookupCountsAsNoSSO() async {
        let (service, _) = makeService()
        AuthServiceMockURLProtocol.configure(data: "{}".data(using: .utf8)!, statusCode: 500)

        #expect(await service.ssoAvailable(for: "ann@acme.com") == false)
    }

    @Test func ssoAvailable_neverCallsOutForAccountNumbers() async {
        let (service, _) = makeService()
        // Would decode as sso == true if it were (wrongly) requested.
        AuthServiceMockURLProtocol.configure(data: #"{ "sso": true }"#.data(using: .utf8)!)

        #expect(await service.ssoAvailable(for: "1234-5678-9012-3456") == false)
    }

    // MARK: - PKCE

    @Test func pkce_challengeMatchesRFC7636Vector() {
        // RFC 7636 appendix B.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

        #expect(SSOService.codeChallenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func pkce_verifierIsBase64URLAndLongEnough() {
        let verifier = SSOService.makeCodeVerifier()

        #expect(verifier.count == 43)
        #expect(verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(SSOService.makeCodeVerifier() != verifier)
    }

    // MARK: - Endpoints

    @Test func newEndpoints_pathsMethodsAndAuth() {
        #expect(APIEndpoint.verifyTwoFactor.path == "/auth/2fa/verify")
        #expect(APIEndpoint.verifyTwoFactor.method == .POST)
        #expect(APIEndpoint.verifyTwoFactor.requiresAuth == false)

        #expect(APIEndpoint.ssoExchange.path == "/auth/sso/exchange")
        #expect(APIEndpoint.ssoExchange.method == .POST)
        #expect(APIEndpoint.ssoExchange.requiresAuth == false)

        #expect(APIEndpoint.loginLookup(identifier: "a@b.com").path == "/auth/login/lookup")
        #expect(APIEndpoint.loginLookup(identifier: "a@b.com").method == .GET)
        #expect(APIEndpoint.loginLookup(identifier: "a@b.com").requiresAuth == false)
        #expect(APIEndpoint.loginLookup(identifier: "a@b.com").queryItems == [URLQueryItem(name: "identifier", value: "a@b.com")])

        #expect(APIEndpoint.changePassword.path == "/auth/password")
        #expect(APIEndpoint.changePassword.method == .PATCH)
        #expect(APIEndpoint.changePassword.requiresAuth == true)
    }

    // MARK: - 403 error codes

    @Test func forbiddenWithCode_mapsToSpecificErrors() async {
        let cases: [(String, (APIError) -> Bool)] = [
            ("two_factor_setup_required", { if case .twoFactorSetupRequired = $0 { return true } else { return false } }),
            ("server_not_available", { if case .serverNotAvailable = $0 { return true } else { return false } }),
            ("subscription_required", { if case .subscriptionRequired = $0 { return true } else { return false } }),
        ]
        for (code, matches) in cases {
            AuthServiceMockURLProtocol.reset()
            let apiClient = APIClient(
                baseURL: URL(string: "https://api.example.com/api")!,
                session: makeAuthServiceMockSession(),
                keychainService: MockKeychainService()
            )
            AuthServiceMockURLProtocol.configure(data: "{ \"error\": \"x\", \"code\": \"\(code)\" }".data(using: .utf8)!, statusCode: 403)

            do {
                let _: EmptyResponse = try await apiClient.request(endpoint: .connect)
                Issue.record("Expected a throw for \(code)")
            } catch let error as APIError {
                #expect(matches(error), "Wrong APIError for \(code): \(error)")
            } catch {
                Issue.record("Unexpected error type for \(code)")
            }
        }
    }

    @Test func plainForbidden_staysForbidden() async {
        AuthServiceMockURLProtocol.reset()
        let apiClient = APIClient(
            baseURL: URL(string: "https://api.example.com/api")!,
            session: makeAuthServiceMockSession(),
            keychainService: MockKeychainService()
        )
        AuthServiceMockURLProtocol.configure(data: #"{ "error": "nope" }"#.data(using: .utf8)!, statusCode: 403)

        do {
            let _: EmptyResponse = try await apiClient.request(endpoint: .connect)
            Issue.record("Expected a throw")
        } catch let error as APIError {
            if case .forbidden = error {} else { Issue.record("Expected .forbidden, got \(error)") }
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    // MARK: - Profile: organization fields and entitlement

    @Test func userProfile_organizationFieldsDecode_andDefaultWhenAbsent() throws {
        let org = #"""
        { "id": 1, "accountType": "standard", "isActive": true, "planTier": "paid",
          "subscriptionManagedByOrganization": true, "organizationName": "Acme", "organizationRole": "member",
          "twoFactorRequiredByOrg": true, "totpEnabled": false, "mustChangePassword": true }
        """#.data(using: .utf8)!
        let profile = try JSONDecoder().decode(UserProfile.self, from: org)

        #expect(profile.subscriptionManagedByOrganization)
        #expect(profile.organizationName == "Acme")
        #expect(profile.twoFactorRequiredByOrg)
        #expect(profile.totpEnabled == false)
        #expect(profile.mustChangePassword)
        #expect(profile.isOrganizationMember)

        let plain = try JSONDecoder().decode(UserProfile.self, from: TestFixtures.minimalUserProfileJSON)
        #expect(plain.subscriptionManagedByOrganization == false)
        #expect(plain.twoFactorRequiredByOrg == false)
        #expect(plain.mustChangePassword == false)
        #expect(plain.isOrganizationMember == false)
    }

    @Test func userProfile_orgSeatWithNoExpiryStillHasEntitlement() throws {
        let json = #"""
        { "id": 1, "accountType": "standard", "isActive": true, "planTier": "paid",
          "subscriptionManagedByOrganization": true, "organizationName": "Acme" }
        """#.data(using: .utf8)!
        let seat = try JSONDecoder().decode(UserProfile.self, from: json)

        #expect(seat.subscriptionExpiresAt == nil)
        #expect(seat.hasEntitlement)
    }

    @Test func userProfile_personalAccountNeedsAFutureExpiry() throws {
        let expired = #"{ "id": 1, "accountType": "standard", "isActive": true, "planTier": "paid" }"#.data(using: .utf8)!

        #expect(try JSONDecoder().decode(UserProfile.self, from: expired).hasEntitlement == false)
    }

    @Test func unknownEnumValues_doNotBreakProfileDecoding() throws {
        let json = #"{ "id": 1, "accountType": "enterprise", "planTier": "business" }"#.data(using: .utf8)!
        let profile = try JSONDecoder().decode(UserProfile.self, from: json)

        #expect(profile.accountType == .standard)
        #expect(profile.planTier == .free)
    }

    // MARK: - Organization access (revoked / lapsed)

    private func profile(access: String?) throws -> UserProfile {
        let accessField = access.map { ", \"organizationAccess\": \"\($0)\"" } ?? ""
        let json = "{ \"id\": 1, \"accountType\": \"standard\", \"isActive\": false\(accessField) }".data(using: .utf8)!
        return try JSONDecoder().decode(UserProfile.self, from: json)
    }

    @Test func organizationAccess_decodesEachState() throws {
        #expect(try profile(access: "active").organizationAccess == .active)
        #expect(try profile(access: "inactive").organizationAccess == .inactive)
        #expect(try profile(access: "revoked").organizationAccess == .revoked)
        #expect(try profile(access: nil).organizationAccess == nil)
    }

    @Test func organizationAccess_unknownValueNeverLocksAnyoneOut() throws {
        let unknown = try profile(access: "suspended")

        #expect(unknown.organizationAccess == .active)
        #expect(unknown.lostOrganizationAccess == nil)
    }

    @Test func lostOrganizationAccess_onlyForInactiveAndRevoked() throws {
        #expect(try profile(access: "inactive").lostOrganizationAccess == .inactive)
        #expect(try profile(access: "revoked").lostOrganizationAccess == .revoked)
        #expect(try profile(access: "active").lostOrganizationAccess == nil)
        #expect(try profile(access: nil).lostOrganizationAccess == nil)
    }

    @Test func inactiveOrgMemberStaysOrgManaged_butRevokedBecomesAConsumer() throws {
        #expect(try profile(access: "inactive").isOrganizationMember == true)
        #expect(try profile(access: "revoked").isOrganizationMember == false)
    }

    @Test func organizationAccessMessages_areNonEmptyForLostStates() {
        #expect(!OrganizationAccess.inactive.userMessage.isEmpty)
        #expect(!OrganizationAccess.revoked.userMessage.isEmpty)
        #expect(OrganizationAccess.inactive.userMessage != OrganizationAccess.revoked.userMessage)
    }

    // MARK: - Expired vs wrong 2FA code

    @Test func verifyTwoFactor_expiredChallenge_throwsChallengeExpired() async {
        let (service, keychain) = makeService()
        AuthServiceMockURLProtocol.configure(
            data: #"{ "error": "Your sign-in timed out. Please sign in again.", "code": "two_factor_challenge_expired" }"#.data(using: .utf8)!,
            statusCode: 401
        )

        do {
            try await service.verifyTwoFactor(challengeToken: String(repeating: "a", count: 64), code: "123456")
            Issue.record("Expected a throw")
        } catch let error as AuthError {
            if case .twoFactorChallengeExpired = error {} else { Issue.record("Expected .twoFactorChallengeExpired, got \(error)") }
        } catch {
            Issue.record("Unexpected error type")
        }
        #expect(keychain.hasAuthToken == false)
    }

    @Test func verifyTwoFactor_wrongCode_isStillAPlainInvalidCode() async {
        let (service, _) = makeService()
        AuthServiceMockURLProtocol.configure(
            data: #"{ "error": "Invalid or expired code", "code": "two_factor_invalid_code" }"#.data(using: .utf8)!,
            statusCode: 401
        )

        do {
            try await service.verifyTwoFactor(challengeToken: String(repeating: "a", count: 64), code: "000000")
            Issue.record("Expected a throw")
        } catch let error as AuthError {
            if case .invalidTwoFactorCode = error {} else { Issue.record("Expected .invalidTwoFactorCode, got \(error)") }
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func plain401_staysUnauthorized() async {
        AuthServiceMockURLProtocol.reset()
        let apiClient = APIClient(
            baseURL: URL(string: "https://api.example.com/api")!,
            session: makeAuthServiceMockSession(),
            keychainService: MockKeychainService()
        )
        AuthServiceMockURLProtocol.configure(data: #"{ "error": "Authentication required" }"#.data(using: .utf8)!, statusCode: 401)

        do {
            let _: EmptyResponse = try await apiClient.request(endpoint: .me)
            Issue.record("Expected a throw")
        } catch let error as APIError {
            if case .unauthorized = error {} else { Issue.record("Expected .unauthorized, got \(error)") }
        } catch {
            Issue.record("Unexpected error type")
        }
    }
}
