import Foundation

class SettingsStorage {
    private static let settingsKey = "vpnSettings"

    static func loadSettings() -> VPNSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey) else {
            return VPNSettings()
        }

        if let settings = try? JSONDecoder().decode(VPNSettings.self, from: data) {
            return settings
        }
        return VPNSettings()
    }

    static func saveSettings(_ settings: VPNSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
}
