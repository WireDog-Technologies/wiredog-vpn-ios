import Foundation

/// A pick-a-reason answer on the paywall exit sheet or the account-deletion flow. The `key` is
/// what the backend counts (it only accepts these exact values); the label is what people read.
struct ExitReason: Identifiable, Equatable {
    let key: String
    let label: String

    var id: String { key }

    /// The only reason that carries typed text.
    static let otherKey = "other"
    static let tooExpensiveKey = "too_expensive"
    static let notReadyKey = "not_ready"

    static let paywall: [ExitReason] = [
        ExitReason(key: "too_expensive", label: "Too expensive"),
        ExitReason(key: "server_locations", label: "Server locations"),
        ExitReason(key: "missing_feature", label: "Missing a feature I want"),
        ExitReason(key: "not_ready", label: "Not ready yet / Need more time"),
        ExitReason(key: "other", label: "Other"),
    ]

    static let deletion: [ExitReason] = [
        ExitReason(key: "too_expensive", label: "Too expensive"),
        ExitReason(key: "server_locations", label: "Server locations"),
        ExitReason(key: "missing_feature", label: "Missing a feature I want"),
        ExitReason(key: "switching_vpn", label: "Switching to another VPN"),
        ExitReason(key: "no_longer_needed", label: "Don't need a VPN anymore"),
        ExitReason(key: "privacy_concerns", label: "Privacy concerns"),
        ExitReason(key: "other", label: "Other"),
    ]
}
