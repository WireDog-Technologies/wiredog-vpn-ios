import Foundation

class ServerStorage {
    private static let recentServersKey = "recentServers"
    private static let favoriteServersKey = "favoriteServers"
    private static let maxRecentServers = 5

    // Use App Group for sharing with Network Extension
    private static var userDefaults: UserDefaults {
        UserDefaults(suiteName: Config.appGroupIdentifier) ?? .standard
    }

    static func addRecentServer(_ serverId: String) {
        var recentIds = getRecentServerIds()

        // Remove if already exists (to move it to front)
        recentIds.removeAll { $0 == serverId }

        // Add to front (FIFO)
        recentIds.insert(serverId, at: 0)

        // Keep only last 5
        if recentIds.count > maxRecentServers {
            recentIds = Array(recentIds.prefix(maxRecentServers))
        }

        saveRecentServerIds(recentIds)
    }

    static func getRecentServers(from servers: [Server]) -> [Server] {
        let recentIds = getRecentServerIds()
        return recentIds.compactMap { id in
            servers.first { $0.id == id }
        }
    }

    private static func getRecentServerIds() -> [String] {
        guard let data = userDefaults.data(forKey: recentServersKey) else {
            return []
        }

        if let ids = try? JSONDecoder().decode([String].self, from: data) {
            return ids
        }
        return []
    }

    private static func saveRecentServerIds(_ ids: [String]) {
        if let data = try? JSONEncoder().encode(ids) {
            userDefaults.set(data, forKey: recentServersKey)
        }
    }

    static func toggleFavorite(_ serverId: String) {
        var favorites = getFavoriteIds()

        if favorites.contains(serverId) {
            favorites.removeAll { $0 == serverId }
        } else {
            favorites.append(serverId)
        }

        saveFavoriteIds(favorites)
    }

    static func isFavorite(_ serverId: String) -> Bool {
        return getFavoriteIds().contains(serverId)
    }

    static func getFavoriteServers(from servers: [Server]) -> [Server] {
        let favoriteIds = getFavoriteIds()
        return servers.filter { favoriteIds.contains($0.id) }
    }

    private static func getFavoriteIds() -> [String] {
        guard let data = userDefaults.data(forKey: favoriteServersKey) else {
            return []
        }

        if let ids = try? JSONDecoder().decode([String].self, from: data) {
            return ids
        }
        return []
    }

    private static func saveFavoriteIds(_ ids: [String]) {
        if let data = try? JSONEncoder().encode(ids) {
            userDefaults.set(data, forKey: favoriteServersKey)
        }
    }
}
