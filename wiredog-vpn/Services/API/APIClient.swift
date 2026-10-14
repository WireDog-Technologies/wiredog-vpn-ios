import Foundation

actor APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let keychainService: KeychainServiceProtocol

    init(
        baseURL: URL? = nil,
        session: URLSession? = nil,
        keychainService: KeychainServiceProtocol? = nil
    ) {
        self.baseURL = baseURL ?? Config.apiBaseURL
        self.keychainService = keychainService ?? KeychainService.shared

        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = Config.apiRequestTimeout
            config.timeoutIntervalForResource = Config.apiResourceTimeout
            self.session = URLSession(configuration: config)
        }

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string: \(dateString)")
        }

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Public Methods

    /// Drops any pooled/keep-alive connections. Must be called after the VPN tunnel connects
    /// or disconnects — otherwise a request can keep reusing a socket opened over the old
    /// network interface and fail/time out even though the network is otherwise fine.
    func resetConnections() async {
        await withCheckedContinuation { continuation in
            session.reset { continuation.resume() }
        }
    }

    func request<T: Decodable>(
        endpoint: APIEndpoint,
        body: Encodable? = nil
    ) async throws -> T {
        var url = baseURL.appendingPathComponent(endpoint.path)
        if !endpoint.queryItems.isEmpty,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = endpoint.queryItems
            url = components.url ?? url
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add auth header if required and available
        if endpoint.requiresAuth {
            if let token = keychainService.getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        // Encode body if provided
        if let body = body {
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                LogService.shared.logApp("[API] Encoding error: \(error.localizedDescription)", level: .error)
                throw APIError.encodingError(error)
            }
        }

        // Perform request
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            LogService.shared.logApp("[API] Network error: \(error.localizedDescription)", level: .error)
            throw APIError.networkError(error)
        }

        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Sliding session renewal: the backend reissues a fresh token with a renewed expiry on
        // every authenticated request (see verifyToken in the backend's auth middleware) so an
        // actively-used app never hits its token's flat TTL. Persist it whenever present, even on
        // a non-2xx response, since the token itself was still valid to make the renewal decision.
        if let refreshedToken = httpResponse.value(forHTTPHeaderField: "X-Refreshed-Token") {
            keychainService.saveAuthToken(refreshedToken)
        }

        // Handle HTTP status codes
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 400:
            LogService.shared.logApp("[API] 400 Bad Request", level: .error)
            throw APIError.badRequest
        case 401:
            // /auth/2fa/verify tags a timed-out sign-in so it is not mistaken for a wrong code.
            if (try? decoder.decode(ErrorResponse.self, from: data))?.code == "two_factor_challenge_expired" {
                LogService.shared.logApp("[API] 401 Two-factor challenge expired", level: .error)
                throw APIError.twoFactorChallengeExpired
            }
            LogService.shared.logApp("[API] 401 Unauthorized — session may have expired", level: .error)
            throw APIError.unauthorized
        case 403:
            // Some 403s carry a machine-readable `code` so the app can react specifically
            // instead of showing the generic "check your subscription" message.
            switch (try? decoder.decode(ErrorResponse.self, from: data))?.code {
            case "two_factor_setup_required":
                LogService.shared.logApp("[API] 403 Org requires 2FA setup", level: .error)
                throw APIError.twoFactorSetupRequired
            case "server_not_available":
                LogService.shared.logApp("[API] 403 Server not available to this organization", level: .error)
                throw APIError.serverNotAvailable
            case "subscription_required":
                LogService.shared.logApp("[API] 403 Subscription required", level: .error)
                throw APIError.subscriptionRequired
            default:
                LogService.shared.logApp("[API] 403 Forbidden", level: .error)
                throw APIError.forbidden
            }
        case 404:
            LogService.shared.logApp("[API] 404 Not Found", level: .error)
            throw APIError.notFound
        case 429:
            // The backend reuses 429 for two different conditions: real rate limiting and the
            // 5-device connection cap. Peek at the error message to tell them apart so the user
            // gets an actionable message instead of a generic "too many requests".
            if let serverMessage = try? decoder.decode(ErrorResponse.self, from: data).error,
               serverMessage.contains("Connection limit exceeded") {
                LogService.shared.logApp("[API] 429 Device limit reached", level: .error)
                throw APIError.deviceLimitReached
            }
            LogService.shared.logApp("[API] 429 Rate Limited — too many requests", level: .error)
            throw APIError.rateLimited
        case 500...599:
            LogService.shared.logApp("[API] Server error \(httpResponse.statusCode)", level: .error)
            throw APIError.serverError(httpResponse.statusCode)
        default:
            LogService.shared.logApp("[API] Unknown HTTP error \(httpResponse.statusCode)", level: .error)
            throw APIError.unknown(httpResponse.statusCode)
        }

        // Decode response
        do {
            if data.isEmpty || T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            return try decoder.decode(T.self, from: data)
        } catch {
            // error.localizedDescription collapses every DecodingError case down to one of two
            // generic strings ("...isn't in the correct format" / "...is missing") with no field
            // name, so it's useless for telling a missing key apart from a null value apart from
            // a type mismatch. Log the structured case instead — never the response body itself,
            // which may carry user data (e.g. /me).
            LogService.shared.logApp("[API] Decoding error for \(T.self) from \(endpoint.path): \(Self.describe(decodingError: error))", level: .error)
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Error Description

    private static func describe(decodingError error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "keyNotFound '\(key.stringValue)' at \(Self.path(context, key: key))"
        case .valueNotFound(let type, let context):
            return "valueNotFound: null for non-optional \(type) at \(Self.path(context))"
        case .typeMismatch(let type, let context):
            return "typeMismatch: expected \(type) at \(Self.path(context)) — \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "dataCorrupted at \(Self.path(context)): \(context.debugDescription)"
        @unknown default:
            return decodingError.localizedDescription
        }
    }

    private static func path(_ context: DecodingError.Context, key: CodingKey? = nil) -> String {
        let components = context.codingPath.map(\.stringValue) + (key.map { [$0.stringValue] } ?? [])
        return components.isEmpty ? "<root>" : components.joined(separator: ".")
    }

    // Convenience method for requests with no expected response body
    func requestVoid(
        endpoint: APIEndpoint,
        body: Encodable? = nil
    ) async throws {
        let _: EmptyResponse = try await request(endpoint: endpoint, body: body)
    }
}
