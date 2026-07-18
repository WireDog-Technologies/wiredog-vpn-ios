import Foundation

/// Tracks eligibility for the "Enjoying WireDog VPN?" pre-prompt shown before
/// requesting an App Store review. Only users who tap 👍 ever see the native
/// review sheet; 👎 routes to Report an Issue instead and re-asks later.
final class ReviewPromptService {
    static let shared = ReviewPromptService()

    private static let requiredSuccessfulConnections = 3
    private static let maxLifetimeAsks = 3
    private static let cooldown: TimeInterval = 90 * 24 * 60 * 60 // 90 days

    private static let connectionCountKey = "reviewPromptConnectionCount"
    private static let askCountKey = "reviewPromptAskCount"
    private static let lastShownDateKey = "reviewPromptLastShownDate"
    private static let respondedPositivelyKey = "reviewPromptRespondedPositively"

    private init() {}

    /// Call every time a connection succeeds. Returns true if this is the Nth
    /// successful connection and the pre-prompt should be shown now.
    @discardableResult
    func recordSuccessfulConnection() -> Bool {
        guard !hasRespondedPositively else { return false }
        guard askCount < Self.maxLifetimeAsks else { return false }
        if let last = lastShownDate, Date().timeIntervalSince(last) < Self.cooldown {
            return false
        }

        let count = UserDefaults.standard.integer(forKey: Self.connectionCountKey) + 1
        guard count >= Self.requiredSuccessfulConnections else {
            UserDefaults.standard.set(count, forKey: Self.connectionCountKey)
            return false
        }

        UserDefaults.standard.set(0, forKey: Self.connectionCountKey)
        UserDefaults.standard.set(askCount + 1, forKey: Self.askCountKey)
        UserDefaults.standard.set(Date(), forKey: Self.lastShownDateKey)
        return true
    }

    /// Call when the user taps 👍. Suppresses the pre-prompt permanently.
    func recordPositiveResponse() {
        UserDefaults.standard.set(true, forKey: Self.respondedPositivelyKey)
    }

    private var askCount: Int {
        UserDefaults.standard.integer(forKey: Self.askCountKey)
    }

    private var lastShownDate: Date? {
        UserDefaults.standard.object(forKey: Self.lastShownDateKey) as? Date
    }

    private var hasRespondedPositively: Bool {
        UserDefaults.standard.bool(forKey: Self.respondedPositivelyKey)
    }
}
