import Foundation

/// Separate MockURLProtocol for AuthService tests to avoid cross-suite interference
/// with APIClientTests which uses the primary MockURLProtocol.
class AuthServiceMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var mockData: Data?
    nonisolated(unsafe) static var mockResponse: URLResponse?
    nonisolated(unsafe) static var mockError: Error?
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        AuthServiceMockURLProtocol.capturedRequests.append(request)

        if let error = Self.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if let response = Self.mockResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }

        if let data = Self.mockData {
            client?.urlProtocol(self, didLoad: data)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        mockData = nil
        mockResponse = nil
        mockError = nil
        capturedRequests = []
    }

    static func configure(
        data: Data? = nil,
        statusCode: Int = 200,
        url: String = "https://api.example.com/api/test"
    ) {
        mockData = data
        mockResponse = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )
        mockError = nil
    }
}

func makeAuthServiceMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AuthServiceMockURLProtocol.self]
    return URLSession(configuration: config)
}
