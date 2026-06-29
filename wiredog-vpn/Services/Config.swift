import Foundation

enum Config {
    // API Configuration (from xcconfig WIREDOG_API_BASE_URL → Info.plist WireDogAPIBaseURL)
    // Falls back to placeholder if not configured (indicates missing Config.xcconfig)
    static let apiBaseURL: URL = {
        let urlString = Bundle.main.infoDictionary?["WireDogAPIBaseURL"] as? String ?? "https://api.example.com/api"
        return URL(string: urlString) ?? URL(string: "https://api.example.com/api")!
    }()

    // App Group Identifier (from xcconfig WIREDOG_APP_GROUP_ID → Info.plist WireDogAppGroupID)
    // Falls back to placeholder if not configured (indicates missing Config.xcconfig)
    static let appGroupIdentifier: String = {
        Bundle.main.infoDictionary?["WireDogAppGroupID"] as? String ?? "group.com.example.vpn"
    }()

    // Tunnel Bundle Identifier (from xcconfig WIREDOG_TUNNEL_BUNDLE_ID → Info.plist WireDogTunnelBundleID)
    // Falls back to placeholder if not configured (indicates missing Config.xcconfig)
    static let tunnelBundleIdentifier: String = {
        Bundle.main.infoDictionary?["WireDogTunnelBundleID"] as? String ?? "com.example.vpn.tunnel"
    }()

    // Web URLs (from xcconfig WIREDOG_URL_* → Info.plist WireDogURL*)
    static let dashboardURL: URL = URL(string: Bundle.main.infoDictionary?["WireDogURLDashboard"] as? String ?? "https://www.example.com/dashboard")!

    static let privacyPolicyURL: URL = URL(string: Bundle.main.infoDictionary?["WireDogURLPrivacy"] as? String ?? "https://www.example.com/legal/privacy")!

    static let termsOfServiceURL: URL = URL(string: Bundle.main.infoDictionary?["WireDogURLTerms"] as? String ?? "https://www.example.com/legal/terms")!

    static let getStartedURL: URL = URL(string: Bundle.main.infoDictionary?["WireDogURLGetStarted"] as? String ?? "https://www.example.com/get-started")!

    static let appStoreURL: URL = URL(string: Bundle.main.infoDictionary?["WireDogAppStoreURL"] as? String ?? "https://apps.apple.com/app/example/id0")!

    static let pricingURL: URL = URL(string: "https://www.wiredogvpn.com/#pricing")!

    static let supportURL: URL = URL(string: "https://www.wiredogvpn.com/help")!
    static let supportEmail: String = "support@wiredogvpn.com"

    // Timeouts
    static let apiRequestTimeout: TimeInterval = 30
    static let apiResourceTimeout: TimeInterval = 60
    static let vpnConnectionTimeout: TimeInterval = 30

    // Statistics polling interval
    static let statisticsPollingInterval: TimeInterval = 2.0
}
