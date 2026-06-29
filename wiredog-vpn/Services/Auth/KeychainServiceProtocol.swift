import Foundation

protocol KeychainServiceProtocol {
    func saveAuthToken(_ token: String) -> Bool
    func getAuthToken() -> String?
    @discardableResult func deleteAuthToken() -> Bool
    var hasAuthToken: Bool { get }
}

extension KeychainService: KeychainServiceProtocol {}
