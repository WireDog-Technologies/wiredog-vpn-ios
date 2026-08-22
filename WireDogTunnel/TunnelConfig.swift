import Foundation

/// Minimal, extension-local mirror of the app's Config.swift — kept separate (rather than sharing
/// the app's file across targets) to avoid pulling the main app's dependency surface into the
/// tunnel extension, which runs under a much tighter memory budget than the host app.
enum TunnelConfig {
    static let apiBaseURL: URL = {
        let urlString = Bundle.main.infoDictionary?["WireDogAPIBaseURL"] as? String ?? "https://api.example.com/api"
        return URL(string: urlString) ?? URL(string: "https://api.example.com/api")!
    }()

    static let appGroupIdentifier: String = {
        Bundle.main.infoDictionary?["WireDogAppGroupID"] as? String ?? "group.com.example.vpn"
    }()

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}
