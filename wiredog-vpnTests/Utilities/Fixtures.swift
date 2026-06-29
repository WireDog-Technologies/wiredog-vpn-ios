import Foundation
@testable import wiredog_vpn

enum TestFixtures {

    // MARK: - WireGuard Config

    static let defaultAwgParams = AwgParams(
        jc: 4, jmin: 40, jmax: 70,
        s1: 0, s2: 0,
        h1: 1, h2: 2, h3: 3, h4: 4
    )

    static func wireGuardConfig(
        privateKey: String = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        address: String = "10.0.0.1/32",
        dns: String = "8.8.8.8",
        publicKey: String = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",
        endpoint: String = "192.0.2.1:51820",
        allowedIPs: String = "0.0.0.0/0,::/0",
        persistentKeepalive: Int = 25,
        awg: AwgParams = defaultAwgParams
    ) -> WireGuardConfigResponse {
        WireGuardConfigResponse(
            privateKey: privateKey,
            address: address,
            dns: dns,
            peer: PeerConfig(
                publicKey: publicKey,
                endpoint: endpoint,
                allowedIPs: allowedIPs,
                persistentKeepalive: persistentKeepalive
            ),
            awg: awg
        )
    }

    // MARK: - Login Response JSON

    static func loginResponseJSON(
        token: String = "test-token-abc123",
        displayName: String? = "Test User",
        accountType: String = "standard"
    ) -> Data {
        var fields = [
            "\"token\": \"\(token)\"",
            "\"accountType\": \"\(accountType)\""
        ]
        if let name = displayName {
            fields.insert("\"displayName\": \"\(name)\"", at: 1)
        }
        return "{\(fields.joined(separator: ", "))}".data(using: .utf8)!
    }

    // MARK: - User Profile JSON

    static let fullUserProfileJSON = """
    {
      "id": 123,
      "username": "testuser",
      "accountNumber": "ABC123DEF456",
      "accountType": "standard",
      "displayName": "Test User",
      "isActive": true,
      "planTier": "premium",
      "billingPeriod": "monthly",
      "subscriptionExpiresAt": "2026-05-06T10:30:00.123Z",
      "subscriptionStartedAt": "2026-04-06T10:30:00Z"
    }
    """.data(using: .utf8)!

    static let minimalUserProfileJSON = """
    {
      "id": 456,
      "accountType": "anonymous"
    }
    """.data(using: .utf8)!

    // MARK: - Servers JSON

    static let serverListJSON = """
    [
      {
        "id": "us-east-1",
        "state": "New York",
        "stateCode": "NY",
        "city": "New York City",
        "latitude": 40.7128,
        "longitude": -74.0060,
        "isRecommended": true,
        "latency": 25,
        "load": 42
      },
      {
        "id": "us-west-1",
        "state": "California",
        "stateCode": "CA",
        "city": "Los Angeles",
        "latitude": 34.0522,
        "longitude": -118.2437,
        "isRecommended": false,
        "load": 78
      }
    ]
    """.data(using: .utf8)!
}
