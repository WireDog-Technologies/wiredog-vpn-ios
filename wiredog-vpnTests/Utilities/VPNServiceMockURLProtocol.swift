import Foundation

/// Separate MockURLProtocol for VPNService tests to avoid cross-suite static-state interference
/// with APIClientTests (primary MockURLProtocol) and AuthServiceTests (AuthServiceMockURLProtocol).
class VPNServiceMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var mockData: Data?
    // Separate canned response for /vpn/disconnect requests, since disconnect() logic now branches
    // on whether the call actually decoded as a success (not just "did a response come back"), and
    // ConnectResponse/DisconnectResponse have different shapes that can't share one fixed payload.
    nonisolated(unsafe) static var mockDisconnectData: Data?
    nonisolated(unsafe) static var mockResponse: URLResponse?
    nonisolated(unsafe) static var mockError: Error?
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        VPNServiceMockURLProtocol.capturedRequests.append(request)

        if let error = Self.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if let response = Self.mockResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }

        let isDisconnect = request.url?.path.hasSuffix("/vpn/disconnect") == true
        let data = isDisconnect ? (Self.mockDisconnectData ?? Self.mockData) : Self.mockData
        if let data {
            client?.urlProtocol(self, didLoad: data)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        mockData = nil
        mockDisconnectData = nil
        mockResponse = nil
        mockError = nil
        capturedRequests = []
    }

    static func configure(
        data: Data? = nil,
        statusCode: Int = 200,
        url: String = "https://api.example.com/api/vpn/connect"
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

func makeVPNServiceMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [VPNServiceMockURLProtocol.self]
    return URLSession(configuration: config)
}

/// A second, independent mock protocol dedicated to the AuthService instance injected into
/// VPNService tests — connect() drives real traffic through both AuthService (/auth/me) and
/// VPNService (/vpn/connect, /vpn/disconnect) in the same call, and those two need different
/// response shapes decoded at the same time, so they can't share one mock's fixed response.
class VPNServiceAuthMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var mockData: Data?
    nonisolated(unsafe) static var mockResponse: URLResponse?
    nonisolated(unsafe) static var mockError: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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
    }

    static func configure(
        data: Data? = nil,
        statusCode: Int = 200,
        url: String = "https://api.example.com/api/auth/me"
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

func makeVPNServiceAuthMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [VPNServiceAuthMockURLProtocol.self]
    return URLSession(configuration: config)
}
