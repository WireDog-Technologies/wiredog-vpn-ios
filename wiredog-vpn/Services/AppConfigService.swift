import Foundation

@MainActor
class AppConfigService: ObservableObject {
    static let shared = AppConfigService()

    @Published var updateAction: UpdateAction = .none
    @Published var isChecking = true

    private let cacheKey = "appConfigCache"
    private let cacheTimestampKey = "appConfigCacheTimestamp"
    private let cacheTTL: TimeInterval = 24 * 60 * 60 // 24 hours

    private init() {}

    // MARK: - Public

    func checkAppConfig() async {
        isChecking = true
        defer { isChecking = false }

        LogService.shared.logApp("[AppConfig] Checking app configuration...")
        let (config, isCacheFresh) = await fetchConfigWithCache()
        guard let config = config else {
            // No config available, allow app to proceed
            LogService.shared.logApp("[AppConfig] No config available, allowing app to proceed", level: .warning)
            updateAction = .none
            return
        }

        updateAction = evaluate(config: config)
        LogService.shared.logApp("[AppConfig] Config evaluated: \(updateAction) (cache fresh: \(isCacheFresh))")
    }

    // MARK: - Fetch with Cache

    private func fetchConfigWithCache() async -> (AppConfigResponse?, isCacheFresh: Bool) {
        // Try network first
        do {
            let config: AppConfigResponse = try await APIClient.shared.request(endpoint: .appConfig)
            saveToCache(config)
            return (config, true)
        } catch {
            // Network failed, try cache
            LogService.shared.logApp("[AppConfig] API fetch failed: \(error.localizedDescription)", level: .warning)
            let cached = loadFromCache()
            if cached != nil {
                LogService.shared.logApp("[AppConfig] Using cached config", level: .info)
            } else {
                LogService.shared.logApp("[AppConfig] No cached config available", level: .warning)
            }
            let isFresh = cached != nil
            return (cached, isFresh)
        }
    }

    // MARK: - Evaluation

    private func evaluate(config: AppConfigResponse) -> UpdateAction {
        if config.maintenanceMode {
            LogService.shared.logApp("[AppConfig] Maintenance mode ENABLED", level: .info)
            return .maintenance
        }

        guard let iosConfig = config.platforms.ios else {
            LogService.shared.logApp("[AppConfig] No iOS platform config found", level: .warning)
            return .none
        }

        // Check platform-level maintenance mode
        if iosConfig.maintenanceMode {
            LogService.shared.logApp("[AppConfig] iOS maintenance mode ENABLED", level: .info)
            return .maintenance
        }

        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let currentVersionInt = parseVersionToInt(currentVersion)

        if iosConfig.forceUpdate {
            let message = iosConfig.updateMessage ?? "A new version is available. Please update to continue."
            LogService.shared.logApp("[AppConfig] Force update enabled by API", level: .info)
            return .forceUpdate(message: message)
        }

        if currentVersionInt < iosConfig.minSupportedVersion {
            let message = iosConfig.updateMessage ?? "A new version is available. Please update to continue."
            LogService.shared.logApp("[AppConfig] Current version \(currentVersion) (\(currentVersionInt)) < minSupportedVersion \(iosConfig.minSupportedVersion) — force update required", level: .info)
            return .forceUpdate(message: message)
        }

        if currentVersionInt < iosConfig.latestVersion {
            LogService.shared.logApp("[AppConfig] Soft update available: current \(currentVersion) (\(currentVersionInt)) < latest \(iosConfig.latestVersion) — no notification shown", level: .debug)
            // Soft updates don't trigger notifications, app continues normally
            return .none
        }

        LogService.shared.logApp("[AppConfig] All checks passed: version \(currentVersion) (\(currentVersionInt)), maintenance disabled", level: .debug)
        return .none
    }

    // MARK: - Version Parsing

    private func parseVersionToInt(_ version: String) -> Int {
        // Parse "X.Y.Z" format, take major version (X) as integer
        let components = version.split(separator: ".").compactMap { Int($0) }
        return components.first ?? 1
    }


    // MARK: - Cache

    private func saveToCache(_ config: AppConfigResponse) {
        if let data = try? JSONEncoder().encode(CachedConfig(config: config)) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
        }
    }

    private func loadFromCache() -> AppConfigResponse? {
        let timestamp = UserDefaults.standard.double(forKey: cacheTimestampKey)
        guard timestamp > 0 else { return nil }

        let age = Date().timeIntervalSince1970 - timestamp
        guard age < cacheTTL else { return nil }

        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(CachedConfig.self, from: data) else {
            return nil
        }
        return cached.config
    }
}

// MARK: - Cache Model

private struct CachedConfig: Codable {
    let config: AppConfigResponse
}

