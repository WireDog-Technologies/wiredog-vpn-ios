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

    func request<T: Decodable>(
        endpoint: APIEndpoint,
        body: Encodable? = nil
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(endpoint.path)

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

        // Handle HTTP status codes
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 400:
            LogService.shared.logApp("[API] 400 Bad Request", level: .error)
            throw APIError.badRequest
        case 401:
            LogService.shared.logApp("[API] 401 Unauthorized — session may have expired", level: .error)
            throw APIError.unauthorized
        case 403:
            LogService.shared.logApp("[API] 403 Forbidden", level: .error)
            throw APIError.forbidden
        case 404:
            LogService.shared.logApp("[API] 404 Not Found", level: .error)
            throw APIError.notFound
        case 429:
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
            LogService.shared.logApp("[API] Decoding error: \(error.localizedDescription)", level: .error)
            throw APIError.decodingError(error)
        }
    }

    // Convenience method for requests with no expected response body
    func requestVoid(
        endpoint: APIEndpoint,
        body: Encodable? = nil
    ) async throws {
        let _: EmptyResponse = try await request(endpoint: endpoint, body: body)
    }
}
