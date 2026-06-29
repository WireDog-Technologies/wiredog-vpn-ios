import Testing
@testable import wiredog_vpn

struct APIEndpointsTests {

    // MARK: - Path Tests

    @Test func login_path() {
        #expect(APIEndpoint.login.path == "/auth/login")
    }

    @Test func logout_path() {
        #expect(APIEndpoint.logout.path == "/auth/logout")
    }

    @Test func me_path() {
        #expect(APIEndpoint.me.path == "/auth/me")
    }

    @Test func servers_path() {
        #expect(APIEndpoint.servers.path == "/vpn/servers")
    }

    @Test func connect_path() {
        #expect(APIEndpoint.connect.path == "/vpn/connect")
    }

    @Test func disconnect_path() {
        #expect(APIEndpoint.disconnect.path == "/vpn/disconnect")
    }

    @Test func appConfig_path() {
        #expect(APIEndpoint.appConfig.path == "/app/config")
    }

    @Test func deleteAccount_path() {
        #expect(APIEndpoint.deleteAccount.path == "/auth/account")
    }

    @Test func forgotPassword_path() {
        #expect(APIEndpoint.forgotPassword.path == "/auth/forgot-password")
    }

    @Test func verifyResetCode_path() {
        #expect(APIEndpoint.verifyResetCode.path == "/auth/verify-reset-code")
    }

    @Test func resetPassword_path() {
        #expect(APIEndpoint.resetPassword.path == "/auth/reset-password")
    }

    @Test func registerStandard_path() {
        #expect(APIEndpoint.registerStandard.path == "/auth/register/standard")
    }

    @Test func registerAnonymous_path() {
        #expect(APIEndpoint.registerAnonymous.path == "/auth/register/anonymous")
    }

    // MARK: - HTTP Method Tests

    @Test func postEndpoints_usePostMethod() {
        let postEndpoints: [APIEndpoint] = [
            .login, .logout, .connect, .disconnect,
            .forgotPassword, .verifyResetCode, .resetPassword,
            .registerStandard, .registerAnonymous
        ]
        for endpoint in postEndpoints {
            #expect(endpoint.method == .POST, "Expected \(endpoint) to use POST")
        }
    }

    @Test func getEndpoints_useGetMethod() {
        let getEndpoints: [APIEndpoint] = [.me, .servers, .appConfig]
        for endpoint in getEndpoints {
            #expect(endpoint.method == .GET, "Expected \(endpoint) to use GET")
        }
    }

    @Test func deleteAccount_usesDeleteMethod() {
        #expect(APIEndpoint.deleteAccount.method == .DELETE)
    }

    // MARK: - Auth Requirement Tests

    @Test func authenticatedEndpoints_requireAuth() {
        let authRequired: [APIEndpoint] = [
            .logout, .me, .servers, .connect, .disconnect, .deleteAccount
        ]
        for endpoint in authRequired {
            #expect(endpoint.requiresAuth == true,
                   "Expected \(endpoint) to require auth")
        }
    }

    @Test func publicEndpoints_doNotRequireAuth() {
        let publicEndpoints: [APIEndpoint] = [
            .login, .appConfig, .forgotPassword, .verifyResetCode,
            .resetPassword, .registerStandard, .registerAnonymous
        ]
        for endpoint in publicEndpoints {
            #expect(endpoint.requiresAuth == false,
                   "Expected \(endpoint) to be public")
        }
    }

    // MARK: - Consistency Check

    @Test func loginAndRegister_neverRequireAuth() {
        // Login/register endpoints must always be public
        #expect(APIEndpoint.login.requiresAuth == false)
        #expect(APIEndpoint.registerStandard.requiresAuth == false)
        #expect(APIEndpoint.registerAnonymous.requiresAuth == false)
    }
}
