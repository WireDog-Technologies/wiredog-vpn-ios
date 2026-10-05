import Foundation

/// Pre-payment funnel milestones, each reported at most once per account. The backend turns
/// them into bare daily counters (no account id is stored) and ignores paid, organization
/// and test accounts, so this only answers "what share of new accounts got this far".
enum Milestone: String, CaseIterable {
    case connectAttempted = "connect_attempted"
    /// Sent alongside the first of any paywall action below, so "saw the paywall and left"
    /// can be counted without per-account data (1 − engaged / connectAttempted).
    case paywallEngaged = "paywall_engaged"
    case paywallCheckoutTapped = "paywall_checkout_tapped"
    case paywallBetterPlansTapped = "paywall_better_plans_tapped"
    case paywallAppStoreOpened = "paywall_app_store_opened"
    case iapAllPlansTapped = "iap_all_plans_tapped"
    case iapPurchaseStarted = "iap_purchase_started"

    var isPaywallAction: Bool {
        switch self {
        case .connectAttempted, .paywallEngaged: return false
        default: return true
        }
    }
}

@MainActor
final class MilestoneService {
    static let shared = MilestoneService()

    private static let sentKeyPrefix = "sent_milestones_"

    private let apiClient: APIClient
    private var inFlight: Set<String> = []

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    /// Fire-and-forget. Marked sent only after the backend accepts it, so a failed send (offline)
    /// is retried the next time the user repeats the action.
    func record(_ milestone: Milestone) {
        #if os(tvOS)
        // The funnel is the iOS signup → paywall path; Apple TV only pairs existing accounts.
        return
        #else
        guard let user = AuthService.shared.currentUser, !user.hasEntitlement else { return }
        send(milestone, accountId: user.id)
        if milestone.isPaywallAction {
            send(.paywallEngaged, accountId: user.id)
        }
        #endif
    }

    private func send(_ milestone: Milestone, accountId: Int) {
        let defaultsKey = Self.sentKeyPrefix + String(accountId)
        var sent = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
        let flightKey = "\(accountId):\(milestone.rawValue)"
        guard !sent.contains(milestone.rawValue), !inFlight.contains(flightKey) else { return }
        inFlight.insert(flightKey)

        Task {
            defer { inFlight.remove(flightKey) }
            do {
                try await apiClient.requestVoid(
                    endpoint: .milestones,
                    body: MilestoneRequest(key: milestone.rawValue)
                )
                sent = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
                sent.insert(milestone.rawValue)
                UserDefaults.standard.set(Array(sent), forKey: defaultsKey)
            } catch {
                LogService.shared.logApp("[Milestone] \(milestone.rawValue) not sent: \(error.localizedDescription)", level: .warning)
            }
        }
    }
}

private struct MilestoneRequest: Encodable {
    let key: String
}
