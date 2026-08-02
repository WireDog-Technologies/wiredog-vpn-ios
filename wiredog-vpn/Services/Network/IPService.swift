import Foundation

class IPService {
    static let shared = IPService()

    private let ipifyURL = URL(string: "https://api.ipify.org?format=json")!
    private let geoURL = URL(string: "https://ipapi.co/json/")!
    private let session: URLSession

    // Cache geo result for 30 minutes to avoid repeated calls to ipapi.co
    private var geoCachedResult: String?
    private var geoCachedAt: Date?
    private let geoCacheTTL: TimeInterval = 30 * 60

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    struct IPResponse: Decodable {
        let ip: String
    }

    private struct GeoResponse: Decodable {
        let city: String?
        let regionCode: String?
        let country: String?

        enum CodingKeys: String, CodingKey {
            case city
            case regionCode = "region_code"
            case country
        }
    }

    /// Fetches the current public IP address
    func getPublicIP() async throws -> String {
        let (data, _) = try await session.data(from: ipifyURL)
        let response = try JSONDecoder().decode(IPResponse.self, from: data)
        return response.ip
    }

    /// Fetches the current public IP address, returning nil on failure
    func getPublicIPSafe() async -> String? {
        do {
            return try await getPublicIP()
        } catch {
            return nil
        }
    }

    /// Drops any pooled/keep-alive connections. Must be called after the VPN
    /// tunnel connects or disconnects — otherwise `getPublicIPSafe()` can keep
    /// reusing a socket opened over the old network interface and silently
    /// keep returning the pre-change IP instead of the current one.
    func resetConnections() async {
        await withCheckedContinuation { continuation in
            session.reset { continuation.resume() }
        }
    }

    /// Fetches a city-level location string derived from the public IP.
    /// Returns "City, ST" for US IPs and "City, CC" for international IPs.
    /// Result is cached for 30 minutes to avoid repeated calls to ipapi.co.
    func getGeoLocation() async -> String? {
        if let cached = geoCachedResult,
           let fetchedAt = geoCachedAt,
           Date().timeIntervalSince(fetchedAt) < geoCacheTTL {
            return cached
        }

        do {
            let (data, _) = try await session.data(from: geoURL)
            let geo = try JSONDecoder().decode(GeoResponse.self, from: data)
            guard let city = geo.city, !city.isEmpty else { return nil }
            let result: String
            if geo.country == "US", let region = geo.regionCode, !region.isEmpty {
                result = "\(city), \(region)"
            } else if let country = geo.country, !country.isEmpty {
                result = "\(city), \(country)"
            } else {
                result = city
            }
            geoCachedResult = result
            geoCachedAt = Date()
            return result
        } catch {
            return nil
        }
    }

    /// Clears the geo location cache — call this after the VPN connects or disconnects
    /// so the next geo lookup reflects the new IP.
    func clearGeoCache() {
        geoCachedResult = nil
        geoCachedAt = nil
    }
}
