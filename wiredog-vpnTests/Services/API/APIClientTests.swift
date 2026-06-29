import Testing
import Foundation
@testable import wiredog_vpn

@Suite(.serialized)
struct APIClientTests {

    // MARK: - Helpers

    private func makeClient(
        keychain: MockKeychainService = MockKeychainService()
    ) -> (APIClient, MockKeychainService) {
        MockURLProtocol.reset()
        let session = makeMockSession()
        let client = APIClient(
            baseURL: URL(string: "https://api.example.com/api")!,
            session: session,
            keychainService: keychain
        )
        return (client, keychain)
    }

    private func configureSuccess(data: Data, url: String = "https://api.example.com/api/auth/login") {
        MockURLProtocol.mockData = data
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )
    }

    private func configureError(statusCode: Int, url: String = "https://api.example.com/api/auth/login") {
        MockURLProtocol.mockData = "{}".data(using: .utf8)
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )
    }

    // MARK: - Success Cases

    @Test func request_successfulLogin_decodesResponse() async throws {
        let (client, _) = makeClient()
        let json = TestFixtures.loginResponseJSON()
        configureSuccess(data: json)

        let response: LoginResponse = try await client.request(endpoint: .login, body: StandardLoginRequest(identifier: "test@example.com", password: "pass"))

        #expect(response.token == "test-token-abc123")
        #expect(response.displayName == "Test User")
        #expect(response.accountType == .standard)
    }

    @Test func request_emptyResponse_returnsEmptyResponse() async throws {
        let (client, _) = makeClient()
        configureSuccess(data: Data())

        let response: EmptyResponse = try await client.request(endpoint: .logout)
        // If we get here without throwing, EmptyResponse was returned correctly
        _ = response
    }

    @Test func request_decodesDateWithFractionalSeconds() async throws {
        let (client, _) = makeClient()
        let json = TestFixtures.fullUserProfileJSON
        configureSuccess(data: json, url: "https://api.example.com/api/auth/me")

        let keychain = MockKeychainService()
        keychain.saveAuthToken("token")
        let (authedClient, _) = makeClient(keychain: keychain)
        configureSuccess(data: json, url: "https://api.example.com/api/auth/me")

        let profile: UserProfile = try await authedClient.request(endpoint: .me)
        #expect(profile.subscriptionExpiresAt != nil)
        #expect(profile.subscriptionStartedAt != nil)
    }

    // MARK: - HTTP Error Cases

    @Test func request_400_throwsBadRequest() async throws {
        let (client, _) = makeClient()
        configureError(statusCode: 400)

        await #expect(throws: APIError.self) {
            let _: LoginResponse = try await client.request(endpoint: .login)
        }
    }

    @Test func request_401_throwsUnauthorized() async throws {
        let (client, _) = makeClient()
        configureError(statusCode: 401)

        await #expect(throws: APIError.self) {
            let _: LoginResponse = try await client.request(endpoint: .login)
        }
    }

    @Test func request_403_throwsForbidden() async throws {
        let (client, _) = makeClient()
        configureError(statusCode: 403)

        await #expect(throws: APIError.self) {
            let _: LoginResponse = try await client.request(endpoint: .login)
        }
    }

    @Test func request_404_throwsNotFound() async throws {
        let (client, _) = makeClient()
        configureError(statusCode: 404)

        await #expect(throws: APIError.self) {
            let _: LoginResponse = try await client.request(endpoint: .login)
        }
    }

    @Test func request_429_throwsRateLimited() async throws {
        let (client, _) = makeClient()
        configureError(statusCode: 429)

        await #expect(throws: APIError.self) {
            let _: LoginResponse = try await client.request(endpoint: .login)
        }
    }

    @Test func request_500_throwsServerError() async throws {
        let (client, _) = makeClient()
        configureError(statusCode: 500)

        await #expect(throws: APIError.self) {
            let _: LoginResponse = try await client.request(endpoint: .login)
        }
    }

    // MARK: - Auth Header Injection

    @Test func request_authEndpoint_injectsBearer() async throws {
        let keychain = MockKeychainService()
        keychain.saveAuthToken("my-secret-token")
        let (client, _) = makeClient(keychain: keychain)

        MockURLProtocol.mockData = TestFixtures.serverListJSON
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/api/vpn/servers")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )

        let _: [APIServer] = try await client.request(endpoint: .servers)

        let captured = MockURLProtocol.capturedRequests.first
        #expect(captured?.value(forHTTPHeaderField: "Authorization") == "Bearer my-secret-token")
    }

    @Test func request_publicEndpoint_noAuthHeader() async throws {
        let (client, _) = makeClient()
        configureSuccess(data: TestFixtures.loginResponseJSON())

        let _: LoginResponse = try await client.request(
            endpoint: .login,
            body: StandardLoginRequest(identifier: "test@test.com", password: "pass")
        )

        let captured = MockURLProtocol.capturedRequests.first
        #expect(captured?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: - Request Structure

    @Test func request_setsCorrectHTTPMethod() async throws {
        let (client, _) = makeClient()
        configureSuccess(data: TestFixtures.loginResponseJSON())

        let _: LoginResponse = try await client.request(
            endpoint: .login,
            body: StandardLoginRequest(identifier: "test@test.com", password: "pass")
        )

        let captured = MockURLProtocol.capturedRequests.first
        #expect(captured?.httpMethod == "POST")
    }

    @Test func request_setsContentTypeJSON() async throws {
        let (client, _) = makeClient()
        configureSuccess(data: TestFixtures.loginResponseJSON())

        let _: LoginResponse = try await client.request(
            endpoint: .login,
            body: StandardLoginRequest(identifier: "test@test.com", password: "pass")
        )

        let captured = MockURLProtocol.capturedRequests.first
        #expect(captured?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(captured?.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func request_encodesBodyAsJSON() async throws {
        let (client, _) = makeClient()
        configureSuccess(data: TestFixtures.loginResponseJSON())

        let _: LoginResponse = try await client.request(
            endpoint: .login,
            body: StandardLoginRequest(identifier: "user@test.com", password: "secret123")
        )

        let captured = MockURLProtocol.capturedRequests.first
        let bodyData = captured?.httpBody ?? captured?.httpBodyStream.flatMap { stream in
            stream.open()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            let count = stream.read(buffer, maxLength: 4096)
            return Data(bytes: buffer, count: count)
        }

        if let bodyData = bodyData {
            let dict = try JSONSerialization.jsonObject(with: bodyData) as? [String: String]
            #expect(dict?["identifier"] == "user@test.com")
            #expect(dict?["password"] == "secret123")
        }
    }

    // MARK: - Network Error

    @Test func request_networkError_throwsNetworkError() async throws {
        let (client, _) = makeClient()
        MockURLProtocol.reset()
        MockURLProtocol.mockError = URLError(.notConnectedToInternet)

        await #expect(throws: APIError.self) {
            let _: LoginResponse = try await client.request(endpoint: .login)
        }
    }

    // MARK: - Decoding Error

    @Test func request_invalidJSON_throwsDecodingError() async throws {
        let (client, _) = makeClient()
        configureSuccess(data: "not valid json".data(using: .utf8)!)

        await #expect(throws: APIError.self) {
            let _: LoginResponse = try await client.request(endpoint: .login)
        }
    }
}
