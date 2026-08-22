import Foundation

class BroadcastReadStore {
    private static let readIdsKey = "broadcastReadMessageIds"

    static func loadReadIds() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: readIdsKey),
              let ids = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return []
        }
        return ids
    }

    static func save(_ ids: Set<String>) {
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: readIdsKey)
        }
    }
}
