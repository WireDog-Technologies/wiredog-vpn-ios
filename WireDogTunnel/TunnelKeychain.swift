import Foundation
import Security

/// Reads the auth token the main app stored via KeychainService.swift. Deliberately mirrors that
/// implementation's exact query (same service/account, no explicit kSecAttrAccessGroup) rather than
/// sharing the file across targets — both targets are entitled to exactly one keychain access group
/// ($(AppIdentifierPrefix)com.wiredog.vpn), so Keychain Services falls back to it as the implicit
/// default for both processes without either side needing to name it explicitly.
enum TunnelKeychain {
    private static let serviceIdentifier = TunnelConfig.appGroupIdentifier.replacingOccurrences(of: "group.", with: "")
    private static let tokenKey = "authToken"

    static func getAuthToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }
}
