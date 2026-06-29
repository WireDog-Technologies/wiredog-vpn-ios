import Testing
import Foundation
@testable import wiredog_vpn

struct AuthModelsTests {

    // MARK: - Decoder Helper

    /// Mirrors the exact date decoding strategy used by APIClient
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string: \(dateString)"
            )
        }
        return decoder
    }

    // MARK: - UserProfile Decoding

    @Test func userProfile_allFields() throws {
        let json = """
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

        let profile = try decoder.decode(UserProfile.self, from: json)

        #expect(profile.id == 123)
        #expect(profile.username == "testuser")
        #expect(profile.accountNumber == "ABC123DEF456")
        #expect(profile.accountType == .standard)
        #expect(profile.displayName == "Test User")
        #expect(profile.isActive == true)
        #expect(profile.planTier == .premium)
        #expect(profile.billingPeriod == "monthly")
        #expect(profile.subscriptionExpiresAt != nil)
        #expect(profile.subscriptionStartedAt != nil)
    }

    @Test func userProfile_minimalFields_usesDefaults() throws {
        let json = """
        {
          "id": 456,
          "accountType": "anonymous"
        }
        """.data(using: .utf8)!

        let profile = try decoder.decode(UserProfile.self, from: json)

        #expect(profile.id == 456)
        #expect(profile.accountType == .anonymous)
        #expect(profile.username == nil)
        #expect(profile.accountNumber == nil)
        #expect(profile.displayName == nil)
        #expect(profile.isActive == true)        // default
        #expect(profile.planTier == .free)        // default
        #expect(profile.billingPeriod == nil)
        #expect(profile.subscriptionExpiresAt == nil)
        #expect(profile.subscriptionStartedAt == nil)
    }

    @Test func userProfile_isActiveFalse() throws {
        let json = """
        {
          "id": 1,
          "accountType": "standard",
          "isActive": false
        }
        """.data(using: .utf8)!

        let profile = try decoder.decode(UserProfile.self, from: json)
        #expect(profile.isActive == false)
    }

    @Test func userProfile_missingIsActive_defaultsToTrue() throws {
        let json = """
        {
          "id": 1,
          "accountType": "standard"
        }
        """.data(using: .utf8)!

        let profile = try decoder.decode(UserProfile.self, from: json)
        #expect(profile.isActive == true)
    }

    @Test func userProfile_missingPlanTier_defaultsToFree() throws {
        let json = """
        {
          "id": 1,
          "accountType": "standard"
        }
        """.data(using: .utf8)!

        let profile = try decoder.decode(UserProfile.self, from: json)
        #expect(profile.planTier == .free)
    }

    // MARK: - Date Parsing

    @Test func userProfile_dateWithFractionalSeconds() throws {
        let json = """
        {
          "id": 1,
          "accountType": "standard",
          "subscriptionExpiresAt": "2026-05-06T10:30:00.123Z"
        }
        """.data(using: .utf8)!

        let profile = try decoder.decode(UserProfile.self, from: json)
        #expect(profile.subscriptionExpiresAt != nil)
    }

    @Test func userProfile_dateWithoutFractionalSeconds() throws {
        let json = """
        {
          "id": 1,
          "accountType": "standard",
          "subscriptionStartedAt": "2026-04-06T10:30:00Z"
        }
        """.data(using: .utf8)!

        let profile = try decoder.decode(UserProfile.self, from: json)
        #expect(profile.subscriptionStartedAt != nil)
    }

    @Test func userProfile_bothDateFormats_decodeSameDay() throws {
        let json = """
        {
          "id": 1,
          "accountType": "standard",
          "subscriptionExpiresAt": "2026-05-06T10:30:00.000Z",
          "subscriptionStartedAt": "2026-05-06T10:30:00Z"
        }
        """.data(using: .utf8)!

        let profile = try decoder.decode(UserProfile.self, from: json)
        let calendar = Calendar(identifier: .gregorian)
        let expires = calendar.dateComponents([.year, .month, .day], from: profile.subscriptionExpiresAt!)
        let started = calendar.dateComponents([.year, .month, .day], from: profile.subscriptionStartedAt!)
        #expect(expires == started)
    }

    // MARK: - LoginResponse Decoding

    @Test func loginResponse_allFields() throws {
        let json = """
        {
          "token": "jwt-token-abc123",
          "displayName": "Test User",
          "accountType": "standard"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(LoginResponse.self, from: json)
        #expect(response.token == "jwt-token-abc123")
        #expect(response.displayName == "Test User")
        #expect(response.accountType == .standard)
    }

    @Test func loginResponse_optionalDisplayNameMissing() throws {
        let json = """
        {
          "token": "jwt-token-abc123",
          "accountType": "anonymous"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(LoginResponse.self, from: json)
        #expect(response.token == "jwt-token-abc123")
        #expect(response.displayName == nil)
        #expect(response.accountType == .anonymous)
    }

    // MARK: - Enum Decoding

    @Test func accountType_standard() throws {
        let json = #"{"accountType":"standard"}"#.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode([String: AccountType].self, from: json)
        #expect(wrapper["accountType"] == .standard)
    }

    @Test func accountType_anonymous() throws {
        let json = #"{"accountType":"anonymous"}"#.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode([String: AccountType].self, from: json)
        #expect(wrapper["accountType"] == .anonymous)
    }

    @Test func planTier_allCases() throws {
        let cases: [(String, PlanTier)] = [
            ("free", .free),
            ("paid", .paid),
            ("premium", .premium),
            ("elite", .elite),
            ("patriot", .patriot),
        ]
        for (raw, expected) in cases {
            let json = #"{"planTier":"\#(raw)"}"#.data(using: .utf8)!
            let wrapper = try JSONDecoder().decode([String: PlanTier].self, from: json)
            #expect(wrapper["planTier"] == expected, "Expected \(raw) to decode to \(expected)")
        }
    }

    @Test func planTier_invalidValue_throws() throws {
        let json = #"{"planTier":"invalid"}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode([String: PlanTier].self, from: json)
        }
    }

    @Test func accountType_invalidValue_throws() throws {
        let json = #"{"accountType":"invalid"}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode([String: AccountType].self, from: json)
        }
    }

    // MARK: - Request Encoding

    @Test func standardLoginRequest_encodesCorrectFields() throws {
        let request = StandardLoginRequest(identifier: "user@example.com", password: "pass123")
        let data = try JSONEncoder().encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: String]

        #expect(dict["identifier"] == "user@example.com")
        #expect(dict["password"] == "pass123")
        #expect(dict.count == 2)
    }

    @Test func anonymousLoginRequest_encodesCorrectField() throws {
        let request = AnonymousLoginRequest(identifier: "ABCD1234")
        let data = try JSONEncoder().encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: String]

        #expect(dict["identifier"] == "ABCD1234")
        #expect(dict.count == 1)
    }
}
