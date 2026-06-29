import Testing
@testable import wiredog_vpn

struct KeychainServiceTests {

    // MARK: - MockKeychainService Validation
    // These tests verify the mock behaves correctly so we can trust it in other test suites.

    @Test func saveAndRetrieveToken() {
        let keychain = MockKeychainService()
        let result = keychain.saveAuthToken("test-token-123")

        #expect(result == true)
        #expect(keychain.getAuthToken() == "test-token-123")
    }

    @Test func hasAuthToken_trueWhenSaved() {
        let keychain = MockKeychainService()
        #expect(keychain.hasAuthToken == false)

        keychain.saveAuthToken("token")
        #expect(keychain.hasAuthToken == true)
    }

    @Test func deleteAuthToken_removesToken() {
        let keychain = MockKeychainService()
        keychain.saveAuthToken("token")
        #expect(keychain.hasAuthToken == true)

        keychain.deleteAuthToken()
        #expect(keychain.hasAuthToken == false)
        #expect(keychain.getAuthToken() == nil)
    }

    @Test func overwriteExistingToken() {
        let keychain = MockKeychainService()
        keychain.saveAuthToken("token-v1")
        keychain.saveAuthToken("token-v2")

        #expect(keychain.getAuthToken() == "token-v2")
        #expect(keychain.saveCallCount == 2)
    }

    @Test func saveFailure_returnsFalse() {
        let keychain = MockKeychainService()
        keychain.shouldFailOnSave = true

        let result = keychain.saveAuthToken("token")
        #expect(result == false)
        #expect(keychain.hasAuthToken == false)
    }

    @Test func deleteCallCount_tracked() {
        let keychain = MockKeychainService()
        keychain.saveAuthToken("token")
        keychain.deleteAuthToken()
        keychain.deleteAuthToken()

        #expect(keychain.deleteCallCount == 2)
    }

    @Test func getAuthToken_returnsNilWhenEmpty() {
        let keychain = MockKeychainService()
        #expect(keychain.getAuthToken() == nil)
    }
}
