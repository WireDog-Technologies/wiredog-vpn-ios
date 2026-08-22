import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case badRequest
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case deviceLimitReached
    case serverError(Int)
    case networkError(Error)
    case decodingError(Error)
    case encodingError(Error)
    case unknown(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .badRequest:
            return "Invalid request"
        case .unauthorized:
            return "Authentication required. Please log in again."
        case .forbidden:
            return "Access denied. Check your subscription."
        case .notFound:
            return "Resource not found"
        case .rateLimited:
            return "Too many requests. Please wait and try again."
        case .deviceLimitReached:
            return "You've reached your 5-device limit. Disconnect another device to continue."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse server response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .unknown(let code):
            return "Unknown error (\(code))"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .serverError, .rateLimited, .networkError:
            return true
        case .invalidURL, .invalidResponse, .badRequest, .unauthorized, .forbidden, .notFound, .deviceLimitReached, .decodingError, .encodingError, .unknown:
            return false
        }
    }
}
