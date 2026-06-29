import Foundation
@testable import wiredog_vpn

// MARK: - MockKeychainService

class MockKeychainService: KeychainServiceProtocol {
    private(set) var storage: [String: String] = [:]
    private(set) var saveCallCount = 0
    private(set) var deleteCallCount = 0
    var shouldFailOnSave = false

    func saveAuthToken(_ token: String) -> Bool {
        saveCallCount += 1
        if shouldFailOnSave { return false }
        storage["token"] = token
        return true
    }

    func getAuthToken() -> String? {
        storage["token"]
    }

    @discardableResult
    func deleteAuthToken() -> Bool {
        deleteCallCount += 1
        storage.removeValue(forKey: "token")
        return true
    }

    var hasAuthToken: Bool {
        storage["token"] != nil
    }
}

// MARK: - MockURLProtocol

class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var mockData: Data?
    nonisolated(unsafe) static var mockResponse: URLResponse?
    nonisolated(unsafe) static var mockError: Error?
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.capturedRequests.append(request)

        if let error = MockURLProtocol.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if let response = MockURLProtocol.mockResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }

        if let data = MockURLProtocol.mockData {
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

// MARK: - Mock URLSession Helper

func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}
